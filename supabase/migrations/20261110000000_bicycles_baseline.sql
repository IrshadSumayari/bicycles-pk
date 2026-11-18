-- Bicycles.pk database baseline.
-- One migration for the whole schema: POS, inventory, online shop, bike specs, bulky delivery and assembly.
-- Generated from the final schema; add new changes as new migration files after this one.




SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "app_private";


ALTER SCHEMA "app_private" OWNER TO "postgres";


CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "app_private"."catalog_angle_paths"("p_style" "uuid", "p_image" "text") RETURNS "text"[]
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
 SELECT CASE WHEN count(*)>1 THEN array_agg(storage_path ORDER BY sort_order,id) END FROM (
  SELECT i.storage_path,i.sort_order,i.id FROM public.product_images i
  WHERE i.style_id=p_style AND (i.variant_color IS NULL OR EXISTS(
   SELECT 1 FROM public.public_catalog c WHERE c.style_id=p_style AND c.price>0 AND lower(trim(c.color))=lower(trim(i.variant_color))))
  ORDER BY i.sort_order,i.id LIMIT 4) photos
$$;


ALTER FUNCTION "app_private"."catalog_angle_paths"("p_style" "uuid", "p_image" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app_private"."return_photo_access"("p_path" "text", "p_upload" boolean DEFAULT false) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
 SELECT coalesce(EXISTS(SELECT 1 FROM public.online_return_photos p JOIN public.online_return_requests r ON r.id=p.request_id JOIN public.online_orders o ON o.id=r.order_id
 WHERE p.storage_path=p_path AND (
 (public.is_website_customer() AND o.account_id=auth.uid() AND (NOT p_upload OR r.status IN ('submitted','needs_information')))
 OR (NOT p_upload AND public.has_app_role(ARRAY['admin','manager']) AND public.is_branch_member(o.branch_id)))),false)
$$;


ALTER FUNCTION "app_private"."return_photo_access"("p_path" "text", "p_upload" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app_private"."return_request_json"("p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
 SELECT jsonb_build_object('id',r.id,'order_no',o.order_no,'reason',r.reason,'requested_resolution',r.requested_resolution,
 'message',r.message,'status',r.status,'version',r.version,'created_at',r.created_at,'updated_at',r.updated_at,
 'items',(SELECT coalesce(jsonb_agg(jsonb_build_object('line_no',l.line_no,'description',l.description,'sku',l.sku,'size',l.size,'color',l.color,'quantity',i.quantity) ORDER BY l.line_no),'[]'::jsonb)
 FROM public.online_return_items i JOIN public.online_order_lines l ON l.id=i.order_line_id WHERE i.request_id=r.id),
 'events',(SELECT coalesce(jsonb_agg(jsonb_build_object('actor',e.actor,'status',e.status,'message',e.message,'created_at',e.created_at) ORDER BY e.created_at,e.id),'[]'::jsonb) FROM public.online_return_events e WHERE e.request_id=r.id),
 'photos',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'storage_path',p.storage_path,'uploaded',EXISTS(SELECT 1 FROM storage.objects s WHERE s.bucket_id='return-evidence' AND s.name=p.storage_path)) ORDER BY p.created_at,p.id),'[]'::jsonb) FROM public.online_return_photos p WHERE p.request_id=r.id))
 FROM public.online_return_requests r JOIN public.online_orders o ON o.id=r.order_id WHERE r.id=p_id
$$;


ALTER FUNCTION "app_private"."return_request_json"("p_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app_private"."valid_bike_specs"("p" "jsonb") RETURNS boolean
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'public'
    AS $$
 SELECT jsonb_typeof(p)='object'
  AND p - ARRAY['frame','fork','wheel_size','tyres','gears','drivetrain','brakes','suspension','weight',
   'max_load','rider_height','age_range','motor','battery','range','folded_size','warranty'] = '{}'::jsonb
  AND NOT EXISTS(SELECT 1 FROM jsonb_each(p) e
   WHERE jsonb_typeof(e.value)<>'string' OR length(e.value#>>'{}')>120 OR btrim(e.value#>>'{}')='')
$$;


ALTER FUNCTION "app_private"."valid_bike_specs"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."adjust_customer_balance"("p_customer" "uuid", "p_amount" numeric, "p_reason" "text", "p_request_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_existing JSONB; v_customer public.customers;
BEGIN
 IF NOT public.has_app_role(ARRAY['admin','manager']) THEN RAISE EXCEPTION 'Only managers can adjust balances' USING ERRCODE='42501'; END IF;
 v_existing:=public.idempotency_begin(p_request_id,'adjust_customer_balance');
 IF v_existing IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=p_request_id AND user_id=auth.uid()) OR v_existing->>'customer_id' IS DISTINCT FROM p_customer::text THEN
     RAISE EXCEPTION 'Request id belongs to another adjustment' USING ERRCODE='42501'; END IF;
   RETURN v_existing;
 END IF;
 IF p_request_id IS NULL THEN RAISE EXCEPTION 'request_id is required'; END IF;
 IF coalesce(trim(p_reason),'')='' THEN RAISE EXCEPTION 'Add a reason for this balance adjustment'; END IF;
 IF p_amount IS NULL OR p_amount=0 OR p_amount<>round(p_amount,2) OR p_amount::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'Enter a non-zero adjustment with at most two decimals'; END IF;
 SELECT * INTO v_customer FROM public.customers WHERE id=p_customer FOR UPDATE;
 IF v_customer.id IS NULL THEN RAISE EXCEPTION 'Customer not found'; END IF;
 INSERT INTO public.customer_ledger(customer_id,entry_type,amount,note) VALUES(p_customer,'adjustment',p_amount,trim(p_reason));
 RETURN public.idempotency_finish(p_request_id,jsonb_build_object('customer_id',p_customer,'balance',coalesce(v_customer.credit_used,0)+p_amount));
END; $$;


ALTER FUNCTION "public"."adjust_customer_balance"("p_customer" "uuid", "p_amount" numeric, "p_reason" "text", "p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."adjust_stock"("p_variant_id" "uuid", "p_location_id" "uuid", "p_quantity" numeric, "p_reason" "text", "p_movement_type" "text" DEFAULT 'adjust'::"text", "p_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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
    IF p_quantity <> trunc(p_quantity) THEN
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


ALTER FUNCTION "public"."adjust_stock"("p_variant_id" "uuid", "p_location_id" "uuid", "p_quantity" numeric, "p_reason" "text", "p_movement_type" "text", "p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."advance_online_order"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE k UUID;r JSONB;o public.online_orders;target TEXT;l public.online_order_lines;cost NUMERIC;header public.sales;invoice TEXT;profile public.users;location UUID;paid public.online_payments;reservation public.stock_reservations;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 k:=nullif(p->>'request_id','')::uuid;r:=public.request_begin(k,'advance_online_order');IF r IS NOT NULL THEN RETURN r;END IF;
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
   PERFORM public.post_stock_movement(l.location_id,l.variant_id,-l.quantity,'sale','web','sale',header.id,cost,NULL);
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


ALTER FUNCTION "public"."advance_online_order"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_customer_ledger"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_flag TEXT:=current_setting('app.customer_ledger',true);
BEGIN
 PERFORM set_config('app.customer_ledger','on',true);
 UPDATE public.customers SET credit_used=coalesce(credit_used,0)+NEW.amount WHERE id=NEW.customer_id;
 -- Do not leave an authorization flag enabled for the rest of the transaction.
 PERFORM set_config('app.customer_ledger',coalesce(v_flag,''),true);
 RETURN NEW;
END; $$;


ALTER FUNCTION "public"."apply_customer_ledger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."approve_stock_count"("p_count_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_count public.stock_counts;
    v_line public.stock_count_lines;
    v_diff NUMERIC;
    v_changed INTEGER := 0;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can approve a stock count' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_count FROM public.stock_counts WHERE id = p_count_id FOR UPDATE;
    IF v_count.id IS NULL OR NOT public.is_branch_member(v_count.branch_id) THEN
        RAISE EXCEPTION 'Count not found';
    END IF;
    IF v_count.status = 'approved' THEN
        -- Approving twice (e.g. a retry) is a no-op
        RETURN jsonb_build_object('count', to_jsonb(v_count), 'changed_lines', 0, 'already_approved', true);
    END IF;
    IF v_count.status <> 'open' THEN
        RAISE EXCEPTION 'Count % is %', v_count.count_no, v_count.status;
    END IF;

    FOR v_line IN
        SELECT * FROM public.stock_count_lines WHERE count_id = p_count_id ORDER BY variant_id
    LOOP
        v_diff := v_line.counted - v_line.expected;
        IF v_diff <> 0 THEN
            PERFORM public.post_stock_movement(
                v_count.location_id, v_line.variant_id, v_diff, 'count', 'pos', 'stock_count', v_count.id,
                NULL, 'Stock count ' || v_count.count_no);
            v_changed := v_changed + 1;
        END IF;
        UPDATE public.stock_count_lines SET difference = v_diff WHERE id = v_line.id;
    END LOOP;

    UPDATE public.stock_counts SET status = 'approved', closed_by = auth.uid(), closed_at = now()
    WHERE id = p_count_id RETURNING * INTO v_count;

    RETURN jsonb_build_object('count', to_jsonb(v_count), 'changed_lines', v_changed);
END;
$$;


ALTER FUNCTION "public"."approve_stock_count"("p_count_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_generate_invoice_number"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.invoice_number IS NULL OR NEW.invoice_number = '' THEN
        NEW.invoice_number := generate_invoice_number();
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."auto_generate_invoice_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."backfill_customer_ledger"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE c public.customers; v_flag TEXT:=current_setting('app.customer_ledger',true);
BEGIN
 FOR c IN SELECT * FROM public.customers ORDER BY id FOR UPDATE LOOP
   -- Already ledger-backed customers need no opening entry, including accounts
   -- first created after this migration. This also makes reapplication safe.
   IF coalesce(c.credit_used,0)<>0 AND NOT EXISTS (SELECT 1 FROM public.customer_ledger l WHERE l.customer_id=c.id) THEN
     PERFORM set_config('app.customer_ledger','on',true);
     UPDATE public.customers SET credit_used=0 WHERE id=c.id;
     INSERT INTO public.customer_ledger(customer_id,entry_type,amount,note) VALUES(c.id,'opening',c.credit_used,'Balance brought forward');
     PERFORM set_config('app.customer_ledger',coalesce(v_flag,''),true);
   END IF;
 END LOOP;
END; $$;


ALTER FUNCTION "public"."backfill_customer_ledger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_my_online_order"("p_order_no" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE a UUID;o public.online_orders;
BEGIN
 a:=public.require_website_customer();SELECT * INTO o FROM public.online_orders WHERE order_no=p_order_no AND account_id=a FOR UPDATE;
 IF o.id IS NULL THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF;
 IF o.status='cancelled' THEN RETURN jsonb_build_object('status','cancelled'); END IF;
 IF o.status NOT IN ('pending_payment','placed') THEN RAISE EXCEPTION 'Please contact the shop to cancel this order'; END IF;
 RETURN public.cancel_online_order_internal(o.id,'Cancelled by customer');
END $$;


ALTER FUNCTION "public"."cancel_my_online_order"("p_order_no" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_online_order"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE k UUID;r JSONB;o public.online_orders;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 k:=nullif(p->>'request_id','')::uuid;r:=public.request_begin(k,'cancel_online_order');IF r IS NOT NULL THEN RETURN r;END IF;
 SELECT * INTO o FROM public.online_orders WHERE id=nullif(p->>'id','')::uuid FOR UPDATE;
 IF o.id IS NULL OR NOT public.is_branch_member(o.branch_id) THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF;
 IF coalesce(length(trim(p->>'reason')),0) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'Enter a cancellation reason of at most 2000 characters'; END IF;
 RETURN public.idempotency_finish(k,public.cancel_online_order_internal(o.id,trim(p->>'reason')));
END $$;


ALTER FUNCTION "public"."cancel_online_order"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_online_order_internal"("p_id" "uuid", "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."cancel_online_order_internal"("p_id" "uuid", "p_reason" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."stock_counts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "count_no" "text" NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "location_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "notes" "text",
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "closed_by" "uuid",
    "closed_at" timestamp with time zone,
    CONSTRAINT "stock_counts_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'approved'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."stock_counts" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_stock_count"("p_count_id" "uuid") RETURNS "public"."stock_counts"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_count public.stock_counts;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can cancel a stock count' USING ERRCODE = '42501';
    END IF;
    UPDATE public.stock_counts SET status = 'cancelled', closed_by = auth.uid(), closed_at = now()
    WHERE id = p_count_id AND status = 'open' AND public.is_branch_member(branch_id)
    RETURNING * INTO v_count;
    IF v_count.id IS NULL THEN
        RAISE EXCEPTION 'Open count not found';
    END IF;
    RETURN v_count;
END;
$$;


ALTER FUNCTION "public"."cancel_stock_count"("p_count_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cash_session_detail"("p_session_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
            'document_no', coalesce(r.return_no, s.invoice_number)
        ) ORDER BY m.created_at, m.id)
        FROM public.cash_movements m LEFT JOIN public.users u ON u.id = m.created_by
        LEFT JOIN public.payments pay ON pay.id = m.payment_id
        LEFT JOIN public.sales s ON s.id = pay.sale_id
        LEFT JOIN public.returns r ON r.id = pay.return_id
        WHERE m.session_id = v_session.id), '[]'::jsonb));
END;
$$;


ALTER FUNCTION "public"."cash_session_detail"("p_session_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cash_session_summary"("p_session_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;
RETURN (SELECT jsonb_build_object(
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
      AND (s.user_id = auth.uid() OR (public.has_app_role(ARRAY['admin', 'manager']) AND public.is_branch_member(s.branch_id))));
END;$$;


ALTER FUNCTION "public"."cash_session_summary"("p_session_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."catalog_collections"() RETURNS TABLE("slug" "text", "name" "text", "description" "text", "hero_image_path" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
 SELECT c.slug,c.name,c.description,c.hero_image_path FROM public.collections c WHERE c.published
  AND (c.starts_at IS NULL OR c.starts_at<=now()) AND (c.ends_at IS NULL OR c.ends_at>now()) ORDER BY c.sort_order,c.slug;
$$;


ALTER FUNCTION "public"."catalog_collections"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."catalog_facets"("p_collection" "text") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
 SELECT jsonb_build_object(
  'sizes',coalesce(array_agg(DISTINCT c.size ORDER BY c.size) FILTER (WHERE c.size IS NOT NULL),'{}'::text[]),
  'colors',coalesce(array_agg(DISTINCT c.color ORDER BY c.color) FILTER (WHERE c.color IS NOT NULL),'{}'::text[]),
  'brands',coalesce(array_agg(DISTINCT s.brand ORDER BY s.brand) FILTER (WHERE nullif(s.brand,'') IS NOT NULL),'{}'::text[]),
  'wheel_sizes',coalesce(array_agg(DISTINCT s.specs->>'wheel_size' ORDER BY s.specs->>'wheel_size') FILTER (WHERE s.specs ? 'wheel_size'),'{}'::text[]),
  'brakes',coalesce(array_agg(DISTINCT s.specs->>'brakes' ORDER BY s.specs->>'brakes') FILTER (WHERE s.specs ? 'brakes'),'{}'::text[]),
  'gears',coalesce(array_agg(DISTINCT s.specs->>'gears' ORDER BY s.specs->>'gears') FILTER (WHERE s.specs ? 'gears'),'{}'::text[]),
  'suspension',coalesce(array_agg(DISTINCT s.specs->>'suspension' ORDER BY s.specs->>'suspension') FILTER (WHERE s.specs ? 'suspension'),'{}'::text[]),
  'price_min',min(c.price),'price_max',max(c.price))
 FROM public.public_catalog c JOIN public.product_styles s ON s.id=c.style_id
 WHERE c.slug IS NOT NULL AND c.price>0 AND (nullif(p_collection,'') IS NULL OR EXISTS(
  SELECT 1 FROM public.collection_styles cs JOIN public.collections co ON co.id=cs.collection_id
  WHERE cs.style_id=c.style_id AND co.slug=p_collection AND co.published
   AND (co.starts_at IS NULL OR co.starts_at<=now()) AND (co.ends_at IS NULL OR co.ends_at>now())));
$$;


ALTER FUNCTION "public"."catalog_facets"("p_collection" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."catalog_list"("p" "jsonb") RETURNS TABLE("style_id" "uuid", "slug" "text", "title" "text", "min_price" numeric, "max_price" numeric, "compare_at_price" numeric, "image_path" "text", "angle_paths" "text"[], "colors" "text"[], "sizes" "text"[], "stock_level" "text", "total_count" bigint)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_q TEXT:=replace(replace(replace(trim(coalesce(p->>'q','')),E'\\',E'\\\\'),'%',E'\\%'),'_',E'\\_');
 v_sort TEXT:=coalesce(p->>'sort','new'); v_limit INT:=least(48,greatest(1,coalesce((p->>'limit')::int,24)));
 v_offset INT:=greatest(0,coalesce((p->>'offset')::int,0));
 v_in_stock BOOLEAN:=coalesce(p->>'in_stock','')='true';
BEGIN
 IF v_sort NOT IN ('new','price_asc','price_desc') THEN RAISE EXCEPTION 'Choose new, price_asc or price_desc'; END IF;
 RETURN QUERY
 SELECT s.style_id,s.slug,s.title,s.min_price,s.max_price,s.compare_at_price,s.image_path,app_private.catalog_angle_paths(s.style_id,s.image_path),s.colors,s.sizes,s.stock_level,count(*) OVER ()
 FROM public.catalog_style_rows() s JOIN public.product_styles ps ON ps.id=s.style_id
 WHERE (v_q='' OR s.title ILIKE '%'||v_q||'%' OR ps.brand ILIKE '%'||v_q||'%')
 AND (nullif(p->>'collection','') IS NULL OR EXISTS(
  SELECT 1 FROM public.collection_styles cs JOIN public.collections co ON co.id=cs.collection_id
  WHERE cs.style_id=s.style_id AND co.slug=p->>'collection' AND co.published
   AND (co.starts_at IS NULL OR co.starts_at<=now()) AND (co.ends_at IS NULL OR co.ends_at>now())))
 AND (nullif(p->>'brand','') IS NULL OR ps.brand=p->>'brand')
 AND (nullif(p->>'wheel_size','') IS NULL OR ps.specs->>'wheel_size'=p->>'wheel_size')
 AND (nullif(p->>'brakes','') IS NULL OR ps.specs->>'brakes'=p->>'brakes')
 AND (nullif(p->>'gears','') IS NULL OR ps.specs->>'gears'=p->>'gears')
 AND (nullif(p->>'suspension','') IS NULL OR ps.specs->>'suspension'=p->>'suspension')
 AND EXISTS(SELECT 1 FROM public.public_catalog c WHERE c.style_id=s.style_id AND c.price>0
  AND (nullif(p->>'category','') IS NULL OR c.category=p->>'category')
  AND (jsonb_typeof(p->'categories') IS DISTINCT FROM 'array'
    OR c.category IN (SELECT jsonb_array_elements_text(p->'categories')))
  AND (nullif(p->>'size','') IS NULL OR c.size=p->>'size')
  AND (nullif(p->>'color','') IS NULL OR c.color=p->>'color')
  AND (NOT v_in_stock OR c.stock_level<>'out_of_stock')
  AND (nullif(p->>'price_min','') IS NULL OR c.price>=(p->>'price_min')::numeric)
  AND (nullif(p->>'price_max','') IS NULL OR c.price<=(p->>'price_max')::numeric))
 ORDER BY CASE WHEN v_sort='new' THEN s.created_at END DESC,
  CASE WHEN v_sort='price_asc' THEN s.min_price END ASC,
  CASE WHEN v_sort='price_desc' THEN s.min_price END DESC,s.style_id
 LIMIT v_limit OFFSET v_offset;
END $$;


ALTER FUNCTION "public"."catalog_list"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."catalog_policy"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
 SELECT jsonb_build_object('return_window_days',return_window_days,'cod_enabled',cod_enabled) FROM public.app_settings ORDER BY created_at,id LIMIT 1
$$;


ALTER FUNCTION "public"."catalog_policy"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."catalog_product"("p_slug" "text") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
 SELECT jsonb_build_object('style_id',s.style_id,'slug',s.slug,'title',s.title,
  'description',st.web_description,'specs',st.specs,'bulky',st.bulky,'purchase_policy',public.catalog_policy(),
  'kind',st.kind,'brand',st.brand,'material',st.material,'season',st.season,
  'category',(SELECT name FROM public.categories WHERE id=st.category_id),'unit',st.unit,
  'min_price',s.min_price,'max_price',s.max_price,'stock_level',s.stock_level,
  'images',coalesce((SELECT jsonb_agg(jsonb_build_object('storage_path',i.storage_path,'alt',i.alt,'variant_color',i.variant_color) ORDER BY i.sort_order,i.id)
   FROM public.product_images i WHERE i.style_id=s.style_id AND (i.variant_color IS NULL OR EXISTS(
    SELECT 1 FROM public.public_catalog c WHERE c.style_id=s.style_id AND c.color=i.variant_color AND c.price>0))),'[]'::jsonb),
  'variants',(SELECT jsonb_agg(jsonb_build_object('variant_id',c.variant_id,'size',c.size,'color',c.color,'fit',c.fit,
   'price',c.price,'compare_at_price',c.compare_at_price,'stock_level',c.stock_level) ORDER BY c.size,c.color,c.fit,c.variant_id)
   FROM public.public_catalog c WHERE c.style_id=s.style_id AND c.price>0),
  'related',coalesce((SELECT jsonb_agg(jsonb_build_object('style_id',r.style_id,'slug',r.slug,'title',r.title,'min_price',r.min_price,'image_path',r.image_path))
   FROM (SELECT other.* FROM public.catalog_style_rows() other WHERE other.style_id<>s.style_id AND EXISTS(
    SELECT 1 FROM public.collection_styles mine JOIN public.collection_styles theirs ON theirs.collection_id=mine.collection_id
    JOIN public.collections co ON co.id=mine.collection_id WHERE mine.style_id=s.style_id AND theirs.style_id=other.style_id
     AND co.published AND (co.starts_at IS NULL OR co.starts_at<=now()) AND (co.ends_at IS NULL OR co.ends_at>now()))
    ORDER BY other.created_at DESC,other.style_id LIMIT 8) r),'[]'::jsonb))
 FROM public.catalog_style_rows() s JOIN public.product_styles st ON st.id=s.style_id WHERE s.slug=p_slug;
$$;


ALTER FUNCTION "public"."catalog_product"("p_slug" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."catalog_style_rows"() RETURNS TABLE("style_id" "uuid", "slug" "text", "title" "text", "min_price" numeric, "max_price" numeric, "compare_at_price" numeric, "image_path" "text", "colors" "text"[], "sizes" "text"[], "stock_level" "text", "created_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
 SELECT c.style_id,c.slug,coalesce(nullif(trim(s.web_title),''),s.name),min(c.price),max(c.price),max(c.compare_at_price),
  (SELECT i.storage_path FROM public.product_images i WHERE i.style_id=c.style_id AND (i.variant_color IS NULL OR EXISTS(
   SELECT 1 FROM public.public_catalog visible WHERE visible.style_id=c.style_id AND visible.color=i.variant_color AND visible.price>0)) ORDER BY i.sort_order,i.id LIMIT 1),
  coalesce(array_agg(DISTINCT c.color ORDER BY c.color) FILTER (WHERE c.color IS NOT NULL),'{}'::text[]),
  coalesce(array_agg(DISTINCT c.size ORDER BY c.size) FILTER (WHERE c.size IS NOT NULL),'{}'::text[]),
  CASE WHEN bool_or(c.stock_level='in_stock') THEN 'in_stock' WHEN bool_or(c.stock_level='low_stock') THEN 'low_stock' ELSE 'out_of_stock' END,s.created_at
 FROM public.public_catalog c JOIN public.product_styles s ON s.id=c.style_id
 WHERE c.slug IS NOT NULL AND c.price>0
 GROUP BY c.style_id,c.slug,s.web_title,s.name,s.created_at;
$$;


ALTER FUNCTION "public"."catalog_style_rows"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."close_cash_session"("p_counted_cash" numeric, "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_session UUID;
BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;

    -- Preserve the original validation order, signature, errors and rounding.
    IF p_counted_cash IS NULL OR p_counted_cash < 0 THEN
        RAISE EXCEPTION 'Enter the counted cash (0 or more)';
    END IF;
    SELECT id INTO v_session FROM public.cash_sessions WHERE user_id = auth.uid() AND status = 'open' FOR UPDATE;
    IF v_session IS NULL THEN RAISE EXCEPTION 'No open cash shift'; END IF;
    RETURN public.close_cash_session_internal(v_session, p_counted_cash, p_notes, auth.uid());
END;
$$;


ALTER FUNCTION "public"."close_cash_session"("p_counted_cash" numeric, "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."close_cash_session_internal"("p_session_id" "uuid", "p_counted" numeric, "p_notes" "text", "p_closed_by" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."close_cash_session_internal"("p_session_id" "uuid", "p_counted" numeric, "p_notes" "text", "p_closed_by" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."close_online_reservations"("p_order" "uuid", "p_status" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE r public.stock_reservations;
BEGIN
 FOR r IN SELECT sr.* FROM public.stock_reservations sr JOIN public.online_order_lines l ON l.reservation_id=sr.id WHERE l.order_id=p_order ORDER BY sr.variant_id,sr.location_id,sr.id FOR UPDATE OF sr LOOP
  IF r.status<>'active' THEN
   IF p_status='consumed' THEN RAISE EXCEPTION 'The reserved stock is no longer available. Please check this order.'; END IF;
   CONTINUE;
  END IF;
  PERFORM public.close_reservation(r.id,p_status);
 END LOOP;
END $$;


ALTER FUNCTION "public"."close_online_reservations"("p_order" "uuid", "p_status" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."stock_reservations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "location_id" "uuid" NOT NULL,
    "variant_id" "uuid" NOT NULL,
    "quantity" numeric(18,6) NOT NULL,
    "channel" "text" NOT NULL,
    "reference_type" "text",
    "reference_id" "uuid",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "expires_at" timestamp with time zone,
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "closed_at" timestamp with time zone,
    CONSTRAINT "stock_reservations_channel_check" CHECK (("channel" = ANY (ARRAY['pos'::"text", 'web'::"text"]))),
    CONSTRAINT "stock_reservations_quantity_check" CHECK (("quantity" > (0)::numeric)),
    CONSTRAINT "stock_reservations_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'consumed'::"text", 'released'::"text", 'expired'::"text"])))
);


ALTER TABLE "public"."stock_reservations" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."close_reservation"("p_reservation_id" "uuid", "p_status" "text") RETURNS "public"."stock_reservations"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."close_reservation"("p_reservation_id" "uuid", "p_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."collect_cod_payment"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE k UUID;r JSONB;o public.online_orders;pay JSONB;amount NUMERIC;paid NUMERIC:=0;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 k:=nullif(p->>'request_id','')::uuid;r:=public.request_begin(k,'collect_cod_payment');IF r IS NOT NULL THEN RETURN r;END IF;
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


ALTER FUNCTION "public"."collect_cod_payment"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."commission_branches"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY created_at,code)
 FROM public.branches WHERE active AND public.is_branch_member(id)),'[]'::jsonb);
END; $$;


ALTER FUNCTION "public"."commission_branches"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."commission_overview"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_branch UUID:=(p->>'branch_id')::uuid; v_from DATE:=(p->>'from')::date; v_to DATE:=(p->>'to')::date;
 v_user UUID:=nullif(p->>'user_id','')::uuid; v_manager BOOLEAN; v_start TIMESTAMPTZ; v_end TIMESTAMPTZ; v_people JSONB; v_summary JSONB; v_rows JSONB; v_count BIGINT;
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) OR NOT coalesce(public.is_branch_member(v_branch),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 v_manager:=coalesce(public.has_app_role(ARRAY['admin','manager']),false);
 IF NOT v_manager THEN v_user:=auth.uid(); END IF;
 IF v_from IS NULL OR v_to IS NULL OR v_from>v_to OR v_to-v_from>366 THEN RAISE EXCEPTION 'Choose a date range up to one year'; END IF;
 v_start:=v_from::timestamp AT TIME ZONE 'Asia/Karachi'; v_end:=(v_to+1)::timestamp AT TIME ZONE 'Asia/Karachi';
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'active',u.active,'enabled',coalesce(r.enabled,false),'kind',coalesce(r.kind,'percentage'),'rate',coalesce(r.rate,0)) ORDER BY u.name,u.id),'[]'::jsonb)
 INTO v_people FROM public.users u LEFT JOIN public.commission_rules r ON r.user_id=u.id AND r.branch_id=v_branch
 WHERE (v_manager OR u.id=auth.uid()) AND ((u.role IN ('admin','manager','cashier') AND (u.role='admin' OR EXISTS(SELECT 1 FROM public.branch_memberships m WHERE m.user_id=u.id AND m.branch_id=v_branch)))
 OR EXISTS(SELECT 1 FROM public.commission_entries e WHERE e.user_id=u.id AND e.branch_id=v_branch));
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.name,x.user_id),'[]'::jsonb) INTO v_summary FROM (
 SELECT e.user_id,u.name,coalesce(sum(e.amount),0) balance,
 coalesce(sum(e.amount) FILTER(WHERE e.kind='earned' AND e.created_at>=v_start AND e.created_at<v_end),0) earned,
 -coalesce(sum(e.amount) FILTER(WHERE e.kind='return' AND e.created_at>=v_start AND e.created_at<v_end),0) reversed,
 -coalesce(sum(e.amount) FILTER(WHERE e.kind='payout' AND e.created_at>=v_start AND e.created_at<v_end),0) paid,
 count(*) FILTER(WHERE e.kind='earned' AND e.created_at>=v_start AND e.created_at<v_end) invoices
 FROM public.commission_entries e JOIN public.users u ON u.id=e.user_id WHERE e.branch_id=v_branch AND (v_user IS NULL OR e.user_id=v_user) GROUP BY e.user_id,u.name
 ) x;
 SELECT count(*) INTO v_count FROM public.commission_entries e WHERE e.branch_id=v_branch AND (v_user IS NULL OR e.user_id=v_user) AND e.created_at>=v_start AND e.created_at<v_end;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC),'[]'::jsonb) INTO v_rows FROM (
 SELECT e.id,e.user_id,u.name,e.kind,e.amount,e.note,e.created_at,s.invoice_number,sc.kind rule_kind,sc.rate rule_rate,sc.basis
 FROM public.commission_entries e JOIN public.users u ON u.id=e.user_id LEFT JOIN public.sales s ON s.id=e.sale_id LEFT JOIN public.sale_commissions sc ON sc.sale_id=e.sale_id
 WHERE e.branch_id=v_branch AND (v_user IS NULL OR e.user_id=v_user) AND e.created_at>=v_start AND e.created_at<v_end
 ORDER BY e.created_at DESC,e.id DESC LIMIT 50 OFFSET greatest(0,coalesce((p->>'offset')::int,0))
 ) x;
 RETURN jsonb_build_object('people',v_people,'summary',v_summary,'entries',v_rows,'total_count',v_count,'can_manage',v_manager);
END; $$;


ALTER FUNCTION "public"."commission_overview"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."commission_sellers"("p_branch" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) OR NOT coalesce(public.is_branch_member(p_branch),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',u.id,'name',u.name) ORDER BY u.name,u.id)
 FROM public.users u JOIN public.commission_rules r ON r.user_id=u.id AND r.branch_id=p_branch
 WHERE u.active AND u.role IN ('admin','manager','cashier') AND r.enabled
 AND (u.role='admin' OR EXISTS(SELECT 1 FROM public.branch_memberships m WHERE m.user_id=u.id AND m.branch_id=p_branch))),'[]'::jsonb);
END; $$;


ALTER FUNCTION "public"."commission_sellers"("p_branch" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_online_order"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE a UUID;k UUID;cached JSONB;q JSONB;o public.online_orders;account public.customer_accounts;s public.app_settings;item JSONB;loc RECORD;chosen UUID;res public.stock_reservations;qty NUMERIC;customer UUID;ph TEXT;note TEXT;line INT:=0;hold TIMESTAMPTZ;method TEXT;
BEGIN
 a:=public.require_website_customer();k:=nullif(p->>'request_id','')::uuid;
 cached:=public.request_begin(k,'create_online_order');IF cached IS NOT NULL THEN RETURN cached;END IF;
 SELECT * INTO account FROM public.customer_accounts WHERE id=a FOR UPDATE;
 q:=public.quote_online_order(p);method:=p->>'payment_method';
 IF method IS NULL OR method NOT IN ('card','easypaisa','cod') THEN RAISE EXCEPTION 'Choose card, Easypaisa or cash on delivery'; END IF;
 IF method IN ('card','easypaisa') AND NOT (q->'payment_methods' ? method) THEN RAISE EXCEPTION 'Card and wallet payments are not available yet'; END IF;
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
  delivery_fee,subtotal,discount,tax,total,notes_customer,notes_staff,expires_at,assembly)
 VALUES(k,a,customer,public.default_branch_id(),method,p->>'fulfilment',CASE WHEN method='cod' THEN 'placed' ELSE 'pending_payment' END,CASE WHEN method='cod' THEN 'cod' ELSE 'unpaid' END,
 trim(p->>'contact_name'),ph,nullif(trim(p->>'email'),''),CASE WHEN p->>'fulfilment'='delivery' THEN jsonb_build_object('line1',trim(p->'address'->>'line1'),'line2',p->'address'->>'line2','city',trim(p->'address'->>'city'),'postal_code',p->'address'->>'postal_code') END,
 (q->>'delivery_fee')::numeric,(q->>'subtotal')::numeric,0,(q->>'tax')::numeric,(q->>'total')::numeric,nullif(trim(p->>'notes_customer'),''),note,hold,(q->>'assembly')::boolean) RETURNING * INTO o;
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
  ORDER BY b.on_hand-b.reserved DESC,b.location_id LIMIT 1;
  IF chosen IS NULL THEN RAISE EXCEPTION '% is sold out',item->>'description'; END IF;
  UPDATE public.stock_balances SET reserved=reserved+qty,updated_at=now() WHERE location_id=chosen AND variant_id=(item->>'variant_id')::uuid;
  INSERT INTO public.stock_reservations(branch_id,location_id,variant_id,quantity,channel,reference_type,reference_id,expires_at)
  VALUES(o.branch_id,chosen,(item->>'variant_id')::uuid,qty,'web','online_order',o.id,hold) RETURNING * INTO res;
  line:=line+1;
  INSERT INTO public.online_order_lines(order_id,line_no,variant_id,description,sku,size,color,unit,quantity,unit_price,taxable,tax,total,location_id,reservation_id)
  VALUES(o.id,line,(item->>'variant_id')::uuid,item->>'description',item->>'sku',item->>'size',item->>'color',item->>'unit',qty,(item->>'unit_price')::numeric,(item->>'taxable')::boolean,(item->>'tax')::numeric,(item->>'total')::numeric,chosen,res.id);
 END LOOP;
 INSERT INTO public.online_order_events(order_id,event,public_message) VALUES(o.id,o.status,'Your order has been received.');
 RETURN public.idempotency_finish(k,jsonb_build_object('id',o.id,'order_no',o.order_no,'status',o.status,'subtotal',o.subtotal,'discount',o.discount,'tax',o.tax,'delivery_fee',o.delivery_fee,'total',o.total,'expires_at',o.expires_at,'assembly',o.assembly));
END $_$;


ALTER FUNCTION "public"."create_online_order"("p" "jsonb") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."returns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "return_no" "text" NOT NULL,
    "request_id" "uuid",
    "sale_id" "uuid" NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "location_id" "uuid" NOT NULL,
    "customer_id" "uuid",
    "reason" "text" NOT NULL,
    "refund_total" numeric(14,2) NOT NULL,
    "refund_method" "text" NOT NULL,
    "exchange_sale_id" "uuid",
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "returns_refund_method_check" CHECK (("refund_method" = ANY (ARRAY['cash'::"text", 'card'::"text", 'digital'::"text", 'credit'::"text", 'exchange'::"text", 'cod_reversal'::"text"]))),
    CONSTRAINT "returns_refund_total_check" CHECK (("refund_total" >= (0)::numeric))
);


ALTER TABLE "public"."returns" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_return"("p" "jsonb", "p_refund_method" "text") RETURNS "public"."returns"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_role TEXT := public.current_app_role();
    v_sale public.sales;
    v_settings public.app_settings;
    v_needs_manager BOOLEAN := false;
    v_req JSONB;
    v_line public.sale_lines;
    v_returned NUMERIC;
    v_qty NUMERIC;
    v_refund NUMERIC;
    v_tax NUMERIC;
    v_total NUMERIC := 0;
    v_restock BOOLEAN;
    v_condition TEXT;
    v_return public.returns;
    v_track BOOLEAN;
    v_customer public.customers;
BEGIN
    IF v_role IS NULL OR v_role NOT IN ('admin', 'manager', 'cashier') THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
    IF COALESCE(trim(p->>'reason'), '') = '' THEN
        RAISE EXCEPTION 'A reason is required for a return';
    END IF;
    IF jsonb_typeof(p->'lines') <> 'array' OR jsonb_array_length(p->'lines') = 0 THEN
        RAISE EXCEPTION 'Choose at least one item to return';
    END IF;

    -- Locking the sale serialises returns of the same sale
    SELECT * INTO v_sale FROM public.sales WHERE id = NULLIF(p->>'sale_id', '')::uuid FOR UPDATE;
    IF v_sale.id IS NULL OR NOT public.is_branch_member(v_sale.branch_id) THEN
        RAISE EXCEPTION 'Sale not found';
    END IF;
    IF v_sale.status NOT IN ('completed', 'credit', 'refunded') THEN
        RAISE EXCEPTION 'Only completed sales can be returned';
    END IF;

    SELECT * INTO v_settings FROM public.app_settings ORDER BY created_at LIMIT 1;
    IF v_sale.created_at < now() - make_interval(days => COALESCE(v_settings.return_window_days, 7)) THEN
        v_needs_manager := true;
    END IF;

    INSERT INTO public.returns (return_no, request_id, sale_id, branch_id, location_id, customer_id, reason,
                                refund_total, refund_method)
    VALUES ('RTN-' || lpad(nextval('public.return_no_seq')::text, 6, '0'), NULLIF(p->>'request_id', '')::uuid,
            v_sale.id, v_sale.branch_id, COALESCE(v_sale.location_id, (
                SELECT id FROM public.locations WHERE branch_id = v_sale.branch_id AND kind = 'shop_floor' ORDER BY created_at LIMIT 1)),
            v_sale.customer_id, trim(p->>'reason'), 0, p_refund_method)
    RETURNING * INTO v_return;

    FOR v_req IN
        SELECT l FROM jsonb_array_elements(p->'lines') l ORDER BY l->>'sale_line_id'
    LOOP
        SELECT * INTO v_line FROM public.sale_lines
        WHERE id = NULLIF(v_req->>'sale_line_id', '')::uuid AND sale_id = v_sale.id;
        IF v_line.id IS NULL THEN
            RAISE EXCEPTION 'That item is not on this sale';
        END IF;

        v_qty := COALESCE(NULLIF(v_req->>'quantity', '')::numeric, 0);
        IF v_qty <= 0 THEN
            RAISE EXCEPTION 'Return quantity for "%" must be greater than zero', v_line.description;
        END IF;
        IF v_qty <> trunc(v_qty) THEN
            RAISE EXCEPTION 'Whole quantities only for "%"', v_line.description;
        END IF;
        IF v_line.unit = 'job' THEN
            v_needs_manager := true;
        END IF;

        SELECT COALESCE(sum(quantity), 0) INTO v_returned FROM public.return_lines WHERE sale_line_id = v_line.id;
        IF v_returned + v_qty > v_line.quantity THEN
            RAISE EXCEPTION 'Only % of "%" can still be returned', trim_scale(v_line.quantity - v_returned), v_line.description;
        END IF;

        -- Exact share of what was paid: earlier returns + this one never exceed the line total
        v_refund := round(v_line.total * (v_returned + v_qty) / v_line.quantity, 2)
                  - round(v_line.total * v_returned / v_line.quantity, 2);
        v_tax := round(v_line.tax * (v_returned + v_qty) / v_line.quantity, 2)
               - round(v_line.tax * v_returned / v_line.quantity, 2);

        v_condition := COALESCE(NULLIF(v_req->>'condition', ''), 'resaleable');
        IF v_condition NOT IN ('resaleable', 'damaged', 'faulty') THEN
            RAISE EXCEPTION 'Invalid condition: %', v_condition;
        END IF;
        v_restock := COALESCE((v_req->>'restock')::boolean, v_condition = 'resaleable');

        SELECT s.track_inventory INTO v_track
        FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id WHERE v.id = v_line.variant_id;
        v_restock := v_restock AND COALESCE(v_track, false);

        INSERT INTO public.return_lines (return_id, sale_line_id, variant_id, description, quantity, refund_amount,
                                         tax_amount, restocked, condition)
        VALUES (v_return.id, v_line.id, v_line.variant_id, v_line.description, v_qty, v_refund, v_tax, v_restock, v_condition);

        IF v_restock THEN
            PERFORM public.post_stock_movement(v_return.location_id, v_line.variant_id, v_qty, 'return', 'pos',
                                               'return', v_return.id, v_line.unit_cost, v_return.return_no);
        END IF;

        v_total := v_total + v_refund;
    END LOOP;

    IF v_needs_manager AND v_role NOT IN ('admin', 'manager') THEN
        RAISE EXCEPTION 'This return needs a manager (services, or outside the % day return window)',
            COALESCE(v_settings.return_window_days, 7) USING ERRCODE = '42501';
    END IF;

    -- Refund
    IF v_total > 0 THEN
        IF p_refund_method = 'credit' THEN
            SELECT * INTO v_customer FROM public.customers WHERE id = v_sale.customer_id FOR UPDATE;
            IF v_customer.id IS NULL THEN
                RAISE EXCEPTION 'Store credit refunds need the sale to have a customer';
            END IF;
            IF COALESCE(v_customer.credit_used, 0) < v_total THEN
                RAISE EXCEPTION 'Store credit refunds can only reduce what the customer owes (owes %)',
                    COALESCE(v_customer.credit_used, 0);
            END IF;
            INSERT INTO public.customer_ledger(customer_id,entry_type,amount,return_id)
            VALUES(v_customer.id,'return_credit',-v_total,v_return.id);
        END IF;

        INSERT INTO public.payments (sale_id, return_id, method, amount, direction, reference)
        VALUES (v_sale.id, v_return.id, p_refund_method, v_total, 'out', v_return.return_no);
    END IF;

    IF v_sale.customer_id IS NOT NULL THEN
        UPDATE public.customers SET total_purchases = GREATEST(COALESCE(total_purchases, 0) - v_total, 0)
        WHERE id = v_sale.customer_id;
    END IF;

    -- Fully returned sales are marked refunded
    IF NOT EXISTS (
        SELECT 1 FROM public.sale_lines sl
        WHERE sl.sale_id = v_sale.id
          AND sl.quantity > COALESCE((SELECT sum(quantity) FROM public.return_lines rl WHERE rl.sale_line_id = sl.id), 0)
    ) THEN
        UPDATE public.sales SET status = 'refunded' WHERE id = v_sale.id;
    END IF;

    UPDATE public.returns SET refund_total = v_total WHERE id = v_return.id RETURNING * INTO v_return;
    RETURN v_return;
END;
$$;


ALTER FUNCTION "public"."create_return"("p" "jsonb", "p_refund_method" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_return_request"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE a UUID; o public.online_orders; r public.online_return_requests; k UUID; item JSONB; line public.online_order_lines; qty INT; seen INT[]:='{}';
BEGIN
 a:=public.require_website_customer();
 SELECT * INTO o FROM public.online_orders WHERE order_no=p->>'order_no' AND account_id=a FOR UPDATE;
 IF o.id IS NULL THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF;
 k:=nullif(p->>'request_id','')::uuid;
 IF k IS NULL THEN RAISE EXCEPTION 'A request id is required'; END IF;
 SELECT * INTO r FROM public.online_return_requests WHERE order_id=o.id;
 IF r.id IS NOT NULL THEN
  IF r.id=k THEN RETURN app_private.return_request_json(r.id); END IF;
  RAISE EXCEPTION 'A return request already exists for this order. Open it to see updates';
 END IF;
 IF EXISTS(SELECT 1 FROM public.online_return_requests WHERE id=k) THEN RAISE EXCEPTION 'Request id unavailable' USING ERRCODE='42501'; END IF;
 IF o.status<>'delivered' THEN RAISE EXCEPTION 'Return requests open after delivery. Contact us for help with this order'; END IF;
 IF coalesce(p->>'reason','') NOT IN ('damaged','wrong_item','size_fit','other') OR coalesce(p->>'requested_resolution','') NOT IN ('refund','exchange')
 OR coalesce(length(trim(p->>'message')),0) NOT BETWEEN 10 AND 2000 THEN RAISE EXCEPTION 'Choose a reason, preferred resolution and a description of 10–2000 characters'; END IF;
 IF jsonb_typeof(p->'items') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Select the items for this request'; END IF;
 IF jsonb_array_length(p->'items') NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'Select 1–50 order items'; END IF;
 INSERT INTO public.online_return_requests(id,order_id,reason,requested_resolution,message)
 VALUES(k,o.id,p->>'reason',p->>'requested_resolution',trim(p->>'message'));
 FOR item IN SELECT jsonb_array_elements(p->'items') LOOP
  SELECT * INTO line FROM public.online_order_lines WHERE order_id=o.id AND line_no=(item->>'line_no')::int;
  IF line.id IS NULL THEN RAISE EXCEPTION 'Select an item from this order'; END IF;
  IF line.line_no=ANY(seen) THEN RAISE EXCEPTION 'Select each item once'; END IF;
  IF jsonb_typeof(item->'quantity') IS DISTINCT FROM 'number' OR (item->>'quantity')::numeric<>trunc((item->>'quantity')::numeric) THEN RAISE EXCEPTION 'Choose a whole return quantity'; END IF;
  qty:=(item->>'quantity')::int;
  IF qty<1 OR qty>line.quantity THEN RAISE EXCEPTION 'Return quantity exceeds the ordered quantity'; END IF;
  INSERT INTO public.online_return_items VALUES(k,line.id,qty); seen:=seen||line.line_no;
 END LOOP;
 INSERT INTO public.online_return_events(request_id,actor,status,message) VALUES(k,'customer','submitted',trim(p->>'message'));
 RETURN app_private.return_request_json(k);
END $$;


ALTER FUNCTION "public"."create_return_request"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_app_role"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT role FROM public.users WHERE id = auth.uid() AND active = true
$$;


ALTER FUNCTION "public"."current_app_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_cash_session"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;
RETURN (SELECT public.cash_session_summary(id) FROM public.cash_sessions WHERE user_id = auth.uid() AND status = 'open');
END;$$;


ALTER FUNCTION "public"."current_cash_session"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."customer_discount_codes"("p_customer_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT COALESCE(public.is_counter_staff(), false) THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
    RETURN COALESCE((SELECT jsonb_agg(public.discount_code_json(c) ORDER BY c.created_at DESC)
                     FROM public.discount_codes c WHERE c.customer_id = p_customer_id), '[]'::jsonb);
END;
$$;


ALTER FUNCTION "public"."customer_discount_codes"("p_customer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."customer_statement"("p_customer" "uuid", "p_from" "date", "p_to" "date") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE c public.customers; v_opening NUMERIC; v_entries JSONB; v_delta NUMERIC;
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) THEN RAISE EXCEPTION 'Only counter staff can see statements' USING ERRCODE='42501'; END IF;
 IF p_from IS NULL OR p_to IS NULL OR p_from>p_to THEN RAISE EXCEPTION 'Choose a valid statement date range'; END IF;
 SELECT * INTO c FROM public.customers WHERE id=p_customer;
 IF c.id IS NULL THEN RAISE EXCEPTION 'Customer not found'; END IF;
 SELECT coalesce(sum(amount),0) INTO v_opening FROM public.customer_ledger WHERE customer_id=p_customer AND created_at<(p_from::timestamp AT TIME ZONE public.report_tz());
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'date',x.created_at,'type',x.entry_type,'document_no',x.document_no,
   'note',x.note,'debit',greatest(x.amount,0),'credit',greatest(-x.amount,0),'balance',x.balance) ORDER BY x.created_at,x.id),'[]'::jsonb),coalesce(sum(x.amount),0)
 INTO v_entries,v_delta FROM (
   SELECT l.*,coalesce(s.invoice_number,r.return_no,h.payment_no) document_no,
     v_opening+sum(l.amount) OVER(ORDER BY l.created_at,l.id ROWS UNBOUNDED PRECEDING) balance
   FROM public.customer_ledger l LEFT JOIN public.sales s ON s.id=l.sale_id LEFT JOIN public.returns r ON r.id=l.return_id
   LEFT JOIN public.customer_payments h ON h.id=l.payment_id
   WHERE l.customer_id=p_customer AND l.created_at>=(p_from::timestamp AT TIME ZONE public.report_tz()) AND l.created_at<((p_to+1)::timestamp AT TIME ZONE public.report_tz())
 ) x;
 RETURN jsonb_build_object('customer',jsonb_build_object('id',c.id,'name',c.name,'phone',c.phone,'credit_limit',c.credit_limit,'balance',c.credit_used),
   'opening_balance',v_opening,'entries',v_entries,'closing_balance',v_opening+v_delta);
END; $$;


ALTER FUNCTION "public"."customer_statement"("p_customer" "uuid", "p_from" "date", "p_to" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."customers_with_balance"("p" "jsonb" DEFAULT '{}'::"jsonb") RETURNS TABLE("customer" "jsonb", "oldest_unpaid_date" "date", "last_payment_date" "date", "total_count" bigint)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_q TEXT:=replace(replace(replace(trim(coalesce(p->>'q','')),E'\\',E'\\\\'),'%',E'\\%'),'_',E'\\_');
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) THEN RAISE EXCEPTION 'Only counter staff can see customer balances' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT to_jsonb(c),
   (SELECT (min(l.created_at) AT TIME ZONE public.report_tz())::date FROM public.customer_ledger l WHERE l.customer_id=c.id AND l.amount>0),
   (SELECT (max(l.created_at) AT TIME ZONE public.report_tz())::date FROM public.customer_ledger l WHERE l.customer_id=c.id AND l.entry_type='payment'),count(*) OVER()
 FROM public.customers c WHERE c.credit_used>0 AND (v_q='' OR c.name ILIKE '%'||v_q||'%' OR c.phone ILIKE '%'||v_q||'%' OR c.email ILIKE '%'||v_q||'%')
 ORDER BY c.name,c.id LIMIT least(200,greatest(1,coalesce((p->>'limit')::int,50))) OFFSET greatest(0,coalesce((p->>'offset')::int,0));
END; $$;


ALTER FUNCTION "public"."customers_with_balance"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."default_branch_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT id FROM public.branches WHERE active ORDER BY created_at, code LIMIT 1
$$;


ALTER FUNCTION "public"."default_branch_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_business_lookup"("p_kind" "text", "p_id" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_before JSONB;
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) THEN RAISE EXCEPTION 'Only managers can manage lookups' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('business-lookup:'||p_kind,0));
 CASE p_kind
 WHEN 'category' THEN SELECT to_jsonb(c.*) INTO v_before FROM public.categories c WHERE id=p_id::uuid FOR UPDATE;
 WHEN 'size_scheme' THEN SELECT to_jsonb(s.*) INTO v_before FROM public.size_schemes s WHERE id=p_id::uuid FOR UPDATE;
 ELSE SELECT to_jsonb(b.*) INTO v_before FROM public.business_lookups b WHERE id=p_id::uuid AND kind=p_kind FOR UPDATE;
 END CASE;
 IF v_before IS NULL THEN RAISE EXCEPTION 'Lookup no longer exists'; END IF;
 IF public.lookup_usage(p_kind,p_id)>0 THEN RAISE EXCEPTION 'This lookup is in use. Deactivate it, or reassign its records before deleting.'; END IF;
 CASE p_kind
 WHEN 'category' THEN DELETE FROM public.categories WHERE id=p_id::uuid;
 WHEN 'size_scheme' THEN DELETE FROM public.size_schemes WHERE id=p_id::uuid;
 ELSE DELETE FROM public.business_lookups WHERE id=p_id::uuid AND kind=p_kind;
 END CASE;
 INSERT INTO public.lookup_events(kind,lookup_id,action,old_value) VALUES(p_kind,p_id,'delete',v_before);
END; $$;


ALTER FUNCTION "public"."delete_business_lookup"("p_kind" "text", "p_id" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."discount_codes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "kind" "text" NOT NULL,
    "description" "text",
    "customer_id" "uuid",
    "discount_type" "text" NOT NULL,
    "value" numeric(14,2) NOT NULL,
    "min_amount" numeric(14,2),
    "max_discount" numeric(14,2),
    "valid_from" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone,
    "max_uses" integer,
    "used_count" integer DEFAULT 0 NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "discount_codes_code_check" CHECK (("code" ~ '^[A-Z0-9-]{4,24}$'::"text")),
    CONSTRAINT "discount_codes_dates" CHECK ((("expires_at" IS NULL) OR ("expires_at" > "valid_from"))),
    CONSTRAINT "discount_codes_discount_type_check" CHECK (("discount_type" = ANY (ARRAY['percentage'::"text", 'fixed'::"text"]))),
    CONSTRAINT "discount_codes_kind_check" CHECK (("kind" = ANY (ARRAY['welcome'::"text", 'manual'::"text"]))),
    CONSTRAINT "discount_codes_max_discount_check" CHECK (("max_discount" > (0)::numeric)),
    CONSTRAINT "discount_codes_max_uses_check" CHECK (("max_uses" > 0)),
    CONSTRAINT "discount_codes_min_amount_check" CHECK (("min_amount" >= (0)::numeric)),
    CONSTRAINT "discount_codes_percent" CHECK ((("discount_type" <> 'percentage'::"text") OR ("value" <= (100)::numeric))),
    CONSTRAINT "discount_codes_used_count_check" CHECK (("used_count" >= 0)),
    CONSTRAINT "discount_codes_value_check" CHECK (("value" > (0)::numeric)),
    CONSTRAINT "discount_codes_welcome_customer" CHECK ((("kind" <> 'welcome'::"text") OR (("customer_id" IS NOT NULL) AND ("max_uses" = 1))))
);


ALTER TABLE "public"."discount_codes" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."discount_code_json"("p_code" "public"."discount_codes") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
    SELECT jsonb_build_object(
        'id', p_code.id, 'code', p_code.code, 'kind', p_code.kind, 'description', p_code.description,
        'customer_id', p_code.customer_id, 'discount_type', p_code.discount_type, 'value', p_code.value,
        'min_amount', p_code.min_amount, 'max_discount', p_code.max_discount,
        'valid_from', p_code.valid_from, 'expires_at', p_code.expires_at,
        'max_uses', p_code.max_uses, 'used_count', p_code.used_count, 'active', p_code.active,
        'status', CASE
            WHEN NOT p_code.active THEN 'off'
            WHEN p_code.max_uses IS NOT NULL AND p_code.used_count >= p_code.max_uses THEN 'used'
            WHEN p_code.expires_at IS NOT NULL AND p_code.expires_at <= now() THEN 'expired'
            WHEN p_code.valid_from > now() THEN 'scheduled'
            ELSE 'ready' END)
$$;


ALTER FUNCTION "public"."discount_code_json"("p_code" "public"."discount_codes") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."expire_online_orders"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."expire_online_orders"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."expire_stock_reservations"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."expire_stock_reservations"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."find_sale_for_return"("p_invoice" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_sale public.sales;
    v_days INTEGER;
BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;

    IF public.current_app_role() NOT IN ('admin', 'manager', 'cashier') THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_sale FROM public.sales
    WHERE upper(invoice_number) = upper(trim(p_invoice)) AND public.is_branch_member(branch_id);
    IF v_sale.id IS NULL THEN
        RAISE EXCEPTION 'No sale with invoice number %', trim(p_invoice);
    END IF;
    IF v_sale.status = 'draft' THEN
        RAISE EXCEPTION '% is a draft, not a completed sale', v_sale.invoice_number;
    END IF;

    SELECT COALESCE(return_window_days, 7) INTO v_days FROM public.app_settings ORDER BY created_at LIMIT 1;

    RETURN jsonb_build_object(
        'sale', jsonb_build_object(
            'id', v_sale.id, 'invoice_number', v_sale.invoice_number, 'created_at', v_sale.created_at,
            'customer_id', v_sale.customer_id, 'customer_name', v_sale.customer_name, 'cashier', v_sale.cashier,
            'total', v_sale.total, 'status', v_sale.status),
        'return_window_days', v_days,
        'within_window', v_sale.created_at >= now() - make_interval(days => v_days),
        'lines', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'sale_line_id', sl.id, 'variant_id', sl.variant_id, 'description', sl.description, 'sku', sl.sku,
                'unit', sl.unit, 'quantity', sl.quantity, 'total', sl.total, 'is_gift', sl.is_gift,
                'returned', COALESCE((SELECT sum(rl.quantity) FROM public.return_lines rl WHERE rl.sale_line_id = sl.id), 0)
            ) ORDER BY sl.line_no), '[]'::jsonb)
            FROM public.sale_lines sl WHERE sl.sale_id = v_sale.id),
        'returns', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object('return_no', r.return_no, 'refund_total', r.refund_total,
                                                         'created_at', r.created_at) ORDER BY r.created_at), '[]'::jsonb)
            FROM public.returns r WHERE r.sale_id = v_sale.id)
    );
END;
$$;


ALTER FUNCTION "public"."find_sale_for_return"("p_invoice" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."force_close_cash_session"("p_session_id" "uuid", "p_counted_cash" numeric, "p_notes" "text", "p_request_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."force_close_cash_session"("p_session_id" "uuid", "p_counted_cash" numeric, "p_notes" "text", "p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_invoice_number"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    settings_id UUID;
    prefix TEXT;
    counter INTEGER;
BEGIN
    SELECT id, invoice_prefix, invoice_counter
    INTO settings_id, prefix, counter
    FROM public.app_settings
    ORDER BY created_at
    LIMIT 1
    FOR UPDATE;

    prefix := COALESCE(prefix, 'INV');
    counter := COALESCE(counter, 1000) + 1;

    IF settings_id IS NOT NULL THEN
        UPDATE public.app_settings SET invoice_counter = counter WHERE id = settings_id;
    END IF;

    RETURN prefix || '-' || LPAD(counter::TEXT, 6, '0');
END;
$$;


ALTER FUNCTION "public"."generate_invoice_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_cash_variance_alert"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NEW.cash_variance_alert IS DISTINCT FROM OLD.cash_variance_alert
       AND auth.uid() IS NOT NULL AND NOT public.has_app_role(ARRAY['admin']) THEN
        RAISE EXCEPTION 'Only administrators can change the cash difference alert' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."guard_cash_variance_alert"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_customer_balance"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
 IF (TG_OP='INSERT' AND coalesce(NEW.credit_used,0)<>0) THEN
   RAISE EXCEPTION 'The balance changes only through payments and sales' USING ERRCODE='42501';
 ELSIF TG_OP='UPDATE' AND NEW.credit_used IS DISTINCT FROM OLD.credit_used
       AND current_setting('app.customer_ledger',true) IS DISTINCT FROM 'on' THEN
   RAISE EXCEPTION 'The balance changes only through payments and sales' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END; $$;


ALTER FUNCTION "public"."guard_customer_balance"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_auth_user_marked_staff"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    base_username TEXT;
BEGIN
    IF COALESCE(NEW.raw_app_meta_data->>'account_type', '') <> 'staff'
       OR COALESCE(OLD.raw_app_meta_data->>'account_type', '') = 'staff'
       OR EXISTS (SELECT 1 FROM public.users WHERE id = NEW.id) THEN
        RETURN NEW;
    END IF;

    base_username := COALESCE(
        NULLIF(trim(NEW.raw_user_meta_data->>'username'), ''),
        split_part(COALESCE(NEW.email, NEW.id::text), '@', 1)
    );
    IF EXISTS (SELECT 1 FROM public.users WHERE username = base_username) THEN
        base_username := base_username || '-' || substr(NEW.id::text, 1, 6);
    END IF;

    INSERT INTO public.users (id, username, name, email, role, permissions, active)
    VALUES (
        NEW.id,
        base_username,
        COALESCE(NULLIF(trim(NEW.raw_user_meta_data->>'name'), ''), base_username),
        COALESCE(NEW.email, ''),
        'cashier',
        '{}',
        false
    )
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.branch_memberships (user_id, branch_id)
    SELECT NEW.id, public.default_branch_id()
    WHERE public.default_branch_id() IS NOT NULL
    ON CONFLICT DO NOTHING;

    -- The customer account made at insert time belongs to no one yet
    DELETE FROM public.customer_accounts WHERE id = NEW.id AND customer_id IS NULL;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_auth_user_marked_staff"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_auth_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    is_first_user BOOLEAN;
    is_staff_account BOOLEAN;
    base_username TEXT;
    new_role TEXT;
BEGIN
    SELECT NOT EXISTS (SELECT 1 FROM public.users) INTO is_first_user;
    is_staff_account := is_first_user OR COALESCE(NEW.raw_app_meta_data->>'account_type', '') = 'staff';

    IF NOT is_staff_account THEN
        INSERT INTO public.customer_accounts (id, full_name, email, phone)
        VALUES (
            NEW.id,
            NULLIF(trim(NEW.raw_user_meta_data->>'name'), ''),
            NEW.email,
            public.normalize_phone(COALESCE(NULLIF(NEW.phone, ''), NULLIF(trim(NEW.raw_user_meta_data->>'phone'), '')))
        )
        ON CONFLICT (id) DO NOTHING;
        RETURN NEW;
    END IF;

    base_username := COALESCE(
        NULLIF(trim(NEW.raw_user_meta_data->>'username'), ''),
        split_part(COALESCE(NEW.email, NEW.id::text), '@', 1)
    );
    IF EXISTS (SELECT 1 FROM public.users WHERE username = base_username) THEN
        base_username := base_username || '-' || substr(NEW.id::text, 1, 6);
    END IF;

    new_role := CASE WHEN is_first_user THEN 'admin' ELSE 'cashier' END;

    INSERT INTO public.users (id, username, name, email, role, permissions, active)
    VALUES (
        NEW.id,
        base_username,
        COALESCE(NULLIF(trim(NEW.raw_user_meta_data->>'name'), ''), base_username),
        COALESCE(NEW.email, ''),
        new_role,
        '{}',
        is_first_user
    )
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.branch_memberships (user_id, branch_id)
    SELECT NEW.id, public.default_branch_id()
    WHERE public.default_branch_id() IS NOT NULL
    ON CONFLICT DO NOTHING;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_auth_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."has_app_role"("roles" "text"[]) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT COALESCE(public.current_app_role() = ANY(roles), false)
$$;


ALTER FUNCTION "public"."has_app_role"("roles" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."idempotency_begin"("p_key" "uuid", "p_operation" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."idempotency_begin"("p_key" "uuid", "p_operation" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."idempotency_finish"("p_key" "uuid", "p_result" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF p_key IS NOT NULL THEN
        UPDATE public.idempotency_keys SET result = p_result WHERE key = p_key;
    END IF;
    RETURN p_result;
END;
$$;


ALTER FUNCTION "public"."idempotency_finish"("p_key" "uuid", "p_result" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."import_opening_balances"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE
 v_request UUID; v_existing JSONB; r JSONB; n INT:=0; v_phone TEXT;
 v_amount NUMERIC; v_customer UUID; v_created INT:=0; v_balances INT:=0;
 v_total NUMERIC:=0; v_skipped JSONB:='[]'; v_count INT;
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin']),false) THEN
  RAISE EXCEPTION 'Only administrators can import opening balances' USING ERRCODE='42501';
 END IF;
 v_request:=nullif(p->>'request_id','')::uuid;
 IF v_request IS NULL THEN RAISE EXCEPTION 'request_id is required'; END IF;
 v_existing:=public.idempotency_begin(v_request,'import_opening_balances');
 IF v_existing IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=v_request AND user_id=auth.uid()) THEN
   RAISE EXCEPTION 'Request id belongs to another user' USING ERRCODE='42501'; END IF;
  RETURN v_existing;
 END IF;
 IF jsonb_typeof(p->'rows') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Choose a balances file'; END IF;
 IF jsonb_array_length(p->'rows')=0 THEN RAISE EXCEPTION 'Add at least one balance'; END IF;
 -- Validate every row before creating any customer or ledger entry.
 FOR r IN SELECT * FROM jsonb_array_elements(p->'rows') LOOP
  n:=n+1;
  IF coalesce(trim(r->>'name'),'')='' THEN RAISE EXCEPTION 'Row %: name is required',n; END IF;
  v_phone:=public.normalize_phone(r->>'phone');
  IF v_phone IS NULL OR v_phone !~ '^\+[1-9][0-9]{7,14}$' THEN RAISE EXCEPTION 'Row %: phone number is not valid',n; END IF;
  BEGIN v_amount:=(r->>'amount')::numeric;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
   RAISE EXCEPTION 'Row %: amount must be positive with at most 2 decimals',n;
  END;
  IF v_amount IS NULL OR v_amount<=0 OR v_amount>=1000000000000 OR v_amount<>round(v_amount,2)
    OR v_amount::text IN ('NaN','Infinity','-Infinity') THEN
   RAISE EXCEPTION 'Row %: amount must be positive with at most 2 decimals',n;
  END IF;
 END LOOP;
 n:=0;
 -- Serialise this small one-off import; avoid overlapping batches locking
 -- the same customers in opposite file order.
 PERFORM pg_advisory_xact_lock(hashtextextended('go_live_customer_import',0));
 FOR r IN SELECT * FROM jsonb_array_elements(p->'rows') LOOP
  n:=n+1; v_phone:=public.normalize_phone(r->>'phone');
  INSERT INTO public.customers(name,phone) VALUES(trim(r->>'name'),v_phone)
   ON CONFLICT (phone) WHERE phone IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  v_created:=v_created+v_count;
  SELECT id INTO v_customer FROM public.customers WHERE phone=v_phone FOR UPDATE;
  IF EXISTS(SELECT 1 FROM public.customer_ledger WHERE customer_id=v_customer AND entry_type='opening') THEN
   v_skipped:=v_skipped||jsonb_build_array(jsonb_build_object('row',n,'phone',v_phone,'reason','An opening balance already exists'));
  ELSE
   v_amount:=(r->>'amount')::numeric;
   INSERT INTO public.customer_ledger(customer_id,entry_type,amount,note)
    VALUES(v_customer,'opening',v_amount,nullif(trim(r->>'note'),''));
   v_balances:=v_balances+1; v_total:=v_total+v_amount;
  END IF;
 END LOOP;
 RETURN public.idempotency_finish(v_request,jsonb_build_object('created_customers',v_created,'balances',v_balances,'total_amount',v_total,'skipped',v_skipped));
END; $_$;


ALTER FUNCTION "public"."import_opening_balances"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."initiate_online_payment"("p_order_no" "text", "p_account_id" "uuid", "p_provider" "text", "p_provider_ref" "text", "p_method" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."initiate_online_payment"("p_order_no" "text", "p_account_id" "uuid", "p_provider" "text", "p_provider_ref" "text", "p_method" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_branch_member"("p_branch_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT public.has_app_role(ARRAY['admin'])
        OR (public.is_staff() AND EXISTS (
            SELECT 1 FROM public.branch_memberships m
            WHERE m.user_id = auth.uid() AND m.branch_id = p_branch_id
        ))
$$;


ALTER FUNCTION "public"."is_branch_member"("p_branch_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_counter_staff"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT public.has_app_role(ARRAY['admin', 'manager', 'cashier'])
$$;


ALTER FUNCTION "public"."is_counter_staff"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_staff"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT public.current_app_role() IS NOT NULL
$$;


ALTER FUNCTION "public"."is_staff"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_website_customer"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
 SELECT EXISTS(SELECT 1 FROM public.customer_accounts WHERE id=auth.uid()) AND NOT public.is_staff()
$$;


ALTER FUNCTION "public"."is_website_customer"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."issue_customer_welcome_code"("p_customer_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_code public.discount_codes;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can issue welcome codes' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.customers WHERE id = p_customer_id) THEN
        RAISE EXCEPTION 'Customer not found';
    END IF;
    IF NOT (SELECT welcome_enabled FROM public.discount_code_settings WHERE id) THEN
        RAISE EXCEPTION 'Switch on welcome codes in Discounts first';
    END IF;
    v_code := public.issue_welcome_code(p_customer_id);
    IF v_code.id IS NULL THEN
        RAISE EXCEPTION 'This customer already has a welcome code';
    END IF;
    RETURN public.discount_code_json(v_code);
END;
$$;


ALTER FUNCTION "public"."issue_customer_welcome_code"("p_customer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."issue_welcome_code"("p_customer_id" "uuid") RETURNS "public"."discount_codes"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_settings public.discount_code_settings;
    v_code public.discount_codes;
BEGIN
    SELECT * INTO v_settings FROM public.discount_code_settings WHERE id;
    IF NOT COALESCE(v_settings.welcome_enabled, false) THEN
        RETURN NULL;
    END IF;
    INSERT INTO public.discount_codes (code, kind, description, customer_id, discount_type, value,
                                       min_amount, max_discount, expires_at, max_uses, created_by)
    VALUES (public.new_discount_code(), 'welcome', 'Welcome code', p_customer_id, v_settings.welcome_type,
            v_settings.welcome_value, v_settings.welcome_min_amount, v_settings.welcome_max_discount,
            now() + make_interval(days => v_settings.welcome_valid_days), 1, auth.uid())
    ON CONFLICT (customer_id) WHERE kind = 'welcome' DO NOTHING
    RETURNING * INTO v_code;
    RETURN v_code;
END;
$$;


ALTER FUNCTION "public"."issue_welcome_code"("p_customer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."issue_welcome_code_for_new_customer"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    PERFORM public.issue_welcome_code(NEW.id);
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."issue_welcome_code_for_new_customer"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."limit_open_online_orders"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."limit_open_online_orders"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."link_customer_account"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE a UUID; c UUID; ph TEXT;
BEGIN
 a:=public.require_website_customer();
 PERFORM 1 FROM public.customer_accounts WHERE id=a FOR UPDATE;
 SELECT public.normalize_phone(phone) INTO ph FROM auth.users WHERE id=a AND phone_confirmed_at IS NOT NULL;
 IF ph IS NULL OR ph='' THEN RETURN jsonb_build_object('status','link_in_shop'); END IF;
 SELECT id INTO c FROM public.customers WHERE phone=ph FOR UPDATE;
 IF c IS NULL THEN RETURN jsonb_build_object('status','link_in_shop'); END IF;
 IF EXISTS(SELECT 1 FROM public.customer_accounts WHERE customer_id=c AND id<>a)
 OR EXISTS(SELECT 1 FROM public.customer_accounts WHERE id=a AND customer_id IS NOT NULL AND customer_id<>c) THEN
  RAISE EXCEPTION 'Please ask the shop to check your account link';
 END IF;
 UPDATE public.customer_accounts SET phone=ph,customer_id=c,phone_verified=true WHERE id=a;
 RETURN jsonb_build_object('status','linked');
END $$;


ALTER FUNCTION "public"."link_customer_account"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_business_lookups"("p_kind" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) THEN RAISE EXCEPTION 'Only managers can manage lookups' USING ERRCODE='42501'; END IF;
 CASE p_kind
 WHEN 'category' THEN RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'description',c.description,'active',c.active,'usage_count',public.lookup_usage(p_kind,c.id::text)) ORDER BY c.name,c.id) FROM public.categories c),'[]'::jsonb);
 WHEN 'size_scheme' THEN RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'code',s.code,'sizes',s.sizes,'active',s.active,'usage_count',public.lookup_usage(p_kind,s.id::text)) ORDER BY s.name,s.id) FROM public.size_schemes s),'[]'::jsonb);
 ELSE
  IF p_kind NOT IN ('brand','material','season','color','fit','bank','return_reason','stock_reason','customer_tier') OR p_kind IS NULL THEN RAISE EXCEPTION 'Unknown lookup type'; END IF;
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',b.id,'name',b.value,'active',b.active,'usage_count',public.lookup_usage(p_kind,b.id::text)) ORDER BY b.value,b.id) FROM public.business_lookups b WHERE b.kind=p_kind),'[]'::jsonb);
 END CASE;
END; $$;


ALTER FUNCTION "public"."list_business_lookups"("p_kind" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_cash_sessions"("p" "jsonb" DEFAULT '{}'::"jsonb") RETURNS TABLE("id" "uuid", "session_no" "text", "user_id" "uuid", "user_name" "text", "status" "text", "opened_at" timestamp with time zone, "closed_at" timestamp with time zone, "opening_float" numeric, "cash_sales" numeric, "refunds" numeric, "cash_in" numeric, "cash_out" numeric, "expected_cash" numeric, "counted_cash" numeric, "variance" numeric, "closing_notes" "text", "closed_by_name" "text", "over_limit" boolean, "total_count" bigint)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."list_cash_sessions"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_online_orders"("p" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."list_online_orders"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_return_requests"("p" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE n INT; off INT; result JSONB; total INT;
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 n:=least(100,greatest(1,coalesce((p->>'limit')::int,24))); off:=greatest(0,coalesce((p->>'offset')::int,0));
 SELECT count(*) INTO total FROM public.online_return_requests r JOIN public.online_orders o ON o.id=r.order_id WHERE public.is_branch_member(o.branch_id)
 AND (CASE WHEN coalesce(p->>'status','active')='active' THEN r.status NOT IN ('closed','rejected') WHEN p->>'status'='all' THEN true ELSE r.status=p->>'status' END);
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.updated_at DESC,t.id),'[]'::jsonb) INTO result FROM (
 SELECT r.id,r.order_id,o.order_no,r.status,r.reason,r.updated_at FROM public.online_return_requests r JOIN public.online_orders o ON o.id=r.order_id
 WHERE public.is_branch_member(o.branch_id) AND (CASE WHEN coalesce(p->>'status','active')='active' THEN r.status NOT IN ('closed','rejected') WHEN p->>'status'='all' THEN true ELSE r.status=p->>'status' END)
 ORDER BY r.updated_at DESC,r.id LIMIT n OFFSET off) t;
 RETURN jsonb_build_object('requests',result,'total_count',total);
END $$;


ALTER FUNCTION "public"."list_return_requests"("p" "jsonb") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."stock_balances" (
    "location_id" "uuid" NOT NULL,
    "variant_id" "uuid" NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "on_hand" numeric(18,6) DEFAULT 0 NOT NULL,
    "reserved" numeric(18,6) DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "stock_balances_on_hand_check" CHECK (("on_hand" >= (0)::numeric)),
    CONSTRAINT "stock_balances_reserved_check" CHECK (("reserved" >= (0)::numeric)),
    CONSTRAINT "stock_balances_reserved_le_on_hand" CHECK (("reserved" <= "on_hand"))
);


ALTER TABLE "public"."stock_balances" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lock_stock_balance"("p_location_id" "uuid", "p_variant_id" "uuid") RETURNS "public"."stock_balances"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."lock_stock_balance"("p_location_id" "uuid", "p_variant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lookup_usage"("p_kind" "text", "p_id" "text") RETURNS bigint
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_value TEXT; v_count BIGINT;
BEGIN
 CASE p_kind
 WHEN 'category' THEN SELECT count(*) INTO v_count FROM public.product_styles WHERE category_id=p_id::uuid;
 WHEN 'size_scheme' THEN SELECT count(*) INTO v_count FROM public.product_styles WHERE size_scheme_id=p_id::uuid;
 ELSE
  SELECT value INTO v_value FROM public.business_lookups WHERE id=p_id::uuid AND kind=p_kind;
  CASE p_kind
  WHEN 'brand' THEN SELECT count(*) INTO v_count FROM public.product_styles WHERE lower(brand)=lower(v_value);
  WHEN 'material' THEN SELECT count(*) INTO v_count FROM public.product_styles WHERE lower(material)=lower(v_value);
  WHEN 'season' THEN SELECT count(*) INTO v_count FROM public.product_styles WHERE lower(season)=lower(v_value);
  WHEN 'color' THEN SELECT count(*) INTO v_count FROM public.product_variants WHERE lower(color)=lower(v_value);
  WHEN 'fit' THEN SELECT count(*) INTO v_count FROM public.product_variants WHERE lower(fit)=lower(v_value);
  WHEN 'bank' THEN SELECT (SELECT count(*) FROM public.payments WHERE lower(bank_name)=lower(v_value))
   +(SELECT count(*) FROM public.discounts d WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(d.conditions,'[]'::jsonb)) c WHERE c->>'type'='bank_name' AND lower(c->>'value')=lower(v_value))) INTO v_count;
  WHEN 'stock_reason' THEN SELECT count(*) INTO v_count FROM public.stock_movements WHERE lower(reason)=lower(v_value) OR lower(left(reason,length(v_value)+2))=lower(v_value||': ');
  WHEN 'customer_tier' THEN SELECT (SELECT count(*) FROM public.customers WHERE lower(price_tier)=lower(v_value))+(SELECT count(*) FROM public.discounts d WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(d.conditions,'[]'::jsonb)) c WHERE c->>'type'='customer_tier' AND lower(c->>'value')=lower(v_value))) INTO v_count;
  WHEN 'return_reason' THEN SELECT count(*) INTO v_count FROM public.returns WHERE lower(reason)=lower(v_value) OR lower(left(reason,length(v_value)+2))=lower(v_value||': ');
  ELSE RAISE EXCEPTION 'Unknown lookup type'; END CASE;
 END CASE;
 RETURN coalesce(v_count,0);
END; $$;


ALTER FUNCTION "public"."lookup_usage"("p_kind" "text", "p_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_online_order_paid"("p_order_no" "text", "p_provider" "text", "p_provider_ref" "text", "p_amount" numeric, "p_method" "text", "p_raw" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."mark_online_order_paid"("p_order_no" "text", "p_provider" "text", "p_provider_ref" "text", "p_amount" numeric, "p_method" "text", "p_raw" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."marketing_audience"("p_channel" "text", "p_query" "text" DEFAULT ''::"text", "p_limit" integer DEFAULT 50, "p_offset" integer DEFAULT 0) RETURNS TABLE("name" "text", "contact" "text", "source" "text", "consent_at" timestamp with time zone, "total_count" bigint)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
BEGIN
  IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
    RAISE EXCEPTION 'Marketing audiences are for managers only' USING ERRCODE='42501';
  END IF;
  IF p_channel NOT IN ('email','sms') OR p_channel IS NULL THEN RAISE EXCEPTION 'Choose email or SMS'; END IF;
  RETURN QUERY
  WITH contacts AS (
    SELECT c.name AS person,
      CASE WHEN p_channel='email' THEN lower(trim(c.email)) ELSE public.normalize_phone(c.phone) END AS destination,
      CASE WHEN p_channel='email' THEN c.email_marketing_consent ELSE c.sms_marketing_consent END AS opted,
      CASE WHEN p_channel='email' THEN c.email_consent_at ELSE c.sms_consent_at END AS consent_time,
      'POS'::text AS origin FROM public.customers c
    UNION ALL
    SELECT a.full_name,
      CASE WHEN p_channel='email' THEN lower(trim(a.email)) ELSE public.normalize_phone(a.phone) END,
      CASE WHEN p_channel='email' THEN a.email_marketing_consent ELSE a.sms_marketing_consent END,
      CASE WHEN p_channel='email' THEN a.email_consent_at ELSE a.sms_consent_at END,
      'Website'::text FROM public.customer_accounts a
  ), eligible AS (
    SELECT min(coalesce(c.person,'')) AS person,c.destination,string_agg(DISTINCT c.origin,' + ' ORDER BY c.origin) AS origin,max(c.consent_time) AS consent_time
    FROM contacts c
    WHERE c.opted IS NOT NULL AND CASE WHEN p_channel='email'
      THEN c.destination ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
      ELSE c.destination ~ '^\+[1-9][0-9]{7,14}$' END
    GROUP BY c.destination HAVING bool_and(c.opted)
  )
  SELECT e.person,e.destination,e.origin,e.consent_time,count(*) OVER()
  FROM eligible e
  WHERE coalesce(p_query,'')='' OR position(lower(p_query) IN lower(e.person||' '||e.destination))>0
  ORDER BY e.destination LIMIT least(greatest(coalesce(p_limit,50),1),1000) OFFSET greatest(coalesce(p_offset,0),0);
END; $_$;


ALTER FUNCTION "public"."marketing_audience"("p_channel" "text", "p_query" "text", "p_limit" integer, "p_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."my_online_order"("p_order_no" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE a UUID;v UUID;
BEGIN
 a:=public.require_website_customer();SELECT id INTO v FROM public.online_orders WHERE order_no=p_order_no AND account_id=a;
 IF v IS NULL THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF;
 RETURN public.online_order_public(v);
END $$;


ALTER FUNCTION "public"."my_online_order"("p_order_no" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."my_online_orders"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE a UUID;
BEGIN
 a:=public.require_website_customer();
 RETURN coalesce((SELECT jsonb_agg(public.online_order_public(id) ORDER BY created_at DESC,id) FROM public.online_orders WHERE account_id=a),'[]');
END $$;


ALTER FUNCTION "public"."my_online_orders"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."my_return_request"("p_order_no" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE a UUID; o UUID; r UUID;
BEGIN
 a:=public.require_website_customer();
 SELECT id INTO o FROM public.online_orders WHERE order_no=p_order_no AND account_id=a;
 IF o IS NULL THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF;
 SELECT id INTO r FROM public.online_return_requests WHERE order_id=o;
 RETURN app_private.return_request_json(r);
END $$;


ALTER FUNCTION "public"."my_return_request"("p_order_no" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."needs_bootstrap"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT NOT EXISTS (SELECT 1 FROM public.users)
$$;


ALTER FUNCTION "public"."needs_bootstrap"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."new_discount_code"() RETURNS "text"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_alphabet CONSTANT TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    v_bytes BYTEA;
    v_code TEXT;
    v_i INTEGER;
BEGIN
    LOOP
        v_bytes := uuid_send(gen_random_uuid());
        v_code := 'LV-';
        FOR v_i IN 0 .. 5 LOOP
            v_code := v_code || substr(v_alphabet, get_byte(v_bytes, v_i) % 32 + 1, 1);
        END LOOP;
        EXIT WHEN NOT EXISTS (SELECT 1 FROM public.discount_codes WHERE code = v_code);
    END LOOP;
    RETURN v_code;
END;
$$;


ALTER FUNCTION "public"."new_discount_code"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_customer_phone"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.phone := public.normalize_phone(NEW.phone);
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."normalize_customer_phone"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_discount_code"("p_code" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'public'
    AS $$
    SELECT NULLIF(upper(regexp_replace(COALESCE(p_code, ''), '\s', '', 'g')), '')
$$;


ALTER FUNCTION "public"."normalize_discount_code"("p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_phone"("p_phone" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    digits TEXT := regexp_replace(COALESCE(p_phone, ''), '\D', '', 'g');
BEGIN
    IF digits = '' THEN
        RETURN NULL;
    ELSIF left(digits, 2) = '00' THEN
        RETURN '+' || substr(digits, 3);
    ELSIF left(digits, 1) = '0' AND length(digits) = 11 THEN
        RETURN '+92' || substr(digits, 2);
    ELSIF left(digits, 2) = '92' AND length(digits) = 12 THEN
        RETURN '+' || digits;
    ELSIF length(digits) = 10 AND left(digits, 1) = '3' THEN
        RETURN '+92' || digits;
    ELSIF left(trim(p_phone), 1) = '+' THEN
        RETURN '+' || digits;
    END IF;
    RETURN digits;
END;
$$;


ALTER FUNCTION "public"."normalize_phone"("p_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."online_order_detail"("p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE r JSONB;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.online_orders WHERE id=p_id AND public.is_branch_member(branch_id)) THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF; SELECT to_jsonb(o)||jsonb_build_object('lines',(SELECT coalesce(jsonb_agg(to_jsonb(l) ORDER BY line_no),'[]') FROM public.online_order_lines l WHERE l.order_id=o.id),
 'events',(SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY created_at,id),'[]') FROM public.online_order_events e WHERE e.order_id=o.id),
 'payments',(SELECT coalesce(jsonb_agg(to_jsonb(pay) ORDER BY created_at,id),'[]') FROM public.online_payments pay WHERE pay.order_id=o.id)) INTO r FROM public.online_orders o WHERE o.id=p_id;
 IF r IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;RETURN r;
END $$;


ALTER FUNCTION "public"."online_order_detail"("p_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."online_order_public"("p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
 SELECT jsonb_build_object('order_no',o.order_no,'status',o.status,'payment_status',o.payment_status,'payment_method',o.payment_method,
 'fulfilment',o.fulfilment,'contact_name',o.contact_name,'phone',o.phone,'email',o.email,'address',o.address,'delivery_fee',o.delivery_fee,'assembly',o.assembly,
 'subtotal',o.subtotal,'discount',o.discount,'tax',o.tax,'total',o.total,'tracking_no',o.tracking_no,'courier',o.courier,'notes_customer',o.notes_customer,
 'expires_at',o.expires_at,'created_at',o.created_at,'updated_at',o.updated_at,'cancelled_reason',o.cancelled_reason,
 'lines',(SELECT coalesce(jsonb_agg(jsonb_build_object('line_no',l.line_no,'variant_id',l.variant_id,'description',l.description,'sku',l.sku,'size',l.size,'color',l.color,
 'unit',l.unit,'quantity',l.quantity,'unit_price',l.unit_price,'taxable',l.taxable,'tax',l.tax,'total',l.total) ORDER BY l.line_no),'[]') FROM public.online_order_lines l WHERE l.order_id=o.id),
 'events',(SELECT coalesce(jsonb_agg(jsonb_build_object('event',e.event,'message',e.public_message,'created_at',e.created_at) ORDER BY e.created_at,e.id),'[]')
 FROM public.online_order_events e WHERE e.order_id=o.id AND e.public_message IS NOT NULL)) FROM public.online_orders o WHERE o.id=p_id
$$;


ALTER FUNCTION "public"."online_order_public"("p_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."open_cash_session"("p_opening_float" numeric, "p_location_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_location UUID := p_location_id;
    v_branch UUID;
    v_session public.cash_sessions;
BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;

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


ALTER FUNCTION "public"."open_cash_session"("p_opening_float" numeric, "p_location_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."post_customer_payment"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_request UUID; v_customer public.customers; v_existing JSONB; v_header public.customer_payments;
 v_pay JSONB; v_amount NUMERIC; v_total NUMERIC:=0; v_tendered NUMERIC;
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) THEN RAISE EXCEPTION 'Only counter staff can collect payments' USING ERRCODE='42501'; END IF;
 v_request:=nullif(p->>'request_id','')::uuid;
 v_existing:=public.idempotency_begin(v_request,'post_customer_payment');
 IF v_existing IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM public.customer_payments h WHERE h.request_id=v_request AND h.created_by=auth.uid() AND h.customer_id=(p->>'customer_id')::uuid) THEN
     RAISE EXCEPTION 'Request id belongs to another payment' USING ERRCODE='42501';
   END IF;
   RETURN v_existing;
 END IF;
 IF v_request IS NULL THEN RAISE EXCEPTION 'request_id is required'; END IF;
 SELECT * INTO v_customer FROM public.customers WHERE id=(p->>'customer_id')::uuid FOR UPDATE;
 IF v_customer.id IS NULL THEN RAISE EXCEPTION 'Choose a customer'; END IF;
 IF jsonb_typeof(p->'payments') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Add at least one payment'; END IF;
 FOR v_pay IN SELECT * FROM jsonb_array_elements(p->'payments') LOOP
   IF coalesce(v_pay->>'method','') NOT IN ('cash','card','digital') THEN RAISE EXCEPTION 'Choose cash, card or digital for collecting payments'; END IF;
   v_amount:=nullif(v_pay->>'amount','')::numeric;
   IF v_amount IS NULL OR v_amount<=0 OR v_amount<>round(v_amount,2) OR v_amount::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'Each payment needs an amount greater than zero with at most two decimals'; END IF;
   v_total:=v_total+v_amount;
 END LOOP;
 IF v_total=0 THEN RAISE EXCEPTION 'Add at least one payment'; END IF;
 IF v_total>coalesce(v_customer.credit_used,0) THEN RAISE EXCEPTION 'This is more than the customer owes (PKR %)',coalesce(v_customer.credit_used,0); END IF;
 INSERT INTO public.customer_payments(payment_no,request_id,customer_id,total,note)
 VALUES('PAY-'||lpad(nextval('public.customer_payment_no_seq')::text,6,'0'),v_request,v_customer.id,v_total,nullif(trim(p->>'note'),'')) RETURNING * INTO v_header;
 FOR v_pay IN SELECT * FROM jsonb_array_elements(p->'payments') LOOP
   v_amount:=(v_pay->>'amount')::numeric;
   v_tendered:=coalesce(nullif(v_pay->>'tendered','')::numeric,v_amount);
   IF v_pay->>'method'='cash' AND (v_tendered<v_amount OR v_tendered<>round(v_tendered,2) OR v_tendered::text IN ('NaN','Infinity','-Infinity')) THEN RAISE EXCEPTION 'Cash received must cover the payment amount'; END IF;
   INSERT INTO public.payments(customer_payment_id,method,amount,direction,tendered,change_given,reference,card_last4)
   VALUES(v_header.id,v_pay->>'method',v_amount,'in',CASE WHEN v_pay->>'method'='cash' THEN v_tendered END,
     CASE WHEN v_pay->>'method'='cash' THEN v_tendered-v_amount ELSE 0 END,
     nullif(left(v_pay->>'reference',100),''),CASE WHEN v_pay->>'method'='card' THEN nullif(v_pay->>'card_last4','') END);
 END LOOP;
 INSERT INTO public.customer_ledger(customer_id,entry_type,amount,payment_id,note)
 VALUES(v_customer.id,'payment',-v_total,v_header.id,nullif(trim(p->>'note'),''));
 RETURN public.idempotency_finish(v_request,jsonb_build_object('payment_no',v_header.payment_no,'paid',v_total,'balance',v_customer.credit_used-v_total,
   'payments',(SELECT jsonb_agg(jsonb_build_object('method',pay.method,'amount',pay.amount,'reference',pay.reference) ORDER BY pay.created_at,pay.id)
               FROM public.payments pay WHERE pay.customer_payment_id=v_header.id)));
END; $$;


ALTER FUNCTION "public"."post_customer_payment"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."post_exchange"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_previous TEXT:=current_setting('pos.exchange_salesperson',true); v_result JSONB; v_user UUID:=nullif(p->>'salesperson_id','')::uuid; v_recorded UUID;
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 PERFORM set_config('pos.exchange_salesperson',coalesce(v_user::text,''),true);
 v_result:=public.post_exchange_without_commission(p);
 SELECT user_id INTO v_recorded FROM public.sale_commissions WHERE sale_id=(v_result->'sale'->>'id')::uuid;
 IF v_recorded IS DISTINCT FROM v_user THEN RAISE EXCEPTION 'This exchange already has a different salesperson'; END IF;
 PERFORM set_config('pos.exchange_salesperson',coalesce(v_previous,''),true);
 RETURN v_result;
END; $$;


ALTER FUNCTION "public"."post_exchange"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."post_exchange_without_commission"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_request_id UUID := NULLIF(p->>'request_id', '')::uuid;
    v_existing JSONB;
    v_return public.returns;
    v_sale_req JSONB;
    v_quote JSONB;
    v_new_total NUMERIC;
    v_credit NUMERIC;
    v_due NUMERIC;
    v_back NUMERIC;
    v_payments JSONB;
    v_new_sale JSONB;
    v_back_method TEXT := COALESCE(NULLIF(p->>'refund_method', ''), 'cash');
    v_orig public.sales;
BEGIN
    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'request_id is required';
    END IF;
    IF v_back_method NOT IN ('cash', 'card', 'digital', 'credit') THEN
        RAISE EXCEPTION 'Invalid refund method: %', v_back_method;
    END IF;
    v_existing := public.idempotency_begin(v_request_id, 'post_exchange');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    SELECT * INTO v_orig FROM public.sales WHERE id = NULLIF(p->>'sale_id', '')::uuid;

    -- 1. Return: the value becomes exchange credit
    v_return := public.create_return(jsonb_build_object(
        'request_id', NULL, 'sale_id', p->'sale_id', 'reason', p->'reason', 'lines', p->'return_lines'), 'exchange');
    v_credit := v_return.refund_total;

    -- 2. Price the replacement items
    v_sale_req := jsonb_build_object('customer_id', v_orig.customer_id, 'lines', p->'new_lines',
                                     'location_id', v_return.location_id);
    v_quote := public.quote_sale(v_sale_req);
    v_new_total := (v_quote->>'total')::numeric;
    v_due := GREATEST(v_new_total - v_credit, 0);
    v_back := GREATEST(v_credit - v_new_total, 0);

    v_payments := CASE WHEN LEAST(v_credit, v_new_total) > 0
                       THEN jsonb_build_array(jsonb_build_object('method', 'exchange', 'amount', LEAST(v_credit, v_new_total),
                                                                 'reference', v_return.return_no))
                       ELSE '[]'::jsonb END;
    IF v_due > 0 THEN
        IF jsonb_typeof(p->'payments') <> 'array' OR jsonb_array_length(p->'payments') = 0 THEN
            RAISE EXCEPTION 'The customer owes % more; add a payment', v_due;
        END IF;
        IF jsonb_array_length(p->'payments') = 1 AND NULLIF(p->'payments'->0->>'amount', '') IS NULL THEN
            v_payments := v_payments || jsonb_build_array(p->'payments'->0 || jsonb_build_object('amount', v_due));
        ELSE
            v_payments := v_payments || (p->'payments');
        END IF;
    END IF;

    -- 3. The replacement sale, paid first with the exchange credit
    PERFORM set_config('pos.allow_exchange_payment', 'on', true);
    v_new_sale := public.post_sale(v_sale_req || jsonb_build_object(
        'request_id', gen_random_uuid(), 'payments', v_payments,
        'notes', 'Exchange for ' || v_orig.invoice_number || ' (' || v_return.return_no || ')'));
    PERFORM set_config('pos.allow_exchange_payment', 'off', true);

    -- 4. Anything left over goes back to the customer
    IF v_back > 0 THEN
        IF v_back_method = 'credit' THEN
            INSERT INTO public.customer_ledger(customer_id,entry_type,amount,return_id)
            SELECT id,'return_credit',-v_back,v_return.id FROM public.customers
            WHERE id = v_orig.customer_id AND credit_used >= v_back FOR UPDATE;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Store credit refunds can only reduce what the customer owes';
            END IF;
        END IF;
        INSERT INTO public.payments (sale_id, return_id, method, amount, direction, reference)
        VALUES (v_orig.id, v_return.id, v_back_method, v_back, 'out', v_return.return_no);
    END IF;

    UPDATE public.returns SET exchange_sale_id = (v_new_sale->'sale'->>'id')::uuid WHERE id = v_return.id
    RETURNING * INTO v_return;

    RETURN public.idempotency_finish(v_request_id, jsonb_build_object(
        'return', to_jsonb(v_return),
        'sale', v_new_sale->'sale',
        'customer_paid', v_due,
        'refunded', v_back
    ));
END;
$$;


ALTER FUNCTION "public"."post_exchange_without_commission"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."post_goods_receipt"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_request_id UUID := NULLIF(p->>'request_id', '')::uuid;
    v_existing JSONB;
    v_location UUID := NULLIF(p->>'location_id', '')::uuid;
    v_branch UUID;
    v_supplier UUID := NULLIF(p->>'supplier_id', '')::uuid;
    v_supplier_name TEXT := NULLIF(trim(COALESCE(p->>'supplier_name', '')), '');
    v_receipt public.goods_receipts;
    v_line JSONB;
    v_line_no INTEGER := 0;
    v_variant RECORD;
    v_qty NUMERIC;
    v_cost NUMERIC;
    v_on_hand NUMERIC;
    v_old_cost NUMERIC;
    v_total NUMERIC := 0;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can receive stock' USING ERRCODE = '42501';
    END IF;
    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'request_id is required';
    END IF;

    v_existing := public.idempotency_begin(v_request_id, 'post_goods_receipt');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    IF jsonb_typeof(p->'lines') <> 'array' OR jsonb_array_length(p->'lines') = 0 THEN
        RAISE EXCEPTION 'Add at least one item';
    END IF;

    IF v_location IS NULL THEN
        SELECT id INTO v_location FROM public.locations
        WHERE branch_id = public.default_branch_id() AND kind = 'shop_floor' AND active
        ORDER BY created_at LIMIT 1;
    END IF;
    SELECT branch_id INTO v_branch FROM public.locations WHERE id = v_location AND active;
    IF v_branch IS NULL OR NOT public.is_branch_member(v_branch) THEN
        RAISE EXCEPTION 'Receiving location not found' USING ERRCODE = '42501';
    END IF;

    -- Supplier: existing id, or find/create by name
    IF v_supplier IS NULL AND v_supplier_name IS NOT NULL THEN
        SELECT id INTO v_supplier FROM public.suppliers WHERE lower(name) = lower(v_supplier_name);
        IF v_supplier IS NULL THEN
            INSERT INTO public.suppliers (name) VALUES (v_supplier_name) RETURNING id INTO v_supplier;
        END IF;
    END IF;
    IF v_supplier IS NOT NULL THEN
        SELECT name INTO v_supplier_name FROM public.suppliers WHERE id = v_supplier;
        IF v_supplier_name IS NULL THEN
            RAISE EXCEPTION 'Supplier not found';
        END IF;
    END IF;

    -- Header total up front (the receipt is append-only); lines are validated below
    SELECT COALESCE(SUM(round(COALESCE(NULLIF(l->>'quantity', '')::numeric, 0)
                              * COALESCE(NULLIF(l->>'unit_cost', '')::numeric, 0), 2)), 0)
    INTO v_total FROM jsonb_array_elements(p->'lines') l;

    INSERT INTO public.goods_receipts (receipt_no, request_id, branch_id, location_id, supplier_id, supplier_name,
                                       supplier_reference, notes, total_cost)
    VALUES ('GRN-' || lpad(nextval('public.goods_receipt_no_seq')::text, 6, '0'), v_request_id, v_branch, v_location,
            v_supplier, v_supplier_name, NULLIF(trim(p->>'supplier_reference'), ''), NULLIF(trim(p->>'notes'), ''),
            v_total)
    RETURNING * INTO v_receipt;

    -- Lines in variant order (consistent locking with sales)
    FOR v_line IN
        SELECT l FROM jsonb_array_elements(p->'lines') WITH ORDINALITY AS t(l, n)
        ORDER BY l->>'variant_id', n
    LOOP
        v_line_no := v_line_no + 1;

        SELECT v.id, s.unit, s.track_inventory,
               trim(s.name || COALESCE(' ' || v.size, '') || COALESCE(' ' || v.color, '') || COALESCE(' ' || v.fit, '')) AS description
        INTO v_variant
        FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id
        WHERE v.id = NULLIF(v_line->>'variant_id', '')::uuid;
        IF v_variant.id IS NULL THEN
            RAISE EXCEPTION 'Item not found: %', v_line->>'variant_id';
        END IF;
        IF NOT v_variant.track_inventory THEN
            RAISE EXCEPTION '"%" does not track stock', v_variant.description;
        END IF;

        v_qty := NULLIF(v_line->>'quantity', '')::numeric;
        v_cost := COALESCE(NULLIF(v_line->>'unit_cost', '')::numeric, -1);
        IF v_qty IS NULL OR v_qty <= 0 THEN
            RAISE EXCEPTION 'Quantity for "%" must be greater than zero', v_variant.description;
        END IF;
        IF v_cost < 0 THEN
            RAISE EXCEPTION 'Enter the unit cost for "%"', v_variant.description;
        END IF;
        IF v_qty <> trunc(v_qty) THEN
            RAISE EXCEPTION 'Whole quantities only for "%"', v_variant.description;
        END IF;

        -- Weighted average cost over all stock of this item
        SELECT COALESCE(SUM(on_hand), 0) INTO v_on_hand FROM public.stock_balances WHERE variant_id = v_variant.id;
        SELECT unit_cost INTO v_old_cost FROM public.variant_costs WHERE variant_id = v_variant.id FOR UPDATE;
        INSERT INTO public.variant_costs (variant_id, unit_cost)
        VALUES (v_variant.id, CASE
            WHEN v_old_cost IS NULL OR v_on_hand <= 0 THEN v_cost
            ELSE round((v_on_hand * v_old_cost + v_qty * v_cost) / (v_on_hand + v_qty), 4) END)
        ON CONFLICT (variant_id) DO UPDATE SET unit_cost = EXCLUDED.unit_cost;

        PERFORM public.post_stock_movement(v_location, v_variant.id, v_qty, 'receive', 'pos', 'goods_receipt',
                                           v_receipt.id, v_cost, v_receipt.receipt_no);

        INSERT INTO public.goods_receipt_lines (receipt_id, line_no, variant_id, description, quantity, unit_cost,
                                                line_cost)
        VALUES (v_receipt.id, v_line_no, v_variant.id, v_variant.description, v_qty, v_cost, round(v_qty * v_cost, 2));
    END LOOP;

    RETURN public.idempotency_finish(v_request_id, jsonb_build_object(
        'receipt', to_jsonb(v_receipt),
        'lines', (SELECT jsonb_agg(to_jsonb(l) ORDER BY l.line_no) FROM public.goods_receipt_lines l WHERE l.receipt_id = v_receipt.id)
    ));
END;
$$;


ALTER FUNCTION "public"."post_goods_receipt"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."post_return"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_request_id UUID := NULLIF(p->>'request_id', '')::uuid;
    v_existing JSONB;
    v_method TEXT := COALESCE(NULLIF(p->>'refund_method', ''), 'cash');
    v_return public.returns;
BEGIN
    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'request_id is required';
    END IF;
    IF v_method NOT IN ('cash', 'card', 'digital', 'credit') THEN
        RAISE EXCEPTION 'Invalid refund method: %', v_method;
    END IF;
    v_existing := public.idempotency_begin(v_request_id, 'post_return');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    v_return := public.create_return(p, v_method);
    RETURN public.idempotency_finish(v_request_id, jsonb_build_object(
        'return', to_jsonb(v_return),
        'lines', (SELECT jsonb_agg(to_jsonb(l)) FROM public.return_lines l WHERE l.return_id = v_return.id)
    ));
END;
$$;


ALTER FUNCTION "public"."post_return"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."post_sale"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_result JSONB; v_sale public.sales; v_rule public.commission_rules; v_snapshot public.sale_commissions;
 v_user UUID:=coalesce(nullif(p_request->>'salesperson_id',''),nullif(current_setting('pos.exchange_salesperson',true),''))::uuid; v_name TEXT; v_basis NUMERIC; v_amount NUMERIC;
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 v_result:=public.post_sale_without_commission(p_request);
 SELECT * INTO v_sale FROM public.sales WHERE id=(v_result->'sale'->>'id')::uuid;
 IF v_sale.cashier_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'This checkout belongs to another cashier' USING ERRCODE='42501'; END IF;
 IF v_sale.status='draft' THEN
   IF v_user IS NOT NULL THEN RAISE EXCEPTION 'Assign commission when checking out, not on a draft'; END IF;
   RETURN v_result;
 END IF;
 SELECT * INTO v_snapshot FROM public.sale_commissions WHERE sale_id=v_sale.id;
 IF FOUND THEN
   IF v_snapshot.user_id IS DISTINCT FROM v_user THEN RAISE EXCEPTION 'This sale already has a different salesperson'; END IF;
   RETURN v_result;
 END IF;
 IF v_sale.status NOT IN ('completed','credit') THEN RAISE EXCEPTION 'This sale cannot earn commission'; END IF;
 SELECT round(coalesce(sum(net),0),2) INTO v_basis FROM public.sale_lines WHERE sale_id=v_sale.id AND NOT is_gift;
 v_amount:=0;
 IF v_user IS NOT NULL THEN
   SELECT name INTO v_name FROM public.users u WHERE u.id=v_user AND u.active AND u.role IN ('admin','manager','cashier')
    AND (u.role='admin' OR EXISTS(SELECT 1 FROM public.branch_memberships m WHERE m.user_id=u.id AND m.branch_id=v_sale.branch_id));
   IF NOT FOUND THEN RAISE EXCEPTION 'Choose an active salesperson in this branch'; END IF;
   SELECT * INTO v_rule FROM public.commission_rules WHERE branch_id=v_sale.branch_id AND user_id=v_user AND enabled FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Commission is not enabled for this salesperson. Refresh checkout.'; END IF;
   IF v_basis>0 THEN v_amount:=CASE WHEN v_rule.kind='fixed' THEN v_rule.rate ELSE round(v_basis*v_rule.rate/100,2) END; END IF;
 END IF;
 INSERT INTO public.sale_commissions(sale_id,branch_id,user_id,person_name,kind,rate,basis,original_amount)
 VALUES(v_sale.id,v_sale.branch_id,v_user,v_name,v_rule.kind,coalesce(v_rule.rate,0),v_basis,v_amount);
 IF v_amount>0 THEN INSERT INTO public.commission_entries(branch_id,user_id,kind,amount,sale_id)
 VALUES(v_sale.branch_id,v_user,'earned',v_amount,v_sale.id); END IF;
 RETURN v_result;
END; $$;


ALTER FUNCTION "public"."post_sale"("p_request" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."post_sale_without_commission"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_request_id UUID := NULLIF(p_request->>'request_id', '')::uuid;
    v_existing JSONB;
    v_quote JSONB;
    v_status TEXT := COALESCE(NULLIF(p_request->>'status', ''), 'completed');
    v_profile public.users;
    v_total NUMERIC;
    v_payments JSONB := COALESCE(p_request->'payments', '[]'::jsonb);
    v_pay JSONB;
    v_pay_total NUMERIC := 0;
    v_amount NUMERIC;
    v_tendered NUMERIC;
    v_change NUMERIC := 0;
    v_credit NUMERIC := 0;
    v_customer public.customers;
    v_sale public.sales;
    v_line JSONB;
    v_line_no INTEGER := 0;
    v_invoice TEXT;
    v_primary_method TEXT;
    v_card JSONB;
    v_items_snapshot JSONB := '[]'::jsonb;
    v_result JSONB;
BEGIN
    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'request_id is required';
    END IF;
    IF v_status NOT IN ('completed', 'draft') THEN
        RAISE EXCEPTION 'Invalid sale status: %', v_status;
    END IF;

    v_existing := public.idempotency_begin(v_request_id, 'post_sale');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    v_quote := public.quote_sale(p_request);
    v_total := (v_quote->>'total')::numeric;
    SELECT * INTO v_profile FROM public.users WHERE id = auth.uid();

    -- Payments (not needed for drafts)
    IF v_status = 'completed' THEN
        IF jsonb_typeof(v_payments) <> 'array' OR jsonb_array_length(v_payments) = 0 THEN
            IF v_total = 0 THEN
                v_payments := '[]'::jsonb;
            ELSE
                RAISE EXCEPTION 'Add a payment';
            END IF;
        END IF;
        IF jsonb_array_length(v_payments) = 1 AND NULLIF(v_payments->0->>'amount', '') IS NULL THEN
            v_payments := jsonb_build_array(v_payments->0 || jsonb_build_object('amount', v_total));
        END IF;

        FOR v_pay IN SELECT * FROM jsonb_array_elements(v_payments)
        LOOP
            v_amount := (v_pay->>'amount')::numeric;
            IF v_amount IS NULL OR v_amount <= 0 THEN
                RAISE EXCEPTION 'Each payment needs an amount greater than zero';
            END IF;
            IF v_pay->>'method' = 'exchange' AND COALESCE(current_setting('pos.allow_exchange_payment', true), '') <> 'on' THEN
                RAISE EXCEPTION 'Exchange credit can only be used through an exchange' USING ERRCODE = '42501';
            END IF;
            IF v_pay->>'method' NOT IN ('cash', 'card', 'digital', 'credit', 'exchange') THEN
                RAISE EXCEPTION 'Invalid payment method: %', v_pay->>'method';
            END IF;
            IF v_pay->>'method' = 'cash' AND NULLIF(v_pay->>'tendered', '') IS NOT NULL THEN
                v_tendered := (v_pay->>'tendered')::numeric;
                IF v_tendered < v_amount THEN
                    RAISE EXCEPTION 'Cash received is less than the cash amount';
                END IF;
                v_change := v_change + (v_tendered - v_amount);
            END IF;
            IF v_pay->>'method' = 'credit' THEN
                v_credit := v_credit + v_amount;
            END IF;
            v_pay_total := v_pay_total + v_amount;
        END LOOP;

        IF v_pay_total <> v_total THEN
            RAISE EXCEPTION 'Payments (%) do not match the total (%)', v_pay_total, v_total;
        END IF;

        IF v_credit > 0 THEN
            IF NULLIF(v_quote->>'customer_id', '') IS NULL THEN
                RAISE EXCEPTION 'Store credit needs a customer';
            END IF;
            SELECT * INTO v_customer FROM public.customers WHERE id = (v_quote->>'customer_id')::uuid FOR UPDATE;
            IF COALESCE(v_customer.credit_limit, 0) - COALESCE(v_customer.credit_used, 0) < v_credit THEN
                RAISE EXCEPTION 'Customer credit limit exceeded (available: %)',
                    COALESCE(v_customer.credit_limit, 0) - COALESCE(v_customer.credit_used, 0);
            END IF;
            -- The customer stays locked; record the credit after the sale header exists.
        END IF;
    END IF;

    SELECT p->>'method' INTO v_primary_method
    FROM jsonb_array_elements(v_payments) p ORDER BY (p->>'amount')::numeric DESC LIMIT 1;

    SELECT p INTO v_card FROM jsonb_array_elements(v_payments) p WHERE p->>'method' = 'card' LIMIT 1;

    IF v_status = 'draft' THEN
        v_invoice := 'DRAFT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    ELSE
        v_invoice := public.generate_invoice_number();
    END IF;

    -- Snapshot in the legacy `items` shape so existing screens keep working
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'product', jsonb_build_object('id', l->>'variant_id', 'name', l->>'description', 'sku', l->>'sku',
                                      'price', (l->>'unit_price')::numeric, 'unit', l->>'unit'),
        'quantity', (l->>'quantity')::numeric,
        'discount', (l->>'manual_discount')::numeric + (l->>'promotion_discount')::numeric,
        'discountType', 'fixed',
        'subtotal', (l->>'net')::numeric
    )), '[]'::jsonb) INTO v_items_snapshot
    FROM jsonb_array_elements(v_quote->'lines') l
    WHERE NOT (l->>'is_gift')::boolean;

    INSERT INTO public.sales (
        invoice_number, receipt_number, request_id, branch_id, location_id, channel,
        customer_id, customer_name, items, subtotal, discount_amount, tax_amount, total,
        payment_method, card_details, status, cashier, cashier_id, cashier_role, notes,
        applied_discounts, free_gifts, change_due
    ) VALUES (
        v_invoice, v_invoice, v_request_id, (v_quote->>'branch_id')::uuid, (v_quote->>'location_id')::uuid, 'pos',
        NULLIF(v_quote->>'customer_id', '')::uuid, v_quote->>'customer_name', v_items_snapshot,
        (v_quote->>'subtotal')::numeric, (v_quote->>'discount_amount')::numeric,
        (v_quote->>'tax_amount')::numeric, v_total,
        CASE WHEN v_status = 'draft' THEN NULL ELSE COALESCE(v_primary_method, 'cash') END,
        CASE WHEN v_card IS NULL THEN NULL ELSE public.sanitize_card_details(jsonb_build_object(
            'bankName', v_card->>'bank_name', 'cardType', v_card->>'card_type',
            'lastFourDigits', v_card->>'card_last4', 'holderName', v_card->>'holder_name')) END,
        CASE WHEN v_status = 'draft' THEN 'draft' WHEN v_credit > 0 THEN 'credit' ELSE 'completed' END,
        v_profile.name, v_profile.id, v_profile.role, left(p_request->>'notes', 1000),
        COALESCE(v_quote->'applied_discounts', '[]'::jsonb),
        COALESCE((SELECT jsonb_agg(l) FROM jsonb_array_elements(v_quote->'lines') l WHERE (l->>'is_gift')::boolean), '[]'::jsonb),
        v_change
    )
    RETURNING * INTO v_sale;
    IF v_credit > 0 THEN
        INSERT INTO public.customer_ledger(customer_id,entry_type,amount,sale_id)
        VALUES(v_customer.id,'sale_credit',v_credit,v_sale.id);
    END IF;

    FOR v_line IN SELECT * FROM jsonb_array_elements(v_quote->'lines')
    LOOP
        v_line_no := v_line_no + 1;
        INSERT INTO public.sale_lines (
            sale_id, line_no, variant_id, description, sku, unit, quantity, unit_price, gross,
            manual_discount, promotion_discount, net, taxable, tax, total, unit_cost, is_gift, promotion_id
        ) VALUES (
            v_sale.id, v_line_no, (v_line->>'variant_id')::uuid, v_line->>'description', v_line->>'sku',
            v_line->>'unit', (v_line->>'quantity')::numeric, (v_line->>'unit_price')::numeric,
            (v_line->>'gross')::numeric, (v_line->>'manual_discount')::numeric,
            (v_line->>'promotion_discount')::numeric, (v_line->>'net')::numeric,
            (v_line->>'taxable')::boolean, (v_line->>'tax')::numeric, (v_line->>'total')::numeric,
            NULLIF(v_line->>'unit_cost', '')::numeric, (v_line->>'is_gift')::boolean,
            NULLIF(v_line->>'promotion_id', '')::uuid
        );
    END LOOP;

    -- Stock: one movement per item, locked in variant order so two tills
    -- selling the same items can never deadlock each other
    IF v_status = 'completed' THEN
        FOR v_line IN
            SELECT jsonb_build_object(
                'variant_id', l->>'variant_id',
                'quantity', SUM((l->>'quantity')::numeric),
                'unit_cost', MAX(l->>'unit_cost'))
            FROM jsonb_array_elements(v_quote->'lines') l
            WHERE (l->>'track_inventory')::boolean
            GROUP BY l->>'variant_id'
            ORDER BY l->>'variant_id'
        LOOP
            PERFORM public.post_stock_movement(
                (v_quote->>'location_id')::uuid, (v_line->>'variant_id')::uuid,
                -((v_line->>'quantity')::numeric), 'sale', 'pos', 'sale', v_sale.id,
                NULLIF(v_line->>'unit_cost', '')::numeric, NULL
            );
        END LOOP;
    END IF;

    IF v_status = 'completed' THEN
        FOR v_pay IN SELECT * FROM jsonb_array_elements(v_payments)
        LOOP
            INSERT INTO public.payments (
                sale_id, method, amount, tendered, change_given, reference,
                card_type, card_last4, bank_name, holder_name
            ) VALUES (
                v_sale.id, v_pay->>'method', (v_pay->>'amount')::numeric,
                NULLIF(v_pay->>'tendered', '')::numeric,
                CASE WHEN v_pay->>'method' = 'cash' AND NULLIF(v_pay->>'tendered', '') IS NOT NULL
                     THEN (v_pay->>'tendered')::numeric - (v_pay->>'amount')::numeric ELSE 0 END,
                left(v_pay->>'reference', 100),
                CASE WHEN v_pay->>'method' = 'card' THEN left(v_pay->>'card_type', 20) END,
                CASE WHEN v_pay->>'method' = 'card' THEN NULLIF(right(regexp_replace(COALESCE(v_pay->>'card_last4', ''), '\D', '', 'g'), 4), '') END,
                CASE WHEN v_pay->>'method' = 'card' THEN left(v_pay->>'bank_name', 100) END,
                CASE WHEN v_pay->>'method' = 'card' THEN left(v_pay->>'holder_name', 100) END
            );
        END LOOP;
    END IF;

    v_result := jsonb_build_object(
        'sale', to_jsonb(v_sale),
        'lines', (SELECT jsonb_agg(to_jsonb(sl) ORDER BY sl.line_no) FROM public.sale_lines sl WHERE sl.sale_id = v_sale.id),
        'payments', COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.created_at) FROM public.payments p WHERE p.sale_id = v_sale.id), '[]'::jsonb),
        'change_due', v_change
    );
    RETURN public.idempotency_finish(v_request_id, v_result);
END;
$$;


ALTER FUNCTION "public"."post_sale_without_commission"("p_request" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."post_stock_movement"("p_location_id" "uuid", "p_variant_id" "uuid", "p_quantity" numeric, "p_movement_type" "text", "p_channel" "text" DEFAULT 'pos'::"text", "p_reference_type" "text" DEFAULT NULL::"text", "p_reference_id" "uuid" DEFAULT NULL::"uuid", "p_unit_cost" numeric DEFAULT NULL::numeric, "p_reason" "text" DEFAULT NULL::"text") RETURNS "public"."stock_balances"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_balance public.stock_balances;
    v_name TEXT;
BEGIN
    IF p_quantity = 0 THEN
        RAISE EXCEPTION 'Quantity cannot be zero';
    END IF;

    SELECT s.name || COALESCE(' ' || v.size, '') || COALESCE(' ' || v.color, '')
    INTO v_name
    FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id
    WHERE v.id = p_variant_id;
    IF v_name IS NULL THEN
        RAISE EXCEPTION 'Item not found';
    END IF;

    v_balance := public.lock_stock_balance(p_location_id, p_variant_id);

    IF p_quantity < 0 AND v_balance.on_hand - v_balance.reserved + p_quantity < 0 THEN
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


ALTER FUNCTION "public"."post_stock_movement"("p_location_id" "uuid", "p_variant_id" "uuid", "p_quantity" numeric, "p_movement_type" "text", "p_channel" "text", "p_reference_type" "text", "p_reference_id" "uuid", "p_unit_cost" numeric, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prepare_return_photo"("p_id" "uuid", "p_photo_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE a UUID;r public.online_return_requests;photo public.online_return_photos;
BEGIN
 a:=public.require_website_customer();
 SELECT q.* INTO r FROM public.online_return_requests q JOIN public.online_orders o ON o.id=q.order_id WHERE q.id=p_id AND o.account_id=a FOR UPDATE OF q;
 IF r.id IS NULL THEN RAISE EXCEPTION 'Request not found' USING ERRCODE='42501'; END IF;
 IF r.status NOT IN ('submitted','needs_information') THEN RAISE EXCEPTION 'Photos can be added while the request is awaiting review'; END IF;
 IF p_photo_id IS NULL THEN RAISE EXCEPTION 'A photo id is required'; END IF;
 SELECT * INTO photo FROM public.online_return_photos WHERE id=p_photo_id;
 IF photo.id IS NOT NULL THEN
  IF photo.request_id<>r.id THEN RAISE EXCEPTION 'Photo id unavailable' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('id',photo.id,'storage_path',photo.storage_path,'uploaded',EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='return-evidence' AND name=photo.storage_path));
 END IF;
 IF (SELECT count(*) FROM public.online_return_photos WHERE request_id=r.id)>=3 THEN RAISE EXCEPTION 'Up to three product photos are allowed per request'; END IF;
 INSERT INTO public.online_return_photos(id,request_id,storage_path) VALUES(p_photo_id,r.id,r.id::text||'/'||p_photo_id::text||'.webp') RETURNING * INTO photo;
 RETURN jsonb_build_object('id',photo.id,'storage_path',photo.storage_path,'uploaded',false);
END $$;


ALTER FUNCTION "public"."prepare_return_photo"("p_id" "uuid", "p_photo_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_ledger_changes"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RAISE EXCEPTION '% rows cannot be changed or deleted; post a correcting entry instead', TG_TABLE_NAME
        USING ERRCODE = '42501';
END;
$$;


ALTER FUNCTION "public"."prevent_ledger_changes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."promotion_item_matches"("p_ref" "text", "p_variant_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
    SELECT p_ref = p_variant_id::text
        OR EXISTS (SELECT 1 FROM public.product_variants v
                   WHERE v.id = p_variant_id AND v.legacy_product_id::text = p_ref)
$$;


ALTER FUNCTION "public"."promotion_item_matches"("p_ref" "text", "p_variant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."protect_customer_account_columns"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
 IF current_user NOT IN ('postgres','supabase_admin') AND auth.uid() IS NOT NULL AND NOT public.has_app_role(ARRAY['admin','manager']) THEN
  IF NEW.customer_id IS DISTINCT FROM OLD.customer_id OR NEW.phone_verified IS DISTINCT FROM OLD.phone_verified OR NEW.id IS DISTINCT FROM OLD.id THEN
   RAISE EXCEPTION 'This field cannot be changed' USING ERRCODE='42501';
  END IF;
 END IF;
 IF NEW.phone IS DISTINCT FROM OLD.phone AND current_user NOT IN ('postgres','supabase_admin') THEN NEW.phone_verified:=false; END IF;
 NEW.phone:=public.normalize_phone(NEW.phone);
 RETURN NEW;
END $$;


ALTER FUNCTION "public"."protect_customer_account_columns"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."protect_user_privileged_columns"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    -- auth.uid() is NULL for the service role / SQL editor: allow those.
    IF auth.uid() IS NOT NULL AND NOT public.has_app_role(ARRAY['admin']) THEN
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.role IS DISTINCT FROM OLD.role
           OR NEW.active IS DISTINCT FROM OLD.active
           OR NEW.permissions IS DISTINCT FROM OLD.permissions
           OR NEW.email IS DISTINCT FROM OLD.email
           OR NEW.username IS DISTINCT FROM OLD.username THEN
            RAISE EXCEPTION 'Only administrators can change role, status, email or username'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- Never leave the store without an active administrator
    IF OLD.role = 'admin' AND OLD.active = true
       AND (NEW.role <> 'admin' OR NEW.active = false)
       AND NOT EXISTS (
           SELECT 1 FROM public.users
           WHERE role = 'admin' AND active = true AND id <> OLD.id
       ) THEN
        RAISE EXCEPTION 'At least one active administrator is required';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."protect_user_privileged_columns"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."publish_style"("p_style" "uuid", "p_published" boolean, "p_dry_run" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE s public.product_styles; v_problems JSONB:='[]';
BEGIN
 IF NOT public.has_app_role(ARRAY['admin','manager']) THEN RAISE EXCEPTION 'Only managers can publish styles' USING ERRCODE='42501'; END IF;
 SELECT * INTO s FROM public.product_styles WHERE id=p_style FOR UPDATE;
 IF s.id IS NULL THEN RAISE EXCEPTION 'Style not found'; END IF;
 IF p_published IS NULL THEN RAISE EXCEPTION 'Choose whether to publish the style'; END IF;
 IF p_published THEN
  IF s.slug IS NULL OR trim(s.slug)='' THEN v_problems:=v_problems||'"Add a slug"'::jsonb; END IF;
  IF coalesce(nullif(trim(s.web_title),''),nullif(trim(s.name),'')) IS NULL THEN v_problems:=v_problems||'"Add a web title or name"'::jsonb; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.product_images WHERE style_id=s.id) THEN v_problems:=v_problems||'"Add at least one image"'::jsonb; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.product_variants WHERE style_id=s.id AND active AND published AND price>0) THEN v_problems:=v_problems||'"Add a published active variant with a price greater than zero"'::jsonb; END IF;
 END IF;
 IF coalesce(p_dry_run,false) THEN RETURN v_problems; END IF;
 IF jsonb_array_length(v_problems)>0 THEN RAISE EXCEPTION 'Cannot publish: %',(SELECT string_agg(value,'; ') FROM jsonb_array_elements_text(v_problems)); END IF;
 UPDATE public.product_styles SET published=p_published WHERE id=s.id;
 RETURN jsonb_build_object('style_id',s.id,'published',p_published,'problems',v_problems);
END; $$;


ALTER FUNCTION "public"."publish_style"("p_style" "uuid", "p_published" boolean, "p_dry_run" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."quote_online_order"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE s public.app_settings;item JSONB;v RECORD;qty NUMERIC;net NUMERIC(14,2);tax NUMERIC(14,2);sub NUMERIC(14,2):=0;taxes NUMERIC(14,2):=0;
 fee NUMERIC(14,2);total NUMERIC(14,2);lines JSONB:='[]';name TEXT;available BOOLEAN;
 units NUMERIC:=0;bulky NUMERIC(14,2):=0;assembly NUMERIC(14,2):=0;delivery BOOLEAN;want BOOLEAN;offered BOOLEAN;cod BOOLEAN;
BEGIN
 IF p->>'fulfilment' IS NULL OR p->>'fulfilment' NOT IN ('pickup','delivery') THEN RAISE EXCEPTION 'Choose pickup or delivery'; END IF;
 IF p ? 'assembly' AND jsonb_typeof(p->'assembly') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Choose whether to add assembly'; END IF;
 IF jsonb_typeof(p->'lines') IS DISTINCT FROM 'array' OR jsonb_array_length(p->'lines') NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'Add between one and fifty items'; END IF;
 IF (SELECT count(*) FROM jsonb_array_elements(p->'lines'))<>(SELECT count(DISTINCT x->>'variant_id') FROM jsonb_array_elements(p->'lines') x) THEN RAISE EXCEPTION 'Combine duplicate items into one line'; END IF;
 SELECT * INTO s FROM public.app_settings ORDER BY created_at,id LIMIT 1;
 IF s.id IS NULL THEN RAISE EXCEPTION 'Store settings not found'; END IF;
 FOR item IN SELECT jsonb_array_elements(p->'lines') LOOP
  IF jsonb_typeof(item->'quantity') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Enter a quantity'; END IF;
  qty:=(item->>'quantity')::numeric;
  SELECT c.*,ps.taxable,ps.track_inventory,ps.bulky INTO v FROM public.public_catalog c JOIN public.product_styles ps ON ps.id=c.style_id WHERE c.variant_id=nullif(item->>'variant_id','')::uuid AND c.price>0;
  IF NOT FOUND THEN
   SELECT ps.name INTO name FROM public.product_variants pv JOIN public.product_styles ps ON ps.id=pv.style_id WHERE pv.id=nullif(item->>'variant_id','')::uuid;
   RAISE EXCEPTION '% is not available online',coalesce(name,'That item');
  END IF;
  IF qty NOT BETWEEN 1 AND 10 OR qty<>trunc(qty) THEN RAISE EXCEPTION 'Choose a whole quantity from 1 to 10'; END IF;
  net:=round(v.price*qty,2);
  -- Same additive, per-line tax rule used by quote_sale/post_sale; delivery is untaxed.
  tax:=CASE WHEN v.taxable THEN round(net*coalesce(s.tax_rate,0)/100,2) ELSE 0 END;
  SELECT EXISTS(SELECT 1 FROM public.stock_balances b JOIN public.locations l ON l.id=b.location_id WHERE b.variant_id=v.variant_id AND l.active
   AND l.branch_id=public.default_branch_id() AND l.kind IN ('shop_floor','stockroom','online') AND b.on_hand-b.reserved>=qty) INTO available;
  lines:=lines||jsonb_build_array(jsonb_build_object('variant_id',v.variant_id,'description',v.title,'sku',v.sku,'size',v.size,'color',v.color,'unit',v.unit,
   'quantity',qty,'unit_price',v.price,'taxable',v.taxable,'tax',tax,'total',net+tax,'availability',CASE WHEN NOT available THEN 'out_of_stock' ELSE v.stock_level END));
  sub:=sub+net;taxes:=taxes+tax;
  IF v.bulky THEN units:=units+qty; END IF;
 END LOOP;
 delivery:=p->>'fulfilment'='delivery';
 offered:=delivery AND units>0 AND s.assembly_fee IS NOT NULL;
 want:=delivery AND coalesce((p->>'assembly')::boolean,false);
 IF want AND NOT offered THEN RAISE EXCEPTION 'Assembly is not available for this order'; END IF;
 fee:=CASE WHEN NOT delivery OR (s.free_delivery_over IS NOT NULL AND sub>=s.free_delivery_over) THEN 0 ELSE s.delivery_fee END;
 IF delivery THEN bulky:=round(units*s.bulky_delivery_fee,2); END IF;
 IF want THEN assembly:=round(units*s.assembly_fee,2); END IF;
 total:=sub+taxes+fee+bulky+assembly;
 cod:=s.cod_enabled AND (s.cod_max_total IS NULL OR total<=s.cod_max_total);
 RETURN jsonb_build_object('lines',lines,'subtotal',sub,'discount',0,'tax',taxes,'delivery_fee',fee+bulky+assembly,'total',total,
  'bulky_units',units,'bulky_fee',bulky,'assembly',want,'assembly_fee',assembly,
  'assembly_available',offered,'assembly_unit_fee',CASE WHEN offered THEN s.assembly_fee END,
  'cod_allowed',cod,
  'payment_methods',to_jsonb(array_remove(ARRAY[CASE WHEN s.online_card_enabled THEN 'card' END,
   CASE WHEN s.online_card_enabled THEN 'easypaisa' END,CASE WHEN cod THEN 'cod' END],NULL)));
END $$;


ALTER FUNCTION "public"."quote_online_order"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."quote_sale"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_role TEXT := public.current_app_role();
    v_settings public.app_settings;
    v_location public.locations;
    v_customer public.customers;
    v_req JSONB;
    v_variant RECORD;
    v_lines JSONB := '[]'::jsonb;
    v_gifts JSONB := '[]'::jsonb;
    v_promos JSONB := '[]'::jsonb;
    v_qty NUMERIC;
    v_gross NUMERIC;
    v_manual NUMERIC;
    v_dtype TEXT;
    v_dvalue NUMERIC;
    v_max_pct NUMERIC;
    v_subtotal NUMERIC := 0;
    v_manual_total NUMERIC := 0;
    v_net_before_promo NUMERIC;
    v_promo_total NUMERIC := 0;
    v_promo RECORD;
    v_cond JSONB;
    v_eligible BOOLEAN;
    v_amount NUMERIC;
    v_gift_ref TEXT;
    v_gift RECORD;
    v_line JSONB;
    v_i INTEGER;
    v_n INTEGER;
    v_alloc NUMERIC;
    v_alloc_left NUMERIC;
    v_net NUMERIC;
    v_tax NUMERIC;
    v_tax_total NUMERIC := 0;
    v_result_lines JSONB := '[]'::jsonb;
    v_now_local TIMESTAMP;
    v_code_text TEXT := public.normalize_discount_code(p_request->>'discount_code');
    v_code public.discount_codes;
    -- Automatic promotions the cashier removed from this sale
    v_skip TEXT[] := CASE WHEN jsonb_typeof(p_request->'skipped_promotions') = 'array'
        THEN ARRAY(SELECT jsonb_array_elements_text(p_request->'skipped_promotions'))
        ELSE ARRAY[]::TEXT[] END;
BEGIN
    IF v_role IS NULL OR v_role NOT IN ('admin', 'manager', 'cashier') THEN
        RAISE EXCEPTION 'Not authorized to sell' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_settings FROM public.app_settings ORDER BY created_at LIMIT 1;

    IF p_request ? 'location_id' AND NULLIF(p_request->>'location_id', '') IS NOT NULL THEN
        SELECT * INTO v_location FROM public.locations WHERE id = (p_request->>'location_id')::uuid AND active;
    ELSE
        SELECT * INTO v_location FROM public.locations
        WHERE branch_id = public.default_branch_id() AND kind = 'shop_floor' AND active
        ORDER BY created_at LIMIT 1;
    END IF;
    IF v_location.id IS NULL THEN
        RAISE EXCEPTION 'Selling location not found';
    END IF;
    IF NOT public.is_branch_member(v_location.branch_id) THEN
        RAISE EXCEPTION 'Not a member of this branch' USING ERRCODE = '42501';
    END IF;

    IF NULLIF(p_request->>'customer_id', '') IS NOT NULL THEN
        SELECT * INTO v_customer FROM public.customers WHERE id = (p_request->>'customer_id')::uuid;
        IF v_customer.id IS NULL THEN
            RAISE EXCEPTION 'Customer not found';
        END IF;
    END IF;

    IF jsonb_typeof(p_request->'lines') <> 'array' OR jsonb_array_length(p_request->'lines') = 0 THEN
        RAISE EXCEPTION 'A sale needs at least one item';
    END IF;

    v_max_pct := CASE WHEN v_role IN ('admin', 'manager') THEN 100 ELSE v_settings.max_cashier_discount_percent END;

    -- 1. Lines at database prices, with manual discounts within the role limit
    FOR v_req IN SELECT * FROM jsonb_array_elements(p_request->'lines')
    LOOP
        SELECT v.id, v.sku, v.price, v.active AS v_active, s.name, s.unit, s.taxable, s.track_inventory,
               s.active AS s_active, s.kind,
               trim(s.name || COALESCE(' ' || v.size, '') || COALESCE(' ' || v.color, '') || COALESCE(' ' || v.fit, '')) AS description,
               c.unit_cost
        INTO v_variant
        FROM public.product_variants v
        JOIN public.product_styles s ON s.id = v.style_id
        LEFT JOIN public.variant_costs c ON c.variant_id = v.id
        WHERE v.id = NULLIF(v_req->>'variant_id', '')::uuid;

        IF v_variant.id IS NULL THEN
            RAISE EXCEPTION 'Item not found: %', v_req->>'variant_id';
        END IF;
        IF NOT (v_variant.v_active AND v_variant.s_active) THEN
            RAISE EXCEPTION '"%" is no longer for sale', v_variant.description;
        END IF;

        v_qty := COALESCE((v_req->>'quantity')::numeric, 0);
        IF v_qty <= 0 THEN
            RAISE EXCEPTION 'Quantity for "%" must be greater than zero', v_variant.description;
        END IF;
        IF v_qty <> trunc(v_qty) THEN
            RAISE EXCEPTION 'Whole quantities only for "%"', v_variant.description;
        END IF;

        v_gross := round(v_variant.price * v_qty, 2);
        v_dtype := COALESCE(v_req->>'discount_type', 'fixed');
        v_dvalue := COALESCE((v_req->>'discount_value')::numeric, 0);
        IF v_dvalue < 0 THEN
            RAISE EXCEPTION 'Discount cannot be negative';
        END IF;
        v_manual := CASE WHEN v_dtype = 'percentage' THEN round(v_gross * v_dvalue / 100, 2) ELSE round(v_dvalue, 2) END;
        v_manual := LEAST(v_manual, v_gross);
        IF v_gross > 0 AND v_manual > round(v_gross * v_max_pct / 100, 2) THEN
            RAISE EXCEPTION 'Discount on "%" is above your limit of % percent', v_variant.description, trim_scale(v_max_pct)
                USING ERRCODE = '42501';
        END IF;

        v_subtotal := v_subtotal + v_gross;
        v_manual_total := v_manual_total + v_manual;

        v_lines := v_lines || jsonb_build_object(
            'variant_id', v_variant.id,
            'description', v_variant.description,
            'sku', v_variant.sku,
            'unit', v_variant.unit,
            'quantity', v_qty,
            'unit_price', v_variant.price,
            'gross', v_gross,
            'manual_discount', v_manual,
            'taxable', v_variant.taxable,
            'track_inventory', v_variant.track_inventory,
            'unit_cost', v_variant.unit_cost,
            'is_gift', false
        );
    END LOOP;

    v_net_before_promo := v_subtotal - v_manual_total;
    v_now_local := now() AT TIME ZONE COALESCE(
        (SELECT timezone FROM public.branches WHERE id = v_location.branch_id), 'Asia/Karachi');

    -- 2. Promotions
    FOR v_promo IN
        SELECT * FROM public.discounts
        WHERE active AND now() BETWEEN valid_from AND valid_to
          AND NOT (id::text = ANY(v_skip))
          AND (valid_days IS NULL OR cardinality(valid_days) = 0 OR EXTRACT(DOW FROM v_now_local)::int = ANY(valid_days))
        ORDER BY created_at, id
    LOOP
        v_eligible := v_promo.min_amount IS NULL OR v_net_before_promo >= v_promo.min_amount;

        FOR v_cond IN SELECT * FROM jsonb_array_elements(COALESCE(v_promo.conditions, '[]'::jsonb))
        LOOP
            EXIT WHEN NOT v_eligible;
            CASE v_cond->>'type'
                WHEN 'min_amount' THEN
                    v_eligible := v_net_before_promo >= COALESCE((v_cond->>'value')::numeric, 0);
                WHEN 'specific_products' THEN
                    v_eligible := jsonb_typeof(v_cond->'value') = 'array' AND NOT EXISTS (
                        SELECT 1 FROM jsonb_array_elements_text(v_cond->'value') ref
                        WHERE COALESCE((
                            SELECT SUM((l->>'quantity')::numeric) FROM jsonb_array_elements(v_lines) l
                            WHERE public.promotion_item_matches(ref, (l->>'variant_id')::uuid)
                        ), 0) < COALESCE((v_cond->>'minQuantity')::numeric, 1)
                    );
                WHEN 'payment_method' THEN
                    v_eligible := EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(p_request->'payments', '[]')) pm
                                          WHERE pm->>'method' = v_cond->>'value');
                WHEN 'customer_tier' THEN
                    v_eligible := v_customer.id IS NOT NULL AND v_customer.price_tier = v_cond->>'value';
                WHEN 'card_type' THEN
                    v_eligible := EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(p_request->'payments', '[]')) pm
                                          WHERE pm->>'method' = 'card' AND pm->>'card_type' = v_cond->>'value');
                WHEN 'bank_name' THEN
                    v_eligible := EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(p_request->'payments', '[]')) pm
                                          WHERE pm->>'method' = 'card' AND pm->>'bank_name' = v_cond->>'value');
                ELSE
                    v_eligible := false;  -- unknown condition: never apply
            END CASE;
        END LOOP;

        CONTINUE WHEN NOT v_eligible;

        IF v_promo.type = 'free_gift' THEN
            FOREACH v_gift_ref IN ARRAY COALESCE(v_promo.free_gift_products, ARRAY[]::text[])
            LOOP
                SELECT v.id, v.sku, s.name, s.unit, s.track_inventory, c.unit_cost,
                       trim(s.name || COALESCE(' ' || v.size, '') || COALESCE(' ' || v.color, '')) AS description,
                       COALESCE((SELECT on_hand - reserved FROM public.stock_balances b
                                 WHERE b.variant_id = v.id AND b.location_id = v_location.id), 0) AS available
                INTO v_gift
                FROM public.product_variants v
                JOIN public.product_styles s ON s.id = v.style_id
                LEFT JOIN public.variant_costs c ON c.variant_id = v.id
                WHERE (v.id::text = v_gift_ref OR v.legacy_product_id::text = v_gift_ref) AND v.active AND s.active
                LIMIT 1;

                -- A gift that is out of stock is skipped rather than blocking the sale
                IF v_gift.id IS NOT NULL AND (NOT v_gift.track_inventory OR v_gift.available >= 1) THEN
                    v_gifts := v_gifts || jsonb_build_object(
                        'variant_id', v_gift.id, 'description', v_gift.description || ' (gift)', 'sku', v_gift.sku,
                        'unit', v_gift.unit, 'quantity', 1, 'unit_price', 0, 'gross', 0, 'manual_discount', 0,
                        'taxable', false, 'track_inventory', v_gift.track_inventory, 'unit_cost', v_gift.unit_cost,
                        'is_gift', true, 'promotion_id', v_promo.id
                    );
                END IF;
            END LOOP;
            v_promos := v_promos || jsonb_build_object('discountId', v_promo.id, 'discountName', v_promo.name,
                                                       'discountAmount', 0, 'type', 'free_gift');
        ELSE
            v_amount := CASE v_promo.type
                WHEN 'percentage' THEN round(v_net_before_promo * v_promo.value / 100, 2)
                WHEN 'fixed' THEN round(v_promo.value, 2)
                ELSE 0 END;
            IF v_promo.max_discount IS NOT NULL THEN
                v_amount := LEAST(v_amount, v_promo.max_discount);
            END IF;
            v_amount := LEAST(v_amount, v_net_before_promo - v_promo_total);
            IF v_amount > 0 THEN
                v_promo_total := v_promo_total + v_amount;
                v_promos := v_promos || jsonb_build_object('discountId', v_promo.id, 'discountName', v_promo.name,
                                                           'discountAmount', v_amount, 'type', v_promo.type);
            END IF;
        END IF;
    END LOOP;


    -- 2b. Discount code: one more promotion on the same net amount
    IF v_code_text IS NOT NULL THEN
        SELECT * INTO v_code FROM public.discount_codes WHERE code = v_code_text;
        IF v_code.id IS NULL OR NOT v_code.active THEN
            RAISE EXCEPTION 'Discount code % is not valid. Check the spelling.', v_code_text;
        END IF;
        IF v_code.valid_from > now() THEN
            RAISE EXCEPTION 'Discount code % starts on %', v_code.code,
                to_char(v_code.valid_from AT TIME ZONE 'Asia/Karachi', 'DD Mon YYYY');
        END IF;
        IF v_code.expires_at IS NOT NULL AND v_code.expires_at <= now() THEN
            RAISE EXCEPTION 'Discount code % expired on %', v_code.code,
                to_char(v_code.expires_at AT TIME ZONE 'Asia/Karachi', 'DD Mon YYYY');
        END IF;
        IF v_code.max_uses IS NOT NULL AND v_code.used_count >= v_code.max_uses THEN
            RAISE EXCEPTION 'Discount code % has already been used', v_code.code;
        END IF;
        IF v_code.customer_id IS NOT NULL AND v_code.customer_id IS DISTINCT FROM v_customer.id THEN
            RAISE EXCEPTION 'Discount code % belongs to a customer. Select that customer first.', v_code.code;
        END IF;
        IF v_code.min_amount IS NOT NULL AND v_net_before_promo < v_code.min_amount THEN
            RAISE EXCEPTION 'Discount code % needs a minimum spend of %', v_code.code, trim_scale(v_code.min_amount);
        END IF;

        v_amount := CASE v_code.discount_type
            WHEN 'percentage' THEN round(v_net_before_promo * v_code.value / 100, 2)
            ELSE round(v_code.value, 2) END;
        IF v_code.max_discount IS NOT NULL THEN
            v_amount := LEAST(v_amount, v_code.max_discount);
        END IF;
        v_amount := GREATEST(LEAST(v_amount, v_net_before_promo - v_promo_total), 0);
        v_promo_total := v_promo_total + v_amount;
        v_promos := v_promos || jsonb_build_object('discountId', v_code.id, 'discountName', 'Code ' || v_code.code,
                                                   'discountAmount', v_amount, 'type', 'code', 'code', v_code.code);
    END IF;

    -- 3. Spread promotion discounts over lines by net value, then tax per line
    v_n := jsonb_array_length(v_lines);
    v_alloc_left := v_promo_total;
    FOR v_i IN 0 .. v_n - 1
    LOOP
        v_line := v_lines->v_i;
        v_net := (v_line->>'gross')::numeric - (v_line->>'manual_discount')::numeric;
        IF v_i = v_n - 1 THEN
            v_alloc := v_alloc_left;
        ELSIF v_net_before_promo > 0 THEN
            v_alloc := round(v_promo_total * v_net / v_net_before_promo, 2);
        ELSE
            v_alloc := 0;
        END IF;
        v_alloc := LEAST(v_alloc, v_net);
        v_alloc_left := v_alloc_left - v_alloc;
        v_net := v_net - v_alloc;

        v_tax := CASE WHEN (v_line->>'taxable')::boolean
                      THEN round(v_net * COALESCE(v_settings.tax_rate, 0) / 100, 2) ELSE 0 END;
        v_tax_total := v_tax_total + v_tax;

        v_result_lines := v_result_lines || (v_line || jsonb_build_object(
            'promotion_discount', v_alloc, 'net', v_net, 'tax', v_tax, 'total', v_net + v_tax));
    END LOOP;

    FOR v_line IN SELECT * FROM jsonb_array_elements(v_gifts)
    LOOP
        v_result_lines := v_result_lines || (v_line || jsonb_build_object(
            'promotion_discount', 0, 'net', 0, 'tax', 0, 'total', 0));
    END LOOP;

    RETURN jsonb_build_object(
        'branch_id', v_location.branch_id,
        'location_id', v_location.id,
        'customer_id', v_customer.id,
        'customer_name', v_customer.name,
        'lines', v_result_lines,
        'applied_discounts', v_promos,
        'subtotal', v_subtotal,
        'manual_discount', v_manual_total,
        'promotion_discount', v_promo_total,
        'discount_amount', v_manual_total + v_promo_total,
        'tax_rate', COALESCE(v_settings.tax_rate, 0),
        'tax_amount', v_tax_total,
        'total', v_subtotal - v_manual_total - v_promo_total + v_tax_total
    );
END;
$$;


ALTER FUNCTION "public"."quote_sale"("p_request" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."receive_cod_parcel_return"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."receive_cod_parcel_return"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_cash_movement"("p_amount" numeric, "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_session public.cash_sessions;
BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;

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


ALTER FUNCTION "public"."record_cash_movement"("p_amount" numeric, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_cash_payment"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."record_cash_payment"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_commission_payout"("p_branch" "uuid", "p_user" "uuid", "p_amount" numeric, "p_note" "text", "p_request" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_entry public.commission_entries; v_balance NUMERIC;
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) OR NOT coalesce(public.is_branch_member(p_branch),false) THEN RAISE EXCEPTION 'Only branch managers can record payouts' USING ERRCODE='42501'; END IF;
 IF p_request IS NULL OR p_user IS NULL OR p_amount IS NULL OR p_amount<=0 OR p_amount<>round(p_amount,2) OR p_amount::text IN ('NaN','Infinity','-Infinity') OR length(trim(coalesce(p_note,'')))=0 OR length(p_note)>500 THEN RAISE EXCEPTION 'Enter an amount and payment reference (up to 500 characters)'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('commission-request:'||p_request::text,0));
 SELECT * INTO v_entry FROM public.commission_entries WHERE request_id=p_request;
 IF FOUND THEN
   IF v_entry.branch_id IS DISTINCT FROM p_branch OR v_entry.user_id IS DISTINCT FROM p_user OR v_entry.amount<>-p_amount OR v_entry.note<>trim(p_note) OR v_entry.created_by IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Payout reference was already used for a different payment'; END IF;
   RETURN to_jsonb(v_entry);
 END IF;
 -- Serialize payouts for this account. A later return can create a carry-forward debit.
 PERFORM pg_advisory_xact_lock(hashtextextended('commission-account:'||p_branch::text||':'||p_user::text,0));
 SELECT coalesce(sum(amount),0) INTO v_balance FROM public.commission_entries WHERE branch_id=p_branch AND user_id=p_user;
 IF p_amount>v_balance THEN RAISE EXCEPTION 'Payout exceeds outstanding commission (%)',v_balance; END IF;
 INSERT INTO public.commission_entries(branch_id,user_id,kind,amount,note,request_id)
 VALUES(p_branch,p_user,'payout',-p_amount,trim(p_note),p_request) RETURNING * INTO v_entry;
 RETURN to_jsonb(v_entry);
END; $$;


ALTER FUNCTION "public"."record_commission_payout"("p_branch" "uuid", "p_user" "uuid", "p_amount" numeric, "p_note" "text", "p_request" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_marketing_consent"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE email_changed boolean; sms_changed boolean;
BEGIN
  IF TG_OP='UPDATE' THEN
    -- A new address/phone needs its own consent, even if a caller resubmits true.
    IF lower(trim(coalesce(NEW.email,''))) IS DISTINCT FROM lower(trim(coalesce(OLD.email,''))) THEN
      NEW.email_marketing_consent := NULL;
    END IF;
    IF public.normalize_phone(NEW.phone) IS DISTINCT FROM public.normalize_phone(OLD.phone) THEN
      NEW.sms_marketing_consent := NULL;
    END IF;
    email_changed := NEW.email_marketing_consent IS DISTINCT FROM OLD.email_marketing_consent
      OR lower(trim(coalesce(NEW.email,''))) IS DISTINCT FROM lower(trim(coalesce(OLD.email,'')));
    sms_changed := NEW.sms_marketing_consent IS DISTINCT FROM OLD.sms_marketing_consent
      OR public.normalize_phone(NEW.phone) IS DISTINCT FROM public.normalize_phone(OLD.phone);
    NEW.email_consent_at := OLD.email_consent_at;
    NEW.sms_consent_at := OLD.sms_consent_at;
  ELSE
    email_changed := NEW.email_marketing_consent IS NOT NULL;
    sms_changed := NEW.sms_marketing_consent IS NOT NULL;
    NEW.email_consent_at := NULL;
    NEW.sms_consent_at := NULL;
  END IF;
  IF NEW.email_marketing_consent IS TRUE AND coalesce(trim(NEW.email),'') !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
    RAISE EXCEPTION 'A valid email is required for email offers';
  END IF;
  IF NEW.sms_marketing_consent IS TRUE AND coalesce(public.normalize_phone(NEW.phone),'') !~ '^\+[1-9][0-9]{7,14}$' THEN
    RAISE EXCEPTION 'A valid international phone number is required for SMS offers';
  END IF;
  IF email_changed THEN
    NEW.email_consent_at := CASE WHEN NEW.email_marketing_consent IS NULL THEN NULL ELSE now() END;
    INSERT INTO marketing_consent_events(subject_id,source,channel,contact,consent)
      VALUES(NEW.id,TG_TABLE_NAME,'email',lower(trim(NEW.email)),NEW.email_marketing_consent);
  END IF;
  IF sms_changed THEN
    NEW.sms_consent_at := CASE WHEN NEW.sms_marketing_consent IS NULL THEN NULL ELSE now() END;
    INSERT INTO marketing_consent_events(subject_id,source,channel,contact,consent)
      VALUES(NEW.id,TG_TABLE_NAME,'sms',public.normalize_phone(NEW.phone),NEW.sms_marketing_consent);
  END IF;
  RETURN NEW;
END; $_$;


ALTER FUNCTION "public"."record_marketing_consent"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_online_payment_event"("p_order_no" "text", "p_provider" "text", "p_provider_ref" "text", "p_amount" numeric, "p_method" "text", "p_status" "text", "p_raw" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."record_online_payment_event"("p_order_no" "text", "p_provider" "text", "p_provider_ref" "text", "p_amount" numeric, "p_method" "text", "p_status" "text", "p_raw" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_online_refund"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE k UUID;r JSONB;o public.online_orders;payment public.online_payments;left_paid NUMERIC;refunded NUMERIC;state TEXT;
BEGIN
 IF NOT public.has_app_role(ARRAY['admin','manager']) THEN RAISE EXCEPTION 'Only managers can record an online refund' USING ERRCODE='42501'; END IF;
 k:=nullif(p->>'request_id','')::uuid;r:=public.request_begin(k,'record_online_refund');IF r IS NOT NULL THEN RETURN r;END IF;
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


ALTER FUNCTION "public"."record_online_refund"("p" "jsonb") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."stock_count_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "count_id" "uuid" NOT NULL,
    "variant_id" "uuid" NOT NULL,
    "counted" numeric(18,6) NOT NULL,
    "expected" numeric(18,6) NOT NULL,
    "difference" numeric(18,6),
    "counted_by" "uuid" DEFAULT "auth"."uid"(),
    "counted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "stock_count_lines_counted_check" CHECK (("counted" >= (0)::numeric))
);


ALTER TABLE "public"."stock_count_lines" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_stock_count"("p_count_id" "uuid", "p_variant_id" "uuid", "p_counted" numeric) RETURNS "public"."stock_count_lines"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_count public.stock_counts;
    v_expected NUMERIC;
    v_line public.stock_count_lines;
BEGIN
    IF NOT public.is_staff() THEN
        RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE = '42501';
    END IF;
    IF public.current_app_role() NOT IN ('admin', 'manager', 'cashier') THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_count FROM public.stock_counts WHERE id = p_count_id FOR UPDATE;
    IF v_count.id IS NULL OR NOT public.is_branch_member(v_count.branch_id) THEN
        RAISE EXCEPTION 'Count not found';
    END IF;
    IF v_count.status <> 'open' THEN
        RAISE EXCEPTION 'Count % is %', v_count.count_no, v_count.status;
    END IF;
    IF p_counted IS NULL OR p_counted < 0 THEN
        RAISE EXCEPTION 'Counted quantity cannot be negative';
    END IF;
    IF p_counted <> trunc(p_counted) THEN
        RAISE EXCEPTION 'Whole quantities only';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id
                   WHERE v.id = p_variant_id AND s.track_inventory) THEN
        RAISE EXCEPTION 'Item not found or does not track stock';
    END IF;

    SELECT COALESCE((SELECT on_hand FROM public.stock_balances
                     WHERE variant_id = p_variant_id AND location_id = v_count.location_id), 0)
    INTO v_expected;

    INSERT INTO public.stock_count_lines (count_id, variant_id, counted, expected)
    VALUES (p_count_id, p_variant_id, p_counted, v_expected)
    ON CONFLICT (count_id, variant_id)
    DO UPDATE SET counted = EXCLUDED.counted, expected = EXCLUDED.expected,
                  counted_by = auth.uid(), counted_at = now()
    RETURNING * INTO v_line;
    RETURN v_line;
END;
$$;


ALTER FUNCTION "public"."record_stock_count"("p_count_id" "uuid", "p_variant_id" "uuid", "p_counted" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."redeem_sale_discount_code"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_entry JSONB;
    v_code public.discount_codes;
BEGIN
    IF NEW.status NOT IN ('completed', 'credit') THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.status IN ('completed', 'credit', 'refunded') THEN
        RETURN NEW;
    END IF;

    FOR v_entry IN
        SELECT e FROM jsonb_array_elements(COALESCE(NEW.applied_discounts, '[]'::jsonb)) e WHERE e->>'type' = 'code'
    LOOP
        SELECT * INTO v_code FROM public.discount_codes WHERE id = (v_entry->>'discountId')::uuid FOR UPDATE;
        IF v_code.id IS NULL OR NOT v_code.active
           OR (v_code.expires_at IS NOT NULL AND v_code.expires_at <= now())
           OR (v_code.max_uses IS NOT NULL AND v_code.used_count >= v_code.max_uses) THEN
            RAISE EXCEPTION 'Discount code % was just used or switched off. Remove it and try again.', v_entry->>'code';
        END IF;
        INSERT INTO public.discount_code_redemptions (code_id, code, sale_id, customer_id, amount)
        VALUES (v_code.id, v_code.code, NEW.id, NEW.customer_id, COALESCE((v_entry->>'discountAmount')::numeric, 0))
        ON CONFLICT (sale_id) DO NOTHING;
        IF FOUND THEN
            UPDATE public.discount_codes SET used_count = used_count + 1 WHERE id = v_code.id;
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."redeem_sale_discount_code"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."register_catalog_lookups"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE r RECORD;
BEGIN
 FOR r IN SELECT key,value FROM jsonb_each_text(to_jsonb(NEW))
 WHERE key=ANY(CASE WHEN TG_TABLE_NAME='product_styles' THEN ARRAY['brand','material','season'] WHEN TG_TABLE_NAME='customers' THEN ARRAY['price_tier'] ELSE ARRAY['color','fit'] END)
 AND length(trim(coalesce(value,''))) BETWEEN 1 AND 200 LOOP
  IF r.key='price_tier' AND lower(trim(r.value))='standard' THEN CONTINUE; END IF;
  INSERT INTO public.business_lookups(kind,value) VALUES(CASE WHEN r.key='price_tier' THEN 'customer_tier' ELSE r.key END,trim(r.value)) ON CONFLICT DO NOTHING;
 END LOOP;
 RETURN NEW;
END; $$;


ALTER FUNCTION "public"."register_catalog_lookups"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."release_reservation"("p_reservation_id" "uuid") RETURNS "public"."stock_reservations"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_branch UUID;v_reference TEXT;
BEGIN
 SELECT branch_id,reference_type INTO v_branch,v_reference FROM public.stock_reservations WHERE id=p_reservation_id;
 IF NOT public.is_branch_member(v_branch) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF v_reference='online_order' THEN RAISE EXCEPTION 'Use online order cancellation to release this reservation'; END IF;
 RETURN public.close_reservation(p_reservation_id,'released');
END $$;


ALTER FUNCTION "public"."release_reservation"("p_reservation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reply_return_request"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE a UUID; r public.online_return_requests; k UUID; old JSONB;
BEGIN
 a:=public.require_website_customer();
 SELECT q.* INTO r FROM public.online_return_requests q JOIN public.online_orders o ON o.id=q.order_id
 WHERE q.id=(p->>'id')::uuid AND o.account_id=a FOR UPDATE OF q;
 IF r.id IS NULL THEN RAISE EXCEPTION 'Request not found' USING ERRCODE='42501'; END IF;
 k:=nullif(p->>'request_id','')::uuid; IF k IS NULL THEN RAISE EXCEPTION 'A request id is required'; END IF;
 old:=public.idempotency_begin(k,'reply_return_request');
 IF old IS NOT NULL THEN
  IF old->>'id'<>r.id::text OR NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=k AND user_id=auth.uid()) THEN RAISE EXCEPTION 'Request id unavailable' USING ERRCODE='42501'; END IF;
  RETURN old;
 END IF;
 IF r.version IS DISTINCT FROM (p->>'version')::int THEN RAISE EXCEPTION 'This request changed. Refresh before replying'; END IF;
 IF r.status<>'needs_information' THEN RAISE EXCEPTION 'A reply is available when staff request more information'; END IF;
 IF coalesce(length(trim(p->>'message')),0) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'Enter a reply of 1–2000 characters'; END IF;
 UPDATE public.online_return_requests SET status='submitted',version=version+1,updated_at=now() WHERE id=r.id;
 INSERT INTO public.online_return_events(request_id,actor,status,message) VALUES(r.id,'customer','submitted',trim(p->>'message'));
 RETURN public.idempotency_finish(k,app_private.return_request_json(r.id));
END $$;


ALTER FUNCTION "public"."reply_return_request"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."report_line_activity"("p_from" "date", "p_to" "date", "p_branch" "uuid") RETURNS TABLE("variant_id" "uuid", "sale_id" "uuid", "quantity" numeric, "net" numeric, "cost" numeric, "returns" numeric, "discounts" numeric, "is_return" boolean)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT l.variant_id, s.id, l.quantity, l.net,
        l.quantity * coalesce(l.unit_cost, 0), 0::numeric,
        l.manual_discount + l.promotion_discount, false
    FROM public.sales s JOIN public.sale_lines l ON l.sale_id = s.id
    WHERE s.status IN ('completed','credit','refunded')
      AND public.is_branch_member(s.branch_id) AND (p_branch IS NULL OR s.branch_id = p_branch)
      AND s.created_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
      AND s.created_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz())
    UNION ALL
    SELECT l.variant_id, r.sale_id, -l.quantity, -(l.refund_amount - l.tax_amount),
        CASE WHEN l.restocked THEN -l.quantity * coalesce(sl.unit_cost, 0) ELSE 0 END,
        l.refund_amount - l.tax_amount, 0::numeric, true
    FROM public.returns r JOIN public.return_lines l ON l.return_id = r.id
    JOIN public.sale_lines sl ON sl.id = l.sale_line_id
    JOIN public.sales s ON s.id = r.sale_id
    WHERE s.status IN ('completed','credit','refunded')
      AND public.is_branch_member(r.branch_id) AND (p_branch IS NULL OR r.branch_id = p_branch)
      AND r.created_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
      AND r.created_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz())
$$;


ALTER FUNCTION "public"."report_line_activity"("p_from" "date", "p_to" "date", "p_branch" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."report_sales_summary"("p_from" "date", "p_to" "date", "p_branch" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("day" "date", "invoices" integer, "gross" numeric, "discounts" numeric, "net_sales" numeric, "tax" numeric, "returns" numeric, "returns_tax" numeric, "net_after_returns" numeric, "cost" numeric, "margin" numeric)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
        RAISE EXCEPTION 'Only managers can see reports' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    WITH sold AS (
        SELECT (s.created_at AT TIME ZONE public.report_tz())::date AS d,
            count(DISTINCT s.id)::int AS n, sum(l.gross) AS g,
            sum(l.manual_discount + l.promotion_discount) AS discount,
            sum(l.net) AS revenue, sum(l.tax) AS taxes,
            sum(l.quantity * coalesce(l.unit_cost, 0)) AS c
        FROM public.sales s JOIN public.sale_lines l ON l.sale_id = s.id
        -- A fully refunded invoice still contributes its original sale.
        WHERE s.status IN ('completed','credit','refunded')
          AND public.is_branch_member(s.branch_id)
          AND (p_branch IS NULL OR s.branch_id = p_branch)
          AND s.created_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
          AND s.created_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz())
        GROUP BY 1
    ), refunded AS (
        SELECT (r.created_at AT TIME ZONE public.report_tz())::date AS d,
            sum(l.refund_amount - l.tax_amount) AS revenue, sum(l.tax_amount) AS taxes,
            sum(CASE WHEN l.restocked THEN l.quantity * coalesce(sl.unit_cost, 0) ELSE 0 END) AS c
        FROM public.returns r JOIN public.return_lines l ON l.return_id = r.id
        JOIN public.sale_lines sl ON sl.id = l.sale_line_id
        JOIN public.sales s ON s.id = r.sale_id
        WHERE s.status IN ('completed','credit','refunded')
          AND public.is_branch_member(r.branch_id)
          AND (p_branch IS NULL OR r.branch_id = p_branch)
          AND r.created_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
          AND r.created_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz())
        GROUP BY 1
    )
    SELECT coalesce(s.d, r.d), coalesce(s.n, 0), coalesce(s.g, 0), coalesce(s.discount, 0),
        coalesce(s.revenue, 0), coalesce(s.taxes, 0), coalesce(r.revenue, 0), coalesce(r.taxes, 0),
        coalesce(s.revenue, 0) - coalesce(r.revenue, 0), coalesce(s.c, 0) - coalesce(r.c, 0),
        coalesce(s.revenue, 0) - coalesce(r.revenue, 0) - coalesce(s.c, 0) + coalesce(r.c, 0)
    FROM sold s FULL JOIN refunded r ON r.d = s.d ORDER BY 1;
END;
$$;


ALTER FUNCTION "public"."report_sales_summary"("p_from" "date", "p_to" "date", "p_branch" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."report_size_color_matrix"("p_from" "date", "p_to" "date", "p_branch" "uuid" DEFAULT NULL::"uuid", "p_style" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("size" "text", "color" "text", "sold" numeric, "on_hand" numeric)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
        RAISE EXCEPTION 'Only managers can see reports' USING ERRCODE = '42501';
    END IF;
    IF p_style IS NULL THEN
        RAISE EXCEPTION 'Choose a style for the size and color report' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY
    WITH demand AS (
        SELECT a.variant_id, sum(a.quantity) AS qty
        FROM public.report_line_activity(p_from, p_to, p_branch) a GROUP BY a.variant_id
    ), stock AS (
        SELECT b.variant_id, sum(b.on_hand) AS qty FROM public.stock_balances b
        WHERE public.is_branch_member(b.branch_id) AND (p_branch IS NULL OR b.branch_id = p_branch)
        GROUP BY b.variant_id
    )
    SELECT v.size, v.color, sum(coalesce(d.qty, 0)), sum(coalesce(b.qty, 0))
    FROM public.product_variants v LEFT JOIN demand d ON d.variant_id = v.id
    LEFT JOIN stock b ON b.variant_id = v.id
    WHERE v.style_id = p_style AND (d.variant_id IS NOT NULL OR b.variant_id IS NOT NULL)
    GROUP BY v.size, v.color ORDER BY v.size, v.color;
END;
$$;


ALTER FUNCTION "public"."report_size_color_matrix"("p_from" "date", "p_to" "date", "p_branch" "uuid", "p_style" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."report_staff_sales"("p_from" "date", "p_to" "date", "p_branch" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("user_id" "uuid", "name" "text", "invoices" integer, "net_sales" numeric, "returns" numeric, "discounts" numeric)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
        RAISE EXCEPTION 'Only managers can see reports' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT s.cashier_id, coalesce(u.name, 'Unknown'),
        count(DISTINCT a.sale_id) FILTER (WHERE NOT a.is_return)::int,
        coalesce(sum(a.net) FILTER (WHERE NOT a.is_return), 0), sum(a.returns), sum(a.discounts)
    FROM public.report_line_activity(p_from, p_to, p_branch) a
    JOIN public.sales s ON s.id = a.sale_id LEFT JOIN public.users u ON u.id = s.cashier_id
    GROUP BY s.cashier_id, u.name ORDER BY sum(a.net) DESC, s.cashier_id;
END;
$$;


ALTER FUNCTION "public"."report_staff_sales"("p_from" "date", "p_to" "date", "p_branch" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."report_tenders"("p_from" "date", "p_to" "date", "p_branch" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("method" "text", "money_in" numeric, "money_out" numeric, "net" numeric, "count" integer)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
        RAISE EXCEPTION 'Only managers can see reports' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    WITH receipts AS (
        -- amount is already net of change (tendered - change_given) for cash.
        SELECT p.method, p.direction, p.amount
        FROM public.payments p
        LEFT JOIN public.sales s ON s.id = p.sale_id
        LEFT JOIN public.returns r ON r.id = p.return_id
        LEFT JOIN public.cash_sessions cs ON cs.id = p.cash_session_id
        WHERE p.method NOT IN ('exchange','opening') AND (s.id IS NULL OR s.status <> 'draft')
          AND public.is_branch_member(coalesce(r.branch_id, s.branch_id, cs.branch_id))
          AND (p_branch IS NULL OR coalesce(r.branch_id, s.branch_id, cs.branch_id) = p_branch)
          AND p.created_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
          AND p.created_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz())
    )
    SELECT r.method, coalesce(sum(r.amount) FILTER (WHERE r.direction = 'in'), 0),
        coalesce(sum(r.amount) FILTER (WHERE r.direction = 'out'), 0),
        sum(CASE WHEN r.direction = 'out' THEN -r.amount ELSE r.amount END), count(*)::int
    FROM receipts r GROUP BY r.method ORDER BY r.method;
END;
$$;


ALTER FUNCTION "public"."report_tenders"("p_from" "date", "p_to" "date", "p_branch" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."report_top_items"("p_from" "date", "p_to" "date", "p_branch" "uuid" DEFAULT NULL::"uuid", "p_group" "text" DEFAULT 'style'::"text", "p_limit" integer DEFAULT 50) RETURNS TABLE("key" "text", "label" "text", "quantity" numeric, "net" numeric, "cost" numeric, "margin" numeric)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
        RAISE EXCEPTION 'Only managers can see reports' USING ERRCODE = '42501';
    END IF;
    IF p_group IS NULL OR p_group NOT IN ('style','variant','category','size','color') THEN
        RAISE EXCEPTION 'Choose style, variant, category, size or color' USING ERRCODE = '22023';
    END IF;
    IF p_limit IS NULL OR p_limit < 1 THEN
        RAISE EXCEPTION 'Choose a positive report limit' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY
    WITH grouped AS (
        SELECT CASE p_group WHEN 'style' THEN st.id::text WHEN 'variant' THEN v.id::text
            WHEN 'category' THEN c.id::text WHEN 'size' THEN v.size WHEN 'color' THEN v.color END AS k,
            CASE p_group WHEN 'style' THEN st.name WHEN 'variant' THEN v.sku
            WHEN 'category' THEN c.name WHEN 'size' THEN v.size WHEN 'color' THEN v.color END AS lbl,
            a.quantity, a.net, a.cost
        FROM public.report_line_activity(p_from, p_to, p_branch) a
        LEFT JOIN public.product_variants v ON v.id = a.variant_id
        LEFT JOIN public.product_styles st ON st.id = v.style_id
        LEFT JOIN public.categories c ON c.id = st.category_id
    )
    SELECT g.k, coalesce(g.lbl, 'Unspecified'), sum(g.quantity), sum(g.net), sum(g.cost), sum(g.net - g.cost)
    FROM grouped g GROUP BY g.k, g.lbl ORDER BY sum(g.net) DESC, g.k NULLS LAST LIMIT p_limit;
END;
$$;


ALTER FUNCTION "public"."report_top_items"("p_from" "date", "p_to" "date", "p_branch" "uuid", "p_group" "text", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."report_tz"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ SELECT 'Asia/Karachi'::text $$;


ALTER FUNCTION "public"."report_tz"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."request_begin"("p_key" "uuid", "p_operation" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE r JSONB;
BEGIN
 IF p_key IS NULL THEN RAISE EXCEPTION 'request_id is required'; END IF;
 r:=public.idempotency_begin(p_key,p_operation);
 IF NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=p_key AND user_id=auth.uid()) THEN
  RAISE EXCEPTION 'Please use a new request id' USING ERRCODE='42501';
 END IF;
 RETURN r;
END $$;


ALTER FUNCTION "public"."request_begin"("p_key" "uuid", "p_operation" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."require_online_service"() RETURNS "void"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
 -- cron runs as postgres without a JWT; a caller-supplied claim cannot impersonate it.
 IF coalesce(auth.role(),'')<>'service_role' AND NOT (session_user IN ('postgres','supabase_admin') AND auth.uid() IS NULL AND coalesce(auth.role(),'')='') THEN
 RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
END $$;


ALTER FUNCTION "public"."require_online_service"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."require_website_customer"() RETURNS "uuid"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
 IF public.is_staff() THEN RAISE EXCEPTION 'Please use the shop system' USING ERRCODE='42501'; END IF;
 IF auth.uid() IS NULL OR NOT public.is_website_customer() THEN RAISE EXCEPTION 'Please sign in as a customer' USING ERRCODE='42501'; END IF;
 RETURN auth.uid();
END $$;


ALTER FUNCTION "public"."require_website_customer"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reserve_stock"("p_variant_id" "uuid", "p_location_id" "uuid", "p_quantity" numeric, "p_channel" "text", "p_reference_type" "text" DEFAULT NULL::"text", "p_reference_id" "uuid" DEFAULT NULL::"uuid", "p_expires_at" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS "public"."stock_reservations"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."reserve_stock"("p_variant_id" "uuid", "p_location_id" "uuid", "p_quantity" numeric, "p_channel" "text", "p_reference_type" "text", "p_reference_id" "uuid", "p_expires_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reverse_sale_commission"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE c public.sale_commissions; v_returned NUMERIC; v_prior NUMERIC; v_target NUMERIC; v_delta NUMERIC;
BEGIN
 SELECT sc.* INTO c FROM public.sale_commissions sc JOIN public.sale_lines sl ON sl.sale_id=sc.sale_id WHERE sl.id=NEW.sale_line_id;
 IF c.original_amount IS NULL OR c.original_amount=0 OR c.basis=0 THEN RETURN NEW; END IF;
 -- create_return locks the sale header before inserting any return lines.
 SELECT coalesce(sum(rl.refund_amount-rl.tax_amount),0) INTO v_returned FROM public.return_lines rl
 JOIN public.sale_lines sl ON sl.id=rl.sale_line_id WHERE sl.sale_id=c.sale_id AND NOT sl.is_gift;
 SELECT -coalesce(sum(amount),0) INTO v_prior FROM public.commission_entries WHERE sale_id=c.sale_id AND kind='return';
 v_target:=least(c.original_amount,greatest(0,round(c.original_amount*v_returned/c.basis,2)));
 v_delta:=v_target-v_prior;
 IF v_delta>0 THEN INSERT INTO public.commission_entries(branch_id,user_id,kind,amount,sale_id,return_line_id,note)
 VALUES(c.branch_id,c.user_id,'return',-v_delta,c.sale_id,NEW.id,'Proportional return reversal'); END IF;
 RETURN NEW;
END; $$;


ALTER FUNCTION "public"."reverse_sale_commission"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."review_return_request"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE r public.online_return_requests; k UUID; old JSONB; target TEXT; allowed TEXT[];
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 SELECT q.* INTO r FROM public.online_return_requests q JOIN public.online_orders o ON o.id=q.order_id
 WHERE q.id=(p->>'id')::uuid AND public.is_branch_member(o.branch_id) FOR UPDATE OF q;
 IF r.id IS NULL THEN RAISE EXCEPTION 'Request not found' USING ERRCODE='42501'; END IF;
 k:=nullif(p->>'request_id','')::uuid; IF k IS NULL THEN RAISE EXCEPTION 'A request id is required'; END IF;
 old:=public.idempotency_begin(k,'review_return_request');
 IF old IS NOT NULL THEN
  IF old->>'id'<>r.id::text OR NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=k AND user_id=auth.uid()) THEN RAISE EXCEPTION 'Request id unavailable' USING ERRCODE='42501'; END IF;
  RETURN old;
 END IF;
 IF r.version IS DISTINCT FROM (p->>'version')::int THEN RAISE EXCEPTION 'This request changed. Refresh before reviewing'; END IF;
 target:=p->>'status';
 allowed:=CASE r.status WHEN 'submitted' THEN ARRAY['needs_information','return_authorized','rejected'] WHEN 'needs_information' THEN ARRAY['needs_information','return_authorized','rejected']
 WHEN 'return_authorized' THEN ARRAY['received','closed'] WHEN 'received' THEN ARRAY['closed'] ELSE '{}'::text[] END;
 IF target IS NULL OR NOT(target=ANY(allowed)) THEN RAISE EXCEPTION 'That review step is not available'; END IF;
 IF coalesce(length(trim(p->>'message')),0) NOT BETWEEN 1 AND 2000 OR coalesce(length(p->>'staff_note'),0)>2000 THEN RAISE EXCEPTION 'Enter a customer update of 1–2000 characters and keep internal notes under 2001 characters'; END IF;
 UPDATE public.online_return_requests SET status=target,staff_note=coalesce(p->>'staff_note',staff_note),version=version+1,updated_at=now() WHERE id=r.id;
 INSERT INTO public.online_return_events(request_id,actor,status,message) VALUES(r.id,'staff',target,trim(p->>'message'));
 RETURN public.idempotency_finish(k,app_private.return_request_json(r.id));
END $$;


ALTER FUNCTION "public"."review_return_request"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sale_detail"("p_sale_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_sale public.sales;
BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;

    SELECT s.* INTO v_sale FROM public.sales s
    WHERE s.id = p_sale_id AND public.is_counter_staff() AND public.is_branch_member(s.branch_id)
      AND (public.has_app_role(ARRAY['admin','manager']) OR s.cashier_id = auth.uid());
    IF v_sale.id IS NULL THEN RETURN NULL; END IF;
    RETURN jsonb_build_object(
        'header', jsonb_build_object(
            'id', v_sale.id, 'invoice_number', v_sale.invoice_number, 'receipt_number', v_sale.receipt_number,
            'created_at', v_sale.created_at, 'status', v_sale.status,
            'customer_id', v_sale.customer_id, 'customer_name', coalesce(v_sale.customer_name, (SELECT c.name FROM public.customers c WHERE c.id = v_sale.customer_id)),
            'cashier_name', coalesce(v_sale.cashier, (SELECT u.name FROM public.users u WHERE u.id = v_sale.cashier_id)),
            'subtotal', v_sale.subtotal, 'discount_amount', v_sale.discount_amount, 'tax_amount', v_sale.tax_amount,
            'total', v_sale.total, 'payment_method', v_sale.payment_method, 'notes', v_sale.notes),
        -- Explicit public line fields: unit_cost is intentionally not exposed to cashiers.
        'lines', coalesce((SELECT jsonb_agg(jsonb_build_object(
            'id', l.id, 'line_no', l.line_no, 'variant_id', l.variant_id, 'description', l.description,
            'sku', l.sku, 'unit', l.unit, 'quantity', l.quantity, 'unit_price', l.unit_price,
            'gross', l.gross, 'manual_discount', l.manual_discount, 'promotion_discount', l.promotion_discount,
            'net', l.net, 'taxable', l.taxable, 'tax', l.tax, 'total', l.total, 'is_gift', l.is_gift,
            'returned_quantity', coalesce((SELECT sum(rl.quantity) FROM public.return_lines rl WHERE rl.sale_line_id = l.id), 0)
        ) ORDER BY l.line_no) FROM public.sale_lines l WHERE l.sale_id = v_sale.id), '[]'::jsonb),
        'payments', coalesce((SELECT jsonb_agg(jsonb_build_object(
            'id', pay.id, 'created_at', pay.created_at, 'direction', pay.direction, 'method', pay.method,
            'amount', pay.amount, 'tendered', pay.tendered, 'change_given', pay.change_given,
            'reference', pay.reference, 'card_type', pay.card_type, 'card_last4', pay.card_last4, 'return_id', pay.return_id
        ) ORDER BY pay.created_at, pay.id) FROM public.payments pay
        WHERE pay.sale_id = v_sale.id OR EXISTS (SELECT 1 FROM public.returns r WHERE r.id = pay.return_id AND r.sale_id = v_sale.id)), '[]'::jsonb),
        'returns', coalesce((SELECT jsonb_agg(jsonb_build_object(
            'id', r.id, 'return_no', r.return_no, 'created_at', r.created_at, 'reason', r.reason,
            'refund_total', r.refund_total, 'refund_method', r.refund_method
        ) ORDER BY r.created_at, r.id) FROM public.returns r WHERE r.sale_id = v_sale.id), '[]'::jsonb)
    );
END;
$$;


ALTER FUNCTION "public"."sale_detail"("p_sale_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sale_returnable"("p_sale_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;
RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'sale_line_id', sl.id,
        'line_no', sl.line_no,
        'variant_id', sl.variant_id,
        'description', sl.description,
        'sku', sl.sku,
        'unit', sl.unit,
        'quantity', sl.quantity,
        'returned', COALESCE(r.returned, 0),
        'returnable', sl.quantity - COALESCE(r.returned, 0),
        'unit_paid', CASE WHEN sl.quantity > 0 THEN round(sl.total / sl.quantity, 2) ELSE 0 END,
        'is_gift', sl.is_gift
    ) ORDER BY sl.line_no), '[]'::jsonb)
    FROM public.sale_lines sl
    LEFT JOIN (SELECT sale_line_id, sum(quantity) AS returned FROM public.return_lines GROUP BY sale_line_id) r
           ON r.sale_line_id = sl.id
    WHERE sl.sale_id = p_sale_id
      AND EXISTS (SELECT 1 FROM public.sales s WHERE s.id = p_sale_id
                  AND public.is_branch_member(s.branch_id)
                  AND public.current_app_role() IN ('admin', 'manager', 'cashier')));
END;$$;


ALTER FUNCTION "public"."sale_returnable"("p_sale_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sanitize_card_details"("details" "jsonb") RETURNS "jsonb"
    LANGUAGE "sql" IMMUTABLE
    AS $$
    SELECT CASE
        WHEN details IS NULL OR jsonb_typeof(details) <> 'object' THEN NULL
        ELSE jsonb_strip_nulls(jsonb_build_object(
            'bankName', left(details->>'bankName', 100),
            'cardType', CASE WHEN details->>'cardType' IN ('visa', 'mastercard', 'amex', 'discover', 'unionpay', 'other')
                             THEN details->>'cardType' ELSE 'other' END,
            'lastFourDigits', NULLIF(right(regexp_replace(COALESCE(details->>'lastFourDigits', ''), '\D', '', 'g'), 4), ''),
            'holderName', left(details->>'holderName', 100)
        ))
    END
$$;


ALTER FUNCTION "public"."sanitize_card_details"("details" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_business_lookup"("p" "jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE v_kind TEXT:=p->>'kind'; v_id UUID:=nullif(p->>'id','')::uuid; v_name TEXT:=trim(p->>'name');
 v_active BOOLEAN:=coalesce((p->>'active')::boolean,true); v_code TEXT:=upper(trim(p->>'code')); v_sizes TEXT[];
 v_before JSONB; v_after JSONB; v_old TEXT;
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) THEN RAISE EXCEPTION 'Only managers can manage lookups' USING ERRCODE='42501'; END IF;
 IF v_name IS NULL OR length(v_name) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Enter a name up to 200 characters'; END IF;
 IF v_kind IS NULL OR v_kind NOT IN ('category','size_scheme','brand','material','season','color','fit','bank','return_reason','stock_reason','customer_tier') THEN RAISE EXCEPTION 'Unknown lookup type'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('business-lookup:'||v_kind,0));
 IF v_kind='category' THEN
  IF EXISTS(SELECT 1 FROM public.categories WHERE lower(name)=lower(v_name) AND id IS DISTINCT FROM v_id) THEN RAISE EXCEPTION 'A category with this name already exists'; END IF;
  IF v_id IS NULL THEN INSERT INTO public.categories(name,description,active) VALUES(v_name,nullif(trim(p->>'description'),''),v_active) RETURNING id,to_jsonb(categories.*) INTO v_id,v_after;
  ELSE
   SELECT to_jsonb(c.*) INTO v_before FROM public.categories c WHERE id=v_id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Category no longer exists'; END IF;
   UPDATE public.categories SET name=v_name,description=nullif(trim(p->>'description'),''),active=v_active WHERE id=v_id RETURNING to_jsonb(categories.*) INTO v_after;
  END IF;
 ELSIF v_kind='size_scheme' THEN
  IF v_code IS NULL OR v_code !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$' OR jsonb_typeof(p->'sizes') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Enter a code and at least one size'; END IF;
  SELECT array_agg(x.value ORDER BY x.ord) INTO v_sizes FROM (
   SELECT trim(value) value,min(ord) ord FROM jsonb_array_elements_text(p->'sizes') WITH ORDINALITY a(value,ord) GROUP BY trim(value)
  ) x;
  IF coalesce(cardinality(v_sizes),0) NOT BETWEEN 1 AND 100 OR EXISTS(SELECT 1 FROM unnest(v_sizes) x WHERE x IS NULL OR length(x) NOT BETWEEN 1 AND 30) THEN RAISE EXCEPTION 'Enter 1–100 distinct sizes, each up to 30 characters'; END IF;
  IF v_id IS NULL THEN INSERT INTO public.size_schemes(code,name,sizes,active) VALUES(v_code,v_name,v_sizes,v_active) RETURNING id,to_jsonb(size_schemes.*) INTO v_id,v_after;
  ELSE
   SELECT to_jsonb(s.*) INTO v_before FROM public.size_schemes s WHERE id=v_id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Size list no longer exists'; END IF;
   UPDATE public.size_schemes SET code=v_code,name=v_name,sizes=v_sizes,active=v_active WHERE id=v_id RETURNING to_jsonb(size_schemes.*) INTO v_after;
  END IF;
 ELSE
  IF v_kind IN ('return_reason','stock_reason') AND lower(v_name)='other' THEN RAISE EXCEPTION 'Other is the built-in free-text option'; END IF;
  IF v_kind='customer_tier' AND lower(v_name)='standard' THEN RAISE EXCEPTION 'Standard is the built-in default customer tier'; END IF;
  IF v_id IS NULL THEN INSERT INTO public.business_lookups(kind,value,active) VALUES(v_kind,v_name,v_active) RETURNING id,to_jsonb(business_lookups.*) INTO v_id,v_after;
  ELSE
   SELECT to_jsonb(b.*),b.value INTO v_before,v_old FROM public.business_lookups b WHERE id=v_id AND kind=v_kind FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Lookup no longer exists'; END IF;
   UPDATE public.business_lookups SET value=v_name,active=v_active WHERE id=v_id RETURNING to_jsonb(business_lookups.*) INTO v_after;
   -- Keep current catalog metadata consistent; posted sale/payment snapshots stay intact.
   IF v_old IS DISTINCT FROM v_name THEN
    CASE v_kind
    WHEN 'brand' THEN UPDATE public.product_styles SET brand=v_name WHERE lower(brand)=lower(v_old);
    WHEN 'material' THEN UPDATE public.product_styles SET material=v_name WHERE lower(material)=lower(v_old);
    WHEN 'season' THEN UPDATE public.product_styles SET season=v_name WHERE lower(season)=lower(v_old);
    WHEN 'color' THEN UPDATE public.product_variants SET color=v_name WHERE lower(color)=lower(v_old);
    WHEN 'fit' THEN UPDATE public.product_variants SET fit=v_name WHERE lower(fit)=lower(v_old);
    WHEN 'customer_tier' THEN
      UPDATE public.customers SET price_tier=v_name WHERE lower(price_tier)=lower(v_old);
      UPDATE public.discounts d SET conditions=(SELECT jsonb_agg(CASE WHEN c->>'type'='customer_tier' AND lower(c->>'value')=lower(v_old) THEN jsonb_set(c,'{value}',to_jsonb(v_name)) ELSE c END) FROM jsonb_array_elements(d.conditions) c) WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(d.conditions,'[]'::jsonb)) c WHERE c->>'type'='customer_tier' AND lower(c->>'value')=lower(v_old));
    WHEN 'bank' THEN UPDATE public.discounts d SET conditions=(SELECT jsonb_agg(CASE WHEN c->>'type'='bank_name' AND lower(c->>'value')=lower(v_old) THEN jsonb_set(c,'{value}',to_jsonb(v_name)) ELSE c END) FROM jsonb_array_elements(d.conditions) c)
      WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(d.conditions,'[]'::jsonb)) c WHERE c->>'type'='bank_name' AND lower(c->>'value')=lower(v_old));
    ELSE NULL; END CASE;
   END IF;
  END IF;
 END IF;
 INSERT INTO public.lookup_events(kind,lookup_id,action,old_value,new_value) VALUES(v_kind,v_id::text,'save',v_before,v_after);
 RETURN v_id;
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'This name or code already exists, or the rename conflicts with existing variants';
END; $_$;


ALTER FUNCTION "public"."save_business_lookup"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_collection"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE v_request UUID; v_existing JSONB; v_collection public.collections; v_id UUID;
BEGIN
 IF NOT public.has_app_role(ARRAY['admin','manager']) THEN RAISE EXCEPTION 'Only managers can save collections' USING ERRCODE='42501'; END IF;
 v_request:=nullif(p->>'request_id','')::uuid;
 IF v_request IS NULL THEN RAISE EXCEPTION 'request_id is required'; END IF;
 v_existing:=public.idempotency_begin(v_request,'save_collection');
 IF v_existing IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=v_request AND user_id=auth.uid()) THEN RAISE EXCEPTION 'Request id belongs to another user' USING ERRCODE='42501'; END IF;
  RETURN v_existing;
 END IF;
 IF coalesce(p->>'slug','') !~ '^[a-z0-9]+(-[a-z0-9]+)*$' THEN RAISE EXCEPTION 'Use lowercase letters, numbers and hyphens for the collection slug'; END IF;
 IF coalesce(trim(p->>'name'),'')='' THEN RAISE EXCEPTION 'Collection name is required'; END IF;
 v_id:=nullif(p->>'id','')::uuid;
 IF v_id IS NOT NULL THEN
  PERFORM 1 FROM public.collections WHERE id=v_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Collection not found'; END IF;
 ELSE v_id:=gen_random_uuid(); END IF;
 INSERT INTO public.collections(id,slug,name,description,hero_image_path,published,sort_order,starts_at,ends_at)
 VALUES(v_id,p->>'slug',trim(p->>'name'),nullif(p->>'description',''),nullif(p->>'hero_image_path',''),
  coalesce((p->>'published')::boolean,false),coalesce((p->>'sort_order')::int,0),nullif(p->>'starts_at','')::timestamptz,nullif(p->>'ends_at','')::timestamptz)
 ON CONFLICT(id) DO UPDATE SET slug=excluded.slug,name=excluded.name,description=excluded.description,
  hero_image_path=excluded.hero_image_path,published=excluded.published,sort_order=excluded.sort_order,starts_at=excluded.starts_at,ends_at=excluded.ends_at
 RETURNING * INTO v_collection;
 RETURN public.idempotency_finish(v_request,to_jsonb(v_collection));
END; $_$;


ALTER FUNCTION "public"."save_collection"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_commission_rule"("p_branch" "uuid", "p_user" "uuid", "p_kind" "text", "p_rate" numeric, "p_enabled" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) OR NOT coalesce(public.is_branch_member(p_branch),false) THEN RAISE EXCEPTION 'Only branch managers can change commission rules' USING ERRCODE='42501'; END IF;
 IF p_kind IS NULL OR p_kind NOT IN ('fixed','percentage') OR p_enabled IS NULL OR p_rate IS NULL OR p_rate<0 OR p_rate<>round(p_rate,2)
 OR p_rate::text IN ('NaN','Infinity','-Infinity') OR (p_kind='percentage' AND p_rate>100) OR (p_enabled AND p_rate=0) THEN RAISE EXCEPTION 'Enter a valid commission amount or percentage'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.users u WHERE u.id=p_user AND u.role IN ('admin','manager','cashier') AND (NOT p_enabled OR u.active)
 AND (u.role='admin' OR EXISTS(SELECT 1 FROM public.branch_memberships m WHERE m.user_id=u.id AND m.branch_id=p_branch))) THEN RAISE EXCEPTION 'Choose a salesperson in this branch'; END IF;
 INSERT INTO public.commission_rules(branch_id,user_id,kind,rate,enabled,updated_by)
 VALUES(p_branch,p_user,p_kind,p_rate,p_enabled,auth.uid()) ON CONFLICT(branch_id,user_id)
 DO UPDATE SET kind=excluded.kind,rate=excluded.rate,enabled=excluded.enabled,updated_at=now(),updated_by=auth.uid();
END; $$;


ALTER FUNCTION "public"."save_commission_rule"("p_branch" "uuid", "p_user" "uuid", "p_kind" "text", "p_rate" numeric, "p_enabled" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_discount_code"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE
    v_id UUID := NULLIF(p->>'id', '')::uuid;
    v_old public.discount_codes;
    v_code TEXT := public.normalize_discount_code(p->>'code');
    v_type TEXT := COALESCE(NULLIF(p->>'discount_type', ''), 'percentage');
    v_value NUMERIC := (p->>'value')::numeric;
    v_customer UUID := NULLIF(p->>'customer_id', '')::uuid;
    v_from TIMESTAMPTZ := COALESCE(NULLIF(p->>'valid_from', '')::timestamptz, now());
    v_to TIMESTAMPTZ := NULLIF(p->>'expires_at', '')::timestamptz;
    v_uses INTEGER := NULLIF(p->>'max_uses', '')::int;
    v_row public.discount_codes;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can create discount codes' USING ERRCODE = '42501';
    END IF;
    IF v_type NOT IN ('percentage', 'fixed') THEN
        RAISE EXCEPTION 'Choose percent or amount';
    END IF;
    IF v_value IS NULL OR v_value <= 0 THEN
        RAISE EXCEPTION 'Enter a discount greater than zero';
    END IF;
    IF v_type = 'percentage' AND v_value > 100 THEN
        RAISE EXCEPTION 'A percent discount cannot be more than 100';
    END IF;
    IF v_to IS NOT NULL AND v_to <= v_from THEN
        RAISE EXCEPTION 'The end date must be after the start date';
    END IF;
    IF v_uses IS NOT NULL AND v_uses < 1 THEN
        RAISE EXCEPTION 'Number of uses must be at least 1, or leave it empty for unlimited';
    END IF;
    IF v_code IS NOT NULL AND v_code !~ '^[A-Z0-9-]{4,24}$' THEN
        RAISE EXCEPTION 'A code is 4 to 24 letters, numbers or dashes';
    END IF;
    IF v_customer IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.customers WHERE id = v_customer) THEN
        RAISE EXCEPTION 'Customer not found';
    END IF;

    IF v_id IS NULL THEN
        v_code := COALESCE(v_code, public.new_discount_code());
        IF EXISTS (SELECT 1 FROM public.discount_codes WHERE code = v_code) THEN
            RAISE EXCEPTION 'The code % already exists. Choose another.', v_code;
        END IF;
        INSERT INTO public.discount_codes (code, kind, description, customer_id, discount_type, value,
                                           min_amount, max_discount, valid_from, expires_at, max_uses,
                                           active, created_by)
        VALUES (v_code, 'manual', NULLIF(trim(p->>'description'), ''), v_customer, v_type, round(v_value, 2),
                NULLIF((p->>'min_amount')::numeric, 0), NULLIF((p->>'max_discount')::numeric, 0),
                v_from, v_to, v_uses, COALESCE((p->>'active')::boolean, true), auth.uid())
        RETURNING * INTO v_row;
    ELSE
        SELECT * INTO v_old FROM public.discount_codes WHERE id = v_id FOR UPDATE;
        IF v_old.id IS NULL THEN
            RAISE EXCEPTION 'Discount code not found';
        END IF;
        v_code := COALESCE(v_code, v_old.code);
        IF v_code <> v_old.code AND v_old.used_count > 0 THEN
            RAISE EXCEPTION 'This code has been used, so its text cannot change';
        END IF;
        IF v_code <> v_old.code AND EXISTS (SELECT 1 FROM public.discount_codes WHERE code = v_code) THEN
            RAISE EXCEPTION 'The code % already exists. Choose another.', v_code;
        END IF;
        IF v_uses IS NOT NULL AND v_uses < v_old.used_count THEN
            RAISE EXCEPTION 'This code has already been used % times', v_old.used_count;
        END IF;
        IF v_old.kind = 'welcome' AND (v_customer IS DISTINCT FROM v_old.customer_id OR v_uses IS DISTINCT FROM 1) THEN
            RAISE EXCEPTION 'A welcome code stays with its customer and can be used once';
        END IF;
        UPDATE public.discount_codes SET
            code = v_code, description = NULLIF(trim(p->>'description'), ''), customer_id = v_customer,
            discount_type = v_type, value = round(v_value, 2),
            min_amount = NULLIF((p->>'min_amount')::numeric, 0), max_discount = NULLIF((p->>'max_discount')::numeric, 0),
            valid_from = v_from, expires_at = v_to, max_uses = v_uses,
            active = COALESCE((p->>'active')::boolean, v_old.active)
        WHERE id = v_id
        RETURNING * INTO v_row;
    END IF;
    RETURN public.discount_code_json(v_row);
END;
$_$;


ALTER FUNCTION "public"."save_discount_code"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_discount_code_settings"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_row public.discount_code_settings;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can change discount code settings' USING ERRCODE = '42501';
    END IF;
    IF COALESCE(p->>'welcome_type', 'percentage') NOT IN ('percentage', 'fixed') THEN
        RAISE EXCEPTION 'Choose percent or amount';
    END IF;
    IF COALESCE((p->>'welcome_value')::numeric, 0) <= 0 THEN
        RAISE EXCEPTION 'Enter a discount greater than zero';
    END IF;
    IF COALESCE(p->>'welcome_type', 'percentage') = 'percentage' AND (p->>'welcome_value')::numeric > 100 THEN
        RAISE EXCEPTION 'A percent discount cannot be more than 100';
    END IF;
    IF COALESCE((p->>'welcome_valid_days')::int, 0) NOT BETWEEN 1 AND 3650 THEN
        RAISE EXCEPTION 'Codes must last between 1 and 3650 days';
    END IF;

    UPDATE public.discount_code_settings SET
        welcome_enabled = COALESCE((p->>'welcome_enabled')::boolean, false),
        welcome_type = COALESCE(p->>'welcome_type', 'percentage'),
        welcome_value = round((p->>'welcome_value')::numeric, 2),
        welcome_valid_days = (p->>'welcome_valid_days')::int,
        welcome_min_amount = NULLIF((p->>'welcome_min_amount')::numeric, 0),
        welcome_max_discount = NULLIF((p->>'welcome_max_discount')::numeric, 0),
        updated_at = now(),
        updated_by = auth.uid()
    WHERE id
    RETURNING * INTO v_row;
    RETURN to_jsonb(v_row);
END;
$$;


ALTER FUNCTION "public"."save_discount_code_settings"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_product_images"("p_style" "uuid", "p_images" "jsonb", "p_request_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE v_existing JSONB; r JSONB; v_order INT:=0; v_path TEXT; v_result JSONB;
BEGIN
 IF NOT public.has_app_role(ARRAY['admin','manager']) THEN RAISE EXCEPTION 'Only managers can save product images' USING ERRCODE='42501'; END IF;
 IF p_request_id IS NULL THEN RAISE EXCEPTION 'request_id is required'; END IF;
 v_existing:=public.idempotency_begin(p_request_id,'save_product_images');
 IF v_existing IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=p_request_id AND user_id=auth.uid())
   OR v_existing->>'style_id' IS DISTINCT FROM p_style::text THEN RAISE EXCEPTION 'Request id belongs to another image update' USING ERRCODE='42501'; END IF;
  RETURN v_existing;
 END IF;
 PERFORM 1 FROM public.product_styles WHERE id=p_style FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Style not found'; END IF;
 IF jsonb_typeof(p_images) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Choose an image list'; END IF;
 FOR r IN SELECT * FROM jsonb_array_elements(p_images) LOOP
  v_path:=r->>'storage_path';
  IF v_path IS NULL OR left(v_path,length('styles/'||p_style::text||'/'))<>'styles/'||p_style::text||'/'
   OR v_path ~ '(^|/)[.]{1,2}(/|$)' OR position(E'\\' in v_path)>0 OR v_path ~ '[?#%]'
   OR v_path ~ '/$' THEN RAISE EXCEPTION 'Image paths must be inside styles/%/',p_style; END IF;
 END LOOP;
 DELETE FROM public.product_images WHERE style_id=p_style;
 FOR r IN SELECT * FROM jsonb_array_elements(p_images) LOOP
  INSERT INTO public.product_images(style_id,variant_color,storage_path,alt,sort_order)
   VALUES(p_style,nullif(trim(r->>'variant_color'),''),r->>'storage_path',nullif(trim(r->>'alt'),''),coalesce((r->>'sort_order')::int,v_order));
  v_order:=v_order+1;
 END LOOP;
 SELECT jsonb_build_object('style_id',p_style,'images',coalesce(jsonb_agg(to_jsonb(i) ORDER BY sort_order,id),'[]'::jsonb)) INTO v_result
 FROM public.product_images i WHERE style_id=p_style;
 RETURN public.idempotency_finish(p_request_id,v_result);
END; $_$;


ALTER FUNCTION "public"."save_product_images"("p_style" "uuid", "p_images" "jsonb", "p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_style"("p" "jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
 v_style_id UUID := NULLIF(p->>'style_id','')::uuid;
 v_kind TEXT := COALESCE(NULLIF(p->>'kind',''),'item');
 v_unit TEXT; v_track BOOLEAN; v_category UUID; v_scheme UUID;
 v_code TEXT := upper(NULLIF(trim(COALESCE(p->>'code','')),''));
 v_location UUID := NULLIF(p->>'location_id','')::uuid;
 v_row JSONB; v_variant_id UUID; v_is_new BOOLEAN; v_barcode TEXT; v_opening NUMERIC;
 v_seen TEXT[] := ARRAY[]::text[]; v_key TEXT; v_specs JSONB; v_bulky BOOLEAN;
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) THEN
  RAISE EXCEPTION 'Only managers can edit products' USING ERRCODE='42501'; END IF;
 IF v_kind NOT IN ('item','pack','service') THEN RAISE EXCEPTION 'Invalid product kind: %',v_kind; END IF;
 IF NULLIF(trim(COALESCE(p->>'name','')),'') IS NULL OR v_code IS NULL THEN RAISE EXCEPTION 'Style name and code are required'; END IF;
 IF jsonb_typeof(p->'variants')<>'array' OR jsonb_array_length(p->'variants')=0 THEN RAISE EXCEPTION 'Add at least one size or color'; END IF;
 IF p ? 'bulky' AND jsonb_typeof(p->'bulky') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Choose whether the item is bulky'; END IF;
 v_bulky := (p->>'bulky')::boolean;
 IF p ? 'specs' THEN
  IF jsonb_typeof(p->'specs') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Specifications must be an object'; END IF;
  -- Blank values mean "not stated" and are removed.
  SELECT coalesce(jsonb_object_agg(e.key,to_jsonb(btrim(e.value#>>'{}'))),'{}'::jsonb) INTO v_specs
  FROM jsonb_each(p->'specs') e WHERE jsonb_typeof(e.value)='string' AND btrim(e.value#>>'{}')<>'';
  IF NOT app_private.valid_bike_specs(v_specs) THEN
   RAISE EXCEPTION 'Use only the listed specifications, each up to 120 characters'; END IF;
 END IF;

 v_unit := CASE v_kind WHEN 'pack' THEN 'set' WHEN 'service' THEN 'job' ELSE 'piece' END;
 v_track := v_kind<>'service' AND COALESCE((p->>'track_inventory')::boolean,true);

 IF NULLIF(trim(COALESCE(p->>'category','')),'') IS NOT NULL THEN
  INSERT INTO public.categories(name) VALUES(trim(p->>'category')) ON CONFLICT (name) DO NOTHING;
  SELECT id INTO v_category FROM public.categories WHERE name=trim(p->>'category');
 END IF;
 IF NULLIF(p->>'size_scheme','') IS NOT NULL THEN
  SELECT id INTO v_scheme FROM public.size_schemes WHERE code=p->>'size_scheme';
 END IF;

 IF v_style_id IS NULL THEN
  IF EXISTS(SELECT 1 FROM public.product_styles WHERE code=v_code) THEN RAISE EXCEPTION 'Style code % is already used',v_code; END IF;
  INSERT INTO public.product_styles(code,name,kind,unit,category_id,brand,material,season,design_code,
   description,size_scheme_id,taxable,active,track_inventory,image_url,specs,bulky)
  VALUES(v_code,trim(p->>'name'),v_kind,v_unit,v_category,NULLIF(trim(p->>'brand'),''),
   NULLIF(trim(p->>'material'),''),NULLIF(trim(p->>'season'),''),NULLIF(trim(p->>'design_code'),''),
   NULLIF(p->>'description',''),v_scheme,COALESCE((p->>'taxable')::boolean,true),
   COALESCE((p->>'active')::boolean,true),v_track,NULLIF(p->>'image_url',''),coalesce(v_specs,'{}'::jsonb),coalesce(v_bulky,false))
  RETURNING id INTO v_style_id;
 ELSE
  UPDATE public.product_styles SET
   code=v_code,name=trim(p->>'name'),kind=v_kind,unit=v_unit,category_id=v_category,
   brand=NULLIF(trim(p->>'brand'),''),material=NULLIF(trim(p->>'material'),''),
   season=NULLIF(trim(p->>'season'),''),design_code=NULLIF(trim(p->>'design_code'),''),
   description=NULLIF(p->>'description',''),size_scheme_id=v_scheme,
   taxable=COALESCE((p->>'taxable')::boolean,true),active=COALESCE((p->>'active')::boolean,true),
   track_inventory=v_track,image_url=NULLIF(p->>'image_url',''),
   specs=coalesce(v_specs,specs),bulky=coalesce(v_bulky,bulky)
  WHERE id=v_style_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Style not found'; END IF;
 END IF;

 IF v_location IS NULL THEN
  SELECT id INTO v_location FROM public.locations
  WHERE branch_id=public.default_branch_id() AND kind='shop_floor' AND active ORDER BY created_at LIMIT 1;
 END IF;

 FOR v_row IN SELECT * FROM jsonb_array_elements(p->'variants') LOOP
  v_variant_id := NULLIF(v_row->>'variant_id','')::uuid;
  v_is_new := v_variant_id IS NULL;
  v_barcode := NULLIF(trim(COALESCE(v_row->>'barcode','')),'');
  IF NULLIF(trim(COALESCE(v_row->>'sku','')),'') IS NULL THEN RAISE EXCEPTION 'Every row needs a SKU'; END IF;
  IF COALESCE(NULLIF(v_row->>'price','')::numeric,-1)<0 THEN RAISE EXCEPTION 'Enter a valid price for %',v_row->>'sku'; END IF;
  IF v_row ? 'compare_at_price' AND v_row->'compare_at_price'<>'null'::jsonb
   AND ((v_row->>'compare_at_price')::numeric NOT BETWEEN 0 AND 999999999999.99 OR (v_row->>'compare_at_price')::numeric<>round((v_row->>'compare_at_price')::numeric,2)) THEN
   RAISE EXCEPTION 'Compare-at price must be a non-negative amount with up to two decimals'; END IF;
  v_key := lower(COALESCE(trim(v_row->>'size'),'')||'|'||COALESCE(trim(v_row->>'color'),'')||'|'||COALESCE(trim(v_row->>'fit'),''));
  IF v_key=ANY(v_seen) THEN RAISE EXCEPTION 'The same size and color is listed twice (%)',v_row->>'sku'; END IF;
  v_seen := v_seen||v_key;
  IF v_is_new THEN
   INSERT INTO public.product_variants(style_id,sku,size,color,fit,price,compare_at_price,min_stock,active)
   VALUES(v_style_id,upper(trim(v_row->>'sku')),NULLIF(trim(v_row->>'size'),''),
    NULLIF(trim(v_row->>'color'),''),NULLIF(trim(v_row->>'fit'),''),
    (v_row->>'price')::numeric,(v_row->>'compare_at_price')::numeric,COALESCE(NULLIF(v_row->>'min_stock','')::numeric,0),
    COALESCE((v_row->>'active')::boolean,true))
   RETURNING id INTO v_variant_id;
  ELSE
   UPDATE public.product_variants SET
    sku=upper(trim(v_row->>'sku')),size=NULLIF(trim(v_row->>'size'),''),
    color=NULLIF(trim(v_row->>'color'),''),fit=NULLIF(trim(v_row->>'fit'),''),
    price=(v_row->>'price')::numeric,
    compare_at_price=CASE WHEN v_row ? 'compare_at_price' THEN (v_row->>'compare_at_price')::numeric ELSE compare_at_price END,
    min_stock=COALESCE(NULLIF(v_row->>'min_stock','')::numeric,0),active=COALESCE((v_row->>'active')::boolean,true)
   WHERE id=v_variant_id AND style_id=v_style_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Variant % does not belong to this style',v_variant_id; END IF;
  END IF;
  IF NULLIF(v_row->>'cost','') IS NOT NULL THEN
   INSERT INTO public.variant_costs(variant_id,unit_cost) VALUES(v_variant_id,(v_row->>'cost')::numeric)
   ON CONFLICT (variant_id) DO UPDATE SET unit_cost=EXCLUDED.unit_cost;
  END IF;
  IF v_barcode IS NOT NULL THEN
   IF EXISTS(SELECT 1 FROM public.barcodes WHERE code=v_barcode AND variant_id<>v_variant_id) THEN
    RAISE EXCEPTION 'Barcode % is already used by another item',v_barcode; END IF;
   DELETE FROM public.barcodes WHERE variant_id=v_variant_id AND code<>v_barcode;
   INSERT INTO public.barcodes(code,variant_id) VALUES(v_barcode,v_variant_id) ON CONFLICT (code) DO NOTHING;
  ELSIF v_row ? 'barcode' THEN
   DELETE FROM public.barcodes WHERE variant_id=v_variant_id;
  END IF;
  v_opening := COALESCE(NULLIF(v_row->>'opening_stock','')::numeric,0);
  IF v_is_new AND v_track AND v_opening>0 THEN
   PERFORM public.adjust_stock(v_variant_id,v_location,v_opening,'Opening stock','opening',NULL);
  END IF;
 END LOOP;
 RETURN v_style_id;
END $$;


ALTER FUNCTION "public"."save_style"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_style_web_details"("p_style" "uuid", "p" "jsonb", "p_request_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE v_existing JSONB; s public.product_styles; k TEXT; r JSONB; v_slug TEXT; v_other TEXT; v_result JSONB;
BEGIN
 IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
  RAISE EXCEPTION 'Only managers can save website details' USING ERRCODE='42501'; END IF;
 IF p_request_id IS NULL THEN RAISE EXCEPTION 'request_id is required'; END IF;
 v_existing:=public.idempotency_begin(p_request_id,'save_style_web_details');
 IF v_existing IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=p_request_id AND user_id=auth.uid())
    OR v_existing->>'style_id' IS DISTINCT FROM p_style::text THEN
   RAISE EXCEPTION 'Request id belongs to another website update' USING ERRCODE='42501'; END IF;
  RETURN v_existing;
 END IF;
 SELECT * INTO s FROM public.product_styles WHERE id=p_style FOR UPDATE;
 IF s.id IS NULL THEN RAISE EXCEPTION 'Style not found'; END IF;
 IF jsonb_typeof(p) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Send website details as an object'; END IF;
 FOR k IN SELECT jsonb_object_keys(p) LOOP
  IF k NOT IN ('slug','web_title','web_description','variants') THEN RAISE EXCEPTION 'Unknown website detail: %',k; END IF;
 END LOOP;
 IF p ? 'slug' THEN
  v_slug:=p->>'slug';
  IF v_slug IS NOT NULL AND (jsonb_typeof(p->'slug')<>'string' OR length(v_slug)>120 OR v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$') THEN
   RAISE EXCEPTION 'Use a web address of at most 120 lowercase letters, numbers and hyphens'; END IF;
  IF v_slug IS NULL AND s.published THEN RAISE EXCEPTION 'Unpublish before removing the web address'; END IF;
  IF v_slug IS NOT NULL THEN
   -- Serialise competing requests for this address before checking uniqueness.
   PERFORM pg_advisory_xact_lock(hashtextextended('web_slug:'||v_slug,0));
   SELECT name INTO v_other FROM public.product_styles WHERE slug=v_slug AND id<>p_style;
   IF FOUND THEN RAISE EXCEPTION 'This web address is already used by %',v_other; END IF;
  END IF;
 END IF;
 FOREACH k IN ARRAY ARRAY['web_title','web_description'] LOOP
  IF p ? k AND p->k<>'null'::jsonb AND jsonb_typeof(p->k)<>'string' THEN RAISE EXCEPTION '% must be text',k; END IF;
  IF length(p->>k)>(CASE WHEN k='web_title' THEN 150 ELSE 5000 END) THEN RAISE EXCEPTION '% is too long',k; END IF;
 END LOOP;
 IF p ? 'variants' THEN
  IF jsonb_typeof(p->'variants') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Send a list of variants'; END IF;
  FOR r IN SELECT * FROM jsonb_array_elements(p->'variants') LOOP
   IF jsonb_typeof(r) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Send a variant and its published flag'; END IF;
   FOR k IN SELECT jsonb_object_keys(r) LOOP
    IF k NOT IN ('variant_id','published') THEN RAISE EXCEPTION 'Unknown variant detail: %',k; END IF;
   END LOOP;
   IF jsonb_typeof(r->'published') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Choose Show online for each variant'; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.product_variants WHERE id=nullif(r->>'variant_id','')::uuid AND style_id=p_style) THEN
    RAISE EXCEPTION 'That variant does not belong to this style'; END IF;
  END LOOP;
  -- Lock variants in UUID order regardless of the order sent by the browser.
  PERFORM 1 FROM public.product_variants WHERE style_id=p_style ORDER BY id FOR UPDATE;
  FOR r IN SELECT * FROM jsonb_array_elements(p->'variants') LOOP
   UPDATE public.product_variants SET published=(r->>'published')::boolean WHERE id=(r->>'variant_id')::uuid AND style_id=p_style;
  END LOOP;
 END IF;
 UPDATE public.product_styles SET slug=CASE WHEN p ? 'slug' THEN v_slug ELSE slug END,
  web_title=CASE WHEN p ? 'web_title' THEN nullif(trim(p->>'web_title'),'') ELSE web_title END,
  web_description=CASE WHEN p ? 'web_description' THEN nullif(trim(p->>'web_description'),'') ELSE web_description END
 WHERE id=p_style RETURNING * INTO s;
 v_result:=jsonb_build_object('style_id',s.id,'slug',s.slug,'web_title',s.web_title,'web_description',s.web_description,
  'variants',(SELECT coalesce(jsonb_agg(jsonb_build_object('variant_id',id,'published',published) ORDER BY id),'[]'::jsonb) FROM public.product_variants WHERE style_id=p_style));
 RETURN public.idempotency_finish(p_request_id,v_result);
END $_$;


ALTER FUNCTION "public"."save_style_web_details"("p_style" "uuid", "p" "jsonb", "p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_sales"("p" "jsonb" DEFAULT '{}'::"jsonb") RETURNS TABLE("id" "uuid", "invoice_number" "text", "created_at" timestamp with time zone, "status" "text", "customer_id" "uuid", "customer_name" "text", "cashier_name" "text", "total" numeric, "paid_methods" "text"[], "returned_amount" numeric, "line_count" integer, "total_count" bigint)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE
    v_from DATE := NULLIF(p->>'from', '')::date;
    v_to DATE := NULLIF(p->>'to', '')::date;
    v_status TEXT := NULLIF(p->>'status', '');
    v_method TEXT := NULLIF(p->>'method', '');
    -- Treat search text literally, including %, _ and backslash.
    v_q TEXT := replace(replace(replace(trim(coalesce(p->>'q', '')), E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_');
    v_phone TEXT := regexp_replace(coalesce(p->>'q', ''), '[^0-9]', '', 'g');
    v_limit INT := least(200, greatest(1, coalesce((p->>'limit')::int, 50)));
    v_offset INT := greatest(0, coalesce((p->>'offset')::int, 0));
BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;

    IF NOT public.is_counter_staff() THEN RETURN; END IF;
    IF v_status IS NOT NULL AND v_status NOT IN ('completed','credit','draft','returned','refunded') THEN
        RAISE EXCEPTION 'Choose a valid sale status' USING ERRCODE = '22023';
    END IF;
    IF v_method IS NOT NULL AND v_method NOT IN ('cash','card','digital','credit','exchange') THEN
        RAISE EXCEPTION 'Choose a valid payment method' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY
    SELECT s.id, s.invoice_number, s.created_at, s.status, s.customer_id,
        coalesce(s.customer_name, c.name), coalesce(s.cashier, u.name), s.total,
        ARRAY(SELECT DISTINCT pay.method FROM public.payments pay WHERE pay.sale_id = s.id ORDER BY pay.method),
        coalesce((SELECT sum(r.refund_total) FROM public.returns r WHERE r.sale_id = s.id), 0),
        (SELECT count(*)::int FROM public.sale_lines l WHERE l.sale_id = s.id), count(*) OVER ()
    FROM public.sales s
    LEFT JOIN public.customers c ON c.id = s.customer_id
    LEFT JOIN public.users u ON u.id = s.cashier_id
    WHERE public.is_branch_member(s.branch_id)
      AND (public.has_app_role(ARRAY['admin','manager']) OR s.cashier_id = auth.uid())
      AND (v_from IS NULL OR s.created_at >= (v_from::timestamp AT TIME ZONE public.report_tz()))
      AND (v_to IS NULL OR s.created_at < ((v_to + 1)::timestamp AT TIME ZONE public.report_tz()))
      AND (v_status IS NULL OR s.status = v_status OR (v_status = 'returned' AND EXISTS (
          SELECT 1 FROM public.returns r WHERE r.sale_id = s.id)))
      AND (v_method IS NULL OR EXISTS (SELECT 1 FROM public.payments pay WHERE pay.sale_id = s.id AND pay.method = v_method))
      AND (v_q = '' OR s.invoice_number ILIKE v_q || '%' OR c.name ILIKE '%' || v_q || '%'
          OR s.customer_name ILIKE '%' || v_q || '%' OR c.phone ILIKE '%' || v_q || '%'
          -- Also accept local 03xx and formatted +92 phone searches.
          OR (coalesce(p->>'q', '') ~ '^[+0-9() .-]+$' AND length(v_phone) >= 4 AND (c.phone LIKE '%' || v_phone || '%'
              OR (left(v_phone, 1) = '0' AND c.phone LIKE '%' || substr(v_phone, 2) || '%')))
          OR EXISTS (SELECT 1 FROM public.sale_lines l WHERE l.sale_id = s.id AND l.sku ILIKE '%' || v_q || '%'))
    ORDER BY s.created_at DESC, s.id
    LIMIT v_limit OFFSET v_offset;
END;
$_$;


ALTER FUNCTION "public"."search_sales"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_variants"("p" "jsonb" DEFAULT '{}'::"jsonb") RETURNS TABLE("variant_id" "uuid", "style_id" "uuid", "sku" "text", "name" "text", "size" "text", "color" "text", "kind" "text", "unit" "text", "category" "text", "price" numeric, "taxable" boolean, "available" numeric, "on_hand" numeric, "barcodes" "text"[], "total_count" bigint, "fit" "text", "min_stock" numeric, "active" boolean, "track_inventory" boolean, "image" "text", "description" "text", "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "barcode" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
 v_q TEXT := trim(coalesce(p->>'q',''));
 v_literal TEXT := replace(replace(replace(v_q, E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_');
 v_location UUID;
 v_active BOOLEAN;
 v_limit INT;
 v_offset INT;
BEGIN
 IF NOT public.is_counter_staff() THEN
  RAISE EXCEPTION 'Only counter staff can search products' USING ERRCODE='42501';
 END IF;
 v_location := nullif(p->>'location_id','')::uuid;
 v_active := coalesce((p->>'active_only')::boolean,true);
 v_limit := least(200,greatest(1,coalesce((p->>'limit')::int,60)));
 v_offset := greatest(0,coalesce((p->>'offset')::int,0));
 -- Mirror getSellingLocationId: first active shop floor, ordered by creation.
 IF v_location IS NULL THEN
  SELECT l.id INTO v_location FROM public.locations l WHERE l.kind='shop_floor' AND l.active ORDER BY l.created_at, l.id LIMIT 1;
 END IF;
 IF v_location IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.locations l WHERE l.id=v_location AND public.is_branch_member(l.branch_id)) THEN
  RAISE EXCEPTION 'Choose a location in your branch' USING ERRCODE='42501';
 END IF;
 RETURN QUERY
 SELECT v.id,s.id,v.sku,s.name,v.size,v.color,s.kind,s.unit,coalesce(c.name,''),v.price,s.taxable,
  coalesce(b.on_hand-b.reserved,0),coalesce(b.on_hand,0),
  ARRAY(SELECT bc.code FROM public.barcodes bc WHERE bc.variant_id=v.id ORDER BY bc.code),
  count(*) OVER(),v.fit,v.min_stock,(v.active AND s.active),s.track_inventory,s.image_url,coalesce(s.description,''),v.created_at,v.updated_at,
  (SELECT bc.code FROM public.barcodes bc WHERE bc.variant_id=v.id ORDER BY bc.code LIMIT 1)
 FROM public.product_variants v
 JOIN public.product_styles s ON s.id=v.style_id
 LEFT JOIN public.categories c ON c.id=s.category_id
 LEFT JOIN public.stock_balances b ON b.variant_id=v.id AND b.location_id=v_location
 WHERE (NOT v_active OR (v.active AND s.active))
  AND (nullif(p->>'kind','') IS NULL OR s.kind=p->>'kind')
  AND (nullif(p->>'category','') IS NULL OR c.name=p->>'category')
  AND (jsonb_typeof(p->'categories') IS DISTINCT FROM 'array'
    OR c.name IN (SELECT jsonb_array_elements_text(p->'categories')))
  AND (v_q='' OR lower(v.sku)=lower(v_q)
    OR EXISTS(SELECT 1 FROM public.barcodes bc WHERE bc.variant_id=v.id AND lower(bc.code)=lower(v_q))
    OR s.name ILIKE '%'||v_literal||'%' OR v.sku ILIKE '%'||v_literal||'%')
 ORDER BY CASE WHEN v_q<>'' AND (lower(v.sku)=lower(v_q) OR EXISTS(SELECT 1 FROM public.barcodes bc WHERE bc.variant_id=v.id AND lower(bc.code)=lower(v_q))) THEN 0 ELSE 1 END,
  CASE WHEN p->>'sort'='updated' THEN greatest(s.updated_at,v.updated_at) END DESC NULLS LAST,
  CASE WHEN p->>'sort'='newest' THEN v.created_at END DESC NULLS LAST,
  s.name,v.sku,v.id
 LIMIT v_limit OFFSET v_offset;
END $$;


ALTER FUNCTION "public"."search_variants"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_collection_styles"("p_collection" "uuid", "p_style_ids" "uuid"[], "p_request_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_existing JSONB;
BEGIN
 IF NOT public.has_app_role(ARRAY['admin','manager']) THEN RAISE EXCEPTION 'Only managers can set collection styles' USING ERRCODE='42501'; END IF;
 IF p_request_id IS NULL THEN RAISE EXCEPTION 'request_id is required'; END IF;
 v_existing:=public.idempotency_begin(p_request_id,'set_collection_styles');
 IF v_existing IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=p_request_id AND user_id=auth.uid())
   OR v_existing->>'collection_id' IS DISTINCT FROM p_collection::text THEN RAISE EXCEPTION 'Request id belongs to another collection update' USING ERRCODE='42501'; END IF;
  RETURN v_existing;
 END IF;
 PERFORM 1 FROM public.collections WHERE id=p_collection FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Collection not found'; END IF;
 IF p_style_ids IS NULL OR EXISTS(SELECT 1 FROM unnest(p_style_ids) x WHERE x IS NULL OR NOT EXISTS(SELECT 1 FROM public.product_styles WHERE id=x)) THEN RAISE EXCEPTION 'Choose existing styles'; END IF;
 IF cardinality(p_style_ids)<>(SELECT count(DISTINCT x) FROM unnest(p_style_ids) x) THEN RAISE EXCEPTION 'A style can appear only once in a collection'; END IF;
 DELETE FROM public.collection_styles WHERE collection_id=p_collection;
 INSERT INTO public.collection_styles(collection_id,style_id,sort_order)
  SELECT p_collection,id,(n-1)::int FROM unnest(p_style_ids) WITH ORDINALITY AS s(id,n);
 RETURN public.idempotency_finish(p_request_id,jsonb_build_object('collection_id',p_collection,'style_ids',to_jsonb(p_style_ids)));
END; $$;


ALTER FUNCTION "public"."set_collection_styles"("p_collection" "uuid", "p_style_ids" "uuid"[], "p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staff_link_customer_account"("p_account" "uuid", "p_customer" "uuid", "p_request_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE r JSONB; a public.customer_accounts;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 r:=public.request_begin(p_request_id,'staff_link_customer_account'); IF r IS NOT NULL THEN RETURN r; END IF;
 SELECT * INTO a FROM public.customer_accounts WHERE id=p_account FOR UPDATE;
 IF a.id IS NULL OR EXISTS(SELECT 1 FROM public.users WHERE id=p_account) THEN RAISE EXCEPTION 'Choose a customer account'; END IF;
 PERFORM 1 FROM public.customers WHERE id=p_customer FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;
 IF (a.customer_id IS NOT NULL AND a.customer_id<>p_customer) OR EXISTS(SELECT 1 FROM public.customer_accounts WHERE customer_id=p_customer AND id<>p_account) THEN
  RAISE EXCEPTION 'This account or customer is already linked elsewhere';
 END IF;
 UPDATE public.customer_accounts SET customer_id=p_customer,phone_verified=true WHERE id=p_account;
 RETURN public.idempotency_finish(p_request_id,jsonb_build_object('status','linked'));
END $$;


ALTER FUNCTION "public"."staff_link_customer_account"("p_account" "uuid", "p_customer" "uuid", "p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staff_return_request"("p_order_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE r public.online_return_requests;
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.online_orders WHERE id=p_order_id AND public.is_branch_member(branch_id)) THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF;
 SELECT * INTO r FROM public.online_return_requests WHERE order_id=p_order_id;
 IF r.id IS NULL THEN RETURN NULL; END IF;
 RETURN app_private.return_request_json(r.id)||jsonb_build_object('staff_note',r.staff_note);
END $$;


ALTER FUNCTION "public"."staff_return_request"("p_order_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_stock_count"("p_location_id" "uuid" DEFAULT NULL::"uuid", "p_notes" "text" DEFAULT NULL::"text") RETURNS "public"."stock_counts"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_location UUID := p_location_id;
    v_branch UUID;
    v_count public.stock_counts;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can start a stock count' USING ERRCODE = '42501';
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
    IF EXISTS (SELECT 1 FROM public.stock_counts WHERE location_id = v_location AND status = 'open') THEN
        RAISE EXCEPTION 'A count is already open for this location';
    END IF;

    INSERT INTO public.stock_counts (count_no, branch_id, location_id, notes)
    VALUES ('CNT-' || lpad(nextval('public.stock_count_no_seq')::text, 6, '0'), v_branch, v_location,
            NULLIF(trim(p_notes), ''))
    RETURNING * INTO v_count;
    RETURN v_count;
END;
$$;


ALTER FUNCTION "public"."start_stock_count"("p_location_id" "uuid", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_customer_stats"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NEW.customer_id IS NOT NULL AND NEW.status IN ('completed', 'credit') THEN
        UPDATE public.customers
        SET total_purchases = COALESCE(total_purchases, 0) + NEW.total,
            last_purchase = NEW.created_at
        WHERE id = NEW.customer_id;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_customer_stats"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_online_tracking"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."update_online_tracking"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_settings"("p" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE v_old public.app_settings; v_new public.app_settings; v_key TEXT; v_max INT;
 v_request UUID; v_existing JSONB;
 v_keys TEXT[]:=ARRAY['store_name','store_address','store_phone','store_email','store_logo','tax_rate','currency','interface_mode','auto_backup','receipt_printer','theme','invoice_prefix','invoice_counter','max_cashier_discount_percent','return_window_days','cash_variance_alert','receipt_header','receipt_footer','ntn','strn','online_hold_minutes','delivery_fee','free_delivery_over','cod_enabled','online_card_enabled','cod_max_total','online_max_pending_orders','online_max_open_cod_orders','bulky_delivery_fee','assembly_fee'];
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
   IF v_key IN ('free_delivery_over','cod_max_total','assembly_fee') AND p->v_key='null'::jsonb THEN CONTINUE; END IF;
   IF v_key IN ('tax_rate','max_cashier_discount_percent','return_window_days','cash_variance_alert','invoice_counter','online_hold_minutes','delivery_fee','free_delivery_over','cod_max_total','online_max_pending_orders','online_max_open_cod_orders','bulky_delivery_fee','assembly_fee') THEN
     IF jsonb_typeof(p->v_key) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Enter a number for %',v_key; END IF;
   ELSIF v_key IN ('auto_backup','receipt_printer','cod_enabled','online_card_enabled') THEN
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
 IF p ? 'return_window_days' AND ((p->>'return_window_days')::numeric NOT BETWEEN 0 AND 365 OR (p->>'return_window_days')::numeric<>trunc((p->>'return_window_days')::numeric)) THEN RAISE EXCEPTION 'Return window must be a whole number from 0 to 365 days'; END IF;
 IF p ? 'cash_variance_alert' AND (p->>'cash_variance_alert')::numeric<0 THEN RAISE EXCEPTION 'Cash difference alert must be zero or more'; END IF;
 IF p ? 'invoice_counter' AND ((p->>'invoice_counter')::numeric<0 OR (p->>'invoice_counter')::numeric<>trunc((p->>'invoice_counter')::numeric)) THEN RAISE EXCEPTION 'Invoice preview counter must be a whole number of zero or more'; END IF;
 IF p ? 'store_name' AND coalesce(trim(p->>'store_name'),'')='' THEN RAISE EXCEPTION 'Enter the store name'; END IF;
 IF p ? 'currency' AND coalesce(p->>'currency','') !~ '^[A-Z]{3}$' THEN RAISE EXCEPTION 'Enter a three-letter currency code'; END IF;
 IF p ? 'interface_mode' AND coalesce(p->>'interface_mode','') NOT IN ('touch','traditional') THEN RAISE EXCEPTION 'Choose touch or traditional layout'; END IF;
 IF p ? 'theme' AND coalesce(p->>'theme','') NOT IN ('light','dark','auto') THEN RAISE EXCEPTION 'Choose a valid theme'; END IF;
 FOR v_key IN SELECT unnest(ARRAY['online_max_pending_orders','online_max_open_cod_orders']) LOOP
  IF p ? v_key AND ((p->>v_key)::numeric NOT BETWEEN 1 AND 50 OR (p->>v_key)::numeric<>trunc((p->>v_key)::numeric)) THEN
   RAISE EXCEPTION 'Online order limits must be whole numbers from 1 to 50';
  END IF;
 END LOOP;
 IF p ? 'online_hold_minutes' AND ((p->>'online_hold_minutes')::numeric NOT BETWEEN 1 AND 1440 OR (p->>'online_hold_minutes')::numeric<>trunc((p->>'online_hold_minutes')::numeric)) THEN RAISE EXCEPTION 'Online hold must be a whole number from 1 to 1440 minutes'; END IF;
 FOR v_key IN SELECT unnest(ARRAY['delivery_fee','free_delivery_over','cod_max_total','bulky_delivery_fee','assembly_fee']) LOOP
  IF p ? v_key AND p->v_key<>'null'::jsonb AND ((p->>v_key)::numeric<0 OR (p->>v_key)::numeric<>round((p->>v_key)::numeric,2)) THEN RAISE EXCEPTION 'Enter a non-negative amount with up to two decimals for %',v_key; END IF;
 END LOOP;
 SELECT * INTO v_old FROM public.app_settings ORDER BY created_at,id LIMIT 1 FOR UPDATE;
 IF v_old.id IS NULL THEN RAISE EXCEPTION 'Store settings not found'; END IF;
 v_new:=jsonb_populate_record(v_old,p-'request_id');
 UPDATE public.app_settings SET store_name=v_new.store_name,store_address=v_new.store_address,store_phone=v_new.store_phone,
   store_email=v_new.store_email,store_logo=v_new.store_logo,tax_rate=v_new.tax_rate,currency=v_new.currency,interface_mode=v_new.interface_mode,
   auto_backup=v_new.auto_backup,receipt_printer=v_new.receipt_printer,theme=v_new.theme,invoice_prefix=v_new.invoice_prefix,invoice_counter=v_new.invoice_counter,
   max_cashier_discount_percent=v_new.max_cashier_discount_percent,return_window_days=v_new.return_window_days,cash_variance_alert=v_new.cash_variance_alert,
   receipt_header=v_new.receipt_header,receipt_footer=v_new.receipt_footer,ntn=v_new.ntn,strn=v_new.strn,online_hold_minutes=v_new.online_hold_minutes,
   delivery_fee=v_new.delivery_fee,free_delivery_over=v_new.free_delivery_over,cod_enabled=v_new.cod_enabled,online_card_enabled=v_new.online_card_enabled,
   cod_max_total=v_new.cod_max_total,online_max_pending_orders=v_new.online_max_pending_orders,online_max_open_cod_orders=v_new.online_max_open_cod_orders,
   bulky_delivery_fee=v_new.bulky_delivery_fee,assembly_fee=v_new.assembly_fee
 WHERE id=v_old.id RETURNING * INTO v_new;
 INSERT INTO public.settings_history(old,new) VALUES(to_jsonb(v_old),to_jsonb(v_new));
 RETURN public.idempotency_finish(v_request,to_jsonb(v_new));
END $_$;


ALTER FUNCTION "public"."update_settings"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."variant_by_code"("p_code" "text", "p_location" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("variant_id" "uuid", "style_id" "uuid", "sku" "text", "name" "text", "size" "text", "color" "text", "kind" "text", "unit" "text", "category" "text", "price" numeric, "taxable" boolean, "available" numeric, "on_hand" numeric, "barcodes" "text"[], "total_count" bigint, "fit" "text", "min_stock" numeric, "active" boolean, "track_inventory" boolean, "image" "text", "description" "text", "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "barcode" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_location UUID := p_location;
BEGIN
 IF NOT public.is_counter_staff() THEN
  RAISE EXCEPTION 'Only counter staff can look up products' USING ERRCODE='42501';
 END IF;
 IF v_location IS NULL THEN
  SELECT l.id INTO v_location FROM public.locations l WHERE l.kind='shop_floor' AND l.active ORDER BY l.created_at,l.id LIMIT 1;
 END IF;
 IF v_location IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.locations l WHERE l.id=v_location AND public.is_branch_member(l.branch_id)) THEN
  RAISE EXCEPTION 'Choose a location in your branch' USING ERRCODE='42501';
 END IF;
 IF nullif(trim(p_code),'') IS NULL THEN RETURN; END IF;
 RETURN QUERY
 WITH matches AS (
  SELECT v.id FROM public.product_variants v WHERE lower(v.sku)=lower(trim(p_code))
  UNION
  SELECT bc.variant_id FROM public.barcodes bc WHERE lower(bc.code)=lower(trim(p_code))
 )
 SELECT v.id,s.id,v.sku,s.name,v.size,v.color,s.kind,s.unit,coalesce(c.name,''),v.price,s.taxable,
  coalesce(b.on_hand-b.reserved,0),coalesce(b.on_hand,0),
  ARRAY(SELECT bc.code FROM public.barcodes bc WHERE bc.variant_id=v.id ORDER BY bc.code),
  1::bigint,v.fit,v.min_stock,(v.active AND s.active),s.track_inventory,s.image_url,coalesce(s.description,''),v.created_at,v.updated_at,
  (SELECT bc.code FROM public.barcodes bc WHERE bc.variant_id=v.id ORDER BY bc.code LIMIT 1)
 FROM matches m JOIN public.product_variants v ON v.id=m.id
 JOIN public.product_styles s ON s.id=v.style_id
 LEFT JOIN public.categories c ON c.id=s.category_id
 LEFT JOIN public.stock_balances b ON b.variant_id=v.id AND b.location_id=v_location
 WHERE v.active AND s.active
 ORDER BY s.name,v.sku,v.id LIMIT 1;
END $$;


ALTER FUNCTION "public"."variant_by_code"("p_code" "text", "p_location" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."app_settings" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "store_name" "text" DEFAULT 'Bicycles.pk'::"text",
    "store_address" "text",
    "store_phone" "text",
    "store_email" "text",
    "store_logo" "text",
    "tax_rate" numeric(6,3) DEFAULT 0,
    "currency" "text" DEFAULT 'PKR'::"text",
    "interface_mode" "text" DEFAULT 'touch'::"text",
    "auto_backup" boolean DEFAULT true,
    "receipt_printer" boolean DEFAULT false,
    "theme" "text" DEFAULT 'light'::"text",
    "invoice_prefix" "text" DEFAULT 'INV'::"text",
    "invoice_counter" integer DEFAULT 1000,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "max_cashier_discount_percent" numeric(5,2) DEFAULT 10 NOT NULL,
    "return_window_days" integer DEFAULT 7 NOT NULL,
    "cash_variance_alert" numeric(14,2) DEFAULT 500 NOT NULL,
    "receipt_header" "text",
    "receipt_footer" "text",
    "ntn" "text",
    "strn" "text",
    "online_hold_minutes" integer DEFAULT 30 NOT NULL,
    "delivery_fee" numeric(14,2) DEFAULT 250 NOT NULL,
    "free_delivery_over" numeric(14,2),
    "cod_enabled" boolean DEFAULT true NOT NULL,
    "cod_max_total" numeric(14,2),
    "online_max_pending_orders" integer DEFAULT 3 NOT NULL,
    "online_max_open_cod_orders" integer DEFAULT 3 NOT NULL,
    "online_card_enabled" boolean DEFAULT false NOT NULL,
    "bulky_delivery_fee" numeric(14,2) DEFAULT 0 NOT NULL,
    "assembly_fee" numeric(14,2),
    CONSTRAINT "app_settings_assembly_fee_check" CHECK (("assembly_fee" >= (0)::numeric)),
    CONSTRAINT "app_settings_bulky_delivery_fee_check" CHECK (("bulky_delivery_fee" >= (0)::numeric)),
    CONSTRAINT "app_settings_cash_variance_alert_check" CHECK (("cash_variance_alert" >= (0)::numeric)),
    CONSTRAINT "app_settings_cod_max_total_check" CHECK (("cod_max_total" >= (0)::numeric)),
    CONSTRAINT "app_settings_delivery_fee_check" CHECK (("delivery_fee" >= (0)::numeric)),
    CONSTRAINT "app_settings_free_delivery_over_check" CHECK (("free_delivery_over" >= (0)::numeric)),
    CONSTRAINT "app_settings_interface_mode_check" CHECK (("interface_mode" = ANY (ARRAY['touch'::"text", 'traditional'::"text"]))),
    CONSTRAINT "app_settings_max_cashier_discount_percent_check" CHECK ((("max_cashier_discount_percent" >= (0)::numeric) AND ("max_cashier_discount_percent" <= (100)::numeric))),
    CONSTRAINT "app_settings_ntn_check" CHECK (("length"("ntn") <= 100)),
    CONSTRAINT "app_settings_online_hold_minutes_check" CHECK ((("online_hold_minutes" >= 1) AND ("online_hold_minutes" <= 1440))),
    CONSTRAINT "app_settings_online_max_open_cod_orders_check" CHECK ((("online_max_open_cod_orders" >= 1) AND ("online_max_open_cod_orders" <= 50))),
    CONSTRAINT "app_settings_online_max_pending_orders_check" CHECK ((("online_max_pending_orders" >= 1) AND ("online_max_pending_orders" <= 50))),
    CONSTRAINT "app_settings_receipt_footer_check" CHECK (("length"("receipt_footer") <= 500)),
    CONSTRAINT "app_settings_receipt_header_check" CHECK (("length"("receipt_header") <= 500)),
    CONSTRAINT "app_settings_return_window_days_check" CHECK (("return_window_days" >= 0)),
    CONSTRAINT "app_settings_strn_check" CHECK (("length"("strn") <= 100)),
    CONSTRAINT "app_settings_theme_check" CHECK (("theme" = ANY (ARRAY['light'::"text", 'dark'::"text", 'auto'::"text"])))
);


ALTER TABLE "public"."app_settings" OWNER TO "postgres";


COMMENT ON COLUMN "public"."app_settings"."assembly_fee" IS 'Per bulky unit on courier orders; NULL means assembly is not offered.';



CREATE TABLE IF NOT EXISTS "public"."barcodes" (
    "code" "text" NOT NULL,
    "variant_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "barcodes_code_check" CHECK ((("length"(TRIM(BOTH FROM "code")) > 0) AND ("code" = TRIM(BOTH FROM "code"))))
);


ALTER TABLE "public"."barcodes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."branch_memberships" (
    "user_id" "uuid" NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."branch_memberships" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."branches" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "address" "text",
    "phone" "text",
    "timezone" "text" DEFAULT 'Asia/Karachi'::"text" NOT NULL,
    "currency" "text" DEFAULT 'PKR'::"text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."branches" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."business_lookups" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "kind" "text" NOT NULL,
    "value" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    CONSTRAINT "business_lookups_kind_check" CHECK (("kind" = ANY (ARRAY['brand'::"text", 'material'::"text", 'season'::"text", 'color'::"text", 'fit'::"text", 'bank'::"text", 'return_reason'::"text", 'stock_reason'::"text", 'customer_tier'::"text"]))),
    CONSTRAINT "business_lookups_value_check" CHECK ((("length"(TRIM(BOTH FROM "value")) >= 1) AND ("length"(TRIM(BOTH FROM "value")) <= 200)))
);


ALTER TABLE "public"."business_lookups" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cash_movements" (
    "id" bigint NOT NULL,
    "session_id" "uuid" NOT NULL,
    "amount" numeric(14,2) NOT NULL,
    "movement_type" "text" NOT NULL,
    "payment_id" "uuid",
    "reason" "text",
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "cash_movements_amount_check" CHECK (("amount" <> (0)::numeric)),
    CONSTRAINT "cash_movements_movement_type_check" CHECK (("movement_type" = ANY (ARRAY['sale'::"text", 'refund'::"text", 'cash_in'::"text", 'cash_out'::"text"])))
);


ALTER TABLE "public"."cash_movements" OWNER TO "postgres";


ALTER TABLE "public"."cash_movements" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."cash_movements_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE SEQUENCE IF NOT EXISTS "public"."cash_session_no_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."cash_session_no_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cash_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "session_no" "text" NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "location_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "opening_float" numeric(14,2) NOT NULL,
    "opened_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expected_cash" numeric(14,2),
    "counted_cash" numeric(14,2),
    "variance" numeric(14,2),
    "closing_notes" "text",
    "closed_by" "uuid",
    "closed_at" timestamp with time zone,
    CONSTRAINT "cash_sessions_counted_cash_check" CHECK ((("counted_cash" IS NULL) OR ("counted_cash" >= (0)::numeric))),
    CONSTRAINT "cash_sessions_opening_float_check" CHECK (("opening_float" >= (0)::numeric)),
    CONSTRAINT "cash_sessions_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'closed'::"text"])))
);


ALTER TABLE "public"."cash_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."categories" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."collection_styles" (
    "collection_id" "uuid" NOT NULL,
    "style_id" "uuid" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."collection_styles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."collections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "hero_image_path" "text",
    "published" boolean DEFAULT false NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "starts_at" timestamp with time zone,
    "ends_at" timestamp with time zone,
    CONSTRAINT "collections_check" CHECK ((("ends_at" IS NULL) OR ("starts_at" IS NULL) OR ("ends_at" > "starts_at"))),
    CONSTRAINT "collections_name_check" CHECK (("length"(TRIM(BOTH FROM "name")) > 0)),
    CONSTRAINT "collections_slug_check" CHECK (("slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::"text"))
);


ALTER TABLE "public"."collections" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."commission_entries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "amount" numeric(14,2) NOT NULL,
    "sale_id" "uuid",
    "return_line_id" "uuid",
    "request_id" "uuid",
    "note" "text",
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "commission_entries_amount_check" CHECK ((("amount")::"text" <> ALL (ARRAY['NaN'::"text", 'Infinity'::"text", '-Infinity'::"text"]))),
    CONSTRAINT "commission_entries_check" CHECK (((("kind" = 'earned'::"text") AND ("amount" > (0)::numeric) AND ("sale_id" IS NOT NULL) AND ("return_line_id" IS NULL) AND ("request_id" IS NULL)) OR (("kind" = 'return'::"text") AND ("amount" < (0)::numeric) AND ("sale_id" IS NOT NULL) AND ("return_line_id" IS NOT NULL) AND ("request_id" IS NULL)) OR (("kind" = 'payout'::"text") AND ("amount" < (0)::numeric) AND ("sale_id" IS NULL) AND ("return_line_id" IS NULL) AND ("request_id" IS NOT NULL)))),
    CONSTRAINT "commission_entries_kind_check" CHECK (("kind" = ANY (ARRAY['earned'::"text", 'return'::"text", 'payout'::"text"])))
);


ALTER TABLE "public"."commission_entries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."commission_rules" (
    "branch_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "rate" numeric(14,2) NOT NULL,
    "enabled" boolean DEFAULT false NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    CONSTRAINT "commission_rules_check" CHECK ((("kind" <> 'percentage'::"text") OR ("rate" <= (100)::numeric))),
    CONSTRAINT "commission_rules_check1" CHECK (((NOT "enabled") OR ("rate" > (0)::numeric))),
    CONSTRAINT "commission_rules_kind_check" CHECK (("kind" = ANY (ARRAY['fixed'::"text", 'percentage'::"text"]))),
    CONSTRAINT "commission_rules_rate_check" CHECK ((("rate" >= (0)::numeric) AND (("rate")::"text" <> ALL (ARRAY['NaN'::"text", 'Infinity'::"text", '-Infinity'::"text"]))))
);


ALTER TABLE "public"."commission_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."courier_returns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "return_id" "uuid" NOT NULL,
    "reason" "text" NOT NULL,
    "courier_cost" numeric(14,2) NOT NULL,
    "created_by" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "courier_returns_courier_cost_check" CHECK (("courier_cost" >= (0)::numeric)),
    CONSTRAINT "courier_returns_reason_check" CHECK ((("length"(TRIM(BOTH FROM "reason")) >= 1) AND ("length"(TRIM(BOTH FROM "reason")) <= 1000)))
);


ALTER TABLE "public"."courier_returns" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_accounts" (
    "id" "uuid" NOT NULL,
    "customer_id" "uuid",
    "full_name" "text",
    "email" "text",
    "phone" "text",
    "phone_verified" boolean DEFAULT false NOT NULL,
    "marketing_consent" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "email_marketing_consent" boolean,
    "sms_marketing_consent" boolean,
    "email_consent_at" timestamp with time zone,
    "sms_consent_at" timestamp with time zone
);


ALTER TABLE "public"."customer_accounts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_ledger" (
    "id" bigint NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "entry_type" "text" NOT NULL,
    "amount" numeric(14,2) NOT NULL,
    "sale_id" "uuid",
    "return_id" "uuid",
    "payment_id" "uuid",
    "note" "text",
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "customer_ledger_amount_check" CHECK (("amount" <> (0)::numeric)),
    CONSTRAINT "customer_ledger_entry_type_check" CHECK (("entry_type" = ANY (ARRAY['opening'::"text", 'sale_credit'::"text", 'return_credit'::"text", 'payment'::"text", 'adjustment'::"text"])))
);


ALTER TABLE "public"."customer_ledger" OWNER TO "postgres";


ALTER TABLE "public"."customer_ledger" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."customer_ledger_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE SEQUENCE IF NOT EXISTS "public"."customer_payment_no_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."customer_payment_no_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "payment_no" "text" NOT NULL,
    "request_id" "uuid" NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "total" numeric(14,2) NOT NULL,
    "note" "text",
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "customer_payments_total_check" CHECK (("total" > (0)::numeric))
);


ALTER TABLE "public"."customer_payments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customers" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "email" "text",
    "phone" "text",
    "address" "text",
    "credit_limit" numeric(10,2) DEFAULT 0.00,
    "credit_used" numeric(10,2) DEFAULT 0.00,
    "price_tier" "text" DEFAULT 'Standard'::"text",
    "total_purchases" numeric(12,2) DEFAULT 0.00,
    "last_purchase" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "email_marketing_consent" boolean,
    "sms_marketing_consent" boolean,
    "email_consent_at" timestamp with time zone,
    "sms_consent_at" timestamp with time zone
);


ALTER TABLE "public"."customers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."discount_code_redemptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code_id" "uuid",
    "code" "text" NOT NULL,
    "sale_id" "uuid" NOT NULL,
    "customer_id" "uuid",
    "amount" numeric(14,2) NOT NULL,
    "redeemed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "discount_code_redemptions_amount_check" CHECK (("amount" >= (0)::numeric))
);


ALTER TABLE "public"."discount_code_redemptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."discount_code_settings" (
    "id" boolean DEFAULT true NOT NULL,
    "welcome_enabled" boolean DEFAULT false NOT NULL,
    "welcome_type" "text" DEFAULT 'percentage'::"text" NOT NULL,
    "welcome_value" numeric(14,2) DEFAULT 10 NOT NULL,
    "welcome_valid_days" integer DEFAULT 30 NOT NULL,
    "welcome_min_amount" numeric(14,2),
    "welcome_max_discount" numeric(14,2),
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    CONSTRAINT "discount_code_settings_id_check" CHECK ("id"),
    CONSTRAINT "discount_code_settings_percent" CHECK ((("welcome_type" <> 'percentage'::"text") OR ("welcome_value" <= (100)::numeric))),
    CONSTRAINT "discount_code_settings_welcome_max_discount_check" CHECK (("welcome_max_discount" > (0)::numeric)),
    CONSTRAINT "discount_code_settings_welcome_min_amount_check" CHECK (("welcome_min_amount" >= (0)::numeric)),
    CONSTRAINT "discount_code_settings_welcome_type_check" CHECK (("welcome_type" = ANY (ARRAY['percentage'::"text", 'fixed'::"text"]))),
    CONSTRAINT "discount_code_settings_welcome_valid_days_check" CHECK ((("welcome_valid_days" >= 1) AND ("welcome_valid_days" <= 3650))),
    CONSTRAINT "discount_code_settings_welcome_value_check" CHECK (("welcome_value" > (0)::numeric))
);


ALTER TABLE "public"."discount_code_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."discounts" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "type" "text" NOT NULL,
    "value" numeric(10,2) DEFAULT 0,
    "conditions" "jsonb" DEFAULT '[]'::"jsonb",
    "free_gift_products" "text"[],
    "min_amount" numeric(10,2),
    "max_discount" numeric(10,2),
    "valid_from" timestamp with time zone NOT NULL,
    "valid_to" timestamp with time zone NOT NULL,
    "valid_days" integer[] DEFAULT '{0,1,2,3,4,5,6}'::integer[],
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "discounts_type_check" CHECK (("type" = ANY (ARRAY['percentage'::"text", 'fixed'::"text", 'free_gift'::"text"]))),
    CONSTRAINT "discounts_valid_date_range" CHECK (("valid_to" > "valid_from")),
    CONSTRAINT "discounts_valid_days_range" CHECK (("valid_days" <@ ARRAY[0, 1, 2, 3, 4, 5, 6])),
    CONSTRAINT "discounts_value_non_negative" CHECK (("value" >= (0)::numeric))
);


ALTER TABLE "public"."discounts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."goods_receipt_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "receipt_id" "uuid" NOT NULL,
    "line_no" integer NOT NULL,
    "variant_id" "uuid" NOT NULL,
    "description" "text" NOT NULL,
    "quantity" numeric(18,6) NOT NULL,
    "unit_cost" numeric(14,4) NOT NULL,
    "line_cost" numeric(14,2) NOT NULL,
    CONSTRAINT "goods_receipt_lines_quantity_check" CHECK (("quantity" > (0)::numeric)),
    CONSTRAINT "goods_receipt_lines_unit_cost_check" CHECK (("unit_cost" >= (0)::numeric))
);


ALTER TABLE "public"."goods_receipt_lines" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."goods_receipt_no_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."goods_receipt_no_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."goods_receipts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "receipt_no" "text" NOT NULL,
    "request_id" "uuid",
    "branch_id" "uuid" NOT NULL,
    "location_id" "uuid" NOT NULL,
    "supplier_id" "uuid",
    "supplier_name" "text",
    "supplier_reference" "text",
    "notes" "text",
    "total_cost" numeric(14,2) DEFAULT 0 NOT NULL,
    "received_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."goods_receipts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."idempotency_keys" (
    "key" "uuid" NOT NULL,
    "operation" "text" NOT NULL,
    "user_id" "uuid" DEFAULT "auth"."uid"(),
    "result" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."idempotency_keys" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."locations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "kind" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "locations_kind_check" CHECK (("kind" = ANY (ARRAY['shop_floor'::"text", 'stockroom'::"text", 'online'::"text"])))
);


ALTER TABLE "public"."locations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."lookup_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "kind" "text" NOT NULL,
    "lookup_id" "text" NOT NULL,
    "action" "text" NOT NULL,
    "old_value" "jsonb",
    "new_value" "jsonb",
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "lookup_events_action_check" CHECK (("action" = ANY (ARRAY['save'::"text", 'delete'::"text"])))
);


ALTER TABLE "public"."lookup_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."marketing_campaigns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "channel" "text" NOT NULL,
    "subject" "text" DEFAULT ''::"text" NOT NULL,
    "body" "text" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "created_by" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "marketing_campaigns_body_check" CHECK ((("length"(TRIM(BOTH FROM "body")) >= 1) AND ("length"(TRIM(BOTH FROM "body")) <= 10000))),
    CONSTRAINT "marketing_campaigns_channel_check" CHECK (("channel" = ANY (ARRAY['email'::"text", 'sms'::"text"]))),
    CONSTRAINT "marketing_campaigns_name_check" CHECK ((("length"(TRIM(BOTH FROM "name")) >= 1) AND ("length"(TRIM(BOTH FROM "name")) <= 150))),
    CONSTRAINT "marketing_campaigns_status_check" CHECK (("status" = 'draft'::"text")),
    CONSTRAINT "marketing_campaigns_subject_check" CHECK (("length"("subject") <= 200))
);


ALTER TABLE "public"."marketing_campaigns" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."marketing_consent_events" (
    "id" bigint NOT NULL,
    "subject_id" "uuid" NOT NULL,
    "source" "text" NOT NULL,
    "channel" "text" NOT NULL,
    "contact" "text",
    "consent" boolean,
    "recorded_by" "uuid" DEFAULT "auth"."uid"(),
    "recorded_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "marketing_consent_events_channel_check" CHECK (("channel" = ANY (ARRAY['email'::"text", 'sms'::"text"]))),
    CONSTRAINT "marketing_consent_events_source_check" CHECK (("source" = ANY (ARRAY['customers'::"text", 'customer_accounts'::"text"])))
);


ALTER TABLE "public"."marketing_consent_events" OWNER TO "postgres";


ALTER TABLE "public"."marketing_consent_events" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."marketing_consent_events_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."online_order_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "event" "text" NOT NULL,
    "public_message" "text",
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."online_order_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."online_order_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "line_no" integer NOT NULL,
    "variant_id" "uuid" NOT NULL,
    "description" "text" NOT NULL,
    "sku" "text",
    "size" "text",
    "color" "text",
    "unit" "text" NOT NULL,
    "quantity" numeric(18,6) NOT NULL,
    "unit_price" numeric(14,2) NOT NULL,
    "taxable" boolean NOT NULL,
    "tax" numeric(14,2) NOT NULL,
    "total" numeric(14,2) NOT NULL,
    "location_id" "uuid" NOT NULL,
    "reservation_id" "uuid" NOT NULL,
    CONSTRAINT "online_order_lines_quantity_check" CHECK (((("quantity" >= (1)::numeric) AND ("quantity" <= (10)::numeric)) AND ("quantity" = "trunc"("quantity"))))
);


ALTER TABLE "public"."online_order_lines" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."online_order_no_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."online_order_no_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."online_orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_no" "text" DEFAULT ('WEB-'::"text" || "lpad"(("nextval"('"public"."online_order_no_seq"'::"regclass"))::"text", 6, '0'::"text")) NOT NULL,
    "request_id" "uuid" NOT NULL,
    "account_id" "uuid" NOT NULL,
    "customer_id" "uuid",
    "branch_id" "uuid" NOT NULL,
    "payment_method" "text" NOT NULL,
    "fulfilment" "text" NOT NULL,
    "status" "text" NOT NULL,
    "payment_status" "text" NOT NULL,
    "contact_name" "text" NOT NULL,
    "phone" "text" NOT NULL,
    "email" "text",
    "address" "jsonb",
    "delivery_fee" numeric(14,2) NOT NULL,
    "subtotal" numeric(14,2) NOT NULL,
    "discount" numeric(14,2) DEFAULT 0 NOT NULL,
    "tax" numeric(14,2) NOT NULL,
    "total" numeric(14,2) NOT NULL,
    "tracking_no" "text",
    "courier" "text",
    "notes_customer" "text",
    "notes_staff" "text",
    "sale_id" "uuid",
    "expires_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "cancelled_reason" "text",
    "tracking_version" integer DEFAULT 0 NOT NULL,
    "assembly" boolean DEFAULT false NOT NULL,
    CONSTRAINT "online_orders_fulfilment_check" CHECK (("fulfilment" = ANY (ARRAY['pickup'::"text", 'delivery'::"text"]))),
    CONSTRAINT "online_orders_payment_method_check" CHECK (("payment_method" = ANY (ARRAY['card'::"text", 'easypaisa'::"text", 'cod'::"text"]))),
    CONSTRAINT "online_orders_payment_status_check" CHECK (("payment_status" = ANY (ARRAY['unpaid'::"text", 'paid'::"text", 'refunded'::"text", 'partially_refunded'::"text", 'cod'::"text"]))),
    CONSTRAINT "online_orders_status_check" CHECK (("status" = ANY (ARRAY['pending_payment'::"text", 'placed'::"text", 'confirmed'::"text", 'packed'::"text", 'ready_for_pickup'::"text", 'shipped'::"text", 'delivered'::"text", 'cancelled'::"text", 'expired'::"text", 'returned_to_sender'::"text"]))),
    CONSTRAINT "online_orders_tracking_version_check" CHECK (("tracking_version" >= 0))
);


ALTER TABLE "public"."online_orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."online_payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "provider" "text" NOT NULL,
    "method" "text" NOT NULL,
    "provider_ref" "text" NOT NULL,
    "amount" numeric(14,2) NOT NULL,
    "status" "text" NOT NULL,
    "needs_refund" boolean DEFAULT false NOT NULL,
    "raw" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "online_payments_amount_check" CHECK (("amount" >= (0)::numeric)),
    CONSTRAINT "online_payments_method_check" CHECK (("method" = ANY (ARRAY['card'::"text", 'wallet'::"text"]))),
    CONSTRAINT "online_payments_status_check" CHECK (("status" = ANY (ARRAY['initiated'::"text", 'paid'::"text", 'failed'::"text", 'refunded'::"text"])))
);


ALTER TABLE "public"."online_payments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."online_return_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "request_id" "uuid" NOT NULL,
    "actor" "text" NOT NULL,
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "status" "text" NOT NULL,
    "message" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "online_return_events_actor_check" CHECK (("actor" = ANY (ARRAY['customer'::"text", 'staff'::"text"]))),
    CONSTRAINT "online_return_events_message_check" CHECK ((("length"(TRIM(BOTH FROM "message")) >= 1) AND ("length"(TRIM(BOTH FROM "message")) <= 2000)))
);


ALTER TABLE "public"."online_return_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."online_return_items" (
    "request_id" "uuid" NOT NULL,
    "order_line_id" "uuid" NOT NULL,
    "quantity" integer NOT NULL,
    CONSTRAINT "online_return_items_quantity_check" CHECK ((("quantity" >= 1) AND ("quantity" <= 10)))
);


ALTER TABLE "public"."online_return_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."online_return_photos" (
    "id" "uuid" NOT NULL,
    "request_id" "uuid" NOT NULL,
    "storage_path" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."online_return_photos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."online_return_requests" (
    "id" "uuid" NOT NULL,
    "order_id" "uuid" NOT NULL,
    "reason" "text" NOT NULL,
    "requested_resolution" "text" NOT NULL,
    "message" "text" NOT NULL,
    "status" "text" DEFAULT 'submitted'::"text" NOT NULL,
    "staff_note" "text" DEFAULT ''::"text" NOT NULL,
    "version" integer DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "online_return_requests_message_check" CHECK ((("length"(TRIM(BOTH FROM "message")) >= 10) AND ("length"(TRIM(BOTH FROM "message")) <= 2000))),
    CONSTRAINT "online_return_requests_reason_check" CHECK (("reason" = ANY (ARRAY['damaged'::"text", 'wrong_item'::"text", 'size_fit'::"text", 'other'::"text"]))),
    CONSTRAINT "online_return_requests_requested_resolution_check" CHECK (("requested_resolution" = ANY (ARRAY['refund'::"text", 'exchange'::"text"]))),
    CONSTRAINT "online_return_requests_staff_note_check" CHECK (("length"("staff_note") <= 2000)),
    CONSTRAINT "online_return_requests_status_check" CHECK (("status" = ANY (ARRAY['submitted'::"text", 'needs_information'::"text", 'return_authorized'::"text", 'received'::"text", 'closed'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."online_return_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "sale_id" "uuid",
    "method" "text" NOT NULL,
    "amount" numeric(14,2) NOT NULL,
    "tendered" numeric(14,2),
    "change_given" numeric(14,2) DEFAULT 0 NOT NULL,
    "reference" "text",
    "card_type" "text",
    "card_last4" "text",
    "bank_name" "text",
    "holder_name" "text",
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "direction" "text" DEFAULT 'in'::"text" NOT NULL,
    "cash_session_id" "uuid",
    "return_id" "uuid",
    "customer_payment_id" "uuid",
    CONSTRAINT "payments_amount_check" CHECK (("amount" > (0)::numeric)),
    CONSTRAINT "payments_card_last4_check" CHECK ((("card_last4" IS NULL) OR ("card_last4" ~ '^\d{4}$'::"text"))),
    CONSTRAINT "payments_direction_check" CHECK (("direction" = ANY (ARRAY['in'::"text", 'out'::"text"]))),
    CONSTRAINT "payments_method_check" CHECK (("method" = ANY (ARRAY['cash'::"text", 'card'::"text", 'digital'::"text", 'credit'::"text", 'exchange'::"text", 'opening'::"text"])))
);


ALTER TABLE "public"."payments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_images" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "style_id" "uuid" NOT NULL,
    "variant_color" "text",
    "storage_path" "text" NOT NULL,
    "alt" "text",
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "product_images_check" CHECK (("storage_path" ~~ (('styles/'::"text" || ("style_id")::"text") || '/%'::"text")))
);


ALTER TABLE "public"."product_images" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_styles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "kind" "text" NOT NULL,
    "category_id" "uuid",
    "brand" "text",
    "material" "text",
    "season" "text",
    "design_code" "text",
    "description" "text",
    "size_scheme_id" "uuid",
    "unit" "text" DEFAULT 'piece'::"text" NOT NULL,
    "track_inventory" boolean DEFAULT true NOT NULL,
    "taxable" boolean DEFAULT true NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "published" boolean DEFAULT false NOT NULL,
    "slug" "text",
    "web_title" "text",
    "web_description" "text",
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "image_url" "text",
    "specs" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "bulky" boolean DEFAULT false NOT NULL,
    CONSTRAINT "bike_specs_fields" CHECK ("app_private"."valid_bike_specs"("specs")),
    CONSTRAINT "product_styles_kind_check" CHECK (("kind" = ANY (ARRAY['item'::"text", 'pack'::"text", 'service'::"text"]))),
    CONSTRAINT "product_styles_published_needs_slug" CHECK (((NOT "published") OR ("slug" IS NOT NULL))),
    CONSTRAINT "product_styles_slug_check" CHECK ((("slug" IS NULL) OR ("slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::"text"))),
    CONSTRAINT "product_styles_unit_check" CHECK (("unit" = ANY (ARRAY['piece'::"text", 'set'::"text", 'job'::"text"]))),
    CONSTRAINT "product_styles_unit_matches_kind" CHECK (((("kind" = 'item'::"text") AND ("unit" = 'piece'::"text")) OR (("kind" = 'pack'::"text") AND ("unit" = 'set'::"text")) OR (("kind" = 'service'::"text") AND ("unit" = 'job'::"text") AND ("track_inventory" = false))))
);


ALTER TABLE "public"."product_styles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_variants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "style_id" "uuid" NOT NULL,
    "sku" "text" NOT NULL,
    "size" "text",
    "color" "text",
    "fit" "text",
    "price" numeric(14,2) NOT NULL,
    "compare_at_price" numeric(14,2),
    "min_stock" numeric(18,6) DEFAULT 0 NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "published" boolean DEFAULT true NOT NULL,
    "legacy_product_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "product_variants_compare_at_price_check" CHECK ((("compare_at_price" IS NULL) OR ("compare_at_price" >= (0)::numeric))),
    CONSTRAINT "product_variants_min_stock_check" CHECK (("min_stock" >= (0)::numeric)),
    CONSTRAINT "product_variants_price_check" CHECK (("price" >= (0)::numeric)),
    CONSTRAINT "product_variants_sku_check" CHECK (("length"(TRIM(BOTH FROM "sku")) > 0))
);


ALTER TABLE "public"."product_variants" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."public_catalog" WITH ("security_invoker"='false') AS
 SELECT "s"."id" AS "style_id",
    "s"."slug",
    COALESCE("s"."web_title", "s"."name") AS "title",
    "s"."web_description" AS "description",
    "s"."kind",
    "s"."brand",
    "s"."material",
    "s"."season",
    "c"."name" AS "category",
    "v"."id" AS "variant_id",
    "v"."sku",
    "v"."size",
    "v"."color",
    "v"."fit",
    "v"."price",
    "v"."compare_at_price",
    "s"."unit",
        CASE
            WHEN (NOT "s"."track_inventory") THEN 'in_stock'::"text"
            WHEN (COALESCE("st"."available", (0)::numeric) <= (0)::numeric) THEN 'out_of_stock'::"text"
            WHEN (COALESCE("st"."available", (0)::numeric) <= GREATEST("v"."min_stock", (2)::numeric)) THEN 'low_stock'::"text"
            ELSE 'in_stock'::"text"
        END AS "stock_level"
   FROM ((("public"."product_styles" "s"
     JOIN "public"."product_variants" "v" ON (("v"."style_id" = "s"."id")))
     LEFT JOIN "public"."categories" "c" ON (("c"."id" = "s"."category_id")))
     LEFT JOIN LATERAL ( SELECT "sum"(("b"."on_hand" - "b"."reserved")) AS "available"
           FROM ("public"."stock_balances" "b"
             JOIN "public"."locations" "l" ON (("l"."id" = "b"."location_id")))
          WHERE (("b"."variant_id" = "v"."id") AND ("l"."kind" = ANY (ARRAY['shop_floor'::"text", 'stockroom'::"text", 'online'::"text"])) AND "l"."active")) "st" ON (true))
  WHERE ("s"."published" AND "s"."active" AND "v"."published" AND "v"."active" AND ("s"."kind" <> 'service'::"text"));


ALTER VIEW "public"."public_catalog" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."return_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "return_id" "uuid" NOT NULL,
    "sale_line_id" "uuid" NOT NULL,
    "variant_id" "uuid",
    "description" "text" NOT NULL,
    "quantity" numeric(18,6) NOT NULL,
    "refund_amount" numeric(14,2) NOT NULL,
    "tax_amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "restocked" boolean NOT NULL,
    "condition" "text" DEFAULT 'resaleable'::"text" NOT NULL,
    CONSTRAINT "return_lines_condition_check" CHECK (("condition" = ANY (ARRAY['resaleable'::"text", 'damaged'::"text", 'faulty'::"text"]))),
    CONSTRAINT "return_lines_quantity_check" CHECK (("quantity" > (0)::numeric)),
    CONSTRAINT "return_lines_refund_amount_check" CHECK (("refund_amount" >= (0)::numeric))
);


ALTER TABLE "public"."return_lines" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."return_no_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."return_no_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sale_commissions" (
    "sale_id" "uuid" NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "user_id" "uuid",
    "person_name" "text",
    "kind" "text",
    "rate" numeric(14,2) DEFAULT 0 NOT NULL,
    "basis" numeric(14,2) NOT NULL,
    "original_amount" numeric(14,2) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "sale_commissions_basis_check" CHECK (("basis" >= (0)::numeric)),
    CONSTRAINT "sale_commissions_kind_check" CHECK (("kind" = ANY (ARRAY['fixed'::"text", 'percentage'::"text"]))),
    CONSTRAINT "sale_commissions_original_amount_check" CHECK (("original_amount" >= (0)::numeric))
);


ALTER TABLE "public"."sale_commissions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sale_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "sale_id" "uuid" NOT NULL,
    "line_no" integer NOT NULL,
    "variant_id" "uuid",
    "description" "text" NOT NULL,
    "sku" "text",
    "unit" "text" NOT NULL,
    "quantity" numeric(18,6) NOT NULL,
    "unit_price" numeric(14,2) NOT NULL,
    "gross" numeric(14,2) NOT NULL,
    "manual_discount" numeric(14,2) DEFAULT 0 NOT NULL,
    "promotion_discount" numeric(14,2) DEFAULT 0 NOT NULL,
    "net" numeric(14,2) NOT NULL,
    "taxable" boolean NOT NULL,
    "tax" numeric(14,2) DEFAULT 0 NOT NULL,
    "total" numeric(14,2) NOT NULL,
    "unit_cost" numeric(14,4),
    "is_gift" boolean DEFAULT false NOT NULL,
    "promotion_id" "uuid",
    CONSTRAINT "sale_lines_quantity_check" CHECK (("quantity" > (0)::numeric)),
    CONSTRAINT "sale_lines_unit_price_check" CHECK (("unit_price" >= (0)::numeric))
);


ALTER TABLE "public"."sale_lines" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sales" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "invoice_number" "text" NOT NULL,
    "customer_id" "uuid",
    "customer_name" "text",
    "items" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "subtotal" numeric(12,2) DEFAULT 0 NOT NULL,
    "discount_amount" numeric(12,2) DEFAULT 0,
    "tax_amount" numeric(12,2) DEFAULT 0,
    "total" numeric(12,2) NOT NULL,
    "payment_method" "text",
    "card_details" "jsonb",
    "status" "text" DEFAULT 'completed'::"text",
    "cashier" "text",
    "cashier_role" "text",
    "receipt_number" "text",
    "notes" "text",
    "applied_discounts" "jsonb" DEFAULT '[]'::"jsonb",
    "free_gifts" "jsonb" DEFAULT '[]'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "cashier_id" "uuid",
    "branch_id" "uuid",
    "location_id" "uuid",
    "channel" "text" DEFAULT 'pos'::"text" NOT NULL,
    "request_id" "uuid",
    "change_due" numeric(14,2) DEFAULT 0 NOT NULL,
    CONSTRAINT "sales_amounts_non_negative" CHECK ((("subtotal" >= (0)::numeric) AND ("discount_amount" >= (0)::numeric) AND ("tax_amount" >= (0)::numeric) AND ("total" >= (0)::numeric))),
    CONSTRAINT "sales_channel_check" CHECK (("channel" = ANY (ARRAY['pos'::"text", 'web'::"text"]))),
    CONSTRAINT "sales_payment_method_check" CHECK (("payment_method" = ANY (ARRAY['cash'::"text", 'card'::"text", 'digital'::"text", 'credit'::"text", 'exchange'::"text"]))),
    CONSTRAINT "sales_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'completed'::"text", 'refunded'::"text", 'credit'::"text", 'draft'::"text"])))
);


ALTER TABLE "public"."sales" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sales_tabs" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid",
    "name" "text" NOT NULL,
    "cart" "jsonb" DEFAULT '[]'::"jsonb",
    "selected_customer_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."sales_tabs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."settings_history" (
    "id" bigint NOT NULL,
    "changed_by" "uuid" DEFAULT "auth"."uid"(),
    "changed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "old" "jsonb" NOT NULL,
    "new" "jsonb" NOT NULL
);


ALTER TABLE "public"."settings_history" OWNER TO "postgres";


ALTER TABLE "public"."settings_history" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."settings_history_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."size_schemes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "sizes" "text"[] NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    CONSTRAINT "size_schemes_sizes_check" CHECK (("cardinality"("sizes") > 0))
);


ALTER TABLE "public"."size_schemes" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."stock_count_no_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."stock_count_no_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."stock_movements" (
    "id" bigint NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "location_id" "uuid" NOT NULL,
    "variant_id" "uuid" NOT NULL,
    "quantity" numeric(18,6) NOT NULL,
    "movement_type" "text" NOT NULL,
    "channel" "text" DEFAULT 'pos'::"text" NOT NULL,
    "reference_type" "text",
    "reference_id" "uuid",
    "unit_cost" numeric(14,4),
    "reason" "text",
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "stock_movements_channel_check" CHECK (("channel" = ANY (ARRAY['pos'::"text", 'web'::"text", 'system'::"text"]))),
    CONSTRAINT "stock_movements_movement_type_check" CHECK (("movement_type" = ANY (ARRAY['opening'::"text", 'receive'::"text", 'sale'::"text", 'return'::"text", 'adjust'::"text", 'count'::"text", 'waste'::"text", 'transfer_in'::"text", 'transfer_out'::"text"]))),
    CONSTRAINT "stock_movements_quantity_check" CHECK (("quantity" <> (0)::numeric))
);


ALTER TABLE "public"."stock_movements" OWNER TO "postgres";


ALTER TABLE "public"."stock_movements" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."stock_movements_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."suppliers" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "email" "text",
    "phone" "text",
    "address" "text",
    "payment_terms" "text",
    "rating" numeric(2,1) DEFAULT 5.0,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "suppliers_rating_check" CHECK ((("rating" >= (0)::numeric) AND ("rating" <= (5)::numeric)))
);


ALTER TABLE "public"."suppliers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" NOT NULL,
    "username" "text" NOT NULL,
    "name" "text" NOT NULL,
    "email" "text" NOT NULL,
    "role" "text" DEFAULT 'cashier'::"text" NOT NULL,
    "permissions" "text"[] DEFAULT '{}'::"text"[],
    "active" boolean DEFAULT true,
    "last_login" timestamp with time zone,
    "avatar" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "users_role_check" CHECK (("role" = ANY (ARRAY['admin'::"text", 'manager'::"text", 'cashier'::"text"])))
);


ALTER TABLE "public"."users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."variant_costs" (
    "variant_id" "uuid" NOT NULL,
    "unit_cost" numeric(14,4) DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "variant_costs_unit_cost_check" CHECK (("unit_cost" >= (0)::numeric))
);


ALTER TABLE "public"."variant_costs" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."variant_stock" WITH ("security_invoker"='true') AS
 SELECT "variant_id",
    "location_id",
    "branch_id",
    "on_hand",
    "reserved",
    ("on_hand" - "reserved") AS "available"
   FROM "public"."stock_balances" "b";


ALTER VIEW "public"."variant_stock" OWNER TO "postgres";


ALTER TABLE ONLY "public"."app_settings"
    ADD CONSTRAINT "app_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."barcodes"
    ADD CONSTRAINT "barcodes_pkey" PRIMARY KEY ("code");



ALTER TABLE ONLY "public"."branch_memberships"
    ADD CONSTRAINT "branch_memberships_pkey" PRIMARY KEY ("user_id", "branch_id");



ALTER TABLE ONLY "public"."branches"
    ADD CONSTRAINT "branches_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."branches"
    ADD CONSTRAINT "branches_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."business_lookups"
    ADD CONSTRAINT "business_lookups_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cash_movements"
    ADD CONSTRAINT "cash_movements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cash_sessions"
    ADD CONSTRAINT "cash_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cash_sessions"
    ADD CONSTRAINT "cash_sessions_session_no_key" UNIQUE ("session_no");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."collection_styles"
    ADD CONSTRAINT "collection_styles_pkey" PRIMARY KEY ("collection_id", "style_id");



ALTER TABLE ONLY "public"."collections"
    ADD CONSTRAINT "collections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."collections"
    ADD CONSTRAINT "collections_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."commission_entries"
    ADD CONSTRAINT "commission_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."commission_entries"
    ADD CONSTRAINT "commission_entries_request_id_key" UNIQUE ("request_id");



ALTER TABLE ONLY "public"."commission_entries"
    ADD CONSTRAINT "commission_entries_return_line_id_key" UNIQUE ("return_line_id");



ALTER TABLE ONLY "public"."commission_rules"
    ADD CONSTRAINT "commission_rules_pkey" PRIMARY KEY ("branch_id", "user_id");



ALTER TABLE ONLY "public"."courier_returns"
    ADD CONSTRAINT "courier_returns_order_id_key" UNIQUE ("order_id");



ALTER TABLE ONLY "public"."courier_returns"
    ADD CONSTRAINT "courier_returns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."courier_returns"
    ADD CONSTRAINT "courier_returns_return_id_key" UNIQUE ("return_id");



ALTER TABLE ONLY "public"."customer_accounts"
    ADD CONSTRAINT "customer_accounts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_ledger"
    ADD CONSTRAINT "customer_ledger_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_payments"
    ADD CONSTRAINT "customer_payments_payment_no_key" UNIQUE ("payment_no");



ALTER TABLE ONLY "public"."customer_payments"
    ADD CONSTRAINT "customer_payments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_payments"
    ADD CONSTRAINT "customer_payments_request_id_key" UNIQUE ("request_id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."discount_code_redemptions"
    ADD CONSTRAINT "discount_code_redemptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."discount_code_redemptions"
    ADD CONSTRAINT "discount_code_redemptions_sale_id_key" UNIQUE ("sale_id");



ALTER TABLE ONLY "public"."discount_code_settings"
    ADD CONSTRAINT "discount_code_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."discount_codes"
    ADD CONSTRAINT "discount_codes_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."discount_codes"
    ADD CONSTRAINT "discount_codes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."discounts"
    ADD CONSTRAINT "discounts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."goods_receipt_lines"
    ADD CONSTRAINT "goods_receipt_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."goods_receipt_lines"
    ADD CONSTRAINT "goods_receipt_lines_receipt_id_line_no_key" UNIQUE ("receipt_id", "line_no");



ALTER TABLE ONLY "public"."goods_receipts"
    ADD CONSTRAINT "goods_receipts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."goods_receipts"
    ADD CONSTRAINT "goods_receipts_receipt_no_key" UNIQUE ("receipt_no");



ALTER TABLE ONLY "public"."goods_receipts"
    ADD CONSTRAINT "goods_receipts_request_id_key" UNIQUE ("request_id");



ALTER TABLE ONLY "public"."idempotency_keys"
    ADD CONSTRAINT "idempotency_keys_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."locations"
    ADD CONSTRAINT "locations_branch_id_code_key" UNIQUE ("branch_id", "code");



ALTER TABLE ONLY "public"."locations"
    ADD CONSTRAINT "locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lookup_events"
    ADD CONSTRAINT "lookup_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."marketing_campaigns"
    ADD CONSTRAINT "marketing_campaigns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."marketing_consent_events"
    ADD CONSTRAINT "marketing_consent_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."online_order_events"
    ADD CONSTRAINT "online_order_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."online_order_lines"
    ADD CONSTRAINT "online_order_lines_order_id_line_no_key" UNIQUE ("order_id", "line_no");



ALTER TABLE ONLY "public"."online_order_lines"
    ADD CONSTRAINT "online_order_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."online_order_lines"
    ADD CONSTRAINT "online_order_lines_reservation_id_key" UNIQUE ("reservation_id");



ALTER TABLE ONLY "public"."online_orders"
    ADD CONSTRAINT "online_orders_order_no_key" UNIQUE ("order_no");



ALTER TABLE ONLY "public"."online_orders"
    ADD CONSTRAINT "online_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."online_orders"
    ADD CONSTRAINT "online_orders_request_id_key" UNIQUE ("request_id");



ALTER TABLE ONLY "public"."online_orders"
    ADD CONSTRAINT "online_orders_sale_id_key" UNIQUE ("sale_id");



ALTER TABLE ONLY "public"."online_payments"
    ADD CONSTRAINT "online_payments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."online_payments"
    ADD CONSTRAINT "online_payments_provider_ref_key" UNIQUE ("provider_ref");



ALTER TABLE ONLY "public"."online_return_events"
    ADD CONSTRAINT "online_return_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."online_return_items"
    ADD CONSTRAINT "online_return_items_pkey" PRIMARY KEY ("request_id", "order_line_id");



ALTER TABLE ONLY "public"."online_return_photos"
    ADD CONSTRAINT "online_return_photos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."online_return_photos"
    ADD CONSTRAINT "online_return_photos_storage_path_key" UNIQUE ("storage_path");



ALTER TABLE ONLY "public"."online_return_requests"
    ADD CONSTRAINT "online_return_requests_order_id_key" UNIQUE ("order_id");



ALTER TABLE ONLY "public"."online_return_requests"
    ADD CONSTRAINT "online_return_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_images"
    ADD CONSTRAINT "product_images_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_styles"
    ADD CONSTRAINT "product_styles_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."product_styles"
    ADD CONSTRAINT "product_styles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_styles"
    ADD CONSTRAINT "product_styles_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."product_variants"
    ADD CONSTRAINT "product_variants_legacy_product_id_key" UNIQUE ("legacy_product_id");



ALTER TABLE ONLY "public"."product_variants"
    ADD CONSTRAINT "product_variants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_variants"
    ADD CONSTRAINT "product_variants_sku_key" UNIQUE ("sku");



ALTER TABLE ONLY "public"."return_lines"
    ADD CONSTRAINT "return_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."returns"
    ADD CONSTRAINT "returns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."returns"
    ADD CONSTRAINT "returns_request_id_key" UNIQUE ("request_id");



ALTER TABLE ONLY "public"."returns"
    ADD CONSTRAINT "returns_return_no_key" UNIQUE ("return_no");



ALTER TABLE ONLY "public"."sale_commissions"
    ADD CONSTRAINT "sale_commissions_pkey" PRIMARY KEY ("sale_id");



ALTER TABLE ONLY "public"."sale_lines"
    ADD CONSTRAINT "sale_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sale_lines"
    ADD CONSTRAINT "sale_lines_sale_id_line_no_key" UNIQUE ("sale_id", "line_no");



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_invoice_number_key" UNIQUE ("invoice_number");



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_request_id_key" UNIQUE ("request_id");



ALTER TABLE ONLY "public"."sales_tabs"
    ADD CONSTRAINT "sales_tabs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."settings_history"
    ADD CONSTRAINT "settings_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."size_schemes"
    ADD CONSTRAINT "size_schemes_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."size_schemes"
    ADD CONSTRAINT "size_schemes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."stock_balances"
    ADD CONSTRAINT "stock_balances_pkey" PRIMARY KEY ("location_id", "variant_id");



ALTER TABLE ONLY "public"."stock_count_lines"
    ADD CONSTRAINT "stock_count_lines_item_key" UNIQUE ("count_id", "variant_id");



ALTER TABLE ONLY "public"."stock_count_lines"
    ADD CONSTRAINT "stock_count_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."stock_counts"
    ADD CONSTRAINT "stock_counts_count_no_key" UNIQUE ("count_no");



ALTER TABLE ONLY "public"."stock_counts"
    ADD CONSTRAINT "stock_counts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."stock_movements"
    ADD CONSTRAINT "stock_movements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."stock_reservations"
    ADD CONSTRAINT "stock_reservations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_username_key" UNIQUE ("username");



ALTER TABLE ONLY "public"."variant_costs"
    ADD CONSTRAINT "variant_costs_pkey" PRIMARY KEY ("variant_id");



CREATE INDEX "barcodes_lower_code_idx" ON "public"."barcodes" USING "btree" ("lower"("code"));



CREATE UNIQUE INDEX "business_lookup_unique" ON "public"."business_lookups" USING "btree" ("kind", "lower"("value"));



CREATE INDEX "commission_account" ON "public"."commission_entries" USING "btree" ("branch_id", "user_id", "created_at", "id");



CREATE UNIQUE INDEX "commission_one_earning" ON "public"."commission_entries" USING "btree" ("sale_id") WHERE ("kind" = 'earned'::"text");



CREATE INDEX "discount_code_redemptions_code" ON "public"."discount_code_redemptions" USING "btree" ("code_id");



CREATE INDEX "discount_codes_customer" ON "public"."discount_codes" USING "btree" ("customer_id");



CREATE UNIQUE INDEX "discount_codes_one_welcome" ON "public"."discount_codes" USING "btree" ("customer_id") WHERE ("kind" = 'welcome'::"text");



CREATE INDEX "idx_barcodes_variant" ON "public"."barcodes" USING "btree" ("variant_id");



CREATE INDEX "idx_branch_memberships_branch" ON "public"."branch_memberships" USING "btree" ("branch_id");



CREATE INDEX "idx_cash_movements_session" ON "public"."cash_movements" USING "btree" ("session_id");



CREATE INDEX "idx_cash_sessions_branch_time" ON "public"."cash_sessions" USING "btree" ("branch_id", "opened_at");



CREATE UNIQUE INDEX "idx_cash_sessions_open_user" ON "public"."cash_sessions" USING "btree" ("user_id") WHERE ("status" = 'open'::"text");



CREATE INDEX "idx_collection_styles_style" ON "public"."collection_styles" USING "btree" ("style_id", "collection_id");



CREATE UNIQUE INDEX "idx_customer_accounts_customer" ON "public"."customer_accounts" USING "btree" ("customer_id") WHERE ("customer_id" IS NOT NULL);



CREATE UNIQUE INDEX "idx_customer_ledger_opening" ON "public"."customer_ledger" USING "btree" ("customer_id") WHERE ("entry_type" = 'opening'::"text");



CREATE INDEX "idx_customer_ledger_time" ON "public"."customer_ledger" USING "btree" ("customer_id", "created_at", "id");



CREATE INDEX "idx_customers_email" ON "public"."customers" USING "btree" ("email") WHERE ("email" IS NOT NULL);



CREATE INDEX "idx_customers_name" ON "public"."customers" USING "gin" ("to_tsvector"('"english"'::"regconfig", "name"));



CREATE INDEX "idx_customers_name_text" ON "public"."customers" USING "btree" ("name" "text_pattern_ops");



CREATE UNIQUE INDEX "idx_customers_phone_unique" ON "public"."customers" USING "btree" ("phone") WHERE ("phone" IS NOT NULL);



CREATE INDEX "idx_discounts_active" ON "public"."discounts" USING "btree" ("active");



CREATE INDEX "idx_discounts_type" ON "public"."discounts" USING "btree" ("type");



CREATE INDEX "idx_discounts_validity" ON "public"."discounts" USING "btree" ("valid_from", "valid_to") WHERE ("active" = true);



CREATE INDEX "idx_goods_receipt_lines_variant" ON "public"."goods_receipt_lines" USING "btree" ("variant_id");



CREATE INDEX "idx_goods_receipts_branch_time" ON "public"."goods_receipts" USING "btree" ("branch_id", "received_at");



CREATE INDEX "idx_payments_created_at" ON "public"."payments" USING "btree" ("created_at");



CREATE INDEX "idx_payments_customer_payment" ON "public"."payments" USING "btree" ("customer_payment_id") WHERE ("customer_payment_id" IS NOT NULL);



CREATE INDEX "idx_payments_sale" ON "public"."payments" USING "btree" ("sale_id");



CREATE INDEX "idx_product_images_style_order" ON "public"."product_images" USING "btree" ("style_id", "sort_order", "id");



CREATE INDEX "idx_product_styles_kind" ON "public"."product_styles" USING "btree" ("kind");



CREATE INDEX "idx_product_styles_published" ON "public"."product_styles" USING "btree" ("published") WHERE "published";



CREATE INDEX "idx_product_styles_search" ON "public"."product_styles" USING "gin" ("to_tsvector"('"simple"'::"regconfig", ((((COALESCE("name", ''::"text") || ' '::"text") || COALESCE("code", ''::"text")) || ' '::"text") || COALESCE("brand", ''::"text"))));



CREATE UNIQUE INDEX "idx_product_variants_options" ON "public"."product_variants" USING "btree" ("style_id", COALESCE("size", ''::"text"), COALESCE("color", ''::"text"), COALESCE("fit", ''::"text"));



CREATE INDEX "idx_product_variants_style" ON "public"."product_variants" USING "btree" ("style_id");



CREATE INDEX "idx_return_lines_return" ON "public"."return_lines" USING "btree" ("return_id");



CREATE INDEX "idx_return_lines_sale_line" ON "public"."return_lines" USING "btree" ("sale_line_id");



CREATE INDEX "idx_returns_branch_time" ON "public"."returns" USING "btree" ("branch_id", "created_at");



CREATE INDEX "idx_returns_sale" ON "public"."returns" USING "btree" ("sale_id");



CREATE INDEX "idx_sale_lines_variant" ON "public"."sale_lines" USING "btree" ("variant_id");



CREATE INDEX "idx_sales_branch_time" ON "public"."sales" USING "btree" ("branch_id", "created_at");



CREATE INDEX "idx_sales_cashier" ON "public"."sales" USING "btree" ("cashier");



CREATE INDEX "idx_sales_cashier_id" ON "public"."sales" USING "btree" ("cashier_id");



CREATE INDEX "idx_sales_created_at_status" ON "public"."sales" USING "btree" ("created_at", "status");



CREATE INDEX "idx_sales_customer_id" ON "public"."sales" USING "btree" ("customer_id");



CREATE INDEX "idx_sales_invoice_number" ON "public"."sales" USING "btree" ("invoice_number");



CREATE INDEX "idx_sales_payment_method" ON "public"."sales" USING "btree" ("payment_method");



CREATE INDEX "idx_sales_status" ON "public"."sales" USING "btree" ("status");



CREATE INDEX "idx_sales_tabs_user_id" ON "public"."sales_tabs" USING "btree" ("user_id");



CREATE INDEX "idx_sales_timestamp" ON "public"."sales" USING "btree" ("created_at");



CREATE INDEX "idx_stock_balances_branch" ON "public"."stock_balances" USING "btree" ("branch_id");



CREATE INDEX "idx_stock_balances_variant" ON "public"."stock_balances" USING "btree" ("variant_id");



CREATE INDEX "idx_stock_counts_branch" ON "public"."stock_counts" USING "btree" ("branch_id", "created_at");



CREATE INDEX "idx_stock_movements_branch_time" ON "public"."stock_movements" USING "btree" ("branch_id", "created_at");



CREATE INDEX "idx_stock_movements_reference" ON "public"."stock_movements" USING "btree" ("reference_type", "reference_id");



CREATE INDEX "idx_stock_movements_variant" ON "public"."stock_movements" USING "btree" ("variant_id", "created_at");



CREATE INDEX "idx_stock_reservations_active" ON "public"."stock_reservations" USING "btree" ("variant_id", "location_id") WHERE ("status" = 'active'::"text");



CREATE INDEX "idx_stock_reservations_expiry" ON "public"."stock_reservations" USING "btree" ("expires_at") WHERE ("status" = 'active'::"text");



CREATE INDEX "idx_stock_reservations_reference" ON "public"."stock_reservations" USING "btree" ("reference_type", "reference_id");



CREATE UNIQUE INDEX "idx_suppliers_name" ON "public"."suppliers" USING "btree" ("lower"("name"));



CREATE INDEX "idx_users_active" ON "public"."users" USING "btree" ("active");



CREATE INDEX "idx_users_email" ON "public"."users" USING "btree" ("email");



CREATE INDEX "idx_users_role" ON "public"."users" USING "btree" ("role");



CREATE INDEX "idx_users_username" ON "public"."users" USING "btree" ("username");



CREATE INDEX "online_events_order" ON "public"."online_order_events" USING "btree" ("order_id", "created_at");



CREATE INDEX "online_orders_account" ON "public"."online_orders" USING "btree" ("account_id", "created_at");



CREATE INDEX "online_orders_expiry" ON "public"."online_orders" USING "btree" ("expires_at") WHERE ("status" = 'pending_payment'::"text");



CREATE INDEX "online_orders_status" ON "public"."online_orders" USING "btree" ("status", "created_at");



CREATE INDEX "online_payments_order" ON "public"."online_payments" USING "btree" ("order_id");



CREATE INDEX "online_return_events_request" ON "public"."online_return_events" USING "btree" ("request_id", "created_at");



CREATE INDEX "online_return_photos_request" ON "public"."online_return_photos" USING "btree" ("request_id");



CREATE INDEX "online_return_queue" ON "public"."online_return_requests" USING "btree" ("status", "updated_at" DESC);



CREATE INDEX "product_variants_lower_sku_idx" ON "public"."product_variants" USING "btree" ("lower"("sku"));



CREATE OR REPLACE TRIGGER "accounts_marketing_consent" BEFORE INSERT OR UPDATE ON "public"."customer_accounts" FOR EACH ROW EXECUTE FUNCTION "public"."record_marketing_consent"();



CREATE OR REPLACE TRIGGER "campaigns_updated" BEFORE UPDATE ON "public"."marketing_campaigns" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "commission_entries_immutable" BEFORE DELETE OR UPDATE ON "public"."commission_entries" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "commission_sales_immutable" BEFORE DELETE OR UPDATE ON "public"."sale_commissions" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "courier_returns_append_only" BEFORE DELETE OR UPDATE ON "public"."courier_returns" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "customer_ledger_append_only" BEFORE DELETE OR UPDATE ON "public"."customer_ledger" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "customer_ledger_apply" AFTER INSERT ON "public"."customer_ledger" FOR EACH ROW EXECUTE FUNCTION "public"."apply_customer_ledger"();



CREATE OR REPLACE TRIGGER "customer_payments_append_only" BEFORE DELETE OR UPDATE ON "public"."customer_payments" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "customers_guard_balance" BEFORE INSERT OR UPDATE ON "public"."customers" FOR EACH ROW EXECUTE FUNCTION "public"."guard_customer_balance"();



CREATE OR REPLACE TRIGGER "customers_marketing_consent" BEFORE INSERT OR UPDATE ON "public"."customers" FOR EACH ROW EXECUTE FUNCTION "public"."record_marketing_consent"();



CREATE OR REPLACE TRIGGER "customers_welcome_code" AFTER INSERT ON "public"."customers" FOR EACH ROW EXECUTE FUNCTION "public"."issue_welcome_code_for_new_customer"();



CREATE OR REPLACE TRIGGER "lookup_events_immutable" BEFORE DELETE OR UPDATE ON "public"."lookup_events" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "online_events_append_only" BEFORE DELETE OR UPDATE ON "public"."online_order_events" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "online_orders_open_limit" BEFORE INSERT ON "public"."online_orders" FOR EACH ROW EXECUTE FUNCTION "public"."limit_open_online_orders"();



CREATE OR REPLACE TRIGGER "online_orders_updated" BEFORE UPDATE ON "public"."online_orders" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "online_payments_updated" BEFORE UPDATE ON "public"."online_payments" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "online_return_events_immutable" BEFORE DELETE OR UPDATE ON "public"."online_return_events" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "register_customer_tiers" AFTER INSERT OR UPDATE OF "price_tier" ON "public"."customers" FOR EACH ROW EXECUTE FUNCTION "public"."register_catalog_lookups"();



CREATE OR REPLACE TRIGGER "register_style_lookups" AFTER INSERT OR UPDATE OF "brand", "material", "season" ON "public"."product_styles" FOR EACH ROW EXECUTE FUNCTION "public"."register_catalog_lookups"();



CREATE OR REPLACE TRIGGER "register_variant_lookups" AFTER INSERT OR UPDATE OF "color", "fit" ON "public"."product_variants" FOR EACH ROW EXECUTE FUNCTION "public"."register_catalog_lookups"();



CREATE OR REPLACE TRIGGER "reverse_commission_after_return" AFTER INSERT ON "public"."return_lines" FOR EACH ROW EXECUTE FUNCTION "public"."reverse_sale_commission"();



CREATE OR REPLACE TRIGGER "sales_redeem_discount_code" AFTER INSERT OR UPDATE OF "status" ON "public"."sales" FOR EACH ROW EXECUTE FUNCTION "public"."redeem_sale_discount_code"();



CREATE OR REPLACE TRIGGER "settings_history_append_only" BEFORE DELETE OR UPDATE ON "public"."settings_history" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "trigger_auto_generate_invoice_number" BEFORE INSERT ON "public"."sales" FOR EACH ROW EXECUTE FUNCTION "public"."auto_generate_invoice_number"();



CREATE OR REPLACE TRIGGER "trigger_cash_movements_append_only" BEFORE DELETE OR UPDATE ON "public"."cash_movements" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "trigger_goods_receipt_lines_append_only" BEFORE DELETE OR UPDATE ON "public"."goods_receipt_lines" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "trigger_goods_receipts_append_only" BEFORE DELETE OR UPDATE ON "public"."goods_receipts" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "trigger_guard_cash_variance_alert" BEFORE UPDATE OF "cash_variance_alert" ON "public"."app_settings" FOR EACH ROW EXECUTE FUNCTION "public"."guard_cash_variance_alert"();



CREATE OR REPLACE TRIGGER "trigger_normalize_customer_phone" BEFORE INSERT OR UPDATE OF "phone" ON "public"."customers" FOR EACH ROW EXECUTE FUNCTION "public"."normalize_customer_phone"();



CREATE OR REPLACE TRIGGER "trigger_payments_append_only" BEFORE DELETE OR UPDATE ON "public"."payments" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "trigger_protect_customer_account_columns" BEFORE UPDATE ON "public"."customer_accounts" FOR EACH ROW EXECUTE FUNCTION "public"."protect_customer_account_columns"();



CREATE OR REPLACE TRIGGER "trigger_protect_user_privileged_columns" BEFORE UPDATE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."protect_user_privileged_columns"();



CREATE OR REPLACE TRIGGER "trigger_record_cash_payment" BEFORE INSERT ON "public"."payments" FOR EACH ROW EXECUTE FUNCTION "public"."record_cash_payment"();



CREATE OR REPLACE TRIGGER "trigger_return_lines_append_only" BEFORE DELETE OR UPDATE ON "public"."return_lines" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "trigger_returns_append_only" BEFORE DELETE ON "public"."returns" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "trigger_sale_lines_append_only" BEFORE UPDATE ON "public"."sale_lines" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "trigger_stock_movements_append_only" BEFORE DELETE OR UPDATE ON "public"."stock_movements" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_ledger_changes"();



CREATE OR REPLACE TRIGGER "trigger_update_customer_stats" AFTER INSERT ON "public"."sales" FOR EACH ROW EXECUTE FUNCTION "public"."update_customer_stats"();



CREATE OR REPLACE TRIGGER "update_app_settings_updated_at" BEFORE UPDATE ON "public"."app_settings" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_branches_updated_at" BEFORE UPDATE ON "public"."branches" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_categories_updated_at" BEFORE UPDATE ON "public"."categories" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_customer_accounts_updated_at" BEFORE UPDATE ON "public"."customer_accounts" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_customers_updated_at" BEFORE UPDATE ON "public"."customers" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_discount_codes_updated_at" BEFORE UPDATE ON "public"."discount_codes" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_discounts_updated_at" BEFORE UPDATE ON "public"."discounts" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_product_styles_updated_at" BEFORE UPDATE ON "public"."product_styles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_product_variants_updated_at" BEFORE UPDATE ON "public"."product_variants" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_sales_tabs_updated_at" BEFORE UPDATE ON "public"."sales_tabs" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_sales_updated_at" BEFORE UPDATE ON "public"."sales" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_suppliers_updated_at" BEFORE UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_users_updated_at" BEFORE UPDATE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_variant_costs_updated_at" BEFORE UPDATE ON "public"."variant_costs" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



ALTER TABLE ONLY "public"."barcodes"
    ADD CONSTRAINT "barcodes_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."product_variants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."branch_memberships"
    ADD CONSTRAINT "branch_memberships_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."branch_memberships"
    ADD CONSTRAINT "branch_memberships_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cash_movements"
    ADD CONSTRAINT "cash_movements_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."cash_sessions"("id");



ALTER TABLE ONLY "public"."cash_sessions"
    ADD CONSTRAINT "cash_sessions_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."cash_sessions"
    ADD CONSTRAINT "cash_sessions_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."cash_sessions"
    ADD CONSTRAINT "cash_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."collection_styles"
    ADD CONSTRAINT "collection_styles_collection_id_fkey" FOREIGN KEY ("collection_id") REFERENCES "public"."collections"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."collection_styles"
    ADD CONSTRAINT "collection_styles_style_id_fkey" FOREIGN KEY ("style_id") REFERENCES "public"."product_styles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."commission_entries"
    ADD CONSTRAINT "commission_entries_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."commission_entries"
    ADD CONSTRAINT "commission_entries_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."commission_entries"
    ADD CONSTRAINT "commission_entries_return_line_id_fkey" FOREIGN KEY ("return_line_id") REFERENCES "public"."return_lines"("id");



ALTER TABLE ONLY "public"."commission_entries"
    ADD CONSTRAINT "commission_entries_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "public"."sale_commissions"("sale_id");



ALTER TABLE ONLY "public"."commission_entries"
    ADD CONSTRAINT "commission_entries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."commission_rules"
    ADD CONSTRAINT "commission_rules_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."commission_rules"
    ADD CONSTRAINT "commission_rules_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."commission_rules"
    ADD CONSTRAINT "commission_rules_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."courier_returns"
    ADD CONSTRAINT "courier_returns_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."courier_returns"
    ADD CONSTRAINT "courier_returns_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."online_orders"("id");



ALTER TABLE ONLY "public"."courier_returns"
    ADD CONSTRAINT "courier_returns_return_id_fkey" FOREIGN KEY ("return_id") REFERENCES "public"."returns"("id");



ALTER TABLE ONLY "public"."customer_accounts"
    ADD CONSTRAINT "customer_accounts_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_accounts"
    ADD CONSTRAINT "customer_accounts_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_ledger"
    ADD CONSTRAINT "customer_ledger_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id");



ALTER TABLE ONLY "public"."customer_ledger"
    ADD CONSTRAINT "customer_ledger_payment_header_fkey" FOREIGN KEY ("payment_id") REFERENCES "public"."customer_payments"("id");



ALTER TABLE ONLY "public"."customer_ledger"
    ADD CONSTRAINT "customer_ledger_return_id_fkey" FOREIGN KEY ("return_id") REFERENCES "public"."returns"("id");



ALTER TABLE ONLY "public"."customer_ledger"
    ADD CONSTRAINT "customer_ledger_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "public"."sales"("id");



ALTER TABLE ONLY "public"."customer_payments"
    ADD CONSTRAINT "customer_payments_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id");



ALTER TABLE ONLY "public"."discount_code_redemptions"
    ADD CONSTRAINT "discount_code_redemptions_code_id_fkey" FOREIGN KEY ("code_id") REFERENCES "public"."discount_codes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."discount_code_redemptions"
    ADD CONSTRAINT "discount_code_redemptions_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."discount_code_redemptions"
    ADD CONSTRAINT "discount_code_redemptions_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "public"."sales"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."discount_code_settings"
    ADD CONSTRAINT "discount_code_settings_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."discount_codes"
    ADD CONSTRAINT "discount_codes_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."discount_codes"
    ADD CONSTRAINT "discount_codes_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."goods_receipt_lines"
    ADD CONSTRAINT "goods_receipt_lines_receipt_id_fkey" FOREIGN KEY ("receipt_id") REFERENCES "public"."goods_receipts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."goods_receipt_lines"
    ADD CONSTRAINT "goods_receipt_lines_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."product_variants"("id");



ALTER TABLE ONLY "public"."goods_receipts"
    ADD CONSTRAINT "goods_receipts_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."goods_receipts"
    ADD CONSTRAINT "goods_receipts_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."goods_receipts"
    ADD CONSTRAINT "goods_receipts_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."locations"
    ADD CONSTRAINT "locations_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lookup_events"
    ADD CONSTRAINT "lookup_events_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."online_order_events"
    ADD CONSTRAINT "online_order_events_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."online_order_events"
    ADD CONSTRAINT "online_order_events_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."online_orders"("id");



ALTER TABLE ONLY "public"."online_order_lines"
    ADD CONSTRAINT "online_order_lines_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."online_order_lines"
    ADD CONSTRAINT "online_order_lines_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."online_orders"("id");



ALTER TABLE ONLY "public"."online_order_lines"
    ADD CONSTRAINT "online_order_lines_reservation_id_fkey" FOREIGN KEY ("reservation_id") REFERENCES "public"."stock_reservations"("id");



ALTER TABLE ONLY "public"."online_order_lines"
    ADD CONSTRAINT "online_order_lines_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."product_variants"("id");



ALTER TABLE ONLY "public"."online_orders"
    ADD CONSTRAINT "online_orders_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."customer_accounts"("id");



ALTER TABLE ONLY "public"."online_orders"
    ADD CONSTRAINT "online_orders_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."online_orders"
    ADD CONSTRAINT "online_orders_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id");



ALTER TABLE ONLY "public"."online_orders"
    ADD CONSTRAINT "online_orders_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "public"."sales"("id");



ALTER TABLE ONLY "public"."online_payments"
    ADD CONSTRAINT "online_payments_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."online_orders"("id");



ALTER TABLE ONLY "public"."online_return_events"
    ADD CONSTRAINT "online_return_events_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."online_return_events"
    ADD CONSTRAINT "online_return_events_request_id_fkey" FOREIGN KEY ("request_id") REFERENCES "public"."online_return_requests"("id");



ALTER TABLE ONLY "public"."online_return_items"
    ADD CONSTRAINT "online_return_items_order_line_id_fkey" FOREIGN KEY ("order_line_id") REFERENCES "public"."online_order_lines"("id");



ALTER TABLE ONLY "public"."online_return_items"
    ADD CONSTRAINT "online_return_items_request_id_fkey" FOREIGN KEY ("request_id") REFERENCES "public"."online_return_requests"("id");



ALTER TABLE ONLY "public"."online_return_photos"
    ADD CONSTRAINT "online_return_photos_request_id_fkey" FOREIGN KEY ("request_id") REFERENCES "public"."online_return_requests"("id");



ALTER TABLE ONLY "public"."online_return_requests"
    ADD CONSTRAINT "online_return_requests_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."online_orders"("id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_cash_session_id_fkey" FOREIGN KEY ("cash_session_id") REFERENCES "public"."cash_sessions"("id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_customer_payment_id_fkey" FOREIGN KEY ("customer_payment_id") REFERENCES "public"."customer_payments"("id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_return_id_fkey" FOREIGN KEY ("return_id") REFERENCES "public"."returns"("id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "public"."sales"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."product_images"
    ADD CONSTRAINT "product_images_style_id_fkey" FOREIGN KEY ("style_id") REFERENCES "public"."product_styles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."product_styles"
    ADD CONSTRAINT "product_styles_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."product_styles"
    ADD CONSTRAINT "product_styles_size_scheme_id_fkey" FOREIGN KEY ("size_scheme_id") REFERENCES "public"."size_schemes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."product_variants"
    ADD CONSTRAINT "product_variants_style_id_fkey" FOREIGN KEY ("style_id") REFERENCES "public"."product_styles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."return_lines"
    ADD CONSTRAINT "return_lines_return_id_fkey" FOREIGN KEY ("return_id") REFERENCES "public"."returns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."return_lines"
    ADD CONSTRAINT "return_lines_sale_line_id_fkey" FOREIGN KEY ("sale_line_id") REFERENCES "public"."sale_lines"("id");



ALTER TABLE ONLY "public"."return_lines"
    ADD CONSTRAINT "return_lines_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."product_variants"("id");



ALTER TABLE ONLY "public"."returns"
    ADD CONSTRAINT "returns_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."returns"
    ADD CONSTRAINT "returns_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."returns"
    ADD CONSTRAINT "returns_exchange_sale_id_fkey" FOREIGN KEY ("exchange_sale_id") REFERENCES "public"."sales"("id");



ALTER TABLE ONLY "public"."returns"
    ADD CONSTRAINT "returns_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."returns"
    ADD CONSTRAINT "returns_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "public"."sales"("id");



ALTER TABLE ONLY "public"."sale_commissions"
    ADD CONSTRAINT "sale_commissions_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."sale_commissions"
    ADD CONSTRAINT "sale_commissions_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "public"."sales"("id");



ALTER TABLE ONLY "public"."sale_commissions"
    ADD CONSTRAINT "sale_commissions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."sale_lines"
    ADD CONSTRAINT "sale_lines_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "public"."sales"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sale_lines"
    ADD CONSTRAINT "sale_lines_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."product_variants"("id");



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_cashier_id_fkey" FOREIGN KEY ("cashier_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."sales_tabs"
    ADD CONSTRAINT "sales_tabs_selected_customer_id_fkey" FOREIGN KEY ("selected_customer_id") REFERENCES "public"."customers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sales_tabs"
    ADD CONSTRAINT "sales_tabs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."stock_balances"
    ADD CONSTRAINT "stock_balances_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."stock_balances"
    ADD CONSTRAINT "stock_balances_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."stock_balances"
    ADD CONSTRAINT "stock_balances_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."product_variants"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."stock_count_lines"
    ADD CONSTRAINT "stock_count_lines_count_id_fkey" FOREIGN KEY ("count_id") REFERENCES "public"."stock_counts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."stock_count_lines"
    ADD CONSTRAINT "stock_count_lines_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."product_variants"("id");



ALTER TABLE ONLY "public"."stock_counts"
    ADD CONSTRAINT "stock_counts_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."stock_counts"
    ADD CONSTRAINT "stock_counts_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."stock_movements"
    ADD CONSTRAINT "stock_movements_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."stock_movements"
    ADD CONSTRAINT "stock_movements_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."stock_movements"
    ADD CONSTRAINT "stock_movements_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."product_variants"("id");



ALTER TABLE ONLY "public"."stock_reservations"
    ADD CONSTRAINT "stock_reservations_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."stock_reservations"
    ADD CONSTRAINT "stock_reservations_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."stock_reservations"
    ADD CONSTRAINT "stock_reservations_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."product_variants"("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."variant_costs"
    ADD CONSTRAINT "variant_costs_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."product_variants"("id") ON DELETE CASCADE;



ALTER TABLE "public"."app_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."barcodes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "barcodes_select_staff" ON "public"."barcodes" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "barcodes_write_back_office" ON "public"."barcodes" TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



ALTER TABLE "public"."branch_memberships" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."branches" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "branches_select_members" ON "public"."branches" FOR SELECT TO "authenticated" USING ("public"."is_branch_member"("id"));



CREATE POLICY "branches_write_admin" ON "public"."branches" TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['admin'::"text"]));



ALTER TABLE "public"."business_lookups" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "business_lookups_read" ON "public"."business_lookups" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "campaigns_delete" ON "public"."marketing_campaigns" FOR DELETE TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



CREATE POLICY "campaigns_insert" ON "public"."marketing_campaigns" FOR INSERT TO "authenticated" WITH CHECK (("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]) AND ("created_by" = "auth"."uid"())));



CREATE POLICY "campaigns_select" ON "public"."marketing_campaigns" FOR SELECT TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



CREATE POLICY "campaigns_update" ON "public"."marketing_campaigns" FOR UPDATE TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



ALTER TABLE "public"."cash_movements" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cash_movements_select" ON "public"."cash_movements" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."cash_sessions" "s"
  WHERE ("s"."id" = "cash_movements"."session_id"))));



ALTER TABLE "public"."cash_sessions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cash_sessions_select" ON "public"."cash_sessions" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]) AND "public"."is_branch_member"("branch_id"))));



ALTER TABLE "public"."categories" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "categories_select_staff" ON "public"."categories" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "categories_write_back_office" ON "public"."categories" TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



ALTER TABLE "public"."collection_styles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."collections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."commission_entries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "commission_entries_read" ON "public"."commission_entries" FOR SELECT TO "authenticated" USING (("public"."is_branch_member"("branch_id") AND (("user_id" = "auth"."uid"()) OR "public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]))));



ALTER TABLE "public"."commission_rules" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "commission_rules_read" ON "public"."commission_rules" FOR SELECT TO "authenticated" USING (("public"."is_branch_member"("branch_id") AND (("user_id" = "auth"."uid"()) OR "public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]))));



CREATE POLICY "commission_sales_read" ON "public"."sale_commissions" FOR SELECT TO "authenticated" USING (("public"."is_branch_member"("branch_id") AND (("user_id" = "auth"."uid"()) OR "public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]))));



CREATE POLICY "counter_read" ON "public"."online_order_events" FOR SELECT TO "authenticated" USING (("public"."is_counter_staff"() AND (EXISTS ( SELECT 1
   FROM "public"."online_orders" "o"
  WHERE (("o"."id" = "online_order_events"."order_id") AND "public"."is_branch_member"("o"."branch_id"))))));



CREATE POLICY "counter_read" ON "public"."online_order_lines" FOR SELECT TO "authenticated" USING (("public"."is_counter_staff"() AND (EXISTS ( SELECT 1
   FROM "public"."online_orders" "o"
  WHERE (("o"."id" = "online_order_lines"."order_id") AND "public"."is_branch_member"("o"."branch_id"))))));



CREATE POLICY "counter_read" ON "public"."online_orders" FOR SELECT TO "authenticated" USING (("public"."is_counter_staff"() AND "public"."is_branch_member"("branch_id")));



CREATE POLICY "counter_read" ON "public"."online_payments" FOR SELECT TO "authenticated" USING (("public"."is_counter_staff"() AND (EXISTS ( SELECT 1
   FROM "public"."online_orders" "o"
  WHERE (("o"."id" = "online_payments"."order_id") AND "public"."is_branch_member"("o"."branch_id"))))));



ALTER TABLE "public"."courier_returns" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "courier_returns_read" ON "public"."courier_returns" FOR SELECT TO "authenticated" USING (("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]) AND (EXISTS ( SELECT 1
   FROM "public"."online_orders" "o"
  WHERE (("o"."id" = "courier_returns"."order_id") AND "public"."is_branch_member"("o"."branch_id"))))));



ALTER TABLE "public"."customer_accounts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customer_accounts_back_office" ON "public"."customer_accounts" FOR SELECT TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



CREATE POLICY "customer_accounts_own_select" ON "public"."customer_accounts" FOR SELECT TO "authenticated" USING (("id" = "auth"."uid"()));



CREATE POLICY "customer_accounts_own_update" ON "public"."customer_accounts" FOR UPDATE TO "authenticated" USING (("id" = "auth"."uid"())) WITH CHECK (("id" = "auth"."uid"()));



ALTER TABLE "public"."customer_ledger" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customer_ledger_select" ON "public"."customer_ledger" FOR SELECT TO "authenticated" USING ("public"."is_counter_staff"());



ALTER TABLE "public"."customer_payments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customer_payments_select" ON "public"."customer_payments" FOR SELECT TO "authenticated" USING ("public"."is_counter_staff"());



ALTER TABLE "public"."customers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customers_delete_back_office" ON "public"."customers" FOR DELETE TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



CREATE POLICY "customers_insert_staff" ON "public"."customers" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_staff"() AND (COALESCE("credit_used", (0)::numeric) = (0)::numeric) AND (COALESCE("total_purchases", (0)::numeric) = (0)::numeric)));



CREATE POLICY "customers_select_staff" ON "public"."customers" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "customers_update_back_office" ON "public"."customers" FOR UPDATE TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



ALTER TABLE "public"."discount_code_redemptions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "discount_code_redemptions_read" ON "public"."discount_code_redemptions" FOR SELECT TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



ALTER TABLE "public"."discount_code_settings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "discount_code_settings_read" ON "public"."discount_code_settings" FOR SELECT TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



ALTER TABLE "public"."discount_codes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "discount_codes_read" ON "public"."discount_codes" FOR SELECT TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



ALTER TABLE "public"."discounts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "discounts_select_staff" ON "public"."discounts" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "discounts_write_back_office" ON "public"."discounts" TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



ALTER TABLE "public"."goods_receipt_lines" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "goods_receipt_lines_back_office" ON "public"."goods_receipt_lines" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."goods_receipts" "r"
  WHERE ("r"."id" = "goods_receipt_lines"."receipt_id"))));



ALTER TABLE "public"."goods_receipts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "goods_receipts_back_office" ON "public"."goods_receipts" FOR SELECT TO "authenticated" USING (("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]) AND "public"."is_branch_member"("branch_id")));



ALTER TABLE "public"."idempotency_keys" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."locations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "locations_select_members" ON "public"."locations" FOR SELECT TO "authenticated" USING ("public"."is_branch_member"("branch_id"));



CREATE POLICY "locations_write_admin" ON "public"."locations" TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['admin'::"text"]));



ALTER TABLE "public"."lookup_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "lookup_events_read" ON "public"."lookup_events" FOR SELECT TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



ALTER TABLE "public"."marketing_campaigns" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."marketing_consent_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "marketing_events_read" ON "public"."marketing_consent_events" FOR SELECT TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



CREATE POLICY "memberships_select" ON "public"."branch_memberships" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"])));



CREATE POLICY "memberships_write_admin" ON "public"."branch_memberships" TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['admin'::"text"]));



ALTER TABLE "public"."online_order_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."online_order_lines" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."online_orders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."online_payments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."online_return_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."online_return_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."online_return_photos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."online_return_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."payments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "payments_customer_collection_select" ON "public"."payments" FOR SELECT TO "authenticated" USING ((("customer_payment_id" IS NOT NULL) AND "public"."is_counter_staff"()));



CREATE POLICY "payments_select" ON "public"."payments" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."sales" "s"
  WHERE ("s"."id" = "payments"."sale_id"))));



ALTER TABLE "public"."product_images" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."product_styles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "product_styles_select_staff" ON "public"."product_styles" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "product_styles_write_back_office" ON "public"."product_styles" TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



ALTER TABLE "public"."product_variants" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "product_variants_select_staff" ON "public"."product_variants" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "product_variants_write_back_office" ON "public"."product_variants" TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



ALTER TABLE "public"."return_lines" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "return_lines_select" ON "public"."return_lines" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."returns" "r"
  WHERE ("r"."id" = "return_lines"."return_id"))));



ALTER TABLE "public"."returns" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "returns_select" ON "public"."returns" FOR SELECT TO "authenticated" USING (("public"."is_branch_member"("branch_id") AND ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]) OR ("created_by" = "auth"."uid"()))));



ALTER TABLE "public"."sale_commissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sale_lines" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sale_lines_select" ON "public"."sale_lines" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."sales" "s"
  WHERE ("s"."id" = "sale_lines"."sale_id"))));



ALTER TABLE "public"."sales" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_delete_drafts" ON "public"."sales" FOR DELETE TO "authenticated" USING ((("status" = 'draft'::"text") AND ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]) OR ("cashier_id" = "auth"."uid"()))));



CREATE POLICY "sales_select_own_or_back_office" ON "public"."sales" FOR SELECT TO "authenticated" USING (("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]) OR ("public"."is_staff"() AND ("cashier_id" = "auth"."uid"()))));



ALTER TABLE "public"."sales_tabs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_tabs_own" ON "public"."sales_tabs" TO "authenticated" USING (("public"."is_staff"() AND ("user_id" = "auth"."uid"()))) WITH CHECK (("public"."is_staff"() AND ("user_id" = "auth"."uid"())));



CREATE POLICY "sales_update_drafts" ON "public"."sales" FOR UPDATE TO "authenticated" USING ((("status" = 'draft'::"text") AND ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]) OR ("cashier_id" = "auth"."uid"())))) WITH CHECK (("status" = 'draft'::"text"));



ALTER TABLE "public"."settings_history" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "settings_history_select" ON "public"."settings_history" FOR SELECT TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



CREATE POLICY "settings_select_staff" ON "public"."app_settings" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



ALTER TABLE "public"."size_schemes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "size_schemes_select_staff" ON "public"."size_schemes" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "size_schemes_write_back_office" ON "public"."size_schemes" TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



CREATE POLICY "staff_read" ON "public"."collection_styles" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "staff_read" ON "public"."collections" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "staff_read" ON "public"."product_images" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



ALTER TABLE "public"."stock_balances" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "stock_balances_select_members" ON "public"."stock_balances" FOR SELECT TO "authenticated" USING ("public"."is_branch_member"("branch_id"));



ALTER TABLE "public"."stock_count_lines" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "stock_count_lines_select" ON "public"."stock_count_lines" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."stock_counts" "c"
  WHERE ("c"."id" = "stock_count_lines"."count_id"))));



ALTER TABLE "public"."stock_counts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "stock_counts_select_members" ON "public"."stock_counts" FOR SELECT TO "authenticated" USING ("public"."is_branch_member"("branch_id"));



ALTER TABLE "public"."stock_movements" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "stock_movements_select_back_office" ON "public"."stock_movements" FOR SELECT TO "authenticated" USING (("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]) AND "public"."is_branch_member"("branch_id")));



ALTER TABLE "public"."stock_reservations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "stock_reservations_select_members" ON "public"."stock_reservations" FOR SELECT TO "authenticated" USING ("public"."is_branch_member"("branch_id"));



ALTER TABLE "public"."suppliers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "suppliers_select_staff" ON "public"."suppliers" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "suppliers_write_back_office" ON "public"."suppliers" TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));



ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users_delete_admin" ON "public"."users" FOR DELETE TO "authenticated" USING (("public"."has_app_role"(ARRAY['admin'::"text"]) AND ("id" <> "auth"."uid"())));



CREATE POLICY "users_select_self_or_back_office" ON "public"."users" FOR SELECT TO "authenticated" USING ((("id" = "auth"."uid"()) OR "public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"])));



CREATE POLICY "users_update_self_or_admin" ON "public"."users" FOR UPDATE TO "authenticated" USING ((("id" = "auth"."uid"()) OR "public"."has_app_role"(ARRAY['admin'::"text"]))) WITH CHECK ((("id" = "auth"."uid"()) OR "public"."has_app_role"(ARRAY['admin'::"text"])));



ALTER TABLE "public"."variant_costs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "variant_costs_back_office" ON "public"."variant_costs" TO "authenticated" USING ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['admin'::"text", 'manager'::"text"]));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


-- Supabase grants every new object to the API roles by default. Start from no access,
-- then grant exactly what each table and function needs below.
REVOKE ALL ON ALL TABLES IN SCHEMA "public" FROM "anon", "authenticated", "service_role";
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "public" FROM "anon", "authenticated", "service_role";
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "public" FROM "anon", "authenticated", "service_role";
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "app_private" FROM "anon", "authenticated", "service_role";

GRANT USAGE ON SCHEMA "app_private" TO "authenticated";






GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "app_private"."catalog_angle_paths"("p_style" "uuid", "p_image" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "app_private"."return_photo_access"("p_path" "text", "p_upload" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "app_private"."return_photo_access"("p_path" "text", "p_upload" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "app_private"."return_request_json"("p_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "app_private"."valid_bike_specs"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "app_private"."valid_bike_specs"("p" "jsonb") TO "authenticated";











































































































































































REVOKE ALL ON FUNCTION "public"."adjust_customer_balance"("p_customer" "uuid", "p_amount" numeric, "p_reason" "text", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."adjust_customer_balance"("p_customer" "uuid", "p_amount" numeric, "p_reason" "text", "p_request_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."adjust_customer_balance"("p_customer" "uuid", "p_amount" numeric, "p_reason" "text", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."adjust_stock"("p_variant_id" "uuid", "p_location_id" "uuid", "p_quantity" numeric, "p_reason" "text", "p_movement_type" "text", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."adjust_stock"("p_variant_id" "uuid", "p_location_id" "uuid", "p_quantity" numeric, "p_reason" "text", "p_movement_type" "text", "p_request_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."adjust_stock"("p_variant_id" "uuid", "p_location_id" "uuid", "p_quantity" numeric, "p_reason" "text", "p_movement_type" "text", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."advance_online_order"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."advance_online_order"("p" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."advance_online_order"("p" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."apply_customer_ledger"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."apply_customer_ledger"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."approve_stock_count"("p_count_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."approve_stock_count"("p_count_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."approve_stock_count"("p_count_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."auto_generate_invoice_number"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."auto_generate_invoice_number"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."backfill_customer_ledger"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."backfill_customer_ledger"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_my_online_order"("p_order_no" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_my_online_order"("p_order_no" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."cancel_my_online_order"("p_order_no" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."cancel_online_order"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_online_order"("p" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."cancel_online_order"("p" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."cancel_online_order_internal"("p_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_online_order_internal"("p_id" "uuid", "p_reason" "text") TO "service_role";



GRANT ALL ON TABLE "public"."stock_counts" TO "authenticated";
GRANT ALL ON TABLE "public"."stock_counts" TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_stock_count"("p_count_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_stock_count"("p_count_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_stock_count"("p_count_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."cash_session_detail"("p_session_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cash_session_detail"("p_session_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cash_session_detail"("p_session_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."cash_session_summary"("p_session_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cash_session_summary"("p_session_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cash_session_summary"("p_session_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."catalog_collections"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."catalog_collections"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."catalog_collections"() TO "service_role";
GRANT ALL ON FUNCTION "public"."catalog_collections"() TO "anon";



REVOKE ALL ON FUNCTION "public"."catalog_facets"("p_collection" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."catalog_facets"("p_collection" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."catalog_facets"("p_collection" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."catalog_facets"("p_collection" "text") TO "anon";



REVOKE ALL ON FUNCTION "public"."catalog_list"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."catalog_list"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."catalog_list"("p" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."catalog_list"("p" "jsonb") TO "anon";



REVOKE ALL ON FUNCTION "public"."catalog_policy"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."catalog_policy"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."catalog_policy"() TO "service_role";
GRANT ALL ON FUNCTION "public"."catalog_policy"() TO "anon";



REVOKE ALL ON FUNCTION "public"."catalog_product"("p_slug" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."catalog_product"("p_slug" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."catalog_product"("p_slug" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."catalog_product"("p_slug" "text") TO "anon";



REVOKE ALL ON FUNCTION "public"."catalog_style_rows"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."catalog_style_rows"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."close_cash_session"("p_counted_cash" numeric, "p_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."close_cash_session"("p_counted_cash" numeric, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."close_cash_session"("p_counted_cash" numeric, "p_notes" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."close_cash_session_internal"("p_session_id" "uuid", "p_counted" numeric, "p_notes" "text", "p_closed_by" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."close_cash_session_internal"("p_session_id" "uuid", "p_counted" numeric, "p_notes" "text", "p_closed_by" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."close_online_reservations"("p_order" "uuid", "p_status" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."close_online_reservations"("p_order" "uuid", "p_status" "text") TO "service_role";



GRANT ALL ON TABLE "public"."stock_reservations" TO "authenticated";
GRANT ALL ON TABLE "public"."stock_reservations" TO "service_role";



REVOKE ALL ON FUNCTION "public"."close_reservation"("p_reservation_id" "uuid", "p_status" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."close_reservation"("p_reservation_id" "uuid", "p_status" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."collect_cod_payment"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."collect_cod_payment"("p" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."collect_cod_payment"("p" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."commission_branches"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."commission_branches"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."commission_branches"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."commission_overview"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."commission_overview"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."commission_overview"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."commission_sellers"("p_branch" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."commission_sellers"("p_branch" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."commission_sellers"("p_branch" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_online_order"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_online_order"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_online_order"("p" "jsonb") TO "service_role";



GRANT ALL ON TABLE "public"."returns" TO "authenticated";
GRANT ALL ON TABLE "public"."returns" TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_return"("p" "jsonb", "p_refund_method" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_return"("p" "jsonb", "p_refund_method" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_return_request"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_return_request"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_return_request"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."current_app_role"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_app_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_app_role"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."current_cash_session"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_cash_session"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_cash_session"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."customer_discount_codes"("p_customer_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."customer_discount_codes"("p_customer_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."customer_discount_codes"("p_customer_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."customer_statement"("p_customer" "uuid", "p_from" "date", "p_to" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."customer_statement"("p_customer" "uuid", "p_from" "date", "p_to" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."customer_statement"("p_customer" "uuid", "p_from" "date", "p_to" "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."customers_with_balance"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."customers_with_balance"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."customers_with_balance"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."default_branch_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."default_branch_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."default_branch_id"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."delete_business_lookup"("p_kind" "text", "p_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."delete_business_lookup"("p_kind" "text", "p_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_business_lookup"("p_kind" "text", "p_id" "text") TO "service_role";



GRANT ALL ON TABLE "public"."discount_codes" TO "authenticated";
GRANT ALL ON TABLE "public"."discount_codes" TO "service_role";



REVOKE ALL ON FUNCTION "public"."discount_code_json"("p_code" "public"."discount_codes") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."discount_code_json"("p_code" "public"."discount_codes") TO "service_role";



REVOKE ALL ON FUNCTION "public"."expire_online_orders"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."expire_online_orders"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."expire_stock_reservations"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."expire_stock_reservations"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."find_sale_for_return"("p_invoice" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."find_sale_for_return"("p_invoice" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."find_sale_for_return"("p_invoice" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."force_close_cash_session"("p_session_id" "uuid", "p_counted_cash" numeric, "p_notes" "text", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."force_close_cash_session"("p_session_id" "uuid", "p_counted_cash" numeric, "p_notes" "text", "p_request_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."force_close_cash_session"("p_session_id" "uuid", "p_counted_cash" numeric, "p_notes" "text", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."generate_invoice_number"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."generate_invoice_number"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."guard_cash_variance_alert"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."guard_cash_variance_alert"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."guard_customer_balance"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."guard_customer_balance"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."handle_auth_user_marked_staff"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_auth_user_marked_staff"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."handle_new_auth_user"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."has_app_role"("roles" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."has_app_role"("roles" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_app_role"("roles" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."idempotency_begin"("p_key" "uuid", "p_operation" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."idempotency_begin"("p_key" "uuid", "p_operation" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."idempotency_finish"("p_key" "uuid", "p_result" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."idempotency_finish"("p_key" "uuid", "p_result" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."import_opening_balances"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."import_opening_balances"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."import_opening_balances"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."initiate_online_payment"("p_order_no" "text", "p_account_id" "uuid", "p_provider" "text", "p_provider_ref" "text", "p_method" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."initiate_online_payment"("p_order_no" "text", "p_account_id" "uuid", "p_provider" "text", "p_provider_ref" "text", "p_method" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_branch_member"("p_branch_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_branch_member"("p_branch_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_branch_member"("p_branch_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_counter_staff"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_counter_staff"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_counter_staff"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_staff"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_staff"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_staff"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_website_customer"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_website_customer"() TO "service_role";
GRANT ALL ON FUNCTION "public"."is_website_customer"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."issue_customer_welcome_code"("p_customer_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."issue_customer_welcome_code"("p_customer_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."issue_customer_welcome_code"("p_customer_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."issue_welcome_code"("p_customer_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."issue_welcome_code"("p_customer_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."issue_welcome_code_for_new_customer"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."issue_welcome_code_for_new_customer"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."limit_open_online_orders"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."limit_open_online_orders"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."link_customer_account"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."link_customer_account"() TO "service_role";
GRANT ALL ON FUNCTION "public"."link_customer_account"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."list_business_lookups"("p_kind" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_business_lookups"("p_kind" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_business_lookups"("p_kind" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."list_cash_sessions"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_cash_sessions"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_cash_sessions"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."list_online_orders"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_online_orders"("p" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."list_online_orders"("p" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."list_return_requests"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_return_requests"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_return_requests"("p" "jsonb") TO "service_role";



GRANT ALL ON TABLE "public"."stock_balances" TO "authenticated";
GRANT ALL ON TABLE "public"."stock_balances" TO "service_role";



REVOKE ALL ON FUNCTION "public"."lock_stock_balance"("p_location_id" "uuid", "p_variant_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."lock_stock_balance"("p_location_id" "uuid", "p_variant_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."lookup_usage"("p_kind" "text", "p_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."lookup_usage"("p_kind" "text", "p_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_online_order_paid"("p_order_no" "text", "p_provider" "text", "p_provider_ref" "text", "p_amount" numeric, "p_method" "text", "p_raw" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_online_order_paid"("p_order_no" "text", "p_provider" "text", "p_provider_ref" "text", "p_amount" numeric, "p_method" "text", "p_raw" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."marketing_audience"("p_channel" "text", "p_query" "text", "p_limit" integer, "p_offset" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."marketing_audience"("p_channel" "text", "p_query" "text", "p_limit" integer, "p_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."marketing_audience"("p_channel" "text", "p_query" "text", "p_limit" integer, "p_offset" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."my_online_order"("p_order_no" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."my_online_order"("p_order_no" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."my_online_order"("p_order_no" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."my_online_orders"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."my_online_orders"() TO "service_role";
GRANT ALL ON FUNCTION "public"."my_online_orders"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."my_return_request"("p_order_no" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."my_return_request"("p_order_no" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."my_return_request"("p_order_no" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."needs_bootstrap"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."needs_bootstrap"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."needs_bootstrap"() TO "service_role";
GRANT ALL ON FUNCTION "public"."needs_bootstrap"() TO "anon";



REVOKE ALL ON FUNCTION "public"."new_discount_code"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."new_discount_code"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."normalize_customer_phone"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."normalize_customer_phone"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."normalize_discount_code"("p_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."normalize_discount_code"("p_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."normalize_phone"("p_phone" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."normalize_phone"("p_phone" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."normalize_phone"("p_phone" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."online_order_detail"("p_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."online_order_detail"("p_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."online_order_detail"("p_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."online_order_public"("p_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."online_order_public"("p_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."open_cash_session"("p_opening_float" numeric, "p_location_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."open_cash_session"("p_opening_float" numeric, "p_location_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."open_cash_session"("p_opening_float" numeric, "p_location_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."post_customer_payment"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."post_customer_payment"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."post_customer_payment"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."post_exchange"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."post_exchange"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."post_exchange"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."post_exchange_without_commission"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."post_exchange_without_commission"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."post_goods_receipt"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."post_goods_receipt"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."post_goods_receipt"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."post_return"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."post_return"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."post_return"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."post_sale"("p_request" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."post_sale"("p_request" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."post_sale"("p_request" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."post_sale_without_commission"("p_request" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."post_sale_without_commission"("p_request" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."post_stock_movement"("p_location_id" "uuid", "p_variant_id" "uuid", "p_quantity" numeric, "p_movement_type" "text", "p_channel" "text", "p_reference_type" "text", "p_reference_id" "uuid", "p_unit_cost" numeric, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."post_stock_movement"("p_location_id" "uuid", "p_variant_id" "uuid", "p_quantity" numeric, "p_movement_type" "text", "p_channel" "text", "p_reference_type" "text", "p_reference_id" "uuid", "p_unit_cost" numeric, "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."prepare_return_photo"("p_id" "uuid", "p_photo_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prepare_return_photo"("p_id" "uuid", "p_photo_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."prepare_return_photo"("p_id" "uuid", "p_photo_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."prevent_ledger_changes"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prevent_ledger_changes"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."promotion_item_matches"("p_ref" "text", "p_variant_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."promotion_item_matches"("p_ref" "text", "p_variant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."promotion_item_matches"("p_ref" "text", "p_variant_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."protect_customer_account_columns"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."protect_customer_account_columns"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."protect_user_privileged_columns"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."protect_user_privileged_columns"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."publish_style"("p_style" "uuid", "p_published" boolean, "p_dry_run" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."publish_style"("p_style" "uuid", "p_published" boolean, "p_dry_run" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."publish_style"("p_style" "uuid", "p_published" boolean, "p_dry_run" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."quote_online_order"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."quote_online_order"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."quote_online_order"("p" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."quote_online_order"("p" "jsonb") TO "anon";



REVOKE ALL ON FUNCTION "public"."quote_sale"("p_request" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."quote_sale"("p_request" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."quote_sale"("p_request" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."receive_cod_parcel_return"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."receive_cod_parcel_return"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."receive_cod_parcel_return"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_cash_movement"("p_amount" numeric, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_cash_movement"("p_amount" numeric, "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_cash_movement"("p_amount" numeric, "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_cash_payment"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_cash_payment"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_commission_payout"("p_branch" "uuid", "p_user" "uuid", "p_amount" numeric, "p_note" "text", "p_request" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_commission_payout"("p_branch" "uuid", "p_user" "uuid", "p_amount" numeric, "p_note" "text", "p_request" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_commission_payout"("p_branch" "uuid", "p_user" "uuid", "p_amount" numeric, "p_note" "text", "p_request" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_marketing_consent"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_marketing_consent"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_online_payment_event"("p_order_no" "text", "p_provider" "text", "p_provider_ref" "text", "p_amount" numeric, "p_method" "text", "p_status" "text", "p_raw" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_online_payment_event"("p_order_no" "text", "p_provider" "text", "p_provider_ref" "text", "p_amount" numeric, "p_method" "text", "p_status" "text", "p_raw" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_online_refund"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_online_refund"("p" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."record_online_refund"("p" "jsonb") TO "authenticated";



GRANT ALL ON TABLE "public"."stock_count_lines" TO "authenticated";
GRANT ALL ON TABLE "public"."stock_count_lines" TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_stock_count"("p_count_id" "uuid", "p_variant_id" "uuid", "p_counted" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_stock_count"("p_count_id" "uuid", "p_variant_id" "uuid", "p_counted" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_stock_count"("p_count_id" "uuid", "p_variant_id" "uuid", "p_counted" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."redeem_sale_discount_code"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."redeem_sale_discount_code"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."register_catalog_lookups"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."register_catalog_lookups"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."release_reservation"("p_reservation_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."release_reservation"("p_reservation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."release_reservation"("p_reservation_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."reply_return_request"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reply_return_request"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reply_return_request"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."report_line_activity"("p_from" "date", "p_to" "date", "p_branch" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."report_line_activity"("p_from" "date", "p_to" "date", "p_branch" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."report_sales_summary"("p_from" "date", "p_to" "date", "p_branch" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."report_sales_summary"("p_from" "date", "p_to" "date", "p_branch" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."report_sales_summary"("p_from" "date", "p_to" "date", "p_branch" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."report_size_color_matrix"("p_from" "date", "p_to" "date", "p_branch" "uuid", "p_style" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."report_size_color_matrix"("p_from" "date", "p_to" "date", "p_branch" "uuid", "p_style" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."report_size_color_matrix"("p_from" "date", "p_to" "date", "p_branch" "uuid", "p_style" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."report_staff_sales"("p_from" "date", "p_to" "date", "p_branch" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."report_staff_sales"("p_from" "date", "p_to" "date", "p_branch" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."report_staff_sales"("p_from" "date", "p_to" "date", "p_branch" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."report_tenders"("p_from" "date", "p_to" "date", "p_branch" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."report_tenders"("p_from" "date", "p_to" "date", "p_branch" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."report_tenders"("p_from" "date", "p_to" "date", "p_branch" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."report_top_items"("p_from" "date", "p_to" "date", "p_branch" "uuid", "p_group" "text", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."report_top_items"("p_from" "date", "p_to" "date", "p_branch" "uuid", "p_group" "text", "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."report_top_items"("p_from" "date", "p_to" "date", "p_branch" "uuid", "p_group" "text", "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."report_tz"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."report_tz"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."report_tz"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."request_begin"("p_key" "uuid", "p_operation" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."request_begin"("p_key" "uuid", "p_operation" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."require_online_service"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."require_online_service"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."require_website_customer"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."require_website_customer"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."reserve_stock"("p_variant_id" "uuid", "p_location_id" "uuid", "p_quantity" numeric, "p_channel" "text", "p_reference_type" "text", "p_reference_id" "uuid", "p_expires_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reserve_stock"("p_variant_id" "uuid", "p_location_id" "uuid", "p_quantity" numeric, "p_channel" "text", "p_reference_type" "text", "p_reference_id" "uuid", "p_expires_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."reserve_stock"("p_variant_id" "uuid", "p_location_id" "uuid", "p_quantity" numeric, "p_channel" "text", "p_reference_type" "text", "p_reference_id" "uuid", "p_expires_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."reverse_sale_commission"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reverse_sale_commission"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."review_return_request"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."review_return_request"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."review_return_request"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."sale_detail"("p_sale_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sale_detail"("p_sale_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sale_detail"("p_sale_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."sale_returnable"("p_sale_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sale_returnable"("p_sale_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sale_returnable"("p_sale_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."sanitize_card_details"("details" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sanitize_card_details"("details" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_business_lookup"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_business_lookup"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_business_lookup"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_collection"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_collection"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_collection"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_commission_rule"("p_branch" "uuid", "p_user" "uuid", "p_kind" "text", "p_rate" numeric, "p_enabled" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_commission_rule"("p_branch" "uuid", "p_user" "uuid", "p_kind" "text", "p_rate" numeric, "p_enabled" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_commission_rule"("p_branch" "uuid", "p_user" "uuid", "p_kind" "text", "p_rate" numeric, "p_enabled" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_discount_code"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_discount_code"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_discount_code"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_discount_code_settings"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_discount_code_settings"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_discount_code_settings"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_product_images"("p_style" "uuid", "p_images" "jsonb", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_product_images"("p_style" "uuid", "p_images" "jsonb", "p_request_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_product_images"("p_style" "uuid", "p_images" "jsonb", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_style"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_style"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_style"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_style_web_details"("p_style" "uuid", "p" "jsonb", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_style_web_details"("p_style" "uuid", "p" "jsonb", "p_request_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_style_web_details"("p_style" "uuid", "p" "jsonb", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."search_sales"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."search_sales"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_sales"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."search_variants"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."search_variants"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_variants"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_collection_styles"("p_collection" "uuid", "p_style_ids" "uuid"[], "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_collection_styles"("p_collection" "uuid", "p_style_ids" "uuid"[], "p_request_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_collection_styles"("p_collection" "uuid", "p_style_ids" "uuid"[], "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."staff_link_customer_account"("p_account" "uuid", "p_customer" "uuid", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_link_customer_account"("p_account" "uuid", "p_customer" "uuid", "p_request_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."staff_link_customer_account"("p_account" "uuid", "p_customer" "uuid", "p_request_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."staff_return_request"("p_order_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_return_request"("p_order_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."staff_return_request"("p_order_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."start_stock_count"("p_location_id" "uuid", "p_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."start_stock_count"("p_location_id" "uuid", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."start_stock_count"("p_location_id" "uuid", "p_notes" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_customer_stats"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_customer_stats"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_online_tracking"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_online_tracking"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_online_tracking"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_settings"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_settings"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_settings"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_updated_at_column"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."variant_by_code"("p_code" "text", "p_location" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."variant_by_code"("p_code" "text", "p_location" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."variant_by_code"("p_code" "text", "p_location" "uuid") TO "service_role";
























GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."app_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."app_settings" TO "service_role";



GRANT ALL ON TABLE "public"."barcodes" TO "authenticated";
GRANT ALL ON TABLE "public"."barcodes" TO "service_role";



GRANT ALL ON TABLE "public"."branch_memberships" TO "authenticated";
GRANT ALL ON TABLE "public"."branch_memberships" TO "service_role";



GRANT ALL ON TABLE "public"."branches" TO "authenticated";
GRANT ALL ON TABLE "public"."branches" TO "service_role";



GRANT ALL ON TABLE "public"."business_lookups" TO "service_role";
GRANT SELECT ON TABLE "public"."business_lookups" TO "authenticated";



GRANT ALL ON TABLE "public"."cash_movements" TO "authenticated";
GRANT ALL ON TABLE "public"."cash_movements" TO "service_role";



GRANT ALL ON SEQUENCE "public"."cash_movements_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."cash_movements_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."cash_session_no_seq" TO "service_role";



GRANT ALL ON TABLE "public"."cash_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."cash_sessions" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."categories" TO "authenticated";
GRANT ALL ON TABLE "public"."categories" TO "service_role";



GRANT ALL ON TABLE "public"."collection_styles" TO "service_role";
GRANT SELECT ON TABLE "public"."collection_styles" TO "authenticated";



GRANT ALL ON TABLE "public"."collections" TO "service_role";
GRANT SELECT ON TABLE "public"."collections" TO "authenticated";



GRANT ALL ON TABLE "public"."commission_entries" TO "service_role";
GRANT SELECT ON TABLE "public"."commission_entries" TO "authenticated";



GRANT ALL ON TABLE "public"."commission_rules" TO "service_role";
GRANT SELECT ON TABLE "public"."commission_rules" TO "authenticated";



GRANT ALL ON TABLE "public"."courier_returns" TO "service_role";
GRANT SELECT ON TABLE "public"."courier_returns" TO "authenticated";



GRANT ALL ON TABLE "public"."customer_accounts" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_accounts" TO "service_role";



GRANT ALL ON TABLE "public"."customer_ledger" TO "service_role";
GRANT SELECT ON TABLE "public"."customer_ledger" TO "authenticated";



GRANT ALL ON SEQUENCE "public"."customer_ledger_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."customer_payment_no_seq" TO "service_role";



GRANT ALL ON TABLE "public"."customer_payments" TO "service_role";
GRANT SELECT ON TABLE "public"."customer_payments" TO "authenticated";



GRANT ALL ON TABLE "public"."customers" TO "authenticated";
GRANT ALL ON TABLE "public"."customers" TO "service_role";



GRANT ALL ON TABLE "public"."discount_code_redemptions" TO "authenticated";
GRANT ALL ON TABLE "public"."discount_code_redemptions" TO "service_role";



GRANT ALL ON TABLE "public"."discount_code_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."discount_code_settings" TO "service_role";



GRANT ALL ON TABLE "public"."discounts" TO "authenticated";
GRANT ALL ON TABLE "public"."discounts" TO "service_role";



GRANT ALL ON TABLE "public"."goods_receipt_lines" TO "authenticated";
GRANT ALL ON TABLE "public"."goods_receipt_lines" TO "service_role";



GRANT ALL ON SEQUENCE "public"."goods_receipt_no_seq" TO "service_role";



GRANT ALL ON TABLE "public"."goods_receipts" TO "authenticated";
GRANT ALL ON TABLE "public"."goods_receipts" TO "service_role";



GRANT ALL ON TABLE "public"."idempotency_keys" TO "authenticated";
GRANT ALL ON TABLE "public"."idempotency_keys" TO "service_role";



GRANT ALL ON TABLE "public"."locations" TO "authenticated";
GRANT ALL ON TABLE "public"."locations" TO "service_role";



GRANT ALL ON TABLE "public"."lookup_events" TO "service_role";
GRANT SELECT ON TABLE "public"."lookup_events" TO "authenticated";



GRANT ALL ON TABLE "public"."marketing_campaigns" TO "authenticated";
GRANT ALL ON TABLE "public"."marketing_campaigns" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."marketing_consent_events" TO "authenticated";
GRANT ALL ON TABLE "public"."marketing_consent_events" TO "service_role";



GRANT ALL ON SEQUENCE "public"."marketing_consent_events_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."marketing_consent_events_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."online_order_events" TO "service_role";
GRANT SELECT ON TABLE "public"."online_order_events" TO "authenticated";



GRANT ALL ON TABLE "public"."online_order_lines" TO "service_role";
GRANT SELECT ON TABLE "public"."online_order_lines" TO "authenticated";



GRANT ALL ON SEQUENCE "public"."online_order_no_seq" TO "service_role";



GRANT ALL ON TABLE "public"."online_orders" TO "service_role";
GRANT SELECT ON TABLE "public"."online_orders" TO "authenticated";



GRANT ALL ON TABLE "public"."online_payments" TO "service_role";
GRANT SELECT ON TABLE "public"."online_payments" TO "authenticated";



GRANT ALL ON TABLE "public"."online_return_events" TO "service_role";



GRANT ALL ON TABLE "public"."online_return_items" TO "service_role";



GRANT ALL ON TABLE "public"."online_return_photos" TO "service_role";



GRANT ALL ON TABLE "public"."online_return_requests" TO "service_role";



GRANT ALL ON TABLE "public"."payments" TO "authenticated";
GRANT ALL ON TABLE "public"."payments" TO "service_role";



GRANT ALL ON TABLE "public"."product_images" TO "service_role";
GRANT SELECT ON TABLE "public"."product_images" TO "authenticated";



GRANT ALL ON TABLE "public"."product_styles" TO "authenticated";
GRANT ALL ON TABLE "public"."product_styles" TO "service_role";



GRANT ALL ON TABLE "public"."product_variants" TO "authenticated";
GRANT ALL ON TABLE "public"."product_variants" TO "service_role";



GRANT ALL ON TABLE "public"."public_catalog" TO "authenticated";
GRANT ALL ON TABLE "public"."public_catalog" TO "service_role";
GRANT SELECT ON TABLE "public"."public_catalog" TO "anon";



GRANT ALL ON TABLE "public"."return_lines" TO "authenticated";
GRANT ALL ON TABLE "public"."return_lines" TO "service_role";



GRANT ALL ON SEQUENCE "public"."return_no_seq" TO "service_role";



GRANT ALL ON TABLE "public"."sale_commissions" TO "service_role";
GRANT SELECT ON TABLE "public"."sale_commissions" TO "authenticated";



GRANT ALL ON TABLE "public"."sale_lines" TO "authenticated";
GRANT ALL ON TABLE "public"."sale_lines" TO "service_role";



GRANT ALL ON TABLE "public"."sales" TO "authenticated";
GRANT ALL ON TABLE "public"."sales" TO "service_role";



GRANT ALL ON TABLE "public"."sales_tabs" TO "authenticated";
GRANT ALL ON TABLE "public"."sales_tabs" TO "service_role";



GRANT ALL ON TABLE "public"."settings_history" TO "service_role";
GRANT SELECT ON TABLE "public"."settings_history" TO "authenticated";



GRANT ALL ON SEQUENCE "public"."settings_history_id_seq" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."size_schemes" TO "authenticated";
GRANT ALL ON TABLE "public"."size_schemes" TO "service_role";



GRANT ALL ON SEQUENCE "public"."stock_count_no_seq" TO "service_role";



GRANT ALL ON TABLE "public"."stock_movements" TO "authenticated";
GRANT ALL ON TABLE "public"."stock_movements" TO "service_role";



GRANT ALL ON SEQUENCE "public"."stock_movements_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."stock_movements_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."suppliers" TO "authenticated";
GRANT ALL ON TABLE "public"."suppliers" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



GRANT ALL ON TABLE "public"."variant_costs" TO "authenticated";
GRANT ALL ON TABLE "public"."variant_costs" TO "service_role";



GRANT ALL ON TABLE "public"."variant_stock" TO "authenticated";
GRANT ALL ON TABLE "public"."variant_stock" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";

































-- Future objects are not reachable by signed-out visitors unless granted explicitly.
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM "anon";

-- ---------------------------------------------------------------------------
-- Objects outside the public schema
-- ---------------------------------------------------------------------------

-- Staff and website accounts are created from Supabase Auth sign-ups.
CREATE OR REPLACE TRIGGER "on_auth_user_created" AFTER INSERT ON "auth"."users"
 FOR EACH ROW EXECUTE FUNCTION "public"."handle_new_auth_user"();
CREATE OR REPLACE TRIGGER "on_auth_user_marked_staff" AFTER UPDATE OF "raw_app_meta_data" ON "auth"."users"
 FOR EACH ROW EXECUTE FUNCTION "public"."handle_auth_user_marked_staff"();

-- Storage: public product photos and private return evidence photos.
INSERT INTO "storage"."buckets" ("id", "name", "public", "file_size_limit", "allowed_mime_types") VALUES
 ('product-images', 'product-images', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp']),
 ('return-evidence', 'return-evidence', false, 5242880, ARRAY['image/webp'])
ON CONFLICT ("id") DO UPDATE SET "public" = EXCLUDED."public", "file_size_limit" = EXCLUDED."file_size_limit",
 "allowed_mime_types" = EXCLUDED."allowed_mime_types";

CREATE POLICY "product_images_read" ON "storage"."objects" FOR SELECT TO "anon", "authenticated"
 USING ("bucket_id" = 'product-images');
CREATE POLICY "product_images_insert" ON "storage"."objects" FOR INSERT TO "authenticated"
 WITH CHECK ("bucket_id" = 'product-images' AND "public"."has_app_role"(ARRAY['admin', 'manager']));
CREATE POLICY "product_images_update" ON "storage"."objects" FOR UPDATE TO "authenticated"
 USING ("bucket_id" = 'product-images' AND "public"."has_app_role"(ARRAY['admin', 'manager']))
 WITH CHECK ("bucket_id" = 'product-images' AND "public"."has_app_role"(ARRAY['admin', 'manager']));
CREATE POLICY "product_images_delete" ON "storage"."objects" FOR DELETE TO "authenticated"
 USING ("bucket_id" = 'product-images' AND "public"."has_app_role"(ARRAY['admin', 'manager']));
CREATE POLICY "return_evidence_read" ON "storage"."objects" FOR SELECT TO "authenticated"
 USING ("bucket_id" = 'return-evidence' AND "app_private"."return_photo_access"("name", false));
CREATE POLICY "return_evidence_upload" ON "storage"."objects" FOR INSERT TO "authenticated"
 WITH CHECK ("bucket_id" = 'return-evidence' AND "app_private"."return_photo_access"("name", true));

-- Release unpaid online reservations every minute.
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM "cron"."job" WHERE "jobname" = 'expire-online-orders') THEN
  PERFORM "cron"."schedule"('expire-online-orders', '* * * * *', 'SELECT public.expire_online_orders()');
 END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Starting data
-- ---------------------------------------------------------------------------

INSERT INTO "public"."app_settings" ("store_name") VALUES ('Bicycles.pk');
INSERT INTO "public"."discount_code_settings" ("id") VALUES (true);

WITH "branch" AS (
 INSERT INTO "public"."branches" ("code", "name") VALUES ('MAIN', 'Main store') RETURNING "id"
)
INSERT INTO "public"."locations" ("branch_id", "code", "name", "kind")
SELECT "branch"."id", "l"."code", "l"."name", "l"."kind" FROM "branch",
 (VALUES ('FLOOR', 'Shop floor', 'shop_floor'), ('STOCK', 'Stockroom', 'stockroom'), ('ONLINE', 'Online orders', 'online'))
 AS "l"("code", "name", "kind");

INSERT INTO "public"."size_schemes" ("code", "name", "sizes") VALUES
 ('FRAME', 'Frame sizes', ARRAY['XS', 'S', 'M', 'L', 'XL']),
 ('WHEEL', 'Wheel sizes', ARRAY['12"', '14"', '16"', '20"', '24"', '26"', '27.5"', '29"', '700c']),
 ('ONE', 'One size', ARRAY['One size']);
