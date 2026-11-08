BEGIN;
SELECT plan(88);
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-000000007101','web-admin@t.local','{"name":"Admin"}','{}'),
 ('00000000-0000-0000-0000-000000007102','web-manager@t.local','{"name":"Manager"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-000000007103','web-cashier@t.local','{"name":"Cashier"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-000000007104','web-customer@t.local','{"name":"Website customer"}','{}');
UPDATE users SET role='manager',active=true WHERE id='00000000-0000-0000-0000-000000007102';
UPDATE users SET active=true WHERE id='00000000-0000-0000-0000-000000007103';
INSERT INTO categories(id,name) VALUES('00000000-0000-0000-0000-0000000071c1','Web shirts'),('00000000-0000-0000-0000-0000000071c2','Web trousers');
UPDATE size_schemes SET size_chart='{"unit":"inches","rows":[{"size":"S","chest":36}]}' WHERE code='LETTER';
INSERT INTO product_styles(id,code,name,kind,slug,published,active,category_id,size_scheme_id,created_at,taxable) VALUES
 ('00000000-0000-0000-0000-0000000071a1','WEB-A',E'100%_Back\\slash shirt','garment','web-a',true,true,'00000000-0000-0000-0000-0000000071c1',(SELECT id FROM size_schemes WHERE code='LETTER'),'2026-01-01',false),
 ('00000000-0000-0000-0000-0000000071a2','WEB-B','Blue shirt','garment','web-b',true,true,'00000000-0000-0000-0000-0000000071c1',NULL,'2026-01-02',false),
 ('00000000-0000-0000-0000-0000000071a3','WEB-C','Trousers','garment','web-c',true,true,'00000000-0000-0000-0000-0000000071c2',NULL,'2026-01-03',false),
 ('00000000-0000-0000-0000-0000000071a4','WEB-D','Draft','garment',NULL,false,true,NULL,NULL,now(),false),
 ('00000000-0000-0000-0000-0000000071a5','WEB-E','Inactive','garment','web-e',true,false,NULL,NULL,now(),false);
INSERT INTO product_variants(id,style_id,sku,size,color,price,compare_at_price,published,active) VALUES
 ('00000000-0000-0000-0000-0000000071b1','00000000-0000-0000-0000-0000000071a1','WEB-A-S','S','Red',100,125,true,true),
 ('00000000-0000-0000-0000-0000000071b2','00000000-0000-0000-0000-0000000071a1','WEB-A-M','M','Blue',150,180,true,true),
 ('00000000-0000-0000-0000-0000000071b3','00000000-0000-0000-0000-0000000071a1','WEB-A-HIDDEN','L','Green',9000,NULL,false,true),
 ('00000000-0000-0000-0000-0000000071b4','00000000-0000-0000-0000-0000000071a1','WEB-A-INACTIVE','XL','Black',8000,NULL,true,false),
 ('00000000-0000-0000-0000-0000000071b5','00000000-0000-0000-0000-0000000071a2','WEB-B-M','M','Red',200,NULL,true,true),
 ('00000000-0000-0000-0000-0000000071b6','00000000-0000-0000-0000-0000000071a3','WEB-C-L','L','White',50,NULL,true,true),
 ('00000000-0000-0000-0000-0000000071b7','00000000-0000-0000-0000-0000000071a4','WEB-D','M','Gold',0,NULL,true,true),
 ('00000000-0000-0000-0000-0000000071b8','00000000-0000-0000-0000-0000000071a5','WEB-E','M','Gold',200,NULL,true,true);
SELECT post_stock_movement((SELECT id FROM locations WHERE code='FLOOR'),'00000000-0000-0000-0000-0000000071b1',1,'opening');
SELECT post_stock_movement((SELECT id FROM locations WHERE code='FLOOR'),'00000000-0000-0000-0000-0000000071b5',10,'opening');
CREATE TEMP TABLE fixture(name TEXT PRIMARY KEY,value JSONB);
GRANT ALL ON fixture TO authenticated;
CREATE FUNCTION pg_temp.image_list(style UUID) RETURNS JSONB LANGUAGE sql AS $$
 SELECT jsonb_build_array(jsonb_build_object('storage_path','styles/'||style::text||'/front.webp','alt','Front','sort_order',1),
  jsonb_build_object('storage_path','styles/'||style::text||'/back.webp','alt','Back','sort_order',0)); $$;
GRANT EXECUTE ON FUNCTION pg_temp.image_list(UUID) TO authenticated;
-- Recursively inspect keys, including nested image, variant and chart objects.
CREATE FUNCTION pg_temp.has_private_key(doc JSONB) RETURNS BOOL LANGUAGE sql IMMUTABLE AS $$
 WITH RECURSIVE nodes(value) AS (
  SELECT doc UNION ALL SELECT child.value FROM nodes n CROSS JOIN LATERAL (
   SELECT o.value FROM jsonb_each(CASE WHEN jsonb_typeof(n.value)='object' THEN n.value ELSE '{}'::jsonb END) o
   UNION ALL SELECT a.value FROM jsonb_array_elements(CASE WHEN jsonb_typeof(n.value)='array' THEN n.value ELSE '[]'::jsonb END) a
  ) child)
 SELECT EXISTS(SELECT 1 FROM nodes n CROSS JOIN LATERAL jsonb_object_keys(CASE WHEN jsonb_typeof(n.value)='object' THEN n.value ELSE '{}'::jsonb END) k WHERE k ~ '(cost|supplier|on_hand|reserved|quantity)' OR k ~ '(^id$|_id$)' AND k NOT IN ('style_id','variant_id'));
$$;
GRANT EXECUTE ON FUNCTION pg_temp.has_private_key(JSONB) TO anon,authenticated;

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000007102","role":"authenticated"}';
INSERT INTO fixture VALUES('images',save_product_images('00000000-0000-0000-0000-0000000071a1',pg_temp.image_list('00000000-0000-0000-0000-0000000071a1'),'00000000-0000-0000-0000-000000071001'));
SELECT is(save_product_images('00000000-0000-0000-0000-0000000071a1','[]','00000000-0000-0000-0000-000000071001'),(SELECT value FROM fixture WHERE name='images'),'image retry returns original list');
SELECT is((SELECT count(*)::int FROM product_images),2,'retry does not replace saved images');
SELECT throws_ok($$ SELECT save_product_images('00000000-0000-0000-0000-0000000071a1','[{"storage_path":"styles/other/front.jpg"}]',gen_random_uuid()) $$,'P0001',NULL,'wrong prefix refused');
SELECT throws_ok($$ SELECT save_product_images('00000000-0000-0000-0000-0000000071a1','[{"storage_path":"styles/00000000-0000-0000-0000-0000000071a1/../other.jpg"}]',gen_random_uuid()) $$,'P0001',NULL,'path traversal refused');
INSERT INTO fixture VALUES('collection',save_collection(jsonb_build_object('request_id',gen_random_uuid(),'slug','web-main','name','Main','published',true)));
SELECT lives_ok($$ SELECT set_collection_styles((SELECT (value->>'id')::uuid FROM fixture WHERE name='collection'),ARRAY['00000000-0000-0000-0000-0000000071a1'::uuid,'00000000-0000-0000-0000-0000000071a2','00000000-0000-0000-0000-0000000071a4'],gen_random_uuid()) $$,'manager assigns collection styles');
SELECT lives_ok($$ INSERT INTO storage.objects(bucket_id,name) VALUES('product-images','manager-test.webp') $$,'manager can upload objects');
SELECT lives_ok($$ UPDATE storage.objects SET name='manager-renamed.webp' WHERE bucket_id='product-images' AND name='manager-test.webp' $$,'manager can update objects');
SELECT is(jsonb_array_length(publish_style('00000000-0000-0000-0000-0000000071a4',true,true)),3,'dry run lists missing slug, image and price');
SELECT is((SELECT published FROM product_styles WHERE id='00000000-0000-0000-0000-0000000071a4'),false,'dry run leaves publication unchanged');
SELECT throws_ok($$ SELECT publish_style('00000000-0000-0000-0000-0000000071a4',true) $$,'P0001',NULL,'invalid publication refused');
SELECT lives_ok($$ SELECT publish_style('00000000-0000-0000-0000-0000000071a1',true) $$,'manager can publish complete style');

RESET ROLE;
INSERT INTO collections(slug,name,published,starts_at,ends_at) VALUES
 ('web-hidden','Hidden',false,NULL,NULL),('web-future','Future',true,now()+interval '1 day',NULL),
 ('web-expired','Expired',true,NULL,now()-interval '1 second');
INSERT INTO collection_styles(collection_id,style_id) SELECT id,'00000000-0000-0000-0000-0000000071a3'::uuid FROM collections WHERE slug IN ('web-hidden','web-future','web-expired');
-- Check every prerequisite independently, not only the first validation error.
UPDATE product_styles SET slug='web-d' WHERE id='00000000-0000-0000-0000-0000000071a4';
UPDATE product_variants SET price=10 WHERE id='00000000-0000-0000-0000-0000000071b7';
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000007102","role":"authenticated"}';
SELECT throws_ok($$ SELECT publish_style('00000000-0000-0000-0000-0000000071a4',true) $$,'P0001','Cannot publish: Add at least one image','missing image refused');
SELECT FROM save_product_images('00000000-0000-0000-0000-0000000071a4',pg_temp.image_list('00000000-0000-0000-0000-0000000071a4'),gen_random_uuid());
RESET ROLE;
UPDATE product_styles SET slug=NULL WHERE id='00000000-0000-0000-0000-0000000071a4';
SET LOCAL ROLE authenticated;
SELECT throws_ok($$ SELECT publish_style('00000000-0000-0000-0000-0000000071a4',true) $$,'P0001','Cannot publish: Add a slug','missing slug refused');
RESET ROLE;
UPDATE product_styles SET slug='web-d' WHERE id='00000000-0000-0000-0000-0000000071a4';
UPDATE product_variants SET price=0 WHERE id='00000000-0000-0000-0000-0000000071b7';
SET LOCAL ROLE authenticated;
SELECT throws_ok($$ SELECT publish_style('00000000-0000-0000-0000-0000000071a4',true) $$,'P0001','Cannot publish: Add a published active variant with a price greater than zero','unpriced variant refused');
SELECT lives_ok($$ SELECT publish_style('00000000-0000-0000-0000-0000000071a4',false) $$,'unpublishing allowed without prerequisites');

SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000007103","role":"authenticated"}';
SELECT throws_ok($$ SELECT save_product_images('00000000-0000-0000-0000-0000000071a1','[]',gen_random_uuid()) $$,'42501',NULL,'cashier cannot save images');
SELECT throws_ok($$ SELECT save_collection('{}') $$,'42501',NULL,'cashier cannot save collections');
SELECT throws_ok($$ SELECT set_collection_styles('00000000-0000-0000-0000-0000000071a1','{}',gen_random_uuid()) $$,'42501',NULL,'cashier cannot set collection styles');
SELECT throws_ok($$ SELECT publish_style('00000000-0000-0000-0000-0000000071a1',false) $$,'42501',NULL,'cashier cannot publish');
SELECT throws_ok($$ INSERT INTO storage.objects(bucket_id,name) VALUES('product-images','cashier.webp') $$,'42501',NULL,'cashier upload refused');
WITH changed AS (UPDATE storage.objects SET name='stolen.webp' WHERE name='manager-renamed.webp' RETURNING id)
 SELECT is(count(*)::int,0,'cashier cannot update objects') FROM changed;
-- Emulate the Storage API's delete context; retain and test RLS itself.
SET LOCAL storage.allow_delete_query='true';
WITH removed AS (DELETE FROM storage.objects WHERE name='manager-renamed.webp' RETURNING id)
 SELECT is(count(*)::int,0,'cashier cannot delete objects') FROM removed;
SELECT throws_ok($$ INSERT INTO product_images(style_id,storage_path) VALUES('00000000-0000-0000-0000-0000000071a1','styles/00000000-0000-0000-0000-0000000071a1/direct.webp') $$,'42501',NULL,'direct image metadata writes refused');

SET LOCAL ROLE anon;
SET LOCAL "request.jwt.claims"='{"role":"anon"}';
SELECT is((SELECT count(*)::int FROM catalog_list('{}')),3,'only published active styles appear');
SELECT is(catalog_product('web-d'),NULL::jsonb,'draft product hidden');
SELECT is(catalog_product('web-e'),NULL::jsonb,'inactive product hidden');
SELECT is(catalog_product('unknown'),NULL::jsonb,'unknown product null');
SELECT is((SELECT array_agg(slug ORDER BY slug) FROM catalog_list('{"collection":"web-main"}')),ARRAY['web-a','web-b'],'collection filter');
SELECT is((SELECT count(*)::int FROM catalog_list('{"collection":"web-hidden"}')),0,'private collection cannot be used as a filter');
SELECT is((SELECT count(*)::int FROM catalog_list('{"collection":"web-future"}')),0,'future collection hidden');
SELECT is((SELECT count(*)::int FROM catalog_list('{"collection":"web-expired"}')),0,'expired collection hidden');
SELECT is((SELECT count(*)::int FROM catalog_list('{"category":"Web shirts"}')),2,'category filter');
SELECT is((SELECT count(*)::int FROM catalog_list('{"size":"M","color":"Blue"}')),1,'size and color filter');
SELECT is((SELECT count(*)::int FROM catalog_list('{"size":"S","color":"Blue"}')),0,'size and color must match the same variant');
SELECT is((SELECT count(*)::int FROM catalog_list('{"price_min":140,"price_max":160}')),1,'price range filter');
SELECT is((SELECT count(*)::int FROM catalog_list('{"q":"%"}')),1,'percent search is literal');
SELECT is((SELECT count(*)::int FROM catalog_list('{"q":"_"}')),1,'underscore search is literal');
SELECT is((SELECT count(*)::int FROM catalog_list(jsonb_build_object('q',E'\\'))),1,'backslash search is literal');
SELECT is((SELECT array_agg(slug) FROM catalog_list('{"sort":"new"}')),ARRAY['web-c','web-b','web-a'],'new sort');
SELECT is((SELECT array_agg(slug) FROM catalog_list('{"sort":"price_asc"}')),ARRAY['web-c','web-a','web-b'],'ascending price sort');
SELECT is((SELECT array_agg(slug) FROM catalog_list('{"sort":"price_desc"}')),ARRAY['web-b','web-a','web-c'],'descending price sort');
SELECT is((SELECT slug FROM catalog_list('{"sort":"price_asc","limit":1,"offset":1}')),'web-a','offset paging');
SELECT is((SELECT total_count FROM catalog_list('{"limit":1}')),3::bigint,'total count before paging');
SELECT is((SELECT min_price FROM catalog_list('{"q":"100"}')),100::numeric,'min price only visible variants');
SELECT is((SELECT max_price FROM catalog_list('{"q":"100"}')),150::numeric,'max price excludes inactive and unpublished variants');
SELECT is((SELECT sizes FROM catalog_list('{"q":"100"}')),ARRAY['M','S'],'size facets exclude hidden variants');
SELECT is((SELECT stock_level FROM catalog_list('{"q":"100"}')),'low_stock','any size availability');
SELECT is(jsonb_array_length(catalog_product('web-a')->'variants'),2,'only active published variants in detail');
SELECT is(catalog_product('web-a')->'images'->0->>'alt','Back','images sorted');
SELECT is(catalog_product('web-a')->'size_chart'->>'unit','inches','optional size chart returned');
SELECT is(catalog_product('web-b')->'size_chart','null'::jsonb,'no size chart yields null');
SELECT is(catalog_product('web-a')->'related'->0->>'slug','web-b','related styles from live collection only');
SELECT is((SELECT count(*)::int FROM catalog_collections()),1,'only collections inside publication window');
SELECT is(catalog_facets('web-main')->'sizes','["M","S"]'::jsonb,'collection sizes facets');
SELECT is((catalog_facets('web-main')->>'price_max')::numeric,200::numeric,'collection price facets');
SELECT is(catalog_facets('web-hidden')->'colors','[]'::jsonb,'hidden collection facets empty');
SELECT is(pg_temp.has_private_key(catalog_product('web-a')),false,'detail has no sensitive keys or internal ids');
SELECT is(pg_temp.has_private_key((SELECT jsonb_agg(to_jsonb(c)) FROM catalog_list('{}') c)),false,'list has no sensitive keys');
SELECT is(pg_temp.has_private_key((SELECT jsonb_agg(to_jsonb(c)) FROM catalog_collections() c)),false,'collections have no sensitive keys');
SELECT is(pg_temp.has_private_key(catalog_facets(NULL)),false,'facets have no sensitive keys');
SELECT throws_ok($$ SELECT * FROM product_styles $$,'42501',NULL,'anon cannot read styles');
SELECT throws_ok($$ SELECT * FROM product_variants $$,'42501',NULL,'anon cannot read variants');
SELECT throws_ok($$ SELECT * FROM variant_costs $$,'42501',NULL,'anon cannot read costs');
SELECT throws_ok($$ SELECT * FROM stock_balances $$,'42501',NULL,'anon cannot read stock');
SELECT throws_ok($$ SELECT * FROM product_images $$,'42501',NULL,'anon cannot read image metadata directly');
SELECT throws_ok($$ SELECT * FROM collections $$,'42501',NULL,'anon cannot read collections directly');
SELECT throws_ok($$ SELECT * FROM collection_styles $$,'42501',NULL,'anon cannot read membership directly');
SELECT throws_ok($$ SELECT * FROM catalog_style_rows() $$,'42501',NULL,'private catalog helper not callable');
SELECT lives_ok($$ SELECT * FROM public_catalog $$,'legacy public catalog view retained');

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000007104","role":"authenticated"}';
SELECT is(public.is_staff(),false,'website customer is not staff');
SELECT is((SELECT count(*)::int FROM customer_accounts WHERE id=auth.uid()),1,'website customer account exists');
SELECT is((SELECT count(*)::int FROM catalog_list('{}')),3,'website customer gets same list');
SELECT is(catalog_product('web-d'),NULL::jsonb,'website customer cannot see drafts');
SELECT is(catalog_product('web-a')->>'slug','web-a','website customer gets product detail');
SELECT is((SELECT count(*)::int FROM catalog_collections()),1,'website customer gets collections');
SELECT is(catalog_facets('web-main')->'sizes','["M","S"]'::jsonb,'website customer gets facets');
SELECT is((SELECT count(*)::int FROM product_images),0,'website customer cannot read staff image metadata');
SELECT throws_ok($$ INSERT INTO storage.objects(bucket_id,name) VALUES('product-images','customer.webp') $$,'42501',NULL,'website customer cannot upload');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000007102","role":"authenticated"}';
SELECT lives_ok($$ SELECT post_sale(jsonb_build_object('request_id',gen_random_uuid(),'lines','[{"variant_id":"00000000-0000-0000-0000-0000000071b1","quantity":1}]'::jsonb,'payments','[{"method":"card","amount":100,"card_last4":"4242"}]'::jsonb)) $$,'sell the last available size');
SET LOCAL ROLE anon;
SET LOCAL "request.jwt.claims"='{"role":"anon"}';
SELECT is((SELECT stock_level FROM catalog_list('{"q":"100"}')),'out_of_stock','stock band updates after last unit sold');
RESET ROLE;
SELECT is((SELECT file_size_limit FROM storage.buckets WHERE id='product-images'),5242880::bigint,'bucket file limit 5 MiB');
SELECT is((SELECT allowed_mime_types FROM storage.buckets WHERE id='product-images'),ARRAY['image/jpeg','image/png','image/webp'],'bucket permits only supported image types');
SELECT is((SELECT public FROM storage.buckets WHERE id='product-images'),true,'bucket public read');
-- More than one public page also exercises the cap and related-product bound.
INSERT INTO product_styles(code,name,kind,slug,published)
 SELECT 'WEB-CAP-'||n,'Cap item '||n,'garment','web-cap-'||n,true FROM generate_series(1,50) n;
INSERT INTO product_variants(style_id,sku,size,color,price)
 SELECT id,code,'M','Blue',75 FROM product_styles WHERE code LIKE 'WEB-CAP-%';
INSERT INTO collection_styles(collection_id,style_id)
 SELECT c.id,s.id FROM collections c CROSS JOIN product_styles s WHERE c.slug='web-main' AND s.code LIKE 'WEB-CAP-%';
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000007102","role":"authenticated"}';
WITH removed AS (DELETE FROM storage.objects WHERE bucket_id='product-images' AND name='manager-renamed.webp' RETURNING id)
 SELECT is(count(*)::int,1,'manager can delete objects through the Storage context') FROM removed;
SET LOCAL ROLE anon;
SET LOCAL "request.jwt.claims"='{"role":"anon"}';
SELECT is((SELECT count(*)::int FROM catalog_list('{"q":"Cap item","limit":500}')),48,'catalog page capped at 48');
SELECT is((SELECT min(total_count) FROM catalog_list('{"q":"Cap item","limit":500}')),50::bigint,'total count includes rows beyond page cap');
SELECT is((SELECT count(*)::int FROM catalog_list('{"q":"Cap item","limit":48,"offset":48}')),2,'last page keeps remaining rows');
SELECT is(jsonb_array_length(catalog_product('web-a')->'related'),8,'related styles capped at eight');
SELECT * FROM finish();
ROLLBACK;
