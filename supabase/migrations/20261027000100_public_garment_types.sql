CREATE OR REPLACE FUNCTION public.catalog_garment_types()
RETURNS TABLE(code TEXT,name TEXT,lead_days INT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT g.code,g.name,g.lead_days FROM public.garment_types g WHERE g.active ORDER BY g.sort_order,g.name
$$;
REVOKE ALL ON FUNCTION public.catalog_garment_types() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.catalog_garment_types() TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.tailoring_request_detail(p_request UUID) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE r JSONB;
BEGIN
 IF NOT public.is_counter_staff() THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 SELECT to_jsonb(t)||jsonb_build_object('photos',(SELECT coalesce(jsonb_agg(to_jsonb(ph) ORDER BY created_at,id),'[]') FROM public.tailoring_request_photos ph WHERE request_id=t.id),
 'events',(SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY created_at,id),'[]') FROM public.tailoring_request_events e WHERE request_id=t.id),
 'requester',(SELECT jsonb_build_object('account_id',a.id,'name',a.full_name,'phone',public.normalize_phone(a.phone),
 'email',a.email,'phone_verified',a.phone_verified,'linked_customer_id',a.customer_id) FROM public.customer_accounts a WHERE a.id=t.account_id)) INTO r FROM public.tailoring_requests t WHERE id=p_request;
 IF r IS NULL THEN RAISE EXCEPTION 'Request not found'; END IF;
 RETURN r;
END $$;
REVOKE ALL ON FUNCTION public.tailoring_request_detail(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.tailoring_request_detail(UUID) TO authenticated;
