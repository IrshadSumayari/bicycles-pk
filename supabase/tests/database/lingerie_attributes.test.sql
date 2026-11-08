BEGIN;
SELECT no_plan();
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-0000000da001','lingerie-admin@t.local','{}','{}'),
 ('00000000-0000-0000-0000-0000000da002','lingerie-customer@t.local','{}','{}'),
 ('00000000-0000-0000-0000-0000000da003','lingerie-cashier@t.local','{}','{"account_type":"staff"}');
UPDATE users SET active=true,role='cashier' WHERE id='00000000-0000-0000-0000-0000000da003';
CREATE TEMP TABLE work(key TEXT PRIMARY KEY,id UUID);
GRANT ALL ON work TO authenticated;
CREATE FUNCTION pg_temp.style(code TEXT, attrs JSONB DEFAULT NULL) RETURNS JSONB LANGUAGE sql AS $$
 SELECT jsonb_build_object('kind','garment','code',code,'name',code,'category','Bras','material','Cotton',
 'variants',jsonb_build_array(jsonb_build_object('sku',code||'-34DD','size','34DD','color','Rose','price',100,'cost',31,'opening_stock',2)))
 || CASE WHEN attrs IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('lingerie',attrs) END $$;
GRANT EXECUTE ON FUNCTION pg_temp.style(TEXT,JSONB) TO authenticated;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-0000000da002","role":"authenticated"}';
SELECT throws_ok($$SELECT save_style('{}')$$,'42501','Not authorized','website customer refused before validation');
SELECT throws_ok($$SELECT save_style_base('{}')$$,'42501',NULL,'base save is private');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-0000000da003","role":"authenticated"}';
SELECT throws_ok($$SELECT save_style('{}')$$,'42501','Not authorized','cashier cannot edit attributes');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-0000000da001","role":"authenticated"}';
INSERT INTO work VALUES('a',save_style(pg_temp.style('LING-A','{"padding":"padded","wire":"wireless","coverage":"full","product_type":"t_shirt","composition":"95% cotton, 5% elastane","sizing_system":"UK"}') ||
 '{"variants":[{"sku":"LING-A-34DD","size":"34DD","color":"Rose","bra_band":"34","bra_cup":"DD","price":100,"cost":31,"opening_stock":2},{"sku":"LING-A-36E","size":"36E","color":"Black","bra_band":"36","bra_cup":"E","price":150,"opening_stock":3}]}'));
INSERT INTO work VALUES('b',save_style(pg_temp.style('LING-B','{"padding":"none","wire":"underwired","coverage":"medium","sizing_system":"EU"}'))),('legacy',save_style(pg_temp.style('LING-LEGACY'))),('hidden',save_style(pg_temp.style('LING-HIDDEN','{"padding":"removable","wire":"wireless","composition":"private fixture","sizing_system":"HIDDEN_SYSTEM"}')));
SELECT is((SELECT lingerie->>'padding' FROM product_styles WHERE id=(SELECT id FROM work WHERE key='a')),'padded','metadata saved through stock-safe RPC');
SELECT is((SELECT sum(on_hand) FROM stock_balances WHERE variant_id=(SELECT id FROM product_variants WHERE sku='LING-A-34DD')),2::numeric,'opening stock is unchanged by metadata extension');
SELECT throws_ok($$SELECT save_style(pg_temp.style('LING-PRIVATE','{"cost":"secret"}'))$$,'23514',NULL,'unapproved public JSON keys refused');
SELECT throws_ok($$SELECT save_style(pg_temp.style('LING-BAD','{"padding":"guess"}'))$$,'23514',NULL,'unknown enum refused');
SELECT is((SELECT count(*)::int FROM product_styles WHERE code IN('LING-PRIVATE','LING-BAD')),0,'failed metadata save rolls back style and opening stock');
SELECT throws_ok($$SELECT save_style(pg_temp.style('LING-PAIR')||'{"variants":[{"sku":"LING-PAIR-1","size":"34DD","bra_band":"34","price":100,"opening_stock":5}]}')$$,'P0001',NULL,'partial band/cup pair refused');
SELECT throws_ok($$SELECT save_style(pg_temp.style('LING-SYSTEM')||'{"variants":[{"sku":"LING-SYSTEM-1","size":"34DD","bra_band":"34","bra_cup":"DD","price":100}]}')$$,'P0001',NULL,'band and cup require supplier sizing system');
SELECT save_style(pg_temp.style('LING-A')||jsonb_build_object('style_id',(SELECT id FROM work WHERE key='a'),'variants',jsonb_build_array(jsonb_build_object('variant_id',(SELECT id FROM product_variants WHERE sku='LING-A-34DD'),'sku','LING-A-34DD','size','34DD','color','Rose','price',100))));
SELECT is((SELECT lingerie->>'wire' FROM product_styles WHERE id=(SELECT id FROM work WHERE key='a')),'wireless','older-client save preserves metadata');
SELECT is((SELECT bra_cup FROM product_variants WHERE sku='LING-A-34DD'),'DD','older-client save preserves explicit cup label');
RESET ROLE;
UPDATE product_styles SET published=true,slug=lower(code) WHERE code IN('LING-A','LING-B','LING-LEGACY');
UPDATE product_variants SET published=true WHERE style_id IN(SELECT id FROM work WHERE key<>'hidden');
INSERT INTO product_variants(style_id,sku,size,price,published,bra_band,bra_cup) SELECT id,'LING-SECRET','99Z',100,false,'99','Z' FROM work WHERE key='a';
SET LOCAL ROLE anon;
SELECT is((SELECT count(*)::int FROM catalog_list('{"padding":"padded"}')),1,'padded filter excludes non-padded');
SELECT is((SELECT count(*)::int FROM catalog_list('{"padding":"none"}')),1,'non-padded is its own exact value');
SELECT is((SELECT count(*)::int FROM catalog_list('{"wire":"underwired"}')),1,'underwired excludes wireless');
SELECT is((SELECT count(*)::int FROM catalog_list('{"wire":"wireless","padding":"none"}')),0,'style attribute filters combine exactly');
SELECT is((SELECT count(*)::int FROM catalog_list('{"band":"34","cup":"DD","sizing_system":"UK"}')),1,'explicit band/cup/system matches');
SELECT is((SELECT count(*)::int FROM catalog_list('{"band":"34","cup":"E","sizing_system":"UK"}')),0,'DD is not converted to E and variant dimensions must coincide');
SELECT is((SELECT count(*)::int FROM catalog_list('{"band":"34","cup":"DD","color":"Black"}')),0,'band/cup/color must be on the same visible variant');
SELECT is((SELECT count(*)::int FROM catalog_list('{"band":"99"}')),0,'hidden variant excluded from filters');
SELECT is((SELECT count(*)::int FROM catalog_list('{"padding":"removable"}')),0,'unpublished style excluded from filters');
SELECT is((SELECT count(*)::int FROM catalog_list('{"material":"Cotton","coverage":"full","product_type":"t_shirt"}')),1,'material, coverage and type filters combine');
SELECT is((SELECT count(*)::int FROM catalog_list('{"material":"Cot"}')),0,'material matching is exact');
SELECT is(catalog_facets(NULL)->>'lingerie_filters_version','1','capability version published');
SELECT is(catalog_facets(NULL)->'cup','["DD", "E"]'::jsonb,'facet cup labels stay distinct and exclude hidden variants');
SELECT is(catalog_facets(NULL)->'sizing_system','["EU", "UK"]'::jsonb,'facets exclude unpublished systems');
SELECT is(catalog_product('ling-legacy')->'lingerie','{}'::jsonb,'old product attributes remain unknown');
SELECT is(catalog_product('ling-a')->'lingerie'->>'composition','95% cotton, 5% elastane','only confirmed public composition shown');
SELECT ok(NOT(catalog_product('ling-a')::text ~ '"(cost|unit_cost|on_hand|reserved|supplier_id)"'),'product contract contains no cost, supplier or exact stock fields');
SELECT ok(NOT has_table_privilege('anon','public.product_styles','SELECT'),'new columns do not expose base styles table');
SELECT ok(NOT has_table_privilege('anon','public.product_variants','SELECT'),'new columns do not expose base variant table');
RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
