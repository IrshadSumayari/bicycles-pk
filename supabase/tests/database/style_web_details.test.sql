BEGIN;
SELECT plan(22);
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-000000007201','details-admin@t.local','{"name":"Admin"}','{}'),
 ('00000000-0000-0000-0000-000000007202','details-manager@t.local','{"name":"Manager"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-000000007203','details-cashier@t.local','{"name":"Cashier"}','{"account_type":"staff"}');
SELECT app_private.bootstrap_admin('details-admin@t.local'); -- first administrator (no longer the first sign-up)
UPDATE users SET role='manager',active=true WHERE id='00000000-0000-0000-0000-000000007202';
UPDATE users SET active=true WHERE id='00000000-0000-0000-0000-000000007203';
INSERT INTO product_styles(id,code,name,kind,slug) VALUES
 ('00000000-0000-0000-0000-0000000072a1','DETAILS-A','First style','item',NULL),
 ('00000000-0000-0000-0000-0000000072a2','DETAILS-B','Second style','item','second-style');
INSERT INTO product_variants(id,style_id,sku,price) VALUES
 ('00000000-0000-0000-0000-0000000072b1','00000000-0000-0000-0000-0000000072a1','DETAILS-A',100),
 ('00000000-0000-0000-0000-0000000072b2','00000000-0000-0000-0000-0000000072a2','DETAILS-B',200);
CREATE TEMP TABLE fixture(value JSONB); GRANT ALL ON fixture TO authenticated;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000007202","role":"authenticated","aal":"aal2"}';
INSERT INTO fixture SELECT save_style_web_details('00000000-0000-0000-0000-0000000072a1','{"slug":"first-style","web_title":"Web title","web_description":"Web description","variants":[{"variant_id":"00000000-0000-0000-0000-0000000072b1","published":false}]}','00000000-0000-0000-0000-000000072001');
SELECT is((SELECT slug FROM product_styles WHERE code='DETAILS-A'),'first-style','manager saves slug');
SELECT is((SELECT web_title FROM product_styles WHERE code='DETAILS-A'),'Web title','manager saves title');
SELECT is((SELECT web_description FROM product_styles WHERE code='DETAILS-A'),'Web description','manager saves description');
SELECT is((SELECT published FROM product_variants WHERE sku='DETAILS-A'),false,'variant flag saved');
SELECT is(save_style_web_details('00000000-0000-0000-0000-0000000072a1','{"unknown":true}','00000000-0000-0000-0000-000000072001'),(SELECT value FROM fixture),'retry returns original before validating');
SELECT throws_ok($$ SELECT save_style_web_details('00000000-0000-0000-0000-0000000072a2','{}','00000000-0000-0000-0000-000000072001') $$,'42501',NULL,'request tied to style');
SELECT throws_ok($$ SELECT save_style_web_details('00000000-0000-0000-0000-0000000072a1','{"slug":"Bad Slug"}',gen_random_uuid()) $$,'P0001',NULL,'bad format refused');
SELECT lives_ok($$ SELECT save_style_web_details('00000000-0000-0000-0000-0000000072a1',jsonb_build_object('slug',repeat('a',120)),gen_random_uuid()) $$,'120-character web address accepted');
SELECT throws_ok($$ SELECT save_style_web_details('00000000-0000-0000-0000-0000000072a1',jsonb_build_object('slug',repeat('a',121)),gen_random_uuid()) $$,'P0001','Use a web address of at most 120 lowercase letters, numbers and hyphens','121-character web address refused');
SELECT FROM save_style_web_details('00000000-0000-0000-0000-0000000072a1','{"slug":"first-style"}',gen_random_uuid());
SELECT throws_ok($$ SELECT save_style_web_details('00000000-0000-0000-0000-0000000072a1','{"slug":"second-style"}',gen_random_uuid()) $$,'P0001','This web address is already used by Second style','duplicate names owning style');
SELECT throws_ok($$ SELECT save_style_web_details('00000000-0000-0000-0000-0000000072a1','{"variants":[{"variant_id":"00000000-0000-0000-0000-0000000072b2","published":true}]}',gen_random_uuid()) $$,'P0001','That variant does not belong to this style','foreign variant refused');
SELECT throws_ok($$ SELECT save_style_web_details('00000000-0000-0000-0000-0000000072a1','{"typo":1}',gen_random_uuid()) $$,'P0001','Unknown website detail: typo','unknown key named');
SELECT throws_ok($$ SELECT save_style_web_details('00000000-0000-0000-0000-0000000072a1',jsonb_build_object('web_title',repeat('x',151)),gen_random_uuid()) $$,'P0001',NULL,'title length checked');
SELECT throws_ok($$ SELECT save_style_web_details('00000000-0000-0000-0000-0000000072a1',jsonb_build_object('web_description',repeat('x',5001)),gen_random_uuid()) $$,'P0001',NULL,'description length checked');
SELECT FROM save_style_web_details('00000000-0000-0000-0000-0000000072a1','{"variants":[{"variant_id":"00000000-0000-0000-0000-0000000072b1","published":true}]}',gen_random_uuid());
SELECT is((SELECT web_title FROM product_styles WHERE code='DETAILS-A'),'Web title','omitted details preserved');
SELECT FROM save_product_images('00000000-0000-0000-0000-0000000072a1','[{"storage_path":"styles/00000000-0000-0000-0000-0000000072a1/front.webp"}]',gen_random_uuid());
SELECT lives_ok($$ SELECT publish_style('00000000-0000-0000-0000-0000000072a1',true) $$,'publish after setting details and image');
SELECT throws_ok($$ SELECT save_style_web_details('00000000-0000-0000-0000-0000000072a1','{"slug":null}',gen_random_uuid()) $$,'P0001','Unpublish before removing the web address','published slug cannot be cleared');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000007201","role":"authenticated","aal":"aal2"}';
SELECT throws_ok($$ SELECT save_style_web_details('00000000-0000-0000-0000-0000000072a1','{}','00000000-0000-0000-0000-000000072001') $$,'42501',NULL,'request tied to user');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-000000007203","role":"authenticated","aal":"aal2"}';
SELECT throws_ok($$ SELECT save_style_web_details('00000000-0000-0000-0000-0000000072a1','{}',gen_random_uuid()) $$,'42501',NULL,'cashier refused');
SET LOCAL ROLE anon;
SELECT throws_ok($$ SELECT save_style_web_details('00000000-0000-0000-0000-0000000072a1','{}',gen_random_uuid()) $$,'42501',NULL,'anon refused');
SELECT is(catalog_product('first-style')->>'title','Web title','public title updated');
SELECT is(catalog_product('first-style')->>'description','Web description','public description updated');
SELECT * FROM finish();
ROLLBACK;
