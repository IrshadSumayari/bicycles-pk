-- Full checkout/returns/exchange integration. All fixture data rolls back.
BEGIN;
SELECT plan(14);
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-00000000cf01','commission-admin@test.local','{"name":"Commission test admin"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000cf02','commission-seller@test.local','{"name":"Commission test seller"}','{"account_type":"staff"}');
SELECT app_private.bootstrap_admin('commission-admin@test.local'); -- first administrator (no longer the first sign-up)
UPDATE public.users SET role='admin',active=true WHERE id='00000000-0000-0000-0000-00000000cf01';
UPDATE public.users SET role='cashier',active=true WHERE id='00000000-0000-0000-0000-00000000cf02';
UPDATE public.app_settings SET tax_rate=10;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000cf01","role":"authenticated","aal":"aal2"}';
SELECT FROM save_style('{"kind":"item","code":"COMM-TEST","name":"Commission test bike","variants":[{"sku":"COMM-TEST-M","price":1000,"opening_stock":20}]}');
CREATE TEMP TABLE comm_ids AS SELECT id variant FROM public.product_variants WHERE sku='COMM-TEST-M';
GRANT SELECT ON comm_ids TO authenticated;
SELECT save_commission_rule(default_branch_id(),'00000000-0000-0000-0000-00000000cf02','fixed',100,true);
CREATE FUNCTION pg_temp.commission_sale(req UUID,qty NUMERIC) RETURNS JSONB LANGUAGE sql AS $$
 SELECT post_sale(jsonb_build_object('request_id',req,'salesperson_id','00000000-0000-0000-0000-00000000cf02',
 'lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT variant FROM comm_ids),'quantity',qty,'discount_type','percentage','discount_value',10)),
 'payments','[{"method":"digital"}]'::jsonb)) $$;
CREATE FUNCTION pg_temp.commission_return(req UUID,qty NUMERIC) RETURNS JSONB LANGUAGE sql AS $$
 SELECT post_return(jsonb_build_object('request_id',req,'sale_id',(SELECT id FROM sales WHERE request_id='00000000-0000-0000-0000-00000000ce01'),
 'reason','Commission fixture return','refund_method','digital','lines',jsonb_build_array(jsonb_build_object('sale_line_id',
 (SELECT sl.id FROM sale_lines sl JOIN sales s ON s.id=sl.sale_id WHERE s.request_id='00000000-0000-0000-0000-00000000ce01' AND NOT sl.is_gift),'quantity',qty)))) $$;
SELECT lives_ok($$ SELECT pg_temp.commission_sale('00000000-0000-0000-0000-00000000ce01',3) $$,'checkout with fixed commission');
SELECT is((SELECT original_amount FROM sale_commissions LIMIT 1),100::numeric,'fixed once per invoice, not per item');
SELECT is((SELECT basis FROM sale_commissions LIMIT 1),2700::numeric,'basis is after discount, before tax');
SELECT is((SELECT user_id FROM sale_commissions LIMIT 1),'00000000-0000-0000-0000-00000000cf02'::uuid,'salesperson differs from cashier');
SELECT FROM pg_temp.commission_sale('00000000-0000-0000-0000-00000000ce01',3);
SELECT is((SELECT count(*)::integer FROM commission_entries WHERE kind='earned'),1,'checkout retry does not double commission');
SELECT FROM record_commission_payout(default_branch_id(),'00000000-0000-0000-0000-00000000cf02',50,'Fixture transfer','00000000-0000-0000-0000-00000000ce09');
SELECT FROM pg_temp.commission_return('00000000-0000-0000-0000-00000000ce02',1);
SELECT is((SELECT -sum(amount) FROM commission_entries WHERE kind='return'),33.33::numeric,'one-third return reverses one-third commission, excluding tax');
SELECT FROM pg_temp.commission_return('00000000-0000-0000-0000-00000000ce03',2);
SELECT is((SELECT -sum(amount) FROM commission_entries WHERE kind='return'),100::numeric,'full return reverses exactly the original commission');
SELECT is((SELECT sum(amount) FROM commission_entries),(-50)::numeric,'paid commission carries a debit after full return');
SELECT lives_ok($$ SELECT record_commission_payout(default_branch_id(),'00000000-0000-0000-0000-00000000cf02',50,'Fixture transfer','00000000-0000-0000-0000-00000000ce09') $$,'payout retry is idempotent after a return');
SELECT save_commission_rule(default_branch_id(),'00000000-0000-0000-0000-00000000cf02','percentage',5,true);
SELECT FROM pg_temp.commission_sale('00000000-0000-0000-0000-00000000ce04',1);
SELECT is((SELECT original_amount FROM sale_commissions sc JOIN sales s ON s.id=sc.sale_id WHERE s.request_id='00000000-0000-0000-0000-00000000ce04'),45::numeric,'percentage uses discounted net sale');
SELECT is((SELECT original_amount FROM sale_commissions sc JOIN sales s ON s.id=sc.sale_id WHERE s.request_id='00000000-0000-0000-0000-00000000ce01'),100::numeric,'changing rule preserves previous invoice');
SELECT lives_ok($$ SELECT post_exchange(jsonb_build_object('request_id','00000000-0000-0000-0000-00000000ce05',
 'sale_id',(SELECT id FROM sales WHERE request_id='00000000-0000-0000-0000-00000000ce04'),'reason','Size exchange','refund_method','digital',
 'salesperson_id','00000000-0000-0000-0000-00000000cf02',
 'return_lines',jsonb_build_array(jsonb_build_object('sale_line_id',(SELECT sl.id FROM sale_lines sl JOIN sales s ON s.id=sl.sale_id WHERE s.request_id='00000000-0000-0000-0000-00000000ce04' AND NOT sl.is_gift),'quantity',1)),
 'new_lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT variant FROM comm_ids),'quantity',1)),
 'payments','[{"method":"digital"}]'::jsonb)) $$,'replacement sale earns commission within exchange transaction');
SELECT is((SELECT max(original_amount) FROM sale_commissions WHERE kind='percentage'),50::numeric,'replacement invoice has its own rate snapshot');
SELECT is(has_function_privilege('authenticated','public.post_sale_without_commission(jsonb)','EXECUTE'),false,'staff cannot bypass commission checkout wrapper');
SELECT * FROM finish();
ROLLBACK;
