-- Discount codes
--
--   * Welcome codes: when switched on, every new customer gets one personal,
--     one-time code. The owner chooses the discount (percent or amount), how
--     long it lasts and an optional minimum spend; changes apply to new codes.
--   * Staff codes: managers create any code (e.g. EID14) with their own value,
--     validity, number of uses and, optionally, one customer.
--   * quote_sale() checks the code and adds it as one more promotion, so tax,
--     receipts and reports keep working. A code is used up only when a sale is
--     saved (not on drafts), under a row lock so two tills cannot both use it.
--   * Returning items does not give the code back.

-- ---------------------------------------------------------------------
-- Settings (one row)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.discount_code_settings (
    id BOOLEAN PRIMARY KEY DEFAULT true CHECK (id),
    welcome_enabled BOOLEAN NOT NULL DEFAULT false,
    welcome_type TEXT NOT NULL DEFAULT 'percentage' CHECK (welcome_type IN ('percentage', 'fixed')),
    welcome_value NUMERIC(14,2) NOT NULL DEFAULT 10 CHECK (welcome_value > 0),
    welcome_valid_days INTEGER NOT NULL DEFAULT 30 CHECK (welcome_valid_days BETWEEN 1 AND 3650),
    welcome_min_amount NUMERIC(14,2) CHECK (welcome_min_amount >= 0),
    welcome_max_discount NUMERIC(14,2) CHECK (welcome_max_discount > 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by UUID REFERENCES auth.users(id),
    CONSTRAINT discount_code_settings_percent CHECK (welcome_type <> 'percentage' OR welcome_value <= 100)
);
INSERT INTO public.discount_code_settings (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------
-- Codes and redemptions
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.discount_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE CHECK (code ~ '^[A-Z0-9-]{4,24}$'),
    kind TEXT NOT NULL CHECK (kind IN ('welcome', 'manual')),
    description TEXT,
    customer_id UUID REFERENCES public.customers(id) ON DELETE CASCADE,
    discount_type TEXT NOT NULL CHECK (discount_type IN ('percentage', 'fixed')),
    value NUMERIC(14,2) NOT NULL CHECK (value > 0),
    min_amount NUMERIC(14,2) CHECK (min_amount >= 0),
    max_discount NUMERIC(14,2) CHECK (max_discount > 0),
    valid_from TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ,
    max_uses INTEGER CHECK (max_uses > 0),          -- NULL: unlimited
    used_count INTEGER NOT NULL DEFAULT 0 CHECK (used_count >= 0),
    active BOOLEAN NOT NULL DEFAULT true,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT discount_codes_percent CHECK (discount_type <> 'percentage' OR value <= 100),
    CONSTRAINT discount_codes_dates CHECK (expires_at IS NULL OR expires_at > valid_from),
    CONSTRAINT discount_codes_welcome_customer CHECK (kind <> 'welcome' OR (customer_id IS NOT NULL AND max_uses = 1))
);
CREATE UNIQUE INDEX IF NOT EXISTS discount_codes_one_welcome ON public.discount_codes(customer_id) WHERE kind = 'welcome';
CREATE INDEX IF NOT EXISTS discount_codes_customer ON public.discount_codes(customer_id);

-- Keeps the code text so history survives a deleted customer (whose codes go with them).
-- Written only by the sales trigger below; there are no write policies.
CREATE TABLE IF NOT EXISTS public.discount_code_redemptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code_id UUID REFERENCES public.discount_codes(id) ON DELETE SET NULL,
    code TEXT NOT NULL,
    sale_id UUID NOT NULL UNIQUE REFERENCES public.sales(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    amount NUMERIC(14,2) NOT NULL CHECK (amount >= 0),
    redeemed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS discount_code_redemptions_code ON public.discount_code_redemptions(code_id);

DROP TRIGGER IF EXISTS update_discount_codes_updated_at ON public.discount_codes;
CREATE TRIGGER update_discount_codes_updated_at BEFORE UPDATE ON public.discount_codes
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.discount_code_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discount_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discount_code_redemptions ENABLE ROW LEVEL SECURITY;

-- Managers see everything; cashiers look up one customer's codes through customer_discount_codes()
DROP POLICY IF EXISTS discount_code_settings_read ON public.discount_code_settings;
CREATE POLICY discount_code_settings_read ON public.discount_code_settings FOR SELECT TO authenticated
    USING (public.has_app_role(ARRAY['admin', 'manager']));
DROP POLICY IF EXISTS discount_codes_read ON public.discount_codes;
CREATE POLICY discount_codes_read ON public.discount_codes FOR SELECT TO authenticated
    USING (public.has_app_role(ARRAY['admin', 'manager']));
DROP POLICY IF EXISTS discount_code_redemptions_read ON public.discount_code_redemptions;
CREATE POLICY discount_code_redemptions_read ON public.discount_code_redemptions FOR SELECT TO authenticated
    USING (public.has_app_role(ARRAY['admin', 'manager']));

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.normalize_discount_code(p_code TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
    SELECT NULLIF(upper(regexp_replace(COALESCE(p_code, ''), '\s', '', 'g')), '')
$$;

-- A new random code such as LV-7KQ2XH (no 0/O or 1/I to avoid misreading)
CREATE OR REPLACE FUNCTION public.new_discount_code()
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
SET search_path = public
AS $$
DECLARE
    v_alphabet CONSTANT TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    v_bytes BYTEA;
    v_code TEXT;
    v_i INTEGER;
BEGIN
    LOOP
        v_bytes := uuid_send(gen_random_uuid());
        v_code := 'LV-';
        FOR v_i IN 0 .. 5 LOOP
            v_code := v_code || substr(v_alphabet, get_byte(v_bytes, v_i) % 32 + 1, 1);
        END LOOP;
        EXIT WHEN NOT EXISTS (SELECT 1 FROM public.discount_codes WHERE code = v_code);
    END LOOP;
    RETURN v_code;
END;
$$;

-- Issues the customer's welcome code from the current settings. Returns NULL
-- when welcome codes are off or the customer already has one.
CREATE OR REPLACE FUNCTION public.issue_welcome_code(p_customer_id UUID)
RETURNS public.discount_codes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_settings public.discount_code_settings;
    v_code public.discount_codes;
BEGIN
    SELECT * INTO v_settings FROM public.discount_code_settings WHERE id;
    IF NOT COALESCE(v_settings.welcome_enabled, false) THEN
        RETURN NULL;
    END IF;
    INSERT INTO public.discount_codes (code, kind, description, customer_id, discount_type, value,
                                       min_amount, max_discount, expires_at, max_uses, created_by)
    VALUES (public.new_discount_code(), 'welcome', 'Welcome code', p_customer_id, v_settings.welcome_type,
            v_settings.welcome_value, v_settings.welcome_min_amount, v_settings.welcome_max_discount,
            now() + make_interval(days => v_settings.welcome_valid_days), 1, auth.uid())
    ON CONFLICT (customer_id) WHERE kind = 'welcome' DO NOTHING
    RETURNING * INTO v_code;
    RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.issue_welcome_code_for_new_customer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.issue_welcome_code(NEW.id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS customers_welcome_code ON public.customers;
CREATE TRIGGER customers_welcome_code AFTER INSERT ON public.customers
    FOR EACH ROW EXECUTE FUNCTION public.issue_welcome_code_for_new_customer();

-- How the code looks to staff: the code itself, what it gives and whether it can be used now
CREATE OR REPLACE FUNCTION public.discount_code_json(p_code public.discount_codes)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'id', p_code.id, 'code', p_code.code, 'kind', p_code.kind, 'description', p_code.description,
        'customer_id', p_code.customer_id, 'discount_type', p_code.discount_type, 'value', p_code.value,
        'min_amount', p_code.min_amount, 'max_discount', p_code.max_discount,
        'valid_from', p_code.valid_from, 'expires_at', p_code.expires_at,
        'max_uses', p_code.max_uses, 'used_count', p_code.used_count, 'active', p_code.active,
        'status', CASE
            WHEN NOT p_code.active THEN 'off'
            WHEN p_code.max_uses IS NOT NULL AND p_code.used_count >= p_code.max_uses THEN 'used'
            WHEN p_code.expires_at IS NOT NULL AND p_code.expires_at <= now() THEN 'expired'
            WHEN p_code.valid_from > now() THEN 'scheduled'
            ELSE 'ready' END)
$$;

-- ---------------------------------------------------------------------
-- Staff functions
-- ---------------------------------------------------------------------
-- A customer's codes, for the till (cashiers cannot browse all codes)
CREATE OR REPLACE FUNCTION public.customer_discount_codes(p_customer_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT COALESCE(public.is_counter_staff(), false) THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
    RETURN COALESCE((SELECT jsonb_agg(public.discount_code_json(c) ORDER BY c.created_at DESC)
                     FROM public.discount_codes c WHERE c.customer_id = p_customer_id), '[]'::jsonb);
END;
$$;

-- Gives an existing customer a welcome code (new customers get one automatically)
CREATE OR REPLACE FUNCTION public.issue_customer_welcome_code(p_customer_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_code public.discount_codes;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can issue welcome codes' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.customers WHERE id = p_customer_id) THEN
        RAISE EXCEPTION 'Customer not found';
    END IF;
    IF NOT (SELECT welcome_enabled FROM public.discount_code_settings WHERE id) THEN
        RAISE EXCEPTION 'Switch on welcome codes in Discounts first';
    END IF;
    v_code := public.issue_welcome_code(p_customer_id);
    IF v_code.id IS NULL THEN
        RAISE EXCEPTION 'This customer already has a welcome code';
    END IF;
    RETURN public.discount_code_json(v_code);
END;
$$;

CREATE OR REPLACE FUNCTION public.save_discount_code_settings(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_row public.discount_code_settings;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can change discount code settings' USING ERRCODE = '42501';
    END IF;
    IF COALESCE(p->>'welcome_type', 'percentage') NOT IN ('percentage', 'fixed') THEN
        RAISE EXCEPTION 'Choose percent or amount';
    END IF;
    IF COALESCE((p->>'welcome_value')::numeric, 0) <= 0 THEN
        RAISE EXCEPTION 'Enter a discount greater than zero';
    END IF;
    IF COALESCE(p->>'welcome_type', 'percentage') = 'percentage' AND (p->>'welcome_value')::numeric > 100 THEN
        RAISE EXCEPTION 'A percent discount cannot be more than 100';
    END IF;
    IF COALESCE((p->>'welcome_valid_days')::int, 0) NOT BETWEEN 1 AND 3650 THEN
        RAISE EXCEPTION 'Codes must last between 1 and 3650 days';
    END IF;

    UPDATE public.discount_code_settings SET
        welcome_enabled = COALESCE((p->>'welcome_enabled')::boolean, false),
        welcome_type = COALESCE(p->>'welcome_type', 'percentage'),
        welcome_value = round((p->>'welcome_value')::numeric, 2),
        welcome_valid_days = (p->>'welcome_valid_days')::int,
        welcome_min_amount = NULLIF((p->>'welcome_min_amount')::numeric, 0),
        welcome_max_discount = NULLIF((p->>'welcome_max_discount')::numeric, 0),
        updated_at = now(),
        updated_by = auth.uid()
    WHERE id
    RETURNING * INTO v_row;
    RETURN to_jsonb(v_row);
END;
$$;

-- Creates (no id) or changes (id) a code. The code text cannot change once used.
CREATE OR REPLACE FUNCTION public.save_discount_code(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID := NULLIF(p->>'id', '')::uuid;
    v_old public.discount_codes;
    v_code TEXT := public.normalize_discount_code(p->>'code');
    v_type TEXT := COALESCE(NULLIF(p->>'discount_type', ''), 'percentage');
    v_value NUMERIC := (p->>'value')::numeric;
    v_customer UUID := NULLIF(p->>'customer_id', '')::uuid;
    v_from TIMESTAMPTZ := COALESCE(NULLIF(p->>'valid_from', '')::timestamptz, now());
    v_to TIMESTAMPTZ := NULLIF(p->>'expires_at', '')::timestamptz;
    v_uses INTEGER := NULLIF(p->>'max_uses', '')::int;
    v_row public.discount_codes;
BEGIN
    IF NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        RAISE EXCEPTION 'Only managers can create discount codes' USING ERRCODE = '42501';
    END IF;
    IF v_type NOT IN ('percentage', 'fixed') THEN
        RAISE EXCEPTION 'Choose percent or amount';
    END IF;
    IF v_value IS NULL OR v_value <= 0 THEN
        RAISE EXCEPTION 'Enter a discount greater than zero';
    END IF;
    IF v_type = 'percentage' AND v_value > 100 THEN
        RAISE EXCEPTION 'A percent discount cannot be more than 100';
    END IF;
    IF v_to IS NOT NULL AND v_to <= v_from THEN
        RAISE EXCEPTION 'The end date must be after the start date';
    END IF;
    IF v_uses IS NOT NULL AND v_uses < 1 THEN
        RAISE EXCEPTION 'Number of uses must be at least 1, or leave it empty for unlimited';
    END IF;
    IF v_code IS NOT NULL AND v_code !~ '^[A-Z0-9-]{4,24}$' THEN
        RAISE EXCEPTION 'A code is 4 to 24 letters, numbers or dashes';
    END IF;
    IF v_customer IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.customers WHERE id = v_customer) THEN
        RAISE EXCEPTION 'Customer not found';
    END IF;

    IF v_id IS NULL THEN
        v_code := COALESCE(v_code, public.new_discount_code());
        IF EXISTS (SELECT 1 FROM public.discount_codes WHERE code = v_code) THEN
            RAISE EXCEPTION 'The code % already exists. Choose another.', v_code;
        END IF;
        INSERT INTO public.discount_codes (code, kind, description, customer_id, discount_type, value,
                                           min_amount, max_discount, valid_from, expires_at, max_uses,
                                           active, created_by)
        VALUES (v_code, 'manual', NULLIF(trim(p->>'description'), ''), v_customer, v_type, round(v_value, 2),
                NULLIF((p->>'min_amount')::numeric, 0), NULLIF((p->>'max_discount')::numeric, 0),
                v_from, v_to, v_uses, COALESCE((p->>'active')::boolean, true), auth.uid())
        RETURNING * INTO v_row;
    ELSE
        SELECT * INTO v_old FROM public.discount_codes WHERE id = v_id FOR UPDATE;
        IF v_old.id IS NULL THEN
            RAISE EXCEPTION 'Discount code not found';
        END IF;
        v_code := COALESCE(v_code, v_old.code);
        IF v_code <> v_old.code AND v_old.used_count > 0 THEN
            RAISE EXCEPTION 'This code has been used, so its text cannot change';
        END IF;
        IF v_code <> v_old.code AND EXISTS (SELECT 1 FROM public.discount_codes WHERE code = v_code) THEN
            RAISE EXCEPTION 'The code % already exists. Choose another.', v_code;
        END IF;
        IF v_uses IS NOT NULL AND v_uses < v_old.used_count THEN
            RAISE EXCEPTION 'This code has already been used % times', v_old.used_count;
        END IF;
        IF v_old.kind = 'welcome' AND (v_customer IS DISTINCT FROM v_old.customer_id OR v_uses IS DISTINCT FROM 1) THEN
            RAISE EXCEPTION 'A welcome code stays with its customer and can be used once';
        END IF;
        UPDATE public.discount_codes SET
            code = v_code, description = NULLIF(trim(p->>'description'), ''), customer_id = v_customer,
            discount_type = v_type, value = round(v_value, 2),
            min_amount = NULLIF((p->>'min_amount')::numeric, 0), max_discount = NULLIF((p->>'max_discount')::numeric, 0),
            valid_from = v_from, expires_at = v_to, max_uses = v_uses,
            active = COALESCE((p->>'active')::boolean, v_old.active)
        WHERE id = v_id
        RETURNING * INTO v_row;
    END IF;
    RETURN public.discount_code_json(v_row);
END;
$$;

-- ---------------------------------------------------------------------
-- quote_sale: as before, plus an optional "discount_code"
-- Patched in place (like 20261102000000) so earlier LadyVogue changes stay.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.patch_function(p_function regprocedure, p_pairs text[])
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

SELECT pg_temp.patch_function('public.quote_sale(jsonb)', ARRAY[
  '    v_now_local TIMESTAMP;' || chr(10) || 'BEGIN',
  $p$    v_now_local TIMESTAMP;
    v_code_text TEXT := public.normalize_discount_code(p_request->>'discount_code');
    v_code public.discount_codes;
BEGIN$p$,
  '    -- 3. Spread promotion discounts over lines by net value, then tax per line',
  $p$
    -- 2b. Discount code: one more promotion on the same net amount
    IF v_code_text IS NOT NULL THEN
        SELECT * INTO v_code FROM public.discount_codes WHERE code = v_code_text;
        IF v_code.id IS NULL OR NOT v_code.active THEN
            RAISE EXCEPTION 'Discount code % is not valid. Check the spelling.', v_code_text;
        END IF;
        IF v_code.valid_from > now() THEN
            RAISE EXCEPTION 'Discount code % starts on %', v_code.code,
                to_char(v_code.valid_from AT TIME ZONE 'Asia/Karachi', 'DD Mon YYYY');
        END IF;
        IF v_code.expires_at IS NOT NULL AND v_code.expires_at <= now() THEN
            RAISE EXCEPTION 'Discount code % expired on %', v_code.code,
                to_char(v_code.expires_at AT TIME ZONE 'Asia/Karachi', 'DD Mon YYYY');
        END IF;
        IF v_code.max_uses IS NOT NULL AND v_code.used_count >= v_code.max_uses THEN
            RAISE EXCEPTION 'Discount code % has already been used', v_code.code;
        END IF;
        IF v_code.customer_id IS NOT NULL AND v_code.customer_id IS DISTINCT FROM v_customer.id THEN
            RAISE EXCEPTION 'Discount code % belongs to a customer. Select that customer first.', v_code.code;
        END IF;
        IF v_code.min_amount IS NOT NULL AND v_net_before_promo < v_code.min_amount THEN
            RAISE EXCEPTION 'Discount code % needs a minimum spend of %', v_code.code, trim_scale(v_code.min_amount);
        END IF;

        v_amount := CASE v_code.discount_type
            WHEN 'percentage' THEN round(v_net_before_promo * v_code.value / 100, 2)
            ELSE round(v_code.value, 2) END;
        IF v_code.max_discount IS NOT NULL THEN
            v_amount := LEAST(v_amount, v_code.max_discount);
        END IF;
        v_amount := GREATEST(LEAST(v_amount, v_net_before_promo - v_promo_total), 0);
        v_promo_total := v_promo_total + v_amount;
        v_promos := v_promos || jsonb_build_object('discountId', v_code.id, 'discountName', 'Code ' || v_code.code,
                                                   'discountAmount', v_amount, 'type', 'code', 'code', v_code.code);
    END IF;

    -- 3. Spread promotion discounts over lines by net value, then tax per line$p$]);

-- ---------------------------------------------------------------------
-- Use up the code when a sale is saved (drafts do not use it)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.redeem_sale_discount_code()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_entry JSONB;
    v_code public.discount_codes;
BEGIN
    IF NEW.status NOT IN ('completed', 'credit') THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.status IN ('completed', 'credit', 'refunded') THEN
        RETURN NEW;
    END IF;

    FOR v_entry IN
        SELECT e FROM jsonb_array_elements(COALESCE(NEW.applied_discounts, '[]'::jsonb)) e WHERE e->>'type' = 'code'
    LOOP
        SELECT * INTO v_code FROM public.discount_codes WHERE id = (v_entry->>'discountId')::uuid FOR UPDATE;
        IF v_code.id IS NULL OR NOT v_code.active
           OR (v_code.expires_at IS NOT NULL AND v_code.expires_at <= now())
           OR (v_code.max_uses IS NOT NULL AND v_code.used_count >= v_code.max_uses) THEN
            RAISE EXCEPTION 'Discount code % was just used or switched off. Remove it and try again.', v_entry->>'code';
        END IF;
        INSERT INTO public.discount_code_redemptions (code_id, code, sale_id, customer_id, amount)
        VALUES (v_code.id, v_code.code, NEW.id, NEW.customer_id, COALESCE((v_entry->>'discountAmount')::numeric, 0))
        ON CONFLICT (sale_id) DO NOTHING;
        IF FOUND THEN
            UPDATE public.discount_codes SET used_count = used_count + 1 WHERE id = v_code.id;
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sales_redeem_discount_code ON public.sales;
CREATE TRIGGER sales_redeem_discount_code AFTER INSERT OR UPDATE OF status ON public.sales
    FOR EACH ROW EXECUTE FUNCTION public.redeem_sale_discount_code();

-- ---------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.normalize_discount_code(TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.new_discount_code() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.issue_welcome_code(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.issue_welcome_code_for_new_customer() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.redeem_sale_discount_code() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.discount_code_json(public.discount_codes) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.customer_discount_codes(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.issue_customer_welcome_code(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.save_discount_code_settings(JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.save_discount_code(JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.quote_sale(JSONB) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.customer_discount_codes(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.issue_customer_welcome_code(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_discount_code_settings(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_discount_code(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.quote_sale(JSONB) TO authenticated;
GRANT SELECT ON public.discount_code_settings, public.discount_codes, public.discount_code_redemptions TO authenticated;
