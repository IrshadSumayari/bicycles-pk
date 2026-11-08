-- =====================================================================
-- Remove the tailoring, fabric and appointment schema inherited from the
-- previous project. LadyVogue sells ready-made pieces, packs and services;
-- nothing in the POS or website uses these objects any more.
--
--   * shared functions stop referring to tailoring, fabric rolls and cuts
--   * tailoring_request_begin() becomes the generic request_begin()
--   * old tables, columns, functions, bucket and the tailor role are dropped
-- =====================================================================

-- Applies exact text replacements to a function definition and recreates it.
-- Fails loudly if a fragment is missing, so a changed definition is reviewed.
-- Line endings are normalised first: a Windows checkout stores CRLF bodies.
CREATE FUNCTION pg_temp.patch_function(p_function regprocedure, p_pairs text[])
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

-- ---------------------------------------------------------------------
-- Generic request helper (was tailoring_request_begin)
-- ---------------------------------------------------------------------
CREATE FUNCTION public.request_begin(p_key uuid, p_operation text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r JSONB;
BEGIN
 IF p_key IS NULL THEN RAISE EXCEPTION 'request_id is required'; END IF;
 r:=public.idempotency_begin(p_key,p_operation);
 IF NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=p_key AND user_id=auth.uid()) THEN
  RAISE EXCEPTION 'Please use a new request id' USING ERRCODE='42501';
 END IF;
 RETURN r;
END $$;
REVOKE ALL ON FUNCTION public.request_begin(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.request_begin(uuid, text) TO service_role;

SELECT pg_temp.patch_function('public.advance_online_order(jsonb)', ARRAY[
  'public.tailoring_request_begin(', 'public.request_begin(',
  '''sale'',header.id,cost,NULL,reservation.roll_id);', '''sale'',header.id,cost,NULL);',
  'SELECT * INTO reservation FROM public.stock_reservations WHERE id=l.reservation_id;' || chr(10) || '   ', '']);
SELECT pg_temp.patch_function('public.cancel_online_order(jsonb)', ARRAY['public.tailoring_request_begin(', 'public.request_begin(']);
SELECT pg_temp.patch_function('public.collect_cod_payment(jsonb)', ARRAY['public.tailoring_request_begin(', 'public.request_begin(']);
SELECT pg_temp.patch_function('public.record_online_refund(jsonb)', ARRAY['public.tailoring_request_begin(', 'public.request_begin(']);
SELECT pg_temp.patch_function('public.staff_link_customer_account(uuid,uuid,uuid)', ARRAY[
  'public.tailoring_request_begin(', 'public.request_begin(',
  ' UPDATE public.tailoring_requests SET customer_id=p_customer WHERE account_id=p_account AND customer_id IS NULL;' || chr(10), '']);
SELECT pg_temp.patch_function('public.link_customer_account()', ARRAY[
  ' UPDATE public.tailoring_requests SET customer_id=c WHERE account_id=a AND customer_id IS NULL;' || chr(10), '']);

-- ---------------------------------------------------------------------
-- Online orders: no fabric lengths, rolls or cuts
-- ---------------------------------------------------------------------
SELECT pg_temp.patch_function('public.quote_online_order(jsonb)', ARRAY[
  'available BOOLEAN;cut_m NUMERIC;pieces NUMERIC;cut TEXT;', 'available BOOLEAN;',
  'count(DISTINCT (x->>''variant_id'',coalesce(x->>''cut'','''')))', 'count(DISTINCT x->>''variant_id'')',
  'ps.track_inventory,ps.fabric_cuts INTO v', 'ps.track_inventory INTO v',
  '  IF v.unit=''meter'' THEN' || chr(10) || '   IF qty NOT BETWEEN 0.5 AND 50 OR mod(qty,0.25)<>0 THEN RAISE EXCEPTION ''Choose metres from 0.5 to 50 in steps of 0.25''; END IF;' || chr(10) || '  ELSIF qty NOT BETWEEN 1 AND 10',
  '  IF qty NOT BETWEEN 1 AND 10',
  '  cut:=NULL;pieces:=NULL;' || chr(10) || '  IF item ? ''cut'' THEN' || chr(10) || '   IF jsonb_typeof(item->''cut'') IS DISTINCT FROM ''string'' OR v.unit<>''meter'' THEN RAISE EXCEPTION ''Choose an available fabric cut''; END IF;' || chr(10) || '   cut:=item->>''cut'';SELECT (c->>''meters'')::numeric INTO cut_m FROM jsonb_array_elements(v.fabric_cuts) c WHERE c->>''label''=cut;' || chr(10) || '   IF cut_m IS NULL THEN RAISE EXCEPTION ''Choose an available fabric cut''; END IF;' || chr(10) || '   pieces:=qty/cut_m;' || chr(10) || '   IF pieces NOT BETWEEN 1 AND 10 OR pieces<>trunc(pieces) THEN RAISE EXCEPTION ''Quantity must equal 1 to 10 whole pieces of the selected cut''; END IF;' || chr(10) || '  END IF;' || chr(10), '',
  ' AND b.on_hand-b.reserved>=qty' || chr(10) || '   AND (v.unit<>''meter'' OR EXISTS(SELECT 1 FROM public.fabric_rolls r WHERE r.variant_id=b.variant_id AND r.location_id=b.location_id AND r.remaining_length-r.reserved_length>=qty))) INTO available;',
  ' AND b.on_hand-b.reserved>=qty) INTO available;',
  '''variant_id'',v.variant_id,''cut'',cut,''cut_pieces'',pieces,''description'',v.title||CASE WHEN cut IS NULL THEN '''' ELSE '' – ''||pieces::int||'' × ''||cut||'' ''||trim_scale(cut_m)::text||'' m'' END,',
  '''variant_id'',v.variant_id,''description'',v.title,']);

SELECT pg_temp.patch_function('public.create_online_order(jsonb)', ARRAY[
  'public.tailoring_request_begin(', 'public.request_begin(',
  ' AND b.on_hand-b.reserved>=qty' || chr(10) || '   AND (item->>''unit''<>''meter'' OR EXISTS(SELECT 1 FROM public.fabric_rolls r WHERE r.variant_id=b.variant_id AND r.location_id=b.location_id AND r.remaining_length-r.reserved_length>=qty))' || chr(10),
  ' AND b.on_hand-b.reserved>=qty' || chr(10),
  '  IF item->>''unit''=''meter'' THEN' || chr(10) || '   res:=public.reserve_roll_length((item->>''variant_id'')::uuid,chosen,qty,NULL,''online_order'',o.id);' || chr(10) || '   UPDATE public.stock_reservations SET channel=''web'',expires_at=hold WHERE id=res.id;' || chr(10) || '  ELSE' || chr(10) || '   UPDATE public.stock_balances SET reserved=reserved+qty,updated_at=now() WHERE location_id=chosen AND variant_id=(item->>''variant_id'')::uuid;' || chr(10) || '   INSERT INTO public.stock_reservations(branch_id,location_id,variant_id,quantity,channel,reference_type,reference_id,expires_at)' || chr(10) || '   VALUES(o.branch_id,chosen,(item->>''variant_id'')::uuid,qty,''web'',''online_order'',o.id,hold) RETURNING * INTO res;' || chr(10) || '  END IF;',
  '  UPDATE public.stock_balances SET reserved=reserved+qty,updated_at=now() WHERE location_id=chosen AND variant_id=(item->>''variant_id'')::uuid;' || chr(10) || '  INSERT INTO public.stock_reservations(branch_id,location_id,variant_id,quantity,channel,reference_type,reference_id,expires_at)' || chr(10) || '  VALUES(o.branch_id,chosen,(item->>''variant_id'')::uuid,qty,''web'',''online_order'',o.id,hold) RETURNING * INTO res;',
  ',location_id,reservation_id,cut_label,cut_pieces)', ',location_id,reservation_id)',
  ',chosen,res.id,item->>''cut'',nullif(item->>''cut_pieces'','''')::numeric::int);', ',chosen,res.id);']);

SELECT pg_temp.patch_function('public.close_online_reservations(uuid,text)', ARRAY[
  '  IF r.roll_id IS NOT NULL THEN UPDATE public.fabric_rolls SET reserved_length=reserved_length-r.quantity WHERE id=r.roll_id; END IF;' || chr(10), '']);

SELECT pg_temp.patch_function('public.online_order_public(uuid)', ARRAY[
  '''cut'',l.cut_label,''cut_pieces'',l.cut_pieces,', '']);

SELECT pg_temp.patch_function('public.catalog_product(text)', ARRAY[
  '''kind'',st.kind,''fabric_cuts'',st.fabric_cuts,', '''kind'',st.kind,']);

-- ---------------------------------------------------------------------
-- Stock ledger: every item is counted in whole units
-- ---------------------------------------------------------------------
DROP FUNCTION public.post_stock_movement(uuid, uuid, numeric, text, text, text, uuid, numeric, text, uuid);
CREATE FUNCTION public.post_stock_movement(
    p_location_id uuid, p_variant_id uuid, p_quantity numeric, p_movement_type text,
    p_channel text DEFAULT 'pos', p_reference_type text DEFAULT NULL, p_reference_id uuid DEFAULT NULL,
    p_unit_cost numeric DEFAULT NULL, p_reason text DEFAULT NULL)
RETURNS public.stock_balances LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_balance public.stock_balances;
    v_name TEXT;
BEGIN
    IF p_quantity = 0 THEN
        RAISE EXCEPTION 'Quantity cannot be zero';
    END IF;

    SELECT s.name || COALESCE(' ' || v.size, '') || COALESCE(' ' || v.color, '')
    INTO v_name
    FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id
    WHERE v.id = p_variant_id;
    IF v_name IS NULL THEN
        RAISE EXCEPTION 'Item not found';
    END IF;

    v_balance := public.lock_stock_balance(p_location_id, p_variant_id);

    IF p_quantity < 0 AND v_balance.on_hand - v_balance.reserved + p_quantity < 0 THEN
        RAISE EXCEPTION 'Not enough stock for "%" (available: %, needed: %)',
            v_name, trim_scale(v_balance.on_hand - v_balance.reserved), trim_scale(-p_quantity)
            USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.stock_movements (
        branch_id, location_id, variant_id, quantity, movement_type, channel,
        reference_type, reference_id, unit_cost, reason
    ) VALUES (
        v_balance.branch_id, p_location_id, p_variant_id, p_quantity, p_movement_type, p_channel,
        p_reference_type, p_reference_id, p_unit_cost, p_reason
    );

    UPDATE public.stock_balances
    SET on_hand = on_hand + p_quantity, updated_at = now()
    WHERE location_id = p_location_id AND variant_id = p_variant_id
    RETURNING * INTO v_balance;

    RETURN v_balance;
END;
$$;
REVOKE ALL ON FUNCTION public.post_stock_movement(uuid, uuid, numeric, text, text, text, uuid, numeric, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.post_stock_movement(uuid, uuid, numeric, text, text, text, uuid, numeric, text) TO service_role;

SELECT pg_temp.patch_function('public.adjust_stock(uuid,uuid,numeric,text,text,uuid)', ARRAY[
  'IF v_unit <> ''meter'' AND p_quantity <> trunc(p_quantity) THEN', 'IF p_quantity <> trunc(p_quantity) THEN']);

SELECT pg_temp.patch_function('public.quote_sale(jsonb)', ARRAY[
  '        IF v_variant.unit = ''meter'' THEN' || chr(10) || '            IF v_qty <> round(v_qty, 2) THEN' || chr(10) || '                RAISE EXCEPTION ''Fabric length for "%" can have at most 2 decimals'', v_variant.description;' || chr(10) || '            END IF;' || chr(10) || '        ELSIF v_qty <> trunc(v_qty) THEN',
  '        IF v_qty <> trunc(v_qty) THEN']);

SELECT pg_temp.patch_function('public.post_goods_receipt(jsonb)', ARRAY[
  '    v_roll public.fabric_rolls;' || chr(10) || '    v_roll_code TEXT;' || chr(10), '',
  '        IF v_variant.unit = ''meter'' THEN' || chr(10) || '            IF v_qty <> round(v_qty, 2) THEN' || chr(10) || '                RAISE EXCEPTION ''Roll length for "%" can have at most 2 decimals'', v_variant.description;' || chr(10) || '            END IF;' || chr(10) || '        ELSIF v_qty <> trunc(v_qty) THEN',
  '        IF v_qty <> trunc(v_qty) THEN',
  '        v_roll := NULL;' || chr(10) || '        IF v_variant.unit = ''meter'' THEN' || chr(10) || '            v_roll_code := NULLIF(upper(trim(COALESCE(v_line->>''roll_code'', ''''))), '''');' || chr(10) || '            IF v_roll_code IS NOT NULL AND EXISTS (SELECT 1 FROM public.barcodes WHERE code = v_roll_code) THEN' || chr(10) || '                RAISE EXCEPTION ''Code % is already used'', v_roll_code;' || chr(10) || '            END IF;' || chr(10) || '            PERFORM public.lock_stock_balance(v_location, v_variant.id);' || chr(10) || '            INSERT INTO public.fabric_rolls (variant_id, branch_id, location_id, roll_code, width_cm, shade_lot,' || chr(10) || '                                             initial_length, remaining_length, unit_cost, notes)' || chr(10) || '            VALUES (v_variant.id, v_branch, v_location, COALESCE(v_roll_code, public.next_roll_code()),' || chr(10) || '                    NULLIF(v_line->>''width_cm'', '''')::numeric, NULLIF(trim(v_line->>''shade_lot''), ''''),' || chr(10) || '                    v_qty, 0, v_cost, ''Received on '' || v_receipt.receipt_no)' || chr(10) || '            RETURNING * INTO v_roll;' || chr(10) || '            INSERT INTO public.barcodes (code, variant_id, roll_id) VALUES (v_roll.roll_code, v_variant.id, v_roll.id);' || chr(10) || '        END IF;' || chr(10) || chr(10), '',
  'v_receipt.id, v_cost, v_receipt.receipt_no, v_roll.id);', 'v_receipt.id, v_cost, v_receipt.receipt_no);',
  '                                                line_cost, roll_id)' || chr(10) || '        VALUES (v_receipt.id, v_line_no, v_variant.id, v_variant.description, v_qty, v_cost, round(v_qty * v_cost, 2),' || chr(10) || '                v_roll.id);',
  '                                                line_cost)' || chr(10) || '        VALUES (v_receipt.id, v_line_no, v_variant.id, v_variant.description, v_qty, v_cost, round(v_qty * v_cost, 2));']);

SELECT pg_temp.patch_function('public.create_return(jsonb,text)', ARRAY[
  '    v_roll public.fabric_rolls;' || chr(10), '',
  '        IF v_line.unit = ''meter'' THEN' || chr(10) || '            IF v_qty <> round(v_qty, 2) THEN' || chr(10) || '                RAISE EXCEPTION ''Length for "%" can have at most 2 decimals'', v_line.description;' || chr(10) || '            END IF;' || chr(10) || '        ELSIF v_qty <> trunc(v_qty) THEN',
  '        IF v_qty <> trunc(v_qty) THEN',
  '        IF v_line.unit IN (''meter'', ''job'') THEN', '        IF v_line.unit = ''job'' THEN',
  '            IF v_line.unit = ''meter'' THEN' || chr(10) || '                -- Returned fabric becomes a remnant roll' || chr(10) || '                PERFORM public.lock_stock_balance(v_return.location_id, v_line.variant_id);' || chr(10) || '                INSERT INTO public.fabric_rolls (variant_id, branch_id, location_id, roll_code, initial_length,' || chr(10) || '                                                 remaining_length, unit_cost, notes)' || chr(10) || '                VALUES (v_line.variant_id, v_return.branch_id, v_return.location_id, public.next_roll_code(), v_qty, 0,' || chr(10) || '                        v_line.unit_cost, ''Returned on '' || v_return.return_no)' || chr(10) || '                RETURNING * INTO v_roll;' || chr(10) || '                INSERT INTO public.barcodes (code, variant_id, roll_id) VALUES (v_roll.roll_code, v_line.variant_id, v_roll.id);' || chr(10) || '                PERFORM public.post_stock_movement(v_return.location_id, v_line.variant_id, v_qty, ''return'', ''pos'',' || chr(10) || '                                                   ''return'', v_return.id, v_line.unit_cost, v_return.return_no, v_roll.id);' || chr(10) || '            ELSE' || chr(10) || '                PERFORM public.post_stock_movement(v_return.location_id, v_line.variant_id, v_qty, ''return'', ''pos'',' || chr(10) || '                                                   ''return'', v_return.id, v_line.unit_cost, v_return.return_no);' || chr(10) || '            END IF;',
  '            PERFORM public.post_stock_movement(v_return.location_id, v_line.variant_id, v_qty, ''return'', ''pos'',' || chr(10) || '                                               ''return'', v_return.id, v_line.unit_cost, v_return.return_no);',
  'This return needs a manager (fabric, services, or outside', 'This return needs a manager (services, or outside']);

-- Stock counts: one line per item
DROP FUNCTION public.record_stock_count(uuid, uuid, numeric, uuid);
CREATE FUNCTION public.record_stock_count(p_count_id uuid, p_variant_id uuid, p_counted numeric)
RETURNS public.stock_count_lines LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_count public.stock_counts;
    v_expected NUMERIC;
    v_line public.stock_count_lines;
BEGIN
    IF NOT public.is_staff() THEN
        RAISE EXCEPTION 'Use the shop system with an active staff account' USING ERRCODE = '42501';
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
    IF p_counted <> trunc(p_counted) THEN
        RAISE EXCEPTION 'Whole quantities only';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id
                   WHERE v.id = p_variant_id AND s.track_inventory) THEN
        RAISE EXCEPTION 'Item not found or does not track stock';
    END IF;

    SELECT COALESCE((SELECT on_hand FROM public.stock_balances
                     WHERE variant_id = p_variant_id AND location_id = v_count.location_id), 0)
    INTO v_expected;

    INSERT INTO public.stock_count_lines (count_id, variant_id, counted, expected)
    VALUES (p_count_id, p_variant_id, p_counted, v_expected)
    ON CONFLICT (count_id, variant_id)
    DO UPDATE SET counted = EXCLUDED.counted, expected = EXCLUDED.expected,
                  counted_by = auth.uid(), counted_at = now()
    RETURNING * INTO v_line;
    RETURN v_line;
END;
$$;
REVOKE ALL ON FUNCTION public.record_stock_count(uuid, uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_stock_count(uuid, uuid, numeric) TO authenticated, service_role;

SELECT pg_temp.patch_function('public.approve_stock_count(uuid)', ARRAY[
  'ORDER BY variant_id, roll_id', 'ORDER BY variant_id',
  '''Stock count '' || v_count.count_no, v_line.roll_id);', '''Stock count '' || v_count.count_no);']);

SELECT pg_temp.patch_function('public.search_variants(jsonb)', ARRAY[
  'ORDER BY (bc.roll_id IS NOT NULL),bc.code', 'ORDER BY bc.code',
  'bc.variant_id=v.id AND bc.roll_id IS NULL ORDER BY', 'bc.variant_id=v.id ORDER BY']);
SELECT pg_temp.patch_function('public.variant_by_code(text,uuid)', ARRAY[
  'ORDER BY (bc.roll_id IS NOT NULL),bc.code', 'ORDER BY bc.code',
  'bc.variant_id=v.id AND bc.roll_id IS NULL ORDER BY', 'bc.variant_id=v.id ORDER BY']);

-- ---------------------------------------------------------------------
-- Product styles: ready-made pieces, packs and services
-- ---------------------------------------------------------------------
SELECT pg_temp.patch_function('public.save_style(jsonb)', ARRAY[
  'IF v_kind NOT IN (''garment'', ''pack'', ''fabric'', ''service'') THEN', 'IF v_kind NOT IN (''garment'', ''pack'', ''service'') THEN',
  'WHEN ''pack'' THEN ''set'' WHEN ''fabric'' THEN ''meter'' WHEN ''service''', 'WHEN ''pack'' THEN ''set'' WHEN ''service''']);

SELECT pg_temp.patch_function('public.save_style_web_details(uuid,jsonb,uuid)', ARRAY[
  'IF k NOT IN (''slug'',''web_title'',''web_description'',''variants'',''fabric_cuts'') THEN', 'IF k NOT IN (''slug'',''web_title'',''web_description'',''variants'') THEN',
  ' IF p ? ''fabric_cuts'' AND (NOT public.valid_fabric_cuts(p->''fabric_cuts'') OR (p->''fabric_cuts''<>''[]'' AND (s.kind<>''fabric'' OR s.unit<>''meter''))) THEN RAISE EXCEPTION ''Use up to 12 unique fabric cut labels and quarter-metre lengths from 0.25 to 20''; END IF;' || chr(10), '',
  'SET fabric_cuts=CASE WHEN p ? ''fabric_cuts'' THEN p->''fabric_cuts'' ELSE fabric_cuts END, slug=', 'SET slug=',
  'jsonb_build_object(''fabric_cuts'',s.fabric_cuts,''style_id''', 'jsonb_build_object(''style_id''']);

-- ---------------------------------------------------------------------
-- Settings, statements and reports
-- ---------------------------------------------------------------------
SELECT pg_temp.patch_function('public.update_settings(jsonb)', ARRAY[
  '''cash_variance_alert'',''min_tailoring_deposit_percent'',''receipt_header''', '''cash_variance_alert'',''receipt_header''',
  '''cash_variance_alert'',''min_tailoring_deposit_percent'',''invoice_counter''', '''cash_variance_alert'',''invoice_counter''',
  ' IF p ? ''min_tailoring_deposit_percent'' AND (p->>''min_tailoring_deposit_percent'')::numeric NOT BETWEEN 0 AND 100 THEN RAISE EXCEPTION ''Minimum deposit must be between 0 and 100 percent''; END IF;' || chr(10), '',
  '   min_tailoring_deposit_percent=v_new.min_tailoring_deposit_percent,receipt_header=', '   receipt_header=']);

SELECT pg_temp.patch_function('public.customer_statement(uuid,date,date)', ARRAY[
  'coalesce(s.invoice_number,r.return_no,o.order_no,h.payment_no)', 'coalesce(s.invoice_number,r.return_no,h.payment_no)',
  '   LEFT JOIN public.tailoring_orders o ON o.id=l.tailoring_order_id LEFT JOIN public.customer_payments h', '   LEFT JOIN public.customer_payments h']);

SELECT pg_temp.patch_function('public.cash_session_detail(uuid)', ARRAY[
  'coalesce(r.return_no, s.invoice_number, o.order_no)', 'coalesce(r.return_no, s.invoice_number)',
  '        LEFT JOIN public.tailoring_orders o ON o.id = pay.tailoring_order_id' || chr(10), '']);

SELECT pg_temp.patch_function('public.report_tenders(date,date,uuid)', ARRAY[
  '        LEFT JOIN public.tailoring_orders o ON o.id = p.tailoring_order_id' || chr(10), '',
  'coalesce(r.branch_id, s.branch_id, o.branch_id, cs.branch_id)', 'coalesce(r.branch_id, s.branch_id, cs.branch_id)']);

SELECT pg_temp.patch_function('public.lookup_usage(text,text)', ARRAY[
  ' WHEN ''garment_type'' THEN SELECT (SELECT count(*) FROM public.measurement_sets WHERE garment_type=p_id)' || chr(10) || '  +(SELECT count(*) FROM public.tailoring_items WHERE garment_type=p_id)+(SELECT count(*) FROM public.tailoring_requests WHERE garment_type=p_id) INTO v_count;' || chr(10), '']);
SELECT pg_temp.patch_function('public.delete_business_lookup(text,text)', ARRAY[
  ' WHEN ''garment_type'' THEN SELECT to_jsonb(g.*) INTO v_before FROM public.garment_types g WHERE code=p_id FOR UPDATE;' || chr(10), '',
  ' WHEN ''garment_type'' THEN DELETE FROM public.garment_types WHERE code=p_id;' || chr(10), '']);

-- ---------------------------------------------------------------------
-- Drop the tailoring, appointment and fabric functions
-- ---------------------------------------------------------------------
DO $$
DECLARE f regprocedure;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace AND p.prokind = 'f'
      AND (p.proname ~ '(tailor|fabric|garment|measurement|wearer|appointment|_roll|roll_)'
           OR p.proname IN ('respond_to_quote', 'my_order_progress', 'return_customer_material'))
  LOOP
    EXECUTE format('DROP FUNCTION %s CASCADE', f);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- Drop columns, constraints and tables
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS tailoring_photos_read ON storage.objects;
DROP POLICY IF EXISTS tailoring_photos_upload ON storage.objects;
-- The bucket is removed only when it holds no photos.
SELECT set_config('storage.allow_delete_query', 'true', true);
DELETE FROM storage.buckets b WHERE b.id = 'tailoring-photos'
  AND NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id = b.id);
SELECT set_config('storage.allow_delete_query', 'false', true);

ALTER TABLE public.barcodes DROP COLUMN roll_id;
ALTER TABLE public.goods_receipt_lines DROP COLUMN roll_id;
ALTER TABLE public.stock_movements DROP COLUMN roll_id;
ALTER TABLE public.stock_reservations DROP COLUMN roll_id;
ALTER TABLE public.stock_count_lines DROP COLUMN roll_id;
ALTER TABLE public.stock_count_lines ADD CONSTRAINT stock_count_lines_item_key UNIQUE (count_id, variant_id);
ALTER TABLE public.payments DROP COLUMN tailoring_order_id;
ALTER TABLE public.customer_ledger DROP COLUMN tailoring_order_id;
ALTER TABLE public.online_order_lines DROP COLUMN cut_label, DROP COLUMN cut_pieces;
ALTER TABLE public.product_styles DROP COLUMN fabric_cuts;
ALTER TABLE public.app_settings DROP COLUMN min_tailoring_deposit_percent, DROP COLUMN appointment_hours;

DROP TABLE public.material_custody_events, public.tailoring_materials, public.tailoring_charges,
  public.tailoring_job_events, public.tailoring_items, public.tailoring_request_events,
  public.tailoring_request_photos, public.tailoring_requests, public.tailoring_orders,
  public.measurement_sets, public.wearer_profiles, public.garment_types, public.appointments,
  public.fabric_rolls;
DROP SEQUENCE IF EXISTS public.fabric_roll_code_seq, public.tailoring_order_no_seq, public.tailoring_request_no_seq;

-- Nothing can be a fabric length, a tailoring movement or a tailor any more.
ALTER TABLE public.product_styles DROP CONSTRAINT product_styles_kind_check,
  ADD CONSTRAINT product_styles_kind_check CHECK (kind IN ('garment', 'pack', 'service'));
ALTER TABLE public.product_styles DROP CONSTRAINT product_styles_unit_matches_kind,
  ADD CONSTRAINT product_styles_unit_matches_kind CHECK (
    (kind = 'garment' AND unit = 'piece') OR (kind = 'pack' AND unit = 'set')
    OR (kind = 'service' AND unit = 'job' AND track_inventory = false));
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT conrelid::regclass AS tbl, conname FROM pg_constraint
           WHERE connamespace = 'public'::regnamespace AND contype = 'c'
             AND pg_get_constraintdef(oid) LIKE '%''meter''%' AND conname LIKE '%unit%'
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', c.tbl, c.conname);
    EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I CHECK (unit IN (''piece'', ''set'', ''job''))', c.tbl, c.conname);
  END LOOP;
END $$;
ALTER TABLE public.online_order_lines DROP CONSTRAINT online_order_lines_quantity_check,
  ADD CONSTRAINT online_order_lines_quantity_check CHECK (quantity BETWEEN 1 AND 10 AND quantity = trunc(quantity));
ALTER TABLE public.stock_movements DROP CONSTRAINT stock_movements_channel_check,
  ADD CONSTRAINT stock_movements_channel_check CHECK (channel IN ('pos', 'web', 'system'));
ALTER TABLE public.stock_movements DROP CONSTRAINT stock_movements_movement_type_check,
  ADD CONSTRAINT stock_movements_movement_type_check CHECK (movement_type IN
    ('opening', 'receive', 'sale', 'return', 'adjust', 'count', 'waste', 'transfer_in', 'transfer_out'));
ALTER TABLE public.stock_reservations DROP CONSTRAINT stock_reservations_channel_check,
  ADD CONSTRAINT stock_reservations_channel_check CHECK (channel IN ('pos', 'web'));
ALTER TABLE public.customer_ledger DROP CONSTRAINT customer_ledger_entry_type_check,
  ADD CONSTRAINT customer_ledger_entry_type_check CHECK (entry_type IN
    ('opening', 'sale_credit', 'return_credit', 'payment', 'adjustment'));
ALTER TABLE public.users DROP CONSTRAINT users_role_check,
  ADD CONSTRAINT users_role_check CHECK (role IN ('admin', 'manager', 'cashier'));

-- History rows about garment forms that no longer exist.
ALTER TABLE public.lookup_events DISABLE TRIGGER lookup_events_immutable;
DELETE FROM public.lookup_events WHERE kind = 'garment_type';
ALTER TABLE public.lookup_events ENABLE TRIGGER lookup_events_immutable;
