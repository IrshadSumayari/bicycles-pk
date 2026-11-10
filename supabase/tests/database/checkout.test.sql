-- Server-side checkout: quote_sale() / post_sale().
BEGIN;
SELECT plan(34);

INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
    ('00000000-0000-0000-0000-00000000bb01', 'admin@t.local',   '{"name":"Admin"}', '{}'),
    ('00000000-0000-0000-0000-00000000bb02', 'manager@t.local', '{"name":"Manager"}', '{"account_type":"staff"}'),
    ('00000000-0000-0000-0000-00000000bb03', 'cashier@t.local', '{"name":"Cashier"}', '{"account_type":"staff"}'),
    ('00000000-0000-0000-0000-00000000bb04', 'inactive@t.local', '{"name":"Inactive"}', '{"account_type":"staff"}');
UPDATE public.users SET role = 'manager', active = true WHERE id = '00000000-0000-0000-0000-00000000bb02';
UPDATE public.users SET active = true WHERE id = '00000000-0000-0000-0000-00000000bb03';
UPDATE public.users SET role = 'cashier', active = false WHERE id = '00000000-0000-0000-0000-00000000bb04';
UPDATE public.app_settings SET tax_rate = 10, max_cashier_discount_percent = 10;

-- Catalog: taxable bike (2000), non-taxable bell (1000), gift set (800 / set), gift bottle cage
INSERT INTO product_styles (id, code, name, kind, unit, taxable) VALUES
    ('00000000-0000-0000-0000-0000000c0001', 'BIKE', 'Bike', 'item', 'piece', true),
    ('00000000-0000-0000-0000-0000000c0002', 'SHAWL', 'Shawl', 'item', 'piece', false),
    ('00000000-0000-0000-0000-0000000c0003', 'GIFTSET', 'Gift set', 'pack', 'set', true),
    ('00000000-0000-0000-0000-0000000c0004', 'POCKET', 'Pocket square', 'item', 'piece', true);
INSERT INTO product_variants (id, style_id, sku, size, color, price) VALUES
    ('00000000-0000-0000-0000-0000000d0001', '00000000-0000-0000-0000-0000000c0001', 'BIKE-L', 'L', 'White', 2000),
    ('00000000-0000-0000-0000-0000000d0002', '00000000-0000-0000-0000-0000000c0002', 'SHAWL-1', NULL, 'Grey', 1000),
    ('00000000-0000-0000-0000-0000000d0003', '00000000-0000-0000-0000-0000000c0003', 'GIFTSET-BLUE', NULL, 'Blue', 800),
    ('00000000-0000-0000-0000-0000000d0004', '00000000-0000-0000-0000-0000000c0004', 'POCKET-1', NULL, 'Red', 300);
INSERT INTO variant_costs (variant_id, unit_cost) VALUES ('00000000-0000-0000-0000-0000000d0001', 900);
INSERT INTO customers (id, name, phone, credit_limit) VALUES
    ('00000000-0000-0000-0000-0000000e0001', 'Bilal', '03001112223', 1000);

CREATE TEMP TABLE floor AS
SELECT l.id FROM locations l JOIN branches b ON b.id = l.branch_id WHERE b.code = 'MAIN' AND l.code = 'FLOOR';
GRANT SELECT ON floor TO authenticated;
SELECT post_stock_movement((SELECT id FROM floor), '00000000-0000-0000-0000-0000000d0001', 5, 'opening');
SELECT post_stock_movement((SELECT id FROM floor), '00000000-0000-0000-0000-0000000d0002', 5, 'opening');
SELECT post_stock_movement((SELECT id FROM floor), '00000000-0000-0000-0000-0000000d0003', 10, 'opening');
SELECT post_stock_movement((SELECT id FROM floor), '00000000-0000-0000-0000-0000000d0004', 1, 'opening');

CREATE FUNCTION pg_temp.on_hand(v UUID) RETURNS NUMERIC LANGUAGE sql AS
$$ SELECT on_hand FROM stock_balances WHERE variant_id = v $$;
GRANT EXECUTE ON FUNCTION pg_temp.on_hand(UUID) TO authenticated;

-- ---------------------------------------------------------------------
-- Cashier
-- ---------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000bb03","role":"authenticated"}';
SELECT FROM open_cash_session(0);

-- Quote: tax only on the taxable bikes
SELECT is(
    (SELECT jsonb_build_object('subtotal', q->'subtotal', 'tax', q->'tax_amount', 'total', q->'total')
     FROM quote_sale('{"lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0001","quantity":2},
                                {"variant_id":"00000000-0000-0000-0000-0000000d0002","quantity":1}]}') q),
    '{"subtotal": 5000, "tax": 400.00, "total": 5400.00}'::jsonb,
    'quote charges tax on taxable items only'
);

-- Post a cash sale with change
SELECT lives_ok($$
    SELECT post_sale('{"request_id":"00000000-0000-0000-0000-0000000f0001",
        "lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0001","quantity":2},
                 {"variant_id":"00000000-0000-0000-0000-0000000d0002","quantity":1}],
        "payments":[{"method":"cash","tendered":6000}]}')
$$, 'cashier posts a cash sale');
SELECT is((SELECT total FROM sales WHERE request_id = '00000000-0000-0000-0000-0000000f0001'), 5400.00, 'total from database prices');
SELECT is((SELECT change_due FROM sales WHERE request_id = '00000000-0000-0000-0000-0000000f0001'), 600.00, 'change worked out');
SELECT matches((SELECT invoice_number FROM sales WHERE request_id = '00000000-0000-0000-0000-0000000f0001'), '^INV-\d{6}$', 'invoice number assigned');
SELECT is(pg_temp.on_hand('00000000-0000-0000-0000-0000000d0001'), 3.000000, 'bike stock deducted');
SELECT is(pg_temp.on_hand('00000000-0000-0000-0000-0000000d0002'), 4.000000, 'bell stock deducted');
SELECT is((SELECT count(*)::int FROM sale_lines sl JOIN sales s ON s.id = sl.sale_id
           WHERE s.request_id = '00000000-0000-0000-0000-0000000f0001'), 2, 'two sale lines stored');
SELECT is((SELECT count(*)::int FROM payments p JOIN sales s ON s.id = p.sale_id
           WHERE s.request_id = '00000000-0000-0000-0000-0000000f0001'), 1, 'one payment stored');

-- Retry
SELECT is(
    (post_sale('{"request_id":"00000000-0000-0000-0000-0000000f0001",
        "lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0001","quantity":2}],
        "payments":[{"method":"cash"}]}')->'sale'->>'id'),
    (SELECT id::text FROM sales WHERE request_id = '00000000-0000-0000-0000-0000000f0001'),
    'a retried request returns the original sale'
);
SELECT is(pg_temp.on_hand('00000000-0000-0000-0000-0000000d0001'), 3.000000, 'retry does not deduct stock again');

-- Tampering: price and totals from the browser are ignored
SELECT is(
    (post_sale('{"request_id":"00000000-0000-0000-0000-0000000f0002",
        "lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0001","quantity":1,"price":1}],
        "subtotal":1,"total":1,
        "payments":[{"method":"card","card_type":"visa","card_last4":"4242","bank_name":"HBL"}]}')->'sale'->>'total')::numeric,
    2200.00,
    'browser prices and totals are ignored'
);
SELECT is((SELECT card_details FROM sales WHERE request_id = '00000000-0000-0000-0000-0000000f0002'),
          '{"bankName":"HBL","cardType":"visa","lastFourDigits":"4242"}'::jsonb, 'card stored as type, bank and last 4');

-- Manual discount limits
SELECT throws_ok($$
    SELECT quote_sale('{"lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0001","quantity":1,
                                  "discount_type":"percentage","discount_value":15}]}')
$$, '42501', NULL, 'cashier cannot discount above 10%');
SELECT is(
    (quote_sale('{"lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0001","quantity":1,
                            "discount_type":"percentage","discount_value":10}]}')->>'total')::numeric,
    1980.00, 'cashier discount within limit; tax after discount'
);

-- Packs
SELECT lives_ok($$
    SELECT post_sale('{"request_id":"00000000-0000-0000-0000-0000000f0003",
        "lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0003","quantity":2}],
        "payments":[{"method":"cash"}]}')
$$, 'packs sold by the set');
SELECT is(pg_temp.on_hand('00000000-0000-0000-0000-0000000d0003'), 8.000000, '2 sets from 10 leaves 8');
SELECT throws_ok($$
    SELECT quote_sale('{"lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0003","quantity":2.5}]}')
$$, NULL, NULL, 'packs only in whole sets');
SELECT throws_ok($$
    SELECT quote_sale('{"lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0001","quantity":1.5}]}')
$$, NULL, NULL, 'items only in whole pieces');

-- Payments must add up
SELECT throws_ok($$
    SELECT post_sale('{"request_id":"00000000-0000-0000-0000-0000000f0004",
        "lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0002","quantity":1}],
        "payments":[{"method":"cash","amount":500},{"method":"card","amount":400,"card_last4":"1111"}]}')
$$, NULL, NULL, 'split payments must equal the total');
SELECT lives_ok($$
    SELECT post_sale('{"request_id":"00000000-0000-0000-0000-0000000f0005",
        "lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0002","quantity":1}],
        "payments":[{"method":"cash","amount":600},{"method":"card","amount":400,"card_last4":"1111"}]}')
$$, 'split cash and card payment');

-- Out of stock: nothing saved
SELECT throws_ok($$
    SELECT post_sale('{"request_id":"00000000-0000-0000-0000-0000000f0006",
        "lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0001","quantity":99}],
        "payments":[{"method":"cash"}]}')
$$, 'P0001', NULL, 'cannot sell more than available');
SELECT is((SELECT count(*)::int FROM sales WHERE request_id = '00000000-0000-0000-0000-0000000f0006'), 0, 'failed sale leaves no record');

-- Store credit
SELECT throws_ok($$
    SELECT post_sale('{"request_id":"00000000-0000-0000-0000-0000000f0007",
        "customer_id":"00000000-0000-0000-0000-0000000e0001",
        "lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0001","quantity":1}],
        "payments":[{"method":"credit"}]}')
$$, NULL, NULL, 'store credit above the limit is refused');

-- Drafts
SELECT lives_ok($$
    SELECT post_sale('{"request_id":"00000000-0000-0000-0000-0000000f0008","status":"draft",
        "lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0001","quantity":1}]}')
$$, 'draft saved without payment');
SELECT is(pg_temp.on_hand('00000000-0000-0000-0000-0000000d0001'), 2.000000, 'draft does not move stock');

-- Completed sales are final
UPDATE sales SET total = 1 WHERE request_id = '00000000-0000-0000-0000-0000000f0001';
DELETE FROM sales WHERE request_id = '00000000-0000-0000-0000-0000000f0001';
SELECT is((SELECT total FROM sales WHERE request_id = '00000000-0000-0000-0000-0000000f0001'), 5400.00,
          'completed sale cannot be edited or deleted');
SELECT lives_ok($$ DELETE FROM sales WHERE request_id = '00000000-0000-0000-0000-0000000f0008' $$, 'own draft can be deleted');
SELECT is((SELECT count(*)::int FROM sales WHERE request_id = '00000000-0000-0000-0000-0000000f0008'), 0, 'draft deleted');

-- Inactive staff cannot sell
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000bb04","role":"authenticated"}';
SELECT throws_ok($$
    SELECT quote_sale('{"lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0001","quantity":1}]}')
$$, '42501', NULL, 'inactive staff cannot use the till');

-- ---------------------------------------------------------------------
-- Promotions
-- ---------------------------------------------------------------------
RESET ROLE;
SET LOCAL "request.jwt.claims" = '';
INSERT INTO discounts (name, type, value, min_amount, valid_from, valid_to) VALUES
    ('10% over 3000', 'percentage', 10, 3000, now() - interval '1 day', now() + interval '1 day');
INSERT INTO discounts (name, type, value, free_gift_products, conditions, valid_from, valid_to) VALUES
    ('Gift with bike', 'free_gift', 0, ARRAY['00000000-0000-0000-0000-0000000d0004'],
     '[{"type":"specific_products","value":["00000000-0000-0000-0000-0000000d0001"]}]',
     now() - interval '1 day', now() + interval '1 day');

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000bb02","role":"authenticated"}';
SELECT FROM open_cash_session(0);

SELECT is(
    (quote_sale('{"lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0002","quantity":4}]}')->>'promotion_discount')::numeric,
    400.00, 'percentage promotion applied above the minimum'
);
SELECT is(
    (quote_sale('{"lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0002","quantity":1}]}')->>'promotion_discount')::numeric,
    0::numeric, 'promotion not applied below the minimum'
);
SELECT lives_ok($$
    SELECT post_sale('{"request_id":"00000000-0000-0000-0000-0000000f0009",
        "lines":[{"variant_id":"00000000-0000-0000-0000-0000000d0001","quantity":1}],
        "payments":[{"method":"cash"}]}')
$$, 'sale with a free gift');
SELECT is(pg_temp.on_hand('00000000-0000-0000-0000-0000000d0004'), 0.000000, 'the gift leaves stock');

SELECT * FROM finish();
ROLLBACK;
