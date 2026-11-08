-- Online customer requests are review records, separate from courier returns
-- and from financial returns. These functions never move stock or send refunds.
CREATE TABLE public.online_return_requests (
 id UUID PRIMARY KEY, order_id UUID NOT NULL UNIQUE REFERENCES public.online_orders(id),
 reason TEXT NOT NULL CHECK(reason IN ('damaged','wrong_item','size_fit','other')),
 requested_resolution TEXT NOT NULL CHECK(requested_resolution IN ('refund','exchange')),
 message TEXT NOT NULL CHECK(length(trim(message)) BETWEEN 10 AND 2000),
 status TEXT NOT NULL DEFAULT 'submitted' CHECK(status IN ('submitted','needs_information','return_authorized','received','closed','rejected')),
 staff_note TEXT NOT NULL DEFAULT '' CHECK(length(staff_note)<=2000),
 version INT NOT NULL DEFAULT 1, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.online_return_items (
 request_id UUID NOT NULL REFERENCES public.online_return_requests(id),
 order_line_id UUID NOT NULL REFERENCES public.online_order_lines(id),
 quantity INT NOT NULL CHECK(quantity BETWEEN 1 AND 10), PRIMARY KEY(request_id,order_line_id)
);
CREATE TABLE public.online_return_events (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), request_id UUID NOT NULL REFERENCES public.online_return_requests(id),
 actor TEXT NOT NULL CHECK(actor IN ('customer','staff')), created_by UUID DEFAULT auth.uid() REFERENCES auth.users(id),
 status TEXT NOT NULL, message TEXT NOT NULL CHECK(length(trim(message)) BETWEEN 1 AND 2000), created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.online_return_photos (
 id UUID PRIMARY KEY, request_id UUID NOT NULL REFERENCES public.online_return_requests(id),
 storage_path TEXT NOT NULL UNIQUE, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX online_return_queue ON public.online_return_requests(status,updated_at DESC);
CREATE INDEX online_return_events_request ON public.online_return_events(request_id,created_at);
CREATE INDEX online_return_photos_request ON public.online_return_photos(request_id);
DO $$ DECLARE t TEXT; BEGIN
 FOREACH t IN ARRAY ARRAY['online_return_requests','online_return_items','online_return_events','online_return_photos'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated',t);
 END LOOP;
END $$;
CREATE TRIGGER online_return_events_immutable BEFORE UPDATE OR DELETE ON public.online_return_events
 FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();

CREATE FUNCTION app_private.return_request_json(p_id UUID) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT jsonb_build_object('id',r.id,'order_no',o.order_no,'reason',r.reason,'requested_resolution',r.requested_resolution,
 'message',r.message,'status',r.status,'version',r.version,'created_at',r.created_at,'updated_at',r.updated_at,
 'items',(SELECT coalesce(jsonb_agg(jsonb_build_object('line_no',l.line_no,'description',l.description,'sku',l.sku,'size',l.size,'color',l.color,'quantity',i.quantity) ORDER BY l.line_no),'[]'::jsonb)
 FROM public.online_return_items i JOIN public.online_order_lines l ON l.id=i.order_line_id WHERE i.request_id=r.id),
 'events',(SELECT coalesce(jsonb_agg(jsonb_build_object('actor',e.actor,'status',e.status,'message',e.message,'created_at',e.created_at) ORDER BY e.created_at,e.id),'[]'::jsonb) FROM public.online_return_events e WHERE e.request_id=r.id),
 'photos',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'storage_path',p.storage_path,'uploaded',EXISTS(SELECT 1 FROM storage.objects s WHERE s.bucket_id='return-evidence' AND s.name=p.storage_path)) ORDER BY p.created_at,p.id),'[]'::jsonb) FROM public.online_return_photos p WHERE p.request_id=r.id))
 FROM public.online_return_requests r JOIN public.online_orders o ON o.id=r.order_id WHERE r.id=p_id
$$;
REVOKE ALL ON FUNCTION app_private.return_request_json(UUID) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.my_return_request(p_order_no TEXT) RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE a UUID; o UUID; r UUID;
BEGIN
 a:=public.require_website_customer();
 SELECT id INTO o FROM public.online_orders WHERE order_no=p_order_no AND account_id=a;
 IF o IS NULL THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF;
 SELECT id INTO r FROM public.online_return_requests WHERE order_id=o;
 RETURN app_private.return_request_json(r);
END $$;

CREATE FUNCTION public.create_return_request(p JSONB) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
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

CREATE FUNCTION public.reply_return_request(p JSONB) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
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

CREATE FUNCTION public.review_return_request(p JSONB) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
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

CREATE FUNCTION public.staff_return_request(p_order_id UUID) RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE r public.online_return_requests;
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.online_orders WHERE id=p_order_id AND public.is_branch_member(branch_id)) THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF;
 SELECT * INTO r FROM public.online_return_requests WHERE order_id=p_order_id;
 IF r.id IS NULL THEN RETURN NULL; END IF;
 RETURN app_private.return_request_json(r.id)||jsonb_build_object('staff_note',r.staff_note);
END $$;

CREATE FUNCTION public.list_return_requests(p JSONB DEFAULT '{}') RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
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

CREATE FUNCTION public.prepare_return_photo(p_id UUID,p_photo_id UUID) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
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

CREATE FUNCTION app_private.return_photo_access(p_path TEXT,p_upload BOOLEAN DEFAULT false) RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT coalesce(EXISTS(SELECT 1 FROM public.online_return_photos p JOIN public.online_return_requests r ON r.id=p.request_id JOIN public.online_orders o ON o.id=r.order_id
 WHERE p.storage_path=p_path AND (
 (public.is_website_customer() AND o.account_id=auth.uid() AND (NOT p_upload OR r.status IN ('submitted','needs_information')))
 OR (NOT p_upload AND public.has_app_role(ARRAY['admin','manager']) AND public.is_branch_member(o.branch_id)))),false)
$$;
REVOKE ALL ON FUNCTION app_private.return_photo_access(TEXT,BOOLEAN) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION app_private.return_photo_access(TEXT,BOOLEAN) TO authenticated;
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types) VALUES('return-evidence','return-evidence',false,5242880,ARRAY['image/webp']);
CREATE POLICY return_evidence_read ON storage.objects FOR SELECT TO authenticated
 USING(bucket_id='return-evidence' AND app_private.return_photo_access(name,false));
CREATE POLICY return_evidence_upload ON storage.objects FOR INSERT TO authenticated
 WITH CHECK(bucket_id='return-evidence' AND app_private.return_photo_access(name,true));
-- Deliberately no object UPDATE/DELETE: evidence cannot be replaced after review.
DO $$ DECLARE f TEXT; BEGIN
 FOREACH f IN ARRAY ARRAY['my_return_request(text)','create_return_request(jsonb)','reply_return_request(jsonb)','review_return_request(jsonb)','staff_return_request(uuid)','list_return_requests(jsonb)','prepare_return_photo(uuid,uuid)'] LOOP
 EXECUTE 'REVOKE ALL ON FUNCTION public.'||f||' FROM PUBLIC,anon';
 EXECUTE 'GRANT EXECUTE ON FUNCTION public.'||f||' TO authenticated';
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.catalog_policy() RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT jsonb_build_object('return_window_days',return_window_days,'cod_enabled',cod_enabled) FROM public.app_settings ORDER BY created_at,id LIMIT 1
$$;
DO $$ DECLARE def TEXT:=replace(pg_get_functiondef('public.catalog_product(text)'::regprocedure),chr(13),''); BEGIN
 IF position('''description'',st.web_description,' IN def)=0 THEN RAISE EXCEPTION 'catalog_product changed'; END IF;
 EXECUTE replace(def,'''description'',st.web_description,','''description'',st.web_description,''purchase_policy'',public.catalog_policy(),');
END $$;
