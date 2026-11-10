-- Stock counts: system quantity captured at count time, manager approval posts differences.
BEGIN;
SELECT plan(13);

INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
    ('00000000-0000-0000-0000-00000000ff01', 'admin@t.local',   '{"name":"Admin"}', '{}'),
    ('00000000-0000-0000-0000-00000000ff02', 'cashier@t.local', '{"name":"Cashier"}', '{"account_type":"staff"}');
UPDATE public.users SET active = true WHERE id = '00000000-0000-0000-0000-00000000ff02';

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ff01","role":"authenticated"}';

CREATE TEMP TABLE s AS SELECT
    save_style('{"kind":"item","code":"SK","name":"City bike","variants":[
        {"sku":"SK-M","size":"M","price":4500,"opening_stock":5},
        {"sku":"SK-L","size":"L","price":4500,"opening_stock":3}]}') AS item,
    save_style('{"kind":"pack","code":"GIFT","name":"Gift set","variants":[{"sku":"GIFT-1","price":800,"opening_stock":20}]}') AS pack;
CREATE TEMP TABLE ids AS SELECT
    (SELECT id FROM product_variants WHERE sku = 'SK-M') AS m,
    (SELECT id FROM product_variants WHERE sku = 'SK-L') AS l,
    (SELECT id FROM product_variants WHERE sku = 'GIFT-1') AS pack;
CREATE TEMP TABLE c AS SELECT (start_stock_count()).id AS id;
GRANT SELECT ON s, ids, c TO authenticated;

CREATE FUNCTION pg_temp.on_hand(sku TEXT) RETURNS NUMERIC LANGUAGE sql AS
$$ SELECT b.on_hand FROM stock_balances b JOIN product_variants v ON v.id = b.variant_id WHERE v.sku = $1 $$;
GRANT EXECUTE ON FUNCTION pg_temp.on_hand(TEXT) TO authenticated;

SELECT matches((SELECT count_no FROM stock_counts WHERE id = (SELECT id FROM c)), '^CNT-\d{6}$', 'count numbered');
SELECT throws_ok($$ SELECT start_stock_count() $$, NULL, NULL, 'only one open count per location');

-- Cashier counts
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ff02","role":"authenticated"}';
SELECT FROM open_cash_session(0);
SELECT lives_ok($$ SELECT record_stock_count((SELECT id FROM c), (SELECT m FROM ids), 4) $$, 'cashier records a count');
SELECT lives_ok($$ SELECT record_stock_count((SELECT id FROM c), (SELECT pack FROM ids), 19) $$,
                'packs counted as sets');
SELECT throws_ok($$ SELECT record_stock_count((SELECT id FROM c), (SELECT l FROM ids), 2.5) $$, NULL, NULL,
                 'pieces are counted in whole numbers');
SELECT throws_ok($$ SELECT approve_stock_count((SELECT id FROM c)) $$, '42501', NULL, 'cashier cannot approve');

-- A sale between counting and approval
SELECT lives_ok($$
    SELECT post_sale(jsonb_build_object('request_id', '00000000-0000-0000-0000-00000000c001',
        'lines', jsonb_build_array(jsonb_build_object('variant_id', (SELECT m FROM ids), 'quantity', 1)),
        'payments', jsonb_build_array(jsonb_build_object('method', 'cash'))))
$$, 'a sale happens before approval');

-- Manager approves
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ff01","role":"authenticated"}';
SELECT is((approve_stock_count((SELECT id FROM c))->>'changed_lines')::int, 2, 'two differences posted');
SELECT is(pg_temp.on_hand('SK-M'), 3.000000, 'count difference (-1) applied on top of the later sale (-1)');
SELECT is(pg_temp.on_hand('SK-L'), 3.000000, 'items not counted are untouched');
SELECT is(pg_temp.on_hand('GIFT-1'), 19.000000, 'pack count corrected');
SELECT is((approve_stock_count((SELECT id FROM c))->>'already_approved')::boolean, true, 'approving twice is a no-op');
SELECT throws_ok($$ SELECT record_stock_count((SELECT id FROM c), (SELECT l FROM ids), 1) $$, NULL, NULL,
                 'an approved count is closed');

SELECT * FROM finish();
ROLLBACK;
