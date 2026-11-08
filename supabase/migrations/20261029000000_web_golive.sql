-- Online settings, approved compare-at import support and least-privilege public surface.
CREATE OR REPLACE FUNCTION public.update_settings(p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_old public.app_settings; v_new public.app_settings; v_key TEXT; v_max INT;
 v_request UUID; v_existing JSONB;
 v_keys TEXT[]:=ARRAY['store_name','store_address','store_phone','store_email','store_logo','tax_rate','currency','interface_mode','auto_backup','receipt_printer','theme','invoice_prefix','invoice_counter','max_cashier_discount_percent','return_window_days','cash_variance_alert','min_tailoring_deposit_percent','receipt_header','receipt_footer','ntn','strn','online_hold_minutes','delivery_fee','free_delivery_over','cod_enabled','cod_max_total','online_max_pending_orders','online_max_open_cod_orders'];
BEGIN
 IF NOT public.has_app_role(ARRAY['admin','manager']) THEN RAISE EXCEPTION 'Only managers can change settings' USING ERRCODE='42501'; END IF;
 v_request:=nullif(p->>'request_id','')::uuid;
 v_existing:=public.idempotency_begin(v_request,'update_settings');
 IF v_existing IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=v_request AND user_id=auth.uid()) THEN RAISE EXCEPTION 'Request id belongs to another settings save' USING ERRCODE='42501'; END IF;
   RETURN v_existing;
 END IF;
 IF jsonb_typeof(p) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Send a settings patch'; END IF;
 FOR v_key IN SELECT jsonb_object_keys(p) LOOP
   IF v_key='request_id' THEN CONTINUE; END IF;
   IF NOT (v_key=ANY(v_keys)) THEN RAISE EXCEPTION 'Unknown setting: %',v_key; END IF;
   IF public.current_app_role()='manager' AND v_key NOT IN ('receipt_header','receipt_footer') THEN RAISE EXCEPTION 'Only administrators can change %',v_key USING ERRCODE='42501'; END IF;
   IF v_key IN ('free_delivery_over','cod_max_total') AND p->v_key='null'::jsonb THEN CONTINUE; END IF;
   IF v_key IN ('tax_rate','max_cashier_discount_percent','return_window_days','cash_variance_alert','min_tailoring_deposit_percent','invoice_counter','online_hold_minutes','delivery_fee','free_delivery_over','cod_max_total','online_max_pending_orders','online_max_open_cod_orders') THEN
     IF jsonb_typeof(p->v_key) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Enter a number for %',v_key; END IF;
   ELSIF v_key IN ('auto_backup','receipt_printer','cod_enabled') THEN
     IF jsonb_typeof(p->v_key) IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Choose on or off for %',v_key; END IF;
   ELSE
     IF jsonb_typeof(p->v_key) NOT IN ('string','null') THEN RAISE EXCEPTION 'Enter text for %',v_key; END IF;
     v_max:=CASE v_key WHEN 'store_name' THEN 200 WHEN 'store_address' THEN 1000 WHEN 'store_phone' THEN 50
       WHEN 'store_email' THEN 254 WHEN 'store_logo' THEN 3000000 WHEN 'receipt_header' THEN 500 WHEN 'receipt_footer' THEN 500
       WHEN 'invoice_prefix' THEN 20 ELSE 100 END;
     IF length(p->>v_key)>v_max THEN RAISE EXCEPTION '% must be at most % characters',v_key,v_max; END IF;
   END IF;
 END LOOP;
 IF p ? 'tax_rate' AND (p->>'tax_rate')::numeric NOT BETWEEN 0 AND 100 THEN RAISE EXCEPTION 'Tax must be between 0 and 100 percent'; END IF;
 IF p ? 'max_cashier_discount_percent' AND (p->>'max_cashier_discount_percent')::numeric NOT BETWEEN 0 AND 100 THEN RAISE EXCEPTION 'Discount limit must be between 0 and 100 percent'; END IF;
 IF p ? 'min_tailoring_deposit_percent' AND (p->>'min_tailoring_deposit_percent')::numeric NOT BETWEEN 0 AND 100 THEN RAISE EXCEPTION 'Minimum deposit must be between 0 and 100 percent'; END IF;
 IF p ? 'return_window_days' AND ((p->>'return_window_days')::numeric NOT BETWEEN 0 AND 365 OR (p->>'return_window_days')::numeric<>trunc((p->>'return_window_days')::numeric)) THEN RAISE EXCEPTION 'Return window must be a whole number from 0 to 365 days'; END IF;
 IF p ? 'cash_variance_alert' AND (p->>'cash_variance_alert')::numeric<0 THEN RAISE EXCEPTION 'Cash difference alert must be zero or more'; END IF;
 IF p ? 'invoice_counter' AND ((p->>'invoice_counter')::numeric<0 OR (p->>'invoice_counter')::numeric<>trunc((p->>'invoice_counter')::numeric)) THEN RAISE EXCEPTION 'Invoice preview counter must be a whole number of zero or more'; END IF;
 IF p ? 'store_name' AND coalesce(trim(p->>'store_name'),'')='' THEN RAISE EXCEPTION 'Enter the store name'; END IF;
 IF p ? 'currency' AND coalesce(p->>'currency','') !~ '^[A-Z]{3}$' THEN RAISE EXCEPTION 'Enter a three-letter currency code'; END IF;
 IF p ? 'interface_mode' AND coalesce(p->>'interface_mode','') NOT IN ('touch','traditional') THEN RAISE EXCEPTION 'Choose touch or traditional layout'; END IF;
 IF p ? 'theme' AND coalesce(p->>'theme','') NOT IN ('light','dark','auto') THEN RAISE EXCEPTION 'Choose a valid theme'; END IF;
 FOR v_key IN SELECT unnest(ARRAY['online_max_pending_orders','online_max_open_cod_orders']) LOOP
  IF p ? v_key AND ((p->>v_key)::numeric NOT BETWEEN 1 AND 50 OR (p->>v_key)::numeric<>trunc((p->>v_key)::numeric)) THEN
   RAISE EXCEPTION 'Online order limits must be whole numbers from 1 to 50';
  END IF;
 END LOOP;
 IF p ? 'online_hold_minutes' AND ((p->>'online_hold_minutes')::numeric NOT BETWEEN 1 AND 1440 OR (p->>'online_hold_minutes')::numeric<>trunc((p->>'online_hold_minutes')::numeric)) THEN RAISE EXCEPTION 'Online hold must be a whole number from 1 to 1440 minutes'; END IF;
 FOR v_key IN SELECT unnest(ARRAY['delivery_fee','free_delivery_over','cod_max_total']) LOOP
  IF p ? v_key AND p->v_key<>'null'::jsonb AND ((p->>v_key)::numeric<0 OR (p->>v_key)::numeric<>round((p->>v_key)::numeric,2)) THEN RAISE EXCEPTION 'Enter a non-negative amount with up to two decimals for %',v_key; END IF;
 END LOOP;
 SELECT * INTO v_old FROM public.app_settings ORDER BY created_at,id LIMIT 1 FOR UPDATE;
 IF v_old.id IS NULL THEN RAISE EXCEPTION 'Store settings not found'; END IF;
 v_new:=jsonb_populate_record(v_old,p-'request_id');
 UPDATE public.app_settings SET store_name=v_new.store_name,store_address=v_new.store_address,store_phone=v_new.store_phone,
   store_email=v_new.store_email,store_logo=v_new.store_logo,tax_rate=v_new.tax_rate,currency=v_new.currency,interface_mode=v_new.interface_mode,
   auto_backup=v_new.auto_backup,receipt_printer=v_new.receipt_printer,theme=v_new.theme,invoice_prefix=v_new.invoice_prefix,invoice_counter=v_new.invoice_counter,
   max_cashier_discount_percent=v_new.max_cashier_discount_percent,return_window_days=v_new.return_window_days,cash_variance_alert=v_new.cash_variance_alert,
   min_tailoring_deposit_percent=v_new.min_tailoring_deposit_percent,receipt_header=v_new.receipt_header,receipt_footer=v_new.receipt_footer,ntn=v_new.ntn,strn=v_new.strn,online_hold_minutes=v_new.online_hold_minutes,delivery_fee=v_new.delivery_fee,free_delivery_over=v_new.free_delivery_over,cod_enabled=v_new.cod_enabled,cod_max_total=v_new.cod_max_total,online_max_pending_orders=v_new.online_max_pending_orders,online_max_open_cod_orders=v_new.online_max_open_cod_orders
 WHERE id=v_old.id RETURNING * INTO v_new;
 INSERT INTO public.settings_history(old,new) VALUES(to_jsonb(v_old),to_jsonb(v_new));
 RETURN public.idempotency_finish(v_request,to_jsonb(v_new));
END; $$;

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

        IF v_row ? 'compare_at_price' AND v_row->'compare_at_price'<>'null'::jsonb
           AND ((v_row->>'compare_at_price')::numeric NOT BETWEEN 0 AND 999999999999.99 OR (v_row->>'compare_at_price')::numeric<>round((v_row->>'compare_at_price')::numeric,2)) THEN
            RAISE EXCEPTION 'Compare-at price must be a non-negative amount with up to two decimals';
        END IF;
        v_key := lower(COALESCE(trim(v_row->>'size'), '') || '|' || COALESCE(trim(v_row->>'color'), '') || '|' ||
                       COALESCE(trim(v_row->>'fit'), ''));
        IF v_key = ANY(v_seen) THEN
            RAISE EXCEPTION 'The same size and color is listed twice (%)', v_row->>'sku';
        END IF;
        v_seen := v_seen || v_key;

        IF v_is_new THEN
            INSERT INTO public.product_variants (style_id, sku, size, color, fit, price, compare_at_price, min_stock, active)
            VALUES (v_style_id, upper(trim(v_row->>'sku')), NULLIF(trim(v_row->>'size'), ''),
                    NULLIF(trim(v_row->>'color'), ''), NULLIF(trim(v_row->>'fit'), ''),
                    (v_row->>'price')::numeric, (v_row->>'compare_at_price')::numeric, COALESCE(NULLIF(v_row->>'min_stock', '')::numeric, 0),
                    COALESCE((v_row->>'active')::boolean, true))
            RETURNING id INTO v_variant_id;
        ELSE
            UPDATE public.product_variants SET
                sku = upper(trim(v_row->>'sku')), size = NULLIF(trim(v_row->>'size'), ''),
                color = NULLIF(trim(v_row->>'color'), ''), fit = NULLIF(trim(v_row->>'fit'), ''),
                price = (v_row->>'price')::numeric, compare_at_price = CASE WHEN v_row ? 'compare_at_price' THEN (v_row->>'compare_at_price')::numeric ELSE compare_at_price END, min_stock = COALESCE(NULLIF(v_row->>'min_stock', '')::numeric, 0),
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

-- A minimal public policy response avoids exposing staff-only settings tables.
CREATE OR REPLACE FUNCTION public.catalog_policy() RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT jsonb_build_object('return_window_days',return_window_days)
 FROM public.app_settings ORDER BY created_at,id LIMIT 1
$$;

-- Remove default PUBLIC execution and unintended anonymous trigger/helper grants.
DO $$ DECLARE f RECORD; BEGIN
 FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind='f' LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon',f.signature);
 END LOOP;
 FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN ('auto_generate_invoice_number','handle_auth_user_marked_staff','handle_new_auth_user','keep_roll_barcodes','normalize_customer_phone','normalize_phone','prevent_ledger_changes','protect_customer_account_columns','protect_user_privileged_columns','sanitize_card_details','update_customer_stats','update_updated_at_column') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM authenticated',f.signature);
 END LOOP;
END $$;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.needs_bootstrap(),public.catalog_list(JSONB),public.catalog_product(TEXT),public.catalog_collections(),public.catalog_facets(TEXT),public.catalog_garment_types(),public.quote_online_order(JSONB),public.catalog_policy() TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.update_settings(JSONB),public.save_style(JSONB) TO authenticated;
-- Customer phone triggers run with the caller's rights, so staff and customers must be able to normalise phones.
GRANT EXECUTE ON FUNCTION public.normalize_phone(TEXT) TO authenticated;

-- Explicit customer denial for staff entry points; retain all existing staff and branch checks.
CREATE OR REPLACE FUNCTION public.cash_session_summary(p_session_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;
RETURN (SELECT jsonb_build_object(
        'session', to_jsonb(s),
        'cash_sales', COALESCE((SELECT sum(amount) FROM public.cash_movements WHERE session_id = s.id AND movement_type = 'sale'), 0),
        'cash_refunds', COALESCE((SELECT -sum(amount) FROM public.cash_movements WHERE session_id = s.id AND movement_type = 'refund'), 0),
        'cash_in', COALESCE((SELECT sum(amount) FROM public.cash_movements WHERE session_id = s.id AND movement_type = 'cash_in'), 0),
        'cash_out', COALESCE((SELECT -sum(amount) FROM public.cash_movements WHERE session_id = s.id AND movement_type = 'cash_out'), 0),
        'expected_cash', s.opening_float + COALESCE((SELECT sum(amount) FROM public.cash_movements WHERE session_id = s.id), 0),
        'other_payments', COALESCE((
            SELECT jsonb_object_agg(method, total) FROM (
                SELECT p.method, sum(CASE WHEN p.direction = 'out' THEN -p.amount ELSE p.amount END) AS total
                FROM public.payments p
                WHERE p.method NOT IN ('cash', 'opening') AND p.created_by = s.user_id
                  AND NOT EXISTS (SELECT 1 FROM public.online_orders oo
                                  WHERE oo.sale_id = p.sale_id AND oo.payment_method IN ('card', 'easypaisa'))
                  AND p.created_at >= s.opened_at AND p.created_at <= COALESCE(s.closed_at, now())
                GROUP BY p.method) t), '{}'::jsonb)
    )
    FROM public.cash_sessions s
    WHERE s.id = p_session_id
      AND (s.user_id = auth.uid() OR (public.has_app_role(ARRAY['admin', 'manager']) AND public.is_branch_member(s.branch_id))));
END;$function$
;
CREATE OR REPLACE FUNCTION public.close_cash_session(p_counted_cash numeric, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_session UUID;
BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;

    -- Preserve the original validation order, signature, errors and rounding.
    IF p_counted_cash IS NULL OR p_counted_cash < 0 THEN
        RAISE EXCEPTION 'Enter the counted cash (0 or more)';
    END IF;
    SELECT id INTO v_session FROM public.cash_sessions WHERE user_id = auth.uid() AND status = 'open' FOR UPDATE;
    IF v_session IS NULL THEN RAISE EXCEPTION 'No open cash shift'; END IF;
    RETURN public.close_cash_session_internal(v_session, p_counted_cash, p_notes, auth.uid());
END;
$function$
;
CREATE OR REPLACE FUNCTION public.confirm_tailoring_order(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_order public.tailoring_orders;
BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;

    SELECT * INTO v_order FROM public.tailoring_orders WHERE id = p_order_id FOR UPDATE;
    IF v_order.id IS NULL OR NOT public.is_counter_staff() OR NOT public.is_branch_member(v_order.branch_id) THEN
        RAISE EXCEPTION 'Order not found';
    END IF;
    IF v_order.status <> 'draft' THEN
        RETURN public.tailoring_order_summary(p_order_id);
    END IF;
    PERFORM public.confirm_tailoring_order_internal(p_order_id);
    RETURN public.tailoring_order_summary(p_order_id);
END;
$function$
;
CREATE OR REPLACE FUNCTION public.current_cash_session()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;
RETURN (SELECT public.cash_session_summary(id) FROM public.cash_sessions WHERE user_id = auth.uid() AND status = 'open');
END;$function$
;
CREATE OR REPLACE FUNCTION public.find_sale_for_return(p_invoice text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_sale public.sales;
    v_days INTEGER;
BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;

    IF public.current_app_role() NOT IN ('admin', 'manager', 'cashier') THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_sale FROM public.sales
    WHERE upper(invoice_number) = upper(trim(p_invoice)) AND public.is_branch_member(branch_id);
    IF v_sale.id IS NULL THEN
        RAISE EXCEPTION 'No sale with invoice number %', trim(p_invoice);
    END IF;
    IF v_sale.status = 'draft' THEN
        RAISE EXCEPTION '% is a draft, not a completed sale', v_sale.invoice_number;
    END IF;

    SELECT COALESCE(return_window_days, 7) INTO v_days FROM public.app_settings ORDER BY created_at LIMIT 1;

    RETURN jsonb_build_object(
        'sale', jsonb_build_object(
            'id', v_sale.id, 'invoice_number', v_sale.invoice_number, 'created_at', v_sale.created_at,
            'customer_id', v_sale.customer_id, 'customer_name', v_sale.customer_name, 'cashier', v_sale.cashier,
            'total', v_sale.total, 'status', v_sale.status),
        'return_window_days', v_days,
        'within_window', v_sale.created_at >= now() - make_interval(days => v_days),
        'lines', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'sale_line_id', sl.id, 'variant_id', sl.variant_id, 'description', sl.description, 'sku', sl.sku,
                'unit', sl.unit, 'quantity', sl.quantity, 'total', sl.total, 'is_gift', sl.is_gift,
                'returned', COALESCE((SELECT sum(rl.quantity) FROM public.return_lines rl WHERE rl.sale_line_id = sl.id), 0)
            ) ORDER BY sl.line_no), '[]'::jsonb)
            FROM public.sale_lines sl WHERE sl.sale_id = v_sale.id),
        'returns', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object('return_no', r.return_no, 'refund_total', r.refund_total,
                                                         'created_at', r.created_at) ORDER BY r.created_at), '[]'::jsonb)
            FROM public.returns r WHERE r.sale_id = v_sale.id)
    );
END;
$function$
;
CREATE OR REPLACE FUNCTION public.list_tailors()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;
RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'name', name) ORDER BY name), '[]'::jsonb)
    FROM public.users WHERE role = 'tailor' AND active AND public.is_staff());
END;$function$
;
CREATE OR REPLACE FUNCTION public.open_cash_session(p_opening_float numeric, p_location_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_location UUID := p_location_id;
    v_branch UUID;
    v_session public.cash_sessions;
BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;

    IF public.current_app_role() NOT IN ('admin', 'manager', 'cashier') THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
    IF p_opening_float IS NULL OR p_opening_float < 0 THEN
        RAISE EXCEPTION 'Enter the opening float (0 or more)';
    END IF;

    -- Opening twice returns the shift that is already open
    SELECT * INTO v_session FROM public.cash_sessions WHERE user_id = auth.uid() AND status = 'open';
    IF v_session.id IS NOT NULL THEN
        RETURN public.cash_session_summary(v_session.id);
    END IF;

    IF v_location IS NULL THEN
        SELECT id INTO v_location FROM public.locations
        WHERE branch_id = public.default_branch_id() AND kind = 'shop_floor' AND active
        ORDER BY created_at LIMIT 1;
    END IF;
    SELECT branch_id INTO v_branch FROM public.locations WHERE id = v_location AND active;
    IF v_branch IS NULL OR NOT public.is_branch_member(v_branch) THEN
        RAISE EXCEPTION 'Location not found' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.cash_sessions (session_no, branch_id, location_id, user_id, opening_float)
    VALUES ('SHIFT-' || lpad(nextval('public.cash_session_no_seq')::text, 6, '0'), v_branch, v_location, auth.uid(),
            round(p_opening_float, 2))
    RETURNING * INTO v_session;
    RETURN public.cash_session_summary(v_session.id);
END;
$function$
;
CREATE OR REPLACE FUNCTION public.post_tailoring_payment(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_request_id UUID := NULLIF(p->>'request_id', '')::uuid;
    v_existing JSONB;
    v_order public.tailoring_orders;
    v_totals JSONB;
BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;

    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'request_id is required';
    END IF;
    v_existing := public.idempotency_begin(v_request_id, 'post_tailoring_payment');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    SELECT * INTO v_order FROM public.tailoring_orders WHERE id = NULLIF(p->>'order_id', '')::uuid FOR UPDATE;
    IF v_order.id IS NULL OR NOT public.is_counter_staff() OR NOT public.is_branch_member(v_order.branch_id) THEN
        RAISE EXCEPTION 'Order not found';
    END IF;
    IF v_order.status IN ('draft', 'cancelled', 'delivered') THEN
        RAISE EXCEPTION 'Payments are taken on confirmed orders only (this one is %)', v_order.status;
    END IF;
    IF jsonb_typeof(p->'payments') <> 'array' OR jsonb_array_length(p->'payments') = 0 THEN
        RAISE EXCEPTION 'Add a payment';
    END IF;

    PERFORM public.record_tailoring_payments(v_order.id, p->'payments', 'in');
    v_totals := public.tailoring_order_totals(v_order.id);
    IF (v_totals->>'balance')::numeric < 0 THEN
        RAISE EXCEPTION 'That is more than the balance due';
    END IF;

    RETURN public.idempotency_finish(v_request_id, public.tailoring_order_summary(v_order.id));
END;
$function$
;
CREATE OR REPLACE FUNCTION public.record_cash_movement(p_amount numeric, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_session public.cash_sessions;
BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;

    IF COALESCE(trim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required';
    END IF;
    IF p_amount IS NULL OR p_amount = 0 OR p_amount <> round(p_amount, 2) THEN
        RAISE EXCEPTION 'Enter an amount';
    END IF;
    SELECT * INTO v_session FROM public.cash_sessions WHERE user_id = auth.uid() AND status = 'open' FOR UPDATE;
    IF v_session.id IS NULL THEN
        RAISE EXCEPTION 'No open cash shift';
    END IF;
    IF p_amount < 0 AND v_session.opening_float + COALESCE(
           (SELECT sum(amount) FROM public.cash_movements WHERE session_id = v_session.id), 0) + p_amount < 0 THEN
        RAISE EXCEPTION 'There is not that much cash in the drawer';
    END IF;

    INSERT INTO public.cash_movements (session_id, amount, movement_type, reason)
    VALUES (v_session.id, p_amount, CASE WHEN p_amount > 0 THEN 'cash_in' ELSE 'cash_out' END, trim(p_reason));
    RETURN public.cash_session_summary(v_session.id);
END;
$function$
;
CREATE OR REPLACE FUNCTION public.record_stock_count(p_count_id uuid, p_variant_id uuid, p_counted numeric, p_roll_id uuid DEFAULT NULL::uuid)
 RETURNS stock_count_lines
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_count public.stock_counts;
    v_unit TEXT;
    v_expected NUMERIC;
    v_line public.stock_count_lines;
BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;

    IF public.current_app_role() NOT IN ('admin', 'manager', 'cashier') THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_count FROM public.stock_counts WHERE id = p_count_id FOR UPDATE;
    IF v_count.id IS NULL OR NOT public.is_branch_member(v_count.branch_id) THEN
        RAISE EXCEPTION 'Count not found';
    END IF;
    IF v_count.status <> 'open' THEN
        RAISE EXCEPTION 'Count % is %', v_count.count_no, v_count.status;
    END IF;
    IF p_counted IS NULL OR p_counted < 0 THEN
        RAISE EXCEPTION 'Counted quantity cannot be negative';
    END IF;

    SELECT s.unit INTO v_unit FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id
    WHERE v.id = p_variant_id AND s.track_inventory;
    IF v_unit IS NULL THEN
        RAISE EXCEPTION 'Item not found or does not track stock';
    END IF;

    IF v_unit = 'meter' THEN
        IF p_roll_id IS NULL THEN
            RAISE EXCEPTION 'Fabric is counted per roll';
        END IF;
        IF p_counted <> round(p_counted, 2) THEN
            RAISE EXCEPTION 'Roll length can have at most 2 decimals';
        END IF;
        SELECT remaining_length INTO v_expected FROM public.fabric_rolls
        WHERE id = p_roll_id AND variant_id = p_variant_id AND location_id = v_count.location_id;
        IF v_expected IS NULL THEN
            RAISE EXCEPTION 'That roll is not at this location';
        END IF;
    ELSE
        IF p_roll_id IS NOT NULL THEN
            RAISE EXCEPTION 'Only fabric is counted per roll';
        END IF;
        IF p_counted <> trunc(p_counted) THEN
            RAISE EXCEPTION 'Whole quantities only';
        END IF;
        SELECT COALESCE((SELECT on_hand FROM public.stock_balances
                         WHERE variant_id = p_variant_id AND location_id = v_count.location_id), 0)
        INTO v_expected;
    END IF;

    INSERT INTO public.stock_count_lines (count_id, variant_id, roll_id, counted, expected)
    VALUES (p_count_id, p_variant_id, p_roll_id, p_counted, v_expected)
    ON CONFLICT (count_id, variant_id, COALESCE(roll_id, '00000000-0000-0000-0000-000000000000'::uuid))
    DO UPDATE SET counted = EXCLUDED.counted, expected = EXCLUDED.expected,
                  counted_by = auth.uid(), counted_at = now()
    RETURNING * INTO v_line;
    RETURN v_line;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.sale_detail(p_sale_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_sale public.sales;
BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;

    SELECT s.* INTO v_sale FROM public.sales s
    WHERE s.id = p_sale_id AND public.is_counter_staff() AND public.is_branch_member(s.branch_id)
      AND (public.has_app_role(ARRAY['admin','manager']) OR s.cashier_id = auth.uid());
    IF v_sale.id IS NULL THEN RETURN NULL; END IF;
    RETURN jsonb_build_object(
        'header', jsonb_build_object(
            'id', v_sale.id, 'invoice_number', v_sale.invoice_number, 'receipt_number', v_sale.receipt_number,
            'created_at', v_sale.created_at, 'status', v_sale.status,
            'customer_id', v_sale.customer_id, 'customer_name', coalesce(v_sale.customer_name, (SELECT c.name FROM public.customers c WHERE c.id = v_sale.customer_id)),
            'cashier_name', coalesce(v_sale.cashier, (SELECT u.name FROM public.users u WHERE u.id = v_sale.cashier_id)),
            'subtotal', v_sale.subtotal, 'discount_amount', v_sale.discount_amount, 'tax_amount', v_sale.tax_amount,
            'total', v_sale.total, 'payment_method', v_sale.payment_method, 'notes', v_sale.notes),
        -- Explicit public line fields: unit_cost is intentionally not exposed to cashiers.
        'lines', coalesce((SELECT jsonb_agg(jsonb_build_object(
            'id', l.id, 'line_no', l.line_no, 'variant_id', l.variant_id, 'description', l.description,
            'sku', l.sku, 'unit', l.unit, 'quantity', l.quantity, 'unit_price', l.unit_price,
            'gross', l.gross, 'manual_discount', l.manual_discount, 'promotion_discount', l.promotion_discount,
            'net', l.net, 'taxable', l.taxable, 'tax', l.tax, 'total', l.total, 'is_gift', l.is_gift,
            'returned_quantity', coalesce((SELECT sum(rl.quantity) FROM public.return_lines rl WHERE rl.sale_line_id = l.id), 0)
        ) ORDER BY l.line_no) FROM public.sale_lines l WHERE l.sale_id = v_sale.id), '[]'::jsonb),
        'payments', coalesce((SELECT jsonb_agg(jsonb_build_object(
            'id', pay.id, 'created_at', pay.created_at, 'direction', pay.direction, 'method', pay.method,
            'amount', pay.amount, 'tendered', pay.tendered, 'change_given', pay.change_given,
            'reference', pay.reference, 'card_type', pay.card_type, 'card_last4', pay.card_last4, 'return_id', pay.return_id
        ) ORDER BY pay.created_at, pay.id) FROM public.payments pay
        WHERE pay.sale_id = v_sale.id OR EXISTS (SELECT 1 FROM public.returns r WHERE r.id = pay.return_id AND r.sale_id = v_sale.id)), '[]'::jsonb),
        'returns', coalesce((SELECT jsonb_agg(jsonb_build_object(
            'id', r.id, 'return_no', r.return_no, 'created_at', r.created_at, 'reason', r.reason,
            'refund_total', r.refund_total, 'refund_method', r.refund_method
        ) ORDER BY r.created_at, r.id) FROM public.returns r WHERE r.sale_id = v_sale.id), '[]'::jsonb)
    );
END;
$function$
;
CREATE OR REPLACE FUNCTION public.sale_returnable(p_sale_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;
RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'sale_line_id', sl.id,
        'line_no', sl.line_no,
        'variant_id', sl.variant_id,
        'description', sl.description,
        'sku', sl.sku,
        'unit', sl.unit,
        'quantity', sl.quantity,
        'returned', COALESCE(r.returned, 0),
        'returnable', sl.quantity - COALESCE(r.returned, 0),
        'unit_paid', CASE WHEN sl.quantity > 0 THEN round(sl.total / sl.quantity, 2) ELSE 0 END,
        'is_gift', sl.is_gift
    ) ORDER BY sl.line_no), '[]'::jsonb)
    FROM public.sale_lines sl
    LEFT JOIN (SELECT sale_line_id, sum(quantity) AS returned FROM public.return_lines GROUP BY sale_line_id) r
           ON r.sale_line_id = sl.id
    WHERE sl.sale_id = p_sale_id
      AND EXISTS (SELECT 1 FROM public.sales s WHERE s.id = p_sale_id
                  AND public.is_branch_member(s.branch_id)
                  AND public.current_app_role() IN ('admin', 'manager', 'cashier')));
END;$function$
;
CREATE OR REPLACE FUNCTION public.search_sales(p jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(id uuid, invoice_number text, created_at timestamp with time zone, status text, customer_id uuid, customer_name text, cashier_name text, total numeric, paid_methods text[], returned_amount numeric, line_count integer, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_from DATE := NULLIF(p->>'from', '')::date;
    v_to DATE := NULLIF(p->>'to', '')::date;
    v_status TEXT := NULLIF(p->>'status', '');
    v_method TEXT := NULLIF(p->>'method', '');
    -- Treat search text literally, including %, _ and backslash.
    v_q TEXT := replace(replace(replace(trim(coalesce(p->>'q', '')), E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_');
    v_phone TEXT := regexp_replace(coalesce(p->>'q', ''), '[^0-9]', '', 'g');
    v_limit INT := least(200, greatest(1, coalesce((p->>'limit')::int, 50)));
    v_offset INT := greatest(0, coalesce((p->>'offset')::int, 0));
BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;

    IF NOT public.is_counter_staff() THEN RETURN; END IF;
    IF v_status IS NOT NULL AND v_status NOT IN ('completed','credit','draft','returned','refunded') THEN
        RAISE EXCEPTION 'Choose a valid sale status' USING ERRCODE = '22023';
    END IF;
    IF v_method IS NOT NULL AND v_method NOT IN ('cash','card','digital','credit','exchange') THEN
        RAISE EXCEPTION 'Choose a valid payment method' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY
    SELECT s.id, s.invoice_number, s.created_at, s.status, s.customer_id,
        coalesce(s.customer_name, c.name), coalesce(s.cashier, u.name), s.total,
        ARRAY(SELECT DISTINCT pay.method FROM public.payments pay WHERE pay.sale_id = s.id ORDER BY pay.method),
        coalesce((SELECT sum(r.refund_total) FROM public.returns r WHERE r.sale_id = s.id), 0),
        (SELECT count(*)::int FROM public.sale_lines l WHERE l.sale_id = s.id), count(*) OVER ()
    FROM public.sales s
    LEFT JOIN public.customers c ON c.id = s.customer_id
    LEFT JOIN public.users u ON u.id = s.cashier_id
    WHERE public.is_branch_member(s.branch_id)
      AND (public.has_app_role(ARRAY['admin','manager']) OR s.cashier_id = auth.uid())
      AND (v_from IS NULL OR s.created_at >= (v_from::timestamp AT TIME ZONE public.report_tz()))
      AND (v_to IS NULL OR s.created_at < ((v_to + 1)::timestamp AT TIME ZONE public.report_tz()))
      AND (v_status IS NULL OR s.status = v_status OR (v_status = 'returned' AND EXISTS (
          SELECT 1 FROM public.returns r WHERE r.sale_id = s.id)))
      AND (v_method IS NULL OR EXISTS (SELECT 1 FROM public.payments pay WHERE pay.sale_id = s.id AND pay.method = v_method))
      AND (v_q = '' OR s.invoice_number ILIKE v_q || '%' OR c.name ILIKE '%' || v_q || '%'
          OR s.customer_name ILIKE '%' || v_q || '%' OR c.phone ILIKE '%' || v_q || '%'
          -- Also accept local 03xx and formatted +92 phone searches.
          OR (coalesce(p->>'q', '') ~ '^[+0-9() .-]+$' AND length(v_phone) >= 4 AND (c.phone LIKE '%' || v_phone || '%'
              OR (left(v_phone, 1) = '0' AND c.phone LIKE '%' || substr(v_phone, 2) || '%')))
          OR EXISTS (SELECT 1 FROM public.sale_lines l WHERE l.sale_id = s.id AND l.sku ILIKE '%' || v_q || '%'))
    ORDER BY s.created_at DESC, s.id
    LIMIT v_limit OFFSET v_offset;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.tailor_queue()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;
RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'item_id', i.id,
        'order_no', o.order_no,
        'line_no', i.line_no,
        'garment_type', i.garment_type,
        'garment_name', g.name,
        'fields', g.fields,
        'wearer_name', w.name,
        'measurements', i.measurements_snapshot,
        'fit_preference', i.fit_preference,
        'design_notes', i.design_notes,
        'status', i.status,
        'due_date', i.due_date,
        'fitting_date', o.fitting_date,
        'promised_date', o.promised_date,
        'assigned_tailor', i.assigned_tailor,
        'tailor_name', t.name,
        'materials', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('source', m.source, 'description', m.description,
                                                'quantity', m.quantity, 'unit', m.unit, 'status', m.status,
                                                'roll_code', r.roll_code))
            FROM public.tailoring_materials m LEFT JOIN public.fabric_rolls r ON r.id = m.roll_id
            WHERE m.item_id = i.id AND m.status <> 'released'), '[]'::jsonb),
        'last_note', (SELECT note FROM public.tailoring_job_events e WHERE e.item_id = i.id AND note IS NOT NULL
                      ORDER BY e.created_at DESC LIMIT 1)
    ) ORDER BY COALESCE(i.due_date, o.promised_date), o.order_no, i.line_no), '[]'::jsonb)
    FROM public.tailoring_items i
    JOIN public.tailoring_orders o ON o.id = i.order_id
    JOIN public.garment_types g ON g.code = i.garment_type
    JOIN public.wearer_profiles w ON w.id = i.wearer_id
    LEFT JOIN public.users t ON t.id = i.assigned_tailor
    WHERE o.status NOT IN ('draft', 'cancelled')
      AND i.status NOT IN ('delivered', 'cancelled')
      AND public.is_branch_member(o.branch_id)
      AND (public.has_app_role(ARRAY['admin', 'manager'])
           OR (public.current_app_role() = 'tailor'
               AND (i.assigned_tailor = auth.uid() OR (i.assigned_tailor IS NULL AND i.status = 'awaiting')))));
END;$function$
;
CREATE OR REPLACE FUNCTION public.tailoring_order_summary(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$BEGIN
 IF NOT public.is_staff() THEN
 RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE='42501';
 END IF;
RETURN (SELECT to_jsonb(o) || public.tailoring_order_totals(o.id) || jsonb_build_object(
        'customer', jsonb_build_object('id', c.id, 'name', c.name, 'phone', c.phone),
        'items', COALESCE((
            SELECT jsonb_agg(to_jsonb(i) || jsonb_build_object(
                'garment_name', g.name, 'wearer_name', w.name,
                'tailor_name', (SELECT name FROM public.users u WHERE u.id = i.assigned_tailor))
                ORDER BY i.line_no)
            FROM public.tailoring_items i
            JOIN public.garment_types g ON g.code = i.garment_type
            JOIN public.wearer_profiles w ON w.id = i.wearer_id
            WHERE i.order_id = o.id), '[]'::jsonb),
        'charges', COALESCE((SELECT jsonb_agg(to_jsonb(ch) ORDER BY ch.created_at) FROM public.tailoring_charges ch
                             WHERE ch.order_id = o.id), '[]'::jsonb),
        'materials', COALESCE((
            SELECT jsonb_agg(to_jsonb(m) || jsonb_build_object('roll_code', r.roll_code) ORDER BY m.created_at)
            FROM public.tailoring_materials m LEFT JOIN public.fabric_rolls r ON r.id = m.roll_id
            WHERE m.order_id = o.id), '[]'::jsonb),
        'payments', COALESCE((SELECT jsonb_agg(jsonb_build_object('method', p.method, 'amount', p.amount,
                                                                  'direction', p.direction, 'created_at', p.created_at)
                                               ORDER BY p.created_at)
                              FROM public.payments p WHERE p.tailoring_order_id = o.id), '[]'::jsonb)
    )
    FROM public.tailoring_orders o
    JOIN public.customers c ON c.id = o.customer_id
    WHERE o.id = p_order_id AND public.is_counter_staff() AND public.is_branch_member(o.branch_id));
END;$function$
;
