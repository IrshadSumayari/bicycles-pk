-- Review fixes: open-order limits per website account, and gateway payments kept
-- out of the packer's cash shift summary.
BEGIN;
UPDATE public.app_settings SET online_card_enabled=true; -- Explicit opt-in for payment flow fixtures.
SELECT plan(9);
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-00000000a101','guard-admin@t.local','{"name":"Admin"}','{}'),
 ('00000000-0000-0000-0000-00000000a102','guard-cashier@t.local','{"name":"Cashier"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000a103','guard-customer@t.local','{"name":"Customer"}','{}');
UPDATE users SET active=true WHERE id='00000000-0000-0000-0000-00000000a102';
UPDATE app_settings SET tax_rate=0,cod_enabled=true,cod_max_total=NULL,online_max_pending_orders=3,online_max_open_cod_orders=3;
INSERT INTO product_styles(id,code,name,kind,unit,taxable,published,slug) VALUES
 ('00000000-0000-0000-0000-00000000a1a1','GUARD-TUBE','Guard tube','item','piece',false,true,'guard-tube');
INSERT INTO product_variants(id,style_id,sku,price,published) VALUES
 ('00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000a1a1','GUARD-TUBE-M',100,true);
SELECT post_stock_movement((SELECT id FROM locations WHERE code='FLOOR'),'00000000-0000-0000-0000-00000000a1b1',50,'opening');

CREATE TEMP TABLE work(key TEXT PRIMARY KEY,value JSONB);
GRANT ALL ON work TO authenticated,service_role;
CREATE FUNCTION pg_temp.place(method TEXT) RETURNS JSONB LANGUAGE sql AS $$
 SELECT create_online_order(jsonb_build_object('request_id',gen_random_uuid(),'payment_method',method,'fulfilment','pickup',
  'contact_name','Guard Customer','phone','03004441100',
  'lines',jsonb_build_array(jsonb_build_object('variant_id','00000000-0000-0000-0000-00000000a1b1','quantity',1))))
$$;
CREATE FUNCTION pg_temp.advance(k TEXT,s TEXT) RETURNS JSONB LANGUAGE sql AS $$
 SELECT advance_online_order(jsonb_build_object('id',(SELECT (value->>'id')::uuid FROM work WHERE key=k),'status',s,'request_id',gen_random_uuid()))
$$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated,service_role;

-- 1. Orders waiting for payment are limited per account
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000a103","role":"authenticated"}';
INSERT INTO work VALUES('card1',pg_temp.place('card')),('card2',pg_temp.place('card')),('card3',pg_temp.place('card'));
SELECT throws_ok($$SELECT pg_temp.place('card')$$,'P0001',
 'You already have 3 orders waiting for payment. Please complete or cancel one first.','fourth unpaid order refused');
RESET ROLE;
UPDATE online_orders SET expires_at=now()-interval '1 minute' WHERE id=(SELECT (value->>'id')::uuid FROM work WHERE key='card3');
SET LOCAL ROLE authenticated;
SELECT lives_ok($$SELECT pg_temp.place('card')$$,'an expired hold no longer counts toward the limit');

-- 2. Open cash-on-delivery orders are limited per account
INSERT INTO work VALUES('cod1',pg_temp.place('cod')),('cod2',pg_temp.place('cod')),('cod3',pg_temp.place('cod'));
SELECT throws_ok($$SELECT pg_temp.place('cod')$$,'P0001',
 'You already have 3 cash-on-delivery orders waiting. Please wait until the shop has packed them, or contact the shop.','fourth open COD order refused');
SELECT is(cancel_my_online_order((SELECT value->>'order_no' FROM work WHERE key='cod3'))->>'status','cancelled','customer cancels one COD order');
SELECT lives_ok($$SELECT pg_temp.place('cod')$$,'a cancelled COD order frees a place');

-- 3. A gateway payment packed by a cashier stays out of the cashier's shift
SET LOCAL ROLE service_role;
SET LOCAL "request.jwt.claims"='{"role":"service_role"}';
SELECT is(mark_online_order_paid((SELECT value->>'order_no' FROM work WHERE key='card1'),'mock','guard-ref-1',100,'card','{}')->>'status','paid','card order paid online');
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000a102","role":"authenticated"}';
SELECT FROM open_cash_session(0);
SELECT FROM pg_temp.advance('card1','confirmed');
SELECT FROM pg_temp.advance('card1','packed');
SELECT is(coalesce(current_cash_session()->'other_payments'->>'card','none'),'none','packing a gateway-paid order adds nothing to the shift');

-- 4. A card payment taken at the counter for a COD order still counts
SELECT FROM pg_temp.advance('cod1','confirmed');
SELECT FROM pg_temp.advance('cod1','packed');
SELECT FROM pg_temp.advance('cod1','ready_for_pickup');
SELECT is(collect_cod_payment(jsonb_build_object('id',(SELECT (value->>'id')::uuid FROM work WHERE key='cod1'),'request_id',gen_random_uuid(),
 'payments',jsonb_build_array(jsonb_build_object('method','card','amount',100,'card_last4','4242'))))->>'payment_status','paid','COD paid by card at pickup');
SELECT is((current_cash_session()->'other_payments'->>'card')::numeric,100::numeric,'counter card payment for COD is in the shift');

SELECT * FROM finish();
ROLLBACK;
