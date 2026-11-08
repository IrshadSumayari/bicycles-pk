ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS cash_variance_alert NUMERIC(14,2)
    NOT NULL DEFAULT 500 CHECK (cash_variance_alert >= 0);

-- Keep the existing settings UPDATE path and its general manager permissions,
-- but only an admin can change this particular control.
CREATE OR REPLACE FUNCTION public.guard_cash_variance_alert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW.cash_variance_alert IS DISTINCT FROM OLD.cash_variance_alert
       AND auth.uid() IS NOT NULL AND NOT public.has_app_role(ARRAY['admin']) THEN
        RAISE EXCEPTION 'Only administrators can change the cash difference alert' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_cash_variance_alert() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trigger_guard_cash_variance_alert ON public.app_settings;
CREATE TRIGGER trigger_guard_cash_variance_alert BEFORE UPDATE OF cash_variance_alert ON public.app_settings
    FOR EACH ROW EXECUTE FUNCTION public.guard_cash_variance_alert();

-- The one closing calculation, extracted unchanged from the original close.
-- Callers authenticate and authorize before entering this private helper.
CREATE OR REPLACE FUNCTION public.close_cash_session_internal(
    p_session_id UUID, p_counted NUMERIC, p_notes TEXT, p_closed_by UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_session public.cash_sessions; v_expected NUMERIC;
BEGIN
    IF p_counted IS NULL OR p_counted < 0 THEN
        RAISE EXCEPTION 'Enter the counted cash (0 or more)';
    END IF;
    SELECT * INTO v_session FROM public.cash_sessions WHERE id = p_session_id FOR UPDATE;
    IF v_session.id IS NULL THEN RAISE EXCEPTION 'Cash shift not found'; END IF;
    IF v_session.status <> 'open' THEN RAISE EXCEPTION 'This cash shift is already closed'; END IF;
    v_expected := v_session.opening_float + coalesce(
        (SELECT sum(amount) FROM public.cash_movements WHERE session_id = v_session.id), 0);
    IF round(p_counted, 2) <> v_expected AND coalesce(trim(p_notes), '') = '' THEN
        RAISE EXCEPTION 'The count differs from the expected cash by %; add a note', round(p_counted, 2) - v_expected;
    END IF;
    UPDATE public.cash_sessions SET status = 'closed', expected_cash = v_expected,
        counted_cash = round(p_counted, 2), variance = round(p_counted, 2) - v_expected,
        closing_notes = nullif(trim(p_notes), ''), closed_by = p_closed_by, closed_at = now()
    WHERE id = v_session.id;
    RETURN public.cash_session_summary(v_session.id);
END;
$$;
REVOKE ALL ON FUNCTION public.close_cash_session_internal(UUID, NUMERIC, TEXT, UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.close_cash_session(p_counted_cash NUMERIC, p_notes TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_session UUID;
BEGIN
    -- Preserve the original validation order, signature, errors and rounding.
    IF p_counted_cash IS NULL OR p_counted_cash < 0 THEN
        RAISE EXCEPTION 'Enter the counted cash (0 or more)';
    END IF;
    SELECT id INTO v_session FROM public.cash_sessions WHERE user_id = auth.uid() AND status = 'open' FOR UPDATE;
    IF v_session IS NULL THEN RAISE EXCEPTION 'No open cash shift'; END IF;
    RETURN public.close_cash_session_internal(v_session, p_counted_cash, p_notes, auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.force_close_cash_session(
    p_session_id UUID, p_counted_cash NUMERIC, p_notes TEXT, p_request_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_session public.cash_sessions; v_existing JSONB; v_result JSONB;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
        RAISE EXCEPTION 'Only managers can close another cashier''s shift' USING ERRCODE = '42501';
    END IF;
    v_existing := public.idempotency_begin(p_request_id, 'force_close_cash_session');
    IF v_existing IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM public.idempotency_keys WHERE key = p_request_id AND user_id = auth.uid())
           OR (v_existing->'session'->>'id')::uuid IS DISTINCT FROM p_session_id
           OR NOT public.is_branch_member((v_existing->'session'->>'branch_id')::uuid) THEN
            RAISE EXCEPTION 'Request id belongs to another closing request' USING ERRCODE = '42501';
        END IF;
        RETURN v_existing;
    END IF;
    IF p_request_id IS NULL THEN RAISE EXCEPTION 'request_id is required'; END IF;
    IF coalesce(trim(p_notes), '') = '' THEN RAISE EXCEPTION 'Add notes explaining why you are closing this shift'; END IF;
    SELECT * INTO v_session FROM public.cash_sessions WHERE id = p_session_id FOR UPDATE;
    IF v_session.id IS NULL OR NOT public.is_branch_member(v_session.branch_id) THEN
        RAISE EXCEPTION 'Cash shift not found or you do not have access' USING ERRCODE = '42501';
    END IF;
    IF v_session.user_id = auth.uid() THEN RAISE EXCEPTION 'Close your own shift from the till'; END IF;
    v_result := public.close_cash_session_internal(p_session_id, p_counted_cash,
        'Closed by manager: ' || trim(p_notes), auth.uid());
    RETURN public.idempotency_finish(p_request_id, v_result);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_cash_sessions(p JSONB DEFAULT '{}'::jsonb)
RETURNS TABLE(id UUID, session_no TEXT, user_id UUID, user_name TEXT, status TEXT,
    opened_at TIMESTAMPTZ, closed_at TIMESTAMPTZ, opening_float NUMERIC, cash_sales NUMERIC,
    refunds NUMERIC, cash_in NUMERIC, cash_out NUMERIC, expected_cash NUMERIC, counted_cash NUMERIC,
    variance NUMERIC, closing_notes TEXT, closed_by_name TEXT, over_limit BOOLEAN, total_count BIGINT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT coalesce(public.is_counter_staff(), false) THEN
        RAISE EXCEPTION 'Only counter staff can see cash shifts' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT s.id, s.session_no, s.user_id, u.name, s.status, s.opened_at, s.closed_at, s.opening_float,
        (x.summary->>'cash_sales')::numeric, (x.summary->>'cash_refunds')::numeric,
        (x.summary->>'cash_in')::numeric, (x.summary->>'cash_out')::numeric,
        coalesce(s.expected_cash, (x.summary->>'expected_cash')::numeric), s.counted_cash, s.variance,
        s.closing_notes, closer.name,
        coalesce(abs(s.variance) > coalesce((SELECT a.cash_variance_alert FROM public.app_settings a ORDER BY a.created_at LIMIT 1), 500), false),
        count(*) OVER ()
    FROM public.cash_sessions s
    JOIN public.users u ON u.id = s.user_id LEFT JOIN public.users closer ON closer.id = s.closed_by
    CROSS JOIN LATERAL (SELECT public.cash_session_summary(s.id) AS summary) x
    WHERE ((public.current_app_role() = 'cashier' AND s.user_id = auth.uid())
        OR (public.has_app_role(ARRAY['admin','manager']) AND public.is_branch_member(s.branch_id)))
      AND (nullif(p->>'from','') IS NULL OR s.opened_at >= ((p->>'from')::date::timestamp AT TIME ZONE public.report_tz()))
      AND (nullif(p->>'to','') IS NULL OR s.opened_at < (((p->>'to')::date + 1)::timestamp AT TIME ZONE public.report_tz()))
      AND (nullif(p->>'user_id','') IS NULL OR s.user_id = (p->>'user_id')::uuid)
      AND (nullif(p->>'status','') IS NULL OR s.status = p->>'status')
      AND (NOT coalesce((p->>'only_variance')::boolean, false) OR s.variance <> 0)
    ORDER BY s.opened_at DESC, s.id
    LIMIT least(200, greatest(1, coalesce((p->>'limit')::int, 50))) OFFSET greatest(0, coalesce((p->>'offset')::int, 0));
END;
$$;

CREATE OR REPLACE FUNCTION public.cash_session_detail(p_session_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_session public.cash_sessions;
BEGIN
    IF NOT coalesce(public.is_counter_staff(), false) THEN
        RAISE EXCEPTION 'Only counter staff can see cash shifts' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_session FROM public.cash_sessions s WHERE s.id = p_session_id AND
        ((public.current_app_role() = 'cashier' AND s.user_id = auth.uid())
         OR (public.has_app_role(ARRAY['admin','manager']) AND public.is_branch_member(s.branch_id)));
    IF v_session.id IS NULL THEN RAISE EXCEPTION 'Cash shift not found or you do not have access' USING ERRCODE = '42501'; END IF;
    RETURN jsonb_build_object(
        'summary', public.cash_session_summary(v_session.id) || jsonb_build_object(
            'user_name', (SELECT u.name FROM public.users u WHERE u.id = v_session.user_id),
            'closed_by_name', (SELECT u.name FROM public.users u WHERE u.id = v_session.closed_by),
            'over_limit', coalesce(abs(v_session.variance) > coalesce((SELECT a.cash_variance_alert FROM public.app_settings a ORDER BY a.created_at LIMIT 1), 500), false)),
        'movements', coalesce((SELECT jsonb_agg(jsonb_build_object(
            'id', m.id, 'created_at', m.created_at, 'movement_type', m.movement_type,
            'amount', m.amount, 'reason', m.reason, 'user_name', u.name,
            'document_no', coalesce(r.return_no, s.invoice_number, o.order_no)
        ) ORDER BY m.created_at, m.id)
        FROM public.cash_movements m LEFT JOIN public.users u ON u.id = m.created_by
        LEFT JOIN public.payments pay ON pay.id = m.payment_id
        LEFT JOIN public.sales s ON s.id = pay.sale_id
        LEFT JOIN public.returns r ON r.id = pay.return_id
        LEFT JOIN public.tailoring_orders o ON o.id = pay.tailoring_order_id
        WHERE m.session_id = v_session.id), '[]'::jsonb));
END;
$$;

REVOKE ALL ON FUNCTION public.close_cash_session(NUMERIC, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_cash_sessions(JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cash_session_detail(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.force_close_cash_session(UUID, NUMERIC, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.close_cash_session(NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_cash_sessions(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cash_session_detail(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.force_close_cash_session(UUID, NUMERIC, TEXT, UUID) TO authenticated;
