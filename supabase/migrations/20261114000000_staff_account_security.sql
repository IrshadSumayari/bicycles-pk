-- Staff account security (review findings S1 and S2).
--
-- 1. The first Auth account no longer becomes the administrator. Every sign-up
--    without staff app metadata is a website customer, so a customer who signs
--    up on an empty database gains nothing. The first administrator is created
--    by the project owner with app_private.bootstrap_admin(email), which only
--    the database owner (SQL editor, CLI) can run.
-- 2. Administrators and managers must sign in with an authenticator app. Their
--    role only takes effect in sessions verified to AAL2, so a stolen password
--    alone opens nothing. Cashiers keep password-only sign-in for shared tills.

-- ---------------------------------------------------------------------------
-- 1. Sign-ups are routed by app metadata only
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION "public"."handle_new_auth_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    base_username TEXT;
BEGIN
    -- app metadata can only be set with the service key (admin-users function).
    IF COALESCE(NEW.raw_app_meta_data->>'account_type', '') <> 'staff' THEN
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

    -- New staff start as inactive cashiers; admin-users then applies the role.
    INSERT INTO public.users (id, username, name, email, role, permissions, active)
    VALUES (
        NEW.id,
        base_username,
        COALESCE(NULLIF(trim(NEW.raw_user_meta_data->>'name'), ''), base_username),
        COALESCE(NEW.email, ''),
        'cashier',
        '{}',
        false
    )
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.branch_memberships (user_id, branch_id)
    SELECT NEW.id, public.default_branch_id()
    WHERE public.default_branch_id() IS NOT NULL
    ON CONFLICT DO NOTHING;

    RETURN NEW;
END;
$$;

-- The POS shows setup instructions until an active administrator exists.
CREATE OR REPLACE FUNCTION "public"."needs_bootstrap"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT NOT EXISTS (SELECT 1 FROM public.users WHERE role = 'admin' AND active = true)
$$;

-- Makes an existing Auth user the first administrator. Run once per project,
-- as the database owner, after creating the user in Authentication -> Users:
--     SELECT app_private.bootstrap_admin('owner@example.com');
-- Refused once an active administrator exists; later admins are made in the POS.
CREATE OR REPLACE FUNCTION "app_private"."bootstrap_admin"("p_email" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_user auth.users;
    v_username TEXT;
BEGIN
    -- Serialise concurrent calls so only one administrator can be bootstrapped.
    PERFORM pg_advisory_xact_lock(hashtext('app_private.bootstrap_admin'));

    IF EXISTS (SELECT 1 FROM public.users WHERE role = 'admin' AND active = true) THEN
        RAISE EXCEPTION 'An administrator already exists. Add staff from User Management in the POS.';
    END IF;

    SELECT * INTO v_user FROM auth.users WHERE lower(email) = lower(trim(p_email));
    IF v_user.id IS NULL THEN
        RAISE EXCEPTION 'No Auth user has the email %. Create it in Authentication -> Users first.', p_email;
    END IF;
    IF EXISTS (SELECT 1 FROM public.customer_accounts WHERE id = v_user.id AND customer_id IS NOT NULL) THEN
        RAISE EXCEPTION 'That email belongs to a website customer with order history. Use a separate staff email.';
    END IF;

    v_username := COALESCE(
        NULLIF(trim(v_user.raw_user_meta_data->>'username'), ''),
        split_part(COALESCE(v_user.email, v_user.id::text), '@', 1)
    );
    IF EXISTS (SELECT 1 FROM public.users WHERE username = v_username AND id <> v_user.id) THEN
        v_username := v_username || '-' || substr(v_user.id::text, 1, 6);
    END IF;

    INSERT INTO public.users (id, username, name, email, role, permissions, active)
    VALUES (
        v_user.id,
        v_username,
        COALESCE(NULLIF(trim(v_user.raw_user_meta_data->>'name'), ''), v_username),
        COALESCE(v_user.email, ''),
        'admin',
        '{}',
        true
    )
    ON CONFLICT (id) DO UPDATE SET role = 'admin', active = true;

    INSERT INTO public.branch_memberships (user_id, branch_id)
    SELECT v_user.id, public.default_branch_id()
    WHERE public.default_branch_id() IS NOT NULL
    ON CONFLICT DO NOTHING;

    -- Mark the account as staff so later sign-in routing agrees, and drop the
    -- empty customer account the sign-up trigger created for it.
    UPDATE auth.users
    SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || '{"account_type":"staff"}'::jsonb
    WHERE id = v_user.id;
    DELETE FROM public.customer_accounts WHERE id = v_user.id AND customer_id IS NULL;

    RETURN v_user.id;
END;
$$;

ALTER FUNCTION "app_private"."bootstrap_admin"("p_email" "text") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "app_private"."bootstrap_admin"("p_email" "text") FROM PUBLIC, "anon", "authenticated", "service_role";

-- ---------------------------------------------------------------------------
-- 2. Administrator and manager roles require an authenticator-verified session
-- ---------------------------------------------------------------------------

-- Every role check (has_app_role, is_staff, is_counter_staff, is_branch_member,
-- row level security) goes through this function. Supabase puts the session's
-- assurance level in the JWT "aal" claim: aal2 after an authenticator code.
CREATE OR REPLACE FUNCTION "public"."current_app_role"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT role FROM public.users
    WHERE id = auth.uid()
      AND active = true
      AND (role = 'cashier' OR COALESCE(auth.jwt()->>'aal', '') = 'aal2')
$$;
