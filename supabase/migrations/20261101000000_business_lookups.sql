-- Owner-managed catalog values. No invented brands, banks, customers or products.
ALTER TABLE public.categories ADD COLUMN IF NOT EXISTS active BOOLEAN NOT NULL DEFAULT true;
UPDATE public.categories SET active=true WHERE active IS NULL;
ALTER TABLE public.categories ALTER COLUMN active SET NOT NULL;
ALTER TABLE public.size_schemes ADD COLUMN active BOOLEAN NOT NULL DEFAULT true;
CREATE TABLE public.business_lookups(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 kind TEXT NOT NULL CHECK(kind IN ('brand','material','season','color','fit','bank','return_reason','stock_reason','customer_tier')),
 value TEXT NOT NULL CHECK(length(trim(value)) BETWEEN 1 AND 200),
 active BOOLEAN NOT NULL DEFAULT true
);
CREATE UNIQUE INDEX business_lookup_unique ON public.business_lookups(kind,lower(value));
ALTER TABLE public.business_lookups ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.business_lookups FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.business_lookups TO authenticated;
CREATE POLICY business_lookups_read ON public.business_lookups FOR SELECT TO authenticated USING(public.is_staff());
REVOKE INSERT,UPDATE,DELETE ON public.categories,public.size_schemes FROM authenticated;
REVOKE DELETE ON public.garment_types FROM authenticated;

-- Register only metadata already entered on actual catalog records.
INSERT INTO public.business_lookups(kind,value)
SELECT kind,min(trim(value)) FROM (
 SELECT 'brand' kind,brand value FROM public.product_styles UNION ALL
 SELECT 'material',material FROM public.product_styles UNION ALL
 SELECT 'season',season FROM public.product_styles UNION ALL
 SELECT 'color',color FROM public.product_variants UNION ALL
 SELECT 'fit',fit FROM public.product_variants UNION ALL
 SELECT 'customer_tier',price_tier FROM public.customers WHERE lower(price_tier)<>'standard'
) x WHERE length(trim(coalesce(value,''))) BETWEEN 1 AND 200 GROUP BY kind,lower(trim(value));

CREATE TABLE public.lookup_events(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),kind TEXT NOT NULL,lookup_id TEXT NOT NULL,
 action TEXT NOT NULL CHECK(action IN ('save','delete')),old_value JSONB,new_value JSONB,
 created_by UUID DEFAULT auth.uid() REFERENCES public.users(id),created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.lookup_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lookup_events FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.lookup_events TO authenticated;
CREATE POLICY lookup_events_read ON public.lookup_events FOR SELECT TO authenticated USING(public.has_app_role(ARRAY['admin','manager']));
CREATE TRIGGER lookup_events_immutable BEFORE UPDATE OR DELETE ON public.lookup_events FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();

CREATE FUNCTION public.register_catalog_lookups() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r RECORD;
BEGIN
 FOR r IN SELECT key,value FROM jsonb_each_text(to_jsonb(NEW))
 WHERE key=ANY(CASE WHEN TG_TABLE_NAME='product_styles' THEN ARRAY['brand','material','season'] WHEN TG_TABLE_NAME='customers' THEN ARRAY['price_tier'] ELSE ARRAY['color','fit'] END)
 AND length(trim(coalesce(value,''))) BETWEEN 1 AND 200 LOOP
  IF r.key='price_tier' AND lower(trim(r.value))='standard' THEN CONTINUE; END IF;
  INSERT INTO public.business_lookups(kind,value) VALUES(CASE WHEN r.key='price_tier' THEN 'customer_tier' ELSE r.key END,trim(r.value)) ON CONFLICT DO NOTHING;
 END LOOP;
 RETURN NEW;
END; $$;
CREATE TRIGGER register_style_lookups AFTER INSERT OR UPDATE OF brand,material,season ON public.product_styles FOR EACH ROW EXECUTE FUNCTION public.register_catalog_lookups();
CREATE TRIGGER register_variant_lookups AFTER INSERT OR UPDATE OF color,fit ON public.product_variants FOR EACH ROW EXECUTE FUNCTION public.register_catalog_lookups();
CREATE TRIGGER register_customer_tiers AFTER INSERT OR UPDATE OF price_tier ON public.customers FOR EACH ROW EXECUTE FUNCTION public.register_catalog_lookups();
REVOKE ALL ON FUNCTION public.register_catalog_lookups() FROM PUBLIC,anon,authenticated;

-- The historical initial migration is retained. Remove its exact unused templates
-- in the final schema on new installs as well as upgrades. Never delete product data.
DELETE FROM public.categories c WHERE (c.name,c.description) IN (
 ('Electronics','Electronic devices and accessories'),('Food & Beverage','Food and drink products'),
 ('Home & Garden','Home improvement and garden supplies'),('Books & Media','Books, magazines, and media content'),
 ('Health & Beauty','Healthcare and beauty products'),('Sports & Outdoors','Sports equipment and outdoor gear'),
 ('Automotive','Car parts and automotive supplies'),('General','General merchandise'))
 AND NOT EXISTS(SELECT 1 FROM public.product_styles s WHERE s.category_id=c.id);
-- If a template category is still assigned, keep the assignment but hide it from new selections.
UPDATE public.categories c SET active=false WHERE (c.name,c.description) IN (
 ('Electronics','Electronic devices and accessories'),('Food & Beverage','Food and drink products'),
 ('Home & Garden','Home improvement and garden supplies'),('Books & Media','Books, magazines, and media content'),
 ('Health & Beauty','Healthcare and beauty products'),('Sports & Outdoors','Sports equipment and outdoor gear'),
 ('Automotive','Car parts and automotive supplies'));

CREATE FUNCTION public.lookup_usage(p_kind TEXT,p_id TEXT) RETURNS BIGINT LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE v_value TEXT; v_count BIGINT;
BEGIN
 CASE p_kind
 WHEN 'category' THEN SELECT count(*) INTO v_count FROM public.product_styles WHERE category_id=p_id::uuid;
 WHEN 'size_scheme' THEN SELECT count(*) INTO v_count FROM public.product_styles WHERE size_scheme_id=p_id::uuid;
 WHEN 'garment_type' THEN SELECT (SELECT count(*) FROM public.measurement_sets WHERE garment_type=p_id)
  +(SELECT count(*) FROM public.tailoring_items WHERE garment_type=p_id)+(SELECT count(*) FROM public.tailoring_requests WHERE garment_type=p_id) INTO v_count;
 ELSE
  SELECT value INTO v_value FROM public.business_lookups WHERE id=p_id::uuid AND kind=p_kind;
  CASE p_kind
  WHEN 'brand' THEN SELECT count(*) INTO v_count FROM public.product_styles WHERE lower(brand)=lower(v_value);
  WHEN 'material' THEN SELECT count(*) INTO v_count FROM public.product_styles WHERE lower(material)=lower(v_value);
  WHEN 'season' THEN SELECT count(*) INTO v_count FROM public.product_styles WHERE lower(season)=lower(v_value);
  WHEN 'color' THEN SELECT count(*) INTO v_count FROM public.product_variants WHERE lower(color)=lower(v_value);
  WHEN 'fit' THEN SELECT count(*) INTO v_count FROM public.product_variants WHERE lower(fit)=lower(v_value);
  WHEN 'bank' THEN SELECT (SELECT count(*) FROM public.payments WHERE lower(bank_name)=lower(v_value))
   +(SELECT count(*) FROM public.discounts d WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(d.conditions,'[]'::jsonb)) c WHERE c->>'type'='bank_name' AND lower(c->>'value')=lower(v_value))) INTO v_count;
  WHEN 'stock_reason' THEN SELECT count(*) INTO v_count FROM public.stock_movements WHERE lower(reason)=lower(v_value) OR lower(left(reason,length(v_value)+2))=lower(v_value||': ');
  WHEN 'customer_tier' THEN SELECT (SELECT count(*) FROM public.customers WHERE lower(price_tier)=lower(v_value))+(SELECT count(*) FROM public.discounts d WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(d.conditions,'[]'::jsonb)) c WHERE c->>'type'='customer_tier' AND lower(c->>'value')=lower(v_value))) INTO v_count;
  WHEN 'return_reason' THEN SELECT count(*) INTO v_count FROM public.returns WHERE lower(reason)=lower(v_value) OR lower(left(reason,length(v_value)+2))=lower(v_value||': ');
  ELSE RAISE EXCEPTION 'Unknown lookup type'; END CASE;
 END CASE;
 RETURN coalesce(v_count,0);
END; $$;
REVOKE ALL ON FUNCTION public.lookup_usage(TEXT,TEXT) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.list_business_lookups(p_kind TEXT) RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) THEN RAISE EXCEPTION 'Only managers can manage lookups' USING ERRCODE='42501'; END IF;
 CASE p_kind
 WHEN 'category' THEN RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'description',c.description,'active',c.active,'usage_count',public.lookup_usage(p_kind,c.id::text)) ORDER BY c.name,c.id) FROM public.categories c),'[]'::jsonb);
 WHEN 'size_scheme' THEN RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'code',s.code,'sizes',s.sizes,'active',s.active,'usage_count',public.lookup_usage(p_kind,s.id::text)) ORDER BY s.name,s.id) FROM public.size_schemes s),'[]'::jsonb);
 ELSE
  IF p_kind NOT IN ('brand','material','season','color','fit','bank','return_reason','stock_reason','customer_tier') OR p_kind IS NULL THEN RAISE EXCEPTION 'Unknown lookup type'; END IF;
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',b.id,'name',b.value,'active',b.active,'usage_count',public.lookup_usage(p_kind,b.id::text)) ORDER BY b.value,b.id) FROM public.business_lookups b WHERE b.kind=p_kind),'[]'::jsonb);
 END CASE;
END; $$;

CREATE FUNCTION public.save_business_lookup(p JSONB) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_kind TEXT:=p->>'kind'; v_id UUID:=nullif(p->>'id','')::uuid; v_name TEXT:=trim(p->>'name');
 v_active BOOLEAN:=coalesce((p->>'active')::boolean,true); v_code TEXT:=upper(trim(p->>'code')); v_sizes TEXT[];
 v_before JSONB; v_after JSONB; v_old TEXT;
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) THEN RAISE EXCEPTION 'Only managers can manage lookups' USING ERRCODE='42501'; END IF;
 IF v_name IS NULL OR length(v_name) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Enter a name up to 200 characters'; END IF;
 IF v_kind IS NULL OR v_kind NOT IN ('category','size_scheme','brand','material','season','color','fit','bank','return_reason','stock_reason','customer_tier') THEN RAISE EXCEPTION 'Unknown lookup type'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('business-lookup:'||v_kind,0));
 IF v_kind='category' THEN
  IF EXISTS(SELECT 1 FROM public.categories WHERE lower(name)=lower(v_name) AND id IS DISTINCT FROM v_id) THEN RAISE EXCEPTION 'A category with this name already exists'; END IF;
  IF v_id IS NULL THEN INSERT INTO public.categories(name,description,active) VALUES(v_name,nullif(trim(p->>'description'),''),v_active) RETURNING id,to_jsonb(categories.*) INTO v_id,v_after;
  ELSE
   SELECT to_jsonb(c.*) INTO v_before FROM public.categories c WHERE id=v_id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Category no longer exists'; END IF;
   UPDATE public.categories SET name=v_name,description=nullif(trim(p->>'description'),''),active=v_active WHERE id=v_id RETURNING to_jsonb(categories.*) INTO v_after;
  END IF;
 ELSIF v_kind='size_scheme' THEN
  IF v_code IS NULL OR v_code !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$' OR jsonb_typeof(p->'sizes') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Enter a code and at least one size'; END IF;
  SELECT array_agg(x.value ORDER BY x.ord) INTO v_sizes FROM (
   SELECT trim(value) value,min(ord) ord FROM jsonb_array_elements_text(p->'sizes') WITH ORDINALITY a(value,ord) GROUP BY trim(value)
  ) x;
  IF coalesce(cardinality(v_sizes),0) NOT BETWEEN 1 AND 100 OR EXISTS(SELECT 1 FROM unnest(v_sizes) x WHERE x IS NULL OR length(x) NOT BETWEEN 1 AND 30) THEN RAISE EXCEPTION 'Enter 1–100 distinct sizes, each up to 30 characters'; END IF;
  IF v_id IS NULL THEN INSERT INTO public.size_schemes(code,name,sizes,active) VALUES(v_code,v_name,v_sizes,v_active) RETURNING id,to_jsonb(size_schemes.*) INTO v_id,v_after;
  ELSE
   SELECT to_jsonb(s.*) INTO v_before FROM public.size_schemes s WHERE id=v_id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Size list no longer exists'; END IF;
   UPDATE public.size_schemes SET code=v_code,name=v_name,sizes=v_sizes,active=v_active WHERE id=v_id RETURNING to_jsonb(size_schemes.*) INTO v_after;
  END IF;
 ELSE
  IF v_kind IN ('return_reason','stock_reason') AND lower(v_name)='other' THEN RAISE EXCEPTION 'Other is the built-in free-text option'; END IF;
  IF v_kind='customer_tier' AND lower(v_name)='standard' THEN RAISE EXCEPTION 'Standard is the built-in default customer tier'; END IF;
  IF v_id IS NULL THEN INSERT INTO public.business_lookups(kind,value,active) VALUES(v_kind,v_name,v_active) RETURNING id,to_jsonb(business_lookups.*) INTO v_id,v_after;
  ELSE
   SELECT to_jsonb(b.*),b.value INTO v_before,v_old FROM public.business_lookups b WHERE id=v_id AND kind=v_kind FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Lookup no longer exists'; END IF;
   UPDATE public.business_lookups SET value=v_name,active=v_active WHERE id=v_id RETURNING to_jsonb(business_lookups.*) INTO v_after;
   -- Keep current catalog metadata consistent; posted sale/payment snapshots stay intact.
   IF v_old IS DISTINCT FROM v_name THEN
    CASE v_kind
    WHEN 'brand' THEN UPDATE public.product_styles SET brand=v_name WHERE lower(brand)=lower(v_old);
    WHEN 'material' THEN UPDATE public.product_styles SET material=v_name WHERE lower(material)=lower(v_old);
    WHEN 'season' THEN UPDATE public.product_styles SET season=v_name WHERE lower(season)=lower(v_old);
    WHEN 'color' THEN UPDATE public.product_variants SET color=v_name WHERE lower(color)=lower(v_old);
    WHEN 'fit' THEN UPDATE public.product_variants SET fit=v_name WHERE lower(fit)=lower(v_old);
    WHEN 'customer_tier' THEN
      UPDATE public.customers SET price_tier=v_name WHERE lower(price_tier)=lower(v_old);
      UPDATE public.discounts d SET conditions=(SELECT jsonb_agg(CASE WHEN c->>'type'='customer_tier' AND lower(c->>'value')=lower(v_old) THEN jsonb_set(c,'{value}',to_jsonb(v_name)) ELSE c END) FROM jsonb_array_elements(d.conditions) c) WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(d.conditions,'[]'::jsonb)) c WHERE c->>'type'='customer_tier' AND lower(c->>'value')=lower(v_old));
    WHEN 'bank' THEN UPDATE public.discounts d SET conditions=(SELECT jsonb_agg(CASE WHEN c->>'type'='bank_name' AND lower(c->>'value')=lower(v_old) THEN jsonb_set(c,'{value}',to_jsonb(v_name)) ELSE c END) FROM jsonb_array_elements(d.conditions) c)
      WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(d.conditions,'[]'::jsonb)) c WHERE c->>'type'='bank_name' AND lower(c->>'value')=lower(v_old));
    ELSE NULL; END CASE;
   END IF;
  END IF;
 END IF;
 INSERT INTO public.lookup_events(kind,lookup_id,action,old_value,new_value) VALUES(v_kind,v_id::text,'save',v_before,v_after);
 RETURN v_id;
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'This name or code already exists, or the rename conflicts with existing variants';
END; $$;

CREATE FUNCTION public.delete_business_lookup(p_kind TEXT,p_id TEXT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_before JSONB;
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) THEN RAISE EXCEPTION 'Only managers can manage lookups' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('business-lookup:'||p_kind,0));
 CASE p_kind
 WHEN 'category' THEN SELECT to_jsonb(c.*) INTO v_before FROM public.categories c WHERE id=p_id::uuid FOR UPDATE;
 WHEN 'size_scheme' THEN SELECT to_jsonb(s.*) INTO v_before FROM public.size_schemes s WHERE id=p_id::uuid FOR UPDATE;
 WHEN 'garment_type' THEN SELECT to_jsonb(g.*) INTO v_before FROM public.garment_types g WHERE code=p_id FOR UPDATE;
 ELSE SELECT to_jsonb(b.*) INTO v_before FROM public.business_lookups b WHERE id=p_id::uuid AND kind=p_kind FOR UPDATE;
 END CASE;
 IF v_before IS NULL THEN RAISE EXCEPTION 'Lookup no longer exists'; END IF;
 IF public.lookup_usage(p_kind,p_id)>0 THEN RAISE EXCEPTION 'This lookup is in use. Deactivate it, or reassign its records before deleting.'; END IF;
 CASE p_kind
 WHEN 'category' THEN DELETE FROM public.categories WHERE id=p_id::uuid;
 WHEN 'size_scheme' THEN DELETE FROM public.size_schemes WHERE id=p_id::uuid;
 WHEN 'garment_type' THEN DELETE FROM public.garment_types WHERE code=p_id;
 ELSE DELETE FROM public.business_lookups WHERE id=p_id::uuid AND kind=p_kind;
 END CASE;
 INSERT INTO public.lookup_events(kind,lookup_id,action,old_value) VALUES(p_kind,p_id,'delete',v_before);
END; $$;
REVOKE ALL ON FUNCTION public.list_business_lookups(TEXT),public.save_business_lookup(JSONB),public.delete_business_lookup(TEXT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.list_business_lookups(TEXT),public.save_business_lookup(JSONB),public.delete_business_lookup(TEXT,TEXT) TO authenticated;
