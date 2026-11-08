-- Review fixes for online orders (PR #47):
-- 1. Payments taken by the payment gateway are not money the packer took at the
--    counter, so they stay out of the shift's "other payments".
-- 2. Limit how many orders one website account can keep open, so nobody can
--    hold the shop's stock with unpaid or cash-on-delivery orders.

ALTER TABLE public.app_settings
 ADD COLUMN IF NOT EXISTS online_max_pending_orders INT NOT NULL DEFAULT 3 CHECK (online_max_pending_orders BETWEEN 1 AND 50),
 ADD COLUMN IF NOT EXISTS online_max_open_cod_orders INT NOT NULL DEFAULT 3 CHECK (online_max_open_cod_orders BETWEEN 1 AND 50);

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
                WHERE p.method NOT IN ('cash', 'opening') AND p.created_by = s.user_id
                  AND NOT EXISTS (SELECT 1 FROM public.online_orders oo
                                  WHERE oo.sale_id = p.sale_id AND oo.payment_method IN ('card', 'easypaisa'))
                  AND p.created_at >= s.opened_at AND p.created_at <= COALESCE(s.closed_at, now())
                GROUP BY p.method) t), '{}'::jsonb)
    )
    FROM public.cash_sessions s
    WHERE s.id = p_session_id
      AND (s.user_id = auth.uid() OR (public.has_app_role(ARRAY['admin', 'manager']) AND public.is_branch_member(s.branch_id)))
$$;
-- create_online_order locks the customer's account row first, so these counts
-- cannot race with a second order from the same account.
CREATE OR REPLACE FUNCTION public.limit_open_online_orders()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s public.app_settings;
BEGIN
 SELECT * INTO s FROM public.app_settings ORDER BY created_at, id LIMIT 1;
 IF NEW.payment_method = 'cod' THEN
  IF (SELECT count(*) FROM public.online_orders
      WHERE account_id = NEW.account_id AND payment_method = 'cod' AND status IN ('placed', 'confirmed'))
     >= coalesce(s.online_max_open_cod_orders, 3) THEN
   RAISE EXCEPTION 'You already have % cash-on-delivery orders waiting. Please wait until the shop has packed them, or contact the shop.',
    coalesce(s.online_max_open_cod_orders, 3);
  END IF;
 ELSIF (SELECT count(*) FROM public.online_orders
        WHERE account_id = NEW.account_id AND status = 'pending_payment' AND expires_at > now())
       >= coalesce(s.online_max_pending_orders, 3) THEN
  RAISE EXCEPTION 'You already have % orders waiting for payment. Please complete or cancel one first.',
   coalesce(s.online_max_pending_orders, 3);
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.limit_open_online_orders() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS online_orders_open_limit ON public.online_orders;
CREATE TRIGGER online_orders_open_limit BEFORE INSERT ON public.online_orders
 FOR EACH ROW EXECUTE FUNCTION public.limit_open_online_orders();
