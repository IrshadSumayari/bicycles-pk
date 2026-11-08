-- Online orders share the shop's physical balances; no separate stock pool.
ALTER TABLE public.app_settings
 ADD COLUMN IF NOT EXISTS online_hold_minutes INT NOT NULL DEFAULT 30 CHECK(online_hold_minutes BETWEEN 1 AND 1440),
 ADD COLUMN IF NOT EXISTS delivery_fee NUMERIC(14,2) NOT NULL DEFAULT 250 CHECK(delivery_fee>=0),
 ADD COLUMN IF NOT EXISTS free_delivery_over NUMERIC(14,2) CHECK(free_delivery_over>=0),
 ADD COLUMN IF NOT EXISTS cod_enabled BOOLEAN NOT NULL DEFAULT true,
 ADD COLUMN IF NOT EXISTS cod_max_total NUMERIC(14,2) CHECK(cod_max_total>=0);
CREATE SEQUENCE IF NOT EXISTS public.online_order_no_seq;
CREATE TABLE IF NOT EXISTS public.online_orders (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),order_no TEXT NOT NULL UNIQUE DEFAULT('WEB-'||lpad(nextval('public.online_order_no_seq')::text,6,'0')),
 request_id UUID NOT NULL UNIQUE,account_id UUID NOT NULL REFERENCES public.customer_accounts(id),customer_id UUID REFERENCES public.customers(id),
 branch_id UUID NOT NULL REFERENCES public.branches(id),
 payment_method TEXT NOT NULL CHECK(payment_method IN ('card','easypaisa','cod')),
 fulfilment TEXT NOT NULL CHECK(fulfilment IN ('pickup','delivery')),
 status TEXT NOT NULL CHECK(status IN ('pending_payment','placed','confirmed','packed','ready_for_pickup','shipped','delivered','cancelled','expired')),
 payment_status TEXT NOT NULL CHECK(payment_status IN ('unpaid','paid','refunded','partially_refunded','cod')),
 contact_name TEXT NOT NULL,phone TEXT NOT NULL,email TEXT,address JSONB,
 delivery_fee NUMERIC(14,2) NOT NULL,subtotal NUMERIC(14,2) NOT NULL,discount NUMERIC(14,2) NOT NULL DEFAULT 0,tax NUMERIC(14,2) NOT NULL,total NUMERIC(14,2) NOT NULL,
 tracking_no TEXT,courier TEXT,notes_customer TEXT,notes_staff TEXT,sale_id UUID UNIQUE REFERENCES public.sales(id),expires_at TIMESTAMPTZ,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),cancelled_reason TEXT
);
CREATE INDEX IF NOT EXISTS online_orders_account ON public.online_orders(account_id,created_at);
CREATE INDEX IF NOT EXISTS online_orders_status ON public.online_orders(status,created_at);
CREATE INDEX IF NOT EXISTS online_orders_expiry ON public.online_orders(expires_at) WHERE status='pending_payment';
CREATE TABLE IF NOT EXISTS public.online_order_lines (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),order_id UUID NOT NULL REFERENCES public.online_orders(id),line_no INT NOT NULL,
 variant_id UUID NOT NULL REFERENCES public.product_variants(id),description TEXT NOT NULL,sku TEXT,size TEXT,color TEXT,unit TEXT NOT NULL,
 quantity NUMERIC(18,6) NOT NULL CHECK(quantity BETWEEN 1 AND 10 AND quantity=trunc(quantity)),unit_price NUMERIC(14,2) NOT NULL,
 taxable BOOLEAN NOT NULL,tax NUMERIC(14,2) NOT NULL,total NUMERIC(14,2) NOT NULL,
 location_id UUID NOT NULL REFERENCES public.locations(id),reservation_id UUID NOT NULL UNIQUE REFERENCES public.stock_reservations(id),
 UNIQUE(order_id,line_no),UNIQUE(order_id,variant_id)
);
CREATE TABLE IF NOT EXISTS public.online_order_events (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),order_id UUID NOT NULL REFERENCES public.online_orders(id),event TEXT NOT NULL,public_message TEXT,
 created_by UUID DEFAULT auth.uid() REFERENCES auth.users(id),created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS online_events_order ON public.online_order_events(order_id,created_at);
CREATE TABLE IF NOT EXISTS public.online_payments (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),order_id UUID NOT NULL REFERENCES public.online_orders(id),provider TEXT NOT NULL,
 method TEXT NOT NULL CHECK(method IN ('card','wallet')),provider_ref TEXT NOT NULL UNIQUE,amount NUMERIC(14,2) NOT NULL CHECK(amount>=0),
 status TEXT NOT NULL CHECK(status IN ('initiated','paid','failed','refunded')),needs_refund BOOLEAN NOT NULL DEFAULT false,raw JSONB,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS online_payments_order ON public.online_payments(order_id);
DROP TRIGGER IF EXISTS online_orders_updated ON public.online_orders;
CREATE TRIGGER online_orders_updated BEFORE UPDATE ON public.online_orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS online_payments_updated ON public.online_payments;
CREATE TRIGGER online_payments_updated BEFORE UPDATE ON public.online_payments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS online_events_append_only ON public.online_order_events;
CREATE TRIGGER online_events_append_only BEFORE UPDATE OR DELETE ON public.online_order_events FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();
DO $$ DECLARE t TEXT; BEGIN
 FOREACH t IN ARRAY ARRAY['online_orders','online_order_lines','online_order_events','online_payments'] LOOP
 EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
 EXECUTE format('DROP POLICY IF EXISTS counter_read ON public.%I',t);
 EXECUTE format('CREATE POLICY counter_read ON public.%I FOR SELECT TO authenticated USING(public.is_counter_staff())',t);
 EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated',t);
 EXECUTE format('GRANT SELECT ON public.%I TO authenticated',t);
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.online_order_public(p_id UUID) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT jsonb_build_object('order_no',o.order_no,'status',o.status,'payment_status',o.payment_status,'payment_method',o.payment_method,
 'fulfilment',o.fulfilment,'contact_name',o.contact_name,'phone',o.phone,'email',o.email,'address',o.address,'delivery_fee',o.delivery_fee,
 'subtotal',o.subtotal,'discount',o.discount,'tax',o.tax,'total',o.total,'tracking_no',o.tracking_no,'courier',o.courier,'notes_customer',o.notes_customer,
 'expires_at',o.expires_at,'created_at',o.created_at,'updated_at',o.updated_at,'cancelled_reason',o.cancelled_reason,
 'lines',(SELECT coalesce(jsonb_agg(jsonb_build_object('line_no',l.line_no,'variant_id',l.variant_id,'description',l.description,'sku',l.sku,'size',l.size,'color',l.color,
 'unit',l.unit,'quantity',l.quantity,'unit_price',l.unit_price,'taxable',l.taxable,'tax',l.tax,'total',l.total) ORDER BY l.line_no),'[]') FROM public.online_order_lines l WHERE l.order_id=o.id),
 'events',(SELECT coalesce(jsonb_agg(jsonb_build_object('event',e.event,'message',e.public_message,'created_at',e.created_at) ORDER BY e.created_at,e.id),'[]')
 FROM public.online_order_events e WHERE e.order_id=o.id AND e.public_message IS NOT NULL)) FROM public.online_orders o WHERE o.id=p_id
$$;

CREATE OR REPLACE FUNCTION public.my_online_orders() RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE a UUID;
BEGIN
 a:=public.require_website_customer();
 RETURN coalesce((SELECT jsonb_agg(public.online_order_public(id) ORDER BY created_at DESC,id) FROM public.online_orders WHERE account_id=a),'[]');
END $$;
CREATE OR REPLACE FUNCTION public.my_online_order(p_order_no TEXT) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE a UUID;v UUID;
BEGIN
 a:=public.require_website_customer();SELECT id INTO v FROM public.online_orders WHERE order_no=p_order_no AND account_id=a;
 IF v IS NULL THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF;
 RETURN public.online_order_public(v);
END $$;

CREATE OR REPLACE FUNCTION public.cancel_online_order_internal(p_id UUID,p_reason TEXT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE o public.online_orders;
BEGIN
 SELECT * INTO o FROM public.online_orders WHERE id=p_id FOR UPDATE;
 IF o.sale_id IS NOT NULL THEN RAISE EXCEPTION 'Use the returns screen for packed orders'; END IF;
 IF o.status IN ('cancelled','expired') THEN RETURN jsonb_build_object('status',o.status); END IF;
 PERFORM public.close_online_reservations(o.id,'released');
 UPDATE public.online_orders SET status='cancelled',cancelled_reason=p_reason,expires_at=NULL WHERE id=o.id;
 UPDATE public.online_payments SET needs_refund=true WHERE order_id=o.id AND status='paid';
 INSERT INTO public.online_order_events(order_id,event,public_message) VALUES(o.id,'cancelled','Your order was cancelled. Any captured payment will be refunded.');
 RETURN jsonb_build_object('status','cancelled');
END $$;
CREATE OR REPLACE FUNCTION public.cancel_my_online_order(p_order_no TEXT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE a UUID;o public.online_orders;
BEGIN
 a:=public.require_website_customer();SELECT * INTO o FROM public.online_orders WHERE order_no=p_order_no AND account_id=a FOR UPDATE;
 IF o.id IS NULL THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF;
 IF o.status='cancelled' THEN RETURN jsonb_build_object('status','cancelled'); END IF;
 IF o.status NOT IN ('pending_payment','placed') THEN RAISE EXCEPTION 'Please contact the shop to cancel this order'; END IF;
 RETURN public.cancel_online_order_internal(o.id,'Cancelled by customer');
END $$;

CREATE OR REPLACE FUNCTION public.list_online_orders(p JSONB DEFAULT '{}') RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE n INT;off INT;q TEXT;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 n:=least(100,greatest(1,coalesce((p->>'limit')::int,24)));off:=greatest(0,coalesce((p->>'offset')::int,0));q:=trim(coalesce(p->>'q',''));
 RETURN jsonb_build_object('total_count',(SELECT count(*) FROM public.online_orders WHERE (nullif(p->>'status','') IS NULL OR status=p->>'status') AND (q='' OR position(lower(q) in lower(order_no))>0 OR position(q in phone)>0)),
 'orders',coalesce((SELECT jsonb_agg(to_jsonb(o) ORDER BY created_at DESC,id) FROM (SELECT * FROM public.online_orders WHERE (nullif(p->>'status','') IS NULL OR status=p->>'status')
 AND (q='' OR position(lower(q) in lower(order_no))>0 OR position(q in phone)>0) ORDER BY created_at DESC,id LIMIT n OFFSET off) o),'[]'));
END $$;
CREATE OR REPLACE FUNCTION public.online_order_detail(p_id UUID) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE r JSONB;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 SELECT to_jsonb(o)||jsonb_build_object('lines',(SELECT coalesce(jsonb_agg(to_jsonb(l) ORDER BY line_no),'[]') FROM public.online_order_lines l WHERE l.order_id=o.id),
 'events',(SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY created_at,id),'[]') FROM public.online_order_events e WHERE e.order_id=o.id),
 'payments',(SELECT coalesce(jsonb_agg(to_jsonb(pay) ORDER BY created_at,id),'[]') FROM public.online_payments pay WHERE pay.order_id=o.id)) INTO r FROM public.online_orders o WHERE o.id=p_id;
 IF r IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.advance_online_order(p JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE k UUID;r JSONB;o public.online_orders;target TEXT;l public.online_order_lines;cost NUMERIC;header public.sales;invoice TEXT;profile public.users;location UUID;paid public.online_payments;reservation public.stock_reservations;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 k:=nullif(p->>'request_id','')::uuid;r:=public.tailoring_request_begin(k,'advance_online_order');IF r IS NOT NULL THEN RETURN r;END IF;
 SELECT * INTO o FROM public.online_orders WHERE id=nullif(p->>'id','')::uuid FOR UPDATE;
 IF o.id IS NULL OR NOT public.is_branch_member(o.branch_id) THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF;
 target:=p->>'status';
 IF target=o.status THEN RETURN public.idempotency_finish(k,jsonb_build_object('status',o.status,'sale_id',o.sale_id)); END IF;
 IF target IS NULL OR NOT ((o.status='placed' AND target='confirmed') OR (o.status='confirmed' AND target='packed')
  OR (o.status='packed' AND target=CASE WHEN o.fulfilment='pickup' THEN 'ready_for_pickup' ELSE 'shipped' END)
  OR (o.status IN ('ready_for_pickup','shipped') AND target='delivered')) THEN RAISE EXCEPTION 'That order status transition is not allowed'; END IF;
 IF o.payment_method<>'cod' AND o.payment_status<>'paid' THEN RAISE EXCEPTION 'Confirm the online payment before preparing this order'; END IF;
 IF target='delivered' AND o.payment_status<>'paid' THEN RAISE EXCEPTION 'Collect payment before marking the order delivered'; END IF;
 IF target='shipped' AND (coalesce(length(trim(p->>'tracking_no')),0) NOT BETWEEN 1 AND 100 OR coalesce(length(trim(p->>'courier')),0) NOT BETWEEN 1 AND 100) THEN RAISE EXCEPTION 'Enter the courier and tracking number'; END IF;
 IF target='packed' THEN
  IF o.sale_id IS NOT NULL THEN RAISE EXCEPTION 'This order already has a sale'; END IF;
  SELECT id INTO location FROM public.locations WHERE branch_id=o.branch_id AND kind='online' AND active ORDER BY id LIMIT 1;
  IF location IS NULL THEN RAISE EXCEPTION 'Set up an active online location for this branch'; END IF;
  SELECT * INTO profile FROM public.users WHERE id=auth.uid();invoice:=public.generate_invoice_number();
  -- Preserve the priced order. Do not run till promotions/pricing a second time.
  INSERT INTO public.sales(invoice_number,receipt_number,request_id,branch_id,location_id,channel,customer_id,customer_name,items,subtotal,discount_amount,tax_amount,total,
   payment_method,status,cashier,cashier_id,cashier_role,notes)
  VALUES(invoice,invoice,o.id,o.branch_id,location,'web',o.customer_id,o.contact_name,
   (SELECT jsonb_agg(jsonb_build_object('product',jsonb_build_object('id',variant_id,'name',description,'sku',sku,'price',unit_price,'unit',unit),'quantity',quantity,'price',unit_price,'total',total,'discount',0) ORDER BY line_no) FROM public.online_order_lines WHERE order_id=o.id),
   o.subtotal+o.delivery_fee,o.discount,o.tax,o.total,CASE o.payment_method WHEN 'easypaisa' THEN 'digital' WHEN 'card' THEN 'card' ELSE 'cash' END,'completed',profile.name,profile.id,profile.role,'Online order '||o.order_no) RETURNING * INTO header;
  -- Release only these reservations before the ledger takes the units. All locks
  -- remain held until the sale and order status commit together.
  PERFORM public.close_online_reservations(o.id,'consumed');
  FOR l IN SELECT * FROM public.online_order_lines WHERE order_id=o.id ORDER BY variant_id,location_id LOOP
   SELECT unit_cost INTO cost FROM public.variant_costs WHERE variant_id=l.variant_id;
   SELECT * INTO reservation FROM public.stock_reservations WHERE id=l.reservation_id;
   PERFORM public.post_stock_movement(l.location_id,l.variant_id,-l.quantity,'sale','web','sale',header.id,cost,NULL,reservation.roll_id);
   INSERT INTO public.sale_lines(sale_id,line_no,variant_id,description,sku,unit,quantity,unit_price,gross,net,taxable,tax,total,unit_cost)
   VALUES(header.id,l.line_no,l.variant_id,l.description,l.sku,l.unit,l.quantity,l.unit_price,round(l.unit_price*l.quantity,2),round(l.unit_price*l.quantity,2),l.taxable,l.tax,l.total,coalesce(cost,0));
  END LOOP;
  -- Delivery is a separate untaxed service line, so invoice and line totals agree.
  IF o.delivery_fee>0 THEN
   INSERT INTO public.sale_lines(sale_id,line_no,description,unit,quantity,unit_price,gross,net,taxable,tax,total,unit_cost)
   VALUES(header.id,(SELECT max(line_no)+1 FROM public.online_order_lines WHERE order_id=o.id),'Delivery fee','piece',1,o.delivery_fee,o.delivery_fee,o.delivery_fee,false,0,o.delivery_fee,0);
  END IF;
  IF o.payment_method<>'cod' THEN
   SELECT * INTO paid FROM public.online_payments WHERE order_id=o.id AND status='paid' AND NOT needs_refund ORDER BY created_at,id LIMIT 1;
   IF paid.id IS NULL THEN RAISE EXCEPTION 'The online payment could not be found'; END IF;
   INSERT INTO public.payments(sale_id,method,amount,reference,bank_name,direction)
   VALUES(header.id,CASE WHEN paid.method='card' THEN 'card' ELSE 'digital' END,o.total,paid.provider_ref,CASE WHEN paid.method='wallet' THEN 'Easypaisa' END,'in');
  END IF;
  UPDATE public.online_orders SET sale_id=header.id WHERE id=o.id;o.sale_id:=header.id;
 END IF;
 UPDATE public.online_orders SET status=target,tracking_no=CASE WHEN target='shipped' THEN trim(p->>'tracking_no') ELSE tracking_no END,
 courier=CASE WHEN target='shipped' THEN trim(p->>'courier') ELSE courier END WHERE id=o.id;
 INSERT INTO public.online_order_events(order_id,event,public_message) VALUES(o.id,target,CASE target WHEN 'confirmed' THEN 'The shop confirmed your order.' WHEN 'packed' THEN 'Your order has been packed.' WHEN 'ready_for_pickup' THEN 'Your order is ready for pickup.' WHEN 'shipped' THEN 'Your order has been shipped.' ELSE 'Your order has been delivered.' END);
 RETURN public.idempotency_finish(k,jsonb_build_object('status',target,'sale_id',o.sale_id));
END $$;

CREATE OR REPLACE FUNCTION public.collect_cod_payment(p JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE k UUID;r JSONB;o public.online_orders;pay JSONB;amount NUMERIC;paid NUMERIC:=0;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 k:=nullif(p->>'request_id','')::uuid;r:=public.tailoring_request_begin(k,'collect_cod_payment');IF r IS NOT NULL THEN RETURN r;END IF;
 SELECT * INTO o FROM public.online_orders WHERE id=nullif(p->>'id','')::uuid FOR UPDATE;
 IF o.id IS NULL OR NOT public.is_branch_member(o.branch_id) THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF;
 IF o.payment_method<>'cod' OR o.sale_id IS NULL OR o.status NOT IN ('ready_for_pickup','shipped') THEN RAISE EXCEPTION 'Collect COD payment at pickup or delivery'; END IF;
 IF o.payment_status='paid' THEN RETURN public.idempotency_finish(k,jsonb_build_object('payment_status','paid')); END IF;
 IF jsonb_typeof(p->'payments') IS DISTINCT FROM 'array' OR jsonb_array_length(p->'payments')=0 THEN RAISE EXCEPTION 'Add a cash or card payment'; END IF;
 FOR pay IN SELECT jsonb_array_elements(p->'payments') LOOP
  IF coalesce(pay->>'method','') NOT IN ('cash','card') OR jsonb_typeof(pay->'amount') IS DISTINCT FROM 'number' OR (pay->>'amount')::numeric<=0 OR (pay->>'amount')::numeric<>round((pay->>'amount')::numeric,2) THEN RAISE EXCEPTION 'Enter a positive cash or card amount with up to two decimals'; END IF;
  amount:=(pay->>'amount')::numeric;
  IF pay->>'method'='cash' AND nullif(pay->>'tendered','') IS NOT NULL AND (pay->>'tendered')::numeric<amount THEN RAISE EXCEPTION 'Cash received is less than the cash amount'; END IF;
  INSERT INTO public.payments(sale_id,method,amount,reference,card_last4,tendered,change_given,direction)
  VALUES(o.sale_id,pay->>'method',amount,left(pay->>'reference',100),CASE WHEN pay->>'method'='card' THEN nullif(pay->>'card_last4','') END,
   CASE WHEN pay->>'method'='cash' THEN nullif(pay->>'tendered','')::numeric END,
   CASE WHEN pay->>'method'='cash' THEN coalesce(nullif(pay->>'tendered','')::numeric,amount)-amount ELSE 0 END,'in');
  paid:=paid+amount;
 END LOOP;
 IF paid<>o.total THEN RAISE EXCEPTION 'The payment must equal the order total'; END IF;
 UPDATE public.online_orders SET payment_status='paid' WHERE id=o.id;
 INSERT INTO public.online_order_events(order_id,event,public_message) VALUES(o.id,'cod_paid','Your payment was received.');
 RETURN public.idempotency_finish(k,jsonb_build_object('payment_status','paid'));
END $$;

CREATE OR REPLACE FUNCTION public.cancel_online_order(p JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE k UUID;r JSONB;o public.online_orders;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 k:=nullif(p->>'request_id','')::uuid;r:=public.tailoring_request_begin(k,'cancel_online_order');IF r IS NOT NULL THEN RETURN r;END IF;
 SELECT * INTO o FROM public.online_orders WHERE id=nullif(p->>'id','')::uuid FOR UPDATE;
 IF o.id IS NULL OR NOT public.is_branch_member(o.branch_id) THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF;
 IF coalesce(length(trim(p->>'reason')),0) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'Enter a cancellation reason of at most 2000 characters'; END IF;
 RETURN public.idempotency_finish(k,public.cancel_online_order_internal(o.id,trim(p->>'reason')));
END $$;

CREATE OR REPLACE FUNCTION public.record_online_refund(p JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE k UUID;r JSONB;o public.online_orders;payment public.online_payments;left_paid NUMERIC;refunded NUMERIC;state TEXT;
BEGIN
 IF NOT public.has_app_role(ARRAY['admin','manager']) THEN RAISE EXCEPTION 'Only managers can record an online refund' USING ERRCODE='42501'; END IF;
 k:=nullif(p->>'request_id','')::uuid;r:=public.tailoring_request_begin(k,'record_online_refund');IF r IS NOT NULL THEN RETURN r;END IF;
 SELECT oo.* INTO o FROM public.online_orders oo JOIN public.online_payments op ON op.order_id=oo.id WHERE op.provider_ref=p->>'provider_ref' FOR UPDATE OF oo;
 SELECT * INTO payment FROM public.online_payments WHERE provider_ref=p->>'provider_ref' FOR UPDATE;
 IF payment.id IS NULL OR NOT public.is_branch_member(o.branch_id) THEN RAISE EXCEPTION 'Online payment not found'; END IF;
 IF payment.status NOT IN ('paid','failed','refunded') THEN RAISE EXCEPTION 'This payment has not been captured'; END IF;
 IF payment.status<>'refunded' THEN
  UPDATE public.online_payments SET status='refunded',needs_refund=false WHERE id=payment.id;
  SELECT coalesce(sum(amount) FILTER(WHERE status='paid'),0),coalesce(sum(amount) FILTER(WHERE status='refunded'),0) INTO left_paid,refunded FROM public.online_payments WHERE order_id=o.id;
  state:=CASE WHEN left_paid>=o.total AND o.status NOT IN ('cancelled','expired') THEN 'paid' WHEN left_paid>0 AND refunded>0 THEN 'partially_refunded' ELSE 'refunded' END;
  UPDATE public.online_orders SET payment_status=state WHERE id=o.id;
  INSERT INTO public.online_order_events(order_id,event,public_message) VALUES(o.id,'refunded','The shop recorded your payment refund.');
 ELSE state:=o.payment_status;
 END IF;
 RETURN public.idempotency_finish(k,jsonb_build_object('payment_status',state));
END $$;
REVOKE ALL ON SEQUENCE public.online_order_no_seq FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.require_online_service() RETURNS VOID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
 -- cron runs as postgres without a JWT; a caller-supplied claim cannot impersonate it.
 IF coalesce(auth.role(),'')<>'service_role' AND NOT (session_user IN ('postgres','supabase_admin') AND auth.uid() IS NULL AND coalesce(auth.role(),'')='') THEN
 RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.quote_online_order(p JSONB) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE s public.app_settings;item JSONB;v RECORD;qty NUMERIC;net NUMERIC(14,2);tax NUMERIC(14,2);sub NUMERIC(14,2):=0;taxes NUMERIC(14,2):=0;fee NUMERIC(14,2);total NUMERIC(14,2);lines JSONB:='[]';name TEXT;available BOOLEAN;
BEGIN
 IF p->>'fulfilment' IS NULL OR p->>'fulfilment' NOT IN ('pickup','delivery') THEN RAISE EXCEPTION 'Choose pickup or delivery'; END IF;
 IF jsonb_typeof(p->'lines') IS DISTINCT FROM 'array' OR jsonb_array_length(p->'lines') NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'Add between one and fifty items'; END IF;
 IF (SELECT count(*) FROM jsonb_array_elements(p->'lines'))<>(SELECT count(DISTINCT x->>'variant_id') FROM jsonb_array_elements(p->'lines') x) THEN RAISE EXCEPTION 'Combine duplicate items into one line'; END IF;
 SELECT * INTO s FROM public.app_settings ORDER BY created_at,id LIMIT 1;
 IF s.id IS NULL THEN RAISE EXCEPTION 'Store settings not found'; END IF;
 FOR item IN SELECT jsonb_array_elements(p->'lines') LOOP
  IF jsonb_typeof(item->'quantity') IS DISTINCT FROM 'number' OR (item->>'quantity')::numeric NOT BETWEEN 1 AND 10 OR (item->>'quantity')::numeric<>trunc((item->>'quantity')::numeric) THEN RAISE EXCEPTION 'Choose a whole quantity from 1 to 10'; END IF;
  qty:=(item->>'quantity')::numeric;
  SELECT c.*,ps.taxable,ps.track_inventory INTO v FROM public.public_catalog c JOIN public.product_styles ps ON ps.id=c.style_id WHERE c.variant_id=nullif(item->>'variant_id','')::uuid AND c.price>0;
  IF NOT FOUND THEN
   SELECT ps.name INTO name FROM public.product_variants pv JOIN public.product_styles ps ON ps.id=pv.style_id WHERE pv.id=nullif(item->>'variant_id','')::uuid;
   RAISE EXCEPTION '% is not available online',coalesce(name,'That item');
  END IF;
  net:=round(v.price*qty,2);
  -- Same additive, per-line tax rule used by quote_sale/post_sale; delivery is untaxed.
  tax:=CASE WHEN v.taxable THEN round(net*coalesce(s.tax_rate,0)/100,2) ELSE 0 END;
  SELECT EXISTS(SELECT 1 FROM public.stock_balances b JOIN public.locations l ON l.id=b.location_id WHERE b.variant_id=v.variant_id AND l.active
   AND l.branch_id=public.default_branch_id() AND l.kind IN ('shop_floor','stockroom','online') AND b.on_hand-b.reserved>=qty
   AND (v.unit<>'meter' OR EXISTS(SELECT 1 FROM public.fabric_rolls r WHERE r.variant_id=b.variant_id AND r.location_id=b.location_id AND r.remaining_length-r.reserved_length>=qty))) INTO available;
  lines:=lines||jsonb_build_array(jsonb_build_object('variant_id',v.variant_id,'description',v.title,'sku',v.sku,'size',v.size,'color',v.color,'unit',v.unit,
   'quantity',qty,'unit_price',v.price,'taxable',v.taxable,'tax',tax,'total',net+tax,'availability',CASE WHEN NOT available THEN 'out_of_stock' ELSE v.stock_level END));
  sub:=sub+net;taxes:=taxes+tax;
 END LOOP;
 fee:=CASE WHEN p->>'fulfilment'='pickup' OR (s.free_delivery_over IS NOT NULL AND sub>=s.free_delivery_over) THEN 0 ELSE s.delivery_fee END;
 total:=sub+taxes+fee;
 RETURN jsonb_build_object('lines',lines,'subtotal',sub,'discount',0,'tax',taxes,'delivery_fee',fee,'total',total,'cod_allowed',s.cod_enabled AND (s.cod_max_total IS NULL OR total<=s.cod_max_total));
END $$;

CREATE OR REPLACE FUNCTION public.create_online_order(p JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE a UUID;k UUID;cached JSONB;q JSONB;o public.online_orders;account public.customer_accounts;s public.app_settings;item JSONB;loc RECORD;chosen UUID;res public.stock_reservations;qty NUMERIC;customer UUID;ph TEXT;note TEXT;line INT:=0;hold TIMESTAMPTZ;method TEXT;
BEGIN
 a:=public.require_website_customer();k:=nullif(p->>'request_id','')::uuid;
 cached:=public.tailoring_request_begin(k,'create_online_order');IF cached IS NOT NULL THEN RETURN cached;END IF;
 SELECT * INTO account FROM public.customer_accounts WHERE id=a FOR UPDATE;
 q:=public.quote_online_order(p);method:=p->>'payment_method';
 IF method IS NULL OR method NOT IN ('card','easypaisa','cod') THEN RAISE EXCEPTION 'Choose card, Easypaisa or cash on delivery'; END IF;
 IF method='cod' AND NOT (q->>'cod_allowed')::boolean THEN RAISE EXCEPTION 'Cash on delivery is unavailable for this order'; END IF;
 ph:=public.normalize_phone(p->>'phone');
 IF coalesce(length(trim(p->>'contact_name')),0) NOT BETWEEN 1 AND 200 OR ph IS NULL OR ph !~ '^\+?[0-9]{10,15}$' THEN RAISE EXCEPTION 'Enter your contact name and a valid phone number'; END IF;
 IF length(p->>'email')>254 OR length(p->>'notes_customer')>2000 THEN RAISE EXCEPTION 'Keep email under 255 characters and notes under 2001'; END IF;
 IF p->>'fulfilment'='delivery' AND (jsonb_typeof(p->'address') IS DISTINCT FROM 'object' OR coalesce(length(trim(p->'address'->>'line1')),0) NOT BETWEEN 1 AND 300
  OR coalesce(length(trim(p->'address'->>'city')),0) NOT BETWEEN 1 AND 100 OR length(p->'address'->>'line2')>300 OR length(p->'address'->>'postal_code')>20) THEN RAISE EXCEPTION 'Enter the delivery address and city'; END IF;
 SELECT * INTO s FROM public.app_settings ORDER BY created_at,id LIMIT 1;
 hold:=CASE WHEN method<>'cod' THEN now()+make_interval(mins=>s.online_hold_minutes) END;
 customer:=account.customer_id;
 IF customer IS NULL THEN
  -- Phone matching alone is not identity verification. Serialize competing creates by phone.
  PERFORM pg_advisory_xact_lock(hashtextextended(ph,28000000));
  IF EXISTS(SELECT 1 FROM public.customers WHERE phone=ph) THEN note:='Contact phone matches an existing shop customer; verify identity and link in the shop.';
  ELSE INSERT INTO public.customers(name,phone,email) VALUES(trim(p->>'contact_name'),ph,nullif(trim(p->>'email'),'')) RETURNING id INTO customer; END IF;
 END IF;
 INSERT INTO public.online_orders(request_id,account_id,customer_id,branch_id,payment_method,fulfilment,status,payment_status,contact_name,phone,email,address,
  delivery_fee,subtotal,discount,tax,total,notes_customer,notes_staff,expires_at)
 VALUES(k,a,customer,public.default_branch_id(),method,p->>'fulfilment',CASE WHEN method='cod' THEN 'placed' ELSE 'pending_payment' END,CASE WHEN method='cod' THEN 'cod' ELSE 'unpaid' END,
 trim(p->>'contact_name'),ph,nullif(trim(p->>'email'),''),CASE WHEN p->>'fulfilment'='delivery' THEN jsonb_build_object('line1',trim(p->'address'->>'line1'),'line2',p->'address'->>'line2','city',trim(p->'address'->>'city'),'postal_code',p->'address'->>'postal_code') END,
 (q->>'delivery_fee')::numeric,(q->>'subtotal')::numeric,0,(q->>'tax')::numeric,(q->>'total')::numeric,nullif(trim(p->>'notes_customer'),''),note,hold) RETURNING * INTO o;
 -- All stock locks follow the same (variant, location) order, including zero balances.
 FOR item IN SELECT value FROM jsonb_array_elements(q->'lines') ORDER BY (value->>'variant_id')::uuid LOOP
  FOR loc IN SELECT id FROM public.locations WHERE active AND branch_id=o.branch_id AND kind IN ('shop_floor','stockroom','online') ORDER BY id LOOP
   PERFORM public.lock_stock_balance(loc.id,(item->>'variant_id')::uuid);
  END LOOP;
 END LOOP;
 FOR item IN SELECT value FROM jsonb_array_elements(q->'lines') LOOP
  qty:=(item->>'quantity')::numeric;
  SELECT b.location_id INTO chosen FROM public.stock_balances b JOIN public.locations l ON l.id=b.location_id
  WHERE b.variant_id=(item->>'variant_id')::uuid AND l.active AND l.branch_id=o.branch_id AND l.kind IN ('shop_floor','stockroom','online') AND b.on_hand-b.reserved>=qty
   AND (item->>'unit'<>'meter' OR EXISTS(SELECT 1 FROM public.fabric_rolls r WHERE r.variant_id=b.variant_id AND r.location_id=b.location_id AND r.remaining_length-r.reserved_length>=qty))
  ORDER BY b.on_hand-b.reserved DESC,b.location_id LIMIT 1;
  IF chosen IS NULL THEN RAISE EXCEPTION '% is sold out',item->>'description'; END IF;
  IF item->>'unit'='meter' THEN
   res:=public.reserve_roll_length((item->>'variant_id')::uuid,chosen,qty,NULL,'online_order',o.id);
   UPDATE public.stock_reservations SET channel='web',expires_at=hold WHERE id=res.id;
  ELSE
   UPDATE public.stock_balances SET reserved=reserved+qty,updated_at=now() WHERE location_id=chosen AND variant_id=(item->>'variant_id')::uuid;
   INSERT INTO public.stock_reservations(branch_id,location_id,variant_id,quantity,channel,reference_type,reference_id,expires_at)
   VALUES(o.branch_id,chosen,(item->>'variant_id')::uuid,qty,'web','online_order',o.id,hold) RETURNING * INTO res;
  END IF;
  line:=line+1;
  INSERT INTO public.online_order_lines(order_id,line_no,variant_id,description,sku,size,color,unit,quantity,unit_price,taxable,tax,total,location_id,reservation_id)
  VALUES(o.id,line,(item->>'variant_id')::uuid,item->>'description',item->>'sku',item->>'size',item->>'color',item->>'unit',qty,(item->>'unit_price')::numeric,(item->>'taxable')::boolean,(item->>'tax')::numeric,(item->>'total')::numeric,chosen,res.id);
 END LOOP;
 INSERT INTO public.online_order_events(order_id,event,public_message) VALUES(o.id,o.status,'Your order has been received.');
 RETURN public.idempotency_finish(k,jsonb_build_object('id',o.id,'order_no',o.order_no,'status',o.status,'subtotal',o.subtotal,'discount',o.discount,'tax',o.tax,'delivery_fee',o.delivery_fee,'total',o.total,'expires_at',o.expires_at));
END $$;

CREATE OR REPLACE FUNCTION public.close_online_reservations(p_order UUID,p_status TEXT) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r public.stock_reservations;
BEGIN
 FOR r IN SELECT sr.* FROM public.stock_reservations sr JOIN public.online_order_lines l ON l.reservation_id=sr.id WHERE l.order_id=p_order ORDER BY sr.variant_id,sr.location_id,sr.id FOR UPDATE OF sr LOOP
  IF r.status<>'active' THEN
   IF p_status='consumed' THEN RAISE EXCEPTION 'The reserved stock is no longer available. Please check this order.'; END IF;
   CONTINUE;
  END IF;
  PERFORM public.close_reservation(r.id,p_status);
  IF r.roll_id IS NOT NULL THEN UPDATE public.fabric_rolls SET reserved_length=reserved_length-r.quantity WHERE id=r.roll_id; END IF;
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.expire_online_orders() RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE o public.online_orders;n INT:=0;
BEGIN
 PERFORM public.require_online_service();
 FOR o IN SELECT * FROM public.online_orders WHERE status='pending_payment' AND expires_at<=now() ORDER BY id FOR UPDATE SKIP LOCKED LOOP
  PERFORM public.close_online_reservations(o.id,'expired');
  UPDATE public.online_orders SET status='expired' WHERE id=o.id;
  INSERT INTO public.online_order_events(order_id,event,public_message) VALUES(o.id,'expired','The payment window expired. Please place a new order.');n:=n+1;
 END LOOP;
 RETURN n;
END $$;

CREATE OR REPLACE FUNCTION public.mark_online_order_paid(p_order_no TEXT,p_provider TEXT,p_provider_ref TEXT,p_amount NUMERIC,p_method TEXT,p_raw JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE o public.online_orders;paid public.online_payments;refund BOOLEAN;failed BOOLEAN;
BEGIN
 PERFORM public.require_online_service();
 IF coalesce(length(trim(p_provider_ref)),0) NOT BETWEEN 1 AND 200 OR coalesce(length(trim(p_provider)),0) NOT BETWEEN 1 AND 50 OR p_method IS NULL OR p_method NOT IN ('card','wallet') OR p_amount IS NULL OR p_amount<0 OR p_amount<>round(p_amount,2) THEN RAISE EXCEPTION 'Invalid payment notification'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_provider_ref,28000001));
 SELECT * INTO paid FROM public.online_payments WHERE provider_ref=p_provider_ref;
 IF FOUND THEN
  IF NOT EXISTS(SELECT 1 FROM public.online_orders WHERE id=paid.order_id AND order_no=p_order_no) OR paid.provider<>p_provider OR paid.amount<>p_amount OR paid.method<>p_method THEN RAISE EXCEPTION 'Payment reference already belongs to another notification'; END IF;
  RETURN jsonb_build_object('status',paid.status,'needs_refund',paid.needs_refund);
 END IF;
 SELECT * INTO o FROM public.online_orders WHERE order_no=p_order_no FOR UPDATE;
 IF o.id IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;
 -- A webhook arriving after the deadline must not beat the next cron tick.
 IF o.status='pending_payment' AND o.expires_at<=now() THEN
  PERFORM public.close_online_reservations(o.id,'expired');UPDATE public.online_orders SET status='expired' WHERE id=o.id;o.status:='expired';
  INSERT INTO public.online_order_events(order_id,event,public_message) VALUES(o.id,'expired','The payment window expired.');
 END IF;
 failed:=p_amount<>o.total OR o.payment_method='cod' OR (o.payment_method='card' AND p_method<>'card') OR (o.payment_method='easypaisa' AND p_method<>'wallet');
 refund:=o.status IN ('expired','cancelled') OR o.payment_status IN ('paid','refunded','partially_refunded');
 INSERT INTO public.online_payments(order_id,provider,method,provider_ref,amount,status,needs_refund,raw)
 VALUES(o.id,p_provider,p_method,p_provider_ref,p_amount,CASE WHEN failed THEN 'failed' ELSE 'paid' END,refund OR failed,p_raw) RETURNING * INTO paid;
 IF NOT failed AND o.status='pending_payment' AND NOT refund THEN
  UPDATE public.online_orders SET status='placed',payment_status='paid',expires_at=NULL WHERE id=o.id;
  UPDATE public.stock_reservations SET expires_at=NULL WHERE reference_type='online_order' AND reference_id=o.id AND status='active';
 END IF;
 INSERT INTO public.online_order_events(order_id,event,public_message) VALUES(o.id,CASE WHEN failed THEN 'payment_failed' WHEN refund THEN 'payment_needs_refund' ELSE 'paid' END,
 CASE WHEN failed THEN 'The payment could not be matched to the order. Please contact the shop.' WHEN refund THEN 'A payment arrived for an order that cannot be fulfilled. The shop will arrange a refund.' ELSE 'Your payment was received.' END);
 RETURN jsonb_build_object('status',paid.status,'needs_refund',paid.needs_refund);
END $$;

-- Retain the settings contract and add only the five admin-only online keys.
CREATE OR REPLACE FUNCTION public.update_settings(p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_old public.app_settings; v_new public.app_settings; v_key TEXT; v_max INT;
 v_request UUID; v_existing JSONB;
 v_keys TEXT[]:=ARRAY['store_name','store_address','store_phone','store_email','store_logo','tax_rate','currency','interface_mode','auto_backup','receipt_printer','theme','invoice_prefix','invoice_counter','max_cashier_discount_percent','return_window_days','cash_variance_alert','min_tailoring_deposit_percent','receipt_header','receipt_footer','ntn','strn','online_hold_minutes','delivery_fee','free_delivery_over','cod_enabled','cod_max_total'];
BEGIN
 IF NOT public.has_app_role(ARRAY['admin','manager']) THEN RAISE EXCEPTION 'Only managers can change settings' USING ERRCODE='42501'; END IF;
 v_request:=nullif(p->>'request_id','')::uuid;
 v_existing:=public.idempotency_begin(v_request,'update_settings');
 IF v_existing IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=v_request AND user_id=auth.uid()) THEN RAISE EXCEPTION 'Request id belongs to another settings save' USING ERRCODE='42501'; END IF;
   RETURN v_existing;
 END IF;
 IF jsonb_typeof(p) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Send a settings patch'; END IF;
 FOR v_key IN SELECT jsonb_object_keys(p) LOOP
   IF v_key='request_id' THEN CONTINUE; END IF;
   IF NOT (v_key=ANY(v_keys)) THEN RAISE EXCEPTION 'Unknown setting: %',v_key; END IF;
   IF public.current_app_role()='manager' AND v_key NOT IN ('receipt_header','receipt_footer') THEN RAISE EXCEPTION 'Only administrators can change %',v_key USING ERRCODE='42501'; END IF;
   IF v_key IN ('free_delivery_over','cod_max_total') AND p->v_key='null'::jsonb THEN CONTINUE; END IF;
   IF v_key IN ('tax_rate','max_cashier_discount_percent','return_window_days','cash_variance_alert','min_tailoring_deposit_percent','invoice_counter','online_hold_minutes','delivery_fee','free_delivery_over','cod_max_total') THEN
     IF jsonb_typeof(p->v_key) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Enter a number for %',v_key; END IF;
   ELSIF v_key IN ('auto_backup','receipt_printer','cod_enabled') THEN
     IF jsonb_typeof(p->v_key) IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Choose on or off for %',v_key; END IF;
   ELSE
     IF jsonb_typeof(p->v_key) NOT IN ('string','null') THEN RAISE EXCEPTION 'Enter text for %',v_key; END IF;
     v_max:=CASE v_key WHEN 'store_name' THEN 200 WHEN 'store_address' THEN 1000 WHEN 'store_phone' THEN 50
       WHEN 'store_email' THEN 254 WHEN 'store_logo' THEN 3000000 WHEN 'receipt_header' THEN 500 WHEN 'receipt_footer' THEN 500
       WHEN 'invoice_prefix' THEN 20 ELSE 100 END;
     IF length(p->>v_key)>v_max THEN RAISE EXCEPTION '% must be at most % characters',v_key,v_max; END IF;
   END IF;
 END LOOP;
 IF p ? 'tax_rate' AND (p->>'tax_rate')::numeric NOT BETWEEN 0 AND 100 THEN RAISE EXCEPTION 'Tax must be between 0 and 100 percent'; END IF;
 IF p ? 'max_cashier_discount_percent' AND (p->>'max_cashier_discount_percent')::numeric NOT BETWEEN 0 AND 100 THEN RAISE EXCEPTION 'Discount limit must be between 0 and 100 percent'; END IF;
 IF p ? 'min_tailoring_deposit_percent' AND (p->>'min_tailoring_deposit_percent')::numeric NOT BETWEEN 0 AND 100 THEN RAISE EXCEPTION 'Minimum deposit must be between 0 and 100 percent'; END IF;
 IF p ? 'return_window_days' AND ((p->>'return_window_days')::numeric NOT BETWEEN 0 AND 365 OR (p->>'return_window_days')::numeric<>trunc((p->>'return_window_days')::numeric)) THEN RAISE EXCEPTION 'Return window must be a whole number from 0 to 365 days'; END IF;
 IF p ? 'cash_variance_alert' AND (p->>'cash_variance_alert')::numeric<0 THEN RAISE EXCEPTION 'Cash difference alert must be zero or more'; END IF;
 IF p ? 'invoice_counter' AND ((p->>'invoice_counter')::numeric<0 OR (p->>'invoice_counter')::numeric<>trunc((p->>'invoice_counter')::numeric)) THEN RAISE EXCEPTION 'Invoice preview counter must be a whole number of zero or more'; END IF;
 IF p ? 'store_name' AND coalesce(trim(p->>'store_name'),'')='' THEN RAISE EXCEPTION 'Enter the store name'; END IF;
 IF p ? 'currency' AND coalesce(p->>'currency','') !~ '^[A-Z]{3}$' THEN RAISE EXCEPTION 'Enter a three-letter currency code'; END IF;
 IF p ? 'interface_mode' AND coalesce(p->>'interface_mode','') NOT IN ('touch','traditional') THEN RAISE EXCEPTION 'Choose touch or traditional layout'; END IF;
 IF p ? 'theme' AND coalesce(p->>'theme','') NOT IN ('light','dark','auto') THEN RAISE EXCEPTION 'Choose a valid theme'; END IF;
 IF p ? 'online_hold_minutes' AND ((p->>'online_hold_minutes')::numeric NOT BETWEEN 1 AND 1440 OR (p->>'online_hold_minutes')::numeric<>trunc((p->>'online_hold_minutes')::numeric)) THEN RAISE EXCEPTION 'Online hold must be a whole number from 1 to 1440 minutes'; END IF;
 FOR v_key IN SELECT unnest(ARRAY['delivery_fee','free_delivery_over','cod_max_total']) LOOP
  IF p ? v_key AND p->v_key<>'null'::jsonb AND ((p->>v_key)::numeric<0 OR (p->>v_key)::numeric<>round((p->>v_key)::numeric,2)) THEN RAISE EXCEPTION 'Enter a non-negative amount with up to two decimals for %',v_key; END IF;
 END LOOP;
 SELECT * INTO v_old FROM public.app_settings ORDER BY created_at,id LIMIT 1 FOR UPDATE;
 IF v_old.id IS NULL THEN RAISE EXCEPTION 'Store settings not found'; END IF;
 v_new:=jsonb_populate_record(v_old,p-'request_id');
 UPDATE public.app_settings SET store_name=v_new.store_name,store_address=v_new.store_address,store_phone=v_new.store_phone,
   store_email=v_new.store_email,store_logo=v_new.store_logo,tax_rate=v_new.tax_rate,currency=v_new.currency,interface_mode=v_new.interface_mode,
   auto_backup=v_new.auto_backup,receipt_printer=v_new.receipt_printer,theme=v_new.theme,invoice_prefix=v_new.invoice_prefix,invoice_counter=v_new.invoice_counter,
   max_cashier_discount_percent=v_new.max_cashier_discount_percent,return_window_days=v_new.return_window_days,cash_variance_alert=v_new.cash_variance_alert,
   min_tailoring_deposit_percent=v_new.min_tailoring_deposit_percent,receipt_header=v_new.receipt_header,receipt_footer=v_new.receipt_footer,ntn=v_new.ntn,strn=v_new.strn,online_hold_minutes=v_new.online_hold_minutes,delivery_fee=v_new.delivery_fee,free_delivery_over=v_new.free_delivery_over,cod_enabled=v_new.cod_enabled,cod_max_total=v_new.cod_max_total
 WHERE id=v_old.id RETURNING * INTO v_new;
 INSERT INTO public.settings_history(old,new) VALUES(to_jsonb(v_old),to_jsonb(v_new));
 RETURN public.idempotency_finish(v_request,to_jsonb(v_new));
END; $$;

-- Generic reservation release must not detach a web hold from its order state
-- (or leave a fabric roll reserved). Online cancellation owns that transition.
CREATE OR REPLACE FUNCTION public.release_reservation(p_reservation_id UUID)
RETURNS public.stock_reservations LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_branch UUID;v_reference TEXT;
BEGIN
 SELECT branch_id,reference_type INTO v_branch,v_reference FROM public.stock_reservations WHERE id=p_reservation_id;
 IF NOT public.is_branch_member(v_branch) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF v_reference='online_order' THEN RAISE EXCEPTION 'Use online order cancellation to release this reservation'; END IF;
 RETURN public.close_reservation(p_reservation_id,'released');
END $$;

DO $$ DECLARE f RECORD; BEGIN
 FOR f IN SELECT oid::regprocedure AS signature,proname FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname=ANY(ARRAY[
 'require_online_service','online_order_public','close_online_reservations','cancel_online_order_internal','quote_online_order','create_online_order',
 'expire_online_orders','mark_online_order_paid','my_online_orders','my_online_order','cancel_my_online_order','list_online_orders','online_order_detail',
 'advance_online_order','collect_cod_payment','cancel_online_order','record_online_refund']) LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',f.signature);
  IF f.proname='quote_online_order' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon,authenticated',f.signature);
  ELSIF f.proname IN ('expire_online_orders','mark_online_order_paid') THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',f.signature);
  ELSIF f.proname NOT IN ('require_online_service','online_order_public','close_online_reservations','cancel_online_order_internal') THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f.signature);
  END IF;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.update_settings(JSONB),public.release_reservation(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_settings(JSONB),public.release_reservation(UUID) TO authenticated;
CREATE EXTENSION IF NOT EXISTS pg_cron;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='expire-online-orders') THEN
  PERFORM cron.schedule('expire-online-orders','* * * * *','SELECT public.expire_online_orders()');
 END IF;
END $$;
