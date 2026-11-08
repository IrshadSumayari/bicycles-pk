-- Separate editorial updates from inventory and pricing changes.
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
  IF k NOT IN ('slug','web_title','web_description','variants') THEN RAISE EXCEPTION 'Unknown website detail: %',k; END IF;
 END LOOP;
 IF p ? 'slug' THEN
  v_slug:=p->>'slug';
  IF v_slug IS NOT NULL AND (jsonb_typeof(p->'slug')<>'string' OR length(v_slug)>80 OR v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$') THEN
   RAISE EXCEPTION 'Use a web address of at most 80 lowercase letters, numbers and hyphens'; END IF;
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
END; $$;
REVOKE ALL ON FUNCTION public.save_style_web_details(UUID,JSONB,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_style_web_details(UUID,JSONB,UUID) TO authenticated;
