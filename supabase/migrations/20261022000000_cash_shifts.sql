-- =====================================================================
-- Cash shifts
--
--   * A cashier opens a shift with an opening float. Every cash payment
--     taken or refunded by that cashier is recorded against the open shift;
--     taking cash without an open shift is refused.
--   * Cash in / cash out (e.g. petty cash, bank deposit) with a reason.
--   * Closing: the cashier counts the drawer; expected cash, counted cash and
--     the variance are stored. Shifts and movements are history.
--   * payments.direction: 'in' for money received, 'out' for refunds.
-- =====================================================================

ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS direction TEXT NOT NULL DEFAULT 'in'
    CHECK (direction IN ('in', 'out'));

CREATE SEQUENCE IF NOT EXISTS public.cash_session_no_seq START 1;
REVOKE ALL ON SEQUENCE public.cash_session_no_seq FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.cash_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_no TEXT NOT NULL UNIQUE,
    branch_id UUID NOT NULL REFERENCES public.branches(id),
    location_id UUID NOT NULL REFERENCES public.locations(id),
    user_id UUID NOT NULL REFERENCES public.users(id),
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
    opening_float NUMERIC(14,2) NOT NULL CHECK (opening_float >= 0),
    opened_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expected_cash NUMERIC(14,2),
    counted_cash NUMERIC(14,2) CHECK (counted_cash IS NULL OR counted_cash >= 0),
    variance NUMERIC(14,2),
    closing_notes TEXT,
    closed_by UUID,
    closed_at TIMESTAMPTZ
);
-- One open shift per cashier
CREATE UNIQUE INDEX IF NOT EXISTS idx_cash_sessions_open_user ON public.cash_sessions(user_id) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_cash_sessions_branch_time ON public.cash_sessions(branch_id, opened_at);

CREATE TABLE IF NOT EXISTS public.cash_movements (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES public.cash_sessions(id),
    -- Signed: positive into the drawer, negative out of it
    amount NUMERIC(14,2) NOT NULL CHECK (amount <> 0),
    movement_type TEXT NOT NULL CHECK (movement_type IN ('sale', 'refund', 'cash_in', 'cash_out')),
    payment_id UUID,
    reason TEXT,
    created_by UUID DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cash_movements_session ON public.cash_movements(session_id);

ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS cash_session_id UUID REFERENCES public.cash_sessions(id);

DROP TRIGGER IF EXISTS trigger_cash_movements_append_only ON public.cash_movements;
CREATE TRIGGER trigger_cash_movements_append_only
    BEFORE UPDATE OR DELETE ON public.cash_movements
    FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();

ALTER TABLE public.cash_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_movements ENABLE ROW LEVEL SECURITY;

-- Cashiers see their own shifts; back office sees all shifts of their branches
DROP POLICY IF EXISTS "cash_sessions_select" ON public.cash_sessions;
CREATE POLICY "cash_sessions_select" ON public.cash_sessions
    FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR (public.has_app_role(ARRAY['admin', 'manager']) AND public.is_branch_member(branch_id)));
DROP POLICY IF EXISTS "cash_movements_select" ON public.cash_movements;
CREATE POLICY "cash_movements_select" ON public.cash_movements
    FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.cash_sessions s WHERE s.id = session_id));

-- ---------------------------------------------------------------------
-- Every cash payment lands in the cashier's open shift
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_cash_payment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session UUID;
BEGIN
    IF NEW.method <> 'cash' THEN
        RETURN NEW;
    END IF;

    SELECT id INTO v_session FROM public.cash_sessions
    WHERE user_id = COALESCE(NEW.created_by, auth.uid()) AND status = 'open'
    FOR UPDATE;
    IF v_session IS NULL THEN
        RAISE EXCEPTION 'Open a cash shift before taking or refunding cash' USING ERRCODE = 'P0001';
    END IF;

    NEW.cash_session_id := v_session;
    INSERT INTO public.cash_movements (session_id, amount, movement_type, payment_id, created_by)
    VALUES (v_session,
            CASE WHEN NEW.direction = 'out' THEN -NEW.amount ELSE NEW.amount END,
            CASE WHEN NEW.direction = 'out' THEN 'refund' ELSE 'sale' END,
            NEW.id, COALESCE(NEW.created_by, auth.uid()));
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_record_cash_payment ON public.payments;
CREATE TRIGGER trigger_record_cash_payment
    BEFORE INSERT ON public.payments
    FOR EACH ROW EXECUTE FUNCTION public.record_cash_payment();

-- ---------------------------------------------------------------------
-- Staff functions
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cash_session_summary(p_session_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'session', to_jsonb(s),
        'cash_sales', COALESCE((SELECT sum(amount) FROM public.cash_movements WHERE session_id = s.id AND movement_type = 'sale'), 0),
        'cash_refunds', COALESCE((SELECT -sum(amount) FROM public.cash_movements WHERE session_id = s.id AND movement_type = 'refund'), 0),
        'cash_in', COALESCE((SELECT sum(amount) FROM public.cash_movements WHERE session_id = s.id AND movement_type = 'cash_in'), 0),
        'cash_out', COALESCE((SELECT -sum(amount) FROM public.cash_movements WHERE session_id = s.id AND movement_type = 'cash_out'), 0),
        'expected_cash', s.opening_float + COALESCE((SELECT sum(amount) FROM public.cash_movements WHERE session_id = s.id), 0),
        'other_payments', COALESCE((
            SELECT jsonb_object_agg(method, total) FROM (
                SELECT p.method, sum(CASE WHEN p.direction = 'out' THEN -p.amount ELSE p.amount END) AS total
                FROM public.payments p
                WHERE p.method <> 'cash' AND p.created_by = s.user_id
                  AND p.created_at >= s.opened_at AND p.created_at <= COALESCE(s.closed_at, now())
                GROUP BY p.method) t), '{}'::jsonb)
    )
    FROM public.cash_sessions s
    WHERE s.id = p_session_id
      AND (s.user_id = auth.uid() OR (public.has_app_role(ARRAY['admin', 'manager']) AND public.is_branch_member(s.branch_id)))
$$;

CREATE OR REPLACE FUNCTION public.open_cash_session(p_opening_float NUMERIC, p_location_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_location UUID := p_location_id;
    v_branch UUID;
    v_session public.cash_sessions;
BEGIN
    IF public.current_app_role() NOT IN ('admin', 'manager', 'cashier') THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
    IF p_opening_float IS NULL OR p_opening_float < 0 THEN
        RAISE EXCEPTION 'Enter the opening float (0 or more)';
    END IF;

    -- Opening twice returns the shift that is already open
    SELECT * INTO v_session FROM public.cash_sessions WHERE user_id = auth.uid() AND status = 'open';
    IF v_session.id IS NOT NULL THEN
        RETURN public.cash_session_summary(v_session.id);
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

    INSERT INTO public.cash_sessions (session_no, branch_id, location_id, user_id, opening_float)
    VALUES ('SHIFT-' || lpad(nextval('public.cash_session_no_seq')::text, 6, '0'), v_branch, v_location, auth.uid(),
            round(p_opening_float, 2))
    RETURNING * INTO v_session;
    RETURN public.cash_session_summary(v_session.id);
END;
$$;

-- The caller's open shift (or null)
CREATE OR REPLACE FUNCTION public.current_cash_session()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.cash_session_summary(id) FROM public.cash_sessions WHERE user_id = auth.uid() AND status = 'open'
$$;

-- Cash put into (positive) or taken out of (negative) the drawer
CREATE OR REPLACE FUNCTION public.record_cash_movement(p_amount NUMERIC, p_reason TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session public.cash_sessions;
BEGIN
    IF COALESCE(trim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required';
    END IF;
    IF p_amount IS NULL OR p_amount = 0 OR p_amount <> round(p_amount, 2) THEN
        RAISE EXCEPTION 'Enter an amount';
    END IF;
    SELECT * INTO v_session FROM public.cash_sessions WHERE user_id = auth.uid() AND status = 'open' FOR UPDATE;
    IF v_session.id IS NULL THEN
        RAISE EXCEPTION 'No open cash shift';
    END IF;
    IF p_amount < 0 AND v_session.opening_float + COALESCE(
           (SELECT sum(amount) FROM public.cash_movements WHERE session_id = v_session.id), 0) + p_amount < 0 THEN
        RAISE EXCEPTION 'There is not that much cash in the drawer';
    END IF;

    INSERT INTO public.cash_movements (session_id, amount, movement_type, reason)
    VALUES (v_session.id, p_amount, CASE WHEN p_amount > 0 THEN 'cash_in' ELSE 'cash_out' END, trim(p_reason));
    RETURN public.cash_session_summary(v_session.id);
END;
$$;

-- Count the drawer and close. The variance is counted - expected.
CREATE OR REPLACE FUNCTION public.close_cash_session(p_counted_cash NUMERIC, p_notes TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session public.cash_sessions;
    v_expected NUMERIC;
BEGIN
    IF p_counted_cash IS NULL OR p_counted_cash < 0 THEN
        RAISE EXCEPTION 'Enter the counted cash (0 or more)';
    END IF;
    SELECT * INTO v_session FROM public.cash_sessions WHERE user_id = auth.uid() AND status = 'open' FOR UPDATE;
    IF v_session.id IS NULL THEN
        RAISE EXCEPTION 'No open cash shift';
    END IF;

    v_expected := v_session.opening_float + COALESCE(
        (SELECT sum(amount) FROM public.cash_movements WHERE session_id = v_session.id), 0);
    IF round(p_counted_cash, 2) <> v_expected AND COALESCE(trim(p_notes), '') = '' THEN
        RAISE EXCEPTION 'The count differs from the expected cash by %; add a note', round(p_counted_cash, 2) - v_expected;
    END IF;

    UPDATE public.cash_sessions SET
        status = 'closed', expected_cash = v_expected, counted_cash = round(p_counted_cash, 2),
        variance = round(p_counted_cash, 2) - v_expected, closing_notes = NULLIF(trim(p_notes), ''),
        closed_by = auth.uid(), closed_at = now()
    WHERE id = v_session.id;
    RETURN public.cash_session_summary(v_session.id);
END;
$$;

REVOKE ALL ON FUNCTION public.record_cash_payment() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cash_session_summary(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.open_cash_session(NUMERIC, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.current_cash_session() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_cash_movement(NUMERIC, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.close_cash_session(NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cash_session_summary(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.open_cash_session(NUMERIC, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_cash_session() TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_cash_movement(NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.close_cash_session(NUMERIC, TEXT) TO authenticated;
