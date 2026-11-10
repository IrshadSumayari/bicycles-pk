-- Discount codes: welcome codes for new customers and codes managers create.
BEGIN;
SELECT plan(32);

INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
    ('00000000-0000-0000-0000-0000000dc001', 'admin@dc.local',   '{"name":"Admin"}', '{}'),
    ('00000000-0000-0000-0000-0000000dc002', 'manager@dc.local', '{"name":"Manager"}', '{"account_type":"staff"}'),
    ('00000000-0000-0000-0000-0000000dc003', 'cashier@dc.local', '{"name":"Cashier"}', '{"account_type":"staff"}');
UPDATE public.users SET role = 'manager', active = true WHERE id = '00000000-0000-0000-0000-0000000dc002';
UPDATE public.users SET active = true WHERE id = '00000000-0000-0000-0000-0000000dc003';
UPDATE public.app_settings SET tax_rate = 10;
UPDATE public.discounts SET active = false;

-- One taxable bike at 2000
INSERT INTO product_styles (id, code, name, kind, unit, taxable) VALUES
    ('00000000-0000-0000-0000-0000000dc101', 'DC-BIKE', 'Bike', 'item', 'piece', true);
INSERT INTO product_variants (id, style_id, sku, size, color, price) VALUES
    ('00000000-0000-0000-0000-0000000dc201', '00000000-0000-0000-0000-0000000dc101', 'DC-BIKE-L', 'L', 'White', 2000);
SELECT post_stock_movement(
    (SELECT l.id FROM locations l JOIN branches b ON b.id = l.branch_id WHERE b.code = 'MAIN' AND l.code = 'FLOOR'),
    '00000000-0000-0000-0000-0000000dc201', 20, 'opening');

-- Welcome codes are off by default: an existing customer has none
INSERT INTO customers (id, name, phone) VALUES ('00000000-0000-0000-0000-0000000dc301', 'Ayesha', '03001230001');
SELECT is((SELECT count(*)::int FROM discount_codes), 0, 'no welcome code while switched off');

-- ---------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000dc003","role":"authenticated"}';
SELECT throws_ok($$ SELECT save_discount_code_settings('{"welcome_enabled":true,"welcome_type":"percentage","welcome_value":15,"welcome_valid_days":30}') $$,
    '42501', NULL, 'cashier cannot change welcome settings');
SELECT is((SELECT count(*)::int FROM discount_code_settings), 0, 'cashier cannot read settings');

SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000dc002","role":"authenticated"}';
SELECT throws_ok($$ SELECT save_discount_code_settings('{"welcome_enabled":true,"welcome_type":"percentage","welcome_value":150,"welcome_valid_days":30}') $$,
    'P0001', 'A percent discount cannot be more than 100', 'percent capped at 100');
SELECT lives_ok($$ SELECT save_discount_code_settings('{"welcome_enabled":true,"welcome_type":"percentage","welcome_value":15,"welcome_valid_days":30}') $$,
    'manager switches on 15% welcome codes');

-- A customer added at the till gets a personal one-time code
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000dc003","role":"authenticated"}';
INSERT INTO customers (id, name, phone) VALUES ('00000000-0000-0000-0000-0000000dc302', 'Bilal', '03001230002');
SELECT is((SELECT jsonb_build_object('n', jsonb_array_length(c), 'kind', c->0->'kind', 'value', c->0->'value',
                                     'uses', c->0->'max_uses', 'status', c->0->'status')
           FROM customer_discount_codes('00000000-0000-0000-0000-0000000dc302') c),
    '{"n":1,"kind":"welcome","value":15.00,"uses":1,"status":"ready"}'::jsonb, 'new customer gets a 15% welcome code');
SELECT ok((SELECT c->0->>'code' FROM customer_discount_codes('00000000-0000-0000-0000-0000000dc302') c) ~ '^LV-[A-HJ-NP-Z2-9]{6}$',
    'code looks like LV-XXXXXX');
SELECT ok((SELECT (c->0->>'expires_at')::timestamptz FROM customer_discount_codes('00000000-0000-0000-0000-0000000dc302') c)
          BETWEEN now() + interval '29 days' AND now() + interval '31 days', 'code lasts 30 days');
SELECT is((SELECT count(*)::int FROM discount_codes), 0, 'cashier cannot browse all codes');

CREATE TEMP TABLE bilal_code AS
SELECT c->0->>'code' AS code FROM customer_discount_codes('00000000-0000-0000-0000-0000000dc302') c;

-- ---------------------------------------------------------------------
-- Using a welcome code
-- ---------------------------------------------------------------------
SELECT throws_ok(format($$ SELECT quote_sale('{"lines":[{"variant_id":"00000000-0000-0000-0000-0000000dc201","quantity":1}],
                                              "discount_code":"%s"}') $$, (SELECT code FROM bilal_code)),
    'P0001', NULL, 'welcome code needs its customer');
SELECT is((SELECT jsonb_build_object('discount', q->'promotion_discount', 'total', q->'total', 'type', q->'applied_discounts'->0->'type')
           FROM quote_sale(format('{"customer_id":"00000000-0000-0000-0000-0000000dc302",
                                    "lines":[{"variant_id":"00000000-0000-0000-0000-0000000dc201","quantity":1}],
                                    "discount_code":" %s "}', lower((SELECT code FROM bilal_code)))::jsonb) q),
    '{"discount":300.00,"total":1870.00,"type":"code"}'::jsonb, '15% off before tax; code is not case or space sensitive');
SELECT throws_ok($$ SELECT quote_sale('{"lines":[{"variant_id":"00000000-0000-0000-0000-0000000dc201","quantity":1}],"discount_code":"NOPE1"}') $$,
    'P0001', 'Discount code NOPE1 is not valid. Check the spelling.', 'unknown code refused');

-- A draft does not use the code
SELECT lives_ok(format($$ SELECT post_sale('{"request_id":"00000000-0000-0000-0000-0000000dc401","status":"draft",
    "customer_id":"00000000-0000-0000-0000-0000000dc302",
    "lines":[{"variant_id":"00000000-0000-0000-0000-0000000dc201","quantity":1}],"discount_code":"%s"}') $$, (SELECT code FROM bilal_code)),
    'draft with a code');
SELECT is((SELECT c->0->>'status' FROM customer_discount_codes('00000000-0000-0000-0000-0000000dc302') c), 'ready', 'draft leaves the code unused');

SELECT is((SELECT (post_sale(format('{"request_id":"00000000-0000-0000-0000-0000000dc402",
    "customer_id":"00000000-0000-0000-0000-0000000dc302",
    "lines":[{"variant_id":"00000000-0000-0000-0000-0000000dc201","quantity":1}],"discount_code":"%s",
    "payments":[{"method":"card","card_last4":"4242"}]}', (SELECT code FROM bilal_code))::jsonb)->'sale'->>'total')::numeric),
    1870.00, 'sale charged with the code');
SELECT is((SELECT c->0->>'status' FROM customer_discount_codes('00000000-0000-0000-0000-0000000dc302') c), 'used', 'code used up by the sale');
SELECT is((SELECT (post_sale(format('{"request_id":"00000000-0000-0000-0000-0000000dc402",
    "customer_id":"00000000-0000-0000-0000-0000000dc302",
    "lines":[{"variant_id":"00000000-0000-0000-0000-0000000dc201","quantity":1}],"discount_code":"%s",
    "payments":[{"method":"card","card_last4":"4242"}]}', (SELECT code FROM bilal_code))::jsonb)->'sale'->>'total')::numeric),
    1870.00, 'retrying the same sale returns it');
SELECT throws_ok(format($$ SELECT quote_sale('{"customer_id":"00000000-0000-0000-0000-0000000dc302",
    "lines":[{"variant_id":"00000000-0000-0000-0000-0000000dc201","quantity":1}],"discount_code":"%s"}') $$, (SELECT code FROM bilal_code)),
    'P0001', format('Discount code %s has already been used', (SELECT code FROM bilal_code)), 'one-time code cannot be reused');

-- ---------------------------------------------------------------------
-- Changing the welcome offer affects only new codes
-- ---------------------------------------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000dc001","role":"authenticated"}';
SELECT lives_ok($$ SELECT save_discount_code_settings('{"welcome_enabled":true,"welcome_type":"fixed","welcome_value":250,"welcome_valid_days":7,"welcome_min_amount":1500}') $$,
    'admin changes the offer to 250 off over 1500');
INSERT INTO customers (id, name, phone) VALUES ('00000000-0000-0000-0000-0000000dc303', 'Sana', '03001230003');
SELECT is((SELECT jsonb_build_object('type', discount_type, 'value', value, 'min', min_amount) FROM discount_codes
           WHERE customer_id = '00000000-0000-0000-0000-0000000dc303'),
    '{"type":"fixed","value":250.00,"min":1500.00}'::jsonb, 'new customer gets the new offer');
SELECT is((SELECT value FROM discount_codes WHERE customer_id = '00000000-0000-0000-0000-0000000dc302'), 15.00,
    'earlier code keeps its value');

-- Existing customers can be given a code once
SELECT is((SELECT issue_customer_welcome_code('00000000-0000-0000-0000-0000000dc301')->>'kind'), 'welcome', 'existing customer given a code');
SELECT throws_ok($$ SELECT issue_customer_welcome_code('00000000-0000-0000-0000-0000000dc301') $$,
    'P0001', 'This customer already has a welcome code', 'only one welcome code each');

-- ---------------------------------------------------------------------
-- Codes managers create
-- ---------------------------------------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000dc003","role":"authenticated"}';
SELECT throws_ok($$ SELECT save_discount_code('{"code":"EID14","discount_type":"percentage","value":14}') $$,
    '42501', NULL, 'cashier cannot create codes');

SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000dc002","role":"authenticated"}';
SELECT is((SELECT save_discount_code('{"code":"eid14","discount_type":"percentage","value":14}')->>'code'), 'EID14',
    'manager creates EID14 for anyone, unlimited uses');
SELECT throws_ok($$ SELECT save_discount_code('{"code":"EID14","discount_type":"fixed","value":100}') $$,
    'P0001', 'The code EID14 already exists. Choose another.', 'duplicate code refused');
SELECT lives_ok($$ SELECT save_discount_code('{"code":"OLD10","discount_type":"percentage","value":10,
    "valid_from":"2026-01-01T00:00:00Z","expires_at":"2026-01-31T00:00:00Z"}') $$, 'expired code saved');

SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000dc003","role":"authenticated"}';
SELECT is((SELECT (q->>'promotion_discount')::numeric FROM quote_sale(
    '{"lines":[{"variant_id":"00000000-0000-0000-0000-0000000dc201","quantity":2}],"discount_code":"EID14"}') q),
    560.00, 'EID14 takes 14% off 4000');
SELECT is((SELECT (post_sale('{"request_id":"00000000-0000-0000-0000-0000000dc403",
    "lines":[{"variant_id":"00000000-0000-0000-0000-0000000dc201","quantity":1}],"discount_code":"EID14",
    "payments":[{"method":"card","card_last4":"1111"}]}')->'sale'->>'total')::numeric), 1892.00, 'EID14 used on a sale');
SELECT throws_ok($$ SELECT quote_sale('{"lines":[{"variant_id":"00000000-0000-0000-0000-0000000dc201","quantity":1}],"discount_code":"OLD10"}') $$,
    'P0001', 'Discount code OLD10 expired on 31 Jan 2026', 'expired code refused');

SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000dc002","role":"authenticated"}';
SELECT is((SELECT used_count FROM discount_codes WHERE code = 'EID14'), 1, 'use counted');
SELECT is((SELECT jsonb_agg(amount ORDER BY amount) FROM discount_code_redemptions), '[280.00, 300.00]'::jsonb,
    'redemptions recorded with the amount given');

SELECT * FROM finish();
ROLLBACK;
