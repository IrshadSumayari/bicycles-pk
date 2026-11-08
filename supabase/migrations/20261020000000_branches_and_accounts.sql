-- =====================================================================
-- Branches, locations and account types
--
--   * One branch seeded now; every staff member belongs to branches
--   * Locations per branch (shop floor, stockroom, workroom, online)
--   * New staff role: tailor
--   * Staff and website customers are separate: a normal sign-up creates a
--     customer account only. Staff profiles are created for the very first
--     user (bootstrap) or by the admin-users edge function
--     (app_metadata.account_type = 'staff').
--   * Customer phone numbers normalised to +92... and unique
-- =====================================================================

-- ---------------------------------------------------------------------
-- Branches and locations
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.branches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    address TEXT,
    phone TEXT,
    timezone TEXT NOT NULL DEFAULT 'Asia/Karachi',
    currency TEXT NOT NULL DEFAULT 'PKR',
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('shop_floor', 'stockroom', 'workroom', 'online')),
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (branch_id, code)
);

CREATE TABLE IF NOT EXISTS public.branch_memberships (
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, branch_id)
);
CREATE INDEX IF NOT EXISTS idx_branch_memberships_branch ON public.branch_memberships(branch_id);

DROP TRIGGER IF EXISTS update_branches_updated_at ON public.branches;
CREATE TRIGGER update_branches_updated_at BEFORE UPDATE ON public.branches
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

INSERT INTO public.branches (code, name) VALUES ('MAIN', 'Main store')
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.locations (branch_id, code, name, kind)
SELECT b.id, l.code, l.name, l.kind
FROM public.branches b
CROSS JOIN (VALUES
    ('FLOOR', 'Shop floor', 'shop_floor'),
    ('STOCK', 'Stockroom', 'stockroom'),
    ('WORK', 'Workroom', 'workroom'),
    ('ONLINE', 'Online orders', 'online')
) AS l(code, name, kind)
WHERE b.code = 'MAIN'
ON CONFLICT (branch_id, code) DO NOTHING;

-- Existing staff join the main branch
INSERT INTO public.branch_memberships (user_id, branch_id)
SELECT u.id, b.id FROM public.users u CROSS JOIN public.branches b WHERE b.code = 'MAIN'
ON CONFLICT DO NOTHING;

-- Default branch for single-branch setups
CREATE OR REPLACE FUNCTION public.default_branch_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT id FROM public.branches WHERE active ORDER BY created_at, code LIMIT 1
$$;

-- Admins see every branch; other staff only the branches they belong to
CREATE OR REPLACE FUNCTION public.is_branch_member(p_branch_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.has_app_role(ARRAY['admin'])
        OR (public.is_staff() AND EXISTS (
            SELECT 1 FROM public.branch_memberships m
            WHERE m.user_id = auth.uid() AND m.branch_id = p_branch_id
        ))
$$;

REVOKE ALL ON FUNCTION public.default_branch_id() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_branch_member(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.default_branch_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_branch_member(UUID) TO authenticated;

ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_memberships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "branches_select_members" ON public.branches;
DROP POLICY IF EXISTS "branches_write_admin" ON public.branches;
CREATE POLICY "branches_select_members" ON public.branches
    FOR SELECT TO authenticated USING (public.is_branch_member(id));
CREATE POLICY "branches_write_admin" ON public.branches
    FOR ALL TO authenticated
    USING (public.has_app_role(ARRAY['admin'])) WITH CHECK (public.has_app_role(ARRAY['admin']));

DROP POLICY IF EXISTS "locations_select_members" ON public.locations;
DROP POLICY IF EXISTS "locations_write_admin" ON public.locations;
CREATE POLICY "locations_select_members" ON public.locations
    FOR SELECT TO authenticated USING (public.is_branch_member(branch_id));
CREATE POLICY "locations_write_admin" ON public.locations
    FOR ALL TO authenticated
    USING (public.has_app_role(ARRAY['admin'])) WITH CHECK (public.has_app_role(ARRAY['admin']));

DROP POLICY IF EXISTS "memberships_select" ON public.branch_memberships;
DROP POLICY IF EXISTS "memberships_write_admin" ON public.branch_memberships;
CREATE POLICY "memberships_select" ON public.branch_memberships
    FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR public.has_app_role(ARRAY['admin', 'manager']));
CREATE POLICY "memberships_write_admin" ON public.branch_memberships
    FOR ALL TO authenticated
    USING (public.has_app_role(ARRAY['admin'])) WITH CHECK (public.has_app_role(ARRAY['admin']));

-- ---------------------------------------------------------------------
-- Tailor role
-- ---------------------------------------------------------------------
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE public.users ADD CONSTRAINT users_role_check
    CHECK (role IN ('admin', 'manager', 'cashier', 'tailor'));

-- ---------------------------------------------------------------------
-- Phone numbers: one format for lookups and uniqueness
--   0300-1234567 / 923001234567 / +92 300 1234567  ->  +923001234567
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.normalize_phone(p_phone TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    digits TEXT := regexp_replace(COALESCE(p_phone, ''), '\D', '', 'g');
BEGIN
    IF digits = '' THEN
        RETURN NULL;
    ELSIF left(digits, 2) = '00' THEN
        RETURN '+' || substr(digits, 3);
    ELSIF left(digits, 1) = '0' AND length(digits) = 11 THEN
        RETURN '+92' || substr(digits, 2);
    ELSIF left(digits, 2) = '92' AND length(digits) = 12 THEN
        RETURN '+' || digits;
    ELSIF length(digits) = 10 AND left(digits, 1) = '3' THEN
        RETURN '+92' || digits;
    ELSIF left(trim(p_phone), 1) = '+' THEN
        RETURN '+' || digits;
    END IF;
    RETURN digits;
END;
$$;

CREATE OR REPLACE FUNCTION public.normalize_customer_phone()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.phone := public.normalize_phone(NEW.phone);
    RETURN NEW;
END;
$$;

UPDATE public.customers SET phone = public.normalize_phone(phone) WHERE phone IS NOT NULL;

DROP TRIGGER IF EXISTS trigger_normalize_customer_phone ON public.customers;
CREATE TRIGGER trigger_normalize_customer_phone
    BEFORE INSERT OR UPDATE OF phone ON public.customers
    FOR EACH ROW EXECUTE FUNCTION public.normalize_customer_phone();

DROP INDEX IF EXISTS public.idx_customers_phone;
CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_phone_unique ON public.customers(phone) WHERE phone IS NOT NULL;

-- ---------------------------------------------------------------------
-- Website customer accounts (never staff)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.customer_accounts (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    -- Linked only after the phone number is verified, so nobody can claim
    -- another person's purchase history by typing their number.
    customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    full_name TEXT,
    email TEXT,
    phone TEXT,
    phone_verified BOOLEAN NOT NULL DEFAULT false,
    marketing_consent BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_accounts_customer ON public.customer_accounts(customer_id)
    WHERE customer_id IS NOT NULL;

DROP TRIGGER IF EXISTS update_customer_accounts_updated_at ON public.customer_accounts;
CREATE TRIGGER update_customer_accounts_updated_at BEFORE UPDATE ON public.customer_accounts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE public.customer_accounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "customer_accounts_own_select" ON public.customer_accounts;
DROP POLICY IF EXISTS "customer_accounts_own_update" ON public.customer_accounts;
DROP POLICY IF EXISTS "customer_accounts_back_office" ON public.customer_accounts;
CREATE POLICY "customer_accounts_own_select" ON public.customer_accounts
    FOR SELECT TO authenticated USING (id = auth.uid());
CREATE POLICY "customer_accounts_own_update" ON public.customer_accounts
    FOR UPDATE TO authenticated USING (id = auth.uid()) WITH CHECK (id = auth.uid());
CREATE POLICY "customer_accounts_back_office" ON public.customer_accounts
    FOR SELECT TO authenticated USING (public.has_app_role(ARRAY['admin', 'manager']));

-- Customers may edit their name, phone and consent, never the link or verification flag
CREATE OR REPLACE FUNCTION public.protect_customer_account_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF auth.uid() IS NOT NULL AND NOT public.has_app_role(ARRAY['admin', 'manager']) THEN
        IF NEW.customer_id IS DISTINCT FROM OLD.customer_id
           OR NEW.phone_verified IS DISTINCT FROM OLD.phone_verified
           OR NEW.id IS DISTINCT FROM OLD.id THEN
            RAISE EXCEPTION 'This field cannot be changed' USING ERRCODE = '42501';
        END IF;
        IF NEW.phone IS DISTINCT FROM OLD.phone THEN
            NEW.phone_verified := false;
        END IF;
    END IF;
    NEW.phone := public.normalize_phone(NEW.phone);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_protect_customer_account_columns ON public.customer_accounts;
CREATE TRIGGER trigger_protect_customer_account_columns
    BEFORE UPDATE ON public.customer_accounts
    FOR EACH ROW EXECUTE FUNCTION public.protect_customer_account_columns();

-- ---------------------------------------------------------------------
-- Sign-up routing: staff or customer
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    is_first_user BOOLEAN;
    is_staff_account BOOLEAN;
    base_username TEXT;
    new_role TEXT;
BEGIN
    SELECT NOT EXISTS (SELECT 1 FROM public.users) INTO is_first_user;
    is_staff_account := is_first_user OR COALESCE(NEW.raw_app_meta_data->>'account_type', '') = 'staff';

    IF NOT is_staff_account THEN
        INSERT INTO public.customer_accounts (id, full_name, email, phone)
        VALUES (
            NEW.id,
            NULLIF(trim(NEW.raw_user_meta_data->>'name'), ''),
            NEW.email,
            public.normalize_phone(COALESCE(NULLIF(NEW.phone, ''), NULLIF(trim(NEW.raw_user_meta_data->>'phone'), '')))
        )
        ON CONFLICT (id) DO NOTHING;
        RETURN NEW;
    END IF;

    base_username := COALESCE(
        NULLIF(trim(NEW.raw_user_meta_data->>'username'), ''),
        split_part(COALESCE(NEW.email, NEW.id::text), '@', 1)
    );
    IF EXISTS (SELECT 1 FROM public.users WHERE username = base_username) THEN
        base_username := base_username || '-' || substr(NEW.id::text, 1, 6);
    END IF;

    new_role := CASE WHEN is_first_user THEN 'admin' ELSE 'cashier' END;

    INSERT INTO public.users (id, username, name, email, role, permissions, active)
    VALUES (
        NEW.id,
        base_username,
        COALESCE(NULLIF(trim(NEW.raw_user_meta_data->>'name'), ''), base_username),
        COALESCE(NEW.email, ''),
        new_role,
        '{}',
        is_first_user
    )
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.branch_memberships (user_id, branch_id)
    SELECT NEW.id, public.default_branch_id()
    WHERE public.default_branch_id() IS NOT NULL
    ON CONFLICT DO NOTHING;

    RETURN NEW;
END;
$$;

-- The POS shows its sign-up form only while no staff account exists yet
CREATE OR REPLACE FUNCTION public.needs_bootstrap()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT NOT EXISTS (SELECT 1 FROM public.users)
$$;

REVOKE ALL ON FUNCTION public.needs_bootstrap() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.needs_bootstrap() TO anon, authenticated;
