-- =====================================================================
-- Returns and exchanges
--
--   * A return refers to lines of the original sale. The refund is the
--     share of what the customer actually paid for that line (after manual
--     and promotion discounts, plus tax), never today's shelf price.
--   * A quantity can only be returned once, even with two tills at once.
--   * Ready-made items within the return window: any till. Fabric, services,
--     or sales older than the window: managers only.
--   * Restocked items go back to the sale's location (fabric as a remnant
--     roll); damaged items are recorded but not restocked.
--   * Refunds are payments going out (cash refunds come out of the shift).
--   * An exchange is a return and a new sale in one transaction: the refund
--     pays for the new items first ('exchange' credit), the customer pays or
--     receives the difference.
-- =====================================================================

ALTER TABLE public.app_settings
    ADD COLUMN IF NOT EXISTS return_window_days INTEGER NOT NULL DEFAULT 7 CHECK (return_window_days >= 0);

-- 'exchange' moves value from a return to the replacement sale; it is never
-- accepted from the till directly (see post_sale).
ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS payments_method_check;
ALTER TABLE public.payments ADD CONSTRAINT payments_method_check
    CHECK (method IN ('cash', 'card', 'digital', 'credit', 'exchange'));
ALTER TABLE public.sales DROP CONSTRAINT IF EXISTS sales_payment_method_check;
ALTER TABLE public.sales ADD CONSTRAINT sales_payment_method_check
    CHECK (payment_method IN ('cash', 'card', 'digital', 'credit', 'exchange'));

CREATE SEQUENCE IF NOT EXISTS public.return_no_seq START 1;
REVOKE ALL ON SEQUENCE public.return_no_seq FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.returns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    return_no TEXT NOT NULL UNIQUE,
    request_id UUID UNIQUE,
    sale_id UUID NOT NULL REFERENCES public.sales(id),
    branch_id UUID NOT NULL REFERENCES public.branches(id),
    location_id UUID NOT NULL REFERENCES public.locations(id),
    customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    reason TEXT NOT NULL,
    refund_total NUMERIC(14,2) NOT NULL CHECK (refund_total >= 0),
    refund_method TEXT NOT NULL CHECK (refund_method IN ('cash', 'card', 'digital', 'credit', 'exchange')),
    exchange_sale_id UUID REFERENCES public.sales(id),
    created_by UUID DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_returns_sale ON public.returns(sale_id);
CREATE INDEX IF NOT EXISTS idx_returns_branch_time ON public.returns(branch_id, created_at);

CREATE TABLE IF NOT EXISTS public.return_lines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    return_id UUID NOT NULL REFERENCES public.returns(id) ON DELETE CASCADE,
    sale_line_id UUID NOT NULL REFERENCES public.sale_lines(id),
    variant_id UUID REFERENCES public.product_variants(id),
    description TEXT NOT NULL,
    quantity NUMERIC(18,6) NOT NULL CHECK (quantity > 0),
    refund_amount NUMERIC(14,2) NOT NULL CHECK (refund_amount >= 0),
    tax_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
    restocked BOOLEAN NOT NULL,
    condition TEXT NOT NULL DEFAULT 'resaleable' CHECK (condition IN ('resaleable', 'damaged', 'faulty'))
);
CREATE INDEX IF NOT EXISTS idx_return_lines_sale_line ON public.return_lines(sale_line_id);

ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS return_id UUID REFERENCES public.returns(id);

ALTER TABLE public.returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.return_lines ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "returns_select" ON public.returns;
CREATE POLICY "returns_select" ON public.returns
    FOR SELECT TO authenticated
    USING (public.is_branch_member(branch_id) AND (public.has_app_role(ARRAY['admin', 'manager']) OR created_by = auth.uid()));
DROP POLICY IF EXISTS "return_lines_select" ON public.return_lines;
CREATE POLICY "return_lines_select" ON public.return_lines
    FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.returns r WHERE r.id = return_id));

DROP TRIGGER IF EXISTS trigger_returns_append_only ON public.returns;
CREATE TRIGGER trigger_returns_append_only
    BEFORE DELETE ON public.returns
    FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();
DROP TRIGGER IF EXISTS trigger_return_lines_append_only ON public.return_lines;
CREATE TRIGGER trigger_return_lines_append_only
    BEFORE UPDATE OR DELETE ON public.return_lines
    FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();

-- What can still be returned from a sale, line by line
CREATE OR REPLACE FUNCTION public.sale_returnable(p_sale_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'sale_line_id', sl.id,
        'line_no', sl.line_no,
        'variant_id', sl.variant_id,
        'description', sl.description,
        'sku', sl.sku,
        'unit', sl.unit,
        'quantity', sl.quantity,
        'returned', COALESCE(r.returned, 0),
        'returnable', sl.quantity - COALESCE(r.returned, 0),
        'unit_paid', CASE WHEN sl.quantity > 0 THEN round(sl.total / sl.quantity, 2) ELSE 0 END,
        'is_gift', sl.is_gift
    ) ORDER BY sl.line_no), '[]'::jsonb)
    FROM public.sale_lines sl
    LEFT JOIN (SELECT sale_line_id, sum(quantity) AS returned FROM public.return_lines GROUP BY sale_line_id) r
           ON r.sale_line_id = sl.id
    WHERE sl.sale_id = p_sale_id
      AND EXISTS (SELECT 1 FROM public.sales s WHERE s.id = p_sale_id
                  AND public.is_branch_member(s.branch_id)
                  AND public.current_app_role() IN ('admin', 'manager', 'cashier'))
$$;

-- ---------------------------------------------------------------------
-- Internal: create the return, restock, refund. p_refund_method may be
-- 'exchange' only when called from post_exchange.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_return(p JSONB, p_refund_method TEXT)
RETURNS public.returns
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role TEXT := public.current_app_role();
    v_sale public.sales;
    v_settings public.app_settings;
    v_needs_manager BOOLEAN := false;
    v_req JSONB;
    v_line public.sale_lines;
    v_returned NUMERIC;
    v_qty NUMERIC;
    v_refund NUMERIC;
    v_tax NUMERIC;
    v_total NUMERIC := 0;
    v_restock BOOLEAN;
    v_condition TEXT;
    v_return public.returns;
    v_roll public.fabric_rolls;
    v_track BOOLEAN;
    v_customer public.customers;
BEGIN
    IF v_role IS NULL OR v_role NOT IN ('admin', 'manager', 'cashier') THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
    IF COALESCE(trim(p->>'reason'), '') = '' THEN
        RAISE EXCEPTION 'A reason is required for a return';
    END IF;
    IF jsonb_typeof(p->'lines') <> 'array' OR jsonb_array_length(p->'lines') = 0 THEN
        RAISE EXCEPTION 'Choose at least one item to return';
    END IF;

    -- Locking the sale serialises returns of the same sale
    SELECT * INTO v_sale FROM public.sales WHERE id = NULLIF(p->>'sale_id', '')::uuid FOR UPDATE;
    IF v_sale.id IS NULL OR NOT public.is_branch_member(v_sale.branch_id) THEN
        RAISE EXCEPTION 'Sale not found';
    END IF;
    IF v_sale.status NOT IN ('completed', 'credit', 'refunded') THEN
        RAISE EXCEPTION 'Only completed sales can be returned';
    END IF;

    SELECT * INTO v_settings FROM public.app_settings ORDER BY created_at LIMIT 1;
    IF v_sale.created_at < now() - make_interval(days => COALESCE(v_settings.return_window_days, 7)) THEN
        v_needs_manager := true;
    END IF;

    INSERT INTO public.returns (return_no, request_id, sale_id, branch_id, location_id, customer_id, reason,
                                refund_total, refund_method)
    VALUES ('RTN-' || lpad(nextval('public.return_no_seq')::text, 6, '0'), NULLIF(p->>'request_id', '')::uuid,
            v_sale.id, v_sale.branch_id, COALESCE(v_sale.location_id, (
                SELECT id FROM public.locations WHERE branch_id = v_sale.branch_id AND kind = 'shop_floor' ORDER BY created_at LIMIT 1)),
            v_sale.customer_id, trim(p->>'reason'), 0, p_refund_method)
    RETURNING * INTO v_return;

    FOR v_req IN
        SELECT l FROM jsonb_array_elements(p->'lines') l ORDER BY l->>'sale_line_id'
    LOOP
        SELECT * INTO v_line FROM public.sale_lines
        WHERE id = NULLIF(v_req->>'sale_line_id', '')::uuid AND sale_id = v_sale.id;
        IF v_line.id IS NULL THEN
            RAISE EXCEPTION 'That item is not on this sale';
        END IF;

        v_qty := COALESCE(NULLIF(v_req->>'quantity', '')::numeric, 0);
        IF v_qty <= 0 THEN
            RAISE EXCEPTION 'Return quantity for "%" must be greater than zero', v_line.description;
        END IF;
        IF v_line.unit = 'meter' THEN
            IF v_qty <> round(v_qty, 2) THEN
                RAISE EXCEPTION 'Length for "%" can have at most 2 decimals', v_line.description;
            END IF;
        ELSIF v_qty <> trunc(v_qty) THEN
            RAISE EXCEPTION 'Whole quantities only for "%"', v_line.description;
        END IF;
        IF v_line.unit IN ('meter', 'job') THEN
            v_needs_manager := true;
        END IF;

        SELECT COALESCE(sum(quantity), 0) INTO v_returned FROM public.return_lines WHERE sale_line_id = v_line.id;
        IF v_returned + v_qty > v_line.quantity THEN
            RAISE EXCEPTION 'Only % of "%" can still be returned', trim_scale(v_line.quantity - v_returned), v_line.description;
        END IF;

        -- Exact share of what was paid: earlier returns + this one never exceed the line total
        v_refund := round(v_line.total * (v_returned + v_qty) / v_line.quantity, 2)
                  - round(v_line.total * v_returned / v_line.quantity, 2);
        v_tax := round(v_line.tax * (v_returned + v_qty) / v_line.quantity, 2)
               - round(v_line.tax * v_returned / v_line.quantity, 2);

        v_condition := COALESCE(NULLIF(v_req->>'condition', ''), 'resaleable');
        IF v_condition NOT IN ('resaleable', 'damaged', 'faulty') THEN
            RAISE EXCEPTION 'Invalid condition: %', v_condition;
        END IF;
        v_restock := COALESCE((v_req->>'restock')::boolean, v_condition = 'resaleable');

        SELECT s.track_inventory INTO v_track
        FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id WHERE v.id = v_line.variant_id;
        v_restock := v_restock AND COALESCE(v_track, false);

        INSERT INTO public.return_lines (return_id, sale_line_id, variant_id, description, quantity, refund_amount,
                                         tax_amount, restocked, condition)
        VALUES (v_return.id, v_line.id, v_line.variant_id, v_line.description, v_qty, v_refund, v_tax, v_restock, v_condition);

        IF v_restock THEN
            IF v_line.unit = 'meter' THEN
                -- Returned fabric becomes a remnant roll
                PERFORM public.lock_stock_balance(v_return.location_id, v_line.variant_id);
                INSERT INTO public.fabric_rolls (variant_id, branch_id, location_id, roll_code, initial_length,
                                                 remaining_length, unit_cost, notes)
                VALUES (v_line.variant_id, v_return.branch_id, v_return.location_id, public.next_roll_code(), v_qty, 0,
                        v_line.unit_cost, 'Returned on ' || v_return.return_no)
                RETURNING * INTO v_roll;
                INSERT INTO public.barcodes (code, variant_id, roll_id) VALUES (v_roll.roll_code, v_line.variant_id, v_roll.id);
                PERFORM public.post_stock_movement(v_return.location_id, v_line.variant_id, v_qty, 'return', 'pos',
                                                   'return', v_return.id, v_line.unit_cost, v_return.return_no, v_roll.id);
            ELSE
                PERFORM public.post_stock_movement(v_return.location_id, v_line.variant_id, v_qty, 'return', 'pos',
                                                   'return', v_return.id, v_line.unit_cost, v_return.return_no);
            END IF;
        END IF;

        v_total := v_total + v_refund;
    END LOOP;

    IF v_needs_manager AND v_role NOT IN ('admin', 'manager') THEN
        RAISE EXCEPTION 'This return needs a manager (fabric, services, or outside the % day return window)',
            COALESCE(v_settings.return_window_days, 7) USING ERRCODE = '42501';
    END IF;

    -- Refund
    IF v_total > 0 THEN
        IF p_refund_method = 'credit' THEN
            SELECT * INTO v_customer FROM public.customers WHERE id = v_sale.customer_id FOR UPDATE;
            IF v_customer.id IS NULL THEN
                RAISE EXCEPTION 'Store credit refunds need the sale to have a customer';
            END IF;
            IF COALESCE(v_customer.credit_used, 0) < v_total THEN
                RAISE EXCEPTION 'Store credit refunds can only reduce what the customer owes (owes %)',
                    COALESCE(v_customer.credit_used, 0);
            END IF;
            UPDATE public.customers SET credit_used = credit_used - v_total WHERE id = v_customer.id;
        END IF;

        INSERT INTO public.payments (sale_id, return_id, method, amount, direction, reference)
        VALUES (v_sale.id, v_return.id, p_refund_method, v_total, 'out', v_return.return_no);
    END IF;

    IF v_sale.customer_id IS NOT NULL THEN
        UPDATE public.customers SET total_purchases = GREATEST(COALESCE(total_purchases, 0) - v_total, 0)
        WHERE id = v_sale.customer_id;
    END IF;

    -- Fully returned sales are marked refunded
    IF NOT EXISTS (
        SELECT 1 FROM public.sale_lines sl
        WHERE sl.sale_id = v_sale.id
          AND sl.quantity > COALESCE((SELECT sum(quantity) FROM public.return_lines rl WHERE rl.sale_line_id = sl.id), 0)
    ) THEN
        UPDATE public.sales SET status = 'refunded' WHERE id = v_sale.id;
    END IF;

    UPDATE public.returns SET refund_total = v_total WHERE id = v_return.id RETURNING * INTO v_return;
    RETURN v_return;
END;
$$;

REVOKE ALL ON FUNCTION public.create_return(JSONB, TEXT) FROM PUBLIC, anon, authenticated;

-- Input: { request_id, sale_id, reason, refund_method: cash|card|digital|credit,
--          lines: [{ sale_line_id, quantity, condition: resaleable|damaged|faulty, restock }] }
CREATE OR REPLACE FUNCTION public.post_return(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_request_id UUID := NULLIF(p->>'request_id', '')::uuid;
    v_existing JSONB;
    v_method TEXT := COALESCE(NULLIF(p->>'refund_method', ''), 'cash');
    v_return public.returns;
BEGIN
    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'request_id is required';
    END IF;
    IF v_method NOT IN ('cash', 'card', 'digital', 'credit') THEN
        RAISE EXCEPTION 'Invalid refund method: %', v_method;
    END IF;
    v_existing := public.idempotency_begin(v_request_id, 'post_return');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    v_return := public.create_return(p, v_method);
    RETURN public.idempotency_finish(v_request_id, jsonb_build_object(
        'return', to_jsonb(v_return),
        'lines', (SELECT jsonb_agg(to_jsonb(l)) FROM public.return_lines l WHERE l.return_id = v_return.id)
    ));
END;
$$;

-- Input: { request_id, sale_id, reason,
--          return_lines: [...as post_return...],
--          new_lines: [...as post_sale lines...],
--          payments: [...for any difference the customer pays...],
--          refund_method: for any difference given back (default cash) }
CREATE OR REPLACE FUNCTION public.post_exchange(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_request_id UUID := NULLIF(p->>'request_id', '')::uuid;
    v_existing JSONB;
    v_return public.returns;
    v_sale_req JSONB;
    v_quote JSONB;
    v_new_total NUMERIC;
    v_credit NUMERIC;
    v_due NUMERIC;
    v_back NUMERIC;
    v_payments JSONB;
    v_new_sale JSONB;
    v_back_method TEXT := COALESCE(NULLIF(p->>'refund_method', ''), 'cash');
    v_orig public.sales;
BEGIN
    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'request_id is required';
    END IF;
    IF v_back_method NOT IN ('cash', 'card', 'digital', 'credit') THEN
        RAISE EXCEPTION 'Invalid refund method: %', v_back_method;
    END IF;
    v_existing := public.idempotency_begin(v_request_id, 'post_exchange');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    SELECT * INTO v_orig FROM public.sales WHERE id = NULLIF(p->>'sale_id', '')::uuid;

    -- 1. Return: the value becomes exchange credit
    v_return := public.create_return(jsonb_build_object(
        'request_id', NULL, 'sale_id', p->'sale_id', 'reason', p->'reason', 'lines', p->'return_lines'), 'exchange');
    v_credit := v_return.refund_total;

    -- 2. Price the replacement items
    v_sale_req := jsonb_build_object('customer_id', v_orig.customer_id, 'lines', p->'new_lines',
                                     'location_id', v_return.location_id);
    v_quote := public.quote_sale(v_sale_req);
    v_new_total := (v_quote->>'total')::numeric;
    v_due := GREATEST(v_new_total - v_credit, 0);
    v_back := GREATEST(v_credit - v_new_total, 0);

    v_payments := CASE WHEN LEAST(v_credit, v_new_total) > 0
                       THEN jsonb_build_array(jsonb_build_object('method', 'exchange', 'amount', LEAST(v_credit, v_new_total),
                                                                 'reference', v_return.return_no))
                       ELSE '[]'::jsonb END;
    IF v_due > 0 THEN
        IF jsonb_typeof(p->'payments') <> 'array' OR jsonb_array_length(p->'payments') = 0 THEN
            RAISE EXCEPTION 'The customer owes % more; add a payment', v_due;
        END IF;
        IF jsonb_array_length(p->'payments') = 1 AND NULLIF(p->'payments'->0->>'amount', '') IS NULL THEN
            v_payments := v_payments || jsonb_build_array(p->'payments'->0 || jsonb_build_object('amount', v_due));
        ELSE
            v_payments := v_payments || (p->'payments');
        END IF;
    END IF;

    -- 3. The replacement sale, paid first with the exchange credit
    PERFORM set_config('pos.allow_exchange_payment', 'on', true);
    v_new_sale := public.post_sale(v_sale_req || jsonb_build_object(
        'request_id', gen_random_uuid(), 'payments', v_payments,
        'notes', 'Exchange for ' || v_orig.invoice_number || ' (' || v_return.return_no || ')'));
    PERFORM set_config('pos.allow_exchange_payment', 'off', true);

    -- 4. Anything left over goes back to the customer
    IF v_back > 0 THEN
        IF v_back_method = 'credit' THEN
            UPDATE public.customers SET credit_used = credit_used - v_back
            WHERE id = v_orig.customer_id AND credit_used >= v_back;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Store credit refunds can only reduce what the customer owes';
            END IF;
        END IF;
        INSERT INTO public.payments (sale_id, return_id, method, amount, direction, reference)
        VALUES (v_orig.id, v_return.id, v_back_method, v_back, 'out', v_return.return_no);
    END IF;

    UPDATE public.returns SET exchange_sale_id = (v_new_sale->'sale'->>'id')::uuid WHERE id = v_return.id
    RETURNING * INTO v_return;

    RETURN public.idempotency_finish(v_request_id, jsonb_build_object(
        'return', to_jsonb(v_return),
        'sale', v_new_sale->'sale',
        'customer_paid', v_due,
        'refunded', v_back
    ));
END;
$$;

REVOKE ALL ON FUNCTION public.sale_returnable(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.post_return(JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.post_exchange(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sale_returnable(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.post_return(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.post_exchange(JSONB) TO authenticated;

-- ---------------------------------------------------------------------
-- post_sale: also accepts the internal 'exchange' tender, only while
-- post_exchange is running in the same transaction.
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
            IF v_pay->>'method' = 'exchange' AND COALESCE(current_setting('pos.allow_exchange_payment', true), '') <> 'on' THEN
                RAISE EXCEPTION 'Exchange credit can only be used through an exchange' USING ERRCODE = '42501';
            END IF;
            IF v_pay->>'method' NOT IN ('cash', 'card', 'digital', 'credit', 'exchange') THEN
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
