-- Staff created through the auth admin API: metadata arrives in a later update.
BEGIN;
SELECT plan(4);

INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
    ('00000000-0000-0000-0000-0000000000f1', 'owner@t.local', '{"name":"Owner"}', '{}');

-- As the auth service does it: insert without account_type, then set it
INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
    ('00000000-0000-0000-0000-0000000000f2', 'karim@t.local', '{"name":"Karim","username":"karim"}', '{"provider":"email"}');
SELECT is((SELECT count(*)::int FROM customer_accounts WHERE id = '00000000-0000-0000-0000-0000000000f2'), 1,
          'at insert time it looks like a customer sign-up');

UPDATE auth.users SET raw_app_meta_data = raw_app_meta_data || '{"account_type":"staff"}'
WHERE id = '00000000-0000-0000-0000-0000000000f2';

SELECT is((SELECT role || ':' || active FROM public.users WHERE id = '00000000-0000-0000-0000-0000000000f2'), 'cashier:false',
          'marking the user as staff creates an inactive staff profile');
SELECT is((SELECT count(*)::int FROM customer_accounts WHERE id = '00000000-0000-0000-0000-0000000000f2'), 0,
          'the mistaken customer account is removed');
SELECT is((SELECT count(*)::int FROM branch_memberships WHERE user_id = '00000000-0000-0000-0000-0000000000f2'), 1,
          'the new staff member joins the default branch');

SELECT * FROM finish();
ROLLBACK;
