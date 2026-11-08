-- Payment initiation and confirmation are atomic, service-only operations.
-- P9-01 returned an existing initiated row without advancing it on confirmation.
CREATE OR REPLACE FUNCTION public.initiate_online_payment(
 p_order_no TEXT,p_account_id UUID,p_provider TEXT,p_provider_ref TEXT,p_method TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE o public.online_orders;pay public.online_payments;
BEGIN
 PERFORM public.require_online_service();
 SELECT * INTO o FROM public.online_orders WHERE order_no=p_order_no FOR UPDATE;
 IF o.id IS NULL OR o.account_id<>p_account_id OR EXISTS(SELECT 1 FROM public.users WHERE id=p_account_id) THEN
  RAISE EXCEPTION 'Order not found' USING ERRCODE='42501';
 END IF;
 IF o.status<>'pending_payment' OR o.expires_at IS NULL OR o.expires_at<=now() THEN RAISE EXCEPTION 'The payment window is closed. Please place a new order'; END IF;
 IF p_provider IS NULL OR p_provider NOT IN ('mock','easypaisa') OR coalesce(length(p_provider_ref),0) NOT BETWEEN 1 AND 200
  OR p_method IS NULL OR p_method<>(CASE o.payment_method WHEN 'card' THEN 'card' WHEN 'easypaisa' THEN 'wallet' ELSE '' END) THEN RAISE EXCEPTION 'Choose the payment method saved on the order'; END IF;
 SELECT * INTO pay FROM public.online_payments WHERE provider_ref=p_provider_ref FOR UPDATE;
 IF pay.id IS NOT NULL THEN
  IF pay.order_id<>o.id OR pay.provider<>p_provider OR pay.method<>p_method OR pay.amount<>o.total THEN RAISE EXCEPTION 'Payment reference already belongs to another checkout'; END IF;
  IF pay.status IN ('paid','refunded') OR pay.needs_refund THEN RAISE EXCEPTION 'This payment needs shop review before another checkout'; END IF;
  RETURN jsonb_build_object('provider_ref',pay.provider_ref,'status',pay.status);
 END IF;
 IF EXISTS(SELECT 1 FROM public.online_payments WHERE order_id=o.id AND status IN ('initiated','paid')) THEN
  RAISE EXCEPTION 'This order already has a payment session. Check its status before starting another';
 END IF;
 INSERT INTO public.online_payments(order_id,provider,provider_ref,method,amount,status,raw)
 VALUES(o.id,p_provider,p_provider_ref,p_method,o.total,'initiated',jsonb_build_object('source','checkout')) RETURNING * INTO pay;
 RETURN jsonb_build_object('provider_ref',pay.provider_ref,'status',pay.status);
END $$;

-- Retain the P9-01 contract, deadline and refund safeguards, but advance an
-- initiated row in place. A failed non-captured notification may later succeed;
-- paid/refunded or captured-mismatch results are terminal for that reference.
CREATE OR REPLACE FUNCTION public.mark_online_order_paid(p_order_no TEXT,p_provider TEXT,p_provider_ref TEXT,p_amount NUMERIC,p_method TEXT,p_raw JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE o public.online_orders;paid public.online_payments;refund BOOLEAN;failed BOOLEAN;
BEGIN
 PERFORM public.require_online_service();
 IF coalesce(length(trim(p_provider_ref)),0) NOT BETWEEN 1 AND 200 OR coalesce(length(trim(p_provider)),0) NOT BETWEEN 1 AND 50 OR p_method IS NULL OR p_method NOT IN ('card','wallet') OR p_amount IS NULL OR p_amount='NaN'::numeric OR p_amount<0 OR p_amount<>round(p_amount,2) THEN RAISE EXCEPTION 'Invalid payment notification'; END IF;
 -- All confirmation/refund paths lock the order before its payment row.
 SELECT * INTO o FROM public.online_orders WHERE order_no=p_order_no FOR UPDATE;
 IF o.id IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_provider_ref,28000001));
 SELECT * INTO paid FROM public.online_payments WHERE provider_ref=p_provider_ref FOR UPDATE;
 IF FOUND THEN
  IF paid.order_id<>o.id OR paid.provider<>p_provider OR paid.method<>p_method OR (paid.amount<>p_amount AND paid.status<>'initiated') THEN RAISE EXCEPTION 'Payment reference already belongs to another notification'; END IF;
  IF paid.status IN ('paid','refunded') OR paid.needs_refund THEN
   RETURN jsonb_build_object('status',paid.status,'needs_refund',paid.needs_refund);
  END IF;
 END IF;
 IF o.status='pending_payment' AND o.expires_at<=now() THEN
  PERFORM public.close_online_reservations(o.id,'expired');UPDATE public.online_orders SET status='expired' WHERE id=o.id;o.status:='expired';
  INSERT INTO public.online_order_events(order_id,event,public_message) VALUES(o.id,'expired','The payment window expired.');
 END IF;
 failed:=p_amount<>o.total OR o.payment_method='cod' OR (o.payment_method='card' AND p_method<>'card') OR (o.payment_method='easypaisa' AND p_method<>'wallet');
 refund:=o.status IN ('expired','cancelled') OR o.payment_status IN ('paid','refunded','partially_refunded');
 IF paid.id IS NULL THEN
  INSERT INTO public.online_payments(order_id,provider,method,provider_ref,amount,status,needs_refund,raw)
  VALUES(o.id,p_provider,p_method,p_provider_ref,p_amount,CASE WHEN failed THEN 'failed' ELSE 'paid' END,refund OR failed,p_raw) RETURNING * INTO paid;
 ELSE
  UPDATE public.online_payments SET amount=p_amount,status=CASE WHEN failed THEN 'failed' ELSE 'paid' END,needs_refund=refund OR failed,raw=p_raw WHERE id=paid.id RETURNING * INTO paid;
 END IF;
 IF NOT failed AND o.status='pending_payment' AND NOT refund THEN
  UPDATE public.online_orders SET status='placed',payment_status='paid',expires_at=NULL WHERE id=o.id;
  UPDATE public.stock_reservations SET expires_at=NULL WHERE reference_type='online_order' AND reference_id=o.id AND status='active';
 END IF;
 INSERT INTO public.online_order_events(order_id,event,public_message) VALUES(o.id,CASE WHEN failed THEN 'payment_failed' WHEN refund THEN 'payment_needs_refund' ELSE 'paid' END,
 CASE WHEN failed THEN 'The payment could not be matched to the order. Please contact the shop.' WHEN refund THEN 'A payment arrived for an order that cannot be fulfilled. The shop will arrange a refund.' ELSE 'Your payment was received.' END);
 RETURN jsonb_build_object('status',paid.status,'needs_refund',paid.needs_refund);
END $$;

CREATE OR REPLACE FUNCTION public.record_online_payment_event(
 p_order_no TEXT,p_provider TEXT,p_provider_ref TEXT,p_amount NUMERIC,p_method TEXT,p_status TEXT,p_raw JSONB
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE o public.online_orders;pay public.online_payments;remaining NUMERIC;refunded NUMERIC;state TEXT;
BEGIN
 PERFORM public.require_online_service();
 IF p_status='paid' THEN RETURN public.mark_online_order_paid(p_order_no,p_provider,p_provider_ref,p_amount,p_method,p_raw); END IF;
 IF p_status IS NULL OR p_status NOT IN ('failed','refunded') THEN RAISE EXCEPTION 'Invalid payment status'; END IF;
 SELECT * INTO o FROM public.online_orders WHERE order_no=p_order_no FOR UPDATE;
 SELECT * INTO pay FROM public.online_payments WHERE provider_ref=p_provider_ref FOR UPDATE;
 IF o.id IS NULL OR pay.id IS NULL OR pay.order_id<>o.id OR pay.provider IS DISTINCT FROM p_provider OR pay.method IS DISTINCT FROM p_method
  OR pay.amount IS DISTINCT FROM p_amount OR (p_status='failed' AND o.total IS DISTINCT FROM p_amount) THEN RAISE EXCEPTION 'Payment does not match its checkout'; END IF;
 -- Never downgrade paid to failed, resurrect refunded, or repeat an event.
 IF pay.status=p_status OR pay.status='refunded' OR (pay.status='paid' AND p_status='failed') THEN
  RETURN jsonb_build_object('status',pay.status,'needs_refund',pay.needs_refund);
 END IF;
 UPDATE public.online_payments SET status=p_status,raw=p_raw,needs_refund=false WHERE id=pay.id;
 IF p_status='refunded' THEN
  SELECT coalesce(sum(amount) FILTER(WHERE status='paid' AND NOT needs_refund),0),coalesce(sum(amount) FILTER(WHERE status='refunded'),0)
   INTO remaining,refunded FROM public.online_payments WHERE order_id=o.id;
  state:=CASE WHEN remaining>=o.total AND o.status NOT IN ('expired','cancelled') THEN 'paid' WHEN remaining>0 AND refunded>0 THEN 'partially_refunded' ELSE 'refunded' END;
  UPDATE public.online_orders SET payment_status=state WHERE id=o.id;
 END IF;
 INSERT INTO public.online_order_events(order_id,event,public_message) VALUES(o.id,CASE p_status WHEN 'failed' THEN 'payment_failed' ELSE 'refunded' END,
  CASE p_status WHEN 'failed' THEN 'The payment was not completed. Please contact the shop if money was deducted.' ELSE 'Your payment was refunded.' END);
 RETURN jsonb_build_object('status',p_status,'needs_refund',false);
END $$;

REVOKE ALL ON FUNCTION public.initiate_online_payment(TEXT,UUID,TEXT,TEXT,TEXT),public.record_online_payment_event(TEXT,TEXT,TEXT,NUMERIC,TEXT,TEXT,JSONB),
 public.mark_online_order_paid(TEXT,TEXT,TEXT,NUMERIC,TEXT,JSONB) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.initiate_online_payment(TEXT,UUID,TEXT,TEXT,TEXT),public.record_online_payment_event(TEXT,TEXT,TEXT,NUMERIC,TEXT,TEXT,JSONB),
 public.mark_online_order_paid(TEXT,TEXT,TEXT,NUMERIC,TEXT,JSONB) TO service_role;
