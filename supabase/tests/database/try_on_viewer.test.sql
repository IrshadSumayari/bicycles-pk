BEGIN;
SELECT no_plan();
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-00000000ab01','tryon-admin@t.local','{}','{}'),
 ('00000000-0000-0000-0000-00000000ab03','tryon-cashier@t.local','{}','{"account_type":"staff"}');
UPDATE users SET active=true,role='cashier' WHERE id='00000000-0000-0000-0000-00000000ab03';INSERT INTO product_styles(id,code,name,kind,slug,published) VALUES
 ('00000000-0000-0000-0000-00000000abb1','TRYON-A','Try-on fixture','garment','tryon-fixture',true),
 ('00000000-0000-0000-0000-00000000abb2','TRYON-B','Other style','garment','tryon-other',true);
INSERT INTO product_variants(style_id,sku,size,color,price,published) VALUES('00000000-0000-0000-0000-00000000abb1','TRYON-A-36B','36B','Rose',100,true);
CREATE TEMP TABLE tryon_fixture(value JSONB,result JSONB); GRANT ALL ON tryon_fixture TO authenticated; GRANT SELECT ON tryon_fixture TO anon;
INSERT INTO tryon_fixture(value) SELECT jsonb_build_object(
 'model_path','styles/00000000-0000-0000-0000-00000000abb1/11111111-2222-3333-4444-555555555555.glb',
 'garment_materials',jsonb_build_array('Lace'),
 'colors',jsonb_build_object('Rose','#c98a9b'),
 'models',jsonb_build_object('dusky',jsonb_build_object('Rose',(SELECT jsonb_agg('styles/00000000-0000-0000-0000-00000000abb1/spin/11111111-2222-3333-4444-55555555555'||g||'.webp') FROM generate_series(0,7) g)),
  'fair',jsonb_build_object('Rose',(SELECT jsonb_agg('styles/00000000-0000-0000-0000-00000000abb1/spin/11111111-2222-3333-4444-55555555556'||g||'.webp') FROM generate_series(0,3) g))));
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000ab03","role":"authenticated"}';
SELECT throws_ok($$SELECT save_style_web_details('00000000-0000-0000-0000-00000000abb1',jsonb_build_object('try_on',(SELECT value FROM tryon_fixture)),gen_random_uuid())$$,'42501',NULL,'cashier cannot edit 360° models');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000ab01","role":"authenticated"}';
UPDATE tryon_fixture SET result=save_style_web_details('00000000-0000-0000-0000-00000000abb1',jsonb_build_object('try_on',value),'00000000-0000-0000-0000-00000000abf1');
SELECT is((SELECT try_on FROM product_styles WHERE code='TRYON-A'),(SELECT value FROM tryon_fixture),'try-on persisted');
SELECT is((SELECT result->'try_on' FROM tryon_fixture),(SELECT value FROM tryon_fixture),'saved response includes try-on');
SELECT FROM save_style_web_details('00000000-0000-0000-0000-00000000abb1','{"web_title":"New title"}',gen_random_uuid());
SELECT is((SELECT try_on FROM product_styles WHERE code='TRYON-A'),(SELECT value FROM tryon_fixture),'older clients keep the saved try-on');
SELECT throws_ok($$SELECT save_style_web_details('00000000-0000-0000-0000-00000000abb2',jsonb_build_object('try_on',(SELECT value FROM tryon_fixture)),gen_random_uuid())$$,'P0001',NULL,'another style''s files refused');
SELECT throws_ok($$SELECT save_style_web_details('00000000-0000-0000-0000-00000000abb1','{"web_title":"Rolled back","try_on":{"colors":{"Rose":"pink"}}}',gen_random_uuid())$$,'P0001',NULL,'invalid shade refused');
SELECT is((SELECT web_title FROM product_styles WHERE code='TRYON-A'),'New title','invalid try-on rolls back editorial changes');
SELECT ok(NOT app_private.valid_try_on('{"models":{"fair":{"Rose":["styles/00000000-0000-0000-0000-00000000abb1/spin/11111111-2222-3333-4444-555555555555.webp"]}}}','00000000-0000-0000-0000-00000000abb1'),'too few model photos refused');
SELECT ok(NOT app_private.valid_try_on('{"models":{"olive":{}}}','00000000-0000-0000-0000-00000000abb1'),'unlisted skin tone refused');
SELECT ok(NOT app_private.valid_try_on('{"model_path":"styles/00000000-0000-0000-0000-00000000abb1/../x.glb"}','00000000-0000-0000-0000-00000000abb1'),'path traversal refused');
SELECT ok(NOT app_private.valid_try_on('{"video":"x"}','00000000-0000-0000-0000-00000000abb1'),'unknown keys refused');
SET LOCAL ROLE anon;
SELECT is(catalog_product('tryon-fixture')->'try_on',(SELECT value FROM tryon_fixture),'published try-on available anonymously');
SELECT is((SELECT angle_paths FROM catalog_list('{"q":"New title"}')),(SELECT array_agg(f) FROM jsonb_array_elements_text((SELECT value->'models'->'fair'->'Rose' FROM tryon_fixture)) f),'product card gets the first tone''s angle photos in order');
SELECT is((SELECT angle_paths FROM catalog_list('{"q":"Other style"}')),NULL::text[],'no angle photos without a set or extra photos');
RESET ROLE;
INSERT INTO product_images(style_id,variant_color,storage_path) VALUES('00000000-0000-0000-0000-00000000abb1','Rose',(SELECT value->'models'->'dusky'->'Rose'->>0 FROM tryon_fixture));
SET LOCAL ROLE anon;
SELECT is((SELECT angle_paths FROM catalog_list('{"q":"New title"}')),(SELECT array_agg(f) FROM jsonb_array_elements_text((SELECT value->'models'->'dusky'->'Rose' FROM tryon_fixture)) f),'product card turns the model shown in its main photo');
RESET ROLE;
SELECT is((SELECT public FROM storage.buckets WHERE id='try-on-models'),true,'3D model bucket is public for viewing');
SELECT is((SELECT allowed_mime_types FROM storage.buckets WHERE id='try-on-models'),ARRAY['model/gltf-binary'],'3D model bucket accepts only .glb');
SELECT * FROM finish();
ROLLBACK;
