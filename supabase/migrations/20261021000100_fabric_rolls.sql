-- =====================================================================
-- Fabric rolls
--
--   * Every meter of fabric stock lives on a physical roll with its own
--     barcode, width and shade/lot. A location's fabric on_hand always equals
--     the sum of its rolls' remaining length.
--   * A cut comes from ONE roll: two short rolls never make one long piece.
--     Without an explicit roll the ledger picks the roll that fits best
--     (the shortest roll that is long enough).
--   * Receiving fabric creates a roll; waste and recounts are posted per roll.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.fabric_rolls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    branch_id UUID NOT NULL REFERENCES public.branches(id),
    location_id UUID NOT NULL REFERENCES public.locations(id),
    roll_code TEXT NOT NULL UNIQUE CHECK (length(trim(roll_code)) > 0),
    width_cm NUMERIC(8,2) CHECK (width_cm IS NULL OR width_cm > 0),
    shade_lot TEXT,
    initial_length NUMERIC(18,6) NOT NULL CHECK (initial_length > 0),
    remaining_length NUMERIC(18,6) NOT NULL CHECK (remaining_length >= 0),
    reserved_length NUMERIC(18,6) NOT NULL DEFAULT 0 CHECK (reserved_length >= 0),
    unit_cost NUMERIC(14,4),
    notes TEXT,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID DEFAULT auth.uid(),
    CONSTRAINT fabric_rolls_reserved_le_remaining CHECK (reserved_length <= remaining_length)
);
CREATE INDEX IF NOT EXISTS idx_fabric_rolls_variant ON public.fabric_rolls(variant_id, location_id) WHERE remaining_length > 0;

ALTER TABLE public.stock_movements ADD COLUMN IF NOT EXISTS roll_id UUID REFERENCES public.fabric_rolls(id);
ALTER TABLE public.stock_reservations ADD COLUMN IF NOT EXISTS roll_id UUID REFERENCES public.fabric_rolls(id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_roll ON public.stock_movements(roll_id) WHERE roll_id IS NOT NULL;

-- A barcode can point at a roll (the roll's variant is still recorded)
ALTER TABLE public.barcodes ADD COLUMN IF NOT EXISTS roll_id UUID UNIQUE REFERENCES public.fabric_rolls(id) ON DELETE CASCADE;

ALTER TABLE public.fabric_rolls ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "fabric_rolls_select_members" ON public.fabric_rolls;
CREATE POLICY "fabric_rolls_select_members" ON public.fabric_rolls
    FOR SELECT TO authenticated USING (public.is_branch_member(branch_id));

-- Roll codes: R + 6 digits
CREATE SEQUENCE IF NOT EXISTS public.fabric_roll_code_seq START 1;
REVOKE ALL ON SEQUENCE public.fabric_roll_code_seq FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.next_roll_code()
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT 'R' || lpad(nextval('public.fabric_roll_code_seq')::text, 6, '0')
$$;
REVOKE ALL ON FUNCTION public.next_roll_code() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- Ledger: post_stock_movement learns about rolls
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.post_stock_movement(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT, UUID, NUMERIC, TEXT);

CREATE OR REPLACE FUNCTION public.post_stock_movement(
    p_location_id UUID,
    p_variant_id UUID,
    p_quantity NUMERIC,
    p_movement_type TEXT,
    p_channel TEXT DEFAULT 'pos',
    p_reference_type TEXT DEFAULT NULL,
    p_reference_id UUID DEFAULT NULL,
    p_unit_cost NUMERIC DEFAULT NULL,
    p_reason TEXT DEFAULT NULL,
    p_roll_id UUID DEFAULT NULL
)
RETURNS public.stock_balances
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_balance public.stock_balances;
    v_name TEXT;
    v_unit TEXT;
    v_roll public.fabric_rolls;
    v_roll_id UUID := p_roll_id;
    v_longest NUMERIC;
BEGIN
    IF p_quantity = 0 THEN
        RAISE EXCEPTION 'Quantity cannot be zero';
    END IF;

    SELECT s.unit, s.name || COALESCE(' ' || v.size, '') || COALESCE(' ' || v.color, '')
    INTO v_unit, v_name
    FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id
    WHERE v.id = p_variant_id;
    IF v_unit IS NULL THEN
        RAISE EXCEPTION 'Item not found';
    END IF;

    v_balance := public.lock_stock_balance(p_location_id, p_variant_id);

    IF p_quantity < 0 AND v_balance.on_hand - v_balance.reserved + p_quantity < 0 THEN
        RAISE EXCEPTION 'Not enough stock for "%" (available: %, needed: %)',
            v_name, trim_scale(v_balance.on_hand - v_balance.reserved), trim_scale(-p_quantity)
            USING ERRCODE = 'P0001';
    END IF;

    -- Fabric: every movement belongs to a roll
    IF v_unit = 'meter' THEN
        IF v_roll_id IS NULL AND p_quantity < 0 THEN
            -- Best fit: the shortest roll that can supply the whole cut
            SELECT id INTO v_roll_id FROM public.fabric_rolls
            WHERE variant_id = p_variant_id AND location_id = p_location_id
              AND remaining_length - reserved_length >= -p_quantity
            ORDER BY remaining_length - reserved_length, received_at, id
            LIMIT 1;
            IF v_roll_id IS NULL THEN
                SELECT max(remaining_length - reserved_length) INTO v_longest FROM public.fabric_rolls
                WHERE variant_id = p_variant_id AND location_id = p_location_id;
                RAISE EXCEPTION 'No single roll of "%" has % m (longest available piece: % m)',
                    v_name, trim_scale(-p_quantity), trim_scale(COALESCE(v_longest, 0))
                    USING ERRCODE = 'P0001';
            END IF;
        ELSIF v_roll_id IS NULL AND p_quantity > 0 THEN
            IF p_movement_type NOT IN ('opening', 'receive') THEN
                RAISE EXCEPTION 'Choose the roll for this fabric movement';
            END IF;
            -- New stock arrives as a new roll
            INSERT INTO public.fabric_rolls (variant_id, branch_id, location_id, roll_code, initial_length,
                                             remaining_length, unit_cost)
            VALUES (p_variant_id, v_balance.branch_id, p_location_id, public.next_roll_code(), p_quantity, 0, p_unit_cost)
            RETURNING id INTO v_roll_id;
            INSERT INTO public.barcodes (code, variant_id, roll_id)
            SELECT roll_code, p_variant_id, id FROM public.fabric_rolls WHERE id = v_roll_id;
        END IF;

        SELECT * INTO v_roll FROM public.fabric_rolls WHERE id = v_roll_id FOR UPDATE;
        IF v_roll.id IS NULL OR v_roll.variant_id <> p_variant_id OR v_roll.location_id <> p_location_id THEN
            RAISE EXCEPTION 'That roll does not hold this fabric at this location';
        END IF;
        IF p_quantity < 0 AND v_roll.remaining_length - v_roll.reserved_length + p_quantity < 0 THEN
            RAISE EXCEPTION 'Roll % has only % m available', v_roll.roll_code,
                trim_scale(v_roll.remaining_length - v_roll.reserved_length) USING ERRCODE = 'P0001';
        END IF;
        UPDATE public.fabric_rolls SET remaining_length = remaining_length + p_quantity WHERE id = v_roll_id;
    ELSIF v_roll_id IS NOT NULL THEN
        RAISE EXCEPTION 'Only fabric is stocked on rolls';
    END IF;

    INSERT INTO public.stock_movements (
        branch_id, location_id, variant_id, quantity, movement_type, channel,
        reference_type, reference_id, unit_cost, reason, roll_id
    ) VALUES (
        v_balance.branch_id, p_location_id, p_variant_id, p_quantity, p_movement_type, p_channel,
        p_reference_type, p_reference_id, p_unit_cost, p_reason, v_roll_id
    );

    UPDATE public.stock_balances
    SET on_hand = on_hand + p_quantity, updated_at = now()
    WHERE location_id = p_location_id AND variant_id = p_variant_id
    RETURNING * INTO v_balance;

    RETURN v_balance;
END;
$$;

REVOKE ALL ON FUNCTION public.post_stock_movement(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT, UUID, NUMERIC, TEXT, UUID)
    FROM PUBLIC, anon, authenticated;

-- Existing fabric stock (from before rolls) becomes one roll per item and location
DO $$
DECLARE
    b RECORD;
    v_roll UUID;
BEGIN
    FOR b IN
        SELECT sb.* FROM public.stock_balances sb
        JOIN public.product_variants v ON v.id = sb.variant_id
        JOIN public.product_styles s ON s.id = v.style_id
        WHERE s.unit = 'meter' AND sb.on_hand > 0
          AND NOT EXISTS (SELECT 1 FROM public.fabric_rolls r WHERE r.variant_id = sb.variant_id AND r.location_id = sb.location_id)
    LOOP
        INSERT INTO public.fabric_rolls (variant_id, branch_id, location_id, roll_code, initial_length, remaining_length,
                                         unit_cost, notes)
        VALUES (b.variant_id, b.branch_id, b.location_id, public.next_roll_code(), b.on_hand, b.on_hand,
                (SELECT unit_cost FROM public.variant_costs WHERE variant_id = b.variant_id), 'Created from existing stock')
        RETURNING id INTO v_roll;
        INSERT INTO public.barcodes (code, variant_id, roll_id)
        SELECT roll_code, variant_id, id FROM public.fabric_rolls WHERE id = v_roll;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- Staff operations
-- ---------------------------------------------------------------------
-- Receive a new roll. Input: variant_id, length, width_cm, shade_lot,
-- unit_cost, roll_code (optional; scanned supplier code), location_id,
-- notes, request_id
CREATE OR REPLACE FUNCTION public.receive_fabric_roll(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_request_id UUID := NULLIF(p->>'request_id', '')::uuid;
    v_existing JSONB;
    v_variant UUID := NULLIF(p->>'variant_id', '')::uuid;
    v_location UUID := NULLIF(p->>'location_id', '')::uuid;
    v_length NUMERIC := NULLIF(p->>'length', '')::numeric;
    v_code TEXT := NULLIF(upper(trim(COALESCE(p->>'roll_code', ''))), '');
    v_branch UUID;
    v_roll public.fabric_rolls;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can receive stock' USING ERRCODE = '42501';
    END IF;

    -- A retried request returns the first result before anything is re-checked
    v_existing := public.idempotency_begin(v_request_id, 'receive_fabric_roll');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id
                   WHERE v.id = v_variant AND s.unit = 'meter') THEN
        RAISE EXCEPTION 'Choose a fabric item';
    END IF;
    IF v_length IS NULL OR v_length <= 0 OR v_length <> round(v_length, 2) THEN
        RAISE EXCEPTION 'Enter the roll length in meters (up to 2 decimals)';
    END IF;
    IF v_code IS NOT NULL AND EXISTS (SELECT 1 FROM public.barcodes WHERE code = v_code) THEN
        RAISE EXCEPTION 'Code % is already used', v_code;
    END IF;

    IF v_location IS NULL THEN
        SELECT id INTO v_location FROM public.locations
        WHERE branch_id = public.default_branch_id() AND kind = 'shop_floor' AND active
        ORDER BY created_at LIMIT 1;
    END IF;
    SELECT branch_id INTO v_branch FROM public.locations WHERE id = v_location;
    IF NOT public.is_branch_member(v_branch) THEN
        RAISE EXCEPTION 'Not a member of this branch' USING ERRCODE = '42501';
    END IF;

    PERFORM public.lock_stock_balance(v_location, v_variant);

    INSERT INTO public.fabric_rolls (variant_id, branch_id, location_id, roll_code, width_cm, shade_lot,
                                     initial_length, remaining_length, unit_cost, notes)
    VALUES (v_variant, v_branch, v_location, COALESCE(v_code, public.next_roll_code()),
            NULLIF(p->>'width_cm', '')::numeric, NULLIF(trim(p->>'shade_lot'), ''),
            v_length, 0, NULLIF(p->>'unit_cost', '')::numeric, NULLIF(trim(p->>'notes'), ''))
    RETURNING * INTO v_roll;

    INSERT INTO public.barcodes (code, variant_id, roll_id) VALUES (v_roll.roll_code, v_variant, v_roll.id);

    PERFORM public.post_stock_movement(v_location, v_variant, v_length, 'receive', 'pos', 'fabric_roll', v_roll.id,
                                       NULLIF(p->>'unit_cost', '')::numeric, 'Roll received', v_roll.id);

    SELECT * INTO v_roll FROM public.fabric_rolls WHERE id = v_roll.id;
    RETURN public.idempotency_finish(v_request_id, to_jsonb(v_roll));
END;
$$;

-- Waste, recount or damage on one roll (negative or positive)
CREATE OR REPLACE FUNCTION public.adjust_fabric_roll(
    p_roll_id UUID,
    p_quantity NUMERIC,
    p_reason TEXT,
    p_movement_type TEXT DEFAULT 'waste',
    p_request_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing JSONB;
    v_roll public.fabric_rolls;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can adjust stock' USING ERRCODE = '42501';
    END IF;
    IF p_movement_type NOT IN ('waste', 'adjust', 'count') THEN
        RAISE EXCEPTION 'Invalid adjustment type: %', p_movement_type;
    END IF;
    IF COALESCE(trim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required';
    END IF;
    IF p_quantity = 0 OR p_quantity <> round(p_quantity, 2) THEN
        RAISE EXCEPTION 'Enter a length in meters (up to 2 decimals)';
    END IF;

    SELECT * INTO v_roll FROM public.fabric_rolls WHERE id = p_roll_id;
    IF v_roll.id IS NULL OR NOT public.is_branch_member(v_roll.branch_id) THEN
        RAISE EXCEPTION 'Roll not found';
    END IF;

    v_existing := public.idempotency_begin(p_request_id, 'adjust_fabric_roll');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    PERFORM public.post_stock_movement(v_roll.location_id, v_roll.variant_id, p_quantity, p_movement_type, 'pos',
                                       'fabric_roll', v_roll.id, NULL, trim(p_reason), v_roll.id);

    SELECT * INTO v_roll FROM public.fabric_rolls WHERE id = p_roll_id;
    RETURN public.idempotency_finish(p_request_id, to_jsonb(v_roll));
END;
$$;

REVOKE ALL ON FUNCTION public.receive_fabric_roll(JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.adjust_fabric_roll(UUID, NUMERIC, TEXT, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.receive_fabric_roll(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.adjust_fabric_roll(UUID, NUMERIC, TEXT, TEXT, UUID) TO authenticated;

-- Roll barcodes are managed with their roll: item-level barcode edits
-- (save_style replaces an item's barcode) must never remove them.
CREATE OR REPLACE FUNCTION public.keep_roll_barcodes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.roll_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.fabric_rolls WHERE id = OLD.roll_id) THEN
        RETURN NULL;  -- skip the delete
    END IF;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trigger_keep_roll_barcodes ON public.barcodes;
CREATE TRIGGER trigger_keep_roll_barcodes
    BEFORE DELETE ON public.barcodes
    FOR EACH ROW EXECUTE FUNCTION public.keep_roll_barcodes();
