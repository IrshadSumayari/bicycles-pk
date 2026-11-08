-- Optional supplier-confirmed lingerie attributes; existing sizes/SKUs/stock unchanged.
ALTER TABLE public.product_styles ADD COLUMN lingerie JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.product_styles ADD CONSTRAINT lingerie_public_fields CHECK (
 jsonb_typeof(lingerie)='object' AND lingerie-ARRAY['product_type','padding','wire','coverage','composition','sizing_system']='{}'::jsonb
 AND (NOT(lingerie ? 'product_type') OR jsonb_typeof(lingerie->'product_type') IN ('string','null'))
 AND (NOT(lingerie ? 'padding') OR jsonb_typeof(lingerie->'padding') IN ('string','null'))
 AND (NOT(lingerie ? 'wire') OR jsonb_typeof(lingerie->'wire') IN ('string','null'))
 AND (NOT(lingerie ? 'coverage') OR jsonb_typeof(lingerie->'coverage') IN ('string','null'))
 AND (NOT(lingerie ? 'composition') OR jsonb_typeof(lingerie->'composition') IN ('string','null'))
 AND (NOT(lingerie ? 'sizing_system') OR jsonb_typeof(lingerie->'sizing_system') IN ('string','null'))
 AND (lingerie->>'product_type' IS NULL OR lingerie->>'product_type' IN ('everyday','t_shirt','bralette','sports','nursing','minimizer','push_up','strapless','brief','thong','boyshort','pyjama_set','nightdress','robe','shapewear','camisole','matching_set'))
 AND (lingerie->>'padding' IS NULL OR lingerie->>'padding' IN ('none','light','padded','removable'))
 AND (lingerie->>'wire' IS NULL OR lingerie->>'wire' IN ('wireless','underwired'))
 AND (lingerie->>'coverage' IS NULL OR lingerie->>'coverage' IN ('full','medium','low'))
 AND coalesce(length(lingerie->>'composition'),0)<=500 AND coalesce(length(lingerie->>'sizing_system'),0)<=60);
ALTER TABLE public.product_variants ADD COLUMN bra_band TEXT CHECK(bra_band IS NULL OR bra_band ~ '^[0-9]{2,3}$'),
 ADD COLUMN bra_cup TEXT CHECK(bra_cup IS NULL OR bra_cup ~ '^[A-Z]{1,3}$'),
 ADD CONSTRAINT bra_labels_pair CHECK((bra_band IS NULL)=(bra_cup IS NULL));

-- Wrap the existing stock-safe save transaction; do not copy old ledger code.
ALTER FUNCTION public.save_style(JSONB) RENAME TO save_style_base;
REVOKE ALL ON FUNCTION public.save_style_base(JSONB) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.save_style(p JSONB) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE style UUID; attrs JSONB; row JSONB; band TEXT; cup TEXT;
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF p ? 'lingerie' AND jsonb_typeof(p->'lingerie') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Lingerie attributes must be an object'; END IF;
 style:=public.save_style_base(p);
 IF p ? 'lingerie' THEN
  attrs:=jsonb_strip_nulls(p->'lingerie');
  -- Column constraints validate every key/value, including direct staff writes.
  UPDATE public.product_styles SET lingerie=attrs WHERE id=style;
 END IF;
 FOR row IN SELECT jsonb_array_elements(p->'variants') LOOP
  IF row ? 'bra_band' OR row ? 'bra_cup' THEN
   band:=nullif(trim(row->>'bra_band'),''); cup:=nullif(trim(row->>'bra_cup'),'');
   IF (band IS NULL)<>(cup IS NULL) OR (band IS NOT NULL AND (band !~ '^[0-9]{2,3}$' OR cup !~ '^[A-Z]{1,3}$')) THEN
    RAISE EXCEPTION 'Enter both supplier band and uppercase cup labels, or leave both blank'; END IF;
   UPDATE public.product_variants SET bra_band=band,bra_cup=cup WHERE style_id=style AND sku=trim(row->>'sku');
  END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.product_variants WHERE style_id=style AND bra_band IS NOT NULL)
 AND NOT EXISTS(SELECT 1 FROM public.product_styles WHERE id=style AND nullif(trim(lingerie->>'sizing_system'),'') IS NOT NULL) THEN
  RAISE EXCEPTION 'Enter the supplier sizing system before adding band and cup labels'; END IF;
 RETURN style;
END $$;
REVOKE ALL ON FUNCTION public.save_style(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_style(JSONB) TO authenticated;

-- Extend narrow public contracts; never expose costs or stock quantities.
CREATE FUNCTION pg_temp.patch_lingerie(fn regprocedure, pairs TEXT[]) RETURNS void LANGUAGE plpgsql AS $$
DECLARE def TEXT:=replace(pg_get_functiondef(fn),chr(13),''); i INT;
BEGIN
 FOR i IN 1..array_length(pairs,1)/2 LOOP
  IF position(pairs[i*2-1] IN def)=0 THEN RAISE EXCEPTION '% changed; fragment % missing',fn,i; END IF;
  def:=replace(def,pairs[i*2-1],pairs[i*2]);
 END LOOP;
 EXECUTE def;
END $$;
SELECT pg_temp.patch_lingerie('public.catalog_list(jsonb)',ARRAY[
 'FROM public.catalog_style_rows() s','FROM public.catalog_style_rows() s JOIN public.product_styles ls ON ls.id=s.style_id',
 'AND EXISTS(SELECT 1 FROM public.public_catalog c WHERE c.style_id=s.style_id AND c.price>0',
 'AND EXISTS(SELECT 1 FROM public.public_catalog c JOIN public.product_variants lv ON lv.id=c.variant_id WHERE c.style_id=s.style_id AND c.price>0
 AND (nullif(p->>''product_type'','''') IS NULL OR ls.lingerie->>''product_type''=p->>''product_type'')
 AND (nullif(p->>''padding'','''') IS NULL OR ls.lingerie->>''padding''=p->>''padding'')
 AND (nullif(p->>''wire'','''') IS NULL OR ls.lingerie->>''wire''=p->>''wire'')
 AND (nullif(p->>''coverage'','''') IS NULL OR ls.lingerie->>''coverage''=p->>''coverage'')
 AND (nullif(p->>''material'','''') IS NULL OR ls.material=p->>''material'')
 AND (nullif(p->>''sizing_system'','''') IS NULL OR ls.lingerie->>''sizing_system''=p->>''sizing_system'')
 AND (nullif(p->>''band'','''') IS NULL OR lv.bra_band=p->>''band'')
 AND (nullif(p->>''cup'','''') IS NULL OR lv.bra_cup=p->>''cup'')'
]);
SELECT pg_temp.patch_lingerie('public.catalog_product(text)',ARRAY[
 '''description'',st.web_description,','''description'',st.web_description,''lingerie'',st.lingerie,',
 '''variant_id'',c.variant_id,''size'',c.size,','''variant_id'',c.variant_id,''bra_band'',(SELECT bra_band FROM public.product_variants WHERE id=c.variant_id),''bra_cup'',(SELECT bra_cup FROM public.product_variants WHERE id=c.variant_id),''size'',c.size,'
]);
SELECT pg_temp.patch_lingerie('public.catalog_facets(text)',ARRAY[
 '''sizes'',coalesce','''lingerie_filters_version'',1,
 ''product_type'',coalesce(array_agg(DISTINCT s.lingerie->>''product_type'' ORDER BY s.lingerie->>''product_type'') FILTER(WHERE s.lingerie->>''product_type'' IS NOT NULL),''{}''::text[]),
 ''padding'',coalesce(array_agg(DISTINCT s.lingerie->>''padding'' ORDER BY s.lingerie->>''padding'') FILTER(WHERE s.lingerie->>''padding'' IS NOT NULL),''{}''::text[]),
 ''wire'',coalesce(array_agg(DISTINCT s.lingerie->>''wire'' ORDER BY s.lingerie->>''wire'') FILTER(WHERE s.lingerie->>''wire'' IS NOT NULL),''{}''::text[]),
 ''coverage'',coalesce(array_agg(DISTINCT s.lingerie->>''coverage'' ORDER BY s.lingerie->>''coverage'') FILTER(WHERE s.lingerie->>''coverage'' IS NOT NULL),''{}''::text[]),
 ''sizing_system'',coalesce(array_agg(DISTINCT s.lingerie->>''sizing_system'' ORDER BY s.lingerie->>''sizing_system'') FILTER(WHERE s.lingerie->>''sizing_system'' IS NOT NULL),''{}''::text[]),
 ''material'',coalesce(array_agg(DISTINCT s.material ORDER BY s.material) FILTER(WHERE nullif(s.material,'''') IS NOT NULL),''{}''::text[]),
 ''band'',coalesce(array_agg(DISTINCT v.bra_band ORDER BY v.bra_band) FILTER(WHERE v.bra_band IS NOT NULL),''{}''::text[]),
 ''cup'',coalesce(array_agg(DISTINCT v.bra_cup ORDER BY v.bra_cup) FILTER(WHERE v.bra_cup IS NOT NULL),''{}''::text[]),''sizes'',coalesce',
 'FROM public.public_catalog c WHERE','FROM public.public_catalog c JOIN public.product_styles s ON s.id=c.style_id JOIN public.product_variants v ON v.id=c.variant_id WHERE'
]);
