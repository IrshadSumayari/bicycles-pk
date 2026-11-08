-- Fail closed for the COD-only launch. Keep existing role, idempotency and fabric behavior.
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS online_card_enabled BOOLEAN NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.update_settings(p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_old public.app_settings; v_new public.app_settings; v_key TEXT; v_max INT;
 v_request UUID; v_existing JSONB;
 v_keys TEXT[]:=ARRAY['store_name','store_address','store_phone','store_email','store_logo','tax_rate','currency','interface_mode','auto_backup','receipt_printer','theme','invoice_prefix','invoice_counter','max_cashier_discount_percent','return_window_days','cash_variance_alert','min_tailoring_deposit_percent','receipt_header','receipt_footer','ntn','strn','online_hold_minutes','delivery_fee','free_delivery_over','cod_enabled','online_card_enabled','cod_max_total','online_max_pending_orders','online_max_open_cod_orders'];
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
   IF v_key IN ('tax_rate','max_cashier_discount_percent','return_window_days','cash_variance_alert','min_tailoring_deposit_percent','invoice_counter','online_hold_minutes','delivery_fee','free_delivery_over','cod_max_total','online_max_pending_orders','online_max_open_cod_orders') THEN
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
 IF p ? 'min_tailoring_deposit_percent' AND (p->>'min_tailoring_deposit_percent')::numeric NOT BETWEEN 0 AND 100 THEN RAISE EXCEPTION 'Minimum deposit must be between 0 and 100 percent'; END IF;
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
   min_tailoring_deposit_percent=v_new.min_tailoring_deposit_percent,receipt_header=v_new.receipt_header,receipt_footer=v_new.receipt_footer,ntn=v_new.ntn,strn=v_new.strn,online_hold_minutes=v_new.online_hold_minutes,delivery_fee=v_new.delivery_fee,free_delivery_over=v_new.free_delivery_over,cod_enabled=v_new.cod_enabled,online_card_enabled=v_new.online_card_enabled,cod_max_total=v_new.cod_max_total,online_max_pending_orders=v_new.online_max_pending_orders,online_max_open_cod_orders=v_new.online_max_open_cod_orders
 WHERE id=v_old.id RETURNING * INTO v_new;
 INSERT INTO public.settings_history(old,new) VALUES(to_jsonb(v_old),to_jsonb(v_new));
 RETURN public.idempotency_finish(v_request,to_jsonb(v_new));
END; $$;

CREATE OR REPLACE FUNCTION public.quote_online_order(p JSONB) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE s public.app_settings;item JSONB;v RECORD;qty NUMERIC;net NUMERIC(14,2);tax NUMERIC(14,2);sub NUMERIC(14,2):=0;taxes NUMERIC(14,2):=0;fee NUMERIC(14,2);total NUMERIC(14,2);lines JSONB:='[]';name TEXT;available BOOLEAN;cut_m NUMERIC;pieces NUMERIC;cut TEXT;
BEGIN
 IF p->>'fulfilment' IS NULL OR p->>'fulfilment' NOT IN ('pickup','delivery') THEN RAISE EXCEPTION 'Choose pickup or delivery'; END IF;
 IF jsonb_typeof(p->'lines') IS DISTINCT FROM 'array' OR jsonb_array_length(p->'lines') NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'Add between one and fifty items'; END IF;
 IF (SELECT count(*) FROM jsonb_array_elements(p->'lines'))<>(SELECT count(DISTINCT (x->>'variant_id',coalesce(x->>'cut',''))) FROM jsonb_array_elements(p->'lines') x) THEN RAISE EXCEPTION 'Combine duplicate items into one line'; END IF;
 SELECT * INTO s FROM public.app_settings ORDER BY created_at,id LIMIT 1;
 IF s.id IS NULL THEN RAISE EXCEPTION 'Store settings not found'; END IF;
 FOR item IN SELECT jsonb_array_elements(p->'lines') LOOP
  IF jsonb_typeof(item->'quantity') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Enter a quantity'; END IF;
  qty:=(item->>'quantity')::numeric;
  SELECT c.*,ps.taxable,ps.track_inventory,ps.fabric_cuts INTO v FROM public.public_catalog c JOIN public.product_styles ps ON ps.id=c.style_id WHERE c.variant_id=nullif(item->>'variant_id','')::uuid AND c.price>0;
  IF NOT FOUND THEN
   SELECT ps.name INTO name FROM public.product_variants pv JOIN public.product_styles ps ON ps.id=pv.style_id WHERE pv.id=nullif(item->>'variant_id','')::uuid;
   RAISE EXCEPTION '% is not available online',coalesce(name,'That item');
  END IF;
  IF v.unit='meter' THEN
   IF qty NOT BETWEEN 0.5 AND 50 OR mod(qty,0.25)<>0 THEN RAISE EXCEPTION 'Choose metres from 0.5 to 50 in steps of 0.25'; END IF;
  ELSIF qty NOT BETWEEN 1 AND 10 OR qty<>trunc(qty) THEN RAISE EXCEPTION 'Choose a whole quantity from 1 to 10'; END IF;
  cut:=NULL;pieces:=NULL;
  IF item ? 'cut' THEN
   IF jsonb_typeof(item->'cut') IS DISTINCT FROM 'string' OR v.unit<>'meter' THEN RAISE EXCEPTION 'Choose an available fabric cut'; END IF;
   cut:=item->>'cut';SELECT (c->>'meters')::numeric INTO cut_m FROM jsonb_array_elements(v.fabric_cuts) c WHERE c->>'label'=cut;
   IF cut_m IS NULL THEN RAISE EXCEPTION 'Choose an available fabric cut'; END IF;
   pieces:=qty/cut_m;
   IF pieces NOT BETWEEN 1 AND 10 OR pieces<>trunc(pieces) THEN RAISE EXCEPTION 'Quantity must equal 1 to 10 whole pieces of the selected cut'; END IF;
  END IF;
  net:=round(v.price*qty,2);
  -- Same additive, per-line tax rule used by quote_sale/post_sale; delivery is untaxed.
  tax:=CASE WHEN v.taxable THEN round(net*coalesce(s.tax_rate,0)/100,2) ELSE 0 END;
  SELECT EXISTS(SELECT 1 FROM public.stock_balances b JOIN public.locations l ON l.id=b.location_id WHERE b.variant_id=v.variant_id AND l.active
   AND l.branch_id=public.default_branch_id() AND l.kind IN ('shop_floor','stockroom','online') AND b.on_hand-b.reserved>=qty
   AND (v.unit<>'meter' OR EXISTS(SELECT 1 FROM public.fabric_rolls r WHERE r.variant_id=b.variant_id AND r.location_id=b.location_id AND r.remaining_length-r.reserved_length>=qty))) INTO available;
  lines:=lines||jsonb_build_array(jsonb_build_object('variant_id',v.variant_id,'cut',cut,'cut_pieces',pieces,'description',v.title||CASE WHEN cut IS NULL THEN '' ELSE ' – '||pieces::int||' × '||cut||' '||trim_scale(cut_m)::text||' m' END,'sku',v.sku,'size',v.size,'color',v.color,'unit',v.unit,
   'quantity',qty,'unit_price',v.price,'taxable',v.taxable,'tax',tax,'total',net+tax,'availability',CASE WHEN NOT available THEN 'out_of_stock' ELSE v.stock_level END));
  sub:=sub+net;taxes:=taxes+tax;
 END LOOP;
 fee:=CASE WHEN p->>'fulfilment'='pickup' OR (s.free_delivery_over IS NOT NULL AND sub>=s.free_delivery_over) THEN 0 ELSE s.delivery_fee END;
 total:=sub+taxes+fee;
 RETURN jsonb_build_object('lines',lines,'subtotal',sub,'discount',0,'tax',taxes,'delivery_fee',fee,'total',total,'cod_allowed',s.cod_enabled AND (s.cod_max_total IS NULL OR total<=s.cod_max_total),'payment_methods',to_jsonb(array_remove(ARRAY[CASE WHEN s.online_card_enabled THEN 'card' END,CASE WHEN s.online_card_enabled THEN 'easypaisa' END,CASE WHEN s.cod_enabled AND (s.cod_max_total IS NULL OR total<=s.cod_max_total) THEN 'cod' END],NULL)));
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
  INSERT INTO public.online_order_lines(order_id,line_no,variant_id,description,sku,size,color,unit,quantity,unit_price,taxable,tax,total,location_id,reservation_id,cut_label,cut_pieces)
  VALUES(o.id,line,(item->>'variant_id')::uuid,item->>'description',item->>'sku',item->>'size',item->>'color',item->>'unit',qty,(item->>'unit_price')::numeric,(item->>'taxable')::boolean,(item->>'tax')::numeric,(item->>'total')::numeric,chosen,res.id,item->>'cut',nullif(item->>'cut_pieces','')::numeric::int);
 END LOOP;
 INSERT INTO public.online_order_events(order_id,event,public_message) VALUES(o.id,o.status,'Your order has been received.');
 RETURN public.idempotency_finish(k,jsonb_build_object('id',o.id,'order_no',o.order_no,'status',o.status,'subtotal',o.subtotal,'discount',o.discount,'tax',o.tax,'delivery_fee',o.delivery_fee,'total',o.total,'expires_at',o.expires_at));
END $$;

REVOKE ALL ON FUNCTION public.update_settings(JSONB),public.create_online_order(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_settings(JSONB),public.create_online_order(JSONB) TO authenticated;
REVOKE ALL ON FUNCTION public.quote_online_order(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quote_online_order(JSONB) TO anon,authenticated;
