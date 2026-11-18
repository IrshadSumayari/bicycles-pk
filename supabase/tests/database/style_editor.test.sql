-- save_style(): one style with a size x color matrix in one transaction.
BEGIN;
SELECT plan(17);

INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
    ('00000000-0000-0000-0000-00000000cc01', 'admin@t.local',   '{"name":"Admin"}', '{}'),
    ('00000000-0000-0000-0000-00000000cc02', 'cashier@t.local', '{"name":"Cashier"}', '{"account_type":"staff"}');
SELECT app_private.bootstrap_admin('admin@t.local'); -- first administrator (no longer the first sign-up)
UPDATE public.users SET active = true WHERE id = '00000000-0000-0000-0000-00000000cc02';

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000cc01","role":"authenticated","aal":"aal2"}';

CREATE TEMP TABLE saved (id UUID);
GRANT ALL ON saved TO authenticated;

SELECT lives_ok($$
    INSERT INTO saved SELECT save_style('{
        "kind":"item","code":"sk-001","name":"Classic City Bike","category":"City Bike",
        "brand":"House","material":"Aluminium","season":"2027","size_scheme":"FRAME",
        "variants":[
            {"sku":"sk-001-wht-m","size":"M","color":"White","price":4500,"cost":2000,"barcode":"SK001WM","opening_stock":4},
            {"sku":"sk-001-wht-l","size":"L","color":"White","price":4500,"cost":2000,"opening_stock":3},
            {"sku":"sk-001-blk-m","size":"M","color":"Black","price":4700,"cost":2100,"opening_stock":0},
            {"sku":"sk-001-blk-l","size":"L","color":"Black","price":4700,"cost":2100,"opening_stock":2}
        ]}')
$$, 'admin creates a style with four variants');
SELECT is((SELECT count(*)::int FROM product_variants WHERE style_id = (SELECT id FROM saved)), 4, 'four variants created');
SELECT is((SELECT code FROM product_styles WHERE id = (SELECT id FROM saved)), 'SK-001', 'style code stored in capitals');
SELECT is((SELECT sum(b.on_hand)::int FROM stock_balances b JOIN product_variants v ON v.id = b.variant_id
           WHERE v.style_id = (SELECT id FROM saved)), 9, 'opening stock posted per variant');
SELECT is((SELECT count(*)::int FROM stock_movements m JOIN product_variants v ON v.id = m.variant_id
           WHERE v.style_id = (SELECT id FROM saved)), 3, 'no movement for zero opening stock');
SELECT is((SELECT s.name FROM product_styles st JOIN size_schemes s ON s.id = st.size_scheme_id WHERE st.id = (SELECT id FROM saved)),
          'Frame sizes', 'size scheme linked');

-- Edit: change a price, add XL, keep stock untouched
SELECT lives_ok($$
    SELECT save_style(jsonb_build_object(
        'style_id', (SELECT id FROM saved), 'kind', 'item', 'code', 'SK-001', 'name', 'Classic City Bike',
        'variants', jsonb_build_array(
            jsonb_build_object('variant_id', (SELECT id FROM product_variants WHERE sku = 'SK-001-WHT-M'),
                               'sku', 'SK-001-WHT-M', 'size', 'M', 'color', 'White', 'price', 4800, 'opening_stock', 50),
            jsonb_build_object('sku', 'SK-001-WHT-XL', 'size', 'XL', 'color', 'White', 'price', 4800, 'opening_stock', 1))))
$$, 'admin edits the style and adds a size');
SELECT is((SELECT price FROM product_variants WHERE sku = 'SK-001-WHT-M'), 4800.00, 'price updated');
SELECT is((SELECT on_hand FROM stock_balances b JOIN product_variants v ON v.id = b.variant_id WHERE v.sku = 'SK-001-WHT-M'),
          4.000000, 'editing an existing variant never changes its stock');
SELECT is((SELECT count(*)::int FROM product_variants WHERE style_id = (SELECT id FROM saved)), 5, 'new size added');
SELECT is((SELECT count(*)::int FROM barcodes WHERE code = 'SK001WM'), 1, 'barcode kept when not sent');

-- Bulk editor payload updates every row and leaves quantities alone.
SELECT save_style(jsonb_build_object(
  'style_id',(SELECT id FROM saved),'kind','item','code','SK-001','name','Classic City Bike',
  'variants',(SELECT jsonb_agg(jsonb_build_object(
    'variant_id',id,'sku',sku,'size',size,'color',color,'fit',fit,'price',3490,'cost',1900))
    FROM product_variants WHERE style_id=(SELECT id FROM saved))));
SELECT is((SELECT count(*)::int FROM product_variants WHERE style_id=(SELECT id FROM saved) AND price=3490),5,'bulk prices persist on every variant');
SELECT is((SELECT count(*)::int FROM variant_costs c JOIN product_variants v ON v.id=c.variant_id WHERE v.style_id=(SELECT id FROM saved) AND c.unit_cost=1900),5,'bulk costs persist on every variant');
SELECT is((SELECT sum(b.on_hand)::int FROM stock_balances b JOIN product_variants v ON v.id=b.variant_id WHERE v.style_id=(SELECT id FROM saved)),10,'bulk pricing preserves stock balances');

-- Validation
SELECT throws_ok($$
    SELECT save_style('{"kind":"item","code":"DUP","name":"Dup","variants":[
        {"sku":"DUP-1","size":"M","color":"Red","price":1},{"sku":"DUP-2","size":"m","color":"red","price":1}]}')
$$, NULL, NULL, 'the same size and color cannot be listed twice');
SELECT throws_ok($$
    SELECT save_style('{"kind":"item","code":"OTHER","name":"Other","variants":[
        {"sku":"OTHER-1","price":1,"barcode":"SK001WM"}]}')
$$, NULL, NULL, 'a barcode cannot be reused by another style');

SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000cc02","role":"authenticated","aal":"aal2"}';
SELECT throws_ok($$
    SELECT save_style('{"kind":"item","code":"CHEAP","name":"Cheap","variants":[{"sku":"CHEAP-1","price":1}]}')
$$, '42501', NULL, 'cashier cannot edit styles');

SELECT * FROM finish();
ROLLBACK;
