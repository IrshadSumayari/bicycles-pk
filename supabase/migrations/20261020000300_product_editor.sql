-- =====================================================================
-- Product editor support
--   * product_styles.image_url (moves to Storage with the website catalog)
--   * save_product(): create or update a style + one variant + cost +
--     barcode (+ opening stock) in one transaction
-- =====================================================================

ALTER TABLE public.product_styles ADD COLUMN IF NOT EXISTS image_url TEXT;

UPDATE public.product_styles s
SET image_url = p.image
FROM public.product_variants v
JOIN public.products p ON p.id = v.legacy_product_id
WHERE v.style_id = s.id AND s.image_url IS NULL AND p.image IS NOT NULL;

-- Input:
-- {
--   "variant_id": uuid (omit to create),
--   "kind": "garment" | "pack" | "fabric" | "service",
--   "name", "sku", "size", "color", "fit", "category" (name), "description",
--   "price", "cost", "min_stock", "barcode", "image_url",
--   "taxable", "active", "track_inventory",
--   "opening_stock" (create only), "location_id" (default: shop floor)
-- }
CREATE OR REPLACE FUNCTION public.save_product(p JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_variant_id UUID := NULLIF(p->>'variant_id', '')::uuid;
    v_style_id UUID;
    v_kind TEXT := COALESCE(NULLIF(p->>'kind', ''), 'garment');
    v_unit TEXT;
    v_track BOOLEAN;
    v_category UUID;
    v_barcode TEXT := NULLIF(trim(COALESCE(p->>'barcode', '')), '');
    v_location UUID := NULLIF(p->>'location_id', '')::uuid;
    v_opening NUMERIC := COALESCE(NULLIF(p->>'opening_stock', '')::numeric, 0);
    v_sku TEXT := NULLIF(trim(COALESCE(p->>'sku', '')), '');
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can edit products' USING ERRCODE = '42501';
    END IF;
    IF v_kind NOT IN ('garment', 'pack', 'fabric', 'service') THEN
        RAISE EXCEPTION 'Invalid product kind: %', v_kind;
    END IF;
    IF NULLIF(trim(COALESCE(p->>'name', '')), '') IS NULL OR v_sku IS NULL THEN
        RAISE EXCEPTION 'Name and SKU are required';
    END IF;
    IF COALESCE(NULLIF(p->>'price', '')::numeric, -1) < 0 THEN
        RAISE EXCEPTION 'Enter a valid price';
    END IF;

    v_unit := CASE v_kind WHEN 'pack' THEN 'set' WHEN 'fabric' THEN 'meter' WHEN 'service' THEN 'job' ELSE 'piece' END;
    v_track := v_kind <> 'service' AND COALESCE((p->>'track_inventory')::boolean, true);

    IF NULLIF(trim(COALESCE(p->>'category', '')), '') IS NOT NULL THEN
        INSERT INTO public.categories (name) VALUES (trim(p->>'category')) ON CONFLICT (name) DO NOTHING;
        SELECT id INTO v_category FROM public.categories WHERE name = trim(p->>'category');
    END IF;

    IF v_variant_id IS NULL THEN
        INSERT INTO public.product_styles (code, name, kind, unit, category_id, description, taxable, active,
                                           track_inventory, image_url)
        VALUES (
            CASE WHEN EXISTS (SELECT 1 FROM public.product_styles WHERE code = v_sku)
                 THEN v_sku || '-' || substr(gen_random_uuid()::text, 1, 4) ELSE v_sku END,
            trim(p->>'name'), v_kind, v_unit, v_category, p->>'description',
            COALESCE((p->>'taxable')::boolean, true), COALESCE((p->>'active')::boolean, true),
            v_track, NULLIF(p->>'image_url', '')
        )
        RETURNING id INTO v_style_id;

        INSERT INTO public.product_variants (style_id, sku, size, color, fit, price, min_stock, active)
        VALUES (
            v_style_id, v_sku, NULLIF(trim(p->>'size'), ''), NULLIF(trim(p->>'color'), ''), NULLIF(trim(p->>'fit'), ''),
            (p->>'price')::numeric, COALESCE(NULLIF(p->>'min_stock', '')::numeric, 0),
            COALESCE((p->>'active')::boolean, true)
        )
        RETURNING id INTO v_variant_id;
    ELSE
        SELECT style_id INTO v_style_id FROM public.product_variants WHERE id = v_variant_id;
        IF v_style_id IS NULL THEN
            RAISE EXCEPTION 'Product not found';
        END IF;

        UPDATE public.product_styles SET
            name = trim(p->>'name'), kind = v_kind, unit = v_unit, category_id = v_category,
            description = p->>'description', taxable = COALESCE((p->>'taxable')::boolean, true),
            active = COALESCE((p->>'active')::boolean, true), track_inventory = v_track,
            image_url = NULLIF(p->>'image_url', '')
        WHERE id = v_style_id;

        UPDATE public.product_variants SET
            sku = v_sku, size = NULLIF(trim(p->>'size'), ''), color = NULLIF(trim(p->>'color'), ''),
            fit = NULLIF(trim(p->>'fit'), ''), price = (p->>'price')::numeric,
            min_stock = COALESCE(NULLIF(p->>'min_stock', '')::numeric, 0),
            active = COALESCE((p->>'active')::boolean, true)
        WHERE id = v_variant_id;
    END IF;

    IF NULLIF(p->>'cost', '') IS NOT NULL THEN
        INSERT INTO public.variant_costs (variant_id, unit_cost) VALUES (v_variant_id, (p->>'cost')::numeric)
        ON CONFLICT (variant_id) DO UPDATE SET unit_cost = EXCLUDED.unit_cost;
    END IF;

    -- One barcode per item from this editor (more can be added later)
    IF v_barcode IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM public.barcodes WHERE code = v_barcode AND variant_id <> v_variant_id) THEN
            RAISE EXCEPTION 'Barcode % is already used by another item', v_barcode;
        END IF;
        DELETE FROM public.barcodes WHERE variant_id = v_variant_id AND code <> v_barcode;
        INSERT INTO public.barcodes (code, variant_id) VALUES (v_barcode, v_variant_id) ON CONFLICT (code) DO NOTHING;
    ELSE
        DELETE FROM public.barcodes WHERE variant_id = v_variant_id;
    END IF;

    IF NULLIF(p->>'variant_id', '') IS NULL AND v_track AND v_opening > 0 THEN
        IF v_location IS NULL THEN
            SELECT id INTO v_location FROM public.locations
            WHERE branch_id = public.default_branch_id() AND kind = 'shop_floor' AND active
            ORDER BY created_at LIMIT 1;
        END IF;
        PERFORM public.adjust_stock(v_variant_id, v_location, v_opening, 'Opening stock', 'opening', NULL);
    END IF;

    RETURN v_variant_id;
END;
$$;

REVOKE ALL ON FUNCTION public.save_product(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_product(JSONB) TO authenticated;

-- The original seed stored 8.75% as 0.0875, but the app reads tax_rate as a
-- percentage (it showed 0.088%). Reset the untouched seed value; the store
-- sets its real rate in Settings.
UPDATE public.app_settings SET tax_rate = 0 WHERE tax_rate = 0.088;
