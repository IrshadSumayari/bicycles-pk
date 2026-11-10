-- Cash shifts: cash needs an open shift, movements, close with variance.
BEGIN;
SELECT plan(16);

INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
    ('00000000-0000-0000-0000-00000000ab01', 'admin@t.local',   '{"name":"Admin"}', '{}'),
    ('00000000-0000-0000-0000-00000000ab02', 'cashier@t.local', '{"name":"Cashier"}', '{"account_type":"staff"}'),
    ('00000000-0000-0000-0000-00000000ab03', 'cashier2@t.local', '{"name":"Cashier Two"}', '{"account_type":"staff"}');
UPDATE public.users SET active = true WHERE id IN ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ab03');

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ab01","role":"authenticated"}';
CREATE TEMP TABLE s AS SELECT save_style('{"kind":"item","code":"SK","name":"City bike","variants":[
    {"sku":"SK-M","size":"M","price":1000,"opening_stock":10}]}') AS id;
CREATE TEMP TABLE v AS SELECT id FROM product_variants WHERE sku = 'SK-M';
GRANT SELECT ON s, v TO authenticated;

CREATE FUNCTION pg_temp.sell(req TEXT, pays JSONB) RETURNS JSONB LANGUAGE sql AS $$
    SELECT post_sale(jsonb_build_object('request_id', req,
        'lines', jsonb_build_array(jsonb_build_object('variant_id', (SELECT id FROM v), 'quantity', 1)),
        'payments', pays))
$$;
GRANT EXECUTE ON FUNCTION pg_temp.sell(TEXT, JSONB) TO authenticated;

-- Cashier without a shift
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ab02","role":"authenticated"}';
SELECT is(current_cash_session(), NULL, 'no shift open yet');
SELECT throws_ok($$ SELECT pg_temp.sell('00000000-0000-0000-0000-0000000a0001', '[{"method":"cash"}]') $$,
                 'P0001', 'Open a cash shift before taking or refunding cash', 'cash needs an open shift');
SELECT lives_ok($$ SELECT pg_temp.sell('00000000-0000-0000-0000-0000000a0002', '[{"method":"card","card_last4":"4242"}]') $$,
                'card sales do not need a shift');

-- Open, sell, move cash
SELECT is((open_cash_session(5000)->'session'->>'opening_float')::numeric, 5000.00, 'shift opened with a float');
SELECT is((open_cash_session(9999)->'session'->>'opening_float')::numeric, 5000.00, 'opening again returns the open shift');
SELECT lives_ok($$ SELECT pg_temp.sell('00000000-0000-0000-0000-0000000a0003', '[{"method":"cash","tendered":2000}]') $$,
                'cash sale with change');
SELECT lives_ok($$ SELECT pg_temp.sell('00000000-0000-0000-0000-0000000a0004',
                  '[{"method":"cash","amount":400},{"method":"digital","amount":600,"reference":"JC-123"}]') $$,
                'split cash and digital');
SELECT lives_ok($$ SELECT record_cash_movement(-300, 'Tea and snacks') $$, 'cash out with a reason');
SELECT throws_ok($$ SELECT record_cash_movement(100, ' ') $$, NULL, NULL, 'cash movements need a reason');
SELECT throws_ok($$ SELECT record_cash_movement(-99999, 'Bank deposit') $$, NULL, NULL, 'cannot take out more than the drawer holds');

SELECT is(
    (SELECT jsonb_build_object('sales', x->'cash_sales', 'out', x->'cash_out', 'expected', x->'expected_cash',
                               'digital', x->'other_payments'->'digital', 'card', x->'other_payments'->'card')
     FROM current_cash_session() x),
    '{"sales": 1400.00, "out": 300.00, "expected": 6100.00, "digital": 600.00, "card": 1000.00}'::jsonb,
    'summary: cash sales net of change, cash out, expected cash and other tenders'
);

-- Another cashier cannot see this shift
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ab03","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM cash_sessions), 0, 'cashiers see only their own shifts');

-- Close
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ab02","role":"authenticated"}';
SELECT throws_ok($$ SELECT close_cash_session(6000) $$, NULL, NULL, 'a variance needs a note');
SELECT is((close_cash_session(6000, 'Short 100, checked twice')->'session'->>'variance')::numeric, -100.00,
          'closed with the variance recorded');
SELECT is(current_cash_session(), NULL, 'no shift open after closing');

-- Manager sees all shifts
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ab01","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM cash_sessions), 1, 'back office sees every shift');

SELECT * FROM finish();
ROLLBACK;
