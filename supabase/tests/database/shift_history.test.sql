BEGIN;
SELECT plan(49);
INSERT INTO auth.users (id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-00000000fa01','admin@t.local','{"name":"Admin"}','{}'),
 ('00000000-0000-0000-0000-00000000fa02','manager@t.local','{"name":"Manager"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000fa03','cashier@t.local','{"name":"Cashier"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000fa04','other@t.local','{"name":"Other"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000fa05','inactive@t.local','{"name":"Inactive"}','{"account_type":"staff"}');
UPDATE users SET active=true;
UPDATE users SET role='manager' WHERE id='00000000-0000-0000-0000-00000000fa02';
UPDATE users SET active=false WHERE id='00000000-0000-0000-0000-00000000fa05';
UPDATE app_settings SET tax_rate=0;
INSERT INTO customers(id,name,phone) VALUES ('00000000-0000-0000-0000-00000000fac1','Customer','03001112233');
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fa01","role":"authenticated"}';
SELECT FROM save_style('{"kind":"garment","code":"HISTORY","name":"Shirt","variants":[{"sku":"HISTORY-M","size":"M","price":1000,"opening_stock":20}]}');
CREATE TEMP TABLE fixture (name TEXT PRIMARY KEY, value JSONB);
GRANT ALL ON fixture TO authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fa03","role":"authenticated"}';
INSERT INTO fixture VALUES ('a',open_cash_session(1000));
INSERT INTO fixture VALUES ('sale',post_sale(jsonb_build_object('request_id','00000000-0000-0000-0000-0000000fa001',
 'lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT id FROM product_variants WHERE sku='HISTORY-M'),'quantity',2)),
 'payments','[{"method":"cash"}]'::jsonb)));
SELECT FROM post_return(jsonb_build_object('request_id','00000000-0000-0000-0000-0000000fa002',
 'sale_id',(SELECT value->'sale'->>'id' FROM fixture WHERE name='sale'),'reason','Too small','refund_method','cash',
 'lines',jsonb_build_array(jsonb_build_object('sale_line_id',(SELECT id FROM sale_lines LIMIT 1),'quantity',1))));
SELECT FROM record_cash_movement(100,'Change');
SELECT FROM record_cash_movement(-50,'Tea');
SELECT is((SELECT expected_cash FROM list_cash_sessions()),2050::numeric,'running expected includes sales, refund, in and out');
SELECT is((SELECT refunds FROM list_cash_sessions()),1000::numeric,'refunds positive');
SELECT is((SELECT cash_sales FROM list_cash_sessions()),2000::numeric,'cash sales');
SELECT is((SELECT jsonb_array_length(cash_session_detail((value->'session'->>'id')::uuid)->'movements') FROM fixture WHERE name='a'),4,'detail has every movement');
SELECT is((SELECT count(*)::int FROM jsonb_array_elements(cash_session_detail((SELECT (value->'session'->>'id')::uuid FROM fixture WHERE name='a'))->'movements') m WHERE m->>'document_no' ~ '^(INV|RTN)-[0-9]{6}$'),2,'sale and return numbers linked');
SELECT is((SELECT count(*)::int FROM jsonb_array_elements(cash_session_detail((SELECT (value->'session'->>'id')::uuid FROM fixture WHERE name='a'))->'movements') m WHERE m->>'user_name'='Cashier'),4,'actor on every movement');
SELECT FROM close_cash_session(1450,'Short after recount');
SELECT ok((SELECT over_limit FROM list_cash_sessions()),'600 difference exceeds default 500');
SELECT is((SELECT count(*)::int FROM list_cash_sessions('{"status":"open"}')),0,'status filter');
SELECT is((SELECT count(*)::int FROM list_cash_sessions('{"only_variance":true}')),1,'difference filter');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fa04","role":"authenticated"}';
INSERT INTO fixture VALUES ('b',open_cash_session(500));
SELECT is((SELECT count(*)::int FROM list_cash_sessions()),1,'cashier sees only own shift');
SELECT is((SELECT count(*)::int FROM list_cash_sessions('{"user_id":"00000000-0000-0000-0000-00000000fa03"}')),0,'cashier cannot filter into another user');
SELECT throws_ok($$ SELECT cash_session_detail((SELECT (value->'session'->>'id')::uuid FROM fixture WHERE name='a')) $$,'42501',NULL,'other cashier detail denied');
SELECT throws_ok($$ SELECT force_close_cash_session((SELECT (value->'session'->>'id')::uuid FROM fixture WHERE name='b'),400,'Forgot','00000000-0000-0000-0000-0000000fa010') $$,'42501',NULL,'cashier force close denied');
SELECT throws_ok($$ SELECT close_cash_session_internal((SELECT (value->'session'->>'id')::uuid FROM fixture WHERE name='b'),500,NULL,auth.uid()) $$,'42501',NULL,'private closing helper inaccessible');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fa05","role":"authenticated"}';
SELECT throws_ok($$ SELECT * FROM list_cash_sessions() $$,'42501',NULL,'inactive staff list denied');
SELECT throws_ok($$ SELECT cash_session_detail((SELECT (value->'session'->>'id')::uuid FROM fixture WHERE name='a')) $$,'42501',NULL,'inactive staff detail denied');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fa02","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM list_cash_sessions()),2,'manager sees branch shifts');
SELECT is((SELECT count(*)::int FROM list_cash_sessions('{"user_id":"00000000-0000-0000-0000-00000000fa03"}')),1,'manager cashier filter');
SELECT is((SELECT total_count FROM list_cash_sessions('{"limit":1,"offset":1}')),2::bigint,'paging keeps total count');
SELECT is((SELECT count(*)::int FROM list_cash_sessions('{"from":"2000-01-01","to":"2000-01-02"}')),0,'date filter');
SELECT is((SELECT count(*)::int FROM list_cash_sessions(jsonb_build_object('from',(now() AT TIME ZONE report_tz())::date,'to',(now() AT TIME ZONE report_tz())::date))),2,'local day inclusive');
SELECT throws_ok($$ SELECT force_close_cash_session((SELECT (value->'session'->>'id')::uuid FROM fixture WHERE name='b'),400,' ','00000000-0000-0000-0000-0000000fa010') $$,'P0001',NULL,'manager notes required');
INSERT INTO fixture VALUES ('closed',force_close_cash_session((SELECT (value->'session'->>'id')::uuid FROM fixture WHERE name='b'),400,'Forgot to close','00000000-0000-0000-0000-0000000fa010'));
SELECT is((SELECT (value->'session'->>'expected_cash')::numeric FROM fixture WHERE name='closed'),500::numeric,'manager closing uses original arithmetic');
SELECT is((SELECT (value->'session'->>'variance')::numeric FROM fixture WHERE name='closed'),-100::numeric,'manager variance');
SELECT is((SELECT value->'session'->>'closing_notes' FROM fixture WHERE name='closed'),'Closed by manager: Forgot to close','prefixed notes');
SELECT is((SELECT closed_by_name FROM list_cash_sessions('{"user_id":"00000000-0000-0000-0000-00000000fa04"}')),'Manager','closer recorded');
SELECT is(force_close_cash_session((SELECT (value->'session'->>'id')::uuid FROM fixture WHERE name='b'),999,'Retry','00000000-0000-0000-0000-0000000fa010'),(SELECT value FROM fixture WHERE name='closed'),'retry returns original result');
SELECT throws_ok($$ SELECT force_close_cash_session((SELECT (value->'session'->>'id')::uuid FROM fixture WHERE name='b'),400,'Again','00000000-0000-0000-0000-0000000fa011') $$,'P0001','This cash shift is already closed','closed session cannot close again');
SELECT FROM open_cash_session(10);
SELECT throws_ok($$ SELECT force_close_cash_session((current_cash_session()->'session'->>'id')::uuid,10,'Own','00000000-0000-0000-0000-0000000fa012') $$,'P0001','Close your own shift from the till','manager uses normal close for own');
SELECT lives_ok($$ SELECT close_cash_session(10) $$,'own close still works without variance notes');
SELECT throws_ok($$ SELECT update_settings('{"cash_variance_alert":100}') $$,'42501',NULL,'manager cannot change alert');
SELECT lives_ok($$ SELECT update_settings('{"receipt_header":"Test store"}') $$,'manager retains receipt settings access');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fa01","role":"authenticated"}';
SELECT throws_ok($$ SELECT force_close_cash_session((SELECT (value->'session'->>'id')::uuid FROM fixture WHERE name='b'),400,'Retry','00000000-0000-0000-0000-0000000fa010') $$,'42501',NULL,'another manager cannot reuse request');
SELECT lives_ok($$ SELECT update_settings('{"cash_variance_alert":100}') $$,'admin can set alert');
SELECT ok(NOT (SELECT over_limit FROM list_cash_sessions('{"user_id":"00000000-0000-0000-0000-00000000fa04"}')),'alert is strictly greater than threshold');
SELECT lives_ok($$ SELECT update_settings('{"cash_variance_alert":0}') $$,'zero threshold allowed');
SELECT ok((SELECT over_limit FROM list_cash_sessions('{"user_id":"00000000-0000-0000-0000-00000000fa04"}')),'zero threshold flags nonzero difference');
SELECT throws_ok($$ SELECT update_settings('{"cash_variance_alert":-1}') $$,'P0001',NULL,'negative threshold refused');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fa04","role":"authenticated"}';
SELECT is(current_cash_session(),NULL,'cashier has no open shift after manager closing');
SELECT throws_ok($$ SELECT post_sale(jsonb_build_object('request_id','00000000-0000-0000-0000-0000000fa020',
 'lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT id FROM product_variants WHERE sku='HISTORY-M'),'quantity',1)),
 'payments','[{"method":"cash"}]'::jsonb)) $$,'P0001','Open a cash shift before taking or refunding cash','cashier must reopen before taking cash');
RESET ROLE;
SET LOCAL "request.jwt.claims"='';
UPDATE cash_sessions SET opened_at='2026-01-01 19:00:00+00' WHERE id=(SELECT (value->'session'->>'id')::uuid FROM fixture WHERE name='a');
UPDATE cash_sessions SET opened_at='2026-01-01 18:59:59+00' WHERE id=(SELECT (value->'session'->>'id')::uuid FROM fixture WHERE name='b');
INSERT INTO branches(id,code,name) VALUES ('00000000-0000-0000-0000-00000000fab1','REMOTE','Other branch');
INSERT INTO locations(id,branch_id,code,name,kind) VALUES ('00000000-0000-0000-0000-00000000fab2','00000000-0000-0000-0000-00000000fab1','FLOOR','Remote floor','shop_floor');
INSERT INTO branch_memberships(user_id,branch_id) VALUES ('00000000-0000-0000-0000-00000000fa04','00000000-0000-0000-0000-00000000fab1');
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fa04","role":"authenticated"}';
INSERT INTO fixture VALUES ('remote',open_cash_session(100,'00000000-0000-0000-0000-00000000fab2'));
SELECT lives_ok($$ SELECT record_cash_movement(10,'Reopened') $$,'reopened cashier can take cash');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fa02","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM list_cash_sessions('{"from":"2026-01-02","to":"2026-01-02"}')),1,'from uses Karachi midnight');
SELECT is((SELECT count(*)::int FROM list_cash_sessions('{"from":"2026-01-01","to":"2026-01-01"}')),1,'to includes last second of local day');
SELECT is((SELECT count(*)::int FROM list_cash_sessions()),3,'manager cannot list foreign branch');
SELECT throws_ok($$ SELECT cash_session_detail((SELECT (value->'session'->>'id')::uuid FROM fixture WHERE name='remote')) $$,'42501',NULL,'foreign branch detail denied');
SELECT throws_ok($$ SELECT force_close_cash_session((SELECT (value->'session'->>'id')::uuid FROM fixture WHERE name='remote'),110,'Remote','00000000-0000-0000-0000-0000000fa021') $$,'42501',NULL,'foreign branch force close denied');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fa01","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM list_cash_sessions()),4,'admin sees every branch');
SELECT is((SELECT count(*)::int FROM list_cash_sessions('{"limit":1}')),1,'limit applied');
SET LOCAL ROLE anon;
SELECT throws_ok($$ SELECT * FROM list_cash_sessions() $$,'42501',NULL,'anonymous access denied');
SELECT * FROM finish();
ROLLBACK;
