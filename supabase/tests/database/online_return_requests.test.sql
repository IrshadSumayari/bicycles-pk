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
 ('00000000-0000-0000-0000-000000009aa1','ORDER-SHIRT','Order shirt','garment','piece',true,true,'order-shirt'),
 ('00000000-0000-0000-0000-000000009aa2','ORDER-LAST','Last scarf','garment','piece',false,true,'order-last'),
 ('00000000-0000-0000-0000-000000009aa3','ORDER-HIDDEN','Hidden shirt','garment','piece',false,false,NULL),
 ('00000000-0000-0000-0000-000000009aa4','ORDER-PACK','Order gift set','pack','set',false,true,'order-pack');
INSERT INTO product_variants(id,style_id,sku,price,published) VALUES
 ('00000000-0000-0000-0000-000000009ab1','00000000-0000-0000-0000-000000009aa1','ORDER-SHIRT-M',100.05,true),
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
INSERT INTO work VALUES('pending',create_online_order(pg_temp.order_payload('cod')));
CREATE FUNCTION pg_temp.payload() RETURNS JSONB LANGUAGE sql AS $$
 SELECT jsonb_build_object('order_no',value->>'order_no','request_id','00000000-0000-0000-0000-00000000aa01','reason','damaged','requested_resolution','exchange','message','The stitching is damaged.','items','[{"line_no":1,"quantity":1}]'::jsonb) FROM work WHERE key='a'
$$;
GRANT EXECUTE ON FUNCTION pg_temp.payload() TO authenticated,anon;
SELECT throws_ok($$SELECT create_return_request(pg_temp.payload())$$,'P0001',NULL,'undelivered order cannot open request');
RESET ROLE;
UPDATE online_orders SET status='delivered' WHERE id=pg_temp.order_id('a');
CREATE TEMP TABLE ledger_before AS SELECT (SELECT count(*) FROM stock_movements) stock,(SELECT count(*) FROM payments) payments,(SELECT count(*) FROM sales) sales,(SELECT sum(on_hand) FROM stock_balances) on_hand;
SET LOCAL ROLE authenticated;
SELECT is(my_return_request((SELECT value->>'order_no' FROM work WHERE key='a')),NULL::jsonb,'no request before submission');
SELECT throws_ok($$SELECT create_return_request(pg_temp.payload()||'{"items":[]}')$$,'P0001',NULL,'empty items rejected');
SELECT throws_ok($$SELECT create_return_request(pg_temp.payload()||'{"items":[{"line_no":1,"quantity":3}]}')$$,'P0001',NULL,'quantity above purchased rejected');
SELECT throws_ok($$SELECT create_return_request(pg_temp.payload()||'{"items":[{"line_no":1,"quantity":1.5}]}')$$,'P0001',NULL,'fractional quantity rejected');
SELECT throws_ok($$SELECT create_return_request(pg_temp.payload()||'{"items":[{"line_no":1,"quantity":0}]}')$$,'P0001',NULL,'zero quantity rejected');
SELECT throws_ok($$SELECT create_return_request(pg_temp.payload()||'{"items":[{"line_no":2,"quantity":1}]}')$$,'P0001',NULL,'foreign line rejected');
SELECT throws_ok($$SELECT create_return_request(pg_temp.payload()||'{"items":[{"line_no":1,"quantity":1},{"line_no":1,"quantity":1}]}')$$,'P0001',NULL,'duplicate line rejected');
SELECT throws_ok($$SELECT create_return_request(pg_temp.payload()||'{"reason":"unknown"}')$$,'P0001',NULL,'unknown reason rejected');
SELECT throws_ok($$SELECT create_return_request(pg_temp.payload()||'{"requested_resolution":"automatic_refund"}')$$,'P0001',NULL,'unknown resolution rejected');
SELECT throws_ok($$SELECT create_return_request(pg_temp.payload()||'{"message":"  "}')$$,'P0001',NULL,'empty description rejected');
INSERT INTO work VALUES('request',create_return_request(pg_temp.payload()));
SELECT is((SELECT value->>'status' FROM work WHERE key='request'),'submitted','submission requires review');
SELECT is(create_return_request(pg_temp.payload()),(SELECT value FROM work WHERE key='request'),'create retry returns one request');
SELECT throws_ok($$SELECT create_return_request(pg_temp.payload()||jsonb_build_object('request_id',gen_random_uuid()))$$,'P0001',NULL,'one request per order');
SELECT is((SELECT value->'items'->0->>'quantity' FROM work WHERE key='request'),'1','selected quantity preserved');
SELECT ok(NOT((SELECT value::text FROM work WHERE key='request')~'staff_note|created_by|account_id|unit_cost|location_id'),'customer response whitelists fields');
SELECT ok(pg_temp.refuse('SELECT * FROM online_return_requests'),'customer cannot read raw request table');
SELECT ok(pg_temp.refuse('SELECT * FROM online_return_events'),'customer cannot read raw event table');
SELECT ok(pg_temp.refuse('SELECT app_private.return_request_json(''00000000-0000-0000-0000-00000000aa01'')'),'raw serializer is private');
SELECT ok(pg_temp.refuse('SELECT list_return_requests()'),'customer cannot read review queue');
SELECT ok(pg_temp.refuse('SELECT review_return_request(''{}'')'),'customer cannot review');
SELECT throws_ok($$SELECT reply_return_request('{"id":"00000000-0000-0000-0000-00000000aa01","request_id":"00000000-0000-0000-0000-00000000ab01","version":1,"message":"Another message"}')$$,'P0001',NULL,'cannot reply before staff ask');

INSERT INTO work VALUES('photo',prepare_return_photo('00000000-0000-0000-0000-00000000aa01','00000000-0000-0000-0000-00000000ac01'));
SELECT is(prepare_return_photo('00000000-0000-0000-0000-00000000aa01','00000000-0000-0000-0000-00000000ac01'),(SELECT value FROM work WHERE key='photo'),'photo reservation retry consumes no slot');
SELECT ok(app_private.return_photo_access((SELECT value->>'storage_path' FROM work WHERE key='photo'),true),'owner can upload reserved path');
SELECT ok(NOT app_private.return_photo_access('arbitrary.webp',true),'unregistered paths refused');
INSERT INTO storage.objects(bucket_id,name) SELECT 'return-evidence',value->>'storage_path' FROM work WHERE key='photo';
SELECT is(prepare_return_photo('00000000-0000-0000-0000-00000000aa01','00000000-0000-0000-0000-00000000ac01')->>'uploaded','true','uncertain upload retry knows object exists');
SELECT is((my_return_request((SELECT value->>'order_no' FROM work WHERE key='a'))->'photos'->0->>'uploaded'),'true','owner sees completed upload');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='return-evidence'),1,'owner can read own evidence');
WITH changed AS (UPDATE storage.objects SET name='replaced.webp' WHERE bucket_id='return-evidence' RETURNING id) SELECT is((SELECT count(*)::int FROM changed),0,'owner cannot replace evidence');
SET LOCAL storage.allow_delete_query=true;
WITH removed AS (DELETE FROM storage.objects WHERE bucket_id='return-evidence' RETURNING id) SELECT is((SELECT count(*)::int FROM removed),0,'owner cannot delete evidence');
SELECT prepare_return_photo('00000000-0000-0000-0000-00000000aa01','00000000-0000-0000-0000-00000000ac02');
SELECT prepare_return_photo('00000000-0000-0000-0000-00000000aa01','00000000-0000-0000-0000-00000000ac03');
SELECT throws_ok($$SELECT prepare_return_photo('00000000-0000-0000-0000-00000000aa01','00000000-0000-0000-0000-00000000ac04')$$,'P0001',NULL,'three photo limit enforced');

SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a04","role":"authenticated"}';
SELECT ok(pg_temp.refuse('SELECT create_return_request(pg_temp.payload())'),'other customer cannot create on this order');
SELECT ok(pg_temp.refuse(format('SELECT my_return_request(%L)',(SELECT value->>'order_no' FROM work WHERE key='a'))),'other customer cannot read request');
SELECT ok(pg_temp.refuse('SELECT prepare_return_photo(''00000000-0000-0000-0000-00000000aa01'',''00000000-0000-0000-0000-00000000ac04'')'),'other customer cannot reserve photos');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='return-evidence'),0,'other customer cannot read evidence');
SELECT throws_ok($$INSERT INTO storage.objects(bucket_id,name) VALUES('return-evidence','00000000-0000-0000-0000-00000000aa01/00000000-0000-0000-0000-00000000ac02.webp')$$,'42501',NULL,'other customer cannot upload to reserved path');

SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a02","role":"authenticated"}';
SELECT ok(pg_temp.refuse('SELECT list_return_requests()'),'cashier cannot review');
SELECT ok(pg_temp.refuse('SELECT staff_return_request(pg_temp.order_id(''a''))'),'cashier cannot read review details');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='return-evidence'),0,'cashier cannot read private evidence');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a05","role":"authenticated"}';
SELECT ok(pg_temp.refuse('SELECT list_return_requests()'),'inactive staff refused');

SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a06","role":"authenticated"}';
SELECT is(list_return_requests()->>'total_count','1','branch manager sees active request');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='return-evidence'),1,'branch manager sees private evidence');
SELECT ok(NOT app_private.return_photo_access((SELECT value->>'storage_path' FROM work WHERE key='photo'),true),'staff cannot upload customer evidence');
SELECT throws_ok($$SELECT review_return_request('{"id":"00000000-0000-0000-0000-00000000aa01","version":1,"status":"closed","request_id":"00000000-0000-0000-0000-00000000ad01","message":"Closed"}')$$,'P0001',NULL,'cannot skip review steps');
INSERT INTO work VALUES('review',jsonb_build_object('id','00000000-0000-0000-0000-00000000aa01','version',1,'status','needs_information','request_id','00000000-0000-0000-0000-00000000ad01','message','Please describe the damaged seam.','staff_note','INTERNAL NOTE'));
SELECT is(review_return_request((SELECT value FROM work WHERE key='review'))->>'status','needs_information','manager requests information');
SELECT is(review_return_request((SELECT value FROM work WHERE key='review'))->>'version','2','review retry does not increment version twice');
SELECT is(staff_return_request(pg_temp.order_id('a'))->>'staff_note','INTERNAL NOTE','manager sees internal note');
SELECT throws_ok($$SELECT review_return_request((SELECT value FROM work WHERE key='review')||jsonb_build_object('request_id',gen_random_uuid()))$$,'P0001',NULL,'stale version refused');

RESET ROLE;
DELETE FROM branch_memberships WHERE user_id='00000000-0000-0000-0000-000000009a06';
SET LOCAL ROLE authenticated;
SELECT is(list_return_requests()->>'total_count','0','manager outside branch sees no requests');
SELECT ok(pg_temp.refuse('SELECT staff_return_request(pg_temp.order_id(''a''))'),'manager outside branch cannot read detail');
SELECT ok(pg_temp.refuse('SELECT review_return_request((SELECT value FROM work WHERE key=''review''))'),'branch membership checked even for retries');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='return-evidence'),0,'manager outside branch cannot read evidence');

SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a03","role":"authenticated"}';
SELECT ok(NOT(my_return_request((SELECT value->>'order_no' FROM work WHERE key='a'))::text~'INTERNAL NOTE|staff_note'),'staff note never leaks to customer');
INSERT INTO work VALUES('reply','{"id":"00000000-0000-0000-0000-00000000aa01","request_id":"00000000-0000-0000-0000-00000000ab01","version":2,"message":"The seam on the left side is torn."}');
SELECT is(reply_return_request((SELECT value FROM work WHERE key='reply'))->>'status','submitted','customer reply returns to staff queue');
SELECT is(reply_return_request((SELECT value FROM work WHERE key='reply'))->>'version','3','reply retry adds no duplicate event');

SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a01","role":"authenticated"}';
SELECT is(review_return_request('{"id":"00000000-0000-0000-0000-00000000aa01","version":3,"status":"return_authorized","request_id":"00000000-0000-0000-0000-00000000ad02","message":"Please contact us to confirm the agreed parcel instructions."}')->>'status','return_authorized','admin provides instructions');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a03","role":"authenticated"}';
SELECT throws_ok($$SELECT prepare_return_photo('00000000-0000-0000-0000-00000000aa01','00000000-0000-0000-0000-00000000ac03')$$,'P0001',NULL,'photo upload locks after instructions');
SELECT throws_ok($$INSERT INTO storage.objects(bucket_id,name) VALUES('return-evidence','00000000-0000-0000-0000-00000000aa01/00000000-0000-0000-0000-00000000ac03.webp')$$,'42501',NULL,'even reserved paths lock after review');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000009a01","role":"authenticated"}';
SELECT is(review_return_request('{"id":"00000000-0000-0000-0000-00000000aa01","version":4,"status":"received","request_id":"00000000-0000-0000-0000-00000000ad03","message":"The parcel has arrived for inspection."}')->>'status','received','staff records receipt');
SELECT is(review_return_request('{"id":"00000000-0000-0000-0000-00000000aa01","version":5,"status":"closed","request_id":"00000000-0000-0000-0000-00000000ad04","message":"Review completed; contact us for the agreed resolution."}')->>'status','closed','staff closes review');
SELECT is(list_return_requests()->>'total_count','0','closed request leaves active queue');
SELECT is(list_return_requests('{"status":"closed","limit":1}')->>'total_count','1','closed requests remain accessible');
SELECT throws_ok($$SELECT review_return_request('{"id":"00000000-0000-0000-0000-00000000aa01","version":6,"status":"return_authorized","request_id":"00000000-0000-0000-0000-00000000ad05","message":"Reopen request"}')$$,'P0001',NULL,'terminal request cannot reopen');
SET LOCAL ROLE anon;
SET LOCAL "request.jwt.claims"='{"role":"anon"}';
SELECT ok(pg_temp.refuse('SELECT my_return_request(''x'')'),'anonymous request access refused');
SELECT ok(pg_temp.refuse('SELECT create_return_request(''{}'')'),'anonymous submission refused');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='return-evidence'),0,'anonymous evidence unreadable');
RESET ROLE;
SET LOCAL "request.jwt.claims"='';
SELECT is((SELECT count(*) FROM stock_movements),(SELECT stock FROM ledger_before),'review does not move stock');
SELECT is((SELECT count(*) FROM payments),(SELECT payments FROM ledger_before),'review does not create refunds or payments');
SELECT is((SELECT count(*) FROM sales),(SELECT sales FROM ledger_before),'review does not create sales');
SELECT is((SELECT sum(on_hand) FROM stock_balances),(SELECT on_hand FROM ledger_before),'on-hand stock unchanged');
SELECT is((SELECT count(*)::int FROM online_return_events),6,'only successful distinct actions append events');
SELECT is((SELECT public FROM storage.buckets WHERE id='return-evidence'),false,'evidence bucket is private');
SELECT is((SELECT file_size_limit FROM storage.buckets WHERE id='return-evidence'),5242880::bigint,'storage size limit enforced');
SELECT is((SELECT allowed_mime_types FROM storage.buckets WHERE id='return-evidence'),ARRAY['image/webp'],'only prepared WebP images accepted');
SELECT * FROM finish();
ROLLBACK;
