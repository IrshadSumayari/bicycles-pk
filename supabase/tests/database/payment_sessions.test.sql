BEGIN;
UPDATE public.app_settings SET online_card_enabled=true; -- Explicit opt-in for payment flow fixtures.
SELECT no_plan();
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-000000009e01','payment-admin@t.local','{"name":"Admin"}','{}'),
 ('00000000-0000-0000-0000-000000009e02','payment-a@t.local','{"name":"Customer A"}','{}'),
 ('00000000-0000-0000-0000-000000009e03','payment-b@t.local','{"name":"Customer B"}','{}');
UPDATE app_settings SET tax_rate=0,cod_enabled=true,cod_max_total=NULL,online_max_pending_orders=20,online_max_open_cod_orders=20;
INSERT INTO product_styles(id,code,name,kind,taxable,published,slug) VALUES
 ('00000000-0000-0000-0000-000000009ea1','PAYMENT-TUBE','Payment tube','item',false,true,'payment-tube');
INSERT INTO product_variants(id,style_id,sku,price,published) VALUES
 ('00000000-0000-0000-0000-000000009eb1','00000000-0000-0000-0000-000000009ea1','PAYMENT-TUBE-M',100,true);
SELECT post_stock_movement((SELECT id FROM locations WHERE code='FLOOR'),'00000000-0000-0000-0000-000000009eb1',20,'opening');
CREATE TEMP TABLE work(key TEXT PRIMARY KEY,value JSONB);
GRANT ALL ON work TO authenticated,service_role;
CREATE FUNCTION pg_temp.create_order() RETURNS JSONB LANGUAGE sql AS $$
 SELECT create_online_order(jsonb_build_object('request_id',gen_random_uuid(),'payment_method','card','fulfilment','pickup','contact_name','Customer A','phone','03009990004',
 'lines',jsonb_build_array(jsonb_build_object('variant_id','00000000-0000-0000-0000-000000009eb1','quantity',1))))
$$;
CREATE FUNCTION pg_temp.start(k TEXT,ref TEXT) RETURNS JSONB LANGUAGE sql AS $$
 SELECT initiate_online_payment(value->>'order_no','00000000-0000-0000-0000-000000009e02','mock',ref,'card') FROM work WHERE key=k
$$;
CREATE FUNCTION pg_temp.notify(k TEXT,ref TEXT,status TEXT DEFAULT 'paid',amount NUMERIC DEFAULT 100) RETURNS JSONB LANGUAGE sql AS $$
 SELECT record_online_payment_event(value->>'order_no','mock',ref,amount,'card',status,'{"source":"confirmed"}') FROM work WHERE key=k
$$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated,service_role;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009e02","role":"authenticated"}';
INSERT INTO work VALUES('paid',pg_temp.create_order()),('expired',pg_temp.create_order()),('mismatch',pg_temp.create_order()),('failed',pg_temp.create_order()),('cancelled',pg_temp.create_order());
SELECT throws_ok($$SELECT pg_temp.start('paid','SESSION-A')$$,'42501',NULL,'customer cannot initialize through service-only RPC');
SELECT throws_ok($$SELECT pg_temp.notify('paid','SESSION-A')$$,'42501',NULL,'customer cannot confirm or refund payments');
SET LOCAL ROLE service_role;
SET LOCAL "request.jwt.claims"='{"role":"service_role"}';
SELECT is(pg_temp.start('paid','SESSION-A')->>'status','initiated','checkout starts initiated');
SELECT is(pg_temp.start('paid','SESSION-A')->>'status','initiated','checkout initialization is idempotent');
SELECT throws_ok($$SELECT pg_temp.start('paid','SESSION-OTHER')$$,'P0001',NULL,'one live checkout per order');
SELECT throws_ok($$SELECT pg_temp.start('failed','SESSION-A')$$,'P0001',NULL,'provider reference cannot cross orders');
SELECT throws_ok($$SELECT initiate_online_payment((SELECT value->>'order_no' FROM work WHERE key='failed'),'00000000-0000-0000-0000-000000009e03','mock','SESSION-B','card')$$,'42501',NULL,'service initialization checks account ownership');
SELECT throws_ok($$SELECT initiate_online_payment((SELECT value->>'order_no' FROM work WHERE key='failed'),'00000000-0000-0000-0000-000000009e02','mock','SESSION-B','wallet')$$,'P0001',NULL,'method bound to order');
SELECT is(pg_temp.notify('paid','SESSION-A')->>'status','paid','initiated row advances to paid');
SELECT is(pg_temp.notify('paid','SESSION-A')->>'status','paid','duplicate confirmation is harmless');
SELECT is(pg_temp.notify('paid','SESSION-A','failed')->>'status','paid','late failed notification never downgrades payment');
SELECT is(pg_temp.notify('paid','SESSION-A','refunded')->>'status','refunded','confirmed refund is applied');
SELECT is(pg_temp.notify('paid','SESSION-A','refunded')->>'status','refunded','duplicate refund is harmless');
SELECT is(pg_temp.notify('paid','SESSION-A','paid')->>'status','refunded','late paid replay cannot resurrect refund');
SELECT is(pg_temp.start('mismatch','SESSION-MISMATCH')->>'status','initiated','mismatch fixture starts');
SELECT is(pg_temp.notify('mismatch','SESSION-MISMATCH','paid',99)->>'needs_refund','true','captured amount mismatch remains recorded for refund');
SELECT is(pg_temp.start('failed','SESSION-FAILED')->>'status','initiated','failed fixture starts');
SELECT is(pg_temp.notify('failed','SESSION-FAILED','failed')->>'status','failed','failure is recorded without placing order');
SELECT is(pg_temp.notify('failed','SESSION-FAILED','paid')->>'status','paid','confirmed payment can follow non-captured failure');
SELECT pg_temp.start('expired','SESSION-LATE');
SELECT pg_temp.start('cancelled','SESSION-CANCELLED');
RESET ROLE;
UPDATE online_orders SET expires_at=now()-interval '1 minute' WHERE id=(SELECT (value->>'id')::uuid FROM work WHERE key='expired');
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009e02","role":"authenticated"}';
SELECT cancel_my_online_order((SELECT value->>'order_no' FROM work WHERE key='cancelled'));
SET LOCAL ROLE service_role;
SET LOCAL "request.jwt.claims"='{"role":"service_role"}';
SELECT is(pg_temp.notify('expired','SESSION-LATE')->>'needs_refund','true','initiated payment arriving after expiry is flagged');
SELECT is(pg_temp.notify('cancelled','SESSION-CANCELLED')->>'needs_refund','true','initiated payment arriving after cancellation is flagged');
SELECT throws_ok($$SELECT pg_temp.start('expired','SESSION-NEW')$$,'P0001',NULL,'cannot create expired checkout');
RESET ROLE;
SET LOCAL "request.jwt.claims"='';
SELECT is((SELECT count(*)::int FROM online_payments WHERE provider_ref='SESSION-A'),1,'initiated row updated, not duplicated');
SELECT is((SELECT count(*)::int FROM online_order_events WHERE order_id=(SELECT (value->>'id')::uuid FROM work WHERE key='paid') AND event='paid'),1,'one paid event');
SELECT is((SELECT count(*)::int FROM online_order_events WHERE order_id=(SELECT (value->>'id')::uuid FROM work WHERE key='paid') AND event='refunded'),1,'one refund event');
SELECT is((SELECT payment_status FROM online_orders WHERE id=(SELECT (value->>'id')::uuid FROM work WHERE key='paid')),'refunded','refund updates order payment state');
SELECT ok((SELECT status='pending_payment' AND payment_status='unpaid' FROM online_orders WHERE id=(SELECT (value->>'id')::uuid FROM work WHERE key='mismatch')),'mismatch never places order');
SELECT is((SELECT status FROM online_orders WHERE id=(SELECT (value->>'id')::uuid FROM work WHERE key='expired')),'expired','late notification expires order before cron');
SELECT is((SELECT amount FROM online_payments WHERE provider_ref='SESSION-MISMATCH'),99.00,'actual captured mismatch amount retained');
SET LOCAL ROLE service_role;
SET LOCAL "request.jwt.claims"='{"role":"service_role"}';
SELECT is(pg_temp.notify('mismatch','SESSION-MISMATCH','refunded',99)->>'status','refunded','provider refund matches actual mismatched capture, not expected order total');
RESET ROLE;
SET LOCAL "request.jwt.claims"='';
SELECT ok((SELECT NOT needs_refund FROM online_payments WHERE provider_ref='SESSION-MISMATCH'),'confirmed refund clears mismatch review flag');
SELECT ok(NOT has_function_privilege('anon','public.initiate_online_payment(text,uuid,text,text,text)','EXECUTE'),'anon cannot initialize');
SELECT ok(NOT has_function_privilege('authenticated','public.record_online_payment_event(text,text,text,numeric,text,text,jsonb)','EXECUTE'),'staff cannot fake provider events');
SELECT * FROM finish();
ROLLBACK;
