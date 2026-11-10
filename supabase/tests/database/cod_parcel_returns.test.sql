BEGIN;
SELECT no_plan();
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-0000000cc001','parcel-admin@t.local','{}','{}'),
 ('00000000-0000-0000-0000-0000000cc002','parcel-customer@t.local','{}','{}'),
 ('00000000-0000-0000-0000-0000000cc003','parcel-cashier@t.local','{}','{"account_type":"staff"}');
UPDATE users SET active=true,role='cashier' WHERE id='00000000-0000-0000-0000-0000000cc003';
UPDATE app_settings SET cod_enabled=true,delivery_fee=250,free_delivery_over=NULL,cod_max_total=NULL,tax_rate=0,online_max_open_cod_orders=20;
INSERT INTO product_styles(id,code,name,kind,unit,published,slug,taxable) VALUES
 ('00000000-0000-0000-0000-0000000cca01','PARCEL-RING','Parcel ring','item','piece',true,'parcel-ring',false);
INSERT INTO product_variants(id,style_id,sku,price,published) VALUES
 ('00000000-0000-0000-0000-0000000ccb01','00000000-0000-0000-0000-0000000cca01','PARCEL-RING-1',100,true);
SELECT post_stock_movement((SELECT id FROM locations WHERE code='FLOOR'),'00000000-0000-0000-0000-0000000ccb01',20,'opening');
CREATE TEMP TABLE work(key TEXT PRIMARY KEY,value JSONB);
GRANT ALL ON work TO authenticated;
CREATE FUNCTION pg_temp.parcel(k TEXT) RETURNS UUID LANGUAGE sql AS $$ SELECT (value->>'id')::uuid FROM work WHERE key=k $$;
CREATE FUNCTION pg_temp.payload(k TEXT,condition TEXT DEFAULT 'resaleable') RETURNS JSONB LANGUAGE sql AS $$
 SELECT jsonb_build_object('id',pg_temp.parcel(k),'request_id',gen_random_uuid(),'reason','Recipient refused; parcel physically inspected','courier_cost',300,
 'lines',jsonb_build_array(jsonb_build_object('variant_id','00000000-0000-0000-0000-0000000ccb01','condition',condition))) $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-0000000cc002","role":"authenticated"}';
INSERT INTO work SELECT k,create_online_order(jsonb_build_object('request_id',gen_random_uuid(),'payment_method','cod','fulfilment','delivery',
 'contact_name','Test Customer','phone','03001234567','address',jsonb_build_object('line1','Test address','city','Islamabad'),
 'lines',jsonb_build_array(jsonb_build_object('variant_id','00000000-0000-0000-0000-0000000ccb01','quantity',2)))) FROM unnest(ARRAY['good','damaged','paid','not_shipped']) k;
SELECT throws_ok($$SELECT receive_cod_parcel_return('{}')$$,'42501','Not authorized','customer denied before validation');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-0000000cc003","role":"authenticated"}';
SELECT throws_ok($$SELECT receive_cod_parcel_return('{}')$$,'42501','Not authorized','cashier cannot receive courier returns');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-0000000cc001","role":"authenticated"}';
SELECT advance_online_order(jsonb_build_object('id',pg_temp.parcel(key),'request_id',gen_random_uuid(),'status','confirmed')) FROM work;
SELECT advance_online_order(jsonb_build_object('id',pg_temp.parcel(key),'request_id',gen_random_uuid(),'status','packed')) FROM work;
SELECT advance_online_order(jsonb_build_object('id',pg_temp.parcel(key),'request_id',gen_random_uuid(),'status','shipped','courier','Test courier','tracking_no','TEST-ONLY')) FROM work WHERE key<>'not_shipped';
SELECT throws_ok($$SELECT receive_cod_parcel_return(pg_temp.payload('not_shipped'))$$,'P0001',NULL,'packed parcel cannot be received as courier return');
SELECT throws_ok($$SELECT receive_cod_parcel_return(pg_temp.payload('good')||'{"reason":""}')$$,'P0001',NULL,'reason required');
SELECT throws_ok($$SELECT receive_cod_parcel_return(pg_temp.payload('good')||'{"courier_cost":-1}')$$,'P0001',NULL,'negative courier cost refused');
SELECT throws_ok($$SELECT receive_cod_parcel_return(pg_temp.payload('good')||'{"courier_cost":1.234}')$$,'P0001',NULL,'fractional paisa refused');
SELECT throws_ok($$SELECT receive_cod_parcel_return(pg_temp.payload('good')||'{"lines":[]}')$$,'P0001',NULL,'missing inspected items refused');
SELECT throws_ok($$SELECT receive_cod_parcel_return(pg_temp.payload('good',''))$$,'P0001',NULL,'condition is explicit');
INSERT INTO work VALUES('request',pg_temp.payload('good'));
INSERT INTO work VALUES('result',receive_cod_parcel_return((SELECT value FROM work WHERE key='request')));
SELECT is((SELECT value->>'cash_refund' FROM work WHERE key='result'),'0','no cash refunded for unpaid COD');
SELECT is((SELECT status FROM online_orders WHERE id=pg_temp.parcel('good')),'returned_to_sender','terminal order status recorded');
SELECT is((SELECT payment_status FROM online_orders WHERE id=pg_temp.parcel('good')),'unpaid','COD is not marked paid/refunded');
SELECT is((SELECT courier_cost FROM courier_returns WHERE order_id=pg_temp.parcel('good')),300::numeric,'actual courier cost recorded separately');
SELECT is((SELECT sum(on_hand) FROM stock_balances WHERE variant_id='00000000-0000-0000-0000-0000000ccb01'),14::numeric,'only returned resaleable units restored to original stock');
SELECT is(receive_cod_parcel_return((SELECT value FROM work WHERE key='request')),(SELECT value FROM work WHERE key='result'),'same request retry returns same receipt');
SELECT throws_ok($$SELECT receive_cod_parcel_return(pg_temp.payload('good'))$$,'P0001',NULL,'new request cannot receive same parcel twice');
SELECT is((SELECT count(*)::int FROM payments WHERE sale_id=(SELECT sale_id FROM online_orders WHERE id=pg_temp.parcel('good'))),0,'no incoming or outgoing payment fabricated');
SELECT is((SELECT refund_total FROM returns WHERE sale_id=(SELECT sale_id FROM online_orders WHERE id=pg_temp.parcel('good'))),450::numeric,'sale value including delivery reversed for reporting');
SELECT is((SELECT count(*)::int FROM return_lines WHERE return_id=(SELECT return_id FROM courier_returns WHERE order_id=pg_temp.parcel('good'))),2,'goods and delivery reversal lines retained');
SELECT lives_ok($$SELECT receive_cod_parcel_return(pg_temp.payload('damaged','damaged'))$$,'damaged parcel accepted without restocking');
SELECT is((SELECT sum(on_hand) FROM stock_balances WHERE variant_id='00000000-0000-0000-0000-0000000ccb01'),14::numeric,'damaged items stay out of sellable stock');
SELECT open_cash_session(0);
SELECT collect_cod_payment(jsonb_build_object('id',pg_temp.parcel('paid'),'request_id',gen_random_uuid(),'payments',jsonb_build_array(jsonb_build_object('method','cash','amount',450))));
SELECT throws_ok($$SELECT receive_cod_parcel_return(pg_temp.payload('paid'))$$,'P0001',NULL,'collected COD must use paid return workflow');
SELECT throws_ok($$SELECT advance_online_order(jsonb_build_object('id',pg_temp.parcel('good'),'request_id',gen_random_uuid(),'status','delivered'))$$,'P0001',NULL,'returned order cannot be delivered');
SELECT * FROM finish();
ROLLBACK;
