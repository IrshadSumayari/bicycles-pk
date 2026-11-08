-- Bounded counter catalog reads. Safe display metadata preserves existing Product
-- behavior without extra requests; costs remain behind variant_costs RLS.
CREATE INDEX IF NOT EXISTS product_variants_lower_sku_idx ON public.product_variants(lower(sku));
CREATE INDEX IF NOT EXISTS barcodes_lower_code_idx ON public.barcodes(lower(code));
DO $$
DECLARE ext_schema TEXT;
BEGIN
 SELECT n.nspname INTO ext_schema FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace WHERE e.extname='pg_trgm';
 IF ext_schema IS NOT NULL THEN
  EXECUTE format('CREATE INDEX IF NOT EXISTS product_styles_name_trgm_idx ON public.product_styles USING gin (name %I.gin_trgm_ops)', ext_schema);
 END IF;
END $$;

CREATE OR REPLACE FUNCTION public.search_variants(p JSONB DEFAULT '{}'::jsonb)
RETURNS TABLE(variant_id UUID, style_id UUID, sku TEXT, name TEXT, size TEXT,
 color TEXT, kind TEXT, unit TEXT, category TEXT, price NUMERIC, taxable BOOLEAN,
 available NUMERIC, on_hand NUMERIC, barcodes TEXT[], total_count BIGINT,
 fit TEXT, min_stock NUMERIC, active BOOLEAN, track_inventory BOOLEAN,
 image TEXT, description TEXT, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ, barcode TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
 v_q TEXT := trim(coalesce(p->>'q',''));
 v_literal TEXT := replace(replace(replace(v_q, E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_');
 v_location UUID;
 v_active BOOLEAN;
 v_limit INT;
 v_offset INT;
BEGIN
 IF NOT public.is_counter_staff() THEN
  RAISE EXCEPTION 'Only counter staff can search products' USING ERRCODE='42501';
 END IF;
 v_location := nullif(p->>'location_id','')::uuid;
 v_active := coalesce((p->>'active_only')::boolean,true);
 v_limit := least(200,greatest(1,coalesce((p->>'limit')::int,60)));
 v_offset := greatest(0,coalesce((p->>'offset')::int,0));
 -- Mirror getSellingLocationId: first active shop floor, ordered by creation.
 IF v_location IS NULL THEN
  SELECT l.id INTO v_location FROM public.locations l WHERE l.kind='shop_floor' AND l.active ORDER BY l.created_at, l.id LIMIT 1;
 END IF;
 IF v_location IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.locations l WHERE l.id=v_location AND public.is_branch_member(l.branch_id)) THEN
  RAISE EXCEPTION 'Choose a location in your branch' USING ERRCODE='42501';
 END IF;
 RETURN QUERY
 SELECT v.id,s.id,v.sku,s.name,v.size,v.color,s.kind,s.unit,coalesce(c.name,''),v.price,s.taxable,
  coalesce(b.on_hand-b.reserved,0),coalesce(b.on_hand,0),
  ARRAY(SELECT bc.code FROM public.barcodes bc WHERE bc.variant_id=v.id ORDER BY (bc.roll_id IS NOT NULL),bc.code),
  count(*) OVER(),v.fit,v.min_stock,(v.active AND s.active),s.track_inventory,s.image_url,coalesce(s.description,''),v.created_at,v.updated_at,
  (SELECT bc.code FROM public.barcodes bc WHERE bc.variant_id=v.id AND bc.roll_id IS NULL ORDER BY bc.code LIMIT 1)
 FROM public.product_variants v
 JOIN public.product_styles s ON s.id=v.style_id
 LEFT JOIN public.categories c ON c.id=s.category_id
 LEFT JOIN public.stock_balances b ON b.variant_id=v.id AND b.location_id=v_location
 WHERE (NOT v_active OR (v.active AND s.active))
  AND (nullif(p->>'kind','') IS NULL OR s.kind=p->>'kind')
  AND (nullif(p->>'category','') IS NULL OR c.name=p->>'category')
  AND (v_q='' OR lower(v.sku)=lower(v_q)
    OR EXISTS(SELECT 1 FROM public.barcodes bc WHERE bc.variant_id=v.id AND lower(bc.code)=lower(v_q))
    OR s.name ILIKE '%'||v_literal||'%' OR v.sku ILIKE '%'||v_literal||'%')
 ORDER BY CASE WHEN v_q<>'' AND (lower(v.sku)=lower(v_q) OR EXISTS(SELECT 1 FROM public.barcodes bc WHERE bc.variant_id=v.id AND lower(bc.code)=lower(v_q))) THEN 0 ELSE 1 END,
  s.name,v.sku,v.id
 LIMIT v_limit OFFSET v_offset;
END $$;

CREATE OR REPLACE FUNCTION public.variant_by_code(p_code TEXT,p_location UUID DEFAULT NULL)
RETURNS TABLE(variant_id UUID, style_id UUID, sku TEXT, name TEXT, size TEXT,
 color TEXT, kind TEXT, unit TEXT, category TEXT, price NUMERIC, taxable BOOLEAN,
 available NUMERIC, on_hand NUMERIC, barcodes TEXT[], total_count BIGINT,
 fit TEXT, min_stock NUMERIC, active BOOLEAN, track_inventory BOOLEAN,
 image TEXT, description TEXT, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ, barcode TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_location UUID := p_location;
BEGIN
 IF NOT public.is_counter_staff() THEN
  RAISE EXCEPTION 'Only counter staff can look up products' USING ERRCODE='42501';
 END IF;
 IF v_location IS NULL THEN
  SELECT l.id INTO v_location FROM public.locations l WHERE l.kind='shop_floor' AND l.active ORDER BY l.created_at,l.id LIMIT 1;
 END IF;
 IF v_location IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.locations l WHERE l.id=v_location AND public.is_branch_member(l.branch_id)) THEN
  RAISE EXCEPTION 'Choose a location in your branch' USING ERRCODE='42501';
 END IF;
 IF nullif(trim(p_code),'') IS NULL THEN RETURN; END IF;
 RETURN QUERY
 WITH matches AS (
  SELECT v.id FROM public.product_variants v WHERE lower(v.sku)=lower(trim(p_code))
  UNION
  SELECT bc.variant_id FROM public.barcodes bc WHERE lower(bc.code)=lower(trim(p_code))
 )
 SELECT v.id,s.id,v.sku,s.name,v.size,v.color,s.kind,s.unit,coalesce(c.name,''),v.price,s.taxable,
  coalesce(b.on_hand-b.reserved,0),coalesce(b.on_hand,0),
  ARRAY(SELECT bc.code FROM public.barcodes bc WHERE bc.variant_id=v.id ORDER BY (bc.roll_id IS NOT NULL),bc.code),
  1::bigint,v.fit,v.min_stock,(v.active AND s.active),s.track_inventory,s.image_url,coalesce(s.description,''),v.created_at,v.updated_at,
  (SELECT bc.code FROM public.barcodes bc WHERE bc.variant_id=v.id AND bc.roll_id IS NULL ORDER BY bc.code LIMIT 1)
 FROM matches m JOIN public.product_variants v ON v.id=m.id
 JOIN public.product_styles s ON s.id=v.style_id
 LEFT JOIN public.categories c ON c.id=s.category_id
 LEFT JOIN public.stock_balances b ON b.variant_id=v.id AND b.location_id=v_location
 WHERE v.active AND s.active
 ORDER BY s.name,v.sku,v.id LIMIT 1;
END $$;

REVOKE ALL ON FUNCTION public.search_variants(JSONB) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.variant_by_code(TEXT,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.search_variants(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.variant_by_code(TEXT,UUID) TO authenticated;
