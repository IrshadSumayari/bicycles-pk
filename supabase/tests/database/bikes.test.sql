BEGIN;
SELECT no_plan();
-- Bike catalogue: specifications, bulky items, listing filters, delivery and assembly.
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-00000000b001','bikes-admin@t.local','{"name":"Bike Admin"}','{}'),
 ('00000000-0000-0000-0000-00000000b002','bikes-manager@t.local','{"name":"Bike Manager"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000b003','bikes-customer@t.local','{"name":"Bike Customer"}','{}');
UPDATE users SET active=true,role='manager' WHERE id='00000000-0000-0000-0000-00000000b002';
UPDATE app_settings SET tax_rate=0,delivery_fee=250,free_delivery_over=NULL,cod_enabled=true,cod_max_total=NULL,
 online_max_pending_orders=20,online_max_open_cod_orders=20,bulky_delivery_fee=1500,assembly_fee=NULL;
CREATE TEMP TABLE ids(key TEXT PRIMARY KEY,id UUID);
GRANT ALL ON ids TO authenticated,anon;
CREATE FUNCTION pg_temp.variant(k TEXT) RETURNS UUID LANGUAGE sql AS $$
 SELECT v.id FROM product_variants v JOIN ids ON ids.id=v.style_id WHERE ids.key=k ORDER BY v.sku LIMIT 1 $$;
CREATE FUNCTION pg_temp.cart(k TEXT,fulfil TEXT,assembly BOOLEAN DEFAULT NULL,qty INT DEFAULT 1) RETURNS JSONB LANGUAGE sql AS $$
 SELECT jsonb_build_object('fulfilment',fulfil,'lines',jsonb_build_array(jsonb_build_object('variant_id',pg_temp.variant(k),'quantity',qty)))
  ||CASE WHEN assembly IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('assembly',assembly) END $$;
CREATE FUNCTION pg_temp.titles(p JSONB) RETURNS TEXT LANGUAGE sql AS $$
 SELECT coalesce(string_agg(title,',' ORDER BY title),'') FROM catalog_list(p) $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated,anon;

-- Managers save bikes with specifications; bulky follows the request.
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000b002","role":"authenticated"}';
INSERT INTO ids SELECT 'city',save_style('{"code":"BK-CITY","name":"City Seven","kind":"item","category":"City & Commuter","brand":"Urbano",
 "bulky":true,"specs":{"wheel_size":"28\"","brakes":" Disc ","gears":"7-speed","colour":""},
 "variants":[{"sku":"BK-CITY-M","size":"M","color":"Black","price":60000,"opening_stock":3}]}');
INSERT INTO ids SELECT 'kids',save_style('{"code":"BK-KID","name":"Junior Sixteen","kind":"item","category":"16\" Bikes","brand":"Minis",
 "bulky":true,"specs":{"wheel_size":"16\"","brakes":"Rim"},"variants":[{"sku":"BK-KID-16","size":"16\"","color":"Red","price":20000}]}');
INSERT INTO ids SELECT 'helmet',save_style('{"code":"AC-HLM","name":"Road Helmet","kind":"item","category":"Helmets","brand":"Urbano",
 "variants":[{"sku":"AC-HLM-M","size":"M","color":"White","price":5000,"opening_stock":8}]}');
SELECT is((SELECT specs FROM product_styles WHERE id=(SELECT id FROM ids WHERE key='city')),
 '{"wheel_size":"28\"","brakes":"Disc","gears":"7-speed"}'::jsonb,'specs are trimmed and blanks dropped');
SELECT ok((SELECT bulky FROM product_styles WHERE id=(SELECT id FROM ids WHERE key='city')),'bike saved as bulky');
SELECT ok(NOT (SELECT bulky FROM product_styles WHERE id=(SELECT id FROM ids WHERE key='helmet')),'accessory not bulky by default');
SELECT save_style(jsonb_build_object('style_id',(SELECT id FROM ids WHERE key='city'),'code','BK-CITY','name','City Seven','kind','item',
 'category','City & Commuter','brand','Urbano','variants',jsonb_build_array(jsonb_build_object('variant_id',pg_temp.variant('city'),'sku','BK-CITY-M','size','M','color','Black','price',60000))));
SELECT ok((SELECT bulky AND specs->>'gears'='7-speed' FROM product_styles WHERE id=(SELECT id FROM ids WHERE key='city')),
 'omitting specs and bulky keeps them');
SELECT throws_ok($$SELECT save_style('{"code":"BAD","name":"Bad","variants":[{"sku":"BAD","price":1}],"specs":{"colour":"Red"}}')$$,
 'P0001','Use only the listed specifications, each up to 120 characters','unknown specification refused');
SELECT throws_ok($$SELECT save_style('{"code":"BAD","name":"Bad","variants":[{"sku":"BAD","price":1}],"bulky":"yes"}')$$,
 'P0001','Choose whether the item is bulky','bulky must be true or false');
SELECT throws_ok($$SELECT save_style('{"code":"BAD","name":"Bad","kind":"garment","variants":[{"sku":"BAD","price":1}]}')$$,
 'P0001','Invalid product kind: garment','only item, pack and service kinds');
-- Publish all three.
RESET ROLE;
UPDATE product_styles SET published=true,slug=lower(code) WHERE id IN (SELECT id FROM ids);
UPDATE product_variants SET published=true WHERE style_id IN (SELECT id FROM ids);

-- Listing filters and facets for signed-out visitors.
SET LOCAL ROLE anon;
SET LOCAL "request.jwt.claims"='{"role":"anon"}';
SELECT is(pg_temp.titles('{"categories":["City & Commuter","16\" Bikes"]}'),'City Seven,Junior Sixteen','section lists its categories');
SELECT is(pg_temp.titles('{"brand":"Urbano"}'),'City Seven,Road Helmet','brand filter');
SELECT is(pg_temp.titles('{"wheel_size":"16\""}'),'Junior Sixteen','wheel size filter');
SELECT is(pg_temp.titles('{"brakes":"Disc"}'),'City Seven','brakes filter');
SELECT is(pg_temp.titles('{"gears":"7-speed"}'),'City Seven','gears filter');
SELECT is(pg_temp.titles('{"in_stock":true,"categories":["City & Commuter","16\" Bikes"]}'),'City Seven','in-stock filter hides sold-out bikes');
SELECT is(pg_temp.titles('{"q":"minis"}'),'Junior Sixteen','search matches the brand');
SELECT is(catalog_facets(NULL)->'brands','["Minis","Urbano"]'::jsonb,'brand facet');
SELECT is(catalog_facets(NULL)->'wheel_sizes','["16\"","28\""]'::jsonb,'wheel size facet');
SELECT is(catalog_facets(NULL)->'brakes','["Disc","Rim"]'::jsonb,'brakes facet');
SELECT ok(NOT (catalog_facets(NULL) ? 'band'),'no clothing facets');
SELECT is(catalog_product('bk-city')->'specs'->>'gears','7-speed','product returns specs');
SELECT ok((catalog_product('bk-city')->>'bulky')::boolean,'product returns bulky');
SELECT ok(NOT (catalog_product('bk-city') ? 'size_chart'),'no clothing size chart');

-- Delivery: bulky charge per bike, assembly only when offered.
SELECT is((quote_online_order(pg_temp.cart('city','delivery'))->>'delivery_fee')::numeric,1750::numeric,'bulky charge added to delivery');
SELECT is((quote_online_order(pg_temp.cart('city','delivery',NULL,2))->>'bulky_fee')::numeric,3000::numeric,'bulky charge per unit');
SELECT is((quote_online_order(pg_temp.cart('helmet','delivery'))->>'delivery_fee')::numeric,250::numeric,'accessory pays the normal fee');
SELECT is((quote_online_order(pg_temp.cart('city','pickup'))->>'delivery_fee')::numeric,0::numeric,'pickup is free');
SELECT ok(NOT (quote_online_order(pg_temp.cart('city','delivery'))->>'assembly_available')::boolean,'assembly off when no fee is set');
SELECT throws_ok($$SELECT quote_online_order(pg_temp.cart('city','delivery',true))$$,'P0001','Assembly is not available for this order','assembly refused when not offered');
RESET ROLE;

-- Only administrators set the bulky and assembly fees.
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000b002","role":"authenticated"}';
SELECT throws_ok($$SELECT update_settings('{"assembly_fee":2000}')$$,'42501','Only administrators can change assembly_fee','managers cannot set assembly');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000b001","role":"authenticated"}';
SELECT is((update_settings('{"assembly_fee":2000}')->>'assembly_fee')::numeric,2000::numeric,'admin sets assembly fee');
SELECT throws_ok($$SELECT update_settings('{"bulky_delivery_fee":-1}')$$,'P0001','Enter a non-negative amount with up to two decimals for bulky_delivery_fee','negative fee refused');
SELECT is(update_settings('{"assembly_fee":null}')->'assembly_fee','null'::jsonb,'null turns assembly off');
SELECT is((update_settings('{"assembly_fee":2000}')->>'assembly_fee')::numeric,2000::numeric,'assembly offered again');
RESET ROLE;

SET LOCAL ROLE anon;
SET LOCAL "request.jwt.claims"='{"role":"anon"}';
SELECT is((quote_online_order(pg_temp.cart('city','delivery',true))->>'assembly_fee')::numeric,2000::numeric,'assembly priced per bike');
SELECT is((quote_online_order(pg_temp.cart('city','delivery',true))->>'total')::numeric,63750::numeric,'total includes delivery, bulky and assembly');
SELECT throws_ok($$SELECT quote_online_order(pg_temp.cart('helmet','delivery',true))$$,'P0001','Assembly is not available for this order','no assembly without a bike');
RESET ROLE;

-- The order records assembly.
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000b003","role":"authenticated"}';
INSERT INTO ids SELECT 'order',(create_online_order(pg_temp.cart('city','delivery',true)||jsonb_build_object('request_id',gen_random_uuid(),
 'payment_method','cod','contact_name','Bike Customer','phone','03001234567','address',jsonb_build_object('line1','1 Mall Road','city','Lahore')))->>'id')::uuid;
RESET ROLE;
SELECT ok((SELECT assembly FROM online_orders WHERE id=(SELECT id FROM ids WHERE key='order')),'order saved with assembly');
SELECT is((SELECT total FROM online_orders WHERE id=(SELECT id FROM ids WHERE key='order')),63750::numeric,'order total matches the quote');

SELECT * FROM finish();
ROLLBACK;
