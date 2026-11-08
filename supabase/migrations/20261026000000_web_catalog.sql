-- Website media and merchandising. Public responses use explicit allow-lists;
-- table access remains staff-only and inventory is exposed only as a band.
ALTER TABLE public.size_schemes ADD COLUMN IF NOT EXISTS size_chart JSONB
 CHECK (size_chart IS NULL OR jsonb_typeof(size_chart) IN ('object','array'));

CREATE TABLE IF NOT EXISTS public.product_images (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 style_id UUID NOT NULL REFERENCES public.product_styles(id) ON DELETE CASCADE,
 variant_color TEXT, storage_path TEXT NOT NULL, alt TEXT,
 sort_order INT NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK (storage_path LIKE 'styles/'||style_id::text||'/%')
);
CREATE INDEX IF NOT EXISTS idx_product_images_style_order ON public.product_images(style_id,sort_order,id);
CREATE TABLE IF NOT EXISTS public.collections (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 slug TEXT NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
 name TEXT NOT NULL CHECK (length(trim(name))>0), description TEXT, hero_image_path TEXT,
 published BOOL NOT NULL DEFAULT false, sort_order INT NOT NULL DEFAULT 0,
 starts_at TIMESTAMPTZ, ends_at TIMESTAMPTZ,
 CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at>starts_at)
);
CREATE TABLE IF NOT EXISTS public.collection_styles (
 collection_id UUID NOT NULL REFERENCES public.collections(id) ON DELETE CASCADE,
 style_id UUID NOT NULL REFERENCES public.product_styles(id) ON DELETE CASCADE,
 sort_order INT NOT NULL DEFAULT 0, PRIMARY KEY(collection_id,style_id)
);
CREATE INDEX IF NOT EXISTS idx_collection_styles_style ON public.collection_styles(style_id,collection_id);
-- The existing style slug and collection slug UNIQUE constraints index lookups.
DO $$ DECLARE t TEXT; BEGIN
 FOREACH t IN ARRAY ARRAY['product_images','collections','collection_styles'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('DROP POLICY IF EXISTS staff_read ON public.%I',t);
  EXECUTE format('CREATE POLICY staff_read ON public.%I FOR SELECT TO authenticated USING (public.is_staff())',t);
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated',t);
  EXECUTE format('GRANT SELECT ON public.%I TO authenticated',t);
 END LOOP;
END $$;

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 VALUES('product-images','product-images',true,5242880,ARRAY['image/jpeg','image/png','image/webp'])
 ON CONFLICT DO NOTHING;
DROP POLICY IF EXISTS product_images_read ON storage.objects;
CREATE POLICY product_images_read ON storage.objects FOR SELECT TO anon,authenticated
 USING (bucket_id='product-images');
DROP POLICY IF EXISTS product_images_insert ON storage.objects;
CREATE POLICY product_images_insert ON storage.objects FOR INSERT TO authenticated
 WITH CHECK (bucket_id='product-images' AND public.has_app_role(ARRAY['admin','manager']));
DROP POLICY IF EXISTS product_images_update ON storage.objects;
CREATE POLICY product_images_update ON storage.objects FOR UPDATE TO authenticated
 USING (bucket_id='product-images' AND public.has_app_role(ARRAY['admin','manager']))
 WITH CHECK (bucket_id='product-images' AND public.has_app_role(ARRAY['admin','manager']));
DROP POLICY IF EXISTS product_images_delete ON storage.objects;
CREATE POLICY product_images_delete ON storage.objects FOR DELETE TO authenticated
 USING (bucket_id='product-images' AND public.has_app_role(ARRAY['admin','manager']));

CREATE OR REPLACE FUNCTION public.save_product_images(p_style UUID,p_images JSONB,p_request_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
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
END; $$;

CREATE OR REPLACE FUNCTION public.save_collection(p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
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
END; $$;

CREATE OR REPLACE FUNCTION public.set_collection_styles(p_collection UUID,p_style_ids UUID[],p_request_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
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

-- Setting a boolean is naturally idempotent. Dry runs never change any row.
CREATE OR REPLACE FUNCTION public.publish_style(p_style UUID,p_published BOOL,p_dry_run BOOL DEFAULT false)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
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

-- Private aggregation shared by the public functions. created_at is used only
-- for sorting and is never emitted by the public wrappers.
CREATE OR REPLACE FUNCTION public.catalog_style_rows()
RETURNS TABLE(style_id UUID,slug TEXT,title TEXT,min_price NUMERIC,max_price NUMERIC,
 compare_at_price NUMERIC,image_path TEXT,colors TEXT[],sizes TEXT[],stock_level TEXT,created_at TIMESTAMPTZ)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
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

CREATE OR REPLACE FUNCTION public.catalog_list(p JSONB)
RETURNS TABLE(style_id UUID,slug TEXT,title TEXT,min_price NUMERIC,max_price NUMERIC,
 compare_at_price NUMERIC,image_path TEXT,colors TEXT[],sizes TEXT[],stock_level TEXT,total_count BIGINT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE v_q TEXT:=replace(replace(replace(trim(coalesce(p->>'q','')),E'\\',E'\\\\'),'%',E'\\%'),'_',E'\\_');
 v_sort TEXT:=coalesce(p->>'sort','new'); v_limit INT:=least(48,greatest(1,coalesce((p->>'limit')::int,24)));
 v_offset INT:=greatest(0,coalesce((p->>'offset')::int,0));
BEGIN
 IF v_sort NOT IN ('new','price_asc','price_desc') THEN RAISE EXCEPTION 'Choose new, price_asc or price_desc'; END IF;
 RETURN QUERY
 SELECT s.style_id,s.slug,s.title,s.min_price,s.max_price,s.compare_at_price,s.image_path,s.colors,s.sizes,s.stock_level,count(*) OVER ()
 FROM public.catalog_style_rows() s
 WHERE (v_q='' OR s.title ILIKE '%'||v_q||'%')
 AND (nullif(p->>'collection','') IS NULL OR EXISTS(
  SELECT 1 FROM public.collection_styles cs JOIN public.collections co ON co.id=cs.collection_id
  WHERE cs.style_id=s.style_id AND co.slug=p->>'collection' AND co.published
   AND (co.starts_at IS NULL OR co.starts_at<=now()) AND (co.ends_at IS NULL OR co.ends_at>now())))
 AND EXISTS(SELECT 1 FROM public.public_catalog c WHERE c.style_id=s.style_id AND c.price>0
  AND (nullif(p->>'category','') IS NULL OR c.category=p->>'category')
  AND (nullif(p->>'size','') IS NULL OR c.size=p->>'size')
  AND (nullif(p->>'color','') IS NULL OR c.color=p->>'color')
  AND (nullif(p->>'price_min','') IS NULL OR c.price>=(p->>'price_min')::numeric)
  AND (nullif(p->>'price_max','') IS NULL OR c.price<=(p->>'price_max')::numeric))
 ORDER BY CASE WHEN v_sort='new' THEN s.created_at END DESC,
  CASE WHEN v_sort='price_asc' THEN s.min_price END ASC,
  CASE WHEN v_sort='price_desc' THEN s.min_price END DESC,s.style_id
 LIMIT v_limit OFFSET v_offset;
END; $$;

CREATE OR REPLACE FUNCTION public.catalog_product(p_slug TEXT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT jsonb_build_object('style_id',s.style_id,'slug',s.slug,'title',s.title,
  'description',st.web_description,'kind',st.kind,'brand',st.brand,'material',st.material,'season',st.season,
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

CREATE OR REPLACE FUNCTION public.catalog_collections()
RETURNS TABLE(slug TEXT,name TEXT,description TEXT,hero_image_path TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT c.slug,c.name,c.description,c.hero_image_path FROM public.collections c WHERE c.published
  AND (c.starts_at IS NULL OR c.starts_at<=now()) AND (c.ends_at IS NULL OR c.ends_at>now()) ORDER BY c.sort_order,c.slug;
$$;

CREATE OR REPLACE FUNCTION public.catalog_facets(p_collection TEXT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT jsonb_build_object('sizes',coalesce(array_agg(DISTINCT c.size ORDER BY c.size) FILTER (WHERE c.size IS NOT NULL),'{}'::text[]),
  'colors',coalesce(array_agg(DISTINCT c.color ORDER BY c.color) FILTER (WHERE c.color IS NOT NULL),'{}'::text[]),'price_min',min(c.price),'price_max',max(c.price))
 FROM public.public_catalog c WHERE c.slug IS NOT NULL AND c.price>0 AND (nullif(p_collection,'') IS NULL OR EXISTS(
  SELECT 1 FROM public.collection_styles cs JOIN public.collections co ON co.id=cs.collection_id
  WHERE cs.style_id=c.style_id AND co.slug=p_collection AND co.published
   AND (co.starts_at IS NULL OR co.starts_at<=now()) AND (co.ends_at IS NULL OR co.ends_at>now())));
$$;

REVOKE ALL ON FUNCTION public.catalog_style_rows() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.save_product_images(UUID,JSONB,UUID),public.save_collection(JSONB),
 public.set_collection_styles(UUID,UUID[],UUID),public.publish_style(UUID,BOOL,BOOL) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_product_images(UUID,JSONB,UUID),public.save_collection(JSONB),
 public.set_collection_styles(UUID,UUID[],UUID),public.publish_style(UUID,BOOL,BOOL) TO authenticated;
REVOKE ALL ON FUNCTION public.catalog_list(JSONB),public.catalog_product(TEXT),public.catalog_collections(),public.catalog_facets(TEXT) FROM PUBLIC;

-- Preserve the safe legacy view; no underlying public table is readable by anon.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;
GRANT SELECT ON public.public_catalog TO anon;
GRANT EXECUTE ON FUNCTION public.catalog_list(JSONB),public.catalog_product(TEXT),public.catalog_collections(),public.catalog_facets(TEXT) TO anon,authenticated;
