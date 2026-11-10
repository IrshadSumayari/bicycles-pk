BEGIN;
SELECT plan(25);
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-00000000ac01','lookup-admin@test.local','{"name":"Lookup admin"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000ac02','lookup-cashier@test.local','{"name":"Lookup cashier"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000ac03','lookup-customer@test.local','{}','{}');
UPDATE public.users SET role='admin',active=true WHERE id='00000000-0000-0000-0000-00000000ac01';
UPDATE public.users SET active=true WHERE id='00000000-0000-0000-0000-00000000ac02';
CREATE TEMP TABLE lookup_test_ids(key TEXT PRIMARY KEY,id UUID);
GRANT ALL ON lookup_test_ids TO authenticated;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000ac01","role":"authenticated"}';

INSERT INTO lookup_test_ids VALUES('category',save_business_lookup('{"kind":"category","name":"Lookup Bicycles","description":"Owner-managed category"}'));
SELECT ok(EXISTS(SELECT 1 FROM categories WHERE id=(SELECT id FROM lookup_test_ids WHERE key='category')),'manager adds category');
SELECT throws_ok($$SELECT save_business_lookup('{"kind":"category","name":"lookup bicycles"}')$$,'P0001',NULL,'case-insensitive duplicates refused');
INSERT INTO lookup_test_ids VALUES('style',save_style('{"code":"LKP-CATALOG","name":"Lookup fixture bike","kind":"item","category":"Lookup Bicycles","brand":"Lookup Brand","track_inventory":false,"variants":[{"sku":"LKP-CATALOG-M","size":"M","color":"Lookup White","price":1000}]}'));
SELECT is((SELECT category_id FROM product_styles WHERE id=(SELECT id FROM lookup_test_ids WHERE key='style')),(SELECT id FROM lookup_test_ids WHERE key='category'),'real style keeps category identity');
SELECT FROM save_business_lookup(jsonb_build_object('kind','category','id',(SELECT id FROM lookup_test_ids WHERE key='category'),'name','Lookup Bicycles Renamed','active',false));
SELECT is((SELECT name FROM categories WHERE id=(SELECT category_id FROM product_styles WHERE id=(SELECT id FROM lookup_test_ids WHERE key='style'))),'Lookup Bicycles Renamed','category rename retains product relationship');
SELECT is((SELECT count(*)::int FROM categories WHERE id=(SELECT id FROM lookup_test_ids WHERE key='category') AND active),0,'inactive category excluded by dropdown query');
SELECT throws_ok($$SELECT delete_business_lookup('category',(SELECT id::text FROM lookup_test_ids WHERE key='category'))$$,'P0001',NULL,'used category cannot be deleted');
SELECT ok(EXISTS(SELECT 1 FROM product_styles WHERE code='LKP-CATALOG'),'deletion attempt does not remove product');

INSERT INTO lookup_test_ids VALUES('sizes',save_business_lookup('{"kind":"size_scheme","name":"Lookup Sizes","code":"LKP_SIZES","sizes":["L","S","L"]}'));
SELECT is((SELECT sizes FROM size_schemes WHERE id=(SELECT id FROM lookup_test_ids WHERE key='sizes')),ARRAY['L','S'],'size list retains ordering and removes duplicates');
UPDATE product_styles SET size_scheme_id=(SELECT id FROM lookup_test_ids WHERE key='sizes') WHERE id=(SELECT id FROM lookup_test_ids WHERE key='style');
SELECT throws_ok($$SELECT delete_business_lookup('size_scheme',(SELECT id::text FROM lookup_test_ids WHERE key='sizes'))$$,'P0001',NULL,'used size list cannot be deleted');
SELECT throws_ok($$SELECT save_business_lookup('{"kind":"size_scheme","name":"Bad sizes","code":"BAD","sizes":[]}')$$,'P0001',NULL,'empty size list refused');

SELECT ok(EXISTS(SELECT 1 FROM business_lookups WHERE kind='brand' AND value='Lookup Brand'),'actual product brand registered automatically');
SELECT FROM save_business_lookup(jsonb_build_object('kind','brand','id',(SELECT id FROM business_lookups WHERE kind='brand' AND value='Lookup Brand'),'name','Lookup New Brand'));
SELECT is((SELECT brand FROM product_styles WHERE code='LKP-CATALOG'),'Lookup New Brand','brand edit updates current catalog records');
SELECT ok(EXISTS(SELECT 1 FROM business_lookups WHERE kind='color' AND value='Lookup White'),'actual variant color registered automatically');
INSERT INTO lookup_test_ids VALUES('unused',save_business_lookup('{"kind":"material","name":"Lookup Unused Material"}'));
SELECT lives_ok($$SELECT delete_business_lookup('material',(SELECT id::text FROM lookup_test_ids WHERE key='unused'))$$,'unused value can be deleted');
SELECT is((SELECT count(*)::int FROM business_lookups WHERE id=(SELECT id FROM lookup_test_ids WHERE key='unused')),0,'deleted value no longer listed');

INSERT INTO lookup_test_ids VALUES('bank',save_business_lookup('{"kind":"bank","name":"Lookup Bank"}'));
INSERT INTO discounts(name,type,value,conditions,valid_from,valid_to,active) VALUES('Lookup bank promotion','percentage',1,'[{"type":"bank_name","value":"Lookup Bank","operator":"equals"}]',now()-interval '1 day',now()+interval '1 day',true);
SELECT FROM post_sale(jsonb_build_object('request_id','00000000-0000-0000-0000-00000000ad01','lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT id FROM product_variants WHERE sku='LKP-CATALOG-M'),'quantity',1)),
 'payments','[{"method":"card","bank_name":"Lookup Bank","card_last4":"1234"}]'::jsonb));
SELECT FROM save_business_lookup(jsonb_build_object('kind','bank','id',(SELECT id FROM lookup_test_ids WHERE key='bank'),'name','Lookup Renamed Bank'));
SELECT is((SELECT conditions->0->>'value' FROM discounts WHERE name='Lookup bank promotion'),'Lookup Renamed Bank','bank edit updates configured discount condition');
SELECT is((SELECT bank_name FROM payments WHERE sale_id=(SELECT id FROM sales WHERE request_id='00000000-0000-0000-0000-00000000ad01')),'Lookup Bank','posted payment snapshot preserved');
SELECT throws_ok($$SELECT delete_business_lookup('bank',(SELECT id::text FROM lookup_test_ids WHERE key='bank'))$$,'P0001',NULL,'configured bank cannot be deleted');

SELECT throws_ok($$SELECT save_business_lookup('{"kind":"customer_tier","name":"Standard"}')$$,'P0001',NULL,'default tier is a system fallback');
SELECT throws_ok($$SELECT save_business_lookup('{"kind":"return_reason","name":"Other"}')$$,'P0001',NULL,'free-text reason fallback is not duplicate data');
SELECT ok((SELECT count(*)>0 FROM lookup_events),'lookup changes have an audit trail');
SELECT is(has_table_privilege('authenticated','public.categories','DELETE'),false,'direct deletion cannot bypass used-category check');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000ac02","role":"authenticated"}';
SELECT throws_ok($$SELECT save_business_lookup('{"kind":"category","name":"Cashier category"}')$$,'42501',NULL,'cashier cannot edit lookups');
SELECT lives_ok($$SELECT value FROM business_lookups WHERE active$$,'cashier can read configured choices');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000ac03","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM business_lookups),0,'website customer cannot read staff lookup table');
SELECT * FROM finish();
ROLLBACK;
