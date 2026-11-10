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


SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a03","role":"authenticated"}';
INSERT INTO work VALUES('a',create_online_order(pg_temp.order_payload('cod','00000000-0000-0000-0000-000000009ab1','delivery',2)));
INSERT INTO work VALUES('b',create_online_order(pg_temp.order_payload('cod','00000000-0000-0000-0000-000000009ab1','delivery')));
INSERT INTO work VALUES('pickup',create_online_order(pg_temp.order_payload('cod')));
SELECT ok(pg_temp.refuse('SELECT update_online_tracking(''{}'')'),'customer cannot post shipment updates');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a02","role":"authenticated"}';
INSERT INTO work VALUES('update',jsonb_build_object('id',pg_temp.order_id('a'),'request_id','00000000-0000-0000-0000-00000000bb01','version',0,'courier','PostEx','tracking_no','CN-TRACK-101','kind','out_for_delivery','message','The parcel is out for delivery today.'));
SELECT throws_ok($$SELECT update_online_tracking((SELECT value FROM work WHERE key='update'))$$,'P0001',NULL,'cannot update before shipping');
RESET ROLE;
UPDATE online_orders SET status='shipped',courier='Leopards',tracking_no='INITIAL-CN' WHERE id IN (pg_temp.order_id('a'),pg_temp.order_id('b'));
UPDATE online_orders SET status='ready_for_pickup' WHERE id=pg_temp.order_id('pickup');
CREATE TEMP TABLE ledger_before AS SELECT (SELECT count(*) FROM stock_movements) stock,(SELECT count(*) FROM payments) payments,(SELECT count(*) FROM sales) sales,(SELECT sum(on_hand) FROM stock_balances) on_hand;
SET LOCAL ROLE authenticated;
SELECT throws_ok($$SELECT update_online_tracking((SELECT value FROM work WHERE key='update')||'{"courier":""}')$$,'P0001',NULL,'blank courier rejected');
SELECT throws_ok($$SELECT update_online_tracking((SELECT value FROM work WHERE key='update')||'{"tracking_no":""}')$$,'P0001',NULL,'blank tracking number rejected');
SELECT throws_ok($$SELECT update_online_tracking((SELECT value FROM work WHERE key='update')||'{"message":""}')$$,'P0001',NULL,'public update required');
SELECT throws_ok($$SELECT update_online_tracking((SELECT value FROM work WHERE key='update')||'{"kind":"delivered"}')$$,'P0001',NULL,'cannot bypass delivery completion action');
SELECT throws_ok($$SELECT update_online_tracking((SELECT value FROM work WHERE key='update')||jsonb_build_object('id',pg_temp.order_id('pickup')))$$,'P0001',NULL,'pickup has no courier tracking');
SELECT throws_ok($$SELECT update_online_tracking((SELECT value FROM work WHERE key='update')-'version')$$,'P0001',NULL,'version is required');
SELECT is(update_online_tracking((SELECT value FROM work WHERE key='update'))->>'tracking_version','1','cashier records branch shipment update');
SELECT is(update_online_tracking((SELECT value FROM work WHERE key='update'))->>'tracking_version','1','duplicate retry returns original version');
SELECT is((SELECT count(*)::int FROM online_orders),3,'branch staff can still read their order rows');
SELECT is(online_order_detail(pg_temp.order_id('a'))->>'tracking_no','CN-TRACK-101','corrected tracking number visible to staff');
SELECT is(online_order_detail(pg_temp.order_id('a'))->>'courier','PostEx','courier corrected');
SELECT throws_ok($$SELECT update_online_tracking((SELECT value FROM work WHERE key='update')||jsonb_build_object('request_id',gen_random_uuid()))$$,'P0001',NULL,'stale edit rejected');
SELECT ok(pg_temp.refuse($$SELECT update_online_tracking((SELECT value FROM work WHERE key='update')||jsonb_build_object('id',pg_temp.order_id('b')))$$),'same key cannot be reused on a different order');
SELECT is(list_online_orders('{"q":"cn-track-101"}')->>'total_count','1','tracking-number search ignores case');
SELECT is(list_online_orders('{"q":"postex"}')->>'total_count','1','courier-name search');
SELECT is(jsonb_array_length(list_online_orders('{"q":"postex","offset":1,"limit":1}')->'orders'),0,'tracking search paginates safely');
SELECT is(list_online_orders('{"q":"CN-TRACK-101","status":"delivered"}')->>'total_count','0','status filter still applies to tracking search');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a06","role":"authenticated"}';
SELECT ok(pg_temp.refuse($$SELECT update_online_tracking((SELECT value FROM work WHERE key='update'))$$),'another staff member cannot reuse idempotency key');
RESET ROLE;
DELETE FROM branch_memberships WHERE user_id='00000000-0000-0000-0000-000000009a06';
SET LOCAL ROLE authenticated;
SELECT is(list_online_orders('{"q":"CN-TRACK-101"}')->>'total_count','0','manager outside branch cannot search shipment');
SELECT is((SELECT count(*)::int FROM online_orders),0,'manager outside branch cannot read raw online_orders');
SELECT is((SELECT count(*)::int FROM online_order_lines),0,'manager outside branch cannot read raw online_order_lines');
SELECT is((SELECT count(*)::int FROM online_order_events),0,'manager outside branch cannot read raw online_order_events');
SELECT is((SELECT count(*)::int FROM online_payments),0,'manager outside branch cannot read raw online_payments');
SELECT ok(pg_temp.refuse('SELECT online_order_detail(pg_temp.order_id(''a''))'),'manager outside branch cannot open shipment detail');
SELECT ok(pg_temp.refuse($$SELECT update_online_tracking((SELECT value FROM work WHERE key='update')||jsonb_build_object('request_id',gen_random_uuid()))$$),'manager outside branch cannot update shipment');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a05","role":"authenticated"}';
SELECT ok(pg_temp.refuse('SELECT update_online_tracking(''{}'')'),'inactive staff refused before payload validation');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a03","role":"authenticated"}';
SELECT is(my_online_order((SELECT value->>'order_no' FROM work WHERE key='a'))->>'tracking_no','CN-TRACK-101','customer sees current CN');
SELECT ok(my_online_order((SELECT value->>'order_no' FROM work WHERE key='a'))::text LIKE '%Out for delivery%','customer sees staff delivery update');
SELECT ok(NOT(my_online_order((SELECT value->>'order_no' FROM work WHERE key='a'))::text~'created_by|notes_staff|tracking_version|account_id|unit_cost'),'tracking preserves customer field whitelist');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a04","role":"authenticated"}';
SELECT ok(pg_temp.refuse(format('SELECT my_online_order(%L)',(SELECT value->>'order_no' FROM work WHERE key='a'))),'another customer cannot look up this order');
RESET ROLE;
UPDATE online_orders SET status='delivered' WHERE id=pg_temp.order_id('a');
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a02","role":"authenticated"}';
SELECT throws_ok($$SELECT update_online_tracking((SELECT value FROM work WHERE key='update')||jsonb_build_object('version',1,'request_id',gen_random_uuid()))$$,'P0001',NULL,'cannot publish active delivery update on completed order');
SELECT is(update_online_tracking((SELECT value FROM work WHERE key='update')||jsonb_build_object('kind','tracking_details','version',1,'request_id',gen_random_uuid()))->>'tracking_version','2','metadata correction allowed after delivery with audit message');
SET LOCAL ROLE anon;
SET LOCAL "request.jwt.claims"='{"role":"anon"}';
SELECT ok(pg_temp.refuse('SELECT update_online_tracking(''{}'')'),'anonymous updates refused');
SELECT ok(pg_temp.refuse('SELECT my_online_order(''WEB-000001'')'),'anonymous order lookup refused');
RESET ROLE;
SET LOCAL "request.jwt.claims"='';
SELECT is((SELECT count(*) FROM stock_movements),(SELECT stock FROM ledger_before),'tracking updates never move stock');
SELECT is((SELECT count(*) FROM payments),(SELECT payments FROM ledger_before),'tracking updates never create payments');
SELECT is((SELECT count(*) FROM sales),(SELECT sales FROM ledger_before),'tracking updates never create sales');
SELECT is((SELECT sum(on_hand) FROM stock_balances),(SELECT on_hand FROM ledger_before),'on-hand unchanged');
SELECT is((SELECT payment_status FROM online_orders WHERE id=pg_temp.order_id('a')),'cod','tracking update does not falsely mark COD paid');
SELECT is((SELECT count(*)::int FROM online_order_events WHERE event LIKE 'shipment_%'),2,'retries and invalid updates add no duplicate events');
SELECT * FROM finish();ROLLBACK;
