ALTER TABLE public.online_orders ADD COLUMN tracking_version INT NOT NULL DEFAULT 0 CHECK(tracking_version>=0);
-- Staff-recorded tracking only: this RPC never changes payments, stock or order status.
CREATE FUNCTION public.update_online_tracking(p JSONB) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE o public.online_orders; k UUID; old JSONB; kind TEXT; label TEXT; carrier TEXT; tracking TEXT; msg TEXT;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 SELECT * INTO o FROM public.online_orders WHERE id=(p->>'id')::uuid AND public.is_branch_member(branch_id) FOR UPDATE;
 IF o.id IS NULL THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF;
 k:=nullif(p->>'request_id','')::uuid; old:=public.request_begin(k,'update_online_tracking');
 IF old IS NOT NULL THEN
  IF old->>'id'<>o.id::text THEN RAISE EXCEPTION 'Please use a new request id' USING ERRCODE='42501'; END IF;
  RETURN old;
 END IF;
 IF o.fulfilment<>'delivery' OR o.status NOT IN ('shipped','delivered','returned_to_sender') THEN RAISE EXCEPTION 'Tracking updates are available after the delivery order is shipped'; END IF;
 IF o.tracking_version IS DISTINCT FROM (p->>'version')::int THEN RAISE EXCEPTION 'Tracking changed. Refresh the order before saving'; END IF;
 kind:=p->>'kind'; carrier:=trim(p->>'courier'); tracking:=trim(p->>'tracking_no'); msg:=trim(p->>'message');
 label:=CASE kind WHEN 'tracking_details' THEN 'Tracking details corrected' WHEN 'in_transit' THEN 'In transit' WHEN 'out_for_delivery' THEN 'Out for delivery' WHEN 'delivery_attempted' THEN 'Delivery attempted' WHEN 'delayed' THEN 'Delivery delayed' END;
 IF label IS NULL THEN RAISE EXCEPTION 'Choose a delivery update'; END IF;
 IF kind<>'tracking_details' AND o.status<>'shipped' THEN RAISE EXCEPTION 'Delivery updates require a shipped order'; END IF;
 IF coalesce(length(carrier),0) NOT BETWEEN 1 AND 100 OR coalesce(length(tracking),0) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Enter a courier and tracking number, each up to 100 characters'; END IF;
 IF coalesce(length(msg),0) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'Enter a customer update of 3–500 characters'; END IF;
 UPDATE public.online_orders SET courier=carrier,tracking_no=tracking,tracking_version=tracking_version+1 WHERE id=o.id;
 INSERT INTO public.online_order_events(order_id,event,public_message) VALUES(o.id,'shipment_'||kind,label||' · '||carrier||' / '||tracking||': '||msg);
 RETURN public.idempotency_finish(k,jsonb_build_object('id',o.id,'tracking_version',o.tracking_version+1));
END $$;
REVOKE ALL ON FUNCTION public.update_online_tracking(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_online_tracking(JSONB) TO authenticated;
CREATE OR REPLACE FUNCTION public.list_online_orders(p JSONB DEFAULT '{}') RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE n INT; off INT; q TEXT; result JSONB; total INT;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 n:=least(100,greatest(1,coalesce((p->>'limit')::int,24))); off:=greatest(0,coalesce((p->>'offset')::int,0)); q:=lower(trim(coalesce(p->>'q','')));
 SELECT count(*) INTO total FROM public.online_orders o WHERE public.is_branch_member(o.branch_id)
 AND (nullif(p->>'status','') IS NULL OR o.status=p->>'status')
 AND (q='' OR position(q in lower(o.order_no))>0 OR position(q in o.phone)>0 OR position(q in lower(coalesce(o.tracking_no,'')))>0 OR position(q in lower(coalesce(o.courier,'')))>0);
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC,t.id),'[]'::jsonb) INTO result FROM (
 SELECT * FROM public.online_orders o WHERE public.is_branch_member(o.branch_id)
 AND (nullif(p->>'status','') IS NULL OR o.status=p->>'status')
 AND (q='' OR position(q in lower(o.order_no))>0 OR position(q in o.phone)>0 OR position(q in lower(coalesce(o.tracking_no,'')))>0 OR position(q in lower(coalesce(o.courier,'')))>0)
 ORDER BY o.created_at DESC,o.id LIMIT n OFFSET off) t;
 RETURN jsonb_build_object('total_count',total,'orders',result);
END $$;
DO $$ DECLARE def TEXT:=pg_get_functiondef('public.online_order_detail(uuid)'::regprocedure); BEGIN
 IF position('SELECT to_jsonb(o)' IN def)=0 THEN RAISE EXCEPTION 'online_order_detail changed'; END IF;
 EXECUTE replace(def,'SELECT to_jsonb(o)','IF NOT EXISTS(SELECT 1 FROM public.online_orders WHERE id=p_id AND public.is_branch_member(branch_id)) THEN RAISE EXCEPTION ''Order not found'' USING ERRCODE=''42501''; END IF; SELECT to_jsonb(o)');
END $$;

-- Raw staff reads use the same branch scope as the tracking search and detail RPCs.
DROP POLICY counter_read ON public.online_orders;
CREATE POLICY counter_read ON public.online_orders FOR SELECT TO authenticated
 USING(public.is_counter_staff() AND public.is_branch_member(branch_id));
DROP POLICY counter_read ON public.online_order_lines;
CREATE POLICY counter_read ON public.online_order_lines FOR SELECT TO authenticated
 USING(public.is_counter_staff() AND EXISTS(SELECT 1 FROM public.online_orders o WHERE o.id=online_order_lines.order_id AND public.is_branch_member(o.branch_id)));
DROP POLICY counter_read ON public.online_order_events;
CREATE POLICY counter_read ON public.online_order_events FOR SELECT TO authenticated
 USING(public.is_counter_staff() AND EXISTS(SELECT 1 FROM public.online_orders o WHERE o.id=online_order_events.order_id AND public.is_branch_member(o.branch_id)));
DROP POLICY counter_read ON public.online_payments;
CREATE POLICY counter_read ON public.online_payments FOR SELECT TO authenticated
 USING(public.is_counter_staff() AND EXISTS(SELECT 1 FROM public.online_orders o WHERE o.id=online_payments.order_id AND public.is_branch_member(o.branch_id)));
