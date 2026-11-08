-- =====================================================================
-- Security hardening
-- Applied after 20261019000000_initial_schema.sql (safe to run more than once).
--
-- What it does:
--   * Role helpers backed by the users table (inactive users get nothing)
--   * Role-based row level security on every table
--   * Users can no longer change their own role / active flag
--   * Profiles are created by a trigger on auth.users (first user = admin,
--     everyone else starts inactive until an admin activates them)
--   * Atomic, server-side checkout (process_sale): invoice number, stock,
--     customer credit and the sale row are written in one transaction
--   * Only safe card fields (brand, bank, last 4, holder) are ever stored
-- =====================================================================

-- ---------------------------------------------------------------------
-- Role helpers
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.current_app_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT role FROM public.users WHERE id = auth.uid() AND active = true
$$;

CREATE OR REPLACE FUNCTION public.has_app_role(roles TEXT[])
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(public.current_app_role() = ANY(roles), false)
$$;

CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.current_app_role() IS NOT NULL
$$;

REVOKE ALL ON FUNCTION public.current_app_role() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.has_app_role(TEXT[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_staff() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_app_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_app_role(TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_staff() TO authenticated;

-- ---------------------------------------------------------------------
-- Drop the old permissive policies
-- ---------------------------------------------------------------------
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN
        SELECT policyname, tablename
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN ('app_settings', 'categories', 'customers', 'suppliers', 'products',
                            'product_batches', 'discounts', 'users', 'sales', 'sales_tabs')
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- Policies
--   staff            = any active user
--   admin / manager  = back office
-- ---------------------------------------------------------------------

-- app_settings: everyone reads, back office edits, nobody inserts/deletes from the app
CREATE POLICY "settings_select_staff" ON app_settings
    FOR SELECT TO authenticated USING (public.is_staff());
CREATE POLICY "settings_update_back_office" ON app_settings
    FOR UPDATE TO authenticated
    USING (public.has_app_role(ARRAY['admin', 'manager']))
    WITH CHECK (public.has_app_role(ARRAY['admin', 'manager']));

-- Catalog tables: everyone reads, back office writes
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['categories', 'products', 'product_batches', 'discounts', 'suppliers']
    LOOP
        EXECUTE format(
            'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (public.is_staff())',
            t || '_select_staff', t);
        EXECUTE format(
            'CREATE POLICY %I ON public.%I FOR ALL TO authenticated
                USING (public.has_app_role(ARRAY[''admin'', ''manager'']))
                WITH CHECK (public.has_app_role(ARRAY[''admin'', ''manager'']))',
            t || '_write_back_office', t);
    END LOOP;
END $$;

-- customers: cashiers can look up and add customers; only back office edits/deletes
CREATE POLICY "customers_select_staff" ON customers
    FOR SELECT TO authenticated USING (public.is_staff());
CREATE POLICY "customers_insert_staff" ON customers
    FOR INSERT TO authenticated
    WITH CHECK (public.is_staff() AND COALESCE(credit_used, 0) = 0 AND COALESCE(total_purchases, 0) = 0);
CREATE POLICY "customers_update_back_office" ON customers
    FOR UPDATE TO authenticated
    USING (public.has_app_role(ARRAY['admin', 'manager']))
    WITH CHECK (public.has_app_role(ARRAY['admin', 'manager']));
CREATE POLICY "customers_delete_back_office" ON customers
    FOR DELETE TO authenticated USING (public.has_app_role(ARRAY['admin', 'manager']));

-- users: you see yourself, back office sees everyone, admins manage.
-- No INSERT policy: profiles are created by the auth trigger / admin edge function.
CREATE POLICY "users_select_self_or_back_office" ON users
    FOR SELECT TO authenticated
    USING (id = auth.uid() OR public.has_app_role(ARRAY['admin', 'manager']));
CREATE POLICY "users_update_self_or_admin" ON users
    FOR UPDATE TO authenticated
    USING (id = auth.uid() OR public.has_app_role(ARRAY['admin']))
    WITH CHECK (id = auth.uid() OR public.has_app_role(ARRAY['admin']));
CREATE POLICY "users_delete_admin" ON users
    FOR DELETE TO authenticated
    USING (public.has_app_role(ARRAY['admin']) AND id <> auth.uid());

-- sales: back office sees all, cashiers see their own.
-- No INSERT policy: sales are created only through process_sale().
ALTER TABLE sales ADD COLUMN IF NOT EXISTS cashier_id UUID REFERENCES users(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_sales_cashier_id ON sales(cashier_id);

CREATE POLICY "sales_select_own_or_back_office" ON sales
    FOR SELECT TO authenticated
    USING (public.has_app_role(ARRAY['admin', 'manager']) OR (public.is_staff() AND cashier_id = auth.uid()));
CREATE POLICY "sales_update_back_office" ON sales
    FOR UPDATE TO authenticated
    USING (public.has_app_role(ARRAY['admin', 'manager']))
    WITH CHECK (public.has_app_role(ARRAY['admin', 'manager']));
CREATE POLICY "sales_delete_back_office" ON sales
    FOR DELETE TO authenticated USING (public.has_app_role(ARRAY['admin', 'manager']));

-- sales_tabs: strictly your own
CREATE POLICY "sales_tabs_own" ON sales_tabs
    FOR ALL TO authenticated
    USING (public.is_staff() AND user_id = auth.uid())
    WITH CHECK (public.is_staff() AND user_id = auth.uid());

-- ---------------------------------------------------------------------
-- Protect privileged user columns
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.protect_user_privileged_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- auth.uid() is NULL for the service role / SQL editor: allow those.
    IF auth.uid() IS NOT NULL AND NOT public.has_app_role(ARRAY['admin']) THEN
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.role IS DISTINCT FROM OLD.role
           OR NEW.active IS DISTINCT FROM OLD.active
           OR NEW.permissions IS DISTINCT FROM OLD.permissions
           OR NEW.email IS DISTINCT FROM OLD.email
           OR NEW.username IS DISTINCT FROM OLD.username THEN
            RAISE EXCEPTION 'Only administrators can change role, status, email or username'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- Never leave the store without an active administrator
    IF OLD.role = 'admin' AND OLD.active = true
       AND (NEW.role <> 'admin' OR NEW.active = false)
       AND NOT EXISTS (
           SELECT 1 FROM public.users
           WHERE role = 'admin' AND active = true AND id <> OLD.id
       ) THEN
        RAISE EXCEPTION 'At least one active administrator is required';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_protect_user_privileged_columns ON users;
CREATE TRIGGER trigger_protect_user_privileged_columns
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION public.protect_user_privileged_columns();

-- ---------------------------------------------------------------------
-- Create a profile for every new auth user
--   first user ever -> active admin (bootstraps the store)
--   everyone else   -> inactive cashier until an admin activates them
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    is_first_user BOOLEAN;
    base_username TEXT;
BEGIN
    SELECT NOT EXISTS (SELECT 1 FROM public.users) INTO is_first_user;

    base_username := COALESCE(
        NULLIF(trim(NEW.raw_user_meta_data->>'username'), ''),
        split_part(NEW.email, '@', 1)
    );
    IF EXISTS (SELECT 1 FROM public.users WHERE username = base_username) THEN
        base_username := base_username || '-' || substr(NEW.id::text, 1, 6);
    END IF;

    INSERT INTO public.users (id, username, name, email, role, permissions, active)
    VALUES (
        NEW.id,
        base_username,
        COALESCE(NULLIF(trim(NEW.raw_user_meta_data->>'name'), ''), base_username),
        NEW.email,
        CASE WHEN is_first_user THEN 'admin' ELSE 'cashier' END,
        '{}',
        is_first_user
    )
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_auth_user();

-- ---------------------------------------------------------------------
-- Invoice numbers: row lock so two tills never get the same number
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_invoice_number()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    settings_id UUID;
    prefix TEXT;
    counter INTEGER;
BEGIN
    SELECT id, invoice_prefix, invoice_counter
    INTO settings_id, prefix, counter
    FROM public.app_settings
    ORDER BY created_at
    LIMIT 1
    FOR UPDATE;

    prefix := COALESCE(prefix, 'INV');
    counter := COALESCE(counter, 1000) + 1;

    IF settings_id IS NOT NULL THEN
        UPDATE public.app_settings SET invoice_counter = counter WHERE id = settings_id;
    END IF;

    RETURN prefix || '-' || LPAD(counter::TEXT, 6, '0');
END;
$$;

REVOKE ALL ON FUNCTION public.generate_invoice_number() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- Customer stats: count each sale once (the old trigger also fired on
-- every UPDATE and the app added the total a second time)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_customer_stats()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.customer_id IS NOT NULL AND NEW.status IN ('completed', 'credit') THEN
        UPDATE public.customers
        SET total_purchases = COALESCE(total_purchases, 0) + NEW.total,
            last_purchase = NEW.created_at
        WHERE id = NEW.customer_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_customer_stats ON sales;
CREATE TRIGGER trigger_update_customer_stats
    AFTER INSERT ON sales
    FOR EACH ROW
    EXECUTE FUNCTION public.update_customer_stats();

-- ---------------------------------------------------------------------
-- Strip card data down to fields that are safe to keep (no full PAN)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sanitize_card_details(details JSONB)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN details IS NULL OR jsonb_typeof(details) <> 'object' THEN NULL
        ELSE jsonb_strip_nulls(jsonb_build_object(
            'bankName', left(details->>'bankName', 100),
            'cardType', CASE WHEN details->>'cardType' IN ('visa', 'mastercard', 'amex', 'discover', 'unionpay', 'other')
                             THEN details->>'cardType' ELSE 'other' END,
            'lastFourDigits', NULLIF(right(regexp_replace(COALESCE(details->>'lastFourDigits', ''), '\D', '', 'g'), 4), ''),
            'holderName', left(details->>'holderName', 100)
        ))
    END
$$;

-- Remove any full card numbers already stored
UPDATE sales
SET card_details = public.sanitize_card_details(card_details)
WHERE card_details ? 'cardNumber';

-- ---------------------------------------------------------------------
-- process_sale: the only way to create a sale from the app
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.process_sale(p_sale JSONB)
RETURNS public.sales
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile public.users;
    v_status TEXT;
    v_payment TEXT;
    v_items JSONB;
    v_item JSONB;
    v_product public.products;
    v_product_id UUID;
    v_qty NUMERIC;
    v_weight NUMERIC;
    v_deduct INTEGER;
    v_subtotal NUMERIC := 0;
    v_client_subtotal NUMERIC;
    v_discount NUMERIC;
    v_tax NUMERIC;
    v_total NUMERIC;
    v_customer public.customers;
    v_customer_id UUID;
    v_invoice TEXT;
    v_sale public.sales;
BEGIN
    SELECT * INTO v_profile FROM public.users WHERE id = auth.uid() AND active = true;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;

    v_status := COALESCE(p_sale->>'status', 'completed');
    v_payment := COALESCE(p_sale->>'payment_method', 'cash');
    v_items := COALESCE(p_sale->'items', '[]'::jsonb);
    v_customer_id := NULLIF(p_sale->>'customer_id', '')::UUID;

    IF v_status NOT IN ('completed', 'credit', 'draft') THEN
        RAISE EXCEPTION 'Invalid sale status: %', v_status;
    END IF;
    IF v_payment NOT IN ('cash', 'card', 'digital', 'credit') THEN
        RAISE EXCEPTION 'Invalid payment method: %', v_payment;
    END IF;
    IF jsonb_typeof(v_items) <> 'array' OR jsonb_array_length(v_items) = 0 THEN
        RAISE EXCEPTION 'A sale needs at least one item';
    END IF;

    v_client_subtotal := COALESCE((p_sale->>'subtotal')::NUMERIC, 0);
    v_discount := COALESCE((p_sale->>'discount_amount')::NUMERIC, 0);
    v_tax := COALESCE((p_sale->>'tax_amount')::NUMERIC, 0);
    v_total := COALESCE((p_sale->>'total')::NUMERIC, 0);

    -- Lock products, check prices against the database and (for real sales) deduct stock
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_items)
    LOOP
        v_product_id := (v_item->'product'->>'id')::UUID;
        v_qty := COALESCE((v_item->>'quantity')::NUMERIC, 0);
        v_weight := NULLIF(v_item->>'weight', '')::NUMERIC;

        IF v_qty <= 0 THEN
            RAISE EXCEPTION 'Item quantity must be greater than zero';
        END IF;

        SELECT * INTO v_product FROM public.products WHERE id = v_product_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product not found: %', v_product_id;
        END IF;

        IF COALESCE(v_product.is_weight_based, false) THEN
            v_subtotal := v_subtotal + COALESCE(v_product.price_per_unit, 0) * COALESCE(v_weight, 1) * v_qty;
        ELSE
            v_subtotal := v_subtotal + v_product.price * v_qty;
        END IF;

        IF v_status <> 'draft' AND COALESCE(v_product.track_inventory, true) THEN
            v_deduct := CEIL(COALESCE(v_weight, v_qty))::INTEGER;
            IF COALESCE(v_product.stock, 0) < v_deduct THEN
                RAISE EXCEPTION 'Not enough stock for "%" (available: %, needed: %)',
                    v_product.name, COALESCE(v_product.stock, 0), v_deduct;
            END IF;
            UPDATE public.products SET stock = stock - v_deduct WHERE id = v_product_id;
        END IF;
    END LOOP;

    -- Totals must match the database prices (stops tampered prices)
    IF abs(v_subtotal - v_client_subtotal) > 0.01 THEN
        RAISE EXCEPTION 'Prices have changed since the cart was built. Refresh and try again.';
    END IF;
    IF v_discount < 0 OR v_discount > v_subtotal + 0.01 THEN
        RAISE EXCEPTION 'Discount cannot be more than the subtotal';
    END IF;
    IF v_tax < 0 OR abs((v_subtotal - v_discount + v_tax) - v_total) > 0.01 THEN
        RAISE EXCEPTION 'Sale total does not add up';
    END IF;

    -- Store credit
    IF v_status <> 'draft' AND v_payment = 'credit' THEN
        IF v_customer_id IS NULL THEN
            RAISE EXCEPTION 'Credit sales need a customer';
        END IF;
        SELECT * INTO v_customer FROM public.customers WHERE id = v_customer_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Customer not found';
        END IF;
        IF COALESCE(v_customer.credit_limit, 0) - COALESCE(v_customer.credit_used, 0) < v_total - 0.01 THEN
            RAISE EXCEPTION 'Customer credit limit exceeded';
        END IF;
        UPDATE public.customers SET credit_used = COALESCE(credit_used, 0) + v_total WHERE id = v_customer_id;
    END IF;

    IF v_status = 'draft' THEN
        v_invoice := 'DRAFT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    ELSE
        v_invoice := public.generate_invoice_number();
    END IF;

    INSERT INTO public.sales (
        invoice_number, customer_id, customer_name, items, subtotal, discount_amount,
        tax_amount, total, payment_method, card_details, status, cashier, cashier_id,
        cashier_role, receipt_number, notes, applied_discounts, free_gifts
    ) VALUES (
        v_invoice,
        v_customer_id,
        p_sale->>'customer_name',
        v_items,
        v_subtotal,
        v_discount,
        v_tax,
        v_total,
        v_payment,
        CASE WHEN v_payment = 'card' THEN public.sanitize_card_details(p_sale->'card_details') END,
        v_status,
        v_profile.name,
        v_profile.id,
        v_profile.role,
        v_invoice,
        left(p_sale->>'notes', 1000),
        COALESCE(p_sale->'applied_discounts', '[]'::jsonb),
        COALESCE(p_sale->'free_gifts', '[]'::jsonb)
    )
    RETURNING * INTO v_sale;

    RETURN v_sale;
END;
$$;

REVOKE ALL ON FUNCTION public.process_sale(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_sale(JSONB) TO authenticated;
