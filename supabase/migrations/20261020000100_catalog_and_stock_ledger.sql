-- =====================================================================
-- Catalog (styles + variants) and stock ledger
--
--   * product_styles: what the customer recognises (design, brand, kind)
--   * product_variants: what is sold and counted (size / color / fit, SKU)
--   * barcodes: one table so a code is unique across variants (and fabric
--     rolls later)
--   * variant_costs: kept apart so cashiers never see cost prices
--   * stock_balances / stock_movements / stock_reservations: one stock pool
--     shared by the POS and the website. Balances change only through
--     ledger functions; movements are append-only.
--   * idempotency_keys: a retried request returns the first result
--   * public_catalog: the only catalog data the website (anon) can read
--
-- Legacy `products` stay in place until the app switches over; each legacy
-- product is copied to a style + default variant + opening stock.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Size schemes
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.size_schemes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    sizes TEXT[] NOT NULL CHECK (cardinality(sizes) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.size_schemes (code, name, sizes) VALUES
    ('LETTER', 'Letter sizes', ARRAY['XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL']),
    ('CHEST', 'Chest sizes (inches)', ARRAY['36', '38', '40', '42', '44', '46', '48']),
    ('WAIST', 'Waist sizes (inches)', ARRAY['28', '30', '32', '34', '36', '38', '40', '42', '44']),
    ('FREE', 'One size', ARRAY['Free size'])
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------------
-- Styles and variants
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.product_styles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('garment', 'pack', 'fabric', 'service')),
    category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
    brand TEXT,
    material TEXT,
    season TEXT,
    design_code TEXT,
    description TEXT,
    size_scheme_id UUID REFERENCES public.size_schemes(id) ON DELETE SET NULL,
    -- piece (garment), set (pack), meter (fabric), job (service)
    unit TEXT NOT NULL DEFAULT 'piece' CHECK (unit IN ('piece', 'set', 'meter', 'job')),
    track_inventory BOOLEAN NOT NULL DEFAULT true,
    taxable BOOLEAN NOT NULL DEFAULT true,
    active BOOLEAN NOT NULL DEFAULT true,
    -- Website
    published BOOLEAN NOT NULL DEFAULT false,
    slug TEXT UNIQUE CHECK (slug IS NULL OR slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    web_title TEXT,
    web_description TEXT,
    created_by UUID DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT product_styles_unit_matches_kind CHECK (
        (kind = 'garment' AND unit = 'piece') OR
        (kind = 'pack' AND unit = 'set') OR
        (kind = 'fabric' AND unit = 'meter') OR
        (kind = 'service' AND unit = 'job' AND track_inventory = false)
    ),
    CONSTRAINT product_styles_published_needs_slug CHECK (NOT published OR slug IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_product_styles_kind ON public.product_styles(kind);
CREATE INDEX IF NOT EXISTS idx_product_styles_published ON public.product_styles(published) WHERE published;
CREATE INDEX IF NOT EXISTS idx_product_styles_search ON public.product_styles
    USING gin (to_tsvector('simple', coalesce(name, '') || ' ' || coalesce(code, '') || ' ' || coalesce(brand, '')));

CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    style_id UUID NOT NULL REFERENCES public.product_styles(id) ON DELETE CASCADE,
    sku TEXT NOT NULL UNIQUE CHECK (length(trim(sku)) > 0),
    size TEXT,
    color TEXT,
    fit TEXT,
    -- Price per unit of the style (per piece, per set or per meter)
    price NUMERIC(14,2) NOT NULL CHECK (price >= 0),
    compare_at_price NUMERIC(14,2) CHECK (compare_at_price IS NULL OR compare_at_price >= 0),
    min_stock NUMERIC(18,6) NOT NULL DEFAULT 0 CHECK (min_stock >= 0),
    active BOOLEAN NOT NULL DEFAULT true,
    published BOOLEAN NOT NULL DEFAULT true,
    legacy_product_id UUID UNIQUE REFERENCES public.products(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_variants_options ON public.product_variants
    (style_id, coalesce(size, ''), coalesce(color, ''), coalesce(fit, ''));
CREATE INDEX IF NOT EXISTS idx_product_variants_style ON public.product_variants(style_id);

CREATE TABLE IF NOT EXISTS public.variant_costs (
    variant_id UUID PRIMARY KEY REFERENCES public.product_variants(id) ON DELETE CASCADE,
    unit_cost NUMERIC(14,4) NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.barcodes (
    code TEXT PRIMARY KEY CHECK (length(trim(code)) > 0 AND code = trim(code)),
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_barcodes_variant ON public.barcodes(variant_id);

DROP TRIGGER IF EXISTS update_product_styles_updated_at ON public.product_styles;
CREATE TRIGGER update_product_styles_updated_at BEFORE UPDATE ON public.product_styles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_product_variants_updated_at ON public.product_variants;
CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON public.product_variants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_variant_costs_updated_at ON public.variant_costs;
CREATE TRIGGER update_variant_costs_updated_at BEFORE UPDATE ON public.variant_costs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ---------------------------------------------------------------------
-- Stock ledger
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.stock_balances (
    location_id UUID NOT NULL REFERENCES public.locations(id) ON DELETE RESTRICT,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
    on_hand NUMERIC(18,6) NOT NULL DEFAULT 0 CHECK (on_hand >= 0),
    reserved NUMERIC(18,6) NOT NULL DEFAULT 0 CHECK (reserved >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (location_id, variant_id),
    CONSTRAINT stock_balances_reserved_le_on_hand CHECK (reserved <= on_hand)
);
CREATE INDEX IF NOT EXISTS idx_stock_balances_variant ON public.stock_balances(variant_id);
CREATE INDEX IF NOT EXISTS idx_stock_balances_branch ON public.stock_balances(branch_id);

CREATE TABLE IF NOT EXISTS public.stock_movements (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    branch_id UUID NOT NULL REFERENCES public.branches(id),
    location_id UUID NOT NULL REFERENCES public.locations(id),
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
    -- Signed: positive = into the location, negative = out of it
    quantity NUMERIC(18,6) NOT NULL CHECK (quantity <> 0),
    movement_type TEXT NOT NULL CHECK (movement_type IN (
        'opening', 'receive', 'sale', 'return', 'adjust', 'count', 'waste',
        'transfer_in', 'transfer_out', 'issue', 'conversion'
    )),
    channel TEXT NOT NULL DEFAULT 'pos' CHECK (channel IN ('pos', 'web', 'tailoring', 'system')),
    reference_type TEXT,
    reference_id UUID,
    unit_cost NUMERIC(14,4),
    reason TEXT,
    created_by UUID DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_stock_movements_variant ON public.stock_movements(variant_id, created_at);
CREATE INDEX IF NOT EXISTS idx_stock_movements_reference ON public.stock_movements(reference_type, reference_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_branch_time ON public.stock_movements(branch_id, created_at);

CREATE TABLE IF NOT EXISTS public.stock_reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id UUID NOT NULL REFERENCES public.branches(id),
    location_id UUID NOT NULL REFERENCES public.locations(id),
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
    quantity NUMERIC(18,6) NOT NULL CHECK (quantity > 0),
    channel TEXT NOT NULL CHECK (channel IN ('pos', 'web', 'tailoring')),
    reference_type TEXT,
    reference_id UUID,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'consumed', 'released', 'expired')),
    expires_at TIMESTAMPTZ,
    created_by UUID DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_stock_reservations_active ON public.stock_reservations(variant_id, location_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_stock_reservations_expiry ON public.stock_reservations(expires_at) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_stock_reservations_reference ON public.stock_reservations(reference_type, reference_id);

-- Movements are history: never edited or deleted
CREATE OR REPLACE FUNCTION public.prevent_ledger_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION '% rows cannot be changed or deleted; post a correcting entry instead', TG_TABLE_NAME
        USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS trigger_stock_movements_append_only ON public.stock_movements;
CREATE TRIGGER trigger_stock_movements_append_only
    BEFORE UPDATE OR DELETE ON public.stock_movements
    FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();

-- ---------------------------------------------------------------------
-- Idempotency
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.idempotency_keys (
    key UUID PRIMARY KEY,
    operation TEXT NOT NULL,
    user_id UUID DEFAULT auth.uid(),
    result JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Returns the stored result when this request was already completed, NULL
-- when the caller should do the work (and must call idempotency_finish).
-- A concurrent duplicate waits on the first request's row lock.
CREATE OR REPLACE FUNCTION public.idempotency_begin(p_key UUID, p_operation TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    existing public.idempotency_keys;
BEGIN
    IF p_key IS NULL THEN
        RETURN NULL;
    END IF;

    INSERT INTO public.idempotency_keys (key, operation) VALUES (p_key, p_operation)
    ON CONFLICT (key) DO NOTHING;
    IF FOUND THEN
        RETURN NULL;
    END IF;

    SELECT * INTO existing FROM public.idempotency_keys WHERE key = p_key FOR UPDATE;
    IF existing.operation <> p_operation THEN
        RAISE EXCEPTION 'Request id already used for a different operation';
    END IF;
    IF existing.result IS NULL THEN
        RAISE EXCEPTION 'Request is still being processed';
    END IF;
    RETURN existing.result;
END;
$$;

CREATE OR REPLACE FUNCTION public.idempotency_finish(p_key UUID, p_result JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_key IS NOT NULL THEN
        UPDATE public.idempotency_keys SET result = p_result WHERE key = p_key;
    END IF;
    RETURN p_result;
END;
$$;

-- ---------------------------------------------------------------------
-- Internal ledger primitives (not callable from the API)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.lock_stock_balance(p_location_id UUID, p_variant_id UUID)
RETURNS public.stock_balances
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_balance public.stock_balances;
BEGIN
    INSERT INTO public.stock_balances (location_id, variant_id, branch_id)
    SELECT p_location_id, p_variant_id, l.branch_id FROM public.locations l WHERE l.id = p_location_id
    ON CONFLICT (location_id, variant_id) DO NOTHING;

    SELECT * INTO v_balance FROM public.stock_balances
    WHERE location_id = p_location_id AND variant_id = p_variant_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown location %', p_location_id;
    END IF;
    RETURN v_balance;
END;
$$;

-- Posts one movement and updates the balance. Outgoing movements must fit in
-- the available quantity (on hand - reserved) unless p_from_reservation is
-- set, in which case the caller has already released the matching reservation.
CREATE OR REPLACE FUNCTION public.post_stock_movement(
    p_location_id UUID,
    p_variant_id UUID,
    p_quantity NUMERIC,
    p_movement_type TEXT,
    p_channel TEXT DEFAULT 'pos',
    p_reference_type TEXT DEFAULT NULL,
    p_reference_id UUID DEFAULT NULL,
    p_unit_cost NUMERIC DEFAULT NULL,
    p_reason TEXT DEFAULT NULL
)
RETURNS public.stock_balances
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_balance public.stock_balances;
    v_name TEXT;
BEGIN
    IF p_quantity = 0 THEN
        RAISE EXCEPTION 'Quantity cannot be zero';
    END IF;

    v_balance := public.lock_stock_balance(p_location_id, p_variant_id);

    IF p_quantity < 0 AND v_balance.on_hand - v_balance.reserved + p_quantity < 0 THEN
        SELECT s.name || COALESCE(' ' || v.size, '') || COALESCE(' ' || v.color, '') INTO v_name
        FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id
        WHERE v.id = p_variant_id;
        RAISE EXCEPTION 'Not enough stock for "%" (available: %, needed: %)',
            v_name, trim_scale(v_balance.on_hand - v_balance.reserved), trim_scale(-p_quantity)
            USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.stock_movements (
        branch_id, location_id, variant_id, quantity, movement_type, channel,
        reference_type, reference_id, unit_cost, reason
    ) VALUES (
        v_balance.branch_id, p_location_id, p_variant_id, p_quantity, p_movement_type, p_channel,
        p_reference_type, p_reference_id, p_unit_cost, p_reason
    );

    UPDATE public.stock_balances
    SET on_hand = on_hand + p_quantity, updated_at = now()
    WHERE location_id = p_location_id AND variant_id = p_variant_id
    RETURNING * INTO v_balance;

    RETURN v_balance;
END;
$$;

REVOKE ALL ON FUNCTION public.idempotency_begin(UUID, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.idempotency_finish(UUID, JSONB) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.lock_stock_balance(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.post_stock_movement(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT, UUID, NUMERIC, TEXT)
    FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- Staff stock operations
-- ---------------------------------------------------------------------
-- Manual adjustment (opening stock, count correction, damage, ...)
CREATE OR REPLACE FUNCTION public.adjust_stock(
    p_variant_id UUID,
    p_location_id UUID,
    p_quantity NUMERIC,
    p_reason TEXT,
    p_movement_type TEXT DEFAULT 'adjust',
    p_request_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing JSONB;
    v_branch UUID;
    v_balance public.stock_balances;
    v_unit TEXT;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can adjust stock' USING ERRCODE = '42501';
    END IF;
    IF p_movement_type NOT IN ('opening', 'adjust', 'count', 'waste') THEN
        RAISE EXCEPTION 'Invalid adjustment type: %', p_movement_type;
    END IF;
    IF COALESCE(trim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required for stock adjustments';
    END IF;

    SELECT branch_id INTO v_branch FROM public.locations WHERE id = p_location_id;
    IF NOT public.is_branch_member(v_branch) THEN
        RAISE EXCEPTION 'Not a member of this branch' USING ERRCODE = '42501';
    END IF;

    SELECT s.unit INTO v_unit FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id
    WHERE v.id = p_variant_id;
    IF v_unit IS NULL THEN
        RAISE EXCEPTION 'Variant not found';
    END IF;
    IF v_unit <> 'meter' AND p_quantity <> trunc(p_quantity) THEN
        RAISE EXCEPTION 'Whole quantities only for % items', v_unit;
    END IF;

    v_existing := public.idempotency_begin(p_request_id, 'adjust_stock');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    v_balance := public.post_stock_movement(
        p_location_id, p_variant_id, p_quantity, p_movement_type, 'pos', 'adjustment', NULL, NULL, trim(p_reason)
    );

    RETURN public.idempotency_finish(p_request_id, jsonb_build_object(
        'variant_id', p_variant_id,
        'location_id', p_location_id,
        'on_hand', v_balance.on_hand,
        'reserved', v_balance.reserved
    ));
END;
$$;

-- Hold stock for an online order, a tailoring job or a POS draft
CREATE OR REPLACE FUNCTION public.reserve_stock(
    p_variant_id UUID,
    p_location_id UUID,
    p_quantity NUMERIC,
    p_channel TEXT,
    p_reference_type TEXT DEFAULT NULL,
    p_reference_id UUID DEFAULT NULL,
    p_expires_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS public.stock_reservations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_balance public.stock_balances;
    v_reservation public.stock_reservations;
BEGIN
    IF NOT public.is_staff() THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'Reservation quantity must be greater than zero';
    END IF;

    v_balance := public.lock_stock_balance(p_location_id, p_variant_id);
    IF NOT public.is_branch_member(v_balance.branch_id) THEN
        RAISE EXCEPTION 'Not a member of this branch' USING ERRCODE = '42501';
    END IF;
    IF v_balance.on_hand - v_balance.reserved < p_quantity THEN
        RAISE EXCEPTION 'Not enough stock to reserve (available: %, needed: %)',
            trim_scale(v_balance.on_hand - v_balance.reserved), trim_scale(p_quantity);
    END IF;

    UPDATE public.stock_balances SET reserved = reserved + p_quantity, updated_at = now()
    WHERE location_id = p_location_id AND variant_id = p_variant_id;

    INSERT INTO public.stock_reservations (
        branch_id, location_id, variant_id, quantity, channel, reference_type, reference_id, expires_at
    ) VALUES (
        v_balance.branch_id, p_location_id, p_variant_id, p_quantity, p_channel, p_reference_type, p_reference_id, p_expires_at
    )
    RETURNING * INTO v_reservation;

    RETURN v_reservation;
END;
$$;

-- Internal: close a reservation and give the quantity back to "available"
CREATE OR REPLACE FUNCTION public.close_reservation(p_reservation_id UUID, p_status TEXT)
RETURNS public.stock_reservations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_reservation public.stock_reservations;
BEGIN
    SELECT * INTO v_reservation FROM public.stock_reservations WHERE id = p_reservation_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation not found';
    END IF;
    IF v_reservation.status <> 'active' THEN
        RETURN v_reservation;  -- already closed: closing twice is a no-op
    END IF;

    PERFORM public.lock_stock_balance(v_reservation.location_id, v_reservation.variant_id);
    UPDATE public.stock_balances SET reserved = reserved - v_reservation.quantity, updated_at = now()
    WHERE location_id = v_reservation.location_id AND variant_id = v_reservation.variant_id;

    UPDATE public.stock_reservations SET status = p_status, closed_at = now()
    WHERE id = p_reservation_id
    RETURNING * INTO v_reservation;
    RETURN v_reservation;
END;
$$;

REVOKE ALL ON FUNCTION public.close_reservation(UUID, TEXT) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.release_reservation(p_reservation_id UUID)
RETURNS public.stock_reservations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_branch UUID;
BEGIN
    SELECT branch_id INTO v_branch FROM public.stock_reservations WHERE id = p_reservation_id;
    IF NOT public.is_branch_member(v_branch) THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
    RETURN public.close_reservation(p_reservation_id, 'released');
END;
$$;

-- Releases every expired reservation. Run on a schedule (pg_cron) and before
-- availability checks on the website.
CREATE OR REPLACE FUNCTION public.expire_stock_reservations()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
    n INTEGER := 0;
BEGIN
    FOR r IN
        SELECT id FROM public.stock_reservations
        WHERE status = 'active' AND expires_at IS NOT NULL AND expires_at <= now()
        ORDER BY variant_id, location_id, id
    LOOP
        PERFORM public.close_reservation(r.id, 'expired');
        n := n + 1;
    END LOOP;
    RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.adjust_stock(UUID, UUID, NUMERIC, TEXT, TEXT, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reserve_stock(UUID, UUID, NUMERIC, TEXT, TEXT, UUID, TIMESTAMPTZ) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.release_reservation(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.expire_stock_reservations() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.adjust_stock(UUID, UUID, NUMERIC, TEXT, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_stock(UUID, UUID, NUMERIC, TEXT, TEXT, UUID, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_reservation(UUID) TO authenticated;

-- ---------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------
ALTER TABLE public.size_schemes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_styles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.variant_costs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.barcodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.idempotency_keys ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['size_schemes', 'product_styles', 'product_variants', 'barcodes']
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_select_staff', t);
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_write_back_office', t);
        EXECUTE format(
            'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (public.is_staff())',
            t || '_select_staff', t);
        EXECUTE format(
            'CREATE POLICY %I ON public.%I FOR ALL TO authenticated
                USING (public.has_app_role(ARRAY[''admin'', ''manager'']))
                WITH CHECK (public.has_app_role(ARRAY[''admin'', ''manager'']))',
            t || '_write_back_office', t);
    END LOOP;
END $$;

-- Cost prices: back office only
DROP POLICY IF EXISTS "variant_costs_back_office" ON public.variant_costs;
CREATE POLICY "variant_costs_back_office" ON public.variant_costs
    FOR ALL TO authenticated
    USING (public.has_app_role(ARRAY['admin', 'manager']))
    WITH CHECK (public.has_app_role(ARRAY['admin', 'manager']));

-- Stock: read by branch members, written only by the ledger functions
DROP POLICY IF EXISTS "stock_balances_select_members" ON public.stock_balances;
CREATE POLICY "stock_balances_select_members" ON public.stock_balances
    FOR SELECT TO authenticated USING (public.is_branch_member(branch_id));

DROP POLICY IF EXISTS "stock_movements_select_back_office" ON public.stock_movements;
CREATE POLICY "stock_movements_select_back_office" ON public.stock_movements
    FOR SELECT TO authenticated
    USING (public.has_app_role(ARRAY['admin', 'manager']) AND public.is_branch_member(branch_id));

DROP POLICY IF EXISTS "stock_reservations_select_members" ON public.stock_reservations;
CREATE POLICY "stock_reservations_select_members" ON public.stock_reservations
    FOR SELECT TO authenticated USING (public.is_branch_member(branch_id));

-- idempotency_keys: no policies (internal only)

-- ---------------------------------------------------------------------
-- Staff-facing stock view
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW public.variant_stock
WITH (security_invoker = true) AS
SELECT
    b.variant_id,
    b.location_id,
    b.branch_id,
    b.on_hand,
    b.reserved,
    b.on_hand - b.reserved AS available
FROM public.stock_balances b;

-- ---------------------------------------------------------------------
-- Public catalog for the website (anon). Runs with the view owner's rights
-- on purpose and exposes only safe columns of published, active items.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW public.public_catalog
WITH (security_invoker = false) AS
SELECT
    s.id AS style_id,
    s.slug,
    COALESCE(s.web_title, s.name) AS title,
    s.web_description AS description,
    s.kind,
    s.brand,
    s.material,
    s.season,
    c.name AS category,
    v.id AS variant_id,
    v.sku,
    v.size,
    v.color,
    v.fit,
    v.price,
    v.compare_at_price,
    s.unit,
    CASE
        WHEN NOT s.track_inventory THEN 'in_stock'
        WHEN COALESCE(st.available, 0) <= 0 THEN 'out_of_stock'
        WHEN COALESCE(st.available, 0) <= GREATEST(v.min_stock, 2) THEN 'low_stock'
        ELSE 'in_stock'
    END AS stock_level
FROM public.product_styles s
JOIN public.product_variants v ON v.style_id = s.id
LEFT JOIN public.categories c ON c.id = s.category_id
LEFT JOIN LATERAL (
    SELECT SUM(b.on_hand - b.reserved) AS available
    FROM public.stock_balances b
    JOIN public.locations l ON l.id = b.location_id
    WHERE b.variant_id = v.id AND l.kind IN ('shop_floor', 'stockroom', 'online') AND l.active
) st ON true
WHERE s.published AND s.active AND v.published AND v.active AND s.kind <> 'service';

REVOKE ALL ON public.public_catalog FROM PUBLIC;
GRANT SELECT ON public.public_catalog TO anon, authenticated;

-- ---------------------------------------------------------------------
-- Copy legacy products: one style + default variant + opening stock each
-- ---------------------------------------------------------------------
DO $$
DECLARE
    p RECORD;
    v_style UUID;
    v_variant UUID;
    v_location UUID;
    v_kind TEXT;
BEGIN
    SELECT l.id INTO v_location
    FROM public.locations l JOIN public.branches b ON b.id = l.branch_id
    WHERE b.code = 'MAIN' AND l.code = 'FLOOR';

    FOR p IN
        SELECT pr.* FROM public.products pr
        WHERE NOT EXISTS (SELECT 1 FROM public.product_variants v WHERE v.legacy_product_id = pr.id)
    LOOP
        v_kind := CASE WHEN COALESCE(p.is_weight_based, false) THEN 'fabric' ELSE 'garment' END;

        INSERT INTO public.product_styles (code, name, kind, category_id, description, unit, track_inventory, taxable, active)
        VALUES (
            CASE WHEN EXISTS (SELECT 1 FROM public.product_styles WHERE code = p.sku)
                 THEN p.sku || '-' || substr(p.id::text, 1, 6) ELSE p.sku END,
            p.name, v_kind,
            (SELECT id FROM public.categories WHERE name = p.category),
            p.description,
            CASE WHEN v_kind = 'fabric' THEN 'meter' ELSE 'piece' END,
            COALESCE(p.track_inventory, true),
            COALESCE(p.taxable, true),
            COALESCE(p.active, true)
        )
        RETURNING id INTO v_style;

        INSERT INTO public.product_variants (style_id, sku, price, min_stock, active, legacy_product_id)
        VALUES (
            v_style, p.sku,
            CASE WHEN v_kind = 'fabric' THEN COALESCE(p.price_per_unit, p.price) ELSE p.price END,
            COALESCE(p.min_stock, 0), COALESCE(p.active, true), p.id
        )
        RETURNING id INTO v_variant;

        INSERT INTO public.variant_costs (variant_id, unit_cost) VALUES (v_variant, COALESCE(p.cost, 0));

        IF p.barcode IS NOT NULL AND trim(p.barcode) <> '' THEN
            INSERT INTO public.barcodes (code, variant_id) VALUES (trim(p.barcode), v_variant)
            ON CONFLICT (code) DO NOTHING;
        END IF;

        IF v_location IS NOT NULL AND COALESCE(p.stock, 0) > 0 AND COALESCE(p.track_inventory, true) THEN
            PERFORM public.post_stock_movement(
                v_location, v_variant, p.stock, 'opening', 'system', 'legacy_product', p.id, p.cost,
                'Copied from legacy product'
            );
        END IF;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- Website visitors (anon) get no table access at all, now or for tables
-- added later. They read only the public views granted explicitly.
-- ---------------------------------------------------------------------
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;
GRANT SELECT ON public.public_catalog TO anon;
