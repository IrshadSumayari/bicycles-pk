-- =====================================================================
-- Fix: staff accounts created through the auth admin API
--
-- The auth service inserts the user first and writes app_metadata
-- (account_type = 'staff') in a later UPDATE, so the insert trigger saw an
-- ordinary sign-up and created a customer account. Staff created by an admin
-- (admin-users edge function) therefore became customers.
--
-- This trigger also runs when app_metadata changes: a user marked as staff
-- gets an (inactive cashier) staff profile in the default branch, and the
-- customer account created by mistake is removed if nothing uses it yet.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.handle_auth_user_marked_staff()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    base_username TEXT;
BEGIN
    IF COALESCE(NEW.raw_app_meta_data->>'account_type', '') <> 'staff'
       OR COALESCE(OLD.raw_app_meta_data->>'account_type', '') = 'staff'
       OR EXISTS (SELECT 1 FROM public.users WHERE id = NEW.id) THEN
        RETURN NEW;
    END IF;

    base_username := COALESCE(
        NULLIF(trim(NEW.raw_user_meta_data->>'username'), ''),
        split_part(COALESCE(NEW.email, NEW.id::text), '@', 1)
    );
    IF EXISTS (SELECT 1 FROM public.users WHERE username = base_username) THEN
        base_username := base_username || '-' || substr(NEW.id::text, 1, 6);
    END IF;

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

    -- The customer account made at insert time belongs to no one yet
    DELETE FROM public.customer_accounts WHERE id = NEW.id AND customer_id IS NULL;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_marked_staff ON auth.users;
CREATE TRIGGER on_auth_user_marked_staff
    AFTER UPDATE OF raw_app_meta_data ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_auth_user_marked_staff();

-- Repair accounts already affected: staff-marked users without a staff profile
DO $$
DECLARE
    u RECORD;
BEGIN
    FOR u IN
        SELECT au.* FROM auth.users au
        WHERE au.raw_app_meta_data->>'account_type' = 'staff'
          AND NOT EXISTS (SELECT 1 FROM public.users pu WHERE pu.id = au.id)
    LOOP
        INSERT INTO public.users (id, username, name, email, role, permissions, active)
        VALUES (u.id,
                COALESCE(NULLIF(trim(u.raw_user_meta_data->>'username'), ''), split_part(u.email, '@', 1)) || '-' || substr(u.id::text, 1, 6),
                COALESCE(NULLIF(trim(u.raw_user_meta_data->>'name'), ''), split_part(u.email, '@', 1)),
                COALESCE(u.email, ''), 'cashier', '{}', false)
        ON CONFLICT (id) DO NOTHING;
        INSERT INTO public.branch_memberships (user_id, branch_id)
        SELECT u.id, public.default_branch_id() WHERE public.default_branch_id() IS NOT NULL
        ON CONFLICT DO NOTHING;
        DELETE FROM public.customer_accounts WHERE id = u.id AND customer_id IS NULL;
    END LOOP;
END $$;
