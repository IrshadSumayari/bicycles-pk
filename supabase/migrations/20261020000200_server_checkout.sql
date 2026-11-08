-- =====================================================================
-- Server-side checkout: quote_sale() and post_sale()
--
--   * Prices, promotions, manual-discount limits, tax and gifts are worked
--     out in the database. The browser sends only what is being bought,
--     requested manual discounts and how the customer pays.
--   * Sale lines and payments are stored with snapshots (name, price, cost,
--     discount, tax) so later price or cost changes never rewrite history.
--   * Split payments; payments must add up to the total.
--   * Stock moves through the ledger, gifts included.
--   * Retries with the same request_id return the original sale.
--   * Completed sales can no longer be edited or deleted; only drafts can.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------
-- Tax is a percentage (17 = 17%). The old DECIMAL(5,4) could not hold 17.
ALTER TABLE public.app_settings ALTER COLUMN tax_rate TYPE NUMERIC(6,3);
ALTER TABLE public.app_settings ALTER COLUMN tax_rate SET DEFAULT 0;
ALTER TABLE public.app_settings
    ADD COLUMN IF NOT EXISTS max_cashier_discount_percent NUMERIC(5,2) NOT NULL DEFAULT 10
        CHECK (max_cashier_discount_percent BETWEEN 0 AND 100);

-- ---------------------------------------------------------------------
-- Sales: header columns, lines, payments
-- ---------------------------------------------------------------------
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id);
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS location_id UUID REFERENCES public.locations(id);
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS channel TEXT NOT NULL DEFAULT 'pos' CHECK (channel IN ('pos', 'web'));
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS request_id UUID UNIQUE;
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS change_due NUMERIC(14,2) NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_sales_branch_time ON public.sales(branch_id, created_at);

UPDATE public.sales SET branch_id = public.default_branch_id() WHERE branch_id IS NULL;

CREATE TABLE IF NOT EXISTS public.sale_lines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id UUID NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    line_no INTEGER NOT NULL,
    variant_id UUID REFERENCES public.product_variants(id),
    description TEXT NOT NULL,
    sku TEXT,
    unit TEXT NOT NULL,
    quantity NUMERIC(18,6) NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(14,2) NOT NULL CHECK (unit_price >= 0),
    gross NUMERIC(14,2) NOT NULL,
    manual_discount NUMERIC(14,2) NOT NULL DEFAULT 0,
    promotion_discount NUMERIC(14,2) NOT NULL DEFAULT 0,
    net NUMERIC(14,2) NOT NULL,
    taxable BOOLEAN NOT NULL,
    tax NUMERIC(14,2) NOT NULL DEFAULT 0,
    total NUMERIC(14,2) NOT NULL,
    unit_cost NUMERIC(14,4),
    is_gift BOOLEAN NOT NULL DEFAULT false,
    promotion_id UUID,
    UNIQUE (sale_id, line_no)
);
CREATE INDEX IF NOT EXISTS idx_sale_lines_variant ON public.sale_lines(variant_id);

CREATE TABLE IF NOT EXISTS public.payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id UUID REFERENCES public.sales(id) ON DELETE CASCADE,
    method TEXT NOT NULL CHECK (method IN ('cash', 'card', 'digital', 'credit')),
    amount NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    tendered NUMERIC(14,2),
    change_given NUMERIC(14,2) NOT NULL DEFAULT 0,
    reference TEXT,
    card_type TEXT,
    card_last4 TEXT CHECK (card_last4 IS NULL OR card_last4 ~ '^\d{4}$'),
    bank_name TEXT,
    holder_name TEXT,
    created_by UUID DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_payments_sale ON public.payments(sale_id);

ALTER TABLE public.sale_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

-- Lines and payments are visible to whoever can see the sale
DROP POLICY IF EXISTS "sale_lines_select" ON public.sale_lines;
CREATE POLICY "sale_lines_select" ON public.sale_lines
    FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.sales s WHERE s.id = sale_id));
DROP POLICY IF EXISTS "payments_select" ON public.payments;
CREATE POLICY "payments_select" ON public.payments
    FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.sales s WHERE s.id = sale_id));

-- Posted lines and payments are history
DROP TRIGGER IF EXISTS trigger_sale_lines_append_only ON public.sale_lines;
CREATE TRIGGER trigger_sale_lines_append_only
    BEFORE UPDATE ON public.sale_lines
    FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();
DROP TRIGGER IF EXISTS trigger_payments_append_only ON public.payments;
CREATE TRIGGER trigger_payments_append_only
    BEFORE UPDATE OR DELETE ON public.payments
    FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();

-- Completed sales are final: only drafts may be edited or deleted
DROP POLICY IF EXISTS "sales_update_back_office" ON public.sales;
DROP POLICY IF EXISTS "sales_delete_back_office" ON public.sales;
DROP POLICY IF EXISTS "sales_update_drafts" ON public.sales;
DROP POLICY IF EXISTS "sales_delete_drafts" ON public.sales;
CREATE POLICY "sales_update_drafts" ON public.sales
    FOR UPDATE TO authenticated
    USING (status = 'draft' AND (public.has_app_role(ARRAY['admin', 'manager']) OR cashier_id = auth.uid()))
    WITH CHECK (status = 'draft');
CREATE POLICY "sales_delete_drafts" ON public.sales
    FOR DELETE TO authenticated
    USING (status = 'draft' AND (public.has_app_role(ARRAY['admin', 'manager']) OR cashier_id = auth.uid()));

-- ---------------------------------------------------------------------
-- Promotions (legacy `discounts` table) evaluated on the server
-- ---------------------------------------------------------------------
-- A promotion condition may name either a variant id or a legacy product id
CREATE OR REPLACE FUNCTION public.promotion_item_matches(p_ref TEXT, p_variant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT p_ref = p_variant_id::text
        OR EXISTS (SELECT 1 FROM public.product_variants v
                   WHERE v.id = p_variant_id AND v.legacy_product_id::text = p_ref)
$$;

-- ---------------------------------------------------------------------
-- quote_sale: price a basket without saving anything
--
-- Input:
-- {
--   "location_id": uuid (optional, default: shop floor of the default branch),
--   "customer_id": uuid (optional),
--   "lines": [{ "variant_id": uuid, "quantity": number,
--               "discount_type": "percentage" | "fixed", "discount_value": number }],
--   "payments": [{ "method": "cash"|"card"|"digital"|"credit", "card_type": .., "bank_name": .. }]
-- }
-- Payments are used only for promotion conditions (payment method, card, bank).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.quote_sale(p_request JSONB)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role TEXT := public.current_app_role();
    v_settings public.app_settings;
    v_location public.locations;
    v_customer public.customers;
    v_req JSONB;
    v_variant RECORD;
    v_lines JSONB := '[]'::jsonb;
    v_gifts JSONB := '[]'::jsonb;
    v_promos JSONB := '[]'::jsonb;
    v_qty NUMERIC;
    v_gross NUMERIC;
    v_manual NUMERIC;
    v_dtype TEXT;
    v_dvalue NUMERIC;
    v_max_pct NUMERIC;
    v_subtotal NUMERIC := 0;
    v_manual_total NUMERIC := 0;
    v_net_before_promo NUMERIC;
    v_promo_total NUMERIC := 0;
    v_promo RECORD;
    v_cond JSONB;
    v_eligible BOOLEAN;
    v_amount NUMERIC;
    v_gift_ref TEXT;
    v_gift RECORD;
    v_line JSONB;
    v_i INTEGER;
    v_n INTEGER;
    v_alloc NUMERIC;
    v_alloc_left NUMERIC;
    v_net NUMERIC;
    v_tax NUMERIC;
    v_tax_total NUMERIC := 0;
    v_result_lines JSONB := '[]'::jsonb;
    v_now_local TIMESTAMP;
BEGIN
    IF v_role IS NULL OR v_role NOT IN ('admin', 'manager', 'cashier') THEN
        RAISE EXCEPTION 'Not authorized to sell' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_settings FROM public.app_settings ORDER BY created_at LIMIT 1;

    IF p_request ? 'location_id' AND NULLIF(p_request->>'location_id', '') IS NOT NULL THEN
        SELECT * INTO v_location FROM public.locations WHERE id = (p_request->>'location_id')::uuid AND active;
    ELSE
        SELECT * INTO v_location FROM public.locations
        WHERE branch_id = public.default_branch_id() AND kind = 'shop_floor' AND active
        ORDER BY created_at LIMIT 1;
    END IF;
    IF v_location.id IS NULL THEN
        RAISE EXCEPTION 'Selling location not found';
    END IF;
    IF NOT public.is_branch_member(v_location.branch_id) THEN
        RAISE EXCEPTION 'Not a member of this branch' USING ERRCODE = '42501';
    END IF;

    IF NULLIF(p_request->>'customer_id', '') IS NOT NULL THEN
        SELECT * INTO v_customer FROM public.customers WHERE id = (p_request->>'customer_id')::uuid;
        IF v_customer.id IS NULL THEN
            RAISE EXCEPTION 'Customer not found';
        END IF;
    END IF;

    IF jsonb_typeof(p_request->'lines') <> 'array' OR jsonb_array_length(p_request->'lines') = 0 THEN
        RAISE EXCEPTION 'A sale needs at least one item';
    END IF;

    v_max_pct := CASE WHEN v_role IN ('admin', 'manager') THEN 100 ELSE v_settings.max_cashier_discount_percent END;

    -- 1. Lines at database prices, with manual discounts within the role limit
    FOR v_req IN SELECT * FROM jsonb_array_elements(p_request->'lines')
    LOOP
        SELECT v.id, v.sku, v.price, v.active AS v_active, s.name, s.unit, s.taxable, s.track_inventory,
               s.active AS s_active, s.kind,
               trim(s.name || COALESCE(' ' || v.size, '') || COALESCE(' ' || v.color, '') || COALESCE(' ' || v.fit, '')) AS description,
               c.unit_cost
        INTO v_variant
        FROM public.product_variants v
        JOIN public.product_styles s ON s.id = v.style_id
        LEFT JOIN public.variant_costs c ON c.variant_id = v.id
        WHERE v.id = NULLIF(v_req->>'variant_id', '')::uuid;

        IF v_variant.id IS NULL THEN
            RAISE EXCEPTION 'Item not found: %', v_req->>'variant_id';
        END IF;
        IF NOT (v_variant.v_active AND v_variant.s_active) THEN
            RAISE EXCEPTION '"%" is no longer for sale', v_variant.description;
        END IF;

        v_qty := COALESCE((v_req->>'quantity')::numeric, 0);
        IF v_qty <= 0 THEN
            RAISE EXCEPTION 'Quantity for "%" must be greater than zero', v_variant.description;
        END IF;
        IF v_variant.unit = 'meter' THEN
            IF v_qty <> round(v_qty, 2) THEN
                RAISE EXCEPTION 'Fabric length for "%" can have at most 2 decimals', v_variant.description;
            END IF;
        ELSIF v_qty <> trunc(v_qty) THEN
            RAISE EXCEPTION 'Whole quantities only for "%"', v_variant.description;
        END IF;

        v_gross := round(v_variant.price * v_qty, 2);
        v_dtype := COALESCE(v_req->>'discount_type', 'fixed');
        v_dvalue := COALESCE((v_req->>'discount_value')::numeric, 0);
        IF v_dvalue < 0 THEN
            RAISE EXCEPTION 'Discount cannot be negative';
        END IF;
        v_manual := CASE WHEN v_dtype = 'percentage' THEN round(v_gross * v_dvalue / 100, 2) ELSE round(v_dvalue, 2) END;
        v_manual := LEAST(v_manual, v_gross);
        IF v_gross > 0 AND v_manual > round(v_gross * v_max_pct / 100, 2) THEN
            RAISE EXCEPTION 'Discount on "%" is above your limit of % percent', v_variant.description, trim_scale(v_max_pct)
                USING ERRCODE = '42501';
        END IF;

        v_subtotal := v_subtotal + v_gross;
        v_manual_total := v_manual_total + v_manual;

        v_lines := v_lines || jsonb_build_object(
            'variant_id', v_variant.id,
            'description', v_variant.description,
            'sku', v_variant.sku,
            'unit', v_variant.unit,
            'quantity', v_qty,
            'unit_price', v_variant.price,
            'gross', v_gross,
            'manual_discount', v_manual,
            'taxable', v_variant.taxable,
            'track_inventory', v_variant.track_inventory,
            'unit_cost', v_variant.unit_cost,
            'is_gift', false
        );
    END LOOP;

    v_net_before_promo := v_subtotal - v_manual_total;
    v_now_local := now() AT TIME ZONE COALESCE(
        (SELECT timezone FROM public.branches WHERE id = v_location.branch_id), 'Asia/Karachi');

    -- 2. Promotions
    FOR v_promo IN
        SELECT * FROM public.discounts
        WHERE active AND now() BETWEEN valid_from AND valid_to
          AND (valid_days IS NULL OR cardinality(valid_days) = 0 OR EXTRACT(DOW FROM v_now_local)::int = ANY(valid_days))
        ORDER BY created_at, id
    LOOP
        v_eligible := v_promo.min_amount IS NULL OR v_net_before_promo >= v_promo.min_amount;

        FOR v_cond IN SELECT * FROM jsonb_array_elements(COALESCE(v_promo.conditions, '[]'::jsonb))
        LOOP
            EXIT WHEN NOT v_eligible;
            CASE v_cond->>'type'
                WHEN 'min_amount' THEN
                    v_eligible := v_net_before_promo >= COALESCE((v_cond->>'value')::numeric, 0);
                WHEN 'specific_products' THEN
                    v_eligible := jsonb_typeof(v_cond->'value') = 'array' AND NOT EXISTS (
                        SELECT 1 FROM jsonb_array_elements_text(v_cond->'value') ref
                        WHERE COALESCE((
                            SELECT SUM((l->>'quantity')::numeric) FROM jsonb_array_elements(v_lines) l
                            WHERE public.promotion_item_matches(ref, (l->>'variant_id')::uuid)
                        ), 0) < COALESCE((v_cond->>'minQuantity')::numeric, 1)
                    );
                WHEN 'payment_method' THEN
                    v_eligible := EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(p_request->'payments', '[]')) pm
                                          WHERE pm->>'method' = v_cond->>'value');
                WHEN 'customer_tier' THEN
                    v_eligible := v_customer.id IS NOT NULL AND v_customer.price_tier = v_cond->>'value';
                WHEN 'card_type' THEN
                    v_eligible := EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(p_request->'payments', '[]')) pm
                                          WHERE pm->>'method' = 'card' AND pm->>'card_type' = v_cond->>'value');
                WHEN 'bank_name' THEN
                    v_eligible := EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(p_request->'payments', '[]')) pm
                                          WHERE pm->>'method' = 'card' AND pm->>'bank_name' = v_cond->>'value');
                ELSE
                    v_eligible := false;  -- unknown condition: never apply
            END CASE;
        END LOOP;

        CONTINUE WHEN NOT v_eligible;

        IF v_promo.type = 'free_gift' THEN
            FOREACH v_gift_ref IN ARRAY COALESCE(v_promo.free_gift_products, ARRAY[]::text[])
            LOOP
                SELECT v.id, v.sku, s.name, s.unit, s.track_inventory, c.unit_cost,
                       trim(s.name || COALESCE(' ' || v.size, '') || COALESCE(' ' || v.color, '')) AS description,
                       COALESCE((SELECT on_hand - reserved FROM public.stock_balances b
                                 WHERE b.variant_id = v.id AND b.location_id = v_location.id), 0) AS available
                INTO v_gift
                FROM public.product_variants v
                JOIN public.product_styles s ON s.id = v.style_id
                LEFT JOIN public.variant_costs c ON c.variant_id = v.id
                WHERE (v.id::text = v_gift_ref OR v.legacy_product_id::text = v_gift_ref) AND v.active AND s.active
                LIMIT 1;

                -- A gift that is out of stock is skipped rather than blocking the sale
                IF v_gift.id IS NOT NULL AND (NOT v_gift.track_inventory OR v_gift.available >= 1) THEN
                    v_gifts := v_gifts || jsonb_build_object(
                        'variant_id', v_gift.id, 'description', v_gift.description || ' (gift)', 'sku', v_gift.sku,
                        'unit', v_gift.unit, 'quantity', 1, 'unit_price', 0, 'gross', 0, 'manual_discount', 0,
                        'taxable', false, 'track_inventory', v_gift.track_inventory, 'unit_cost', v_gift.unit_cost,
                        'is_gift', true, 'promotion_id', v_promo.id
                    );
                END IF;
            END LOOP;
            v_promos := v_promos || jsonb_build_object('discountId', v_promo.id, 'discountName', v_promo.name,
                                                       'discountAmount', 0, 'type', 'free_gift');
        ELSE
            v_amount := CASE v_promo.type
                WHEN 'percentage' THEN round(v_net_before_promo * v_promo.value / 100, 2)
                WHEN 'fixed' THEN round(v_promo.value, 2)
                ELSE 0 END;
            IF v_promo.max_discount IS NOT NULL THEN
                v_amount := LEAST(v_amount, v_promo.max_discount);
            END IF;
            v_amount := LEAST(v_amount, v_net_before_promo - v_promo_total);
            IF v_amount > 0 THEN
                v_promo_total := v_promo_total + v_amount;
                v_promos := v_promos || jsonb_build_object('discountId', v_promo.id, 'discountName', v_promo.name,
                                                           'discountAmount', v_amount, 'type', v_promo.type);
            END IF;
        END IF;
    END LOOP;

    -- 3. Spread promotion discounts over lines by net value, then tax per line
    v_n := jsonb_array_length(v_lines);
    v_alloc_left := v_promo_total;
    FOR v_i IN 0 .. v_n - 1
    LOOP
        v_line := v_lines->v_i;
        v_net := (v_line->>'gross')::numeric - (v_line->>'manual_discount')::numeric;
        IF v_i = v_n - 1 THEN
            v_alloc := v_alloc_left;
        ELSIF v_net_before_promo > 0 THEN
            v_alloc := round(v_promo_total * v_net / v_net_before_promo, 2);
        ELSE
            v_alloc := 0;
        END IF;
        v_alloc := LEAST(v_alloc, v_net);
        v_alloc_left := v_alloc_left - v_alloc;
        v_net := v_net - v_alloc;

        v_tax := CASE WHEN (v_line->>'taxable')::boolean
                      THEN round(v_net * COALESCE(v_settings.tax_rate, 0) / 100, 2) ELSE 0 END;
        v_tax_total := v_tax_total + v_tax;

        v_result_lines := v_result_lines || (v_line || jsonb_build_object(
            'promotion_discount', v_alloc, 'net', v_net, 'tax', v_tax, 'total', v_net + v_tax));
    END LOOP;

    FOR v_line IN SELECT * FROM jsonb_array_elements(v_gifts)
    LOOP
        v_result_lines := v_result_lines || (v_line || jsonb_build_object(
            'promotion_discount', 0, 'net', 0, 'tax', 0, 'total', 0));
    END LOOP;

    RETURN jsonb_build_object(
        'branch_id', v_location.branch_id,
        'location_id', v_location.id,
        'customer_id', v_customer.id,
        'customer_name', v_customer.name,
        'lines', v_result_lines,
        'applied_discounts', v_promos,
        'subtotal', v_subtotal,
        'manual_discount', v_manual_total,
        'promotion_discount', v_promo_total,
        'discount_amount', v_manual_total + v_promo_total,
        'tax_rate', COALESCE(v_settings.tax_rate, 0),
        'tax_amount', v_tax_total,
        'total', v_subtotal - v_manual_total - v_promo_total + v_tax_total
    );
END;
$$;

-- ---------------------------------------------------------------------
-- post_sale: price, take payment, move stock and save, in one transaction
--
-- Input: quote_sale input plus
--   "request_id": uuid (required),
--   "status": "completed" (default) or "draft",
--   "notes": text,
--   "payments": [{ "method", "amount" (optional when there is one payment),
--                  "tendered" (cash), "reference", "card_type", "card_last4",
--                  "bank_name", "holder_name" }]
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.post_sale(p_request JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_request_id UUID := NULLIF(p_request->>'request_id', '')::uuid;
    v_existing JSONB;
    v_quote JSONB;
    v_status TEXT := COALESCE(NULLIF(p_request->>'status', ''), 'completed');
    v_profile public.users;
    v_total NUMERIC;
    v_payments JSONB := COALESCE(p_request->'payments', '[]'::jsonb);
    v_pay JSONB;
    v_pay_total NUMERIC := 0;
    v_amount NUMERIC;
    v_tendered NUMERIC;
    v_change NUMERIC := 0;
    v_credit NUMERIC := 0;
    v_customer public.customers;
    v_sale public.sales;
    v_line JSONB;
    v_line_no INTEGER := 0;
    v_invoice TEXT;
    v_primary_method TEXT;
    v_card JSONB;
    v_items_snapshot JSONB := '[]'::jsonb;
    v_result JSONB;
BEGIN
    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'request_id is required';
    END IF;
    IF v_status NOT IN ('completed', 'draft') THEN
        RAISE EXCEPTION 'Invalid sale status: %', v_status;
    END IF;

    v_existing := public.idempotency_begin(v_request_id, 'post_sale');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    v_quote := public.quote_sale(p_request);
    v_total := (v_quote->>'total')::numeric;
    SELECT * INTO v_profile FROM public.users WHERE id = auth.uid();

    -- Payments (not needed for drafts)
    IF v_status = 'completed' THEN
        IF jsonb_typeof(v_payments) <> 'array' OR jsonb_array_length(v_payments) = 0 THEN
            IF v_total = 0 THEN
                v_payments := '[]'::jsonb;
            ELSE
                RAISE EXCEPTION 'Add a payment';
            END IF;
        END IF;
        IF jsonb_array_length(v_payments) = 1 AND NULLIF(v_payments->0->>'amount', '') IS NULL THEN
            v_payments := jsonb_build_array(v_payments->0 || jsonb_build_object('amount', v_total));
        END IF;

        FOR v_pay IN SELECT * FROM jsonb_array_elements(v_payments)
        LOOP
            v_amount := (v_pay->>'amount')::numeric;
            IF v_amount IS NULL OR v_amount <= 0 THEN
                RAISE EXCEPTION 'Each payment needs an amount greater than zero';
            END IF;
            IF v_pay->>'method' NOT IN ('cash', 'card', 'digital', 'credit') THEN
                RAISE EXCEPTION 'Invalid payment method: %', v_pay->>'method';
            END IF;
            IF v_pay->>'method' = 'cash' AND NULLIF(v_pay->>'tendered', '') IS NOT NULL THEN
                v_tendered := (v_pay->>'tendered')::numeric;
                IF v_tendered < v_amount THEN
                    RAISE EXCEPTION 'Cash received is less than the cash amount';
                END IF;
                v_change := v_change + (v_tendered - v_amount);
            END IF;
            IF v_pay->>'method' = 'credit' THEN
                v_credit := v_credit + v_amount;
            END IF;
            v_pay_total := v_pay_total + v_amount;
        END LOOP;

        IF v_pay_total <> v_total THEN
            RAISE EXCEPTION 'Payments (%) do not match the total (%)', v_pay_total, v_total;
        END IF;

        IF v_credit > 0 THEN
            IF NULLIF(v_quote->>'customer_id', '') IS NULL THEN
                RAISE EXCEPTION 'Store credit needs a customer';
            END IF;
            SELECT * INTO v_customer FROM public.customers WHERE id = (v_quote->>'customer_id')::uuid FOR UPDATE;
            IF COALESCE(v_customer.credit_limit, 0) - COALESCE(v_customer.credit_used, 0) < v_credit THEN
                RAISE EXCEPTION 'Customer credit limit exceeded (available: %)',
                    COALESCE(v_customer.credit_limit, 0) - COALESCE(v_customer.credit_used, 0);
            END IF;
            UPDATE public.customers SET credit_used = COALESCE(credit_used, 0) + v_credit WHERE id = v_customer.id;
        END IF;
    END IF;

    SELECT p->>'method' INTO v_primary_method
    FROM jsonb_array_elements(v_payments) p ORDER BY (p->>'amount')::numeric DESC LIMIT 1;

    SELECT p INTO v_card FROM jsonb_array_elements(v_payments) p WHERE p->>'method' = 'card' LIMIT 1;

    IF v_status = 'draft' THEN
        v_invoice := 'DRAFT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    ELSE
        v_invoice := public.generate_invoice_number();
    END IF;

    -- Snapshot in the legacy `items` shape so existing screens keep working
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'product', jsonb_build_object('id', l->>'variant_id', 'name', l->>'description', 'sku', l->>'sku',
                                      'price', (l->>'unit_price')::numeric, 'unit', l->>'unit'),
        'quantity', (l->>'quantity')::numeric,
        'discount', (l->>'manual_discount')::numeric + (l->>'promotion_discount')::numeric,
        'discountType', 'fixed',
        'subtotal', (l->>'net')::numeric
    )), '[]'::jsonb) INTO v_items_snapshot
    FROM jsonb_array_elements(v_quote->'lines') l
    WHERE NOT (l->>'is_gift')::boolean;

    INSERT INTO public.sales (
        invoice_number, receipt_number, request_id, branch_id, location_id, channel,
        customer_id, customer_name, items, subtotal, discount_amount, tax_amount, total,
        payment_method, card_details, status, cashier, cashier_id, cashier_role, notes,
        applied_discounts, free_gifts, change_due
    ) VALUES (
        v_invoice, v_invoice, v_request_id, (v_quote->>'branch_id')::uuid, (v_quote->>'location_id')::uuid, 'pos',
        NULLIF(v_quote->>'customer_id', '')::uuid, v_quote->>'customer_name', v_items_snapshot,
        (v_quote->>'subtotal')::numeric, (v_quote->>'discount_amount')::numeric,
        (v_quote->>'tax_amount')::numeric, v_total,
        CASE WHEN v_status = 'draft' THEN NULL ELSE COALESCE(v_primary_method, 'cash') END,
        CASE WHEN v_card IS NULL THEN NULL ELSE public.sanitize_card_details(jsonb_build_object(
            'bankName', v_card->>'bank_name', 'cardType', v_card->>'card_type',
            'lastFourDigits', v_card->>'card_last4', 'holderName', v_card->>'holder_name')) END,
        CASE WHEN v_status = 'draft' THEN 'draft' WHEN v_credit > 0 THEN 'credit' ELSE 'completed' END,
        v_profile.name, v_profile.id, v_profile.role, left(p_request->>'notes', 1000),
        COALESCE(v_quote->'applied_discounts', '[]'::jsonb),
        COALESCE((SELECT jsonb_agg(l) FROM jsonb_array_elements(v_quote->'lines') l WHERE (l->>'is_gift')::boolean), '[]'::jsonb),
        v_change
    )
    RETURNING * INTO v_sale;

    FOR v_line IN SELECT * FROM jsonb_array_elements(v_quote->'lines')
    LOOP
        v_line_no := v_line_no + 1;
        INSERT INTO public.sale_lines (
            sale_id, line_no, variant_id, description, sku, unit, quantity, unit_price, gross,
            manual_discount, promotion_discount, net, taxable, tax, total, unit_cost, is_gift, promotion_id
        ) VALUES (
            v_sale.id, v_line_no, (v_line->>'variant_id')::uuid, v_line->>'description', v_line->>'sku',
            v_line->>'unit', (v_line->>'quantity')::numeric, (v_line->>'unit_price')::numeric,
            (v_line->>'gross')::numeric, (v_line->>'manual_discount')::numeric,
            (v_line->>'promotion_discount')::numeric, (v_line->>'net')::numeric,
            (v_line->>'taxable')::boolean, (v_line->>'tax')::numeric, (v_line->>'total')::numeric,
            NULLIF(v_line->>'unit_cost', '')::numeric, (v_line->>'is_gift')::boolean,
            NULLIF(v_line->>'promotion_id', '')::uuid
        );
    END LOOP;

    -- Stock: one movement per item, locked in variant order so two tills
    -- selling the same items can never deadlock each other
    IF v_status = 'completed' THEN
        FOR v_line IN
            SELECT jsonb_build_object(
                'variant_id', l->>'variant_id',
                'quantity', SUM((l->>'quantity')::numeric),
                'unit_cost', MAX(l->>'unit_cost'))
            FROM jsonb_array_elements(v_quote->'lines') l
            WHERE (l->>'track_inventory')::boolean
            GROUP BY l->>'variant_id'
            ORDER BY l->>'variant_id'
        LOOP
            PERFORM public.post_stock_movement(
                (v_quote->>'location_id')::uuid, (v_line->>'variant_id')::uuid,
                -((v_line->>'quantity')::numeric), 'sale', 'pos', 'sale', v_sale.id,
                NULLIF(v_line->>'unit_cost', '')::numeric, NULL
            );
        END LOOP;
    END IF;

    IF v_status = 'completed' THEN
        FOR v_pay IN SELECT * FROM jsonb_array_elements(v_payments)
        LOOP
            INSERT INTO public.payments (
                sale_id, method, amount, tendered, change_given, reference,
                card_type, card_last4, bank_name, holder_name
            ) VALUES (
                v_sale.id, v_pay->>'method', (v_pay->>'amount')::numeric,
                NULLIF(v_pay->>'tendered', '')::numeric,
                CASE WHEN v_pay->>'method' = 'cash' AND NULLIF(v_pay->>'tendered', '') IS NOT NULL
                     THEN (v_pay->>'tendered')::numeric - (v_pay->>'amount')::numeric ELSE 0 END,
                left(v_pay->>'reference', 100),
                CASE WHEN v_pay->>'method' = 'card' THEN left(v_pay->>'card_type', 20) END,
                CASE WHEN v_pay->>'method' = 'card' THEN NULLIF(right(regexp_replace(COALESCE(v_pay->>'card_last4', ''), '\D', '', 'g'), 4), '') END,
                CASE WHEN v_pay->>'method' = 'card' THEN left(v_pay->>'bank_name', 100) END,
                CASE WHEN v_pay->>'method' = 'card' THEN left(v_pay->>'holder_name', 100) END
            );
        END LOOP;
    END IF;

    v_result := jsonb_build_object(
        'sale', to_jsonb(v_sale),
        'lines', (SELECT jsonb_agg(to_jsonb(sl) ORDER BY sl.line_no) FROM public.sale_lines sl WHERE sl.sale_id = v_sale.id),
        'payments', COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.created_at) FROM public.payments p WHERE p.sale_id = v_sale.id), '[]'::jsonb),
        'change_due', v_change
    );
    RETURN public.idempotency_finish(v_request_id, v_result);
END;
$$;

REVOKE ALL ON FUNCTION public.quote_sale(JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.post_sale(JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.promotion_item_matches(TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.quote_sale(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.post_sale(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.promotion_item_matches(TEXT, UUID) TO authenticated;
