-- Validation is kept outside the exposed public API schema.
CREATE SCHEMA IF NOT EXISTS app_private;
REVOKE ALL ON SCHEMA app_private FROM PUBLIC;
GRANT USAGE ON SCHEMA app_private TO authenticated;
CREATE FUNCTION app_private.valid_product_guide(p JSONB) RETURNS BOOLEAN LANGUAGE plpgsql IMMUTABLE SET search_path=public AS $$
DECLARE c JSONB; r JSONB; k TEXT; seen TEXT[]:='{}'; label TEXT;
BEGIN
 IF jsonb_typeof(p) IS DISTINCT FROM 'object' OR p-ARRAY['fit','care','included','size_chart']<>'{}'::jsonb THEN RETURN false; END IF;
 FOREACH k IN ARRAY ARRAY['fit','care','included'] LOOP
  IF p ? k AND (jsonb_typeof(p->k) IS DISTINCT FROM 'string' OR length(p->>k)>2000) THEN RETURN false; END IF;
 END LOOP;
 IF NOT(p ? 'size_chart') THEN RETURN true; END IF;
 c:=p->'size_chart';
 IF jsonb_typeof(c) IS DISTINCT FROM 'object' OR c-ARRAY['unit','basis','source','rows']<>'{}'::jsonb
 OR coalesce(c->>'unit','') NOT IN ('cm','in') OR coalesce(c->>'basis','') NOT IN ('body','garment')
 OR jsonb_typeof(c->'source') IS DISTINCT FROM 'string' OR coalesce(length(trim(c->>'source')),0)=0 OR length(c->>'source')>160
 OR jsonb_typeof(c->'rows') IS DISTINCT FROM 'array' THEN RETURN false; END IF;
 IF jsonb_array_length(c->'rows') NOT BETWEEN 1 AND 30 THEN RETURN false; END IF;
 FOR r IN SELECT jsonb_array_elements(c->'rows') LOOP
  IF jsonb_typeof(r) IS DISTINCT FROM 'object' OR r-ARRAY['size','underbust','bust','waist','hips']<>'{}'::jsonb
  OR jsonb_typeof(r->'size') IS DISTINCT FROM 'string' OR coalesce(length(trim(r->>'size')),0)=0 THEN RETURN false; END IF;
  FOR k IN SELECT jsonb_object_keys(r) LOOP
   IF jsonb_typeof(r->k) IS DISTINCT FROM 'string' OR length(r->>k)>60 THEN RETURN false; END IF;
  END LOOP;
  IF coalesce(nullif(trim(r->>'underbust'),''),nullif(trim(r->>'bust'),''),nullif(trim(r->>'waist'),''),nullif(trim(r->>'hips'),'')) IS NULL THEN RETURN false; END IF;
  label:=lower(trim(r->>'size')); IF label=ANY(seen) THEN RETURN false; END IF; seen:=seen||label;
 END LOOP;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION app_private.valid_product_guide(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION app_private.valid_product_guide(JSONB) TO authenticated;
ALTER TABLE public.product_styles ADD COLUMN product_guide JSONB NOT NULL DEFAULT '{}'::jsonb
 CONSTRAINT product_guide_public_fields CHECK(app_private.valid_product_guide(product_guide));

-- Extend the existing idempotent editorial transaction, retaining omitted fields
-- for older clients. Product guides do not modify shared charts or inventory.
CREATE FUNCTION pg_temp.patch_product_guide(fn regprocedure,pairs TEXT[]) RETURNS void LANGUAGE plpgsql AS $$
DECLARE def TEXT:=replace(pg_get_functiondef(fn),chr(13),''); i INT;
BEGIN
 FOR i IN 1..array_length(pairs,1)/2 LOOP
  IF position(pairs[i*2-1] IN def)=0 THEN RAISE EXCEPTION '% changed; fragment % missing',fn,i; END IF;
  def:=replace(def,pairs[i*2-1],pairs[i*2]);
 END LOOP;
 EXECUTE def;
END $$;
SELECT pg_temp.patch_product_guide('public.save_style_web_details(uuid,jsonb,uuid)',ARRAY[
 '''web_description'',''variants'')','''web_description'',''variants'',''product_guide'')',
 'IF p ? ''variants'' THEN',
 'IF p ? ''product_guide'' AND NOT app_private.valid_product_guide(p->''product_guide'') THEN RAISE EXCEPTION ''Enter a valid supplier chart and approved product information''; END IF;
 IF p ? ''variants'' THEN',
 'UPDATE public.product_styles SET slug=',
 'UPDATE public.product_styles SET product_guide=CASE WHEN p ? ''product_guide'' THEN p->''product_guide'' ELSE product_guide END,slug=',
 '''web_description'',s.web_description,',
 '''web_description'',s.web_description,''product_guide'',s.product_guide,'
]);
SELECT pg_temp.patch_product_guide('public.catalog_product(text)',ARRAY[
 '''description'',st.web_description,',
 '''description'',st.web_description,''product_guide'',st.product_guide,'
]);