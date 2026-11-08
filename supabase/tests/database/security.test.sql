-- Roles and row level security for staff accounts.
BEGIN;
SELECT plan(13);

INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
    ('00000000-0000-0000-0000-00000000000a', 'admin@test.local',   '{"name":"Admin","username":"admin"}', '{}'),
    ('00000000-0000-0000-0000-00000000000c', 'cashier@test.local', '{"name":"Cashier","username":"cashier"}', '{"account_type":"staff"}');

SELECT is(
    (SELECT role || ':' || active FROM public.users WHERE id = '00000000-0000-0000-0000-00000000000a'),
    'admin:true', 'first sign-up becomes an active admin'
);
SELECT is(
    (SELECT role || ':' || active FROM public.users WHERE id = '00000000-0000-0000-0000-00000000000c'),
    'cashier:false', 'staff created by an admin start as inactive cashiers'
);

INSERT INTO product_styles (code, name, kind, unit) VALUES ('KURTA', 'Kurta', 'garment', 'piece');

-- Inactive cashier gets nothing
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM product_styles), 0, 'inactive user cannot read the catalog');
SELECT throws_ok($$ SELECT quote_sale('{"lines":[]}') $$, '42501', NULL, 'inactive user cannot sell');

RESET ROLE;
SET LOCAL "request.jwt.claims" = '';
UPDATE public.users SET active = true WHERE id = '00000000-0000-0000-0000-00000000000c';

-- Active cashier
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated"}';
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

-- The last active admin cannot be removed
RESET ROLE;
SET LOCAL "request.jwt.claims" = '';
SELECT throws_ok(
    $$ UPDATE public.users SET active = false WHERE id = '00000000-0000-0000-0000-00000000000a' $$,
    NULL, NULL, 'the last active admin cannot be deactivated'
);

SELECT * FROM finish();
ROLLBACK;
