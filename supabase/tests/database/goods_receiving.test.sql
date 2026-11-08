-- post_goods_receipt(): supplier deliveries, weighted average cost, packs.
BEGIN;
SELECT plan(15);

INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
    ('00000000-0000-0000-0000-00000000ee01', 'admin@t.local',   '{"name":"Admin"}', '{}'),
    ('00000000-0000-0000-0000-00000000ee02', 'cashier@t.local', '{"name":"Cashier"}', '{"account_type":"staff"}');
UPDATE public.users SET active = true WHERE id = '00000000-0000-0000-0000-00000000ee02';

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ee01","role":"authenticated"}';

CREATE TEMP TABLE s AS SELECT
    save_style('{"kind":"garment","code":"SK","name":"Kameez","variants":[
        {"sku":"SK-M","size":"M","price":4500,"cost":2000,"opening_stock":4},
        {"sku":"SK-L","size":"L","price":4500,"cost":2000}]}') AS garment,
    save_style('{"kind":"pack","code":"GIFT","name":"Gift set","variants":[{"sku":"GIFT-1","color":"Blue","price":800}]}') AS pack;
CREATE TEMP TABLE ids AS SELECT
    (SELECT id FROM product_variants WHERE sku = 'SK-M') AS m,
    (SELECT id FROM product_variants WHERE sku = 'SK-L') AS l,
    (SELECT id FROM product_variants WHERE sku = 'GIFT-1') AS pack;
GRANT SELECT ON s, ids TO authenticated;

CREATE FUNCTION pg_temp.receipt(req TEXT) RETURNS JSONB LANGUAGE sql AS $$
    SELECT post_goods_receipt(jsonb_build_object(
        'request_id', req, 'supplier_name', 'Al-Karam Textiles', 'supplier_reference', 'INV-7781',
        'lines', jsonb_build_array(
            jsonb_build_object('variant_id', (SELECT m FROM ids), 'quantity', 6, 'unit_cost', 2500),
            jsonb_build_object('variant_id', (SELECT l FROM ids), 'quantity', 3, 'unit_cost', 2400),
            jsonb_build_object('variant_id', (SELECT pack FROM ids), 'quantity', 25, 'unit_cost', 450))))
$$;
GRANT EXECUTE ON FUNCTION pg_temp.receipt(TEXT) TO authenticated;

SELECT lives_ok($$ SELECT pg_temp.receipt('00000000-0000-0000-0000-00000000f101') $$, 'manager posts a delivery');
SELECT matches((SELECT receipt_no FROM goods_receipts), '^GRN-[0-9]{6}$', 'receipt numbered');
SELECT is((SELECT total_cost FROM goods_receipts), 33450.00, 'receipt total = 6x2500 + 3x2400 + 25x450');
SELECT is((SELECT count(*)::int FROM suppliers WHERE name = 'Al-Karam Textiles'), 1, 'new supplier created by name');
SELECT is((SELECT on_hand FROM stock_balances WHERE variant_id = (SELECT m FROM ids)), 10.000000, 'garment stock received');
SELECT is((SELECT unit_cost FROM variant_costs WHERE variant_id = (SELECT m FROM ids)), 2300.0000,
          'weighted average cost: (4x2000 + 6x2500) / 10');
SELECT is((SELECT unit_cost FROM variant_costs WHERE variant_id = (SELECT l FROM ids)), 2400.0000,
          'no stock before: cost is the delivery cost');
SELECT is((SELECT on_hand FROM stock_balances WHERE variant_id = (SELECT pack FROM ids)), 25.000000, 'pack stock received');
SELECT is((SELECT count(*)::int FROM stock_movements WHERE reference_type = 'goods_receipt'), 3, 'one movement per line');

-- Retry and supplier reuse
SELECT lives_ok($$ SELECT pg_temp.receipt('00000000-0000-0000-0000-00000000f101') $$, 'retrying the same delivery is safe');
SELECT is((SELECT on_hand FROM stock_balances WHERE variant_id = (SELECT m FROM ids)), 10.000000, 'retry does not receive twice');
SELECT lives_ok($$
    SELECT post_goods_receipt(jsonb_build_object('request_id', '00000000-0000-0000-0000-00000000f102',
        'supplier_name', 'al-karam textiles',
        'lines', jsonb_build_array(jsonb_build_object('variant_id', (SELECT l FROM ids), 'quantity', 1, 'unit_cost', 2400))))
$$, 'second delivery from the same supplier');
SELECT is((SELECT count(*)::int FROM suppliers), 1, 'supplier matched by name, any capitalisation');

-- Receipts are history; cashiers have no access
RESET ROLE;
SET LOCAL "request.jwt.claims" = '';
SELECT throws_ok($$ UPDATE goods_receipts SET total_cost = 0 $$, '42501', NULL, 'receipts cannot be edited');

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ee02","role":"authenticated"}';
SELECT throws_ok($$ SELECT pg_temp.receipt('00000000-0000-0000-0000-00000000f103') $$, '42501', NULL,
                 'cashier cannot receive goods');

SELECT * FROM finish();
ROLLBACK;
