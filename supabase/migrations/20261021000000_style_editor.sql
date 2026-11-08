-- =====================================================================
-- Style editor: one style with many variants (size x color x fit)
--
-- save_style() creates or updates a style and all listed variants (price,
-- cost, barcode, low-stock level, opening stock for new rows) in one
-- transaction. Variants missing from the list are left unchanged; hide one
-- by sending it with "active": false.
-- =====================================================================

-- Input:
-- {
--   "style_id": uuid (omit to create),
--   "kind", "code", "name", "category", "brand", "material", "season",
--   "design_code", "description", "size_scheme" (code), "image_url",
--   "taxable", "active", "track_inventory",
--   "location_id" (opening stock location, default shop floor),
--   "variants": [{ "variant_id" (omit for new), "sku", "size", "color", "fit",
--                  "price", "cost", "barcode", "min_stock", "active",
--                  "opening_stock" (new rows only) }]
-- }
CREATE OR REPLACE FUNCTION public.save_style(p JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_style_id UUID := NULLIF(p->>'style_id', '')::uuid;
    v_kind TEXT := COALESCE(NULLIF(p->>'kind', ''), 'garment');
    v_unit TEXT;
    v_track BOOLEAN;
    v_category UUID;
    v_scheme UUID;
    v_code TEXT := upper(NULLIF(trim(COALESCE(p->>'code', '')), ''));
    v_location UUID := NULLIF(p->>'location_id', '')::uuid;
    v_row JSONB;
    v_variant_id UUID;
    v_is_new BOOLEAN;
    v_barcode TEXT;
    v_opening NUMERIC;
    v_seen TEXT[] := ARRAY[]::text[];
    v_key TEXT;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can edit products' USING ERRCODE = '42501';
    END IF;
    IF v_kind NOT IN ('garment', 'pack', 'fabric', 'service') THEN
        RAISE EXCEPTION 'Invalid product kind: %', v_kind;
    END IF;
    IF NULLIF(trim(COALESCE(p->>'name', '')), '') IS NULL OR v_code IS NULL THEN
        RAISE EXCEPTION 'Style name and code are required';
    END IF;
    IF jsonb_typeof(p->'variants') <> 'array' OR jsonb_array_length(p->'variants') = 0 THEN
        RAISE EXCEPTION 'Add at least one size or color';
    END IF;

    v_unit := CASE v_kind WHEN 'pack' THEN 'set' WHEN 'fabric' THEN 'meter' WHEN 'service' THEN 'job' ELSE 'piece' END;
    v_track := v_kind <> 'service' AND COALESCE((p->>'track_inventory')::boolean, true);

    IF NULLIF(trim(COALESCE(p->>'category', '')), '') IS NOT NULL THEN
        INSERT INTO public.categories (name) VALUES (trim(p->>'category')) ON CONFLICT (name) DO NOTHING;
        SELECT id INTO v_category FROM public.categories WHERE name = trim(p->>'category');
    END IF;
    IF NULLIF(p->>'size_scheme', '') IS NOT NULL THEN
        SELECT id INTO v_scheme FROM public.size_schemes WHERE code = p->>'size_scheme';
    END IF;

    IF v_style_id IS NULL THEN
        IF EXISTS (SELECT 1 FROM public.product_styles WHERE code = v_code) THEN
            RAISE EXCEPTION 'Style code % is already used', v_code;
        END IF;
        INSERT INTO public.product_styles (code, name, kind, unit, category_id, brand, material, season, design_code,
                                           description, size_scheme_id, taxable, active, track_inventory, image_url)
        VALUES (v_code, trim(p->>'name'), v_kind, v_unit, v_category, NULLIF(trim(p->>'brand'), ''),
                NULLIF(trim(p->>'material'), ''), NULLIF(trim(p->>'season'), ''), NULLIF(trim(p->>'design_code'), ''),
                NULLIF(p->>'description', ''), v_scheme, COALESCE((p->>'taxable')::boolean, true),
                COALESCE((p->>'active')::boolean, true), v_track, NULLIF(p->>'image_url', ''))
        RETURNING id INTO v_style_id;
    ELSE
        UPDATE public.product_styles SET
            code = v_code, name = trim(p->>'name'), kind = v_kind, unit = v_unit, category_id = v_category,
            brand = NULLIF(trim(p->>'brand'), ''), material = NULLIF(trim(p->>'material'), ''),
            season = NULLIF(trim(p->>'season'), ''), design_code = NULLIF(trim(p->>'design_code'), ''),
            description = NULLIF(p->>'description', ''), size_scheme_id = v_scheme,
            taxable = COALESCE((p->>'taxable')::boolean, true), active = COALESCE((p->>'active')::boolean, true),
            track_inventory = v_track, image_url = NULLIF(p->>'image_url', '')
        WHERE id = v_style_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Style not found';
        END IF;
    END IF;

    IF v_location IS NULL THEN
        SELECT id INTO v_location FROM public.locations
        WHERE branch_id = public.default_branch_id() AND kind = 'shop_floor' AND active
        ORDER BY created_at LIMIT 1;
    END IF;

    FOR v_row IN SELECT * FROM jsonb_array_elements(p->'variants')
    LOOP
        v_variant_id := NULLIF(v_row->>'variant_id', '')::uuid;
        v_is_new := v_variant_id IS NULL;
        v_barcode := NULLIF(trim(COALESCE(v_row->>'barcode', '')), '');

        IF NULLIF(trim(COALESCE(v_row->>'sku', '')), '') IS NULL THEN
            RAISE EXCEPTION 'Every row needs a SKU';
        END IF;
        IF COALESCE(NULLIF(v_row->>'price', '')::numeric, -1) < 0 THEN
            RAISE EXCEPTION 'Enter a valid price for %', v_row->>'sku';
        END IF;

        v_key := lower(COALESCE(trim(v_row->>'size'), '') || '|' || COALESCE(trim(v_row->>'color'), '') || '|' ||
                       COALESCE(trim(v_row->>'fit'), ''));
        IF v_key = ANY(v_seen) THEN
            RAISE EXCEPTION 'The same size and color is listed twice (%)', v_row->>'sku';
        END IF;
        v_seen := v_seen || v_key;

        IF v_is_new THEN
            INSERT INTO public.product_variants (style_id, sku, size, color, fit, price, min_stock, active)
            VALUES (v_style_id, upper(trim(v_row->>'sku')), NULLIF(trim(v_row->>'size'), ''),
                    NULLIF(trim(v_row->>'color'), ''), NULLIF(trim(v_row->>'fit'), ''),
                    (v_row->>'price')::numeric, COALESCE(NULLIF(v_row->>'min_stock', '')::numeric, 0),
                    COALESCE((v_row->>'active')::boolean, true))
            RETURNING id INTO v_variant_id;
        ELSE
            UPDATE public.product_variants SET
                sku = upper(trim(v_row->>'sku')), size = NULLIF(trim(v_row->>'size'), ''),
                color = NULLIF(trim(v_row->>'color'), ''), fit = NULLIF(trim(v_row->>'fit'), ''),
                price = (v_row->>'price')::numeric, min_stock = COALESCE(NULLIF(v_row->>'min_stock', '')::numeric, 0),
                active = COALESCE((v_row->>'active')::boolean, true)
            WHERE id = v_variant_id AND style_id = v_style_id;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Variant % does not belong to this style', v_variant_id;
            END IF;
        END IF;

        IF NULLIF(v_row->>'cost', '') IS NOT NULL THEN
            INSERT INTO public.variant_costs (variant_id, unit_cost) VALUES (v_variant_id, (v_row->>'cost')::numeric)
            ON CONFLICT (variant_id) DO UPDATE SET unit_cost = EXCLUDED.unit_cost;
        END IF;

        IF v_barcode IS NOT NULL THEN
            IF EXISTS (SELECT 1 FROM public.barcodes WHERE code = v_barcode AND variant_id <> v_variant_id) THEN
                RAISE EXCEPTION 'Barcode % is already used by another item', v_barcode;
            END IF;
            DELETE FROM public.barcodes WHERE variant_id = v_variant_id AND code <> v_barcode;
            INSERT INTO public.barcodes (code, variant_id) VALUES (v_barcode, v_variant_id) ON CONFLICT (code) DO NOTHING;
        ELSIF v_row ? 'barcode' THEN
            DELETE FROM public.barcodes WHERE variant_id = v_variant_id;
        END IF;

        v_opening := COALESCE(NULLIF(v_row->>'opening_stock', '')::numeric, 0);
        IF v_is_new AND v_track AND v_opening > 0 THEN
            PERFORM public.adjust_stock(v_variant_id, v_location, v_opening, 'Opening stock', 'opening', NULL);
        END IF;
    END LOOP;

    RETURN v_style_id;
END;
$$;

REVOKE ALL ON FUNCTION public.save_style(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_style(JSONB) TO authenticated;

-- The old single-item editor is replaced by save_style()
DROP FUNCTION IF EXISTS public.save_product(JSONB);
