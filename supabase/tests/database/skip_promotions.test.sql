-- Removing an automatic promotion from one sale at checkout.
BEGIN;
SELECT plan(7);

INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
    ('00000000-0000-0000-0000-00000005c001', 'admin@sp.local',   '{"name":"Admin"}', '{}'),
    ('00000000-0000-0000-0000-00000005c003', 'cashier@sp.local', '{"name":"Cashier"}', '{"account_type":"staff"}');
UPDATE public.users SET active = true WHERE id = '00000000-0000-0000-0000-00000005c003';
UPDATE public.app_settings SET tax_rate = 0;
UPDATE public.discounts SET active = false;

-- One kurta at 2000 and two automatic promotions
INSERT INTO product_styles (id, code, name, kind, unit, taxable) VALUES
    ('00000000-0000-0000-0000-00000005c101', 'SP-KURTA', 'Kurta', 'garment', 'piece', true);
INSERT INTO product_variants (id, style_id, sku, size, color, price) VALUES
    ('00000000-0000-0000-0000-00000005c201', '00000000-0000-0000-0000-00000005c101', 'SP-KURTA-L', 'L', 'White', 2000);
SELECT post_stock_movement(
    (SELECT l.id FROM locations l JOIN branches b ON b.id = l.branch_id WHERE b.code = 'MAIN' AND l.code = 'FLOOR'),
    '00000000-0000-0000-0000-00000005c201', 20, 'opening');
INSERT INTO discounts (id, name, type, value, valid_from, valid_to, active) VALUES
    ('00000000-0000-0000-0000-00000005c301', 'Ten off', 'percentage', 10, now() - interval '1 day', now() + interval '1 day', true),
    ('00000000-0000-0000-0000-00000005c302', 'Flat 100', 'fixed', 100, now() - interval '1 day', now() + interval '1 day', true);

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000005c003","role":"authenticated"}';

SELECT is((SELECT q->'total' FROM quote_sale(
        '{"lines":[{"variant_id":"00000000-0000-0000-0000-00000005c201","quantity":1}]}') q),
    '1700.00'::jsonb, 'both promotions apply automatically');

SELECT is((SELECT jsonb_build_object('total', q->'total', 'n', jsonb_array_length(q->'applied_discounts'),
                                     'left', q->'applied_discounts'->0->>'discountName')
           FROM quote_sale('{"lines":[{"variant_id":"00000000-0000-0000-0000-00000005c201","quantity":1}],
                             "skipped_promotions":["00000000-0000-0000-0000-00000005c301"]}') q),
    '{"total":1900.00,"n":1,"left":"Flat 100"}'::jsonb, 'a cashier can remove one promotion from the sale');

SELECT is((SELECT q->'total' FROM quote_sale(
        '{"lines":[{"variant_id":"00000000-0000-0000-0000-00000005c201","quantity":1}],
          "skipped_promotions":["00000000-0000-0000-0000-00000005c301","00000000-0000-0000-0000-00000005c302"]}') q),
    '2000.00'::jsonb, 'removing every promotion charges the full price');

SELECT is((SELECT q->'total' FROM quote_sale(
        '{"lines":[{"variant_id":"00000000-0000-0000-0000-00000005c201","quantity":1}],
          "skipped_promotions":"not-a-list"}') q),
    '1700.00'::jsonb, 'a malformed list is ignored');

SELECT is((SELECT q->'total' FROM quote_sale(
        '{"lines":[{"variant_id":"00000000-0000-0000-0000-00000005c201","quantity":1}],
          "skipped_promotions":["unknown"]}') q),
    '1700.00'::jsonb, 'an unknown id changes nothing');

-- The posted sale is priced the same way as the quote
SELECT lives_ok($$ SELECT post_sale('{"request_id":"00000000-0000-0000-0000-00000005c401",
        "lines":[{"variant_id":"00000000-0000-0000-0000-00000005c201","quantity":1}],
        "skipped_promotions":["00000000-0000-0000-0000-00000005c301"],
        "payments":[{"method":"card","card_type":"visa","card_last4":"1234"}]}') $$,
    'post a sale with one promotion removed');
SELECT is((SELECT total FROM sales WHERE request_id = '00000000-0000-0000-0000-00000005c401'), 1900.00,
    'the sale is charged without the removed promotion');

SELECT * FROM finish();
ROLLBACK;
