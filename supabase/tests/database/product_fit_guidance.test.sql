BEGIN;
SELECT no_plan();
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-00000000fa01','guide-admin@t.local','{}','{}'),
 ('00000000-0000-0000-0000-00000000fa02','guide-customer@t.local','{}','{}'),
 ('00000000-0000-0000-0000-00000000fa03','guide-cashier@t.local','{}','{"account_type":"staff"}');
UPDATE users SET active=true,role='cashier' WHERE id='00000000-0000-0000-0000-00000000fa03';
INSERT INTO product_styles(id,code,name,kind,slug,published) VALUES
 ('00000000-0000-0000-0000-00000000fab1','GUIDE-A','Guide fixture','garment','guide-fixture',true),
 ('00000000-0000-0000-0000-00000000fab2','GUIDE-HIDDEN','Hidden guide','garment','guide-hidden',false);
INSERT INTO product_variants(style_id,sku,size,price,published) VALUES('00000000-0000-0000-0000-00000000fab1','GUIDE-A-S','S',100,true);
CREATE TEMP TABLE guide_fixture(value JSONB,result JSONB); GRANT ALL ON guide_fixture TO authenticated; GRANT SELECT ON guide_fixture TO anon;
INSERT INTO guide_fixture(value) VALUES('{"fit":"Relaxed fit, supplier confirmed","care":"Follow care label","included":"Top and trousers","size_chart":{"unit":"cm","basis":"body","source":"Supplier chart A","rows":[{"size":"S","bust":"84–88","waist":"64–68"},{"size":"M","bust":"89–93","hips":"94–98"}]}}');
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fa02","role":"authenticated"}';
SELECT throws_ok($$SELECT save_style_web_details('00000000-0000-0000-0000-00000000fab1','{}',gen_random_uuid())$$,'42501',NULL,'customer cannot edit product charts');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fa03","role":"authenticated"}';
SELECT throws_ok($$SELECT save_style_web_details('00000000-0000-0000-0000-00000000fab1','{}',gen_random_uuid())$$,'42501',NULL,'cashier cannot edit product charts');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fa01","role":"authenticated"}';
UPDATE guide_fixture SET result=save_style_web_details('00000000-0000-0000-0000-00000000fab1',jsonb_build_object('product_guide',value),'00000000-0000-0000-0000-00000000faf1');
SELECT is((SELECT product_guide FROM product_styles WHERE code='GUIDE-A'),(SELECT value FROM guide_fixture),'guide persisted');
SELECT is((SELECT result->'product_guide' FROM guide_fixture),(SELECT value FROM guide_fixture),'saved response includes guide');
SELECT is(save_style_web_details('00000000-0000-0000-0000-00000000fab1','{"product_guide":{}}','00000000-0000-0000-0000-00000000faf1'),(SELECT result FROM guide_fixture),'retry returns original guide without clearing');
SELECT FROM save_style_web_details('00000000-0000-0000-0000-00000000fab1','{"web_title":"New title"}',gen_random_uuid());
SELECT is((SELECT product_guide FROM product_styles WHERE code='GUIDE-A'),(SELECT value FROM guide_fixture),'legacy save preserves guide');
SELECT is((SELECT count(*)::int FROM product_variants WHERE style_id='00000000-0000-0000-0000-00000000fab1'),1,'editorial guide does not create variants');
SELECT is((SELECT price FROM product_variants WHERE sku='GUIDE-A-S'),100::numeric,'editorial guide leaves price unchanged');
SELECT throws_ok($$SELECT save_style_web_details('00000000-0000-0000-0000-00000000fab1','{"product_guide":{"cost":10}}',gen_random_uuid())$$,'P0001',NULL,'private guide keys refused');
SELECT throws_ok($$SELECT save_style_web_details('00000000-0000-0000-0000-00000000fab1','{"web_title":"Should roll back","product_guide":{"size_chart":{"unit":"cm","basis":"body","source":"Supplier","rows":[{"size":"S"}]}}}',gen_random_uuid())$$,'P0001',NULL,'empty measurement row refused');
SELECT is((SELECT web_title FROM product_styles WHERE code='GUIDE-A'),'New title','invalid guide rolls back all editorial changes');
SELECT ok(NOT app_private.valid_product_guide('{"size_chart":{"unit":"cm","basis":"body","source":"Supplier","rows":[{"size":"S","bust":"90","cost":"20"}]}}'),'nested private chart fields refused');
SELECT ok(NOT app_private.valid_product_guide('{"size_chart":{"unit":"cm","basis":"body","source":"Supplier","rows":[{"size":"S","bust":"90"},{"size":" s ","bust":"92"}]}}'),'duplicate sizes refused');
SELECT ok(NOT app_private.valid_product_guide('{"size_chart":{"unit":"","basis":"body","source":"Supplier","rows":[{"size":"S","bust":"90"}]}}'),'missing unit refused');
SELECT ok(NOT app_private.valid_product_guide('{"size_chart":{"unit":"cm","basis":"","source":"Supplier","rows":[{"size":"S","bust":"90"}]}}'),'missing measurement basis refused');
SELECT ok(NOT app_private.valid_product_guide('{"size_chart":{"unit":"cm","basis":"body","source":" ","rows":[{"size":"S","bust":"90"}]}}'),'missing chart source refused');
SELECT ok(app_private.valid_product_guide('{"size_chart":{"unit":"in","basis":"garment","source":"Supplier","rows":[{"size":"34DD","bust":"34–36"}]}}'),'garment inch chart accepted literally');
SET LOCAL ROLE anon;
SELECT is(catalog_product('guide-fixture')->'product_guide',(SELECT value FROM guide_fixture),'published guide available anonymously');
SELECT is(catalog_product('guide-hidden'),NULL::jsonb,'draft guide unavailable');
SELECT ok(NOT has_schema_privilege('anon','app_private','USAGE'),'validator not a public RPC');
SELECT ok(NOT(catalog_product('guide-fixture')::text ~ '"(cost|unit_cost|on_hand|reserved|supplier_id)"'),'no private inventory fields exposed');
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fa01","role":"authenticated"}';
SELECT FROM save_style_web_details('00000000-0000-0000-0000-00000000fab1','{"product_guide":{}}',gen_random_uuid());
SELECT is((SELECT product_guide FROM product_styles WHERE code='GUIDE-A'),'{}'::jsonb,'explicit empty guide clears optional information');
RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
