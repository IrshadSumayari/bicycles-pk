-- =====================================================================
-- Goods receiving
--
--   * goods_receipts / goods_receipt_lines: one document per supplier
--     delivery (supplier, their invoice number, items, quantities, costs)
--   * post_goods_receipt(): posts every line to the ledger in one
--     transaction; each fabric line becomes a roll; item cost becomes the
--     weighted average of stock on hand and the new delivery
--   * Idempotent by request_id
-- =====================================================================

CREATE UNIQUE INDEX IF NOT EXISTS idx_suppliers_name ON public.suppliers (lower(name));

CREATE SEQUENCE IF NOT EXISTS public.goods_receipt_no_seq START 1;
REVOKE ALL ON SEQUENCE public.goods_receipt_no_seq FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.goods_receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    receipt_no TEXT NOT NULL UNIQUE,
    request_id UUID UNIQUE,
    branch_id UUID NOT NULL REFERENCES public.branches(id),
    location_id UUID NOT NULL REFERENCES public.locations(id),
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    supplier_name TEXT,
    supplier_reference TEXT,
    notes TEXT,
    total_cost NUMERIC(14,2) NOT NULL DEFAULT 0,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_goods_receipts_branch_time ON public.goods_receipts(branch_id, received_at);

CREATE TABLE IF NOT EXISTS public.goods_receipt_lines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    receipt_id UUID NOT NULL REFERENCES public.goods_receipts(id) ON DELETE CASCADE,
    line_no INTEGER NOT NULL,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
    description TEXT NOT NULL,
    quantity NUMERIC(18,6) NOT NULL CHECK (quantity > 0),
    unit_cost NUMERIC(14,4) NOT NULL CHECK (unit_cost >= 0),
    line_cost NUMERIC(14,2) NOT NULL,
    roll_id UUID REFERENCES public.fabric_rolls(id),
    UNIQUE (receipt_id, line_no)
);
CREATE INDEX IF NOT EXISTS idx_goods_receipt_lines_variant ON public.goods_receipt_lines(variant_id);

ALTER TABLE public.goods_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.goods_receipt_lines ENABLE ROW LEVEL SECURITY;

-- Receipts show costs: back office only. Written only by post_goods_receipt().
DROP POLICY IF EXISTS "goods_receipts_back_office" ON public.goods_receipts;
CREATE POLICY "goods_receipts_back_office" ON public.goods_receipts
    FOR SELECT TO authenticated
    USING (public.has_app_role(ARRAY['admin', 'manager']) AND public.is_branch_member(branch_id));
DROP POLICY IF EXISTS "goods_receipt_lines_back_office" ON public.goods_receipt_lines;
CREATE POLICY "goods_receipt_lines_back_office" ON public.goods_receipt_lines
    FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.goods_receipts r WHERE r.id = receipt_id));

DROP TRIGGER IF EXISTS trigger_goods_receipts_append_only ON public.goods_receipts;
CREATE TRIGGER trigger_goods_receipts_append_only
    BEFORE UPDATE OR DELETE ON public.goods_receipts
    FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();
DROP TRIGGER IF EXISTS trigger_goods_receipt_lines_append_only ON public.goods_receipt_lines;
CREATE TRIGGER trigger_goods_receipt_lines_append_only
    BEFORE UPDATE OR DELETE ON public.goods_receipt_lines
    FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();

-- Input:
-- {
--   "request_id": uuid (required),
--   "location_id": uuid (default: shop floor),
--   "supplier_id": uuid | "supplier_name": text (created if new),
--   "supplier_reference": text, "notes": text,
--   "lines": [{ "variant_id", "quantity", "unit_cost",
--               fabric only: "roll_code", "width_cm", "shade_lot" }]
-- }
CREATE OR REPLACE FUNCTION public.post_goods_receipt(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_request_id UUID := NULLIF(p->>'request_id', '')::uuid;
    v_existing JSONB;
    v_location UUID := NULLIF(p->>'location_id', '')::uuid;
    v_branch UUID;
    v_supplier UUID := NULLIF(p->>'supplier_id', '')::uuid;
    v_supplier_name TEXT := NULLIF(trim(COALESCE(p->>'supplier_name', '')), '');
    v_receipt public.goods_receipts;
    v_line JSONB;
    v_line_no INTEGER := 0;
    v_variant RECORD;
    v_qty NUMERIC;
    v_cost NUMERIC;
    v_roll public.fabric_rolls;
    v_roll_code TEXT;
    v_on_hand NUMERIC;
    v_old_cost NUMERIC;
    v_total NUMERIC := 0;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can receive stock' USING ERRCODE = '42501';
    END IF;
    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'request_id is required';
    END IF;

    v_existing := public.idempotency_begin(v_request_id, 'post_goods_receipt');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    IF jsonb_typeof(p->'lines') <> 'array' OR jsonb_array_length(p->'lines') = 0 THEN
        RAISE EXCEPTION 'Add at least one item';
    END IF;

    IF v_location IS NULL THEN
        SELECT id INTO v_location FROM public.locations
        WHERE branch_id = public.default_branch_id() AND kind = 'shop_floor' AND active
        ORDER BY created_at LIMIT 1;
    END IF;
    SELECT branch_id INTO v_branch FROM public.locations WHERE id = v_location AND active;
    IF v_branch IS NULL OR NOT public.is_branch_member(v_branch) THEN
        RAISE EXCEPTION 'Receiving location not found' USING ERRCODE = '42501';
    END IF;

    -- Supplier: existing id, or find/create by name
    IF v_supplier IS NULL AND v_supplier_name IS NOT NULL THEN
        SELECT id INTO v_supplier FROM public.suppliers WHERE lower(name) = lower(v_supplier_name);
        IF v_supplier IS NULL THEN
            INSERT INTO public.suppliers (name) VALUES (v_supplier_name) RETURNING id INTO v_supplier;
        END IF;
    END IF;
    IF v_supplier IS NOT NULL THEN
        SELECT name INTO v_supplier_name FROM public.suppliers WHERE id = v_supplier;
        IF v_supplier_name IS NULL THEN
            RAISE EXCEPTION 'Supplier not found';
        END IF;
    END IF;

    -- Header total up front (the receipt is append-only); lines are validated below
    SELECT COALESCE(SUM(round(COALESCE(NULLIF(l->>'quantity', '')::numeric, 0)
                              * COALESCE(NULLIF(l->>'unit_cost', '')::numeric, 0), 2)), 0)
    INTO v_total FROM jsonb_array_elements(p->'lines') l;

    INSERT INTO public.goods_receipts (receipt_no, request_id, branch_id, location_id, supplier_id, supplier_name,
                                       supplier_reference, notes, total_cost)
    VALUES ('GRN-' || lpad(nextval('public.goods_receipt_no_seq')::text, 6, '0'), v_request_id, v_branch, v_location,
            v_supplier, v_supplier_name, NULLIF(trim(p->>'supplier_reference'), ''), NULLIF(trim(p->>'notes'), ''),
            v_total)
    RETURNING * INTO v_receipt;

    -- Lines in variant order (consistent locking with sales)
    FOR v_line IN
        SELECT l FROM jsonb_array_elements(p->'lines') WITH ORDINALITY AS t(l, n)
        ORDER BY l->>'variant_id', n
    LOOP
        v_line_no := v_line_no + 1;

        SELECT v.id, s.unit, s.track_inventory,
               trim(s.name || COALESCE(' ' || v.size, '') || COALESCE(' ' || v.color, '') || COALESCE(' ' || v.fit, '')) AS description
        INTO v_variant
        FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id
        WHERE v.id = NULLIF(v_line->>'variant_id', '')::uuid;
        IF v_variant.id IS NULL THEN
            RAISE EXCEPTION 'Item not found: %', v_line->>'variant_id';
        END IF;
        IF NOT v_variant.track_inventory THEN
            RAISE EXCEPTION '"%" does not track stock', v_variant.description;
        END IF;

        v_qty := NULLIF(v_line->>'quantity', '')::numeric;
        v_cost := COALESCE(NULLIF(v_line->>'unit_cost', '')::numeric, -1);
        IF v_qty IS NULL OR v_qty <= 0 THEN
            RAISE EXCEPTION 'Quantity for "%" must be greater than zero', v_variant.description;
        END IF;
        IF v_cost < 0 THEN
            RAISE EXCEPTION 'Enter the unit cost for "%"', v_variant.description;
        END IF;
        IF v_variant.unit = 'meter' THEN
            IF v_qty <> round(v_qty, 2) THEN
                RAISE EXCEPTION 'Roll length for "%" can have at most 2 decimals', v_variant.description;
            END IF;
        ELSIF v_qty <> trunc(v_qty) THEN
            RAISE EXCEPTION 'Whole quantities only for "%"', v_variant.description;
        END IF;

        -- Weighted average cost over all stock of this item
        SELECT COALESCE(SUM(on_hand), 0) INTO v_on_hand FROM public.stock_balances WHERE variant_id = v_variant.id;
        SELECT unit_cost INTO v_old_cost FROM public.variant_costs WHERE variant_id = v_variant.id FOR UPDATE;
        INSERT INTO public.variant_costs (variant_id, unit_cost)
        VALUES (v_variant.id, CASE
            WHEN v_old_cost IS NULL OR v_on_hand <= 0 THEN v_cost
            ELSE round((v_on_hand * v_old_cost + v_qty * v_cost) / (v_on_hand + v_qty), 4) END)
        ON CONFLICT (variant_id) DO UPDATE SET unit_cost = EXCLUDED.unit_cost;

        v_roll := NULL;
        IF v_variant.unit = 'meter' THEN
            v_roll_code := NULLIF(upper(trim(COALESCE(v_line->>'roll_code', ''))), '');
            IF v_roll_code IS NOT NULL AND EXISTS (SELECT 1 FROM public.barcodes WHERE code = v_roll_code) THEN
                RAISE EXCEPTION 'Code % is already used', v_roll_code;
            END IF;
            PERFORM public.lock_stock_balance(v_location, v_variant.id);
            INSERT INTO public.fabric_rolls (variant_id, branch_id, location_id, roll_code, width_cm, shade_lot,
                                             initial_length, remaining_length, unit_cost, notes)
            VALUES (v_variant.id, v_branch, v_location, COALESCE(v_roll_code, public.next_roll_code()),
                    NULLIF(v_line->>'width_cm', '')::numeric, NULLIF(trim(v_line->>'shade_lot'), ''),
                    v_qty, 0, v_cost, 'Received on ' || v_receipt.receipt_no)
            RETURNING * INTO v_roll;
            INSERT INTO public.barcodes (code, variant_id, roll_id) VALUES (v_roll.roll_code, v_variant.id, v_roll.id);
        END IF;

        PERFORM public.post_stock_movement(v_location, v_variant.id, v_qty, 'receive', 'pos', 'goods_receipt',
                                           v_receipt.id, v_cost, v_receipt.receipt_no, v_roll.id);

        INSERT INTO public.goods_receipt_lines (receipt_id, line_no, variant_id, description, quantity, unit_cost,
                                                line_cost, roll_id)
        VALUES (v_receipt.id, v_line_no, v_variant.id, v_variant.description, v_qty, v_cost, round(v_qty * v_cost, 2),
                v_roll.id);
    END LOOP;

    RETURN public.idempotency_finish(v_request_id, jsonb_build_object(
        'receipt', to_jsonb(v_receipt),
        'lines', (SELECT jsonb_agg(to_jsonb(l) ORDER BY l.line_no) FROM public.goods_receipt_lines l WHERE l.receipt_id = v_receipt.id)
    ));
END;
$$;

REVOKE ALL ON FUNCTION public.post_goods_receipt(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.post_goods_receipt(JSONB) TO authenticated;
