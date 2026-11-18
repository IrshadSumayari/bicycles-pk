-- find_sale_for_return(): receipt lookup for any staff member in the branch.
BEGIN;
SELECT plan(5);

INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
    ('00000000-0000-0000-0000-00000000cd01', 'admin@t.local',   '{"name":"Admin"}', '{}'),
    ('00000000-0000-0000-0000-00000000cd02', 'cashier@t.local', '{"name":"Cashier"}', '{"account_type":"staff"}');
SELECT app_private.bootstrap_admin('admin@t.local'); -- first administrator (no longer the first sign-up)
UPDATE public.users SET active = true WHERE id = '00000000-0000-0000-0000-00000000cd02';

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000cd01","role":"authenticated","aal":"aal2"}';
SELECT FROM save_style('{"kind":"item","code":"SK","name":"City bike","variants":[{"sku":"SK-M","size":"M","price":1000,"opening_stock":5}]}');
CREATE TEMP TABLE inv AS SELECT (post_sale(jsonb_build_object('request_id', '00000000-0000-0000-0000-0000000cd001',
    'lines', jsonb_build_array(jsonb_build_object('variant_id', (SELECT id FROM product_variants WHERE sku = 'SK-M'), 'quantity', 2)),
    'payments', jsonb_build_array(jsonb_build_object('method', 'card', 'card_last4', '1111'))))->'sale'->>'invoice_number') AS no;
GRANT SELECT ON inv TO authenticated;

-- A cashier finds the admin's sale by invoice number
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000cd02","role":"authenticated","aal":"aal2"}';
SELECT is((SELECT count(*)::int FROM sales), 0, 'cashier cannot list other people''s sales');
SELECT is((find_sale_for_return((SELECT lower(no) FROM inv))->'sale'->>'total')::numeric, 2000.00, 'but can look one up by invoice number');
SELECT is((find_sale_for_return((SELECT no FROM inv))->'lines'->0->>'quantity')::numeric, 2.000000, 'lookup lists the lines');
SELECT is((find_sale_for_return((SELECT no FROM inv))->>'within_window')::boolean, true, 'lookup says if it is within the return window');
SELECT throws_ok($$ SELECT find_sale_for_return('INV-999999') $$, NULL, NULL, 'unknown invoice numbers are reported');

SELECT * FROM finish();
ROLLBACK;
