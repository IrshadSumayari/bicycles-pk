-- Bike delivery: bulky items pay an extra courier charge per unit, and courier
-- orders can add assembly (delivered ready to ride) per bulky unit. Both are
-- folded into delivery_fee, so order totals keep subtotal + tax + delivery.

ALTER TABLE public.product_styles ADD COLUMN bulky BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.app_settings
 ADD COLUMN bulky_delivery_fee NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK(bulky_delivery_fee>=0),
 ADD COLUMN assembly_fee NUMERIC(14,2) CHECK(assembly_fee>=0);
COMMENT ON COLUMN public.app_settings.assembly_fee IS 'Per bulky unit on courier orders; NULL means assembly is not offered.';
ALTER TABLE public.online_orders ADD COLUMN assembly BOOLEAN NOT NULL DEFAULT false;

-- save_style: an omitted "bulky" keeps the stored value.
ALTER FUNCTION public.save_style(JSONB) RENAME TO save_style_before_bulky;
REVOKE ALL ON FUNCTION public.save_style_before_bulky(JSONB) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.save_style(p JSONB) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE style UUID;
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF p ? 'bulky' AND jsonb_typeof(p->'bulky') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Choose whether the item is bulky'; END IF;
 style:=public.save_style_before_bulky(p - 'bulky');
 IF p ? 'bulky' THEN UPDATE public.product_styles SET bulky=(p->>'bulky')::boolean WHERE id=style; END IF;
 RETURN style;
END $$;
REVOKE ALL ON FUNCTION public.save_style(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_style(JSONB) TO authenticated;

-- update_settings: admins set the two new amounts; everything else is unchanged.
ALTER FUNCTION public.update_settings(JSONB) RENAME TO update_settings_before_bikes;
REVOKE ALL ON FUNCTION public.update_settings_before_bikes(JSONB) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.update_settings(p JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r JSONB; k TEXT;
BEGIN
 IF jsonb_typeof(p) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Send a settings patch'; END IF;
 FOREACH k IN ARRAY ARRAY['bulky_delivery_fee','assembly_fee'] LOOP
  CONTINUE WHEN NOT p ? k;
  IF NOT coalesce(public.has_app_role(ARRAY['admin']),false) THEN RAISE EXCEPTION 'Only administrators can change %',k USING ERRCODE='42501'; END IF;
  CONTINUE WHEN k='assembly_fee' AND p->k='null'::jsonb;
  IF jsonb_typeof(p->k) IS DISTINCT FROM 'number' OR (p->>k)::numeric<0 OR (p->>k)::numeric<>round((p->>k)::numeric,2) THEN
   RAISE EXCEPTION 'Enter a non-negative amount with up to two decimals for %',k; END IF;
 END LOOP;
 r:=public.update_settings_before_bikes(p - 'bulky_delivery_fee' - 'assembly_fee');
 IF p ? 'bulky_delivery_fee' OR p ? 'assembly_fee' THEN
  UPDATE public.app_settings SET
   bulky_delivery_fee=CASE WHEN p ? 'bulky_delivery_fee' THEN (p->>'bulky_delivery_fee')::numeric ELSE bulky_delivery_fee END,
   assembly_fee=CASE WHEN p ? 'assembly_fee' THEN (p->>'assembly_fee')::numeric ELSE assembly_fee END
  WHERE id=(SELECT id FROM public.app_settings ORDER BY created_at,id LIMIT 1);
 END IF;
 RETURN r||(SELECT jsonb_build_object('bulky_delivery_fee',bulky_delivery_fee,'assembly_fee',assembly_fee)
  FROM public.app_settings ORDER BY created_at,id LIMIT 1);
END $$;
REVOKE ALL ON FUNCTION public.update_settings(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_settings(JSONB) TO authenticated;

-- quote_online_order: adds the bulky charge and optional assembly on delivery.
-- Pickup orders never pay either (bikes are handed over assembled).
ALTER FUNCTION public.quote_online_order(JSONB) RENAME TO quote_online_order_before_bikes;
REVOKE ALL ON FUNCTION public.quote_online_order_before_bikes(JSONB) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.quote_online_order(p JSONB) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE q JSONB; s public.app_settings; units NUMERIC; bulky NUMERIC(14,2):=0; assembly NUMERIC(14,2):=0;
 total NUMERIC(14,2); delivery BOOLEAN; want BOOLEAN; offered BOOLEAN;
BEGIN
 IF p ? 'assembly' AND jsonb_typeof(p->'assembly') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Choose whether to add assembly'; END IF;
 q:=public.quote_online_order_before_bikes(p - 'assembly');
 SELECT * INTO s FROM public.app_settings ORDER BY created_at,id LIMIT 1;
 SELECT coalesce(sum((l->>'quantity')::numeric),0) INTO units FROM jsonb_array_elements(q->'lines') l
  JOIN public.product_variants pv ON pv.id=(l->>'variant_id')::uuid
  JOIN public.product_styles ps ON ps.id=pv.style_id WHERE ps.bulky;
 delivery:=p->>'fulfilment'='delivery';
 offered:=delivery AND units>0 AND s.assembly_fee IS NOT NULL;
 want:=delivery AND coalesce((p->>'assembly')::boolean,false);
 IF want AND NOT offered THEN RAISE EXCEPTION 'Assembly is not available for this order'; END IF;
 IF delivery THEN bulky:=round(units*s.bulky_delivery_fee,2); END IF;
 IF want THEN assembly:=round(units*s.assembly_fee,2); END IF;
 total:=(q->>'total')::numeric+bulky+assembly;
 RETURN q||jsonb_build_object(
  'delivery_fee',(q->>'delivery_fee')::numeric+bulky+assembly,'total',total,
  'bulky_units',units,'bulky_fee',bulky,'assembly',want,'assembly_fee',assembly,
  'assembly_available',offered,'assembly_unit_fee',CASE WHEN offered THEN s.assembly_fee END,
  'cod_allowed',s.cod_enabled AND (s.cod_max_total IS NULL OR total<=s.cod_max_total),
  'payment_methods',to_jsonb(array_remove(ARRAY[CASE WHEN s.online_card_enabled THEN 'card' END,
   CASE WHEN s.online_card_enabled THEN 'easypaisa' END,
   CASE WHEN s.cod_enabled AND (s.cod_max_total IS NULL OR total<=s.cod_max_total) THEN 'cod' END],NULL)));
END $$;
REVOKE ALL ON FUNCTION public.quote_online_order(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quote_online_order(JSONB) TO anon,authenticated;

-- create_online_order: the stored order calls the quote above (by name), so
-- its delivery_fee and total already include both; record the assembly choice.
ALTER FUNCTION public.create_online_order(JSONB) RENAME TO create_online_order_before_bikes;
REVOKE ALL ON FUNCTION public.create_online_order_before_bikes(JSONB) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.create_online_order(p JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r JSONB; want BOOLEAN;
BEGIN
 r:=public.create_online_order_before_bikes(p);
 want:=p->>'fulfilment'='delivery' AND jsonb_typeof(p->'assembly')='boolean' AND (p->>'assembly')::boolean;
 IF want THEN UPDATE public.online_orders SET assembly=true WHERE id=(r->>'id')::uuid AND NOT assembly; END IF;
 RETURN r||jsonb_build_object('assembly',want);
END $$;
REVOKE ALL ON FUNCTION public.create_online_order(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_online_order(JSONB) TO authenticated;

-- Show "bulky" on the public product and "assembly" on the customer's order.
DO $$ DECLARE def TEXT:=replace(pg_get_functiondef('public.catalog_product(text)'::regprocedure),chr(13),'');
BEGIN
 IF position('''specs'',st.specs,' IN def)=0 THEN RAISE EXCEPTION 'catalog_product changed'; END IF;
 EXECUTE replace(def,'''specs'',st.specs,','''specs'',st.specs,''bulky'',st.bulky,');
END $$;
DO $$ DECLARE def TEXT:=replace(pg_get_functiondef('public.online_order_public(uuid)'::regprocedure),chr(13),'');
BEGIN
 IF position('''delivery_fee'',o.delivery_fee,' IN def)=0 THEN RAISE EXCEPTION 'online_order_public changed'; END IF;
 EXECUTE replace(def,'''delivery_fee'',o.delivery_fee,','''delivery_fee'',o.delivery_fee,''assembly'',o.assembly,');
END $$;
