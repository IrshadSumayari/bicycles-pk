-- 360° try-on viewer: an optional 3D model (.glb) per style, with garment
-- colours per variant colour, and/or angle photos per model skin tone and
-- variant colour.
-- Stored on the style beside product_guide and returned by catalog_product.
-- Paths must belong to the same style, so one style cannot show another's files.
CREATE SCHEMA IF NOT EXISTS app_private;
CREATE FUNCTION app_private.valid_try_on(p JSONB, p_style UUID) RETURNS BOOLEAN LANGUAGE plpgsql IMMUTABLE SET search_path=public AS $$
DECLARE k TEXT; v JSONB; f JSONB; sets JSONB; prefix TEXT:='styles/'||p_style::text||'/';
BEGIN
 IF jsonb_typeof(p) IS DISTINCT FROM 'object' OR p-ARRAY['model_path','garment_materials','colors','models']<>'{}'::jsonb THEN RETURN false; END IF;
 IF p ? 'model_path' AND (jsonb_typeof(p->'model_path') IS DISTINCT FROM 'string'
  OR left(p->>'model_path',length(prefix))<>prefix
  OR substr(p->>'model_path',length(prefix)+1)!~'^[0-9a-f-]{36}\.glb$') THEN RETURN false; END IF;
 IF p ? 'garment_materials' THEN
  IF jsonb_typeof(p->'garment_materials') IS DISTINCT FROM 'array' OR jsonb_array_length(p->'garment_materials')>20 THEN RETURN false; END IF;
  FOR v IN SELECT jsonb_array_elements(p->'garment_materials') LOOP
   IF jsonb_typeof(v) IS DISTINCT FROM 'string' OR length(trim(v#>>'{}')) NOT BETWEEN 1 AND 80 THEN RETURN false; END IF;
  END LOOP;
 END IF;
 IF p ? 'colors' THEN
  IF jsonb_typeof(p->'colors') IS DISTINCT FROM 'object' OR (SELECT count(*) FROM jsonb_object_keys(p->'colors'))>30 THEN RETURN false; END IF;
  FOR k,v IN SELECT * FROM jsonb_each(p->'colors') LOOP
   IF length(trim(k)) NOT BETWEEN 1 AND 60 OR jsonb_typeof(v) IS DISTINCT FROM 'string' OR (v#>>'{}')!~'^#[0-9a-fA-F]{6}$' THEN RETURN false; END IF;
  END LOOP;
 END IF;
 -- Angle photos per model skin tone (fixed list, shared with the website), then per colour.
 IF p ? 'models' THEN
  IF jsonb_typeof(p->'models') IS DISTINCT FROM 'object'
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(p->'models') t WHERE t NOT IN('fair','wheatish','dusky','deep')) THEN RETURN false; END IF;
  FOR sets IN SELECT value FROM jsonb_each(p->'models') LOOP
   IF jsonb_typeof(sets) IS DISTINCT FROM 'object' OR (SELECT count(*) FROM jsonb_object_keys(sets))>30 THEN RETURN false; END IF;
   FOR k,v IN SELECT * FROM jsonb_each(sets) LOOP
    IF length(trim(k)) NOT BETWEEN 1 AND 60 OR jsonb_typeof(v) IS DISTINCT FROM 'array' OR jsonb_array_length(v) NOT BETWEEN 4 AND 72 THEN RETURN false; END IF;
    FOR f IN SELECT jsonb_array_elements(v) LOOP
     IF jsonb_typeof(f) IS DISTINCT FROM 'string' OR left(f#>>'{}',length(prefix))<>prefix
      OR substr(f#>>'{}',length(prefix)+1)!~'^spin/[0-9a-f-]{36}\.(webp|jpg)$' THEN RETURN false; END IF;
    END LOOP;
   END LOOP;
  END LOOP;
 END IF;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION app_private.valid_try_on(JSONB,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION app_private.valid_try_on(JSONB,UUID) TO authenticated;
ALTER TABLE public.product_styles ADD COLUMN try_on JSONB NOT NULL DEFAULT '{}'::jsonb
 CONSTRAINT try_on_public_fields CHECK(app_private.valid_try_on(try_on,id));

-- 3D files are larger than photos, so they get their own public bucket.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 VALUES('try-on-models','try-on-models',true,26214400,ARRAY['model/gltf-binary'])
 ON CONFLICT DO NOTHING;
DROP POLICY IF EXISTS try_on_models_read ON storage.objects;
CREATE POLICY try_on_models_read ON storage.objects FOR SELECT TO anon,authenticated
 USING (bucket_id='try-on-models');
DROP POLICY IF EXISTS try_on_models_insert ON storage.objects;
CREATE POLICY try_on_models_insert ON storage.objects FOR INSERT TO authenticated
 WITH CHECK (bucket_id='try-on-models' AND public.has_app_role(ARRAY['admin','manager']));
DROP POLICY IF EXISTS try_on_models_delete ON storage.objects;
CREATE POLICY try_on_models_delete ON storage.objects FOR DELETE TO authenticated
 USING (bucket_id='try-on-models' AND public.has_app_role(ARRAY['admin','manager']));

-- Fails loudly if a fragment is missing, so a changed definition is reviewed.
-- Line endings are normalised first: a Windows checkout stores CRLF bodies.
CREATE OR REPLACE FUNCTION pg_temp.patch_function(p_function regprocedure, p_pairs text[])
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_def text := replace(pg_get_functiondef(p_function), chr(13), ''); i int;
BEGIN
  FOR i IN 1 .. array_length(p_pairs, 1) / 2 LOOP
    IF position(p_pairs[2 * i - 1] IN v_def) = 0 THEN
      RAISE EXCEPTION '% changed; fragment % not found', p_function, i;
    END IF;
    v_def := replace(v_def, p_pairs[2 * i - 1], p_pairs[2 * i]);
  END LOOP;
  EXECUTE v_def;
END $$;

-- Omitted try_on keeps the saved value, so older POS clients do not clear it.
SELECT pg_temp.patch_function('public.save_style_web_details(uuid,jsonb,uuid)', ARRAY[
  '''web_description'',''variants'',''product_guide'')',
  '''web_description'',''variants'',''product_guide'',''try_on'')',
  'IF p ? ''product_guide'' AND NOT',
  'IF p ? ''try_on'' AND NOT app_private.valid_try_on(p->''try_on'',p_style) THEN RAISE EXCEPTION ''Enter a valid 3D model, garment colours and model photos for this style''; END IF;
 IF p ? ''product_guide'' AND NOT',
  'UPDATE public.product_styles SET product_guide=',
  'UPDATE public.product_styles SET try_on=CASE WHEN p ? ''try_on'' THEN p->''try_on'' ELSE try_on END,product_guide=',
  '''product_guide'',s.product_guide,',
  '''product_guide'',s.product_guide,''try_on'',s.try_on,']);
SELECT pg_temp.patch_function('public.catalog_product(text)', ARRAY[
  '''description'',st.web_description,',
  '''description'',st.web_description,''try_on'',st.try_on,']);

-- Product cards turn through angle photos on hover. A card uses the angle set
-- that contains its main photo, else the set for the main photo's colour (or
-- the first one) on the first model tone that has it, otherwise the style's
-- other photos. Only colours sold online are used, as for the main photo.
CREATE FUNCTION app_private.catalog_angle_paths(p_style UUID, p_image TEXT) RETURNS TEXT[] LANGUAGE sql STABLE SET search_path=public AS $$
 WITH visible AS (
  SELECT DISTINCT lower(trim(c.color)) AS color FROM public.public_catalog c
  WHERE c.style_id=p_style AND c.price>0 AND c.color IS NOT NULL),
 card AS (SELECT lower(trim(i.variant_color)) AS color FROM public.product_images i WHERE i.style_id=p_style AND i.storage_path=p_image LIMIT 1),
 spin AS (
  SELECT e.value FROM public.product_styles s, jsonb_each(coalesce(s.try_on->'models','{}')) m, jsonb_each(m.value) e
  WHERE s.id=p_style AND lower(trim(e.key)) IN (SELECT color FROM visible)
  ORDER BY coalesce(e.value ? p_image,false) DESC, lower(trim(e.key))=(SELECT color FROM card) DESC NULLS LAST,
   array_position(ARRAY['fair','wheatish','dusky','deep'],m.key), e.key LIMIT 1)
 SELECT coalesce(
  (SELECT array_agg(f ORDER BY n) FROM spin, jsonb_array_elements_text(spin.value) WITH ORDINALITY a(f,n)),
  (SELECT CASE WHEN count(*)>1 THEN array_agg(storage_path ORDER BY sort_order,id) END FROM (
    SELECT i.storage_path,i.sort_order,i.id FROM public.product_images i
    WHERE i.style_id=p_style AND (i.variant_color IS NULL OR lower(trim(i.variant_color)) IN (SELECT color FROM visible))
    ORDER BY i.sort_order,i.id LIMIT 4) photos))
$$;
REVOKE ALL ON FUNCTION app_private.catalog_angle_paths(UUID,TEXT) FROM PUBLIC,anon,authenticated;

-- catalog_list gains a column, so it is dropped and recreated from its
-- current definition, with its grants restored.
DO $$ DECLARE def TEXT:=replace(pg_get_functiondef('public.catalog_list(jsonb)'::regprocedure),chr(13),''); BEGIN
 IF position('image_path text, colors text[]' IN def)=0 OR position('s.image_path,s.colors' IN def)=0 THEN RAISE EXCEPTION 'catalog_list changed'; END IF;
 def:=replace(def,'image_path text, colors text[]','image_path text, angle_paths text[], colors text[]');
 def:=replace(def,'s.image_path,s.colors','s.image_path,app_private.catalog_angle_paths(s.style_id,s.image_path),s.colors');
 DROP FUNCTION public.catalog_list(jsonb);
 EXECUTE def;
END $$;
REVOKE ALL ON FUNCTION public.catalog_list(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.catalog_list(JSONB) TO anon,authenticated;
