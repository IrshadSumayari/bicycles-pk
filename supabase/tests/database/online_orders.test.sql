BEGIN;
UPDATE public.app_settings SET online_card_enabled=true; -- Explicit opt-in for payment flow fixtures.
SELECT no_plan();
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-000000009a01','orders-admin@t.local','{"name":"Private Admin"}','{}'),
 ('00000000-0000-0000-0000-000000009a02','orders-cashier@t.local','{"name":"Private Cashier"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-000000009a03','orders-a@t.local','{"name":"Customer A"}','{}'),
 ('00000000-0000-0000-0000-000000009a04','orders-b@t.local','{"name":"Customer B"}','{}'),
 ('00000000-0000-0000-0000-000000009a05','orders-inactive@t.local','{"name":"Inactive"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-000000009a06','orders-manager@t.local','{"name":"Manager"}','{"account_type":"staff"}');
UPDATE users SET active=true WHERE id IN ('00000000-0000-0000-0000-000000009a02','00000000-0000-0000-0000-000000009a05','00000000-0000-0000-0000-000000009a06');
UPDATE users SET role='cashier',active=false WHERE id='00000000-0000-0000-0000-000000009a05';
UPDATE users SET role='manager' WHERE id='00000000-0000-0000-0000-000000009a06';
UPDATE app_settings SET tax_rate=17,delivery_fee=250,free_delivery_over=NULL,cod_max_total=NULL,cod_enabled=true,online_max_pending_orders=20,online_max_open_cod_orders=20;
INSERT INTO product_styles(id,code,name,kind,unit,taxable,published,slug) VALUES
 ('00000000-0000-0000-0000-000000009aa1','ORDER-TUBE','Order tube','item','piece',true,true,'order-tube'),
 ('00000000-0000-0000-0000-000000009aa2','ORDER-LAST','Last scarf','item','piece',false,true,'order-last'),
 ('00000000-0000-0000-0000-000000009aa3','ORDER-HIDDEN','Hidden tube','item','piece',false,false,NULL),
 ('00000000-0000-0000-0000-000000009aa4','ORDER-PACK','Order gift set','pack','set',false,true,'order-pack');
INSERT INTO product_variants(id,style_id,sku,price,published) VALUES
 ('00000000-0000-0000-0000-000000009ab1','00000000-0000-0000-0000-000000009aa1','ORDER-TUBE-M',100.05,true),
 ('00000000-0000-0000-0000-000000009ab2','00000000-0000-0000-0000-000000009aa2','ORDER-LAST-1',50,true),
 ('00000000-0000-0000-0000-000000009ab3','00000000-0000-0000-0000-000000009aa3','ORDER-HIDDEN-1',90,true),
 ('00000000-0000-0000-0000-000000009ab4','00000000-0000-0000-0000-000000009aa4','ORDER-PACK-1',80,true);
INSERT INTO variant_costs(variant_id,unit_cost) VALUES('00000000-0000-0000-0000-000000009ab1',40);
SELECT post_stock_movement((SELECT id FROM locations WHERE code='FLOOR'),'00000000-0000-0000-0000-000000009ab1',40,'opening');
SELECT post_stock_movement((SELECT id FROM locations WHERE code='STOCK'),'00000000-0000-0000-0000-000000009ab1',60,'opening');
SELECT post_stock_movement((SELECT id FROM locations WHERE code='FLOOR'),'00000000-0000-0000-0000-000000009ab2',1,'opening');
SELECT post_stock_movement((SELECT id FROM locations WHERE code='FLOOR'),'00000000-0000-0000-0000-000000009ab4',10,'opening');
CREATE TEMP TABLE work(key TEXT PRIMARY KEY,value JSONB);
GRANT ALL ON work TO authenticated,service_role,anon;
CREATE FUNCTION pg_temp.cart(v UUID DEFAULT '00000000-0000-0000-0000-000000009ab1',qty INT DEFAULT 1,fulfil TEXT DEFAULT 'pickup') RETURNS JSONB LANGUAGE sql AS $$
 SELECT jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',qty,'price',0,'unit_price',0)),'fulfilment',fulfil,'total',0)
$$;
CREATE FUNCTION pg_temp.order_payload(method TEXT DEFAULT 'card',v UUID DEFAULT '00000000-0000-0000-0000-000000009ab1',fulfil TEXT DEFAULT 'pickup',qty INT DEFAULT 1,k UUID DEFAULT gen_random_uuid()) RETURNS JSONB LANGUAGE sql AS $$
 SELECT pg_temp.cart(v,qty,fulfil)||jsonb_build_object('request_id',k,'payment_method',method,'contact_name','Customer A','phone','03009990001',
 'address',jsonb_build_object('line1','12 Main Road','city','Lahore'),'notes_customer','Please call before delivery')
$$;
CREATE FUNCTION pg_temp.order_id(k TEXT) RETURNS UUID LANGUAGE sql AS $$ SELECT (value->>'id')::uuid FROM work WHERE key=k $$;
CREATE FUNCTION pg_temp.advance(k TEXT,s TEXT,r UUID DEFAULT gen_random_uuid()) RETURNS JSONB LANGUAGE sql AS $$
 SELECT advance_online_order(jsonb_build_object('id',pg_temp.order_id(k),'status',s,'request_id',r,'courier','Courier','tracking_no','TRACK-001'))
$$;
CREATE FUNCTION pg_temp.notify(k TEXT,ref TEXT,method TEXT DEFAULT 'card',amount NUMERIC DEFAULT NULL) RETURNS JSONB LANGUAGE sql AS $$
 SELECT mark_online_order_paid(value->>'order_no','Easypaisa',ref,coalesce(amount,(value->>'total')::numeric),method,'{"private_provider_payload":"secret"}') FROM work WHERE key=k
$$;
CREATE FUNCTION pg_temp.refuse(sql TEXT) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
 BEGIN EXECUTE sql;RETURN false;EXCEPTION WHEN insufficient_privilege THEN RETURN true;END
$$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated,service_role,anon;

SET LOCAL ROLE anon;
SET LOCAL "request.jwt.claims"='{"role":"anon"}';
SELECT is((quote_online_order(pg_temp.cart())->>'subtotal')::numeric,100.05,'quote ignores client prices');
SELECT is((quote_online_order(pg_temp.cart())->>'tax')::numeric,17.01,'tax rounds each line to paisa');
SELECT is((quote_online_order(pg_temp.cart('00000000-0000-0000-0000-000000009ab1',2,'delivery'))->>'total')::numeric,484.12,'delivery fee is added after per-line tax');
SELECT throws_ok($$SELECT quote_online_order(pg_temp.cart('00000000-0000-0000-0000-000000009ab3'))$$,'P0001','Hidden tube is not available online','unpublished style refused by name');
SELECT throws_ok($$SELECT quote_online_order(pg_temp.cart('00000000-0000-0000-0000-000000009ab1',11))$$,'P0001','Choose a whole quantity from 1 to 10','quantity limit');
SELECT throws_ok($$SELECT quote_online_order('{"fulfilment":"pickup","lines":[{"variant_id":"00000000-0000-0000-0000-000000009ab1","quantity":1.5}]}')$$,'P0001','Choose a whole quantity from 1 to 10','fractional quantity refused');
SELECT throws_ok($$SELECT quote_online_order('{"fulfilment":"pickup","lines":[{"variant_id":"00000000-0000-0000-0000-000000009ab1","quantity":1},{"variant_id":"00000000-0000-0000-0000-000000009ab1","quantity":1}]}')$$,'P0001','Combine duplicate items into one line','duplicate variants refused');
SELECT ok(pg_temp.refuse('SELECT create_online_order(pg_temp.order_payload())'),'anon cannot create');
SELECT ok(pg_temp.refuse('SELECT my_online_orders()'),'anon cannot read orders');
SELECT ok(pg_temp.refuse('SELECT expire_online_orders()'),'anon cannot expire orders');
SELECT ok(pg_temp.refuse('SELECT * FROM online_orders'),'anon has no table access');

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a02","role":"authenticated"}';
SELECT is((quote_online_order(pg_temp.cart('00000000-0000-0000-0000-000000009ab1',2))->>'tax')::numeric,
 (quote_sale('{"lines":[{"variant_id":"00000000-0000-0000-0000-000000009ab1","quantity":2}]}')->>'tax_amount')::numeric,'online tax matches POS tax');
SELECT ok(pg_temp.refuse('SELECT create_online_order(pg_temp.order_payload())'),'staff cannot create website orders');
SELECT ok(pg_temp.refuse('SELECT expire_online_orders()'),'counter staff cannot run service expiry');
SELECT ok(pg_temp.refuse($$SELECT mark_online_order_paid('x','x','x',1,'card','{}')$$),'counter staff cannot fake payment notifications');
SELECT ok(pg_temp.refuse($$SELECT close_online_reservations(gen_random_uuid(),'released')$$),'internal reservation helper is private');

SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a03","role":"authenticated"}';
SELECT throws_ok($$SELECT create_online_order(pg_temp.order_payload()||'{"phone":"bad"}')$$,'P0001','Enter your contact name and a valid phone number','contact validation');
SELECT throws_ok($$SELECT create_online_order(pg_temp.order_payload('card','00000000-0000-0000-0000-000000009ab1','delivery')||'{"address":{}}')$$,'P0001','Enter the delivery address and city','delivery address required');
INSERT INTO work VALUES('a',create_online_order(pg_temp.order_payload('card','00000000-0000-0000-0000-000000009ab1','delivery',2,'00000000-0000-0000-0000-000000009ac1')));
SELECT matches((SELECT value->>'order_no' FROM work WHERE key='a'),'^WEB-[0-9]{6}$','order number generated');
SELECT is(create_online_order('{"request_id":"00000000-0000-0000-0000-000000009ac1"}'),(SELECT value FROM work WHERE key='a'),'retry returns original result before validation');
SELECT is((SELECT value->>'status' FROM work WHERE key='a'),'pending_payment','card starts pending payment');
SELECT is((SELECT (value->>'expires_at')::timestamptz-now() FROM work WHERE key='a'),interval '30 minutes','card holds stock for configured window');
SELECT is((SELECT count(*)::int FROM online_orders),0,'customer sees no raw order rows');
SELECT is((SELECT count(*)::int FROM online_order_lines),0,'customer sees no raw lines');
SELECT is((SELECT count(*)::int FROM online_order_events),0,'customer sees no internal events');
SELECT is((SELECT count(*)::int FROM online_payments),0,'customer sees no raw payments');
SELECT ok(NOT (my_online_orders()::text ~ 'notes_staff|created_by|location_id|reservation_id|account_id|customer_id|unit_cost|private_provider_payload'),'customer fields are explicitly whitelisted');
SELECT ok((SELECT customer_id IS NULL AND NOT phone_verified FROM customer_accounts WHERE id=auth.uid()),'new contact never verifies or links the login');
INSERT INTO work VALUES('scarce',create_online_order(pg_temp.order_payload('card','00000000-0000-0000-0000-000000009ab2')));
SELECT is((SELECT stock_level FROM public_catalog WHERE variant_id='00000000-0000-0000-0000-000000009ab2'),'out_of_stock','reservation lowers public stock band');
SELECT is(cancel_my_online_order((SELECT value->>'order_no' FROM work WHERE key='scarce'))->>'status','cancelled','customer cancels unpaid order');
SELECT is((SELECT stock_level FROM public_catalog WHERE variant_id='00000000-0000-0000-0000-000000009ab2'),'low_stock','cancellation restores public band');

SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a04","role":"authenticated"}';
SELECT is(my_online_orders(),'[]'::jsonb,'customer B sees no A orders');
SELECT ok(pg_temp.refuse(format('SELECT my_online_order(%L)',(SELECT value->>'order_no' FROM work WHERE key='a'))),'foreign detail refused');
SELECT ok(pg_temp.refuse(format('SELECT cancel_my_online_order(%L)',(SELECT value->>'order_no' FROM work WHERE key='a'))),'foreign cancellation refused');
SELECT ok(pg_temp.refuse($$SELECT create_online_order('{"request_id":"00000000-0000-0000-0000-000000009ac1"}')$$),'idempotency response cannot cross accounts');
SELECT ok(pg_temp.refuse('SELECT list_online_orders()'),'customer refused staff list');
SELECT ok(pg_temp.refuse('SELECT online_order_detail(pg_temp.order_id(''a''))'),'customer refused staff detail');

SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a02","role":"authenticated"}';
SELECT is((SELECT reserved FROM stock_balances b JOIN locations l ON l.id=b.location_id WHERE b.variant_id='00000000-0000-0000-0000-000000009ab1' AND l.code='STOCK'),2.000000,'most available single location reserved');
SELECT is((SELECT sum(on_hand) FROM stock_balances WHERE variant_id='00000000-0000-0000-0000-000000009ab1'),100.000000,'reservation does not deduct physical stock');
SELECT ok((SELECT customer_id IS NOT NULL FROM online_orders WHERE id=pg_temp.order_id('a')),'new contact creates shop customer for this order');
SELECT is((SELECT phone FROM online_orders WHERE id=pg_temp.order_id('a')),'+923009990001','phone normalized');
SELECT throws_ok($$SELECT release_reservation((SELECT reservation_id FROM online_order_lines WHERE order_id=pg_temp.order_id('a')))$$,'P0001','Use online order cancellation to release this reservation','generic release cannot break order reservations');
SELECT throws_ok($$SELECT pg_temp.advance('a','packed')$$,'P0001','That order status transition is not allowed','cannot skip confirmation');
SELECT is(list_online_orders(jsonb_build_object('q',(SELECT value->>'order_no' FROM work WHERE key='a'),'limit',1))->>'total_count','1','staff search and count');
SELECT is(jsonb_array_length(online_order_detail(pg_temp.order_id('a'))->'lines'),1,'counter staff reads order detail');

SET LOCAL ROLE service_role;
SET LOCAL "request.jwt.claims"='{"role":"service_role"}';
SELECT is(pg_temp.notify('a','ORDER-BAD','card',1)->>'status','failed','amount mismatch is recorded as failed');
SELECT is(pg_temp.notify('a','ORDER-GOOD')->>'status','paid','matching provider payment accepted');
SELECT is(pg_temp.notify('a','ORDER-GOOD')->>'status','paid','duplicate notification returns stored result');
SELECT throws_ok($$SELECT pg_temp.notify('a','ORDER-GOOD','card',2)$$,'P0001','Payment reference already belongs to another notification','conflicting reuse of reference refused');

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a02","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM online_payments WHERE provider_ref='ORDER-GOOD'),1,'exactly one provider payment');
SELECT is((SELECT status FROM online_orders WHERE id=pg_temp.order_id('a')),'placed','payment places order');
SELECT ok((SELECT expires_at IS NULL FROM stock_reservations WHERE reference_id=pg_temp.order_id('a')),'paid reservation no longer expires');
SELECT is(pg_temp.advance('a','confirmed')->>'status','confirmed','confirm paid order');
-- Change the live catalog after the order was priced: packing must use the snapshot.
RESET ROLE;
UPDATE product_variants SET price=999 WHERE id='00000000-0000-0000-0000-000000009ab1';
SET LOCAL ROLE authenticated;
SELECT is(pg_temp.advance('a','packed','00000000-0000-0000-0000-000000009ac2')->>'status','packed','pack creates sale');
SELECT is(pg_temp.advance('a','packed','00000000-0000-0000-0000-000000009ac2')->>'status','packed','pack request retry succeeds');
SELECT is(pg_temp.advance('a','packed')->>'status','packed','new request at same status is also harmless');
SELECT is((SELECT count(*)::int FROM sales WHERE request_id=pg_temp.order_id('a')),1,'exactly one sale');
SELECT is((SELECT sum(on_hand) FROM stock_balances WHERE variant_id='00000000-0000-0000-0000-000000009ab1'),98.000000,'packing deducts exactly once');
SELECT is((SELECT status FROM stock_reservations WHERE reference_id=pg_temp.order_id('a')),'consumed','reservation consumed');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM stock_movements WHERE reference_id=(SELECT sale_id FROM online_orders WHERE id=pg_temp.order_id('a')) AND channel='web' AND movement_type='sale'),1,'one web sale movement');
SET LOCAL ROLE authenticated;
SELECT is((SELECT unit_price FROM sale_lines WHERE sale_id=(SELECT sale_id FROM online_orders WHERE id=pg_temp.order_id('a')) AND variant_id IS NOT NULL),100.05,'packing preserves frozen price');
SELECT is((SELECT unit_cost FROM sale_lines WHERE sale_id=(SELECT sale_id FROM online_orders WHERE id=pg_temp.order_id('a')) AND variant_id IS NOT NULL),40.0000,'packing snapshots cost');
SELECT is((SELECT sum(total) FROM sale_lines WHERE sale_id=(SELECT sale_id FROM online_orders WHERE id=pg_temp.order_id('a'))),(SELECT total FROM online_orders WHERE id=pg_temp.order_id('a')),'sale lines include untaxed delivery and reconcile to order');
SELECT is((SELECT amount FROM payments WHERE reference='ORDER-GOOD'),484.12,'card payment booked against sale');
SELECT throws_ok($$SELECT cancel_online_order(jsonb_build_object('id',pg_temp.order_id('a'),'request_id',gen_random_uuid(),'reason','Change of mind'))$$,'P0001','Use the returns screen for packed orders','packed order requires POS return');
SELECT is(pg_temp.advance('a','shipped')->>'status','shipped','delivery transition records tracking');
SELECT is(pg_temp.advance('a','delivered')->>'status','delivered','paid shipment completes');
SELECT is((SELECT count(*)::int FROM online_order_events WHERE order_id=pg_temp.order_id('a') AND event='packed'),1,'packing retries do not duplicate events');

RESET ROLE;
UPDATE product_variants SET price=100.05 WHERE id='00000000-0000-0000-0000-000000009ab1';
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a03","role":"authenticated"}';
INSERT INTO work VALUES('expire',create_online_order(pg_temp.order_payload()));
INSERT INTO work VALUES('deadline',create_online_order(pg_temp.order_payload()));
INSERT INTO work VALUES('wallet',create_online_order(pg_temp.order_payload('easypaisa')));
INSERT INTO work VALUES('wallet_pack',create_online_order(pg_temp.order_payload('easypaisa')));
INSERT INTO work VALUES('staff_cancel',create_online_order(pg_temp.order_payload('card')));
INSERT INTO work VALUES('cod',create_online_order(pg_temp.order_payload('cod')));
INSERT INTO work VALUES('pack_cancel',create_online_order(pg_temp.order_payload('cod','00000000-0000-0000-0000-000000009ab4','pickup',3)));
SELECT is(cancel_my_online_order((SELECT value->>'order_no' FROM work WHERE key='pack_cancel'))->>'status','cancelled','pack cancellation succeeds');
INSERT INTO work VALUES('pack',create_online_order(pg_temp.order_payload('cod','00000000-0000-0000-0000-000000009ab4','pickup',3)));
RESET ROLE;
UPDATE online_orders SET expires_at=now()-interval '1 minute' WHERE id=pg_temp.order_id('expire');
SET LOCAL ROLE service_role;
SET LOCAL "request.jwt.claims"='{"role":"service_role"}';
SELECT is(expire_online_orders(),1,'direct expiry closes overdue order');
SELECT is(expire_online_orders(),0,'expiry is repeatable');
SELECT is(pg_temp.notify('expire','ORDER-LATE')->>'needs_refund','true','late captured payment flagged for refund');
RESET ROLE;
UPDATE online_orders SET expires_at=now()-interval '1 minute' WHERE id=pg_temp.order_id('deadline');
SET LOCAL ROLE service_role;
SELECT is(pg_temp.notify('deadline','ORDER-DEADLINE')->>'needs_refund','true','webhook also enforces deadline before cron');
SELECT is(pg_temp.notify('wallet','ORDER-WALLET','wallet')->>'status','paid','wallet notification accepted');
SELECT is(pg_temp.notify('wallet_pack','ORDER-WALLET-PACK','wallet')->>'status','paid','second wallet payment accepted for packing');

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a03","role":"authenticated"}';
SELECT is(cancel_my_online_order((SELECT value->>'order_no' FROM work WHERE key='wallet'))->>'status','cancelled','paid customer cancellation succeeds');
SELECT is(my_online_order((SELECT value->>'order_no' FROM work WHERE key='wallet'))->>'payment_status','paid','cancelled captured payment remains paid until refund');
SELECT ok(NOT (my_online_orders()::text ~ 'notes_staff|created_by|location_id|reservation_id|private_provider_payload|Private Cashier'),'paid customer response excludes private notes and provider data');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a02","role":"authenticated"}';
SELECT ok((SELECT customer_id IS NULL AND notes_staff LIKE '%verify identity%' FROM online_orders WHERE id=pg_temp.order_id('cod')),'matching phone never claims an existing customer');
SELECT is((SELECT status FROM online_orders WHERE id=pg_temp.order_id('expire')),'expired','late payment does not reopen expired order');
SELECT is((SELECT status FROM stock_reservations WHERE reference_id=pg_temp.order_id('expire')),'expired','expiry marks reservation expired');
SELECT is((SELECT sum(reserved) FROM stock_balances WHERE variant_id='00000000-0000-0000-0000-000000009ab1'),3.000000,'expired and cancelled holds released while active holds remain');
SELECT ok((SELECT needs_refund FROM online_payments WHERE provider_ref='ORDER-WALLET'),'paid cancellation flags payment');
SELECT ok((SELECT expires_at IS NULL AND status='placed' FROM online_orders WHERE id=pg_temp.order_id('cod')),'COD starts placed without expiry');
SELECT ok(pg_temp.refuse($$SELECT record_online_refund(jsonb_build_object('request_id',gen_random_uuid(),'provider_ref','ORDER-WALLET'))$$),'cashier cannot record portal refund');
SELECT is(pg_temp.advance('cod','confirmed')->>'status','confirmed','COD may be confirmed before payment');
SELECT is(pg_temp.advance('cod','packed')->>'status','packed','COD packs before collection');
SELECT is(pg_temp.advance('cod','ready_for_pickup')->>'status','ready_for_pickup','pickup transition');
SELECT throws_ok($$SELECT pg_temp.advance('cod','delivered')$$,'P0001','Collect payment before marking the order delivered','COD cannot complete unpaid');
SELECT throws_ok($$SELECT collect_cod_payment(jsonb_build_object('id',pg_temp.order_id('cod'),'request_id',gen_random_uuid(),'payments',jsonb_build_array(jsonb_build_object('method','cash','amount',117.06))))$$,'P0001',NULL,'COD cash requires open shift');
SELECT FROM open_cash_session(0);
SELECT is(collect_cod_payment(jsonb_build_object('id',pg_temp.order_id('cod'),'request_id',gen_random_uuid(),'payments',jsonb_build_array(jsonb_build_object('method','cash','amount',117.06))))->>'payment_status','paid','COD cash collection books to open shift');
SELECT is(collect_cod_payment(jsonb_build_object('id',pg_temp.order_id('cod'),'request_id',gen_random_uuid()))->>'payment_status','paid','collection retry does not take money twice');
SELECT is((SELECT count(*)::int FROM payments WHERE sale_id=(SELECT sale_id FROM online_orders WHERE id=pg_temp.order_id('cod'))),1,'one COD payment');
SELECT ok((SELECT cash_session_id IS NOT NULL FROM payments WHERE sale_id=(SELECT sale_id FROM online_orders WHERE id=pg_temp.order_id('cod'))),'cash payment linked to shift');
SELECT is(pg_temp.advance('cod','delivered')->>'status','delivered','paid pickup completes');
SELECT throws_ok($$SELECT cancel_online_order(jsonb_build_object('id',pg_temp.order_id('staff_cancel'),'request_id',gen_random_uuid()))$$,'P0001',NULL,'staff cancellation requires reason');
SELECT is(cancel_online_order(jsonb_build_object('id',pg_temp.order_id('staff_cancel'),'request_id',gen_random_uuid(),'reason','Customer phoned the shop'))->>'status','cancelled','staff can cancel before packing');
SELECT is((SELECT status FROM stock_reservations WHERE reference_id=pg_temp.order_id('staff_cancel')),'released','staff cancellation releases hold');
SELECT pg_temp.advance('wallet_pack','confirmed');
SELECT is(pg_temp.advance('wallet_pack','packed')->>'status','packed','wallet-paid order packs');
SELECT is((SELECT method FROM payments WHERE reference='ORDER-WALLET-PACK'),'digital','wallet maps to digital payment');
SELECT is((SELECT bank_name FROM payments WHERE reference='ORDER-WALLET-PACK'),'Easypaisa','wallet bank and reference preserved');
SELECT is((SELECT sum(reserved) FROM stock_balances WHERE variant_id='00000000-0000-0000-0000-000000009ab4'),3.000000,'pack cancellation and new hold reconcile reservations');
SELECT pg_temp.advance('pack','confirmed');
SELECT is(pg_temp.advance('pack','packed')->>'status','packed','pack order packs');
SELECT is((SELECT sum(on_hand) FROM stock_balances WHERE variant_id='00000000-0000-0000-0000-000000009ab4'),7.000000,'pack stock deducted once');
SELECT is((SELECT sum(reserved) FROM stock_balances WHERE variant_id='00000000-0000-0000-0000-000000009ab4'),0.000000,'packing releases the hold');

SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a06","role":"authenticated"}';
SELECT is(record_online_refund(jsonb_build_object('request_id',gen_random_uuid(),'provider_ref','ORDER-WALLET'))->>'payment_status','refunded','manager records portal refund');
SELECT is(record_online_refund(jsonb_build_object('request_id',gen_random_uuid(),'provider_ref','ORDER-WALLET'))->>'payment_status','refunded','refund naturally idempotent');
SELECT throws_ok($$SELECT update_settings(jsonb_build_object('request_id',gen_random_uuid(),'delivery_fee',100))$$,'42501',NULL,'new online settings are admin only');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a01","role":"authenticated"}';
SELECT lives_ok($$SELECT update_settings(jsonb_build_object('request_id',gen_random_uuid(),'online_hold_minutes',15,'delivery_fee',150,'free_delivery_over',100,'cod_max_total',100,'cod_enabled',true))$$,'admin updates all online settings');
SELECT is((quote_online_order(pg_temp.cart('00000000-0000-0000-0000-000000009ab1',1,'delivery'))->>'delivery_fee')::numeric,0::numeric,'free delivery threshold applies to subtotal');
SELECT is(quote_online_order(pg_temp.cart())->>'cod_allowed','false','COD maximum includes tax');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a03","role":"authenticated"}';
SELECT throws_ok($$SELECT create_online_order(pg_temp.order_payload('cod'))$$,'P0001','Cash on delivery is unavailable for this order','over-limit COD order refused');
INSERT INTO work VALUES('short_hold',create_online_order(pg_temp.order_payload()));
SELECT is((SELECT (value->>'expires_at')::timestamptz-now() FROM work WHERE key='short_hold'),interval '15 minutes','configured hold duration is used');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a01","role":"authenticated"}';
SELECT throws_ok($$SELECT update_settings(jsonb_build_object('request_id',gen_random_uuid(),'online_hold_minutes',0))$$,'P0001',NULL,'hold setting must be positive');
SELECT throws_ok($$SELECT update_settings(jsonb_build_object('request_id',gen_random_uuid(),'delivery_fee',1.001))$$,'P0001',NULL,'delivery fee cannot silently round');
SELECT lives_ok($$SELECT update_settings(jsonb_build_object('request_id',gen_random_uuid(),'free_delivery_over',NULL,'cod_max_total',NULL,'cod_enabled',false))$$,'nullable thresholds can be cleared');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a03","role":"authenticated"}';
SELECT throws_ok($$SELECT create_online_order(pg_temp.order_payload('cod'))$$,'P0001','Cash on delivery is unavailable for this order','disabled COD refused');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a05","role":"authenticated"}';
SELECT ok(pg_temp.refuse('SELECT list_online_orders()'),'inactive staff refused counter list');
SELECT ok(pg_temp.refuse('SELECT online_order_detail(pg_temp.order_id(''a''))'),'inactive staff refused counter detail');
SELECT is((SELECT count(*)::int FROM online_orders),0,'inactive staff cannot read contact tables');
RESET ROLE;
SET LOCAL "request.jwt.claims"='';
SELECT throws_ok($$UPDATE online_order_events SET public_message='changed' WHERE order_id=pg_temp.order_id('a')$$,'42501',NULL,'event trail is append only');
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname='expire-online-orders' AND schedule='* * * * *'),1,'expiry scheduled once every minute');
SELECT * FROM finish();
ROLLBACK;
