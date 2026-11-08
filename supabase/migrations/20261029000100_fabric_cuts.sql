-- Fixed cuts share metre stock and the existing reservation ledger.
ALTER TABLE public.product_styles ADD COLUMN IF NOT EXISTS fabric_cuts JSONB NOT NULL DEFAULT '[]';
CREATE OR REPLACE FUNCTION public.valid_fabric_cuts(cuts JSONB) RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE c JSONB; labels TEXT[]:='{}'; m NUMERIC;
BEGIN
 IF auth.uid() IS NOT NULL AND NOT public.is_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF jsonb_typeof(cuts) IS DISTINCT FROM 'array' THEN RETURN false; END IF;
 IF jsonb_array_length(cuts)>12 THEN RETURN false; END IF;
 FOR c IN SELECT jsonb_array_elements(cuts) LOOP
  IF jsonb_typeof(c) IS DISTINCT FROM 'object' OR jsonb_typeof(c->'label') IS DISTINCT FROM 'string'
   OR length(c->>'label') NOT BETWEEN 1 AND 40 OR trim(c->>'label')<>c->>'label'
   OR jsonb_typeof(c->'meters') IS DISTINCT FROM 'number'
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(c) k WHERE k NOT IN ('label','meters')) THEN RETURN false; END IF;
  m:=(c->>'meters')::numeric;
  IF m NOT BETWEEN 0.25 AND 20 OR mod(m,0.25)<>0 OR c->>'label'=ANY(labels) THEN RETURN false; END IF;
  labels:=array_append(labels,c->>'label');
 END LOOP;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.valid_fabric_cuts(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.valid_fabric_cuts(JSONB) TO authenticated;
ALTER TABLE public.product_styles DROP CONSTRAINT IF EXISTS product_styles_fabric_cuts_check;
ALTER TABLE public.product_styles ADD CONSTRAINT product_styles_fabric_cuts_check CHECK
 (public.valid_fabric_cuts(fabric_cuts) AND (fabric_cuts='[]' OR (kind='fabric' AND unit='meter')));
ALTER TABLE public.online_order_lines ADD COLUMN IF NOT EXISTS cut_label TEXT, ADD COLUMN IF NOT EXISTS cut_pieces INT;
ALTER TABLE public.online_order_lines DROP CONSTRAINT IF EXISTS online_order_lines_quantity_check;
ALTER TABLE public.online_order_lines ADD CONSTRAINT online_order_lines_quantity_check CHECK
 ((unit='meter' AND quantity BETWEEN 0.5 AND 50 AND mod(quantity,0.25)=0)
 OR (unit<>'meter' AND quantity BETWEEN 1 AND 10 AND quantity=trunc(quantity)));
ALTER TABLE public.online_order_lines DROP CONSTRAINT IF EXISTS online_order_lines_cut_check;
ALTER TABLE public.online_order_lines ADD CONSTRAINT online_order_lines_cut_check CHECK
 ((cut_label IS NULL AND cut_pieces IS NULL) OR (unit='meter' AND cut_label IS NOT NULL AND length(cut_label) BETWEEN 1 AND 40 AND cut_pieces IS NOT NULL AND cut_pieces BETWEEN 1 AND 10));
ALTER TABLE public.online_order_lines DROP CONSTRAINT IF EXISTS online_order_lines_order_id_variant_id_key;
CREATE UNIQUE INDEX IF NOT EXISTS online_order_lines_variant_cut ON public.online_order_lines(order_id,variant_id,coalesce(cut_label,''));

CREATE OR REPLACE FUNCTION public.save_style_web_details(p_style UUID,p JSONB,p_request_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_existing JSONB; s public.product_styles; k TEXT; r JSONB; v_slug TEXT;
 v_other TEXT; v_result JSONB;
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
  IF k NOT IN ('slug','web_title','web_description','variants','fabric_cuts') THEN RAISE EXCEPTION 'Unknown website detail: %',k; END IF;
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
 IF p ? 'fabric_cuts' AND (NOT public.valid_fabric_cuts(p->'fabric_cuts') OR (p->'fabric_cuts'<>'[]' AND (s.kind<>'fabric' OR s.unit<>'meter'))) THEN RAISE EXCEPTION 'Use up to 12 unique fabric cut labels and quarter-metre lengths from 0.25 to 20'; END IF;
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
 UPDATE public.product_styles SET fabric_cuts=CASE WHEN p ? 'fabric_cuts' THEN p->'fabric_cuts' ELSE fabric_cuts END, slug=CASE WHEN p ? 'slug' THEN v_slug ELSE slug END,
  web_title=CASE WHEN p ? 'web_title' THEN nullif(trim(p->>'web_title'),'') ELSE web_title END,
  web_description=CASE WHEN p ? 'web_description' THEN nullif(trim(p->>'web_description'),'') ELSE web_description END
 WHERE id=p_style RETURNING * INTO s;
 v_result:=jsonb_build_object('fabric_cuts',s.fabric_cuts,'style_id',s.id,'slug',s.slug,'web_title',s.web_title,'web_description',s.web_description,
  'variants',(SELECT coalesce(jsonb_agg(jsonb_build_object('variant_id',id,'published',published) ORDER BY id),'[]'::jsonb) FROM public.product_variants WHERE style_id=p_style));
 RETURN public.idempotency_finish(p_request_id,v_result);
END; $$;
CREATE OR REPLACE FUNCTION public.catalog_product(p_slug TEXT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT jsonb_build_object('style_id',s.style_id,'slug',s.slug,'title',s.title,
  'description',st.web_description,'kind',st.kind,'fabric_cuts',st.fabric_cuts,'brand',st.brand,'material',st.material,'season',st.season,
  'category',(SELECT name FROM public.categories WHERE id=st.category_id),'unit',st.unit,
  'min_price',s.min_price,'max_price',s.max_price,'stock_level',s.stock_level,
  'images',coalesce((SELECT jsonb_agg(jsonb_build_object('storage_path',i.storage_path,'alt',i.alt,'variant_color',i.variant_color) ORDER BY i.sort_order,i.id)
   FROM public.product_images i WHERE i.style_id=s.style_id AND (i.variant_color IS NULL OR EXISTS(
    SELECT 1 FROM public.public_catalog c WHERE c.style_id=s.style_id AND c.color=i.variant_color AND c.price>0))),'[]'::jsonb),
  'variants',(SELECT jsonb_agg(jsonb_build_object('variant_id',c.variant_id,'size',c.size,'color',c.color,'fit',c.fit,
   'price',c.price,'compare_at_price',c.compare_at_price,'stock_level',c.stock_level) ORDER BY c.size,c.color,c.fit,c.variant_id)
   FROM public.public_catalog c WHERE c.style_id=s.style_id AND c.price>0),
  'size_chart',(SELECT sc.size_chart FROM public.size_schemes sc WHERE sc.id=st.size_scheme_id),
  'related',coalesce((SELECT jsonb_agg(jsonb_build_object('style_id',r.style_id,'slug',r.slug,'title',r.title,'min_price',r.min_price,'image_path',r.image_path))
   FROM (SELECT other.* FROM public.catalog_style_rows() other WHERE other.style_id<>s.style_id AND EXISTS(
    SELECT 1 FROM public.collection_styles mine JOIN public.collection_styles theirs ON theirs.collection_id=mine.collection_id
    JOIN public.collections co ON co.id=mine.collection_id WHERE mine.style_id=s.style_id AND theirs.style_id=other.style_id
     AND co.published AND (co.starts_at IS NULL OR co.starts_at<=now()) AND (co.ends_at IS NULL OR co.ends_at>now()))
    ORDER BY other.created_at DESC,other.style_id LIMIT 8) r),'[]'::jsonb))
 FROM public.catalog_style_rows() s JOIN public.product_styles st ON st.id=s.style_id WHERE s.slug=p_slug;
$$;
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
  INSERT INTO public.online_order_lines(order_id,line_no,variant_id,description,sku,size,color,unit,quantity,unit_price,taxable,tax,total,location_id,reservation_id,cut_label,cut_pieces)
  VALUES(o.id,line,(item->>'variant_id')::uuid,item->>'description',item->>'sku',item->>'size',item->>'color',item->>'unit',qty,(item->>'unit_price')::numeric,(item->>'taxable')::boolean,(item->>'tax')::numeric,(item->>'total')::numeric,chosen,res.id,item->>'cut',nullif(item->>'cut_pieces','')::numeric::int);
 END LOOP;
 INSERT INTO public.online_order_events(order_id,event,public_message) VALUES(o.id,o.status,'Your order has been received.');
 RETURN public.idempotency_finish(k,jsonb_build_object('id',o.id,'order_no',o.order_no,'status',o.status,'subtotal',o.subtotal,'discount',o.discount,'tax',o.tax,'delivery_fee',o.delivery_fee,'total',o.total,'expires_at',o.expires_at));
END $$;
CREATE OR REPLACE FUNCTION public.online_order_public(p_id UUID) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT jsonb_build_object('order_no',o.order_no,'status',o.status,'payment_status',o.payment_status,'payment_method',o.payment_method,
 'fulfilment',o.fulfilment,'contact_name',o.contact_name,'phone',o.phone,'email',o.email,'address',o.address,'delivery_fee',o.delivery_fee,
 'subtotal',o.subtotal,'discount',o.discount,'tax',o.tax,'total',o.total,'tracking_no',o.tracking_no,'courier',o.courier,'notes_customer',o.notes_customer,
 'expires_at',o.expires_at,'created_at',o.created_at,'updated_at',o.updated_at,'cancelled_reason',o.cancelled_reason,
 'lines',(SELECT coalesce(jsonb_agg(jsonb_build_object('line_no',l.line_no,'variant_id',l.variant_id,'description',l.description,'sku',l.sku,'size',l.size,'color',l.color,
 'cut',l.cut_label,'cut_pieces',l.cut_pieces,'unit',l.unit,'quantity',l.quantity,'unit_price',l.unit_price,'taxable',l.taxable,'tax',l.tax,'total',l.total) ORDER BY l.line_no),'[]') FROM public.online_order_lines l WHERE l.order_id=o.id),
 'events',(SELECT coalesce(jsonb_agg(jsonb_build_object('event',e.event,'message',e.public_message,'created_at',e.created_at) ORDER BY e.created_at,e.id),'[]')
 FROM public.online_order_events e WHERE e.order_id=o.id AND e.public_message IS NOT NULL)) FROM public.online_orders o WHERE o.id=p_id
$$;
REVOKE ALL ON FUNCTION public.save_style_web_details(UUID,JSONB,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_style_web_details(UUID,JSONB,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.catalog_product(TEXT),public.quote_online_order(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.catalog_product(TEXT),public.quote_online_order(JSONB) TO anon,authenticated;
REVOKE ALL ON FUNCTION public.create_online_order(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_online_order(JSONB) TO authenticated;
REVOKE ALL ON FUNCTION public.online_order_public(UUID) FROM PUBLIC,anon,authenticated;
