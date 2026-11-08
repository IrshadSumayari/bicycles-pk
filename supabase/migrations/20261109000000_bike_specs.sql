-- Bicycle specifications ("At a glance"): optional free-text values per style.
-- Keys must match specFields in shared/bicycles.ts.
CREATE FUNCTION app_private.valid_bike_specs(p JSONB) RETURNS BOOLEAN LANGUAGE sql IMMUTABLE SET search_path=public AS $$
 SELECT jsonb_typeof(p)='object'
  AND p - ARRAY['frame','fork','wheel_size','tyres','gears','drivetrain','brakes','suspension','weight',
   'max_load','rider_height','age_range','motor','battery','range','folded_size','warranty'] = '{}'::jsonb
  AND NOT EXISTS(SELECT 1 FROM jsonb_each(p) e
   WHERE jsonb_typeof(e.value)<>'string' OR length(e.value#>>'{}')>120 OR btrim(e.value#>>'{}')='')
$$;
REVOKE ALL ON FUNCTION app_private.valid_bike_specs(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION app_private.valid_bike_specs(JSONB) TO authenticated;

ALTER TABLE public.product_styles ADD COLUMN specs JSONB NOT NULL DEFAULT '{}'::jsonb
 CONSTRAINT bike_specs_fields CHECK(app_private.valid_bike_specs(specs));

-- Wrap the current stock-safe save; an omitted "specs" keeps the stored value.
ALTER FUNCTION public.save_style(JSONB) RENAME TO save_style_before_specs;
REVOKE ALL ON FUNCTION public.save_style_before_specs(JSONB) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.save_style(p JSONB) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE style UUID; v_specs JSONB;
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF p ? 'specs' THEN
  IF jsonb_typeof(p->'specs') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Specifications must be an object'; END IF;
  -- Blank values mean "not stated" and are removed.
  SELECT coalesce(jsonb_object_agg(e.key,to_jsonb(btrim(e.value#>>'{}'))),'{}'::jsonb) INTO v_specs
  FROM jsonb_each(p->'specs') e WHERE jsonb_typeof(e.value)='string' AND btrim(e.value#>>'{}')<>'';
  IF NOT app_private.valid_bike_specs(v_specs) THEN
   RAISE EXCEPTION 'Use only the listed specifications, each up to 120 characters'; END IF;
 END IF;
 style:=public.save_style_before_specs(p - 'specs');
 IF p ? 'specs' THEN UPDATE public.product_styles SET specs=v_specs WHERE id=style; END IF;
 RETURN style;
END $$;
REVOKE ALL ON FUNCTION public.save_style(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_style(JSONB) TO authenticated;

-- Return specs with the public product; no costs or stock quantities are added.
DO $$ DECLARE def TEXT:=replace(pg_get_functiondef('public.catalog_product(text)'::regprocedure),chr(13),'');
BEGIN
 IF position('''description'',st.web_description,' IN def)=0 THEN RAISE EXCEPTION 'catalog_product changed'; END IF;
 EXECUTE replace(def,'''description'',st.web_description,','''description'',st.web_description,''specs'',st.specs,');
END $$;
