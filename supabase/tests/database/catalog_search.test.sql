BEGIN;
SELECT plan(38);
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-000000507001','catalog-admin@t.local','{"name":"Admin"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-000000507002','catalog-cashier@t.local','{"name":"Cashier"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-000000507003','catalog-inactive@t.local','{"name":"Inactive staff"}','{"account_type":"staff"}');
UPDATE users SET role='admin',active=true WHERE id='00000000-0000-0000-0000-000000507001';
UPDATE users SET role='cashier',active=true WHERE id='00000000-0000-0000-0000-000000507002';
UPDATE users SET role='cashier',active=false WHERE id='00000000-0000-0000-0000-000000507003';
INSERT INTO categories(id,name) VALUES('00000000-0000-0000-0000-000000507010','Catalog test category'),
 ('00000000-0000-0000-0000-000000507014','Catalog other category');
INSERT INTO product_styles(id,code,name,kind,unit,taxable,category_id) VALUES
 ('00000000-0000-0000-0000-000000507011','CS-A','Zulu catalog','garment','piece',false,'00000000-0000-0000-0000-000000507010'),
 ('00000000-0000-0000-0000-000000507012','CS-B','Alpha CS-BAR','garment','piece',false,'00000000-0000-0000-0000-000000507010'),
 ('00000000-0000-0000-0000-000000507013','CS-F',E'Literal%_\\ pack','pack','set',false,NULL),
 ('00000000-0000-0000-0000-000000507015','CS-G','Other category ring','garment','piece',false,'00000000-0000-0000-0000-000000507014');
INSERT INTO product_variants(id,style_id,sku,size,price,active) VALUES
 ('00000000-0000-0000-0000-000000507021','00000000-0000-0000-0000-000000507011','CS-A','L',100,true),
 ('00000000-0000-0000-0000-000000507022','00000000-0000-0000-0000-000000507012','CS-B','M',100,true),
 ('00000000-0000-0000-0000-000000507023','00000000-0000-0000-0000-000000507013','CS-F',NULL,100,true),
 ('00000000-0000-0000-0000-000000507024','00000000-0000-0000-0000-000000507011','CS-INACTIVE','XS',100,false),
 ('00000000-0000-0000-0000-000000507025','00000000-0000-0000-0000-000000507015','CS-G',NULL,100,true);
INSERT INTO barcodes(variant_id,code) VALUES('00000000-0000-0000-0000-000000507021','CS-BAR');
SELECT post_stock_movement((SELECT id FROM locations WHERE kind='shop_floor' AND active ORDER BY created_at,id LIMIT 1),'00000000-0000-0000-0000-000000507021',10,'opening');
-- Fixed timestamps for the sort tests; the updated_at trigger is skipped here only.
SET LOCAL session_replication_role = replica;
UPDATE product_variants SET created_at='2026-01-01', updated_at='2026-01-01' WHERE sku LIKE 'CS-%';
UPDATE product_styles SET updated_at='2026-01-01' WHERE code LIKE 'CS-%';
UPDATE product_variants SET created_at='2026-03-01' WHERE sku='CS-B';
UPDATE product_styles SET updated_at='2026-04-01' WHERE code='CS-A';
SET LOCAL session_replication_role = origin;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000507001","role":"authenticated"}';
SELECT is((SELECT sku FROM search_variants('{"q":"cs-bar"}') LIMIT 1),'CS-A','Exact barcode precedes a partial name');
SELECT is((SELECT sku FROM search_variants('{"q":"cs-b"}') LIMIT 1),'CS-B','Exact SKU precedes partial name');
SELECT is((SELECT count(*)::int FROM search_variants('{"q":"Zulu catalog"}')),1,'Partial name finds active variant');
SELECT is((SELECT count(*)::int FROM search_variants('{"q":"%"}')),1,'Percent is literal');
SELECT is((SELECT count(*)::int FROM search_variants('{"q":"_"}')),1,'Underscore is literal');
SELECT is((SELECT count(*)::int FROM search_variants(jsonb_build_object('q',E'\\'))),1,'Backslash is literal');
SELECT is((SELECT count(*)::int FROM search_variants('{"category":"Catalog test category"}')),2,'Category filters');
SELECT is((SELECT count(*)::int FROM search_variants('{"kind":"pack","q":"CS-F"}')),1,'Kind filters');
SELECT is((SELECT count(*)::int FROM search_variants('{"categories":["Catalog test category","Catalog other category"],"q":"CS-"}')),3,'Category list includes every listed category');
SELECT is((SELECT count(*)::int FROM search_variants('{"categories":["Catalog other category"],"q":"CS-"}')),1,'Category list excludes unlisted categories');
SELECT is((SELECT count(*)::int FROM search_variants('{"categories":["Catalog other category"],"category":"Catalog test category"}')),0,'Category and category list both apply');
SELECT is((SELECT count(*)::int FROM search_variants('{"categories":"Catalog other category","q":"CS-"}')),4,'A non-list categories value is ignored');
SELECT is((SELECT total_count FROM search_variants('{"category":"Catalog test category","limit":1}')),2::bigint,'Count is before paging');
SELECT is((SELECT sku FROM search_variants('{"category":"Catalog test category","limit":1,"offset":1}')),'CS-A','Offset returns the next ordered item');
SELECT is((SELECT sku FROM search_variants('{"category":"Catalog test category","sort":"updated","limit":1}')),'CS-A','Recently updated style comes first');
SELECT is((SELECT sku FROM search_variants('{"category":"Catalog test category","sort":"newest","limit":1}')),'CS-B','Newest variant comes first');
SELECT is((SELECT sku FROM search_variants('{"category":"Catalog test category","sort":"other","limit":1}')),'CS-B','Unknown sort keeps name order');
SELECT is((SELECT count(*)::int FROM search_variants('{"q":"CS-INACTIVE"}')),0,'Inactive excluded by default');
SELECT is((SELECT count(*)::int FROM search_variants('{"q":"CS-INACTIVE","active_only":false}')),1,'Inactive can be requested explicitly');
SELECT reserve_stock('00000000-0000-0000-0000-000000507021',(SELECT id FROM locations WHERE kind='shop_floor' AND active ORDER BY created_at,id LIMIT 1),2,'pos','sales_tab',gen_random_uuid());
SELECT is((SELECT available FROM variant_by_code('CS-A')),8::numeric,'Reservation reduces availability');
SELECT post_sale('{"request_id":"00000000-0000-0000-0000-000000507099","lines":[{"variant_id":"00000000-0000-0000-0000-000000507021","quantity":1}],"payments":[{"method":"card","card_type":"visa","card_last4":"4242"}]}');
SELECT is((SELECT available FROM variant_by_code('CS-A')),7::numeric,'Sale reduces availability');
SELECT is((SELECT on_hand FROM variant_by_code('CS-A')),9::numeric,'On hand is distinct from available');
SELECT is((SELECT count(*)::int FROM variant_by_code('cs-bar')),1,'Barcode lookup returns one case-insensitive match');
SELECT is((SELECT count(*)::int FROM variant_by_code('CS-UNKNOWN')),0,'Unknown code returns no rows');
SELECT ok(NOT EXISTS(SELECT 1 FROM jsonb_object_keys((SELECT to_jsonb(r) FROM variant_by_code('CS-A')r)) key WHERE key ILIKE '%cost%'),'No cost column returned');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000507003","role":"authenticated"}';
SELECT throws_ok($$SELECT * FROM search_variants('{}')$$,'42501',NULL,'Inactive staff cannot search');
SELECT throws_ok($$SELECT * FROM variant_by_code('CS-A')$$,'42501',NULL,'Inactive staff cannot scan');
SET LOCAL ROLE anon;
SELECT throws_ok($$SELECT * FROM search_variants('{}')$$,'42501',NULL,'Anon cannot search');
SELECT throws_ok($$SELECT * FROM variant_by_code('CS-A')$$,'42501',NULL,'Anon cannot scan');
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000507002","role":"authenticated"}';
SELECT lives_ok($$SELECT * FROM search_variants('{"q":"CS-A"}')$$,'Cashier can search');
SELECT ok(NOT EXISTS(SELECT 1 FROM jsonb_object_keys((SELECT to_jsonb(r) FROM variant_by_code('CS-A')r)) key WHERE key ILIKE '%cost%'),'Cashier response has no cost');
SELECT is((SELECT count(*)::int FROM search_variants('{"category":"Catalog test category","limit":0}')),1,'Limit has a minimum of one');
SELECT is((SELECT sku FROM search_variants('{"category":"Catalog test category","limit":1,"offset":-5}')),'CS-B','Negative offset is clamped');
SELECT is((SELECT barcode FROM variant_by_code('CS-A')),'CS-BAR','Primary item barcode is retained for labels');
RESET ROLE;
SET LOCAL "request.jwt.claims"='';
INSERT INTO product_variants(style_id,sku,size,price) SELECT '00000000-0000-0000-0000-000000507011','CS-CAP-'||n,'CAP-'||n,100 FROM generate_series(1,201)n;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000507002","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM search_variants('{"q":"CS-CAP-","limit":999}')),200,'Limit is capped at 200');
SELECT is((SELECT max(total_count) FROM search_variants('{"q":"CS-CAP-","limit":999}')),201::bigint,'Capped page retains full total');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000507003","role":"authenticated"}';
SELECT throws_ok($$SELECT * FROM search_variants('{"limit":"bad","location_id":"bad"}')$$,'42501',NULL,'Check role before parsing filters');
RESET ROLE;
UPDATE product_styles SET active=false WHERE id='00000000-0000-0000-0000-000000507011';
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000507002","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM variant_by_code('CS-A')),0,'Barcode lookup excludes an inactive style');
SELECT * FROM finish();
ROLLBACK;
