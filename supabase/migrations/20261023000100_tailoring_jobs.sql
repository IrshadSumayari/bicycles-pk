-- =====================================================================
-- Tailoring jobs, delivery and cancellation
--
--   * Each garment moves through stages:
--       awaiting -> cutting -> stitching -> (fitting) -> finishing
--                -> quality_check -> ready -> delivered
--     Rework goes back to stitching from fitting or quality check, with a
--     reason. Every change is logged.
--   * Store fabric is issued (leaves stock) when the garment goes to cutting;
--     customer fabric is marked as handed to the tailor.
--   * Tailors work their own garments (and can pick up unassigned ones);
--     they see measurements and design notes, never prices or phone numbers.
--   * Delivery can be partial; the last delivery needs the balance paid
--     (store credit counts as payment).
--   * Cancellation (managers): unissued fabric goes back to stock, issued
--     fabric stays used, optional refund.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.tailoring_job_events (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id UUID NOT NULL REFERENCES public.tailoring_items(id) ON DELETE CASCADE,
    from_status TEXT,
    to_status TEXT NOT NULL,
    note TEXT,
    created_by UUID DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tailoring_job_events_item ON public.tailoring_job_events(item_id, created_at);

DROP TRIGGER IF EXISTS trigger_tailoring_job_events_append_only ON public.tailoring_job_events;
CREATE TRIGGER trigger_tailoring_job_events_append_only
    BEFORE UPDATE OR DELETE ON public.tailoring_job_events
    FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();

ALTER TABLE public.tailoring_job_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tailoring_job_events_select" ON public.tailoring_job_events;
CREATE POLICY "tailoring_job_events_select" ON public.tailoring_job_events FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.tailoring_items i WHERE i.id = item_id));

-- ---------------------------------------------------------------------
-- Order status follows its garments
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.refresh_tailoring_order_status(p_order_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order public.tailoring_orders;
    v_total INTEGER;
    v_delivered INTEGER;
    v_ready INTEGER;
    v_started INTEGER;
    v_status TEXT;
BEGIN
    SELECT * INTO v_order FROM public.tailoring_orders WHERE id = p_order_id;
    IF v_order.status IN ('draft', 'cancelled') THEN
        RETURN v_order.status;
    END IF;

    SELECT count(*) FILTER (WHERE status <> 'cancelled'),
           count(*) FILTER (WHERE status = 'delivered'),
           count(*) FILTER (WHERE status IN ('ready', 'delivered')),
           count(*) FILTER (WHERE status NOT IN ('awaiting', 'cancelled'))
    INTO v_total, v_delivered, v_ready, v_started
    FROM public.tailoring_items WHERE order_id = p_order_id;

    v_status := CASE
        WHEN v_total > 0 AND v_delivered = v_total THEN 'delivered'
        WHEN v_delivered > 0 THEN 'partially_delivered'
        WHEN v_total > 0 AND v_ready = v_total THEN 'ready'
        WHEN v_started > 0 THEN 'in_progress'
        ELSE 'confirmed' END;

    UPDATE public.tailoring_orders
    SET status = v_status, closed_at = CASE WHEN v_status = 'delivered' THEN now() ELSE closed_at END
    WHERE id = p_order_id;
    RETURN v_status;
END;
$$;
REVOKE ALL ON FUNCTION public.refresh_tailoring_order_status(UUID) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- Assign a garment to a tailor (managers)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assign_tailor(p_item_id UUID, p_tailor_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_item public.tailoring_items;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers assign work' USING ERRCODE = '42501';
    END IF;
    SELECT i.* INTO v_item FROM public.tailoring_items i JOIN public.tailoring_orders o ON o.id = i.order_id
    WHERE i.id = p_item_id AND public.is_branch_member(o.branch_id) FOR UPDATE OF i;
    IF v_item.id IS NULL THEN
        RAISE EXCEPTION 'Garment not found';
    END IF;
    IF v_item.status IN ('delivered', 'cancelled') THEN
        RAISE EXCEPTION 'This garment is already %', v_item.status;
    END IF;
    IF p_tailor_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.users WHERE id = p_tailor_id AND role = 'tailor' AND active) THEN
        RAISE EXCEPTION 'Choose an active tailor';
    END IF;
    UPDATE public.tailoring_items SET assigned_tailor = p_tailor_id WHERE id = p_item_id;
    INSERT INTO public.tailoring_job_events (item_id, from_status, to_status, note)
    VALUES (p_item_id, v_item.status, v_item.status,
            'Assigned to ' || COALESCE((SELECT name FROM public.users WHERE id = p_tailor_id), 'nobody'));
END;
$$;

-- ---------------------------------------------------------------------
-- Move a garment to its next stage
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.advance_tailoring_job(p_item_id UUID, p_to_status TEXT, p_note TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role TEXT := public.current_app_role();
    v_item public.tailoring_items;
    v_order public.tailoring_orders;
    v_allowed TEXT[];
    v_rework BOOLEAN;
    v_mat public.tailoring_materials;
BEGIN
    IF v_role IS NULL OR v_role NOT IN ('admin', 'manager', 'tailor') THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_item FROM public.tailoring_items WHERE id = p_item_id FOR UPDATE;
    SELECT * INTO v_order FROM public.tailoring_orders WHERE id = v_item.order_id FOR UPDATE;
    IF v_item.id IS NULL OR NOT public.is_branch_member(v_order.branch_id) THEN
        RAISE EXCEPTION 'Garment not found';
    END IF;
    IF v_order.status IN ('draft', 'cancelled') THEN
        RAISE EXCEPTION 'Order % is %', v_order.order_no, v_order.status;
    END IF;

    -- Tailors: their own garments, or an unassigned one they pick up
    IF v_role = 'tailor' THEN
        IF v_item.assigned_tailor IS NULL AND v_item.status = 'awaiting' THEN
            UPDATE public.tailoring_items SET assigned_tailor = auth.uid() WHERE id = p_item_id;
            v_item.assigned_tailor := auth.uid();
        ELSIF v_item.assigned_tailor IS DISTINCT FROM auth.uid() THEN
            RAISE EXCEPTION 'This garment is assigned to another tailor' USING ERRCODE = '42501';
        END IF;
    END IF;

    v_allowed := CASE v_item.status
        WHEN 'awaiting' THEN ARRAY['cutting']
        WHEN 'cutting' THEN ARRAY['stitching']
        WHEN 'stitching' THEN ARRAY['fitting', 'finishing']
        WHEN 'fitting' THEN ARRAY['stitching', 'finishing']
        WHEN 'finishing' THEN ARRAY['quality_check']
        WHEN 'quality_check' THEN ARRAY['ready', 'stitching']
        ELSE ARRAY[]::text[] END;
    IF NOT p_to_status = ANY(v_allowed) THEN
        RAISE EXCEPTION 'A garment in % cannot go to %', replace(v_item.status, '_', ' '), replace(p_to_status, '_', ' ');
    END IF;

    v_rework := p_to_status = 'stitching' AND v_item.status IN ('fitting', 'quality_check');
    IF v_rework AND COALESCE(trim(p_note), '') = '' THEN
        RAISE EXCEPTION 'Say what needs to be reworked';
    END IF;
    -- Passing quality check is a manager's call
    IF p_to_status = 'ready' AND v_role = 'tailor' THEN
        RAISE EXCEPTION 'A manager signs off quality checks' USING ERRCODE = '42501';
    END IF;

    -- Cutting: fabric for this garment is handed over
    IF p_to_status = 'cutting' THEN
        FOR v_mat IN SELECT * FROM public.tailoring_materials
                     WHERE item_id = p_item_id AND status IN ('reserved', 'received') ORDER BY variant_id, id
        LOOP
            IF v_mat.source = 'store' THEN
                PERFORM public.close_roll_reservation(v_mat.reservation_id, true, v_order.id);
            END IF;
            UPDATE public.tailoring_materials SET status = 'issued' WHERE id = v_mat.id;
            INSERT INTO public.material_custody_events (material_id, event, quantity, note)
            VALUES (v_mat.id, 'issued', v_mat.quantity, 'Issued for cutting');
        END LOOP;
    END IF;

    UPDATE public.tailoring_items SET status = p_to_status WHERE id = p_item_id;
    INSERT INTO public.tailoring_job_events (item_id, from_status, to_status, note)
    VALUES (p_item_id, v_item.status, p_to_status,
            CASE WHEN v_rework THEN 'Rework: ' || trim(p_note) ELSE NULLIF(trim(p_note), '') END);

    RETURN jsonb_build_object('item_id', p_item_id, 'status', p_to_status,
                              'order_status', public.refresh_tailoring_order_status(v_order.id));
END;
$$;

-- ---------------------------------------------------------------------
-- Give unused customer fabric back
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.return_customer_material(p_material_id UUID, p_quantity NUMERIC, p_note TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_mat public.tailoring_materials;
BEGIN
    IF NOT public.is_counter_staff() THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
    SELECT m.* INTO v_mat FROM public.tailoring_materials m JOIN public.tailoring_orders o ON o.id = m.order_id
    WHERE m.id = p_material_id AND public.is_branch_member(o.branch_id) FOR UPDATE OF m;
    IF v_mat.id IS NULL OR v_mat.source <> 'customer' THEN
        RAISE EXCEPTION 'Only the customer''s own fabric can be returned this way';
    END IF;
    IF p_quantity IS NULL OR p_quantity <= 0 OR v_mat.returned_quantity + p_quantity > v_mat.quantity THEN
        RAISE EXCEPTION 'Return between 0 and % %', trim_scale(v_mat.quantity - v_mat.returned_quantity), v_mat.unit;
    END IF;
    UPDATE public.tailoring_materials
    SET returned_quantity = returned_quantity + p_quantity,
        status = CASE WHEN returned_quantity + p_quantity = quantity THEN 'returned' ELSE status END
    WHERE id = p_material_id;
    INSERT INTO public.material_custody_events (material_id, event, quantity, note)
    VALUES (p_material_id, 'returned', p_quantity, COALESCE(NULLIF(trim(p_note), ''), 'Returned to customer'));
END;
$$;

-- ---------------------------------------------------------------------
-- Delivery (partial or full)
-- { request_id, order_id, item_ids: [...], payments: [...] }
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.deliver_tailoring_items(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_request_id UUID := NULLIF(p->>'request_id', '')::uuid;
    v_existing JSONB;
    v_order public.tailoring_orders;
    v_item_id UUID;
    v_item public.tailoring_items;
    v_remaining INTEGER;
    v_totals JSONB;
BEGIN
    IF NOT public.is_counter_staff() THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'request_id is required';
    END IF;
    v_existing := public.idempotency_begin(v_request_id, 'deliver_tailoring_items');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    SELECT * INTO v_order FROM public.tailoring_orders WHERE id = NULLIF(p->>'order_id', '')::uuid FOR UPDATE;
    IF v_order.id IS NULL OR NOT public.is_branch_member(v_order.branch_id) THEN
        RAISE EXCEPTION 'Order not found';
    END IF;
    IF jsonb_typeof(p->'item_ids') <> 'array' OR jsonb_array_length(p->'item_ids') = 0 THEN
        RAISE EXCEPTION 'Choose the garments being collected';
    END IF;

    IF jsonb_typeof(p->'payments') = 'array' AND jsonb_array_length(p->'payments') > 0 THEN
        PERFORM public.record_tailoring_payments(v_order.id, p->'payments', 'in');
    END IF;

    FOR v_item_id IN SELECT (x)::uuid FROM jsonb_array_elements_text(p->'item_ids') x
    LOOP
        SELECT * INTO v_item FROM public.tailoring_items WHERE id = v_item_id AND order_id = v_order.id FOR UPDATE;
        IF v_item.id IS NULL THEN
            RAISE EXCEPTION 'That garment is not on this order';
        END IF;
        IF v_item.status <> 'ready' THEN
            RAISE EXCEPTION 'Garment % is not ready (%)', v_item.line_no, replace(v_item.status, '_', ' ');
        END IF;
        UPDATE public.tailoring_items SET status = 'delivered', delivered_at = now() WHERE id = v_item_id;
        INSERT INTO public.tailoring_job_events (item_id, from_status, to_status, note)
        VALUES (v_item_id, 'ready', 'delivered', 'Collected by customer');
    END LOOP;

    v_totals := public.tailoring_order_totals(v_order.id);
    IF (v_totals->>'balance')::numeric < 0 THEN
        RAISE EXCEPTION 'That is more than the balance due';
    END IF;
    SELECT count(*) INTO v_remaining FROM public.tailoring_items
    WHERE order_id = v_order.id AND status NOT IN ('delivered', 'cancelled');
    IF v_remaining = 0 AND (v_totals->>'balance')::numeric > 0 THEN
        RAISE EXCEPTION 'Collect the balance of % before handing over the last garment', v_totals->>'balance';
    END IF;

    PERFORM public.refresh_tailoring_order_status(v_order.id);
    RETURN public.idempotency_finish(v_request_id, public.tailoring_order_summary(v_order.id));
END;
$$;

-- ---------------------------------------------------------------------
-- Cancellation (managers)
-- { request_id, order_id, reason, refunds: [{ method, amount }] }
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_tailoring_order(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_request_id UUID := NULLIF(p->>'request_id', '')::uuid;
    v_existing JSONB;
    v_order public.tailoring_orders;
    v_mat public.tailoring_materials;
    v_totals JSONB;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers cancel orders' USING ERRCODE = '42501';
    END IF;
    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'request_id is required';
    END IF;
    IF COALESCE(trim(p->>'reason'), '') = '' THEN
        RAISE EXCEPTION 'A reason is required';
    END IF;
    v_existing := public.idempotency_begin(v_request_id, 'cancel_tailoring_order');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    SELECT * INTO v_order FROM public.tailoring_orders WHERE id = NULLIF(p->>'order_id', '')::uuid FOR UPDATE;
    IF v_order.id IS NULL OR NOT public.is_branch_member(v_order.branch_id) THEN
        RAISE EXCEPTION 'Order not found';
    END IF;
    IF v_order.status IN ('cancelled', 'delivered', 'partially_delivered') THEN
        RAISE EXCEPTION 'Order % is % and cannot be cancelled', v_order.order_no, replace(v_order.status, '_', ' ');
    END IF;

    -- Fabric not yet cut goes back to stock; cut fabric stays used
    FOR v_mat IN SELECT * FROM public.tailoring_materials
                 WHERE order_id = v_order.id AND source = 'store' AND status IN ('planned', 'reserved') ORDER BY variant_id, id
    LOOP
        IF v_mat.reservation_id IS NOT NULL THEN
            PERFORM public.close_roll_reservation(v_mat.reservation_id, false, v_order.id);
        END IF;
        UPDATE public.tailoring_materials SET status = 'released' WHERE id = v_mat.id;
        INSERT INTO public.material_custody_events (material_id, event, quantity, note)
        VALUES (v_mat.id, 'released', v_mat.quantity, 'Order cancelled');
    END LOOP;

    UPDATE public.tailoring_items SET status = 'cancelled' WHERE order_id = v_order.id AND status <> 'delivered';
    UPDATE public.tailoring_orders SET status = 'cancelled', cancel_reason = trim(p->>'reason'), closed_at = now()
    WHERE id = v_order.id;

    IF jsonb_typeof(p->'refunds') = 'array' AND jsonb_array_length(p->'refunds') > 0 THEN
        PERFORM public.record_tailoring_payments(v_order.id, p->'refunds', 'out');
        v_totals := public.tailoring_order_totals(v_order.id);
        IF (v_totals->>'paid')::numeric < 0 THEN
            RAISE EXCEPTION 'Refund is more than was paid';
        END IF;
    END IF;

    RETURN public.idempotency_finish(v_request_id, public.tailoring_order_summary(v_order.id));
END;
$$;

-- ---------------------------------------------------------------------
-- Work queue: what a tailor needs, nothing more
--   tailors: their garments + unassigned ones waiting to be picked up
--   managers: all open garments
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tailor_queue()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'item_id', i.id,
        'order_no', o.order_no,
        'line_no', i.line_no,
        'garment_type', i.garment_type,
        'garment_name', g.name,
        'fields', g.fields,
        'wearer_name', w.name,
        'measurements', i.measurements_snapshot,
        'fit_preference', i.fit_preference,
        'design_notes', i.design_notes,
        'status', i.status,
        'due_date', i.due_date,
        'fitting_date', o.fitting_date,
        'promised_date', o.promised_date,
        'assigned_tailor', i.assigned_tailor,
        'tailor_name', t.name,
        'materials', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('source', m.source, 'description', m.description,
                                                'quantity', m.quantity, 'unit', m.unit, 'status', m.status,
                                                'roll_code', r.roll_code))
            FROM public.tailoring_materials m LEFT JOIN public.fabric_rolls r ON r.id = m.roll_id
            WHERE m.item_id = i.id AND m.status <> 'released'), '[]'::jsonb),
        'last_note', (SELECT note FROM public.tailoring_job_events e WHERE e.item_id = i.id AND note IS NOT NULL
                      ORDER BY e.created_at DESC LIMIT 1)
    ) ORDER BY COALESCE(i.due_date, o.promised_date), o.order_no, i.line_no), '[]'::jsonb)
    FROM public.tailoring_items i
    JOIN public.tailoring_orders o ON o.id = i.order_id
    JOIN public.garment_types g ON g.code = i.garment_type
    JOIN public.wearer_profiles w ON w.id = i.wearer_id
    LEFT JOIN public.users t ON t.id = i.assigned_tailor
    WHERE o.status NOT IN ('draft', 'cancelled')
      AND i.status NOT IN ('delivered', 'cancelled')
      AND public.is_branch_member(o.branch_id)
      AND (public.has_app_role(ARRAY['admin', 'manager'])
           OR (public.current_app_role() = 'tailor'
               AND (i.assigned_tailor = auth.uid() OR (i.assigned_tailor IS NULL AND i.status = 'awaiting'))))
$$;

-- Active tailors, for assignment
CREATE OR REPLACE FUNCTION public.list_tailors()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'name', name) ORDER BY name), '[]'::jsonb)
    FROM public.users WHERE role = 'tailor' AND active AND public.is_staff()
$$;

REVOKE ALL ON FUNCTION public.assign_tailor(UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.advance_tailoring_job(UUID, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.return_customer_material(UUID, NUMERIC, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.deliver_tailoring_items(JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_tailoring_order(JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.tailor_queue() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_tailors() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_tailor(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.advance_tailoring_job(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.return_customer_material(UUID, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deliver_tailoring_items(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_tailoring_order(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tailor_queue() TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_tailors() TO authenticated;
