BEGIN;
SELECT plan(36);
SET LOCAL TIME ZONE 'UTC';
INSERT INTO auth.users (id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-00000000fa01','ts-admin@t.local','{"name":"Search Admin"}','{}'),
 ('00000000-0000-0000-0000-00000000fa02','ts-a@t.local','{"name":"Cashier A"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000fa03','ts-b@t.local','{"name":"Cashier B"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000fa04','ts-inactive@t.local','{"name":"Inactive"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000fa05','ts-manager@t.local','{"name":"Manager"}','{"account_type":"staff"}');
UPDATE public.users SET active = true WHERE id IN
 ('00000000-0000-0000-0000-00000000fa02','00000000-0000-0000-0000-00000000fa03','00000000-0000-0000-0000-00000000fa04','00000000-0000-0000-0000-00000000fa05');
UPDATE public.users SET role = 'cashier', active = false WHERE id = '00000000-0000-0000-0000-00000000fa04';
UPDATE public.users SET role = 'manager' WHERE id = '00000000-0000-0000-0000-00000000fa05';
UPDATE public.app_settings SET tax_rate = 10;
INSERT INTO public.customers(id,name,phone,credit_limit) VALUES
 ('00000000-0000-0000-0000-0000000fa0c1','Search Customer','03001234455',10000);
CREATE TEMP TABLE ids(label TEXT PRIMARY KEY, id UUID);
GRANT ALL ON ids TO authenticated;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000fa01","role":"authenticated"}';
SELECT FROM save_style('{"kind":"garment","code":"SEARCH","name":"Search kurta","taxable":true,
 "variants":[{"sku":"SEARCH-M","price":1000,"cost":400,"size":"M","opening_stock":30}]}');
INSERT INTO ids SELECT 'variant', id FROM product_variants WHERE sku = 'SEARCH-M';
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000fa02","role":"authenticated"}';
SELECT FROM open_cash_session(0);
INSERT INTO ids SELECT 'sale-a', (post_sale(jsonb_build_object('request_id',gen_random_uuid(),
 'customer_id','00000000-0000-0000-0000-0000000fa0c1',
 'lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT id FROM ids WHERE label='variant'),'quantity',2)),
 'payments','[{"method":"cash","amount":1200,"tendered":1300},{"method":"card","amount":1000,"card_last4":"4242"}]'::jsonb))->'sale'->>'id')::uuid;
INSERT INTO ids SELECT 'draft', (post_sale(jsonb_build_object('request_id',gen_random_uuid(),'status','draft',
 'customer_id','00000000-0000-0000-0000-0000000fa0c1',
 'lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT id FROM ids WHERE label='variant'),'quantity',1))))->'sale'->>'id')::uuid;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000fa03","role":"authenticated"}';
INSERT INTO ids SELECT 'sale-b', (post_sale(jsonb_build_object('request_id',gen_random_uuid(),
 'customer_id','00000000-0000-0000-0000-0000000fa0c1',
 'lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT id FROM ids WHERE label='variant'),'quantity',1)),
 'payments','[{"method":"credit"}]'::jsonb))->'sale'->>'id')::uuid;
-- A manager handles the return, so it is hidden by returns' ordinary cashier RLS.
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000fa01","role":"authenticated"}';
SELECT FROM open_cash_session(0);
SELECT FROM post_return(jsonb_build_object('request_id',gen_random_uuid(),'sale_id',(SELECT id FROM ids WHERE label='sale-a'),
 'reason','Wrong size','refund_method','cash','lines',jsonb_build_array(jsonb_build_object(
 'sale_line_id',(SELECT id FROM sale_lines WHERE sale_id=(SELECT id FROM ids WHERE label='sale-a')),'quantity',1))));

SELECT is((SELECT count(*)::int FROM search_sales()),3,'all visible sales');
SELECT is((SELECT count(*)::int FROM search_sales('{"from":"2000-01-01","to":"2000-01-02"}')),0,'date range excludes activity');
SELECT is((SELECT count(*)::int FROM search_sales(jsonb_build_object('from',(now() AT TIME ZONE report_tz())::date,'to',(now() AT TIME ZONE report_tz())::date))),3,'inclusive shop dates');
SELECT is((SELECT count(*)::int FROM search_sales('{"status":"draft"}')),1,'draft status');
SELECT is((SELECT count(*)::int FROM search_sales('{"status":"credit"}')),1,'credit status');
SELECT is((SELECT id FROM search_sales('{"status":"returned"}')),(SELECT id FROM ids WHERE label='sale-a'),'returned means any return');
SELECT results_eq($$ SELECT paid_methods,returned_amount,line_count FROM search_sales('{"method":"card"}') $$,
 $$ VALUES (ARRAY['card','cash']::text[],1100::numeric,1) $$,'split tender filter, full refund amount and line count');
SELECT is((SELECT id FROM search_sales(jsonb_build_object('q',(SELECT invoice_number FROM sales WHERE id=(SELECT id FROM ids WHERE label='sale-a'))))),
 (SELECT id FROM ids WHERE label='sale-a'),'invoice search');
SELECT is((SELECT count(*)::int FROM search_sales('{"q":"0300-1234455"}')),3,'local formatted phone search');
SELECT is((SELECT count(*)::int FROM search_sales('{"q":"SEARCH-M"}')),3,'SKU search');
SELECT is((SELECT count(*)::int FROM search_sales('{"q":"search customer"}')),3,'case insensitive customer name');
SELECT is((SELECT count(*)::int FROM search_sales('{"q":"%"}')),0,'search wildcards are literal');
SELECT is((SELECT total_count FROM search_sales('{"limit":1,"offset":1}')),3::bigint,'full count despite paging');
SELECT results_eq($$ SELECT id FROM search_sales('{"limit":1,"offset":1}') $$,
 $$ SELECT id FROM search_sales() OFFSET 1 LIMIT 1 $$,'stable page order for equal timestamps');
SELECT is((SELECT count(*)::int FROM search_sales('{"offset":99}')),0,'empty page');
SELECT is((sale_detail((SELECT id FROM ids WHERE label='sale-a'))->'lines'->0->>'returned_quantity')::numeric,1::numeric,'detail includes returned quantity');
SELECT is((SELECT count(*)::int FROM jsonb_array_elements(sale_detail((SELECT id FROM ids WHERE label='sale-a'))->'payments') p WHERE p->>'direction'='out'),1,'detail includes refund payment');
SELECT is((sale_detail((SELECT id FROM ids WHERE label='sale-a'))->'returns'->0->>'refund_total')::numeric,1100::numeric,'detail includes return document');
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000fa02","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM search_sales()),2,'cashier sees own sale and draft only');
SELECT is((SELECT id FROM search_sales('{"status":"draft"}')),(SELECT id FROM ids WHERE label='draft'),'own draft visible');
SELECT is(sale_detail((SELECT id FROM ids WHERE label='sale-b')),NULL::jsonb,'another cashier sale detail refused');
SELECT is((sale_detail((SELECT id FROM ids WHERE label='sale-a'))->'lines'->0->>'returned_quantity')::numeric,1::numeric,'own sale includes refund made by manager');
SELECT ok(NOT (sale_detail((SELECT id FROM ids WHERE label='sale-a'))->'lines'->0 ? 'unit_cost'),'cashier detail does not expose cost');
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000fa04","role":"authenticated"}';
SELECT throws_ok($$SELECT * FROM search_sales()$$,'42501',NULL,'inactive staff cannot search sales');
SELECT throws_ok($$SELECT sale_detail((SELECT id FROM ids WHERE label='sale-a'))$$,'42501',NULL,'inactive staff cannot get detail');
RESET ROLE;
SELECT ok(NOT has_function_privilege('anon','public.search_sales(jsonb)','EXECUTE'),'anonymous cannot search');
SELECT ok(NOT has_function_privilege('anon','public.sale_detail(uuid)','EXECUTE'),'anonymous cannot get detail');

-- Branch membership applies even to back-office roles.
INSERT INTO public.branches(id,code,name) VALUES ('00000000-0000-0000-0000-0000000fa0b1','TS-OTHER','Other branch');
INSERT INTO public.locations(id,branch_id,code,name,kind) VALUES
 ('00000000-0000-0000-0000-0000000fa0b2','00000000-0000-0000-0000-0000000fa0b1','FLOOR','Other floor','shop_floor');
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000fa01","role":"authenticated"}';
SELECT FROM save_style('{"kind":"garment","code":"TS-OTHER","name":"Other branch kurta",
 "location_id":"00000000-0000-0000-0000-0000000fa0b2","variants":[{"sku":"TS-OTHER","price":100,"opening_stock":10}]}');
INSERT INTO ids SELECT 'other', (post_sale(jsonb_build_object('request_id',gen_random_uuid(),
 'location_id','00000000-0000-0000-0000-0000000fa0b2',
 'lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT id FROM product_variants WHERE sku='TS-OTHER'),'quantity',1)),
 'payments','[{"method":"card","card_last4":"4242"}]'::jsonb))->'sale'->>'id')::uuid;
SELECT is((SELECT count(*)::int FROM search_sales()),4,'admin sees all branches');
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000fa05","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM search_sales()),3,'manager only sees member branch');
SELECT is(sale_detail((SELECT id FROM ids WHERE label='other')),NULL::jsonb,'manager cannot read other branch detail');
SELECT throws_ok($$ SELECT search_sales('{"status":"bad"}') $$,'22023',NULL,'invalid status refused');
SELECT throws_ok($$ SELECT search_sales('{"method":"bad"}') $$,'22023',NULL,'invalid method refused');
-- Fully refunded status is distinct from the has-any-return filter.
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000fa01","role":"authenticated"}';
SELECT FROM post_return(jsonb_build_object('request_id',gen_random_uuid(),'sale_id',(SELECT id FROM ids WHERE label='sale-a'),
 'reason','Second item returned','refund_method','cash','lines',jsonb_build_array(jsonb_build_object(
 'sale_line_id',(SELECT id FROM sale_lines WHERE sale_id=(SELECT id FROM ids WHERE label='sale-a')),'quantity',1))));
SELECT is((SELECT count(*)::int FROM search_sales('{"status":"refunded"}')),1,'fully refunded status filter');
SELECT is((SELECT count(*)::int FROM search_sales('{"status":"returned"}')),1,'returned filter includes fully refunded');
-- Isolate a local-midnight boundary without altering ledger amounts.
RESET ROLE;
SET LOCAL session_replication_role = replica;
UPDATE public.sales SET created_at = '2026-09-30 19:30:00+00' WHERE id=(SELECT id FROM ids WHERE label='sale-a');
SET LOCAL session_replication_role = origin;
SET LOCAL ROLE authenticated;
SELECT is((SELECT id FROM search_sales('{"from":"2026-10-01","to":"2026-10-01"}')),(SELECT id FROM ids WHERE label='sale-a'),'Karachi day includes previous UTC date');
SELECT is((SELECT count(*)::int FROM search_sales('{"from":"2026-09-30","to":"2026-09-30"}')),0,'local day excludes following midnight');
SELECT * FROM finish();
ROLLBACK;
