-- =====================================================================
-- In-house tailoring: core
--
--   * garment_types: what the shop stitches, with its measurement form,
--     default stitching charge and lead time
--   * wearer_profiles: the people measured (a customer may order for family)
--   * measurement_sets: versioned; every order item keeps a snapshot, so a
--     later re-measure never changes work already in progress
--   * tailoring_orders / tailoring_items (one garment each) / tailoring_charges
--   * tailoring_materials: fabric from store stock (reserved on a specific
--     roll, charged on the order) or brought by the customer (custody only:
--     no stock value, no fabric revenue)
--   * deposits and balance payments are ordinary payments against the order;
--     cash goes through the cashier's shift
-- =====================================================================

-- ---------------------------------------------------------------------
-- Garment types and measurement forms (inches)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.garment_types (
    code TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    -- [{ "key", "label", "required" }]
    fields JSONB NOT NULL,
    default_charge NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (default_charge >= 0),
    lead_days INTEGER NOT NULL DEFAULT 7 CHECK (lead_days >= 0),
    -- Typical fabric needed, in meters (a hint for the counter)
    fabric_meters NUMERIC(8,2),
    active BOOLEAN NOT NULL DEFAULT true,
    sort_order INTEGER NOT NULL DEFAULT 0
);

INSERT INTO public.garment_types (code, name, fields, default_charge, lead_days, fabric_meters, sort_order) VALUES
('SHALWAR_KAMEEZ', 'Shalwar kameez', '[
  {"key":"kameez_length","label":"Kameez length","required":true},
  {"key":"chest","label":"Chest","required":true},
  {"key":"waist","label":"Waist","required":true},
  {"key":"hip","label":"Hip / daman","required":true},
  {"key":"shoulder","label":"Shoulder","required":true},
  {"key":"sleeve","label":"Sleeve","required":true},
  {"key":"neck","label":"Neck / collar","required":true},
  {"key":"armhole","label":"Armhole"},
  {"key":"cuff","label":"Cuff"},
  {"key":"shalwar_length","label":"Shalwar length","required":true},
  {"key":"shalwar_bottom","label":"Shalwar bottom (paicha)","required":true}
]', 2500, 7, 4.5, 10),
('KURTA', 'Kurta', '[
  {"key":"length","label":"Length","required":true},
  {"key":"chest","label":"Chest","required":true},
  {"key":"waist","label":"Waist","required":true},
  {"key":"hip","label":"Hip / daman"},
  {"key":"shoulder","label":"Shoulder","required":true},
  {"key":"sleeve","label":"Sleeve","required":true},
  {"key":"neck","label":"Neck / collar","required":true},
  {"key":"armhole","label":"Armhole"}
]', 1800, 5, 2.75, 20),
('SHERWANI', 'Sherwani', '[
  {"key":"length","label":"Length","required":true},
  {"key":"chest","label":"Chest","required":true},
  {"key":"waist","label":"Waist","required":true},
  {"key":"hip","label":"Hip","required":true},
  {"key":"shoulder","label":"Shoulder","required":true},
  {"key":"sleeve","label":"Sleeve","required":true},
  {"key":"neck","label":"Neck","required":true},
  {"key":"armhole","label":"Armhole","required":true},
  {"key":"bicep","label":"Bicep"}
]', 12000, 14, 3.5, 30),
('SUIT_COAT', 'Suit coat', '[
  {"key":"length","label":"Length","required":true},
  {"key":"chest","label":"Chest","required":true},
  {"key":"waist","label":"Waist","required":true},
  {"key":"hip","label":"Hip","required":true},
  {"key":"shoulder","label":"Shoulder","required":true},
  {"key":"sleeve","label":"Sleeve","required":true},
  {"key":"back_width","label":"Back width"},
  {"key":"bicep","label":"Bicep"}
]', 9000, 14, 2, 40),
('WAISTCOAT', 'Waistcoat', '[
  {"key":"length","label":"Length","required":true},
  {"key":"chest","label":"Chest","required":true},
  {"key":"waist","label":"Waist","required":true},
  {"key":"shoulder","label":"Shoulder"}
]', 3500, 7, 1.2, 50),
('TROUSERS', 'Trousers', '[
  {"key":"waist","label":"Waist","required":true},
  {"key":"hip","label":"Hip","required":true},
  {"key":"length","label":"Length","required":true},
  {"key":"inseam","label":"Inseam","required":true},
  {"key":"thigh","label":"Thigh"},
  {"key":"knee","label":"Knee"},
  {"key":"bottom","label":"Bottom","required":true}
]', 2000, 5, 1.3, 60),
('SHIRT', 'Shirt', '[
  {"key":"length","label":"Length","required":true},
  {"key":"chest","label":"Chest","required":true},
  {"key":"waist","label":"Waist","required":true},
  {"key":"shoulder","label":"Shoulder","required":true},
  {"key":"sleeve","label":"Sleeve","required":true},
  {"key":"neck","label":"Neck / collar","required":true},
  {"key":"cuff","label":"Cuff"}
]', 1500, 5, 2, 70),
('ALTERATION', 'Alteration', '[]', 500, 2, NULL, 90)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------------
-- Wearers and measurements
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wearer_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    relation TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wearer_profiles_customer ON public.wearer_profiles(customer_id);

CREATE TABLE IF NOT EXISTS public.measurement_sets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wearer_id UUID NOT NULL REFERENCES public.wearer_profiles(id) ON DELETE CASCADE,
    garment_type TEXT NOT NULL REFERENCES public.garment_types(code),
    -- { field key: number (inches) }
    measurements JSONB NOT NULL,
    fit_preference TEXT CHECK (fit_preference IS NULL OR fit_preference IN ('slim', 'regular', 'loose')),
    notes TEXT,
    taken_by UUID DEFAULT auth.uid(),
    taken_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_measurement_sets_wearer ON public.measurement_sets(wearer_id, garment_type, taken_at DESC);

-- Measurement history is kept: a re-measure is a new set
DROP TRIGGER IF EXISTS trigger_measurement_sets_append_only ON public.measurement_sets;
CREATE TRIGGER trigger_measurement_sets_append_only
    BEFORE UPDATE OR DELETE ON public.measurement_sets
    FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();

-- ---------------------------------------------------------------------
-- Orders
-- ---------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS public.tailoring_order_no_seq START 1;
REVOKE ALL ON SEQUENCE public.tailoring_order_no_seq FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.tailoring_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_no TEXT NOT NULL UNIQUE,
    request_id UUID UNIQUE,
    branch_id UUID NOT NULL REFERENCES public.branches(id),
    location_id UUID NOT NULL REFERENCES public.locations(id),
    customer_id UUID NOT NULL REFERENCES public.customers(id),
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN (
        'draft', 'confirmed', 'in_progress', 'ready', 'partially_delivered', 'delivered', 'cancelled')),
    promised_date DATE,
    fitting_date DATE,
    notes TEXT,
    created_by UUID DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    confirmed_at TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    cancel_reason TEXT
);
CREATE INDEX IF NOT EXISTS idx_tailoring_orders_branch_status ON public.tailoring_orders(branch_id, status);
CREATE INDEX IF NOT EXISTS idx_tailoring_orders_customer ON public.tailoring_orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_tailoring_orders_promised ON public.tailoring_orders(promised_date) WHERE status NOT IN ('delivered', 'cancelled');

CREATE TABLE IF NOT EXISTS public.tailoring_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.tailoring_orders(id) ON DELETE CASCADE,
    line_no INTEGER NOT NULL,
    garment_type TEXT NOT NULL REFERENCES public.garment_types(code),
    wearer_id UUID NOT NULL REFERENCES public.wearer_profiles(id),
    measurement_set_id UUID REFERENCES public.measurement_sets(id),
    -- Copy taken when the item is created; never changes afterwards
    measurements_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
    fit_preference TEXT,
    design_notes TEXT,
    status TEXT NOT NULL DEFAULT 'awaiting' CHECK (status IN (
        'awaiting', 'cutting', 'stitching', 'fitting', 'finishing', 'quality_check', 'ready', 'delivered', 'cancelled')),
    assigned_tailor UUID REFERENCES public.users(id),
    due_date DATE,
    delivered_at TIMESTAMPTZ,
    UNIQUE (order_id, line_no)
);
CREATE INDEX IF NOT EXISTS idx_tailoring_items_tailor ON public.tailoring_items(assigned_tailor, status);

CREATE TABLE IF NOT EXISTS public.tailoring_charges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.tailoring_orders(id) ON DELETE CASCADE,
    item_id UUID REFERENCES public.tailoring_items(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('stitching', 'fabric', 'lining', 'buttons', 'embroidery', 'alteration', 'other')),
    description TEXT NOT NULL,
    amount NUMERIC(14,2) NOT NULL CHECK (amount >= 0),
    created_by UUID DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tailoring_charges_order ON public.tailoring_charges(order_id);

CREATE TABLE IF NOT EXISTS public.tailoring_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.tailoring_orders(id) ON DELETE CASCADE,
    item_id UUID REFERENCES public.tailoring_items(id) ON DELETE CASCADE,
    source TEXT NOT NULL CHECK (source IN ('store', 'customer')),
    variant_id UUID REFERENCES public.product_variants(id),
    roll_id UUID REFERENCES public.fabric_rolls(id),
    description TEXT NOT NULL,
    quantity NUMERIC(18,6) NOT NULL CHECK (quantity > 0),
    unit TEXT NOT NULL DEFAULT 'meter',
    -- Store fabric: reserved -> issued; customer fabric: received -> issued -> returned (leftovers)
    status TEXT NOT NULL CHECK (status IN ('planned', 'reserved', 'received', 'issued', 'returned', 'released')),
    returned_quantity NUMERIC(18,6) NOT NULL DEFAULT 0 CHECK (returned_quantity >= 0),
    reservation_id UUID REFERENCES public.stock_reservations(id),
    charge_id UUID REFERENCES public.tailoring_charges(id),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT tailoring_materials_store_has_variant CHECK (source = 'customer' OR variant_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_tailoring_materials_order ON public.tailoring_materials(order_id);

CREATE TABLE IF NOT EXISTS public.material_custody_events (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    material_id UUID NOT NULL REFERENCES public.tailoring_materials(id) ON DELETE CASCADE,
    event TEXT NOT NULL CHECK (event IN ('received', 'reserved', 'issued', 'returned', 'released')),
    quantity NUMERIC(18,6) NOT NULL,
    note TEXT,
    created_by UUID DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_material_custody_events_material ON public.material_custody_events(material_id);

DROP TRIGGER IF EXISTS trigger_material_custody_append_only ON public.material_custody_events;
CREATE TRIGGER trigger_material_custody_append_only
    BEFORE UPDATE OR DELETE ON public.material_custody_events
    FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();

-- Payments against an order (deposits, balance, refunds)
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS tailoring_order_id UUID REFERENCES public.tailoring_orders(id);
CREATE INDEX IF NOT EXISTS idx_payments_tailoring_order ON public.payments(tailoring_order_id) WHERE tailoring_order_id IS NOT NULL;

-- Stock reservations can now hold a specific roll's length
ALTER TABLE public.fabric_rolls DROP CONSTRAINT IF EXISTS fabric_rolls_reserved_le_remaining;
ALTER TABLE public.fabric_rolls ADD CONSTRAINT fabric_rolls_reserved_le_remaining CHECK (reserved_length <= remaining_length);

-- ---------------------------------------------------------------------
-- Row level security: counter staff and back office of the branch.
-- Tailors read their work only through tailor_queue() (no prices, phones).
-- ---------------------------------------------------------------------
ALTER TABLE public.garment_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wearer_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.measurement_sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tailoring_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tailoring_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tailoring_charges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tailoring_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.material_custody_events ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_counter_staff()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.has_app_role(ARRAY['admin', 'manager', 'cashier'])
$$;
REVOKE ALL ON FUNCTION public.is_counter_staff() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_counter_staff() TO authenticated;

DROP POLICY IF EXISTS "garment_types_select" ON public.garment_types;
DROP POLICY IF EXISTS "garment_types_write" ON public.garment_types;
CREATE POLICY "garment_types_select" ON public.garment_types FOR SELECT TO authenticated USING (public.is_staff());
CREATE POLICY "garment_types_write" ON public.garment_types FOR ALL TO authenticated
    USING (public.has_app_role(ARRAY['admin', 'manager'])) WITH CHECK (public.has_app_role(ARRAY['admin', 'manager']));

DROP POLICY IF EXISTS "wearer_profiles_counter" ON public.wearer_profiles;
CREATE POLICY "wearer_profiles_counter" ON public.wearer_profiles FOR ALL TO authenticated
    USING (public.is_counter_staff()) WITH CHECK (public.is_counter_staff());
DROP POLICY IF EXISTS "measurement_sets_select" ON public.measurement_sets;
CREATE POLICY "measurement_sets_select" ON public.measurement_sets FOR SELECT TO authenticated USING (public.is_counter_staff());

DROP POLICY IF EXISTS "tailoring_orders_select" ON public.tailoring_orders;
CREATE POLICY "tailoring_orders_select" ON public.tailoring_orders FOR SELECT TO authenticated
    USING (public.is_counter_staff() AND public.is_branch_member(branch_id));
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['tailoring_items', 'tailoring_charges', 'tailoring_materials']
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_select', t);
        EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated
            USING (EXISTS (SELECT 1 FROM public.tailoring_orders o WHERE o.id = order_id))', t || '_select', t);
    END LOOP;
END $$;
DROP POLICY IF EXISTS "material_custody_events_select" ON public.material_custody_events;
CREATE POLICY "material_custody_events_select" ON public.material_custody_events FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.tailoring_materials m WHERE m.id = material_id));

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
-- Total charged, paid (net of refunds) and balance of an order
CREATE OR REPLACE FUNCTION public.tailoring_order_totals(p_order_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'total', t.total,
        'paid', p.paid,
        'balance', t.total - p.paid)
    FROM (SELECT COALESCE(sum(amount), 0) AS total FROM public.tailoring_charges WHERE order_id = p_order_id) t,
         (SELECT COALESCE(sum(CASE WHEN direction = 'out' THEN -amount ELSE amount END), 0) AS paid
          FROM public.payments WHERE tailoring_order_id = p_order_id) p
$$;
REVOKE ALL ON FUNCTION public.tailoring_order_totals(UUID) FROM PUBLIC, anon, authenticated;

-- Required measurement keys that are missing or not positive numbers
CREATE OR REPLACE FUNCTION public.missing_measurements(p_garment_type TEXT, p_values JSONB)
RETURNS TEXT[]
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT COALESCE(array_agg(f->>'label' ORDER BY ord), ARRAY[]::text[])
    FROM public.garment_types g, jsonb_array_elements(g.fields) WITH ORDINALITY AS x(f, ord)
    WHERE g.code = p_garment_type
      AND COALESCE((f->>'required')::boolean, false)
      AND (jsonb_typeof(p_values->(f->>'key')) IS DISTINCT FROM 'number' OR (p_values->>(f->>'key'))::numeric <= 0)
$$;
REVOKE ALL ON FUNCTION public.missing_measurements(TEXT, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.missing_measurements(TEXT, JSONB) TO authenticated;

-- Reserve length on one roll (best fit when no roll is given)
CREATE OR REPLACE FUNCTION public.reserve_roll_length(
    p_variant_id UUID, p_location_id UUID, p_quantity NUMERIC, p_roll_id UUID,
    p_reference_type TEXT, p_reference_id UUID
)
RETURNS public.stock_reservations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_roll public.fabric_rolls;
    v_balance public.stock_balances;
    v_reservation public.stock_reservations;
    v_longest NUMERIC;
BEGIN
    v_balance := public.lock_stock_balance(p_location_id, p_variant_id);

    IF p_roll_id IS NULL THEN
        SELECT * INTO v_roll FROM public.fabric_rolls
        WHERE variant_id = p_variant_id AND location_id = p_location_id
          AND remaining_length - reserved_length >= p_quantity
        ORDER BY remaining_length - reserved_length, received_at, id
        LIMIT 1 FOR UPDATE;
        IF v_roll.id IS NULL THEN
            SELECT max(remaining_length - reserved_length) INTO v_longest FROM public.fabric_rolls
            WHERE variant_id = p_variant_id AND location_id = p_location_id;
            RAISE EXCEPTION 'No single roll has % m available (longest available piece: % m)',
                trim_scale(p_quantity), trim_scale(COALESCE(v_longest, 0)) USING ERRCODE = 'P0001';
        END IF;
    ELSE
        SELECT * INTO v_roll FROM public.fabric_rolls
        WHERE id = p_roll_id AND variant_id = p_variant_id AND location_id = p_location_id FOR UPDATE;
        IF v_roll.id IS NULL THEN
            RAISE EXCEPTION 'That roll does not hold this fabric here';
        END IF;
        IF v_roll.remaining_length - v_roll.reserved_length < p_quantity THEN
            RAISE EXCEPTION 'Roll % has only % m available', v_roll.roll_code,
                trim_scale(v_roll.remaining_length - v_roll.reserved_length) USING ERRCODE = 'P0001';
        END IF;
    END IF;

    UPDATE public.fabric_rolls SET reserved_length = reserved_length + p_quantity WHERE id = v_roll.id;
    UPDATE public.stock_balances SET reserved = reserved + p_quantity, updated_at = now()
    WHERE location_id = p_location_id AND variant_id = p_variant_id;

    INSERT INTO public.stock_reservations (branch_id, location_id, variant_id, quantity, channel, reference_type,
                                           reference_id, roll_id)
    VALUES (v_balance.branch_id, p_location_id, p_variant_id, p_quantity, 'tailoring', p_reference_type, p_reference_id,
            v_roll.id)
    RETURNING * INTO v_reservation;
    RETURN v_reservation;
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_roll_length(UUID, UUID, NUMERIC, UUID, TEXT, UUID) FROM PUBLIC, anon, authenticated;

-- Close a roll reservation: release it, or consume it (fabric issued to the job)
CREATE OR REPLACE FUNCTION public.close_roll_reservation(p_reservation_id UUID, p_consume BOOLEAN, p_reference_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_res public.stock_reservations;
BEGIN
    SELECT * INTO v_res FROM public.stock_reservations WHERE id = p_reservation_id FOR UPDATE;
    IF v_res.id IS NULL OR v_res.status <> 'active' THEN
        RETURN;
    END IF;
    PERFORM public.close_reservation(v_res.id, CASE WHEN p_consume THEN 'consumed' ELSE 'released' END);
    IF v_res.roll_id IS NOT NULL THEN
        UPDATE public.fabric_rolls SET reserved_length = reserved_length - v_res.quantity WHERE id = v_res.roll_id;
    END IF;
    IF p_consume THEN
        PERFORM public.post_stock_movement(v_res.location_id, v_res.variant_id, -v_res.quantity, 'issue', 'tailoring',
                                           'tailoring_order', p_reference_id, NULL, 'Issued for tailoring', v_res.roll_id);
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.close_roll_reservation(UUID, BOOLEAN, UUID) FROM PUBLIC, anon, authenticated;

-- Internal: payments against an order (in = deposit/balance, out = refund)
CREATE OR REPLACE FUNCTION public.record_tailoring_payments(p_order_id UUID, p_payments JSONB, p_direction TEXT)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pay JSONB;
    v_amount NUMERIC;
    v_total NUMERIC := 0;
    v_order public.tailoring_orders;
BEGIN
    SELECT * INTO v_order FROM public.tailoring_orders WHERE id = p_order_id;
    FOR v_pay IN SELECT * FROM jsonb_array_elements(COALESCE(p_payments, '[]'::jsonb))
    LOOP
        v_amount := NULLIF(v_pay->>'amount', '')::numeric;
        IF v_amount IS NULL OR v_amount <= 0 OR v_amount <> round(v_amount, 2) THEN
            RAISE EXCEPTION 'Each payment needs an amount greater than zero';
        END IF;
        IF v_pay->>'method' NOT IN ('cash', 'card', 'digital', 'credit') THEN
            RAISE EXCEPTION 'Invalid payment method: %', v_pay->>'method';
        END IF;
        IF v_pay->>'method' = 'credit' THEN
            IF p_direction = 'in' THEN
                UPDATE public.customers SET credit_used = COALESCE(credit_used, 0) + v_amount
                WHERE id = v_order.customer_id AND COALESCE(credit_limit, 0) - COALESCE(credit_used, 0) >= v_amount;
                IF NOT FOUND THEN
                    RAISE EXCEPTION 'Customer credit limit exceeded';
                END IF;
            ELSE
                UPDATE public.customers SET credit_used = credit_used - v_amount
                WHERE id = v_order.customer_id AND credit_used >= v_amount;
                IF NOT FOUND THEN
                    RAISE EXCEPTION 'Store credit refunds can only reduce what the customer owes';
                END IF;
            END IF;
        END IF;
        INSERT INTO public.payments (tailoring_order_id, method, amount, direction, tendered, change_given, reference,
                                     card_type, card_last4)
        VALUES (p_order_id, v_pay->>'method', v_amount, p_direction,
                CASE WHEN v_pay->>'method' = 'cash' AND p_direction = 'in' THEN NULLIF(v_pay->>'tendered', '')::numeric END,
                CASE WHEN v_pay->>'method' = 'cash' AND p_direction = 'in' AND NULLIF(v_pay->>'tendered', '') IS NOT NULL
                     THEN (v_pay->>'tendered')::numeric - v_amount ELSE 0 END,
                COALESCE(left(v_pay->>'reference', 100), v_order.order_no),
                CASE WHEN v_pay->>'method' = 'card' THEN left(v_pay->>'card_type', 20) END,
                CASE WHEN v_pay->>'method' = 'card' THEN NULLIF(right(regexp_replace(COALESCE(v_pay->>'card_last4', ''), '\D', '', 'g'), 4), '') END);
        IF v_pay->>'method' = 'cash' AND p_direction = 'in' AND NULLIF(v_pay->>'tendered', '') IS NOT NULL
           AND (v_pay->>'tendered')::numeric < v_amount THEN
            RAISE EXCEPTION 'Cash received is less than the cash amount';
        END IF;
        v_total := v_total + v_amount;
    END LOOP;
    RETURN v_total;
END;
$$;
REVOKE ALL ON FUNCTION public.record_tailoring_payments(UUID, JSONB, TEXT) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- Full picture of one order (for the counter)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tailoring_order_summary(p_order_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT to_jsonb(o) || public.tailoring_order_totals(o.id) || jsonb_build_object(
        'customer', jsonb_build_object('id', c.id, 'name', c.name, 'phone', c.phone),
        'items', COALESCE((
            SELECT jsonb_agg(to_jsonb(i) || jsonb_build_object(
                'garment_name', g.name, 'wearer_name', w.name,
                'tailor_name', (SELECT name FROM public.users u WHERE u.id = i.assigned_tailor))
                ORDER BY i.line_no)
            FROM public.tailoring_items i
            JOIN public.garment_types g ON g.code = i.garment_type
            JOIN public.wearer_profiles w ON w.id = i.wearer_id
            WHERE i.order_id = o.id), '[]'::jsonb),
        'charges', COALESCE((SELECT jsonb_agg(to_jsonb(ch) ORDER BY ch.created_at) FROM public.tailoring_charges ch
                             WHERE ch.order_id = o.id), '[]'::jsonb),
        'materials', COALESCE((
            SELECT jsonb_agg(to_jsonb(m) || jsonb_build_object('roll_code', r.roll_code) ORDER BY m.created_at)
            FROM public.tailoring_materials m LEFT JOIN public.fabric_rolls r ON r.id = m.roll_id
            WHERE m.order_id = o.id), '[]'::jsonb),
        'payments', COALESCE((SELECT jsonb_agg(jsonb_build_object('method', p.method, 'amount', p.amount,
                                                                  'direction', p.direction, 'created_at', p.created_at)
                                               ORDER BY p.created_at)
                              FROM public.payments p WHERE p.tailoring_order_id = o.id), '[]'::jsonb)
    )
    FROM public.tailoring_orders o
    JOIN public.customers c ON c.id = o.customer_id
    WHERE o.id = p_order_id AND public.is_counter_staff() AND public.is_branch_member(o.branch_id)
$$;
REVOKE ALL ON FUNCTION public.tailoring_order_summary(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tailoring_order_summary(UUID) TO authenticated;

-- ---------------------------------------------------------------------
-- Measurements on their own (e.g. a customer comes in to be measured)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_measurements(
    p_wearer_id UUID, p_garment_type TEXT, p_measurements JSONB, p_fit_preference TEXT DEFAULT NULL, p_notes TEXT DEFAULT NULL
)
RETURNS public.measurement_sets
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_set public.measurement_sets;
BEGIN
    IF NOT public.is_counter_staff() THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.wearer_profiles WHERE id = p_wearer_id) THEN
        RAISE EXCEPTION 'Wearer not found';
    END IF;
    IF jsonb_typeof(p_measurements) <> 'object' THEN
        RAISE EXCEPTION 'Measurements must be a list of values';
    END IF;
    INSERT INTO public.measurement_sets (wearer_id, garment_type, measurements, fit_preference, notes)
    VALUES (p_wearer_id, p_garment_type, p_measurements, NULLIF(p_fit_preference, ''), NULLIF(trim(p_notes), ''))
    RETURNING * INTO v_set;
    RETURN v_set;
END;
$$;
REVOKE ALL ON FUNCTION public.record_measurements(UUID, TEXT, JSONB, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_measurements(UUID, TEXT, JSONB, TEXT, TEXT) TO authenticated;

-- ---------------------------------------------------------------------
-- Create an order (draft or confirmed) in one transaction
--
-- {
--   request_id, customer_id, status: 'draft' | 'confirmed',
--   promised_date, fitting_date, notes,
--   items: [{
--     garment_type,
--     wearer_id | wearer: { name, relation },
--     measurement_set_id | measurements: { values, fit_preference, notes },
--     design_notes,
--     stitching_charge (default: garment type's charge),
--     charges: [{ kind, description, amount }],
--     materials: [ { source: 'store', variant_id, roll_id?, quantity, charge?: true }
--                | { source: 'customer', description, quantity, unit } ]
--   }],
--   payments: [ deposit payments ]
-- }
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_tailoring_order(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_request_id UUID := NULLIF(p->>'request_id', '')::uuid;
    v_existing JSONB;
    v_status TEXT := COALESCE(NULLIF(p->>'status', ''), 'confirmed');
    v_location public.locations;
    v_customer public.customers;
    v_order public.tailoring_orders;
    v_item_req JSONB;
    v_item public.tailoring_items;
    v_line_no INTEGER := 0;
    v_wearer UUID;
    v_set public.measurement_sets;
    v_garment public.garment_types;
    v_charge JSONB;
    v_mat JSONB;
    v_material public.tailoring_materials;
    v_variant RECORD;
    v_charge_row public.tailoring_charges;
    v_qty NUMERIC;
    v_stitching NUMERIC;
    v_totals JSONB;
BEGIN
    IF NOT public.is_counter_staff() THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'request_id is required';
    END IF;
    IF v_status NOT IN ('draft', 'confirmed') THEN
        RAISE EXCEPTION 'New orders are draft or confirmed';
    END IF;

    v_existing := public.idempotency_begin(v_request_id, 'create_tailoring_order');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    SELECT * INTO v_customer FROM public.customers WHERE id = NULLIF(p->>'customer_id', '')::uuid;
    IF v_customer.id IS NULL THEN
        RAISE EXCEPTION 'Choose the customer';
    END IF;
    IF jsonb_typeof(p->'items') <> 'array' OR jsonb_array_length(p->'items') = 0 THEN
        RAISE EXCEPTION 'Add at least one garment';
    END IF;

    SELECT * INTO v_location FROM public.locations
    WHERE branch_id = public.default_branch_id() AND kind = 'shop_floor' AND active ORDER BY created_at LIMIT 1;
    IF NOT public.is_branch_member(v_location.branch_id) THEN
        RAISE EXCEPTION 'Not a member of this branch' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.tailoring_orders (order_no, request_id, branch_id, location_id, customer_id, status,
                                         promised_date, fitting_date, notes, confirmed_at)
    VALUES ('TLR-' || lpad(nextval('public.tailoring_order_no_seq')::text, 6, '0'), v_request_id,
            v_location.branch_id, v_location.id, v_customer.id, v_status,
            NULLIF(p->>'promised_date', '')::date, NULLIF(p->>'fitting_date', '')::date,
            NULLIF(trim(p->>'notes'), ''), CASE WHEN v_status = 'confirmed' THEN now() END)
    RETURNING * INTO v_order;

    FOR v_item_req IN SELECT * FROM jsonb_array_elements(p->'items')
    LOOP
        v_line_no := v_line_no + 1;

        SELECT * INTO v_garment FROM public.garment_types WHERE code = v_item_req->>'garment_type' AND active;
        IF v_garment.code IS NULL THEN
            RAISE EXCEPTION 'Unknown garment type: %', v_item_req->>'garment_type';
        END IF;

        -- Wearer: existing (must belong to the customer) or new
        v_wearer := NULLIF(v_item_req->>'wearer_id', '')::uuid;
        IF v_wearer IS NULL THEN
            INSERT INTO public.wearer_profiles (customer_id, name, relation)
            VALUES (v_customer.id, COALESCE(NULLIF(trim(v_item_req->'wearer'->>'name'), ''), v_customer.name),
                    NULLIF(trim(v_item_req->'wearer'->>'relation'), ''))
            RETURNING id INTO v_wearer;
        ELSIF NOT EXISTS (SELECT 1 FROM public.wearer_profiles WHERE id = v_wearer AND customer_id = v_customer.id) THEN
            RAISE EXCEPTION 'That wearer belongs to another customer';
        END IF;

        -- Measurements: an existing set of this wearer, or a new one
        v_set := NULL;
        IF NULLIF(v_item_req->>'measurement_set_id', '') IS NOT NULL THEN
            SELECT * INTO v_set FROM public.measurement_sets
            WHERE id = (v_item_req->>'measurement_set_id')::uuid AND wearer_id = v_wearer;
            IF v_set.id IS NULL THEN
                RAISE EXCEPTION 'Those measurements belong to someone else';
            END IF;
        ELSIF jsonb_typeof(v_item_req->'measurements'->'values') = 'object' THEN
            INSERT INTO public.measurement_sets (wearer_id, garment_type, measurements, fit_preference, notes)
            VALUES (v_wearer, v_garment.code, v_item_req->'measurements'->'values',
                    NULLIF(v_item_req->'measurements'->>'fit_preference', ''), NULLIF(trim(v_item_req->'measurements'->>'notes'), ''))
            RETURNING * INTO v_set;
        END IF;

        INSERT INTO public.tailoring_items (order_id, line_no, garment_type, wearer_id, measurement_set_id,
                                            measurements_snapshot, fit_preference, design_notes, due_date)
        VALUES (v_order.id, v_line_no, v_garment.code, v_wearer, v_set.id, COALESCE(v_set.measurements, '{}'::jsonb),
                v_set.fit_preference, NULLIF(trim(v_item_req->>'design_notes'), ''),
                COALESCE(NULLIF(p->>'promised_date', '')::date, current_date + v_garment.lead_days))
        RETURNING * INTO v_item;

        -- Stitching charge (default from the garment type)
        v_stitching := COALESCE(NULLIF(v_item_req->>'stitching_charge', '')::numeric, v_garment.default_charge);
        IF v_stitching < 0 THEN
            RAISE EXCEPTION 'Charges cannot be negative';
        END IF;
        INSERT INTO public.tailoring_charges (order_id, item_id, kind, description, amount)
        VALUES (v_order.id, v_item.id, CASE WHEN v_garment.code = 'ALTERATION' THEN 'alteration' ELSE 'stitching' END,
                v_garment.name || ' stitching', round(v_stitching, 2));

        FOR v_charge IN SELECT * FROM jsonb_array_elements(COALESCE(v_item_req->'charges', '[]'::jsonb))
        LOOP
            IF COALESCE(NULLIF(v_charge->>'amount', '')::numeric, -1) < 0 THEN
                RAISE EXCEPTION 'Charges cannot be negative';
            END IF;
            INSERT INTO public.tailoring_charges (order_id, item_id, kind, description, amount)
            VALUES (v_order.id, v_item.id, COALESCE(NULLIF(v_charge->>'kind', ''), 'other'),
                    COALESCE(NULLIF(trim(v_charge->>'description'), ''), initcap(v_charge->>'kind')),
                    round((v_charge->>'amount')::numeric, 2));
        END LOOP;

        -- Materials
        FOR v_mat IN SELECT * FROM jsonb_array_elements(COALESCE(v_item_req->'materials', '[]'::jsonb))
        LOOP
            v_qty := NULLIF(v_mat->>'quantity', '')::numeric;
            IF v_qty IS NULL OR v_qty <= 0 OR v_qty <> round(v_qty, 2) THEN
                RAISE EXCEPTION 'Enter the fabric length (up to 2 decimals)';
            END IF;

            IF v_mat->>'source' = 'store' THEN
                SELECT v.id, v.price, s.unit,
                       trim(s.name || COALESCE(' ' || v.color, '') || COALESCE(' ' || v.size, '')) AS description
                INTO v_variant
                FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id
                WHERE v.id = NULLIF(v_mat->>'variant_id', '')::uuid AND v.active AND s.active;
                IF v_variant.id IS NULL OR v_variant.unit <> 'meter' THEN
                    RAISE EXCEPTION 'Choose a fabric from stock';
                END IF;

                v_charge_row := NULL;
                IF COALESCE((v_mat->>'charge')::boolean, true) THEN
                    INSERT INTO public.tailoring_charges (order_id, item_id, kind, description, amount)
                    VALUES (v_order.id, v_item.id, 'fabric',
                            v_variant.description || ' ' || trim_scale(v_qty) || ' m', round(v_variant.price * v_qty, 2))
                    RETURNING * INTO v_charge_row;
                END IF;

                INSERT INTO public.tailoring_materials (order_id, item_id, source, variant_id, roll_id, description,
                                                        quantity, unit, status, charge_id)
                VALUES (v_order.id, v_item.id, 'store', v_variant.id, NULLIF(v_mat->>'roll_id', '')::uuid,
                        v_variant.description, v_qty, 'meter', 'planned', v_charge_row.id)
                RETURNING * INTO v_material;
            ELSIF v_mat->>'source' = 'customer' THEN
                INSERT INTO public.tailoring_materials (order_id, item_id, source, description, quantity, unit, status, notes)
                VALUES (v_order.id, v_item.id, 'customer',
                        COALESCE(NULLIF(trim(v_mat->>'description'), ''), 'Customer fabric'), v_qty,
                        COALESCE(NULLIF(v_mat->>'unit', ''), 'meter'), 'received', NULLIF(trim(v_mat->>'notes'), ''))
                RETURNING * INTO v_material;
                INSERT INTO public.material_custody_events (material_id, event, quantity, note)
                VALUES (v_material.id, 'received', v_qty, 'Received from customer');
            ELSE
                RAISE EXCEPTION 'Fabric source must be store or customer';
            END IF;
        END LOOP;
    END LOOP;

    -- Order-level charges
    FOR v_charge IN SELECT * FROM jsonb_array_elements(COALESCE(p->'charges', '[]'::jsonb))
    LOOP
        IF COALESCE(NULLIF(v_charge->>'amount', '')::numeric, -1) < 0 THEN
            RAISE EXCEPTION 'Charges cannot be negative';
        END IF;
        INSERT INTO public.tailoring_charges (order_id, kind, description, amount)
        VALUES (v_order.id, COALESCE(NULLIF(v_charge->>'kind', ''), 'other'),
                COALESCE(NULLIF(trim(v_charge->>'description'), ''), 'Other'), round((v_charge->>'amount')::numeric, 2));
    END LOOP;

    IF v_status = 'confirmed' THEN
        PERFORM public.confirm_tailoring_order_internal(v_order.id);
    END IF;

    -- Deposit
    IF jsonb_typeof(p->'payments') = 'array' AND jsonb_array_length(p->'payments') > 0 THEN
        IF v_status = 'draft' THEN
            RAISE EXCEPTION 'Confirm the order before taking a deposit';
        END IF;
        PERFORM public.record_tailoring_payments(v_order.id, p->'payments', 'in');
        v_totals := public.tailoring_order_totals(v_order.id);
        IF (v_totals->>'balance')::numeric < 0 THEN
            RAISE EXCEPTION 'The deposit is more than the order total';
        END IF;
    END IF;

    RETURN public.idempotency_finish(v_request_id, public.tailoring_order_summary(v_order.id));
END;
$$;

-- Confirming: measurements complete, store fabric reserved on rolls
CREATE OR REPLACE FUNCTION public.confirm_tailoring_order_internal(p_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order public.tailoring_orders;
    v_item RECORD;
    v_missing TEXT[];
    v_mat public.tailoring_materials;
    v_res public.stock_reservations;
BEGIN
    SELECT * INTO v_order FROM public.tailoring_orders WHERE id = p_order_id FOR UPDATE;

    FOR v_item IN SELECT i.*, g.name AS garment_name, w.name AS wearer_name
                  FROM public.tailoring_items i
                  JOIN public.garment_types g ON g.code = i.garment_type
                  JOIN public.wearer_profiles w ON w.id = i.wearer_id
                  WHERE i.order_id = p_order_id ORDER BY i.line_no
    LOOP
        v_missing := public.missing_measurements(v_item.garment_type, v_item.measurements_snapshot);
        IF cardinality(v_missing) > 0 THEN
            RAISE EXCEPTION '% for %: missing %', v_item.garment_name, v_item.wearer_name, array_to_string(v_missing, ', ');
        END IF;
    END LOOP;

    FOR v_mat IN
        SELECT * FROM public.tailoring_materials
        WHERE order_id = p_order_id AND source = 'store' AND status = 'planned'
        ORDER BY variant_id, id
    LOOP
        v_res := public.reserve_roll_length(v_mat.variant_id, v_order.location_id, v_mat.quantity, v_mat.roll_id,
                                            'tailoring_order', p_order_id);
        UPDATE public.tailoring_materials SET status = 'reserved', reservation_id = v_res.id, roll_id = v_res.roll_id
        WHERE id = v_mat.id;
        INSERT INTO public.material_custody_events (material_id, event, quantity, note)
        VALUES (v_mat.id, 'reserved', v_mat.quantity, 'Reserved on roll');
    END LOOP;

    UPDATE public.tailoring_orders SET status = 'confirmed', confirmed_at = COALESCE(confirmed_at, now())
    WHERE id = p_order_id;
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_tailoring_order_internal(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.confirm_tailoring_order(p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order public.tailoring_orders;
BEGIN
    SELECT * INTO v_order FROM public.tailoring_orders WHERE id = p_order_id FOR UPDATE;
    IF v_order.id IS NULL OR NOT public.is_counter_staff() OR NOT public.is_branch_member(v_order.branch_id) THEN
        RAISE EXCEPTION 'Order not found';
    END IF;
    IF v_order.status <> 'draft' THEN
        RETURN public.tailoring_order_summary(p_order_id);
    END IF;
    PERFORM public.confirm_tailoring_order_internal(p_order_id);
    RETURN public.tailoring_order_summary(p_order_id);
END;
$$;

-- Deposit or balance payment
CREATE OR REPLACE FUNCTION public.post_tailoring_payment(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_request_id UUID := NULLIF(p->>'request_id', '')::uuid;
    v_existing JSONB;
    v_order public.tailoring_orders;
    v_totals JSONB;
BEGIN
    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'request_id is required';
    END IF;
    v_existing := public.idempotency_begin(v_request_id, 'post_tailoring_payment');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    SELECT * INTO v_order FROM public.tailoring_orders WHERE id = NULLIF(p->>'order_id', '')::uuid FOR UPDATE;
    IF v_order.id IS NULL OR NOT public.is_counter_staff() OR NOT public.is_branch_member(v_order.branch_id) THEN
        RAISE EXCEPTION 'Order not found';
    END IF;
    IF v_order.status IN ('draft', 'cancelled', 'delivered') THEN
        RAISE EXCEPTION 'Payments are taken on confirmed orders only (this one is %)', v_order.status;
    END IF;
    IF jsonb_typeof(p->'payments') <> 'array' OR jsonb_array_length(p->'payments') = 0 THEN
        RAISE EXCEPTION 'Add a payment';
    END IF;

    PERFORM public.record_tailoring_payments(v_order.id, p->'payments', 'in');
    v_totals := public.tailoring_order_totals(v_order.id);
    IF (v_totals->>'balance')::numeric < 0 THEN
        RAISE EXCEPTION 'That is more than the balance due';
    END IF;

    RETURN public.idempotency_finish(v_request_id, public.tailoring_order_summary(v_order.id));
END;
$$;

REVOKE ALL ON FUNCTION public.create_tailoring_order(JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.confirm_tailoring_order(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.post_tailoring_payment(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_tailoring_order(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_tailoring_order(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.post_tailoring_payment(JSONB) TO authenticated;
