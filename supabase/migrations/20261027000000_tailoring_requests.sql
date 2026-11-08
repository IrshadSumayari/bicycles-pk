-- Website requests are separate from shop orders. All transitions run through RPCs.
CREATE SEQUENCE IF NOT EXISTS public.tailoring_request_no_seq;
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS appointment_hours JSONB NOT NULL
 DEFAULT '{"timezone":"Asia/Karachi","days":[1,2,3,4,5,6],"opens":"11:00","closes":"20:00"}';

CREATE TABLE IF NOT EXISTS public.tailoring_requests (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 request_no TEXT NOT NULL UNIQUE DEFAULT ('REQ-' || lpad(nextval('public.tailoring_request_no_seq')::text,6,'0')),
 request_id UUID NOT NULL UNIQUE, account_id UUID NOT NULL REFERENCES public.customer_accounts(id),
 customer_id UUID REFERENCES public.customers(id), garment_type TEXT NOT NULL REFERENCES public.garment_types(code),
 quantity INT NOT NULL CHECK(quantity BETWEEN 1 AND 10),
 fabric_source TEXT NOT NULL CHECK(fabric_source IN ('store','customer','undecided')),
 fabric_variant_id UUID REFERENCES public.product_variants(id), design_notes TEXT CHECK(length(design_notes)<=2000),
 preferred_date DATE, appointment_wanted BOOLEAN NOT NULL DEFAULT false,
 status TEXT NOT NULL DEFAULT 'submitted' CHECK(status IN ('submitted','reviewing','quoted','accepted','declined','cancelled','converted')),
 quote JSONB, staff_notes TEXT CHECK(length(staff_notes)<=10000), tailoring_order_id UUID UNIQUE REFERENCES public.tailoring_orders(id),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS tailoring_requests_account ON public.tailoring_requests(account_id,created_at);
CREATE INDEX IF NOT EXISTS tailoring_requests_status ON public.tailoring_requests(status,created_at);
CREATE TABLE IF NOT EXISTS public.tailoring_request_photos (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), request_id UUID NOT NULL REFERENCES public.tailoring_requests(id),
 storage_path TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE(request_id,storage_path)
);
CREATE TABLE IF NOT EXISTS public.tailoring_request_events (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), request_id UUID NOT NULL REFERENCES public.tailoring_requests(id),
 event TEXT NOT NULL, public_message TEXT CHECK(length(public_message)<=2000), created_by UUID DEFAULT auth.uid() REFERENCES auth.users(id),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS tailoring_events_request ON public.tailoring_request_events(request_id,created_at);
CREATE TABLE IF NOT EXISTS public.appointments (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), request_id UUID REFERENCES public.tailoring_requests(id),
 account_id UUID REFERENCES public.customer_accounts(id), customer_id UUID REFERENCES public.customers(id),
 starts_at TIMESTAMPTZ NOT NULL, duration_minutes INT NOT NULL DEFAULT 30 CHECK(duration_minutes BETWEEN 1 AND 480),
 purpose TEXT NOT NULL CHECK(purpose IN ('measurement','trial','pickup')),
 status TEXT NOT NULL DEFAULT 'requested' CHECK(status IN ('requested','confirmed','cancelled','done')),
 notes TEXT CHECK(length(notes)<=2000)
);
CREATE INDEX IF NOT EXISTS appointments_calendar ON public.appointments(starts_at) WHERE status IN ('requested','confirmed');
CREATE INDEX IF NOT EXISTS appointments_account ON public.appointments(account_id);
DROP TRIGGER IF EXISTS tailoring_requests_updated ON public.tailoring_requests;
CREATE TRIGGER tailoring_requests_updated BEFORE UPDATE ON public.tailoring_requests FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS tailoring_request_events_append_only ON public.tailoring_request_events;
CREATE TRIGGER tailoring_request_events_append_only BEFORE UPDATE OR DELETE ON public.tailoring_request_events FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();

DO $$ DECLARE t TEXT; BEGIN
 FOREACH t IN ARRAY ARRAY['tailoring_requests','tailoring_request_photos','tailoring_request_events','appointments'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('DROP POLICY IF EXISTS counter_read ON public.%I',t);
  EXECUTE format('CREATE POLICY counter_read ON public.%I FOR SELECT TO authenticated USING(public.is_counter_staff())',t);
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated',t);
  EXECUTE format('GRANT SELECT ON public.%I TO authenticated',t);
 END LOOP;
END $$;
REVOKE ALL ON SEQUENCE public.tailoring_request_no_seq FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.is_website_customer() RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT EXISTS(SELECT 1 FROM public.customer_accounts WHERE id=auth.uid()) AND NOT public.is_staff()
$$;

CREATE OR REPLACE FUNCTION public.require_website_customer() RETURNS UUID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF public.is_staff() THEN RAISE EXCEPTION 'Please use the shop system' USING ERRCODE='42501'; END IF;
 IF auth.uid() IS NULL OR NOT public.is_website_customer() THEN RAISE EXCEPTION 'Please sign in as a customer' USING ERRCODE='42501'; END IF;
 RETURN auth.uid();
END $$;

-- The common idempotency store is global: never expose another user's stored result.
CREATE OR REPLACE FUNCTION public.tailoring_request_begin(p_key UUID,p_operation TEXT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r JSONB;
BEGIN
 IF p_key IS NULL THEN RAISE EXCEPTION 'request_id is required'; END IF;
 r:=public.idempotency_begin(p_key,p_operation);
 IF NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=p_key AND user_id=auth.uid()) THEN
  RAISE EXCEPTION 'Please use a new request id' USING ERRCODE='42501';
 END IF;
 RETURN r;
END $$;

-- Trusted RPCs run as the table owner; direct customer edits still cannot alter links.
CREATE OR REPLACE FUNCTION public.protect_customer_account_columns() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
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

CREATE OR REPLACE FUNCTION public.link_customer_account() RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
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
 UPDATE public.tailoring_requests SET customer_id=c WHERE account_id=a AND customer_id IS NULL;
 RETURN jsonb_build_object('status','linked');
END $$;

CREATE OR REPLACE FUNCTION public.staff_link_customer_account(p_account UUID,p_customer UUID,p_request_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r JSONB; a public.customer_accounts;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 r:=public.tailoring_request_begin(p_request_id,'staff_link_customer_account'); IF r IS NOT NULL THEN RETURN r; END IF;
 SELECT * INTO a FROM public.customer_accounts WHERE id=p_account FOR UPDATE;
 IF a.id IS NULL OR EXISTS(SELECT 1 FROM public.users WHERE id=p_account) THEN RAISE EXCEPTION 'Choose a customer account'; END IF;
 PERFORM 1 FROM public.customers WHERE id=p_customer FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;
 IF (a.customer_id IS NOT NULL AND a.customer_id<>p_customer) OR EXISTS(SELECT 1 FROM public.customer_accounts WHERE customer_id=p_customer AND id<>p_account) THEN
  RAISE EXCEPTION 'This account or customer is already linked elsewhere';
 END IF;
 UPDATE public.customer_accounts SET customer_id=p_customer,phone_verified=true WHERE id=p_account;
 UPDATE public.tailoring_requests SET customer_id=p_customer WHERE account_id=p_account AND customer_id IS NULL;
 RETURN public.idempotency_finish(p_request_id,jsonb_build_object('status','linked'));
END $$;

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('tailoring-photos','tailoring-photos',false,5242880,ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
DROP POLICY IF EXISTS tailoring_photos_upload ON storage.objects;
CREATE POLICY tailoring_photos_upload ON storage.objects FOR INSERT TO authenticated WITH CHECK(
 bucket_id='tailoring-photos' AND public.is_website_customer() AND (storage.foldername(name))[1]='requests' AND (storage.foldername(name))[2]=auth.uid()::text);
DROP POLICY IF EXISTS tailoring_photos_read ON storage.objects;
CREATE POLICY tailoring_photos_read ON storage.objects FOR SELECT TO authenticated USING(
 bucket_id='tailoring-photos' AND (public.is_counter_staff() OR (public.is_website_customer() AND
 (storage.foldername(name))[1]='requests' AND (storage.foldername(name))[2]=auth.uid()::text)));
-- No UPDATE or DELETE policy: keep submitted evidence intact, including orphan uploads.

CREATE OR REPLACE FUNCTION public.submit_tailoring_request(p JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE a UUID; k UUID; r JSONB; t public.tailoring_requests; path TEXT; photos JSONB;
BEGIN
 a:=public.require_website_customer(); k:=nullif(p->>'request_id','')::uuid;
 r:=public.tailoring_request_begin(k,'submit_tailoring_request'); IF r IS NOT NULL THEN RETURN r; END IF;
 PERFORM 1 FROM public.customer_accounts WHERE id=a FOR UPDATE;
 IF (SELECT count(*) FROM public.tailoring_requests WHERE account_id=a AND status IN ('submitted','reviewing','quoted','accepted'))>=5 THEN
  RAISE EXCEPTION 'You already have five open requests. Please contact the shop before adding another.';
 END IF;
 IF (SELECT count(*) FROM public.tailoring_requests WHERE account_id=a AND created_at >= date_trunc('day',now() AT TIME ZONE 'Asia/Karachi') AT TIME ZONE 'Asia/Karachi')>=10 THEN
  RAISE EXCEPTION 'You have sent ten requests today. Please try again tomorrow.';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.garment_types WHERE code=p->>'garment_type' AND active) THEN RAISE EXCEPTION 'Choose an active garment type'; END IF;
 IF coalesce(p->>'quantity','') !~ '^[0-9]+$' OR coalesce((p->>'quantity')::numeric,0) NOT BETWEEN 1 AND 10 THEN RAISE EXCEPTION 'Choose a quantity from 1 to 10'; END IF;
 IF coalesce(p->>'fabric_source','undecided') NOT IN ('store','customer','undecided') THEN RAISE EXCEPTION 'Choose a fabric source'; END IF;
 IF length(p->>'design_notes')>2000 THEN RAISE EXCEPTION 'Keep design notes under 2001 characters'; END IF;
 IF nullif(p->>'fabric_variant_id','') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.product_variants v JOIN public.product_styles s ON s.id=v.style_id
   WHERE v.id=(p->>'fabric_variant_id')::uuid AND v.active AND s.active AND s.kind='fabric') THEN RAISE EXCEPTION 'Choose an available fabric'; END IF;
 photos:=coalesce(p->'photos','[]');
 IF jsonb_typeof(photos)<>'array' THEN RAISE EXCEPTION 'Send a list of photos'; END IF;
 IF jsonb_array_length(photos)>5 THEN RAISE EXCEPTION 'Attach at most five photos'; END IF;
 FOR path IN SELECT jsonb_array_elements_text(photos) LOOP
  IF split_part(path,'/',1)<>'requests' OR split_part(path,'/',2)<>a::text OR path LIKE '%/../%' OR NOT EXISTS(
    SELECT 1 FROM storage.objects WHERE bucket_id='tailoring-photos' AND name=path) THEN RAISE EXCEPTION 'Upload each photo to your own request folder first'; END IF;
 END LOOP;
 INSERT INTO public.tailoring_requests(request_id,account_id,customer_id,garment_type,quantity,fabric_source,fabric_variant_id,design_notes,preferred_date,appointment_wanted)
 SELECT k,a,customer_id,p->>'garment_type',(p->>'quantity')::int,coalesce(p->>'fabric_source','undecided'),nullif(p->>'fabric_variant_id','')::uuid,
 nullif(trim(p->>'design_notes'),''),nullif(p->>'preferred_date','')::date,coalesce((p->>'appointment_wanted')::boolean,false)
 FROM public.customer_accounts WHERE id=a RETURNING * INTO t;
 INSERT INTO public.tailoring_request_photos(request_id,storage_path) SELECT t.id,value FROM jsonb_array_elements_text(photos) ON CONFLICT DO NOTHING;
 INSERT INTO public.tailoring_request_events(request_id,event,public_message) VALUES(t.id,'submitted','Your request has been received.');
 RETURN public.idempotency_finish(k,jsonb_build_object('id',t.id,'request_no',t.request_no,'status',t.status));
END $$;

CREATE OR REPLACE FUNCTION public.my_tailoring_requests() RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE a UUID;
BEGIN
 a:=public.require_website_customer();
 RETURN coalesce((SELECT jsonb_agg((to_jsonb(t)-'staff_notes'-'account_id'-'customer_id'-'request_id') || jsonb_build_object(
 'photos',(SELECT coalesce(jsonb_agg(storage_path ORDER BY created_at,id),'[]') FROM public.tailoring_request_photos WHERE request_id=t.id),
 'events',(SELECT coalesce(jsonb_agg(jsonb_build_object('event',event,'message',public_message,'created_at',created_at) ORDER BY created_at,id),'[]')
 FROM public.tailoring_request_events WHERE request_id=t.id AND public_message IS NOT NULL)) ORDER BY t.created_at DESC,t.id)
 FROM public.tailoring_requests t WHERE account_id=a),'[]');
END $$;

CREATE OR REPLACE FUNCTION public.respond_to_quote(p_request UUID,p_accept BOOLEAN,p_request_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE a UUID; t public.tailoring_requests; r JSONB;
BEGIN
 a:=public.require_website_customer(); r:=public.tailoring_request_begin(p_request_id,'respond_to_quote'); IF r IS NOT NULL THEN RETURN r; END IF;
 SELECT * INTO t FROM public.tailoring_requests WHERE id=p_request AND account_id=a FOR UPDATE;
 IF t.id IS NULL THEN RAISE EXCEPTION 'Request not found' USING ERRCODE='42501'; END IF;
 IF t.status<>'quoted' THEN RAISE EXCEPTION 'This request has no quote to answer'; END IF;
 IF (t.quote->>'valid_until')::timestamptz<=now() THEN RAISE EXCEPTION 'This quote has expired. Please ask the shop for a new quote.'; END IF;
 IF p_accept IS NULL THEN RAISE EXCEPTION 'Choose accept or decline'; END IF;
 UPDATE public.tailoring_requests SET status=CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END WHERE id=t.id;
 INSERT INTO public.tailoring_request_events(request_id,event,public_message) VALUES(t.id,CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END,CASE WHEN p_accept THEN 'You accepted the quote.' ELSE 'You declined the quote.' END);
 RETURN public.idempotency_finish(p_request_id,jsonb_build_object('status',CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END));
END $$;

CREATE OR REPLACE FUNCTION public.cancel_tailoring_request(p_request UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE a UUID; t public.tailoring_requests;
BEGIN
 a:=public.require_website_customer(); SELECT * INTO t FROM public.tailoring_requests WHERE id=p_request AND account_id=a FOR UPDATE;
 IF t.id IS NULL THEN RAISE EXCEPTION 'Request not found' USING ERRCODE='42501'; END IF;
 IF t.status='cancelled' THEN RETURN jsonb_build_object('status','cancelled'); END IF;
 IF t.status NOT IN ('submitted','reviewing','quoted') THEN RAISE EXCEPTION 'Please contact the shop to cancel this request'; END IF;
 UPDATE public.tailoring_requests SET status='cancelled' WHERE id=t.id;
 INSERT INTO public.tailoring_request_events(request_id,event,public_message) VALUES(t.id,'cancelled','You cancelled the request.');
 RETURN jsonb_build_object('status','cancelled');
END $$;

-- No btree_gist is installed. A single transaction lock serializes calendar writes.
-- This also protects different start times and bookings crossing midnight.
CREATE OR REPLACE FUNCTION public.appointment_slots(p_date DATE) RETURNS TABLE(starts_at TIMESTAMPTZ)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE h JSONB; zone TEXT; first_slot TIMESTAMPTZ; last_slot TIMESTAMPTZ;
BEGIN
 PERFORM public.require_website_customer();
 SELECT appointment_hours INTO h FROM public.app_settings ORDER BY created_at,id LIMIT 1;
 zone:=coalesce(h->>'timezone','Asia/Karachi');
 IF NOT coalesce(h->'days','[1,2,3,4,5,6]') @> to_jsonb(extract(isodow FROM p_date)::int) THEN RETURN; END IF;
 first_slot:=(p_date+coalesce(h->>'opens','11:00')::time) AT TIME ZONE zone;
 last_slot:=(p_date+coalesce(h->>'closes','20:00')::time) AT TIME ZONE zone;
 RETURN QUERY SELECT s FROM generate_series(first_slot,last_slot-interval '30 minutes',interval '30 minutes') s
 WHERE s>now() AND NOT EXISTS(SELECT 1 FROM public.appointments a WHERE a.status IN ('requested','confirmed')
 AND tstzrange(a.starts_at,a.starts_at+make_interval(mins=>a.duration_minutes),'[)') && tstzrange(s,s+interval '30 minutes','[)')) ORDER BY s;
END $$;

CREATE OR REPLACE FUNCTION public.request_appointment(p JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE a UUID; k UUID; r JSONB; at_time TIMESTAMPTZ; t UUID; ap public.appointments; zone TEXT;
BEGIN
 a:=public.require_website_customer(); k:=nullif(p->>'request_id','')::uuid;
 r:=public.tailoring_request_begin(k,'request_appointment'); IF r IS NOT NULL THEN RETURN r; END IF;
 PERFORM pg_advisory_xact_lock(27000001);
 t:=nullif(p->>'tailoring_request_id','')::uuid;
 IF t IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.tailoring_requests WHERE id=t AND account_id=a AND status NOT IN ('cancelled','declined')) THEN
  RAISE EXCEPTION 'Request not found' USING ERRCODE='42501'; END IF;
 at_time:=nullif(p->>'starts_at','')::timestamptz;
 SELECT coalesce(appointment_hours->>'timezone','Asia/Karachi') INTO zone FROM public.app_settings ORDER BY created_at,id LIMIT 1;
 IF at_time IS NULL OR NOT EXISTS(SELECT 1 FROM public.appointment_slots((at_time AT TIME ZONE coalesce(zone,'Asia/Karachi'))::date) s WHERE s.starts_at=at_time) THEN
  RAISE EXCEPTION 'That time is unavailable. Please choose another appointment slot.'; END IF;
 IF coalesce(p->>'purpose','') NOT IN ('measurement','trial','pickup') THEN RAISE EXCEPTION 'Choose an appointment purpose'; END IF;
 IF length(p->>'notes')>2000 THEN RAISE EXCEPTION 'Keep appointment notes under 2001 characters'; END IF;
 IF p ? 'duration_minutes' AND (p->>'duration_minutes')::int<>30 THEN RAISE EXCEPTION 'Appointments are 30 minutes'; END IF;
 INSERT INTO public.appointments(request_id,account_id,customer_id,starts_at,purpose,notes)
 SELECT t,a,customer_id,at_time,p->>'purpose',nullif(trim(p->>'notes'),'') FROM public.customer_accounts WHERE id=a RETURNING * INTO ap;
 RETURN public.idempotency_finish(k,jsonb_build_object('id',ap.id,'starts_at',ap.starts_at,'status',ap.status));
END $$;

CREATE OR REPLACE FUNCTION public.my_appointments() RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE a UUID;
BEGIN
 a:=public.require_website_customer();
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'request_id',request_id,'starts_at',starts_at,
 'duration_minutes',duration_minutes,'purpose',purpose,'status',status) ORDER BY starts_at,id) FROM public.appointments WHERE account_id=a),'[]');
END $$;

CREATE OR REPLACE FUNCTION public.my_order_progress(p_request UUID) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE a UUID; o UUID;
BEGIN
 a:=public.require_website_customer();
 SELECT tailoring_order_id INTO o FROM public.tailoring_requests WHERE id=p_request AND account_id=a AND status='converted';
 IF o IS NULL THEN RAISE EXCEPTION 'Converted request not found' USING ERRCODE='42501'; END IF;
 RETURN (SELECT jsonb_build_object('order_no',t.order_no,'promised_date',t.promised_date,'balance_due',public.tailoring_order_totals(o)->'balance',
 'items',(SELECT coalesce(jsonb_agg(jsonb_build_object('stage',CASE i.status WHEN 'awaiting' THEN 'received' WHEN 'ready' THEN 'ready'
 WHEN 'delivered' THEN 'delivered' WHEN 'cancelled' THEN 'cancelled' ELSE 'in work' END) ORDER BY i.line_no),'[]') FROM public.tailoring_items i WHERE order_id=o))
 FROM public.tailoring_orders t WHERE t.id=o);
END $$;

CREATE OR REPLACE FUNCTION public.list_tailoring_requests(p JSONB DEFAULT '{}') RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE n INT; off INT;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 n:=least(100,greatest(1,coalesce((p->>'limit')::int,24))); off:=greatest(0,coalesce((p->>'offset')::int,0));
 RETURN jsonb_build_object('total_count',(SELECT count(*) FROM public.tailoring_requests WHERE nullif(p->>'status','') IS NULL OR status=p->>'status'),
 'requests',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC,t.id) FROM
 (SELECT * FROM public.tailoring_requests WHERE nullif(p->>'status','') IS NULL OR status=p->>'status' ORDER BY created_at DESC,id LIMIT n OFFSET off) t),'[]'));
END $$;

CREATE OR REPLACE FUNCTION public.tailoring_request_detail(p_request UUID) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE r JSONB;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 SELECT to_jsonb(t)||jsonb_build_object('photos',(SELECT coalesce(jsonb_agg(to_jsonb(ph) ORDER BY created_at,id),'[]') FROM public.tailoring_request_photos ph WHERE request_id=t.id),
 'events',(SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY created_at,id),'[]') FROM public.tailoring_request_events e WHERE request_id=t.id)) INTO r FROM public.tailoring_requests t WHERE id=p_request;
 IF r IS NULL THEN RAISE EXCEPTION 'Request not found'; END IF;
 RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.update_tailoring_request(p JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE k UUID; r JSONB; t public.tailoring_requests;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 k:=nullif(p->>'request_id','')::uuid; r:=public.tailoring_request_begin(k,'update_tailoring_request'); IF r IS NOT NULL THEN RETURN r; END IF;
 SELECT * INTO t FROM public.tailoring_requests WHERE id=(p->>'id')::uuid FOR UPDATE;
 IF t.id IS NULL THEN RAISE EXCEPTION 'Request not found'; END IF;
 IF p ? 'status' THEN
  IF p->>'status' IS DISTINCT FROM 'reviewing' OR t.status NOT IN ('submitted','reviewing') THEN RAISE EXCEPTION 'Only submitted requests can enter review'; END IF;
  IF t.status<>'reviewing' THEN
   UPDATE public.tailoring_requests SET status='reviewing' WHERE id=t.id;
   INSERT INTO public.tailoring_request_events(request_id,event,public_message) VALUES(t.id,'reviewing','The shop is reviewing your request.');
  END IF;
 END IF;
 IF p ? 'staff_notes' THEN
  IF length(p->>'staff_notes')>10000 THEN RAISE EXCEPTION 'Keep staff notes under 10001 characters'; END IF;
  UPDATE public.tailoring_requests SET staff_notes=p->>'staff_notes' WHERE id=t.id;
  INSERT INTO public.tailoring_request_events(request_id,event) VALUES(t.id,'staff_notes_updated');
 END IF;
 IF nullif(trim(p->>'public_message'),'') IS NOT NULL THEN
  IF length(p->>'public_message')>2000 THEN RAISE EXCEPTION 'Keep messages under 2001 characters'; END IF;
  INSERT INTO public.tailoring_request_events(request_id,event,public_message) VALUES(t.id,'message',trim(p->>'public_message'));
 END IF;
 RETURN public.idempotency_finish(k,public.tailoring_request_detail(t.id));
END $$;

CREATE OR REPLACE FUNCTION public.quote_tailoring_request(p JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE k UUID; r JSONB; t public.tailoring_requests; q JSONB; c JSONB; charges JSONB:='[]'; total NUMERIC(14,2):=0; amount NUMERIC(14,2); dep NUMERIC(14,2); fabric JSONB;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 k:=nullif(p->>'request_id','')::uuid; r:=public.tailoring_request_begin(k,'quote_tailoring_request'); IF r IS NOT NULL THEN RETURN r; END IF;
 SELECT * INTO t FROM public.tailoring_requests WHERE id=(p->>'id')::uuid FOR UPDATE;
 IF t.id IS NULL OR t.status NOT IN ('submitted','reviewing','quoted') THEN RAISE EXCEPTION 'Choose an open request to quote'; END IF;
 q:=p->'quote';
 IF jsonb_typeof(q->'charges') IS DISTINCT FROM 'array' OR jsonb_array_length(q->'charges') NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'Add between one and fifty quoted charges'; END IF;
 FOR c IN SELECT jsonb_array_elements(q->'charges') LOOP
  IF jsonb_typeof(c->'amount') IS DISTINCT FROM 'number' OR (c->>'amount')::numeric<0 OR (c->>'amount')::numeric<>round((c->>'amount')::numeric,2)
   OR coalesce(length(trim(c->>'description')),0) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Enter a description and a non-negative amount with up to two decimals for every charge'; END IF;
  amount:=(c->>'amount')::numeric; total:=total+amount;
  charges:=charges||jsonb_build_array(jsonb_build_object('description',trim(c->>'description'),'amount',amount));
 END LOOP;
 IF jsonb_typeof(q->'total') IS DISTINCT FROM 'number' OR (q->>'total')::numeric<>total THEN RAISE EXCEPTION 'Quote total must equal the sum of charges'; END IF;
 IF jsonb_typeof(q->'deposit_required') IS DISTINCT FROM 'number' OR (q->>'deposit_required')::numeric NOT BETWEEN 0 AND total
 OR (q->>'deposit_required')::numeric<>round((q->>'deposit_required')::numeric,2) THEN RAISE EXCEPTION 'Deposit must be between zero and the quote total, with up to two decimals'; END IF;
 dep:=(q->>'deposit_required')::numeric;
 IF nullif(q->>'valid_until','') IS NULL OR (q->>'valid_until')::timestamptz<=now() THEN RAISE EXCEPTION 'Choose a future quote expiry'; END IF;
 IF nullif(q->>'promised_date','') IS NULL OR (q->>'promised_date')::date<(now() AT TIME ZONE 'Asia/Karachi')::date THEN RAISE EXCEPTION 'Choose a promised date from today onwards'; END IF;
 -- Preserve only public fabric fields; material charges remain in the quoted charges.
 IF q->'fabric' IS NOT NULL AND q->'fabric'<>'null'::jsonb THEN
  IF jsonb_typeof(q->'fabric')<>'object' OR coalesce(q->'fabric'->>'source','') NOT IN ('store','customer')
   OR coalesce((q->'fabric'->>'quantity')::numeric,0)<=0 OR (q->'fabric'->>'quantity')::numeric<>round((q->'fabric'->>'quantity')::numeric,2)
   OR length(q->'fabric'->>'description')>500 THEN RAISE EXCEPTION 'Enter a fabric source and length with up to two decimals'; END IF;
  IF q->'fabric'->>'source'='store' AND NOT EXISTS(SELECT 1 FROM public.product_variants v JOIN public.product_styles s ON s.id=v.style_id
   WHERE v.id=nullif(q->'fabric'->>'variant_id','')::uuid AND v.active AND s.active AND s.unit='meter') THEN RAISE EXCEPTION 'Choose a fabric from stock'; END IF;
  fabric:=jsonb_build_object('source',q->'fabric'->>'source','variant_id',q->'fabric'->>'variant_id','quantity',(q->'fabric'->>'quantity')::numeric,'description',q->'fabric'->>'description');
 END IF;
 q:=jsonb_build_object('charges',charges,'fabric',fabric,'total',total,'deposit_required',dep,'promised_date',(q->>'promised_date')::date,'valid_until',(q->>'valid_until')::timestamptz);
 UPDATE public.tailoring_requests SET quote=q,status='quoted' WHERE id=t.id;
 INSERT INTO public.tailoring_request_events(request_id,event,public_message) VALUES(t.id,'quoted','Your quote is ready to review.');
 RETURN public.idempotency_finish(k,jsonb_build_object('status','quoted','quote',q));
END $$;

CREATE OR REPLACE FUNCTION public.convert_tailoring_request(p JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE k UUID; r JSONB; t public.tailoring_requests; a public.customer_accounts; c UUID; items JSONB:='[]'; item JSONB; f JSONB; paid NUMERIC; n INT;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 k:=nullif(p->>'request_id','')::uuid; r:=public.tailoring_request_begin(k,'convert_tailoring_request'); IF r IS NOT NULL THEN RETURN r; END IF;
 SELECT ca.* INTO a FROM public.customer_accounts ca JOIN public.tailoring_requests tr ON tr.account_id=ca.id WHERE tr.id=(p->>'id')::uuid FOR UPDATE OF ca;
 SELECT * INTO t FROM public.tailoring_requests WHERE id=(p->>'id')::uuid FOR UPDATE;
 IF t.id IS NULL THEN RAISE EXCEPTION 'Request not found'; END IF;
 IF t.status='converted' THEN RETURN public.idempotency_finish(k,jsonb_build_object('status','converted','tailoring_order_id',t.tailoring_order_id)); END IF;
 IF t.status<>'accepted' THEN RAISE EXCEPTION 'The customer must accept the quote first'; END IF;
 c:=a.customer_id;
 IF c IS NULL THEN
  IF coalesce(trim(a.full_name),'')='' OR public.normalize_phone(a.phone) IS NULL THEN RAISE EXCEPTION 'Check the customer name and phone in the shop first'; END IF;
  -- Staff conversion is an in-shop identity check. Never claim an existing phone silently.
  IF EXISTS(SELECT 1 FROM public.customers WHERE phone=public.normalize_phone(a.phone)) THEN RAISE EXCEPTION 'Link this account to the existing customer in the shop first'; END IF;
  INSERT INTO public.customers(name,phone,email) VALUES(a.full_name,public.normalize_phone(a.phone),a.email) RETURNING id INTO c;
  UPDATE public.customer_accounts SET customer_id=c,phone_verified=true WHERE id=a.id;
 END IF;
 IF jsonb_typeof(p->'payments') NOT IN ('array','null') THEN RAISE EXCEPTION 'Send a list of deposit payments'; END IF;
 SELECT coalesce(sum((v->>'amount')::numeric),0) INTO paid FROM jsonb_array_elements(coalesce(p->'payments','[]')) v;
 IF paid<(t.quote->>'deposit_required')::numeric THEN RAISE EXCEPTION 'Take the deposit required by the accepted quote'; END IF;
 FOR n IN 1..t.quantity LOOP
  item:=jsonb_build_object('garment_type',t.garment_type,'wearer_id',p->'wearer_id','wearer',p->'wearer',
   'measurement_set_id',p->'measurement_set_id','measurements',p->'measurements','design_notes',t.design_notes,'stitching_charge',0);
  -- Fabric length is for the whole request; reserve it once, without adding unquoted charges.
  IF n=1 AND t.quote->'fabric' IS NOT NULL AND t.quote->'fabric'<>'null'::jsonb THEN
   f:=t.quote->'fabric'; item:=item||jsonb_build_object('materials',jsonb_build_array(f||jsonb_build_object('charge',false)));
  END IF;
  items:=items||jsonb_build_array(item);
 END LOOP;
 -- Use a separate deterministic key for the nested order operation.
 r:=public.create_tailoring_order(jsonb_build_object('request_id',t.id,'customer_id',c,'status','confirmed',
 'items',items,'charges',t.quote->'charges','promised_date',t.quote->'promised_date','payments',coalesce(p->'payments','[]'),
 'waive_deposit',coalesce((p->>'waive_deposit')::boolean,false)));
 IF (r->>'total')::numeric<>(t.quote->>'total')::numeric THEN RAISE EXCEPTION 'The order total must match the accepted quote'; END IF;
 UPDATE public.tailoring_requests SET status='converted',customer_id=c,tailoring_order_id=(r->>'id')::uuid WHERE id=t.id;
 INSERT INTO public.tailoring_request_events(request_id,event,public_message) VALUES(t.id,'converted','Your tailoring order has been created.');
 RETURN public.idempotency_finish(k,jsonb_build_object('status','converted','tailoring_order_id',(r->>'id')::uuid));
END $$;

CREATE OR REPLACE FUNCTION public.confirm_appointment(p_id UUID,p_request_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r JSONB; a public.appointments;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 r:=public.tailoring_request_begin(p_request_id,'confirm_appointment'); IF r IS NOT NULL THEN RETURN r; END IF;
 PERFORM pg_advisory_xact_lock(27000001);
 SELECT * INTO a FROM public.appointments WHERE id=p_id FOR UPDATE;
 IF a.id IS NULL OR a.status NOT IN ('requested','confirmed') THEN RAISE EXCEPTION 'Choose a requested appointment'; END IF;
 IF a.starts_at<=now() THEN RAISE EXCEPTION 'Choose a future appointment'; END IF;
 IF EXISTS(SELECT 1 FROM public.appointments b WHERE b.id<>a.id AND b.status IN ('requested','confirmed') AND
 tstzrange(b.starts_at,b.starts_at+make_interval(mins=>b.duration_minutes),'[)') && tstzrange(a.starts_at,a.starts_at+make_interval(mins=>a.duration_minutes),'[)')) THEN
 RAISE EXCEPTION 'That appointment overlaps another booking'; END IF;
 UPDATE public.appointments SET status='confirmed' WHERE id=a.id;
 RETURN public.idempotency_finish(p_request_id,jsonb_build_object('status','confirmed'));
END $$;

CREATE OR REPLACE FUNCTION public.cancel_appointment(p_id UUID,p_reason TEXT,p_request_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r JSONB; a public.appointments;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 r:=public.tailoring_request_begin(p_request_id,'cancel_appointment'); IF r IS NOT NULL THEN RETURN r; END IF;
 PERFORM pg_advisory_xact_lock(27000001); SELECT * INTO a FROM public.appointments WHERE id=p_id FOR UPDATE;
 IF a.id IS NULL OR a.status='done' THEN RAISE EXCEPTION 'Appointment not found or already completed'; END IF;
 IF coalesce(length(trim(p_reason)),0) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'Enter a cancellation reason of at most 2000 characters'; END IF;
 UPDATE public.appointments SET status='cancelled',notes=p_reason WHERE id=a.id;
 RETURN public.idempotency_finish(p_request_id,jsonb_build_object('status','cancelled'));
END $$;

-- Explicit allowlist; internal helpers never become API endpoints.
DO $$ DECLARE f REGPROCEDURE; BEGIN
 FOR f IN SELECT oid::regprocedure FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname=ANY(ARRAY[
 'is_website_customer','require_website_customer','tailoring_request_begin','link_customer_account','staff_link_customer_account',
 'submit_tailoring_request','my_tailoring_requests','respond_to_quote','cancel_tailoring_request','appointment_slots','request_appointment',
 'my_appointments','my_order_progress','list_tailoring_requests','tailoring_request_detail','update_tailoring_request','quote_tailoring_request',
 'convert_tailoring_request','confirm_appointment','cancel_appointment']) LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',f);
  IF f::text NOT LIKE '%require_website_customer(%' AND f::text NOT LIKE '%tailoring_request_begin(%' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f); END IF;
 END LOOP;
END $$;
