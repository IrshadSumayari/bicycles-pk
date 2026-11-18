BEGIN;
SELECT no_plan();
SELECT is((SELECT online_card_enabled FROM public.app_settings ORDER BY created_at,id LIMIT 1),false,'card and wallet default off');
UPDATE public.app_settings SET cod_enabled=true,cod_max_total=NULL;
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-00000000da01','deploy-admin@t.local','{"name":"Admin"}','{}'),
 ('00000000-0000-0000-0000-00000000da02','deploy-manager@t.local','{"name":"Manager"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000da03','deploy-customer@t.local','{"name":"Customer"}','{}');
SELECT app_private.bootstrap_admin('deploy-admin@t.local'); -- first administrator (no longer the first sign-up)
UPDATE public.users SET active=true,role='manager' WHERE id='00000000-0000-0000-0000-00000000da02';
INSERT INTO public.product_styles(id,code,name,kind,unit,published,slug) VALUES
 ('00000000-0000-0000-0000-00000000daa1','DEPLOY-ITEM','Deploy item','item','piece',true,'deploy-item');
INSERT INTO public.product_variants(id,style_id,sku,price,published) VALUES
 ('00000000-0000-0000-0000-00000000dab1','00000000-0000-0000-0000-00000000daa1','DEPLOY-ITEM-1',100,true);
SELECT public.post_stock_movement((SELECT id FROM locations WHERE code='FLOOR'),'00000000-0000-0000-0000-00000000dab1',20,'opening');
CREATE FUNCTION pg_temp.payload(method TEXT) RETURNS JSONB LANGUAGE sql AS $$
 SELECT jsonb_build_object('request_id',gen_random_uuid(),'fulfilment','pickup','contact_name','Customer','phone','03009998888','payment_method',method,
 'lines',jsonb_build_array(jsonb_build_object('variant_id','00000000-0000-0000-0000-00000000dab1','quantity',1)))
$$;
GRANT EXECUTE ON FUNCTION pg_temp.payload(TEXT) TO anon,authenticated;
SET LOCAL ROLE anon;
SELECT is(public.quote_online_order(pg_temp.payload('cod'))->'payment_methods','["cod"]'::jsonb,'anonymous quote exposes only COD at launch');
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000da03","role":"authenticated","aal":"aal2"}';
SELECT is(public.create_online_order(pg_temp.payload('cod'))->>'status','placed','COD creates an order while card is off');
SELECT throws_ok($$SELECT public.create_online_order(pg_temp.payload('card'))$$,'P0001','Card and wallet payments are not available yet','card refused by database');
SELECT throws_ok($$SELECT public.create_online_order(pg_temp.payload('easypaisa'))$$,'P0001','Card and wallet payments are not available yet','wallet refused by database');
SELECT throws_ok($$SELECT public.update_settings(jsonb_build_object('request_id',gen_random_uuid(),'online_card_enabled',true))$$,'42501','Only managers can change settings','customer cannot enable');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000da02","role":"authenticated","aal":"aal2"}';
SELECT throws_ok($$SELECT public.update_settings(jsonb_build_object('request_id',gen_random_uuid(),'online_card_enabled',true))$$,'42501','Only administrators can change online_card_enabled','manager cannot enable');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000da01","role":"authenticated","aal":"aal2"}';
SELECT is((public.update_settings(jsonb_build_object('request_id',gen_random_uuid(),'online_card_enabled',true))->>'online_card_enabled')::boolean,true,'admin enables card and wallet');
SELECT throws_ok($$SELECT public.update_settings(jsonb_build_object('request_id',gen_random_uuid(),'online_card_enabled','yes'))$$,'P0001','Choose on or off for online_card_enabled','switch requires a boolean');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000da03","role":"authenticated","aal":"aal2"}';
SELECT is(public.quote_online_order(pg_temp.payload('card'))->'payment_methods','["card","easypaisa","cod"]'::jsonb,'quote lists all explicitly enabled methods');
SELECT is(public.create_online_order(pg_temp.payload('card'))->>'status','pending_payment','card can create a pending order after opt-in');
SELECT * FROM finish();
ROLLBACK;
