-- Last-unit ordering regressions. pgTAP runs in one session; these assertions do
-- not substitute for the following real two-session check (also run manually).
-- Prepare two published variants, each with exactly one unit at FLOOR, a website
-- customer and an active cashier. Use different variants for the two directions.
-- Session A: BEGIN; set authenticated customer JWT; create_online_order for unit A;
--            leave the transaction open (SELECT pg_sleep(2)), then COMMIT.
-- Session B, while A is open: BEGIN; set cashier JWT; post_sale of unit A with a
--            card payment. It waits on A's balance lock, then is refused for stock.
-- Reverse: A posts a card till sale for unit B and holds before COMMIT; B attempts
--            create_online_order for B. B waits, then gets '<item> is sold out'.
-- Verify A: on_hand=1, reserved=1, one order/no sale. B: on_hand=0, reserved=0,
-- one till sale/no order. The losing transaction must not leave a reservation.
-- Each session uses psql -v ON_ERROR_STOP=1; exit/disconnect rolls back the loser.
BEGIN;
UPDATE public.app_settings SET online_card_enabled=true; -- Explicit opt-in for payment flow fixtures.
SELECT no_plan();
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-000000009d01','order-race-admin@t.local','{"name":"Admin"}','{}'),
 ('00000000-0000-0000-0000-000000009d02','order-race-cashier@t.local','{"name":"Cashier"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-000000009d03','order-race-customer@t.local','{"name":"Customer"}','{}');
UPDATE users SET active=true WHERE id='00000000-0000-0000-0000-000000009d02';
UPDATE app_settings SET tax_rate=0,cod_enabled=true,cod_max_total=NULL;
INSERT INTO product_styles(id,code,name,kind,published,slug,taxable) VALUES
 ('00000000-0000-0000-0000-000000009da1','RACE-ONLINE','Online last unit','garment',true,'race-online',false),
 ('00000000-0000-0000-0000-000000009da2','RACE-TILL','Till last unit','garment',true,'race-till',false);
INSERT INTO product_variants(id,style_id,sku,price,published) VALUES
 ('00000000-0000-0000-0000-000000009db1','00000000-0000-0000-0000-000000009da1','RACE-ONLINE-1',100,true),
 ('00000000-0000-0000-0000-000000009db2','00000000-0000-0000-0000-000000009da2','RACE-TILL-1',100,true);
SELECT post_stock_movement((SELECT id FROM locations WHERE code='FLOOR'),'00000000-0000-0000-0000-000000009db1',1,'opening');
SELECT post_stock_movement((SELECT id FROM locations WHERE code='FLOOR'),'00000000-0000-0000-0000-000000009db2',1,'opening');
CREATE FUNCTION pg_temp.web(v UUID) RETURNS JSONB LANGUAGE sql AS $$
 SELECT create_online_order(jsonb_build_object('request_id',gen_random_uuid(),'fulfilment','pickup','payment_method','cod','contact_name','Race customer','phone','03009990002',
 'lines',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',1))))
$$;
CREATE FUNCTION pg_temp.till(v UUID) RETURNS JSONB LANGUAGE sql AS $$
 SELECT post_sale(jsonb_build_object('request_id',gen_random_uuid(),'lines',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',1)),
 'payments',jsonb_build_array(jsonb_build_object('method','card'))))
$$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009d03","role":"authenticated"}';
SELECT lives_ok($$SELECT pg_temp.web('00000000-0000-0000-0000-000000009db1')$$,'website reserves last unit');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009d02","role":"authenticated"}';
SELECT throws_ok($$SELECT pg_temp.till('00000000-0000-0000-0000-000000009db1')$$,'P0001',NULL,'till cannot sell website-held unit');
SELECT lives_ok($$SELECT pg_temp.till('00000000-0000-0000-0000-000000009db2')$$,'till sells other last unit');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009d03","role":"authenticated"}';
SELECT throws_ok($$SELECT pg_temp.web('00000000-0000-0000-0000-000000009db2')$$,'P0001','Till last unit is sold out','website cannot reserve till-sold unit');
RESET ROLE;
SET LOCAL "request.jwt.claims"='';
SELECT is((SELECT sum(on_hand) FROM stock_balances WHERE variant_id='00000000-0000-0000-0000-000000009db1'),1.000000,'held stock remains physical');
SELECT is((SELECT sum(reserved) FROM stock_balances WHERE variant_id='00000000-0000-0000-0000-000000009db1'),1.000000,'last unit reserved once');
SELECT is((SELECT sum(on_hand) FROM stock_balances WHERE variant_id='00000000-0000-0000-0000-000000009db2'),0.000000,'till sale deducts last unit');
SELECT is((SELECT sum(reserved) FROM stock_balances WHERE variant_id='00000000-0000-0000-0000-000000009db2'),0.000000,'losing reservation leaves no hold');
SELECT is((SELECT count(*)::int FROM online_orders WHERE account_id='00000000-0000-0000-0000-000000009d03'),1,'failed order rolls back completely');
SELECT is((SELECT count(*)::int FROM sales WHERE cashier_id='00000000-0000-0000-0000-000000009d02'),1,'failed till sale rolls back completely');
SELECT * FROM finish();
ROLLBACK;
