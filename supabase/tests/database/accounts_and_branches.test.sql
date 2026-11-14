-- Branches, staff vs customer accounts, phone normalisation.
BEGIN;
SELECT plan(22);

SELECT ok(public.needs_bootstrap(), 'bootstrap needed while no administrator exists');

INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
    ('00000000-0000-0000-0000-0000000000a1', 'owner@test.local',    '{"name":"Owner"}', '{}'),
    ('00000000-0000-0000-0000-0000000000b1', 'shopper@test.local',  '{"name":"Shopper","phone":"0300-1234567"}', '{}'),
    ('00000000-0000-0000-0000-0000000000c1', 'staff@test.local',    '{"name":"Staff"}', '{"account_type":"staff"}');

-- The first sign-up on an empty database gets no staff rights (review finding S1)
SELECT is((SELECT count(*)::int FROM public.users WHERE id = '00000000-0000-0000-0000-0000000000a1'), 0,
          'the first sign-up is a customer, not an administrator');
SELECT ok(public.needs_bootstrap(), 'sign-ups alone never close bootstrap');

-- The project owner makes the first administrator from the SQL editor
SELECT app_private.bootstrap_admin('OWNER@test.local');
SELECT ok(NOT public.needs_bootstrap(), 'bootstrap closed once an active administrator exists');
SELECT is((SELECT role || ':' || active FROM public.users WHERE id = '00000000-0000-0000-0000-0000000000a1'), 'admin:true',
          'bootstrap_admin makes that account an active administrator');
SELECT is((SELECT count(*)::int FROM public.customer_accounts WHERE id = '00000000-0000-0000-0000-0000000000a1'), 0,
          'the empty customer account made at sign-up is removed');
SELECT throws_ok($$ SELECT app_private.bootstrap_admin('shopper@test.local') $$, 'P0001',
                 'An administrator already exists. Add staff from User Management in the POS.',
                 'bootstrap_admin is refused once an administrator exists');

-- Routing
SELECT is((SELECT count(*)::int FROM public.users WHERE id = '00000000-0000-0000-0000-0000000000b1'), 0,
          'a normal sign-up does not create a staff profile');
SELECT is((SELECT phone FROM public.customer_accounts WHERE id = '00000000-0000-0000-0000-0000000000b1'), '+923001234567',
          'a normal sign-up creates a customer account with a normalised phone');
SELECT is((SELECT count(*)::int FROM public.users WHERE id = '00000000-0000-0000-0000-0000000000c1'), 1,
          'admin-created staff get a staff profile');
SELECT is((SELECT count(*)::int FROM public.branch_memberships), 2, 'staff join the default branch');
SELECT is((SELECT count(*)::int FROM public.locations l JOIN public.branches b ON b.id = l.branch_id WHERE b.code = 'MAIN'), 4,
          'main branch has its four locations');

-- Staff roles are admin, manager and cashier only
SELECT throws_ok($$ UPDATE public.users SET role = 'mechanic' WHERE id = '00000000-0000-0000-0000-0000000000c1' $$,
                 '23514', NULL, 'roles outside admin, manager and cashier are refused');

-- Phone normalisation
SELECT is(public.normalize_phone('0300 1234567'), '+923001234567', 'local mobile format');
SELECT is(public.normalize_phone('92-300-1234567'), '+923001234567', 'country code without plus');
SELECT is(public.normalize_phone('+92 (300) 123 4567'), '+923001234567', 'international format');
INSERT INTO customers (name, phone) VALUES ('Sara', '0333-7654321');
SELECT throws_ok($$ INSERT INTO customers (name, phone) VALUES ('Sara again', '+92 333 7654321') $$, '23505', NULL,
                 'same phone in another format is a duplicate');

-- A website customer has no staff access
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated","aal":"aal2"}';

SELECT is((SELECT count(*)::int FROM customers), 0, 'customer login cannot read the customer list');
SELECT is((SELECT count(*)::int FROM sales), 0, 'customer login cannot read sales');
SELECT is((SELECT count(*)::int FROM public.customer_accounts), 1, 'customer sees only their own account');
SELECT throws_ok(
    $$ UPDATE public.customer_accounts SET phone_verified = true WHERE id = '00000000-0000-0000-0000-0000000000b1' $$,
    '42501', NULL, 'customer cannot mark their own phone as verified'
);
SELECT throws_ok($$ SELECT public.post_sale('{"request_id":"00000000-0000-0000-0000-0000000000ff","lines":[]}'::jsonb) $$, '42501', NULL, 'customer cannot post sales');

SELECT * FROM finish();
ROLLBACK;
