-- The authenticator app becomes optional for administrators and managers.
--
-- Before: an admin or manager role only took effect in a session verified with
-- an authenticator code (JWT aal = aal2), so every admin had to set one up.
-- Now: a staff member without an authenticator signs in with a password only.
-- Anyone who has set one up (a verified TOTP factor) still has to enter the
-- code, so a stolen password alone does not open their account.

CREATE OR REPLACE FUNCTION "public"."current_app_role"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT role FROM public.users
    WHERE id = auth.uid()
      AND active = true
      AND (
          role = 'cashier'
          OR COALESCE(auth.jwt()->>'aal', '') = 'aal2'
          OR NOT EXISTS (
              SELECT 1 FROM auth.mfa_factors f
              WHERE f.user_id = auth.uid() AND f.status = 'verified'
          )
      )
$$;
