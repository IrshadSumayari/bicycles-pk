-- Returns and exchanges.
BEGIN;
SELECT plan(25);

INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
    ('00000000-0000-0000-0000-00000000bc01', 'admin@t.local',   '{"name":"Admin"}', '{}'),
    ('00000000-0000-0000-0000-00000000bc02', 'cashier@t.local', '{"name":"Cashier"}', '{"account_type":"staff"}');
UPDATE public.users SET active = true WHERE id = '00000000-0000-0000-0000-00000000bc02';
UPDATE public.app_settings SET tax_rate = 10, max_cashier_discount_percent = 20;

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000bc01","role":"authenticated"}';
SELECT FROM save_style('{"kind":"garment","code":"SK","name":"Kameez","variants":[
    {"sku":"SK-M","size":"M","price":1000,"opening_stock":10},
    {"sku":"SK-L","size":"L","price":1000,"opening_stock":10},
    {"sku":"SK-XL","size":"XL","price":1500,"opening_stock":10}]}');
SELECT FROM save_style('{"kind":"pack","code":"GIFT","name":"Gift set","variants":[{"sku":"GIFT-1","price":800,"opening_stock":20}]}');
CREATE TEMP TABLE ids AS SELECT
    (SELECT id FROM product_variants WHERE sku = 'SK-M') AS m,
    (SELECT id FROM product_variants WHERE sku = 'SK-L') AS l,
    (SELECT id FROM product_variants WHERE sku = 'SK-XL') AS xl,
    (SELECT id FROM product_variants WHERE sku = 'GIFT-1') AS pack;
GRANT SELECT ON ids TO authenticated;

CREATE FUNCTION pg_temp.stock(v UUID) RETURNS NUMERIC LANGUAGE sql AS $$ SELECT sum(on_hand) FROM stock_balances WHERE variant_id = v $$;
CREATE FUNCTION pg_temp.line(req TEXT, v UUID) RETURNS UUID LANGUAGE sql AS
$$ SELECT sl.id FROM sale_lines sl JOIN sales s ON s.id = sl.sale_id WHERE s.request_id = req::uuid AND sl.variant_id = v $$;
CREATE FUNCTION pg_temp.sale(req TEXT) RETURNS UUID LANGUAGE sql AS $$ SELECT id FROM sales WHERE request_id = req::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.stock(UUID), pg_temp.line(TEXT, UUID), pg_temp.sale(TEXT) TO authenticated;

-- Cashier sells 3 x M with a 10% discount (net 2700 + tax 270 = 2970) and 2 gift sets
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000bc02","role":"authenticated"}';
SELECT FROM open_cash_session(10000);
SELECT FROM post_sale(jsonb_build_object('request_id', '00000000-0000-0000-0000-0000000b0001',
    'lines', jsonb_build_array(
        jsonb_build_object('variant_id', (SELECT m FROM ids), 'quantity', 3, 'discount_type', 'percentage', 'discount_value', 10),
        jsonb_build_object('variant_id', (SELECT pack FROM ids), 'quantity', 2)),
    'payments', jsonb_build_array(jsonb_build_object('method', 'cash'))));
SELECT is(pg_temp.stock((SELECT m FROM ids)), 7.000000, 'sold 3 M');

-- What can be returned
SELECT is((SELECT (x->>'returnable')::numeric FROM jsonb_array_elements(sale_returnable(pg_temp.sale('00000000-0000-0000-0000-0000000b0001'))) x
           WHERE x->>'variant_id' = (SELECT m FROM ids)::text), 3.000000, 'all 3 returnable');

-- Return 1 M for cash: refund is what was paid for one (990), not the shelf price
SELECT is((post_return(jsonb_build_object('request_id', '00000000-0000-0000-0000-0000000b0101',
    'sale_id', pg_temp.sale('00000000-0000-0000-0000-0000000b0001'), 'reason', 'Too small', 'refund_method', 'cash',
    'lines', jsonb_build_array(jsonb_build_object('sale_line_id', pg_temp.line('00000000-0000-0000-0000-0000000b0001', (SELECT m FROM ids)), 'quantity', 1))))
    ->'return'->>'refund_total')::numeric, 990.00, 'refund = discounted price + tax');
SELECT is(pg_temp.stock((SELECT m FROM ids)), 8.000000, 'returned item restocked');
SELECT is((current_cash_session()->>'cash_refunds')::numeric, 990.00, 'cash refund came out of the shift');
SELECT matches((SELECT return_no FROM returns LIMIT 1), '^RTN-\d{6}$', 'return numbered');

-- Retry and limits
SELECT lives_ok($$ SELECT post_return(jsonb_build_object('request_id', '00000000-0000-0000-0000-0000000b0101',
    'sale_id', pg_temp.sale('00000000-0000-0000-0000-0000000b0001'), 'reason', 'Too small',
    'lines', jsonb_build_array(jsonb_build_object('sale_line_id', pg_temp.line('00000000-0000-0000-0000-0000000b0001', (SELECT m FROM ids)), 'quantity', 1)))) $$,
    'retrying a return is safe');
SELECT is((SELECT count(*)::int FROM returns), 1, 'retry did not create a second return');
SELECT throws_ok($$ SELECT post_return(jsonb_build_object('request_id', '00000000-0000-0000-0000-0000000b0102',
    'sale_id', pg_temp.sale('00000000-0000-0000-0000-0000000b0001'), 'reason', 'More',
    'lines', jsonb_build_array(jsonb_build_object('sale_line_id', pg_temp.line('00000000-0000-0000-0000-0000000b0001', (SELECT m FROM ids)), 'quantity', 3)))) $$,
    NULL, NULL, 'cannot return more than is left');
SELECT throws_ok($$ SELECT post_return(jsonb_build_object('request_id', '00000000-0000-0000-0000-0000000b0103',
    'sale_id', pg_temp.sale('00000000-0000-0000-0000-0000000b0001'), 'reason', ' ',
    'lines', jsonb_build_array(jsonb_build_object('sale_line_id', pg_temp.line('00000000-0000-0000-0000-0000000b0001', (SELECT m FROM ids)), 'quantity', 1)))) $$,
    NULL, NULL, 'a reason is required');

-- Damaged: refunded, not restocked
SELECT lives_ok($$ SELECT post_return(jsonb_build_object('request_id', '00000000-0000-0000-0000-0000000b0105',
    'sale_id', pg_temp.sale('00000000-0000-0000-0000-0000000b0001'), 'reason', 'Torn seam', 'refund_method', 'cash',
    'lines', jsonb_build_array(jsonb_build_object('sale_line_id', pg_temp.line('00000000-0000-0000-0000-0000000b0001', (SELECT m FROM ids)),
                                                  'quantity', 1, 'condition', 'damaged')))) $$, 'damaged return');
SELECT is(pg_temp.stock((SELECT m FROM ids)), 8.000000, 'damaged item not restocked');

-- The last unit gets the remainder: 3 returns of one always add up to the line total
SELECT is((post_return(jsonb_build_object('request_id', '00000000-0000-0000-0000-0000000b0106',
    'sale_id', pg_temp.sale('00000000-0000-0000-0000-0000000b0001'), 'reason', 'Wrong colour', 'refund_method', 'cash',
    'lines', jsonb_build_array(jsonb_build_object('sale_line_id', pg_temp.line('00000000-0000-0000-0000-0000000b0001', (SELECT m FROM ids)), 'quantity', 1))))
    ->'return'->>'refund_total')::numeric, 990.00, 'third unit refunded');
SELECT is((SELECT sum(refund_amount) FROM return_lines), 2970.00, 'returns of the whole line equal what was paid');

-- Manager returns the gift sets
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000bc01","role":"authenticated"}';
SELECT FROM open_cash_session(5000);
SELECT lives_ok($$ SELECT post_return(jsonb_build_object('request_id', '00000000-0000-0000-0000-0000000b0107',
    'sale_id', pg_temp.sale('00000000-0000-0000-0000-0000000b0001'), 'reason', 'Shade mismatch', 'refund_method', 'cash',
    'lines', jsonb_build_array(jsonb_build_object('sale_line_id', pg_temp.line('00000000-0000-0000-0000-0000000b0001', (SELECT pack FROM ids)), 'quantity', 2)))) $$,
    'manager returns the gift sets');
SELECT is(pg_temp.stock((SELECT pack FROM ids)), 20.000000, 'gift sets restocked');
SELECT is((SELECT status FROM sales WHERE id = pg_temp.sale('00000000-0000-0000-0000-0000000b0001')), 'refunded', 'fully returned sale is marked refunded');

-- Exchanges
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000bc02","role":"authenticated"}';
SELECT FROM post_sale(jsonb_build_object('request_id', '00000000-0000-0000-0000-0000000b0002',
    'lines', jsonb_build_array(jsonb_build_object('variant_id', (SELECT m FROM ids), 'quantity', 1)),
    'payments', jsonb_build_array(jsonb_build_object('method', 'card', 'card_last4', '4242'))));

-- M (1100 paid) for XL (1650): customer pays 550
SELECT is((post_exchange(jsonb_build_object('request_id', '00000000-0000-0000-0000-0000000b0201',
    'sale_id', pg_temp.sale('00000000-0000-0000-0000-0000000b0002'), 'reason', 'Size exchange',
    'return_lines', jsonb_build_array(jsonb_build_object('sale_line_id', pg_temp.line('00000000-0000-0000-0000-0000000b0002', (SELECT m FROM ids)), 'quantity', 1)),
    'new_lines', jsonb_build_array(jsonb_build_object('variant_id', (SELECT xl FROM ids), 'quantity', 1)),
    'payments', jsonb_build_array(jsonb_build_object('method', 'cash')))) ->> 'customer_paid')::numeric,
    550.00, 'exchange for a dearer size: customer pays the difference');
SELECT is((SELECT sum(amount) FROM payments p JOIN sales s ON s.id = p.sale_id
           WHERE s.notes LIKE 'Exchange for%' AND p.method = 'exchange'), 1100.00, 'new sale paid first with the exchange credit');
SELECT is(pg_temp.stock((SELECT xl FROM ids)), 9.000000, 'XL left stock');
SELECT is(pg_temp.stock((SELECT m FROM ids)), 9.000000, 'exchanged M came back to stock');

-- XL (1650) for L (1100): customer gets 550 back
SELECT is((post_exchange(jsonb_build_object('request_id', '00000000-0000-0000-0000-0000000b0202',
    'sale_id', (SELECT exchange_sale_id FROM returns WHERE exchange_sale_id IS NOT NULL), 'reason', 'Too big',
    'return_lines', jsonb_build_array(jsonb_build_object('sale_line_id',
        (SELECT sl.id FROM sale_lines sl JOIN returns r ON r.exchange_sale_id = sl.sale_id), 'quantity', 1)),
    'new_lines', jsonb_build_array(jsonb_build_object('variant_id', (SELECT l FROM ids), 'quantity', 1)),
    'refund_method', 'cash')) ->> 'refunded')::numeric,
    550.00, 'exchange for a cheaper item: difference refunded');

-- Exchange credit cannot be used directly
SELECT throws_ok($$ SELECT post_sale(jsonb_build_object('request_id', '00000000-0000-0000-0000-0000000b0003',
    'lines', jsonb_build_array(jsonb_build_object('variant_id', (SELECT m FROM ids), 'quantity', 1)),
    'payments', jsonb_build_array(jsonb_build_object('method', 'exchange')))) $$,
    '42501', 'Exchange credit can only be used through an exchange', 'exchange tender is blocked at the till');

-- Records are history
RESET ROLE;
SET LOCAL "request.jwt.claims" = '';
SELECT throws_ok($$ DELETE FROM return_lines $$, '42501', NULL, 'return lines cannot be deleted');
SELECT throws_ok($$ DELETE FROM returns $$, '42501', NULL, 'returns cannot be deleted');

SELECT * FROM finish();
ROLLBACK;
