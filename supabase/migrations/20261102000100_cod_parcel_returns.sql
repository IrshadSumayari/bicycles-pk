-- Courier returns of undelivered, uncollected COD parcels. No cash refund is due.
ALTER TABLE public.online_orders DROP CONSTRAINT online_orders_status_check;
ALTER TABLE public.online_orders ADD CONSTRAINT online_orders_status_check CHECK(status IN
 ('pending_payment','placed','confirmed','packed','ready_for_pickup','shipped','delivered','cancelled','expired','returned_to_sender'));
ALTER TABLE public.returns DROP CONSTRAINT returns_refund_method_check;
ALTER TABLE public.returns ADD CONSTRAINT returns_refund_method_check CHECK(refund_method IN
 ('cash','card','digital','credit','exchange','cod_reversal'));
CREATE TABLE public.courier_returns (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 order_id UUID NOT NULL UNIQUE REFERENCES public.online_orders(id),
 return_id UUID NOT NULL UNIQUE REFERENCES public.returns(id),
 reason TEXT NOT NULL CHECK(length(trim(reason)) BETWEEN 1 AND 1000),
 courier_cost NUMERIC(14,2) NOT NULL CHECK(courier_cost>=0),
 created_by UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.courier_returns ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.courier_returns FROM anon,authenticated;
GRANT SELECT ON public.courier_returns TO authenticated;
CREATE POLICY courier_returns_read ON public.courier_returns FOR SELECT TO authenticated USING (
 public.has_app_role(ARRAY['admin','manager']) AND EXISTS (
 SELECT 1 FROM public.online_orders o WHERE o.id=order_id AND public.is_branch_member(o.branch_id)));
CREATE TRIGGER courier_returns_append_only BEFORE UPDATE OR DELETE ON public.courier_returns
 FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();

CREATE FUNCTION public.receive_cod_parcel_return(p JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE k UUID; replay JSONB; o public.online_orders; sale public.sales; r public.returns;
 line public.sale_lines; item JSONB; condition TEXT; restock BOOLEAN; location UUID;
 fee NUMERIC; result JSONB;
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) THEN
  RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 k:=nullif(p->>'request_id','')::uuid;
 IF k IS NULL THEN RAISE EXCEPTION 'request_id is required'; END IF;
 replay:=public.idempotency_begin(k,'receive_cod_parcel_return'); IF replay IS NOT NULL THEN RETURN replay; END IF;
 SELECT * INTO o FROM public.online_orders WHERE id=nullif(p->>'id','')::uuid FOR UPDATE;
 IF o.id IS NULL OR NOT public.is_branch_member(o.branch_id) THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF;
 IF o.status<>'shipped' OR o.fulfilment<>'delivery' OR o.payment_method<>'cod' OR o.payment_status<>'cod' OR o.sale_id IS NULL THEN
  RAISE EXCEPTION 'Only shipped, uncollected COD parcels can be received here. Use the sales return workflow for paid orders.'; END IF;
 SELECT * INTO sale FROM public.sales WHERE id=o.sale_id FOR UPDATE;
 IF sale.status<>'completed' OR EXISTS(SELECT 1 FROM public.returns WHERE sale_id=sale.id)
 OR EXISTS(SELECT 1 FROM public.payments WHERE sale_id=sale.id)
 OR EXISTS(SELECT 1 FROM public.online_payments WHERE order_id=o.id AND status='paid') THEN
  RAISE EXCEPTION 'This sale has payments or returns. Review it through the sales return workflow.'; END IF;
 IF coalesce(length(trim(p->>'reason')),0) NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'Enter a return reason up to 1000 characters'; END IF;
 IF jsonb_typeof(p->'courier_cost') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Enter the courier cost, including zero if none'; END IF;
 fee:=(p->>'courier_cost')::numeric;
 IF fee<0 OR fee<>round(fee,2) THEN RAISE EXCEPTION 'Courier cost must be non-negative with up to two decimals'; END IF;
 IF jsonb_typeof(p->'lines') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Inspect every parcel item'; END IF;
 IF jsonb_array_length(p->'lines')<>(SELECT count(*) FROM public.online_order_lines WHERE order_id=o.id)
 OR (SELECT count(DISTINCT x->>'variant_id') FROM jsonb_array_elements(p->'lines') x)<>jsonb_array_length(p->'lines')
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p->'lines') x WHERE NOT EXISTS(
 SELECT 1 FROM public.online_order_lines ol WHERE ol.order_id=o.id AND ol.variant_id::text=x->>'variant_id')) THEN
  RAISE EXCEPTION 'Inspect every parcel item exactly once'; END IF;
 INSERT INTO public.returns(return_no,request_id,sale_id,branch_id,location_id,customer_id,reason,refund_total,refund_method)
 VALUES('RTN-'||lpad(nextval('public.return_no_seq')::text,6,'0'),k,sale.id,o.branch_id,sale.location_id,o.customer_id,
 'Courier return: '||trim(p->>'reason'),o.total,'cod_reversal') RETURNING * INTO r;
 FOR line IN SELECT * FROM public.sale_lines WHERE sale_id=sale.id ORDER BY variant_id,id LOOP
  restock:=false; condition:='resaleable';
  IF line.variant_id IS NOT NULL THEN
   SELECT x INTO item FROM jsonb_array_elements(p->'lines') x WHERE x->>'variant_id'=line.variant_id::text;
   condition:=item->>'condition';
   IF condition IS NULL OR condition NOT IN ('resaleable','damaged','faulty') THEN RAISE EXCEPTION 'Choose an inspected condition for every item'; END IF;
   SELECT s.track_inventory INTO restock FROM public.product_variants v JOIN public.product_styles s ON s.id=v.style_id WHERE v.id=line.variant_id;
   restock:=coalesce(restock,false) AND condition='resaleable';
   SELECT ol.location_id INTO location FROM public.online_order_lines ol WHERE ol.order_id=o.id AND ol.variant_id=line.variant_id;
   IF location IS NULL THEN RAISE EXCEPTION 'Original picking location not found'; END IF;
  END IF;
  INSERT INTO public.return_lines(return_id,sale_line_id,variant_id,description,quantity,refund_amount,tax_amount,restocked,condition)
  VALUES(r.id,line.id,line.variant_id,line.description,line.quantity,line.total,line.tax,restock,condition);
  IF restock THEN PERFORM public.post_stock_movement(location,line.variant_id,line.quantity,'return','web','return',r.id,line.unit_cost,r.return_no); END IF;
 END LOOP;
 -- Reverse recognized sale value through the existing returns ledger. No payment
 -- is inserted: an unpaid COD parcel has no customer cash to refund.
 UPDATE public.sales SET status='refunded' WHERE id=sale.id;
 IF o.customer_id IS NOT NULL THEN UPDATE public.customers SET total_purchases=greatest(coalesce(total_purchases,0)-o.total,0) WHERE id=o.customer_id; END IF;
 INSERT INTO public.courier_returns(order_id,return_id,reason,courier_cost) VALUES(o.id,r.id,trim(p->>'reason'),fee);
 UPDATE public.online_orders SET status='returned_to_sender',payment_status='unpaid' WHERE id=o.id;
 INSERT INTO public.online_order_events(order_id,event,public_message)
 VALUES(o.id,'returned_to_sender','The undelivered parcel has been received back by the shop. No COD payment was collected.');
 result:=jsonb_build_object('status','returned_to_sender','return_no',r.return_no,'courier_cost',fee,'cash_refund',0);
 RETURN public.idempotency_finish(k,result);
END $$;
REVOKE ALL ON FUNCTION public.receive_cod_parcel_return(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.receive_cod_parcel_return(JSONB) TO authenticated;
