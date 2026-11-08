ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS min_tailoring_deposit_percent NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK(min_tailoring_deposit_percent BETWEEN 0 AND 100);
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS receipt_header TEXT CHECK(length(receipt_header)<=500);
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS receipt_footer TEXT CHECK(length(receipt_footer)<=500);
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS ntn TEXT CHECK(length(ntn)<=100);
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS strn TEXT CHECK(length(strn)<=100);
ALTER TABLE public.app_settings ALTER COLUMN currency SET DEFAULT 'PKR';
UPDATE public.app_settings SET currency='PKR' WHERE currency='USD';
ALTER TABLE public.tailoring_orders ADD COLUMN IF NOT EXISTS deposit_waived_by UUID REFERENCES public.users(id);

CREATE TABLE IF NOT EXISTS public.settings_history (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, changed_by UUID DEFAULT auth.uid(),
 changed_at TIMESTAMPTZ NOT NULL DEFAULT now(), old JSONB NOT NULL, new JSONB NOT NULL
);
ALTER TABLE public.settings_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS settings_history_select ON public.settings_history;
CREATE POLICY settings_history_select ON public.settings_history FOR SELECT TO authenticated USING(public.has_app_role(ARRAY['admin','manager']));
DROP TRIGGER IF EXISTS settings_history_append_only ON public.settings_history;
CREATE TRIGGER settings_history_append_only BEFORE UPDATE OR DELETE ON public.settings_history FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();
REVOKE ALL ON public.settings_history FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.settings_history TO authenticated;
REVOKE ALL ON SEQUENCE public.settings_history_id_seq FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.update_settings(p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_old public.app_settings; v_new public.app_settings; v_key TEXT; v_max INT;
 v_request UUID; v_existing JSONB;
 v_keys TEXT[]:=ARRAY['store_name','store_address','store_phone','store_email','store_logo','tax_rate','currency','interface_mode','auto_backup','receipt_printer','theme','invoice_prefix','invoice_counter','max_cashier_discount_percent','return_window_days','cash_variance_alert','min_tailoring_deposit_percent','receipt_header','receipt_footer','ntn','strn'];
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
   IF v_key IN ('tax_rate','max_cashier_discount_percent','return_window_days','cash_variance_alert','min_tailoring_deposit_percent','invoice_counter') THEN
     IF jsonb_typeof(p->v_key) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Enter a number for %',v_key; END IF;
   ELSIF v_key IN ('auto_backup','receipt_printer') THEN
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
 SELECT * INTO v_old FROM public.app_settings ORDER BY created_at,id LIMIT 1 FOR UPDATE;
 IF v_old.id IS NULL THEN RAISE EXCEPTION 'Store settings not found'; END IF;
 v_new:=jsonb_populate_record(v_old,p-'request_id');
 UPDATE public.app_settings SET store_name=v_new.store_name,store_address=v_new.store_address,store_phone=v_new.store_phone,
   store_email=v_new.store_email,store_logo=v_new.store_logo,tax_rate=v_new.tax_rate,currency=v_new.currency,interface_mode=v_new.interface_mode,
   auto_backup=v_new.auto_backup,receipt_printer=v_new.receipt_printer,theme=v_new.theme,invoice_prefix=v_new.invoice_prefix,invoice_counter=v_new.invoice_counter,
   max_cashier_discount_percent=v_new.max_cashier_discount_percent,return_window_days=v_new.return_window_days,cash_variance_alert=v_new.cash_variance_alert,
   min_tailoring_deposit_percent=v_new.min_tailoring_deposit_percent,receipt_header=v_new.receipt_header,receipt_footer=v_new.receipt_footer,ntn=v_new.ntn,strn=v_new.strn
 WHERE id=v_old.id RETURNING * INTO v_new;
 INSERT INTO public.settings_history(old,new) VALUES(to_jsonb(v_old),to_jsonb(v_new));
 RETURN public.idempotency_finish(v_request,to_jsonb(v_new));
END; $$;
DROP POLICY IF EXISTS settings_update_back_office ON public.app_settings;
-- Also remove any legacy permissive UPDATE/ALL policy before exposing the RPC.
DO $$ DECLARE pol RECORD; BEGIN
 FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='app_settings' AND cmd IN ('UPDATE','ALL') LOOP
   EXECUTE format('DROP POLICY %I ON public.app_settings',pol.policyname);
 END LOOP;
END $$;
REVOKE UPDATE ON public.app_settings FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.update_settings(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_settings(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_garment_type(p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_old public.garment_types; v_new public.garment_types; v_field JSONB; v_seen TEXT[]:='{}';
 v_code TEXT; v_original TEXT; v_request UUID; v_existing JSONB;
BEGIN
 IF NOT public.has_app_role(ARRAY['admin','manager']) THEN RAISE EXCEPTION 'Only managers can edit garment types' USING ERRCODE='42501'; END IF;
 v_request:=nullif(p->>'request_id','')::uuid;
 v_existing:=public.idempotency_begin(v_request,'save_garment_type');
 IF v_existing IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=v_request AND user_id=auth.uid()) THEN RAISE EXCEPTION 'Request id belongs to another garment save' USING ERRCODE='42501'; END IF;
   RETURN v_existing;
 END IF;
 v_code:=trim(p->>'code'); v_original:=nullif(p->>'original_code','');
 IF coalesce(v_code,'') !~ '^[A-Z]+(_[A-Z]+)*$' THEN RAISE EXCEPTION 'Use an upper snake case garment code, such as WAISTCOAT'; END IF;
 IF coalesce(trim(p->>'name'),'')='' OR length(p->>'name')>200 THEN RAISE EXCEPTION 'Enter a garment name of at most 200 characters'; END IF;
 IF jsonb_typeof(p->'fields') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Add at least one measurement field'; END IF;
 IF jsonb_array_length(p->'fields')=0 THEN RAISE EXCEPTION 'Add at least one measurement field'; END IF;
 FOR v_field IN SELECT * FROM jsonb_array_elements(p->'fields') LOOP
   IF jsonb_typeof(v_field) IS DISTINCT FROM 'object' OR jsonb_typeof(v_field->'key') IS DISTINCT FROM 'string' OR coalesce(v_field->>'key','') !~ '^[a-z_]+$' THEN RAISE EXCEPTION 'Measurement keys use lowercase letters and underscores only'; END IF;
   IF v_field->>'key'=ANY(v_seen) THEN RAISE EXCEPTION 'Measurement key % is listed twice',v_field->>'key'; END IF;
   v_seen:=array_append(v_seen,v_field->>'key');
   IF jsonb_typeof(v_field->'label') IS DISTINCT FROM 'string' OR coalesce(trim(v_field->>'label'),'')='' OR length(v_field->>'label')>100 THEN RAISE EXCEPTION 'Give every measurement a label of at most 100 characters'; END IF;
   IF v_field ? 'required' AND jsonb_typeof(v_field->'required') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Choose required or optional for each measurement'; END IF;
 END LOOP;
 SELECT * INTO v_old FROM public.garment_types WHERE code=coalesce(v_original,v_code) FOR UPDATE;
 IF v_original IS NOT NULL AND v_old.code IS NULL THEN RAISE EXCEPTION 'Garment type not found'; END IF;
 IF v_old.code IS NOT NULL AND v_code<>v_old.code AND
    (EXISTS(SELECT 1 FROM public.tailoring_items WHERE garment_type=v_old.code) OR EXISTS(SELECT 1 FROM public.measurement_sets WHERE garment_type=v_old.code)) THEN
   RAISE EXCEPTION 'This garment code has measurement or order history and cannot be changed';
 END IF;
 IF p ? 'lead_days' AND (jsonb_typeof(p->'lead_days') IS DISTINCT FROM 'number' OR (p->>'lead_days')::numeric<>trunc((p->>'lead_days')::numeric)) THEN RAISE EXCEPTION 'Lead days must be a whole number of zero or more'; END IF;
 IF p ? 'sort_order' AND (jsonb_typeof(p->'sort_order') IS DISTINCT FROM 'number' OR (p->>'sort_order')::numeric<>trunc((p->>'sort_order')::numeric)) THEN RAISE EXCEPTION 'Sort order must be a whole number'; END IF;
 IF p ? 'active' AND jsonb_typeof(p->'active') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Choose active or inactive'; END IF;
 v_new:=jsonb_populate_record(NULL::public.garment_types,p);
 v_new.default_charge:=coalesce(v_new.default_charge,0); v_new.lead_days:=coalesce(v_new.lead_days,7);
 v_new.active:=coalesce(v_new.active,true); v_new.sort_order:=coalesce(v_new.sort_order,0);
 IF v_new.default_charge<0 OR v_new.default_charge::text='NaN' OR v_new.lead_days<0 OR v_new.fabric_meters<0 OR v_new.fabric_meters::text='NaN' THEN RAISE EXCEPTION 'Charges, lead days and fabric meters must be zero or more'; END IF;
 IF v_old.code IS NULL THEN
   INSERT INTO public.garment_types VALUES(v_code,trim(v_new.name),v_new.fields,v_new.default_charge,v_new.lead_days,v_new.fabric_meters,v_new.active,v_new.sort_order) RETURNING * INTO v_new;
 ELSE
   UPDATE public.garment_types SET code=v_code,name=trim(v_new.name),fields=v_new.fields,default_charge=v_new.default_charge,
     lead_days=v_new.lead_days,fabric_meters=v_new.fabric_meters,active=v_new.active,sort_order=v_new.sort_order WHERE code=v_old.code RETURNING * INTO v_new;
 END IF;
 RETURN public.idempotency_finish(v_request,to_jsonb(v_new));
END; $$;
DROP POLICY IF EXISTS garment_types_write ON public.garment_types;
REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON public.garment_types FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.save_garment_type(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_garment_type(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.check_tailoring_deposit(p_order_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_percent NUMERIC; v_totals JSONB; v_required NUMERIC;
BEGIN
 IF EXISTS(SELECT 1 FROM public.tailoring_orders WHERE id=p_order_id AND deposit_waived_by IS NOT NULL) THEN RETURN; END IF;
 SELECT min_tailoring_deposit_percent INTO v_percent FROM public.app_settings ORDER BY created_at,id LIMIT 1;
 IF coalesce(v_percent,0)<=0 THEN RETURN; END IF;
 v_totals:=public.tailoring_order_totals(p_order_id);
 v_required:=round((v_totals->>'total')::numeric*v_percent/100,2);
 IF (v_totals->>'paid')::numeric<v_required THEN
   RAISE EXCEPTION 'A deposit of at least % (PKR %) is required',trim_scale(v_percent)::text||'%',v_required;
 END IF;
END; $$;
REVOKE ALL ON FUNCTION public.check_tailoring_deposit(UUID) FROM PUBLIC,anon,authenticated;

-- Latest order bodies; retain all existing price, measurement and stock rules.
CREATE OR REPLACE FUNCTION public.create_tailoring_order(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_request_id UUID := NULLIF(p->>'request_id', '')::uuid;
    v_existing JSONB;
    v_status TEXT := COALESCE(NULLIF(p->>'status', ''), 'confirmed');
    v_location public.locations;
    v_customer public.customers;
    v_order public.tailoring_orders;
    v_item_req JSONB;
    v_item public.tailoring_items;
    v_line_no INTEGER := 0;
    v_wearer UUID;
    v_set public.measurement_sets;
    v_garment public.garment_types;
    v_charge JSONB;
    v_mat JSONB;
    v_material public.tailoring_materials;
    v_variant RECORD;
    v_charge_row public.tailoring_charges;
    v_qty NUMERIC;
    v_stitching NUMERIC;
    v_totals JSONB;
BEGIN
    IF NOT public.is_counter_staff() THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'request_id is required';
    END IF;
    IF v_status NOT IN ('draft', 'confirmed') THEN
        RAISE EXCEPTION 'New orders are draft or confirmed';
    END IF;

    v_existing := public.idempotency_begin(v_request_id, 'create_tailoring_order');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    IF coalesce((p->>'waive_deposit')::boolean,false) AND NOT public.has_app_role(ARRAY['admin','manager']) THEN
        RAISE EXCEPTION 'Only managers can waive the minimum deposit' USING ERRCODE='42501';
    END IF;
    SELECT * INTO v_customer FROM public.customers WHERE id = NULLIF(p->>'customer_id', '')::uuid;
    IF v_customer.id IS NULL THEN
        RAISE EXCEPTION 'Choose the customer';
    END IF;
    IF jsonb_typeof(p->'items') <> 'array' OR jsonb_array_length(p->'items') = 0 THEN
        RAISE EXCEPTION 'Add at least one garment';
    END IF;

    SELECT * INTO v_location FROM public.locations
    WHERE branch_id = public.default_branch_id() AND kind = 'shop_floor' AND active ORDER BY created_at LIMIT 1;
    IF NOT public.is_branch_member(v_location.branch_id) THEN
        RAISE EXCEPTION 'Not a member of this branch' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.tailoring_orders (order_no, request_id, branch_id, location_id, customer_id, status,
                                         promised_date, fitting_date, notes, confirmed_at)
    VALUES ('TLR-' || lpad(nextval('public.tailoring_order_no_seq')::text, 6, '0'), v_request_id,
            v_location.branch_id, v_location.id, v_customer.id, v_status,
            NULLIF(p->>'promised_date', '')::date, NULLIF(p->>'fitting_date', '')::date,
            NULLIF(trim(p->>'notes'), ''), CASE WHEN v_status = 'confirmed' THEN now() END)
    RETURNING * INTO v_order;
    IF coalesce((p->>'waive_deposit')::boolean,false) THEN
        UPDATE public.tailoring_orders SET deposit_waived_by=auth.uid() WHERE id=v_order.id;
    END IF;

    FOR v_item_req IN SELECT * FROM jsonb_array_elements(p->'items')
    LOOP
        v_line_no := v_line_no + 1;

        SELECT * INTO v_garment FROM public.garment_types WHERE code = v_item_req->>'garment_type' AND active;
        IF v_garment.code IS NULL THEN
            RAISE EXCEPTION 'Unknown garment type: %', v_item_req->>'garment_type';
        END IF;

        -- Wearer: existing (must belong to the customer) or new
        v_wearer := NULLIF(v_item_req->>'wearer_id', '')::uuid;
        IF v_wearer IS NULL THEN
            INSERT INTO public.wearer_profiles (customer_id, name, relation)
            VALUES (v_customer.id, COALESCE(NULLIF(trim(v_item_req->'wearer'->>'name'), ''), v_customer.name),
                    NULLIF(trim(v_item_req->'wearer'->>'relation'), ''))
            RETURNING id INTO v_wearer;
        ELSIF NOT EXISTS (SELECT 1 FROM public.wearer_profiles WHERE id = v_wearer AND customer_id = v_customer.id) THEN
            RAISE EXCEPTION 'That wearer belongs to another customer';
        END IF;

        -- Measurements: an existing set of this wearer, or a new one
        v_set := NULL;
        IF NULLIF(v_item_req->>'measurement_set_id', '') IS NOT NULL THEN
            SELECT * INTO v_set FROM public.measurement_sets
            WHERE id = (v_item_req->>'measurement_set_id')::uuid AND wearer_id = v_wearer;
            IF v_set.id IS NULL THEN
                RAISE EXCEPTION 'Those measurements belong to someone else';
            END IF;
        ELSIF jsonb_typeof(v_item_req->'measurements'->'values') = 'object' THEN
            INSERT INTO public.measurement_sets (wearer_id, garment_type, measurements, fit_preference, notes)
            VALUES (v_wearer, v_garment.code, v_item_req->'measurements'->'values',
                    NULLIF(v_item_req->'measurements'->>'fit_preference', ''), NULLIF(trim(v_item_req->'measurements'->>'notes'), ''))
            RETURNING * INTO v_set;
        END IF;

        INSERT INTO public.tailoring_items (order_id, line_no, garment_type, wearer_id, measurement_set_id,
                                            measurements_snapshot, fit_preference, design_notes, due_date)
        VALUES (v_order.id, v_line_no, v_garment.code, v_wearer, v_set.id, COALESCE(v_set.measurements, '{}'::jsonb),
                v_set.fit_preference, NULLIF(trim(v_item_req->>'design_notes'), ''),
                COALESCE(NULLIF(p->>'promised_date', '')::date, current_date + v_garment.lead_days))
        RETURNING * INTO v_item;

        -- Stitching charge (default from the garment type)
        v_stitching := COALESCE(NULLIF(v_item_req->>'stitching_charge', '')::numeric, v_garment.default_charge);
        IF v_stitching < 0 THEN
            RAISE EXCEPTION 'Charges cannot be negative';
        END IF;
        INSERT INTO public.tailoring_charges (order_id, item_id, kind, description, amount)
        VALUES (v_order.id, v_item.id, CASE WHEN v_garment.code = 'ALTERATION' THEN 'alteration' ELSE 'stitching' END,
                v_garment.name || ' stitching', round(v_stitching, 2));

        FOR v_charge IN SELECT * FROM jsonb_array_elements(COALESCE(v_item_req->'charges', '[]'::jsonb))
        LOOP
            IF COALESCE(NULLIF(v_charge->>'amount', '')::numeric, -1) < 0 THEN
                RAISE EXCEPTION 'Charges cannot be negative';
            END IF;
            INSERT INTO public.tailoring_charges (order_id, item_id, kind, description, amount)
            VALUES (v_order.id, v_item.id, COALESCE(NULLIF(v_charge->>'kind', ''), 'other'),
                    COALESCE(NULLIF(trim(v_charge->>'description'), ''), initcap(v_charge->>'kind')),
                    round((v_charge->>'amount')::numeric, 2));
        END LOOP;

        -- Materials
        FOR v_mat IN SELECT * FROM jsonb_array_elements(COALESCE(v_item_req->'materials', '[]'::jsonb))
        LOOP
            v_qty := NULLIF(v_mat->>'quantity', '')::numeric;
            IF v_qty IS NULL OR v_qty <= 0 OR v_qty <> round(v_qty, 2) THEN
                RAISE EXCEPTION 'Enter the fabric length (up to 2 decimals)';
            END IF;

            IF v_mat->>'source' = 'store' THEN
                SELECT v.id, v.price, s.unit,
                       trim(s.name || COALESCE(' ' || v.color, '') || COALESCE(' ' || v.size, '')) AS description
                INTO v_variant
                FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id
                WHERE v.id = NULLIF(v_mat->>'variant_id', '')::uuid AND v.active AND s.active;
                IF v_variant.id IS NULL OR v_variant.unit <> 'meter' THEN
                    RAISE EXCEPTION 'Choose a fabric from stock';
                END IF;

                v_charge_row := NULL;
                IF COALESCE((v_mat->>'charge')::boolean, true) THEN
                    INSERT INTO public.tailoring_charges (order_id, item_id, kind, description, amount)
                    VALUES (v_order.id, v_item.id, 'fabric',
                            v_variant.description || ' ' || trim_scale(v_qty) || ' m', round(v_variant.price * v_qty, 2))
                    RETURNING * INTO v_charge_row;
                END IF;

                INSERT INTO public.tailoring_materials (order_id, item_id, source, variant_id, roll_id, description,
                                                        quantity, unit, status, charge_id)
                VALUES (v_order.id, v_item.id, 'store', v_variant.id, NULLIF(v_mat->>'roll_id', '')::uuid,
                        v_variant.description, v_qty, 'meter', 'planned', v_charge_row.id)
                RETURNING * INTO v_material;
            ELSIF v_mat->>'source' = 'customer' THEN
                INSERT INTO public.tailoring_materials (order_id, item_id, source, description, quantity, unit, status, notes)
                VALUES (v_order.id, v_item.id, 'customer',
                        COALESCE(NULLIF(trim(v_mat->>'description'), ''), 'Customer fabric'), v_qty,
                        COALESCE(NULLIF(v_mat->>'unit', ''), 'meter'), 'received', NULLIF(trim(v_mat->>'notes'), ''))
                RETURNING * INTO v_material;
                INSERT INTO public.material_custody_events (material_id, event, quantity, note)
                VALUES (v_material.id, 'received', v_qty, 'Received from customer');
            ELSE
                RAISE EXCEPTION 'Fabric source must be store or customer';
            END IF;
        END LOOP;
    END LOOP;

    -- Order-level charges
    FOR v_charge IN SELECT * FROM jsonb_array_elements(COALESCE(p->'charges', '[]'::jsonb))
    LOOP
        IF COALESCE(NULLIF(v_charge->>'amount', '')::numeric, -1) < 0 THEN
            RAISE EXCEPTION 'Charges cannot be negative';
        END IF;
        INSERT INTO public.tailoring_charges (order_id, kind, description, amount)
        VALUES (v_order.id, COALESCE(NULLIF(v_charge->>'kind', ''), 'other'),
                COALESCE(NULLIF(trim(v_charge->>'description'), ''), 'Other'), round((v_charge->>'amount')::numeric, 2));
    END LOOP;

    -- Deposit
    IF jsonb_typeof(p->'payments') = 'array' AND jsonb_array_length(p->'payments') > 0 THEN
        IF v_status = 'draft' THEN
            RAISE EXCEPTION 'Confirm the order before taking a deposit';
        END IF;
        PERFORM public.record_tailoring_payments(v_order.id, p->'payments', 'in');
        v_totals := public.tailoring_order_totals(v_order.id);
        IF (v_totals->>'balance')::numeric < 0 THEN
            RAISE EXCEPTION 'The deposit is more than the order total';
        END IF;
    END IF;

    -- The full deposit must be posted before confirmation validates it.
    IF v_status = 'confirmed' THEN
        PERFORM public.confirm_tailoring_order_internal(v_order.id);
    END IF;
    RETURN public.idempotency_finish(v_request_id, public.tailoring_order_summary(v_order.id));
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_tailoring_order_internal(p_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order public.tailoring_orders;
    v_item RECORD;
    v_missing TEXT[];
    v_mat public.tailoring_materials;
    v_res public.stock_reservations;
BEGIN
    SELECT * INTO v_order FROM public.tailoring_orders WHERE id = p_order_id FOR UPDATE;

    PERFORM public.check_tailoring_deposit(p_order_id);

    FOR v_item IN SELECT i.*, g.name AS garment_name, w.name AS wearer_name
                  FROM public.tailoring_items i
                  JOIN public.garment_types g ON g.code = i.garment_type
                  JOIN public.wearer_profiles w ON w.id = i.wearer_id
                  WHERE i.order_id = p_order_id ORDER BY i.line_no
    LOOP
        v_missing := public.missing_measurements(v_item.garment_type, v_item.measurements_snapshot);
        IF cardinality(v_missing) > 0 THEN
            RAISE EXCEPTION '% for %: missing %', v_item.garment_name, v_item.wearer_name, array_to_string(v_missing, ', ');
        END IF;
    END LOOP;

    FOR v_mat IN
        SELECT * FROM public.tailoring_materials
        WHERE order_id = p_order_id AND source = 'store' AND status = 'planned'
        ORDER BY variant_id, id
    LOOP
        v_res := public.reserve_roll_length(v_mat.variant_id, v_order.location_id, v_mat.quantity, v_mat.roll_id,
                                            'tailoring_order', p_order_id);
        UPDATE public.tailoring_materials SET status = 'reserved', reservation_id = v_res.id, roll_id = v_res.roll_id
        WHERE id = v_mat.id;
        INSERT INTO public.material_custody_events (material_id, event, quantity, note)
        VALUES (v_mat.id, 'reserved', v_mat.quantity, 'Reserved on roll');
    END LOOP;

    UPDATE public.tailoring_orders SET status = 'confirmed', confirmed_at = COALESCE(confirmed_at, now())
    WHERE id = p_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_tailoring_order(p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order public.tailoring_orders;
BEGIN
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
$$;

-- Keep the existing one-argument entry point. This overload can take a deposit
-- and/or a manager waiver while confirming a draft, all in one transaction.
CREATE OR REPLACE FUNCTION public.confirm_tailoring_order(p_order_id UUID,p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_order public.tailoring_orders; v_request UUID; v_existing JSONB; v_totals JSONB;
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) THEN RAISE EXCEPTION 'Only counter staff can confirm orders' USING ERRCODE='42501'; END IF;
 v_request:=nullif(p->>'request_id','')::uuid;
 v_existing:=public.idempotency_begin(v_request,'confirm_tailoring_order');
 IF v_existing IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=v_request AND user_id=auth.uid()) OR v_existing->>'id' IS DISTINCT FROM p_order_id::text THEN
     RAISE EXCEPTION 'Request id belongs to another confirmation' USING ERRCODE='42501'; END IF;
   RETURN v_existing;
 END IF;
 IF coalesce((p->>'waive_deposit')::boolean,false) AND NOT public.has_app_role(ARRAY['admin','manager']) THEN RAISE EXCEPTION 'Only managers can waive the minimum deposit' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_order FROM public.tailoring_orders WHERE id=p_order_id FOR UPDATE;
 IF v_order.id IS NULL OR NOT public.is_branch_member(v_order.branch_id) THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501'; END IF;
 IF v_order.status<>'draft' THEN RETURN public.idempotency_finish(v_request,public.tailoring_order_summary(p_order_id)); END IF;
 IF coalesce((p->>'waive_deposit')::boolean,false) THEN UPDATE public.tailoring_orders SET deposit_waived_by=auth.uid() WHERE id=p_order_id; END IF;
 IF jsonb_typeof(p->'payments')='array' AND jsonb_array_length(p->'payments')>0 THEN
   PERFORM public.record_tailoring_payments(p_order_id,p->'payments','in');
   v_totals:=public.tailoring_order_totals(p_order_id);
   IF (v_totals->>'balance')::numeric<0 THEN RAISE EXCEPTION 'The deposit is more than the order total'; END IF;
 END IF;
 PERFORM public.confirm_tailoring_order_internal(p_order_id);
 RETURN public.idempotency_finish(v_request,public.tailoring_order_summary(p_order_id));
END; $$;
REVOKE ALL ON FUNCTION public.confirm_tailoring_order_internal(UUID) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.create_tailoring_order(JSONB),public.confirm_tailoring_order(UUID),public.confirm_tailoring_order(UUID,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_tailoring_order(JSONB),public.confirm_tailoring_order(UUID),public.confirm_tailoring_order(UUID,JSONB) TO authenticated;
