BEGIN;
SELECT plan(48);
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-00000000fb01','admin@t.local','{"name":"Admin"}','{}'),
 ('00000000-0000-0000-0000-00000000fb02','cashier@t.local','{"name":"Cashier"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000fb03','inactive@t.local','{"name":"Inactive"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000fb04','manager@t.local','{"name":"Manager"}','{"account_type":"staff"}');
UPDATE users SET active=true;
UPDATE users SET active=false WHERE id='00000000-0000-0000-0000-00000000fb03';
UPDATE users SET role='manager' WHERE id='00000000-0000-0000-0000-00000000fb04';
INSERT INTO customers(id,name,phone,credit_limit) VALUES
 ('00000000-0000-0000-0000-00000000fbc1','Bilal','03001112233',10000),
 ('00000000-0000-0000-0000-00000000fbc2','Legacy','03001112234',10000),
 ('00000000-0000-0000-0000-00000000fbc3','Statement','03001112235',10000);
-- Emulate the pre-migration counter, then exercise exactly the upgrade helper.
SELECT set_config('app.customer_ledger','on',true);
UPDATE customers SET credit_used=250 WHERE id='00000000-0000-0000-0000-00000000fbc2';
SELECT set_config('app.customer_ledger','',true);
SELECT backfill_customer_ledger(); SELECT backfill_customer_ledger();
SELECT is((SELECT credit_used FROM customers WHERE name='Legacy'),250::numeric,'backfill does not double balance');
SELECT is((SELECT count(*)::int FROM customer_ledger WHERE entry_type='opening'),1,'backfill exactly once');
INSERT INTO customer_ledger(customer_id,entry_type,amount,created_at) VALUES
 ('00000000-0000-0000-0000-00000000fbc3','opening',500,'2026-01-01 18:59:59+00'),
 ('00000000-0000-0000-0000-00000000fbc3','payment',-100,'2026-01-01 19:00:00+00'),
 ('00000000-0000-0000-0000-00000000fbc3','adjustment',50,'2026-01-02 18:59:59+00');
UPDATE app_settings SET tax_rate=0;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fb01","role":"authenticated"}';
SELECT FROM save_style('{"kind":"garment","code":"CREDIT","name":"Shirt","variants":[{"sku":"CREDIT-M","size":"M","price":1000,"opening_stock":20},{"sku":"CREDIT-S","size":"S","price":500,"opening_stock":20}]}');
CREATE TEMP TABLE fixture(name TEXT PRIMARY KEY,value JSONB);
GRANT ALL ON fixture TO authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fb02","role":"authenticated"}';
INSERT INTO fixture VALUES('sale',post_sale(jsonb_build_object('request_id','00000000-0000-0000-0000-0000000fb001',
 'customer_id','00000000-0000-0000-0000-00000000fbc1',
 'lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT id FROM product_variants WHERE sku='CREDIT-M'),'quantity',3)),
 'payments','[{"method":"credit"}]'::jsonb)));
SELECT is((SELECT credit_used FROM customers WHERE name='Bilal'),3000::numeric,'credit sale balance');
SELECT is((SELECT amount FROM customer_ledger WHERE entry_type='sale_credit'),3000::numeric,'credit sale ledger');
SELECT ok((SELECT sale_id IS NOT NULL FROM customer_ledger WHERE entry_type='sale_credit'),'credit ledger links posted sale');
SELECT FROM post_return(jsonb_build_object('request_id','00000000-0000-0000-0000-0000000fb002',
 'sale_id',(SELECT value->'sale'->>'id' FROM fixture WHERE name='sale'),'reason','Wrong size','refund_method','credit',
 'lines',jsonb_build_array(jsonb_build_object('sale_line_id',(SELECT id FROM sale_lines LIMIT 1),'quantity',1))));
SELECT is((SELECT credit_used FROM customers WHERE name='Bilal'),2000::numeric,'return reduces balance');
SELECT is((SELECT amount FROM customer_ledger WHERE entry_type='return_credit'),-1000::numeric,'return ledger');
SELECT throws_ok($$ SELECT post_customer_payment('{"request_id":"00000000-0000-0000-0000-0000000fb010","customer_id":"00000000-0000-0000-0000-00000000fbc1","payments":[{"method":"cash","amount":600}]}') $$,'P0001','Open a cash shift before taking or refunding cash','cash collection needs shift');
SELECT FROM open_cash_session(100);
INSERT INTO fixture VALUES('payment',post_customer_payment('{"request_id":"00000000-0000-0000-0000-0000000fb010","customer_id":"00000000-0000-0000-0000-00000000fbc1","payments":[{"method":"cash","amount":600,"tendered":1000}]}'));
SELECT matches((SELECT value->>'payment_no' FROM fixture WHERE name='payment'),'^PAY-[0-9]{6}$','payment numbered');
SELECT is((SELECT credit_used FROM customers WHERE name='Bilal'),1400::numeric,'cashier can collect part of debt');
SELECT is((current_cash_session()->>'expected_cash')::numeric,700::numeric,'net collection, not tendered cash, enters drawer');
SELECT is((SELECT change_given FROM payments WHERE customer_payment_id IS NOT NULL),400::numeric,'change recorded');
SELECT is(post_customer_payment('{"request_id":"00000000-0000-0000-0000-0000000fb010","customer_id":"00000000-0000-0000-0000-00000000fbc1","payments":[]}'),(SELECT value FROM fixture WHERE name='payment'),'safe retry before validation');
SELECT is((SELECT count(*)::int FROM customer_payments),1,'retry creates no second header');
SELECT is((SELECT value->'payments'->0->>'method' FROM fixture WHERE name='payment'),'cash','receipt uses posted tender details, also on retries');
SELECT throws_ok($$ SELECT post_customer_payment('{"request_id":"00000000-0000-0000-0000-0000000fb011","customer_id":"00000000-0000-0000-0000-00000000fbc1","payments":[{"method":"card","amount":9999}]}') $$,'P0001',NULL,'overpayment denied');
SELECT throws_ok($$ SELECT post_customer_payment('{"request_id":"00000000-0000-0000-0000-0000000fb011","customer_id":"00000000-0000-0000-0000-00000000fbc1","payments":[{"method":"credit","amount":1}]}') $$,'P0001',NULL,'credit cannot collect credit');
SELECT throws_ok($$ SELECT post_customer_payment('{"request_id":"00000000-0000-0000-0000-0000000fb011","customer_id":"00000000-0000-0000-0000-00000000fbc1","payments":[{"method":"exchange","amount":1}]}') $$,'P0001',NULL,'exchange denied');
SELECT throws_ok($$ SELECT post_customer_payment('{"request_id":"00000000-0000-0000-0000-0000000fb011","customer_id":"00000000-0000-0000-0000-00000000fbc1","payments":[{"method":"cash","amount":0}]}') $$,'P0001',NULL,'zero denied');
SELECT throws_ok($$ SELECT adjust_customer_balance('00000000-0000-0000-0000-00000000fbc1',-100,'Write-off','00000000-0000-0000-0000-0000000fb012') $$,'42501',NULL,'cashier cannot adjust');
SELECT is((customer_statement('00000000-0000-0000-0000-00000000fbc3','2026-01-02','2026-01-02')->>'opening_balance')::numeric,500::numeric,'statement local day opening');
SELECT is((customer_statement('00000000-0000-0000-0000-00000000fbc3','2026-01-02','2026-01-02')->'entries'->0->>'balance')::numeric,400::numeric,'running balance');
SELECT is((customer_statement('00000000-0000-0000-0000-00000000fbc3','2026-01-02','2026-01-02')->>'closing_balance')::numeric,450::numeric,'statement local day closing');
SELECT is((SELECT count(*)::int FROM customers_with_balance('{"q":"Bilal"}')),1,'owes list search');
SELECT is((SELECT total_count FROM customers_with_balance('{"limit":1,"offset":1}')),3::bigint,'owes list paging total');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fb03","role":"authenticated"}';
SELECT throws_ok($$ SELECT post_customer_payment('{}') $$,'42501',NULL,'inactive staff cannot collect');
SELECT throws_ok($$ SELECT customer_statement('00000000-0000-0000-0000-00000000fbc1',current_date,current_date) $$,'42501',NULL,'inactive staff cannot read statements');
SELECT is((SELECT count(*)::int FROM customer_ledger),0,'inactive staff ledger RLS');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fb04","role":"authenticated"}';
SELECT throws_ok($$ SELECT adjust_customer_balance('00000000-0000-0000-0000-00000000fbc1',-100,' ','00000000-0000-0000-0000-0000000fb012') $$,'P0001',NULL,'adjustment needs reason');
SELECT is((adjust_customer_balance('00000000-0000-0000-0000-00000000fbc1',-100,'Write-off','00000000-0000-0000-0000-0000000fb012')->>'balance')::numeric,1300::numeric,'manager adjustment');
SELECT is((adjust_customer_balance('00000000-0000-0000-0000-00000000fbc1',-100,'Write-off','00000000-0000-0000-0000-0000000fb012')->>'balance')::numeric,1300::numeric,'adjustment retry');
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-00000000fb01","role":"authenticated"}';
SELECT throws_ok($$ UPDATE customers SET credit_used=1 WHERE name='Bilal' $$,'42501','The balance changes only through payments and sales','even admin cannot edit counter after ledger trigger');
SELECT lives_ok($$ UPDATE customers SET name='Bilal updated' WHERE name='Bilal' $$,'normal name edit works');
SELECT throws_ok($$ INSERT INTO customers(name,phone,credit_used) VALUES('Bad','03001112239',100) $$,'42501',NULL,'nonzero insert blocked');
SELECT throws_ok($$ INSERT INTO customer_ledger(customer_id,entry_type,amount) VALUES('00000000-0000-0000-0000-00000000fbc1','adjustment',999) $$,'42501',NULL,'direct ledger write blocked');
SELECT throws_ok($$ TRUNCATE customer_ledger $$,'42501',NULL,'counter staff cannot truncate ledger');
SELECT FROM post_exchange(jsonb_build_object('request_id','00000000-0000-0000-0000-0000000fb020',
 'sale_id',(SELECT value->'sale'->>'id' FROM fixture WHERE name='sale'),'reason','Smaller replacement','refund_method','credit',
 'return_lines',jsonb_build_array(jsonb_build_object('sale_line_id',(SELECT id FROM sale_lines WHERE sale_id=(SELECT (value->'sale'->>'id')::uuid FROM fixture WHERE name='sale') LIMIT 1),'quantity',1)),
 'new_lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT id FROM product_variants WHERE sku='CREDIT-S'),'quantity',1))));
SELECT is((SELECT credit_used FROM customers WHERE id='00000000-0000-0000-0000-00000000fbc1'),800::numeric,'exchange credit refund reduces debt');
SELECT FROM post_customer_payment('{"request_id":"00000000-0000-0000-0000-0000000fb022","customer_id":"00000000-0000-0000-0000-00000000fbc1","payments":[{"method":"card","amount":50,"card_last4":"4242"},{"method":"digital","amount":50,"reference":"BANK"}]}');
SELECT is((SELECT credit_used FROM customers WHERE id='00000000-0000-0000-0000-00000000fbc1'),700::numeric,'split card and digital collection');
SELECT is((SELECT count(*)::int FROM customer_ledger WHERE entry_type='payment' AND customer_id='00000000-0000-0000-0000-00000000fbc1'),2,'one ledger row per collection despite split tenders');
SELECT is((SELECT count(*)::int FROM jsonb_array_elements(customer_statement('00000000-0000-0000-0000-00000000fbc1','2000-01-01','2100-01-01')->'entries') e WHERE e->>'document_no' ~ '^PAY-[0-9]{6}$'),2,'statement links receipt headers');
SELECT is((SELECT count(*)::int FROM jsonb_array_elements(customer_statement('00000000-0000-0000-0000-00000000fbc1','2000-01-01','2100-01-01')->'entries') e WHERE e->>'document_no' ~ '^RTN-[0-9]{6}$'),2,'statement return documents');
RESET ROLE;
SET LOCAL "request.jwt.claims"='';
SELECT backfill_customer_ledger();
SELECT is((SELECT credit_used FROM customers WHERE id='00000000-0000-0000-0000-00000000fbc1'),700::numeric,'reapplying backfill skips accounts already backed by ledger');
SELECT is((SELECT count(*)::int FROM customer_ledger WHERE entry_type='opening' AND customer_id='00000000-0000-0000-0000-00000000fbc1'),0,'no spurious opening for a new account');
SELECT throws_ok($$ UPDATE customer_ledger SET note='Changed' $$,NULL,NULL,'ledger append only');
SELECT throws_ok($$ DELETE FROM customer_payments $$,NULL,NULL,'receipt header append only');
SELECT ok(NOT EXISTS(SELECT 1 FROM customers c WHERE coalesce(c.credit_used,0)<>(SELECT coalesce(sum(amount),0) FROM customer_ledger l WHERE l.customer_id=c.id)),'every cached balance equals its ledger sum');
SET LOCAL ROLE anon;
SELECT throws_ok($$ SELECT post_customer_payment('{}') $$,'42501',NULL,'anon cannot collect');
SELECT throws_ok($$ SELECT customer_statement('00000000-0000-0000-0000-00000000fbc1',current_date,current_date) $$,'42501',NULL,'anon cannot read statement');
SELECT * FROM finish();
ROLLBACK;
