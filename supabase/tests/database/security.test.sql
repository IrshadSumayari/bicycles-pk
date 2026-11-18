-- Roles and row level security for staff accounts.
BEGIN;
SELECT plan(21);

INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
    ('00000000-0000-0000-0000-00000000000a', 'admin@test.local',   '{"name":"Admin","username":"admin"}', '{}'),
    ('00000000-0000-0000-0000-00000000000c', 'cashier@test.local', '{"name":"Cashier","username":"cashier"}', '{"account_type":"staff"}');
SELECT app_private.bootstrap_admin('admin@test.local');

SELECT is(
    (SELECT role || ':' || active || ':' || username FROM public.users WHERE id = '00000000-0000-0000-0000-00000000000a'),
    'admin:true:admin', 'the bootstrapped owner is an active admin with their chosen username'
);
SELECT is(
    (SELECT role || ':' || active FROM public.users WHERE id = '00000000-0000-0000-0000-00000000000c'),
    'cashier:false', 'staff created by an admin start as inactive cashiers'
);

INSERT INTO product_styles (code, name, kind, unit) VALUES ('BIKE', 'Bike', 'item', 'piece');

-- Inactive cashier gets nothing
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated","aal":"aal2"}';
SELECT is((SELECT count(*)::int FROM product_styles), 0, 'inactive user cannot read the catalog');
SELECT throws_ok($$ SELECT quote_sale('{"lines":[]}') $$, '42501', NULL, 'inactive user cannot sell');

RESET ROLE;
SET LOCAL "request.jwt.claims" = '';
UPDATE public.users SET active = true WHERE id = '00000000-0000-0000-0000-00000000000c';

-- Active cashier
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated","aal":"aal2"}';
SELECT is((SELECT count(*)::int FROM product_styles), 1, 'active cashier can read the catalog');
SELECT is((SELECT count(*)::int FROM public.users), 1, 'cashier only sees their own user row');
SELECT throws_ok(
    $$ UPDATE public.users SET role = 'admin' WHERE id = '00000000-0000-0000-0000-00000000000c' $$,
    '42501', NULL, 'cashier cannot promote themselves'
);
SELECT lives_ok(
    $$ UPDATE public.users SET name = 'Cashier One' WHERE id = '00000000-0000-0000-0000-00000000000c' $$,
    'cashier can update their own name'
);
SELECT throws_ok(
    $$ INSERT INTO sales (invoice_number, items, total) VALUES ('X-1', '[]', 0) $$,
    '42501', NULL, 'cashier cannot insert sales directly'
);
SELECT is((SELECT count(*)::int FROM app_settings), 1, 'cashier can read settings');
SELECT throws_ok($$ UPDATE app_settings SET store_name = 'Hacked' $$,'42501',NULL,'direct settings writes are revoked');
SELECT isnt((SELECT store_name FROM app_settings), 'Hacked', 'cashier cannot change settings');

-- Administrators and managers need an authenticator-verified (aal2) session
-- before their role takes effect; cashiers do not (review finding S2).
RESET ROLE;
SET LOCAL "request.jwt.claims" = '';
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated","aal":"aal1"}';
SELECT is((SELECT count(*)::int FROM product_styles), 1, 'a cashier needs no authenticator code');

SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated","aal":"aal1"}';
SELECT ok(NOT public.has_app_role(ARRAY['admin']), 'a password-only admin session has no admin rights');
SELECT is((SELECT count(*)::int FROM product_styles), 0, 'a password-only admin session cannot read the catalog');
SELECT is((SELECT count(*)::int FROM public.users), 1, 'a password-only admin session still reads its own profile');
SELECT lives_ok(
    $$ UPDATE public.users SET role = 'manager' WHERE id = '00000000-0000-0000-0000-00000000000c' $$,
    'a password-only admin update runs but matches no other row'
);

SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated","aal":"aal2"}';
SELECT ok(public.has_app_role(ARRAY['admin']), 'the admin role works after an authenticator code');
SELECT is((SELECT count(*)::int FROM public.users), 2, 'a verified admin sees all staff');
SELECT is((SELECT role FROM public.users WHERE id = '00000000-0000-0000-0000-00000000000c'), 'cashier',
          'the password-only admin session changed nothing');

-- The last active admin cannot be removed
RESET ROLE;
SET LOCAL "request.jwt.claims" = '';
SELECT throws_ok(
    $$ UPDATE public.users SET active = false WHERE id = '00000000-0000-0000-0000-00000000000a' $$,
    NULL, NULL, 'the last active admin cannot be deactivated'
);

SELECT * FROM finish();
ROLLBACK;
