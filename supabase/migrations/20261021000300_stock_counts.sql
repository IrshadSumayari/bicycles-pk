-- =====================================================================
-- Stock counts
--
--   * A count is opened for a location; staff record counted quantities
--     (fabric per roll). The system quantity is captured at the moment each
--     item is counted, so sales made before approval are not overwritten.
--   * A manager approves: each difference (counted - system at count time)
--     is posted to the ledger as a 'count' movement. Partial counts are
--     fine: items not counted are left alone.
-- =====================================================================

CREATE SEQUENCE IF NOT EXISTS public.stock_count_no_seq START 1;
REVOKE ALL ON SEQUENCE public.stock_count_no_seq FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.stock_counts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    count_no TEXT NOT NULL UNIQUE,
    branch_id UUID NOT NULL REFERENCES public.branches(id),
    location_id UUID NOT NULL REFERENCES public.locations(id),
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'approved', 'cancelled')),
    notes TEXT,
    created_by UUID DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_by UUID,
    closed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_stock_counts_branch ON public.stock_counts(branch_id, created_at);

CREATE TABLE IF NOT EXISTS public.stock_count_lines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    count_id UUID NOT NULL REFERENCES public.stock_counts(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
    roll_id UUID REFERENCES public.fabric_rolls(id),
    counted NUMERIC(18,6) NOT NULL CHECK (counted >= 0),
    expected NUMERIC(18,6) NOT NULL,
    difference NUMERIC(18,6),
    counted_by UUID DEFAULT auth.uid(),
    counted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_stock_count_lines_item
    ON public.stock_count_lines (count_id, variant_id, COALESCE(roll_id, '00000000-0000-0000-0000-000000000000'::uuid));

ALTER TABLE public.stock_counts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_count_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "stock_counts_select_members" ON public.stock_counts;
CREATE POLICY "stock_counts_select_members" ON public.stock_counts
    FOR SELECT TO authenticated USING (public.is_branch_member(branch_id));
DROP POLICY IF EXISTS "stock_count_lines_select" ON public.stock_count_lines;
CREATE POLICY "stock_count_lines_select" ON public.stock_count_lines
    FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.stock_counts c WHERE c.id = count_id));

-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.start_stock_count(p_location_id UUID DEFAULT NULL, p_notes TEXT DEFAULT NULL)
RETURNS public.stock_counts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_location UUID := p_location_id;
    v_branch UUID;
    v_count public.stock_counts;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can start a stock count' USING ERRCODE = '42501';
    END IF;
    IF v_location IS NULL THEN
        SELECT id INTO v_location FROM public.locations
        WHERE branch_id = public.default_branch_id() AND kind = 'shop_floor' AND active
        ORDER BY created_at LIMIT 1;
    END IF;
    SELECT branch_id INTO v_branch FROM public.locations WHERE id = v_location AND active;
    IF v_branch IS NULL OR NOT public.is_branch_member(v_branch) THEN
        RAISE EXCEPTION 'Location not found' USING ERRCODE = '42501';
    END IF;
    IF EXISTS (SELECT 1 FROM public.stock_counts WHERE location_id = v_location AND status = 'open') THEN
        RAISE EXCEPTION 'A count is already open for this location';
    END IF;

    INSERT INTO public.stock_counts (count_no, branch_id, location_id, notes)
    VALUES ('CNT-' || lpad(nextval('public.stock_count_no_seq')::text, 6, '0'), v_branch, v_location,
            NULLIF(trim(p_notes), ''))
    RETURNING * INTO v_count;
    RETURN v_count;
END;
$$;

-- Record (or correct) the counted quantity of one item, or one roll for fabric
CREATE OR REPLACE FUNCTION public.record_stock_count(
    p_count_id UUID,
    p_variant_id UUID,
    p_counted NUMERIC,
    p_roll_id UUID DEFAULT NULL
)
RETURNS public.stock_count_lines
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count public.stock_counts;
    v_unit TEXT;
    v_expected NUMERIC;
    v_line public.stock_count_lines;
BEGIN
    IF public.current_app_role() NOT IN ('admin', 'manager', 'cashier') THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_count FROM public.stock_counts WHERE id = p_count_id FOR UPDATE;
    IF v_count.id IS NULL OR NOT public.is_branch_member(v_count.branch_id) THEN
        RAISE EXCEPTION 'Count not found';
    END IF;
    IF v_count.status <> 'open' THEN
        RAISE EXCEPTION 'Count % is %', v_count.count_no, v_count.status;
    END IF;
    IF p_counted IS NULL OR p_counted < 0 THEN
        RAISE EXCEPTION 'Counted quantity cannot be negative';
    END IF;

    SELECT s.unit INTO v_unit FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id
    WHERE v.id = p_variant_id AND s.track_inventory;
    IF v_unit IS NULL THEN
        RAISE EXCEPTION 'Item not found or does not track stock';
    END IF;

    IF v_unit = 'meter' THEN
        IF p_roll_id IS NULL THEN
            RAISE EXCEPTION 'Fabric is counted per roll';
        END IF;
        IF p_counted <> round(p_counted, 2) THEN
            RAISE EXCEPTION 'Roll length can have at most 2 decimals';
        END IF;
        SELECT remaining_length INTO v_expected FROM public.fabric_rolls
        WHERE id = p_roll_id AND variant_id = p_variant_id AND location_id = v_count.location_id;
        IF v_expected IS NULL THEN
            RAISE EXCEPTION 'That roll is not at this location';
        END IF;
    ELSE
        IF p_roll_id IS NOT NULL THEN
            RAISE EXCEPTION 'Only fabric is counted per roll';
        END IF;
        IF p_counted <> trunc(p_counted) THEN
            RAISE EXCEPTION 'Whole quantities only';
        END IF;
        SELECT COALESCE((SELECT on_hand FROM public.stock_balances
                         WHERE variant_id = p_variant_id AND location_id = v_count.location_id), 0)
        INTO v_expected;
    END IF;

    INSERT INTO public.stock_count_lines (count_id, variant_id, roll_id, counted, expected)
    VALUES (p_count_id, p_variant_id, p_roll_id, p_counted, v_expected)
    ON CONFLICT (count_id, variant_id, COALESCE(roll_id, '00000000-0000-0000-0000-000000000000'::uuid))
    DO UPDATE SET counted = EXCLUDED.counted, expected = EXCLUDED.expected,
                  counted_by = auth.uid(), counted_at = now()
    RETURNING * INTO v_line;
    RETURN v_line;
END;
$$;

-- Post every difference and close the count
CREATE OR REPLACE FUNCTION public.approve_stock_count(p_count_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count public.stock_counts;
    v_line public.stock_count_lines;
    v_diff NUMERIC;
    v_changed INTEGER := 0;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can approve a stock count' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_count FROM public.stock_counts WHERE id = p_count_id FOR UPDATE;
    IF v_count.id IS NULL OR NOT public.is_branch_member(v_count.branch_id) THEN
        RAISE EXCEPTION 'Count not found';
    END IF;
    IF v_count.status = 'approved' THEN
        -- Approving twice (e.g. a retry) is a no-op
        RETURN jsonb_build_object('count', to_jsonb(v_count), 'changed_lines', 0, 'already_approved', true);
    END IF;
    IF v_count.status <> 'open' THEN
        RAISE EXCEPTION 'Count % is %', v_count.count_no, v_count.status;
    END IF;

    FOR v_line IN
        SELECT * FROM public.stock_count_lines WHERE count_id = p_count_id ORDER BY variant_id, roll_id
    LOOP
        v_diff := v_line.counted - v_line.expected;
        IF v_diff <> 0 THEN
            PERFORM public.post_stock_movement(
                v_count.location_id, v_line.variant_id, v_diff, 'count', 'pos', 'stock_count', v_count.id,
                NULL, 'Stock count ' || v_count.count_no, v_line.roll_id);
            v_changed := v_changed + 1;
        END IF;
        UPDATE public.stock_count_lines SET difference = v_diff WHERE id = v_line.id;
    END LOOP;

    UPDATE public.stock_counts SET status = 'approved', closed_by = auth.uid(), closed_at = now()
    WHERE id = p_count_id RETURNING * INTO v_count;

    RETURN jsonb_build_object('count', to_jsonb(v_count), 'changed_lines', v_changed);
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_stock_count(p_count_id UUID)
RETURNS public.stock_counts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count public.stock_counts;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can cancel a stock count' USING ERRCODE = '42501';
    END IF;
    UPDATE public.stock_counts SET status = 'cancelled', closed_by = auth.uid(), closed_at = now()
    WHERE id = p_count_id AND status = 'open' AND public.is_branch_member(branch_id)
    RETURNING * INTO v_count;
    IF v_count.id IS NULL THEN
        RAISE EXCEPTION 'Open count not found';
    END IF;
    RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.start_stock_count(UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_stock_count(UUID, UUID, NUMERIC, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_stock_count(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_stock_count(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_stock_count(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_stock_count(UUID, UUID, NUMERIC, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_stock_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_stock_count(UUID) TO authenticated;
