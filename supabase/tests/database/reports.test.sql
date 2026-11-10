-- Hand-calculated ledger day, permissions, branch isolation and historical returns.
BEGIN;
SELECT plan(49);
SET LOCAL TIME ZONE 'UTC'; -- The report day must still be Karachi's day.

INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-00000000ef01','reports-admin@t.local','{"name":"Reports Admin"}','{}'),
 ('00000000-0000-0000-0000-00000000ef02','reports-cashier@t.local','{"name":"Reports Cashier"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000ef03','reports-inactive@t.local','{"name":"Reports Inactive"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000ef04','reports-manager@t.local','{"name":"Reports Manager"}','{"account_type":"staff"}');
UPDATE public.users SET active = true WHERE id IN
 ('00000000-0000-0000-0000-00000000ef02','00000000-0000-0000-0000-00000000ef04');
UPDATE public.users SET role = 'manager' WHERE id = '00000000-0000-0000-0000-00000000ef04';
UPDATE public.app_settings SET tax_rate = 10;
INSERT INTO public.customers(id, name, phone, credit_limit)
 VALUES ('00000000-0000-0000-0000-0000000ef0c1','Reports Customer','03001234987',5000);
INSERT INTO public.branches(id, code, name)
 VALUES ('00000000-0000-0000-0000-0000000ef0b1','REPORT-OTHER','Other report branch');
INSERT INTO public.locations(id, branch_id, code, name, kind)
 VALUES ('00000000-0000-0000-0000-0000000ef0b2','00000000-0000-0000-0000-0000000ef0b1','FLOOR','Other floor','shop_floor');

CREATE TEMP TABLE dates AS SELECT (now() AT TIME ZONE 'Asia/Karachi')::date AS d;
GRANT SELECT ON dates TO authenticated;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ef01","role":"authenticated"}';
SELECT FROM open_cash_session(0);
SELECT FROM save_style('{"kind":"item","code":"R-BIKE","name":"Report Bike","category":"Report Bicycles","taxable":true,
 "variants":[{"sku":"R-M","size":"M","color":"White","price":1000,"cost":400,"opening_stock":10},
             {"sku":"R-L","size":"L","color":"Blue","price":1000,"cost":400,"opening_stock":5}]}');
SELECT FROM save_style('{"kind":"pack","code":"R-PACK","name":"Report Gift Set","taxable":true,
 "variants":[{"sku":"R-F","color":"Grey","price":250,"cost":100,"opening_stock":20}]}');
CREATE TEMP TABLE ids AS SELECT
 (SELECT id FROM product_variants WHERE sku = 'R-M') AS m,
 (SELECT id FROM product_variants WHERE sku = 'R-L') AS l,
 (SELECT id FROM product_variants WHERE sku = 'R-F') AS pack,
 (SELECT style_id FROM product_variants WHERE sku = 'R-M') AS style;
GRANT SELECT ON ids TO authenticated;
CREATE TEMP TABLE sale AS SELECT post_sale(jsonb_build_object(
 'request_id','00000000-0000-0000-0000-0000000ef001',
 'lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT m FROM ids),'quantity',2,'discount_type','percentage','discount_value',10),
                         jsonb_build_object('variant_id',(SELECT pack FROM ids),'quantity',2)),
 'payments','[{"method":"cash","amount":1500,"tendered":1600},{"method":"card","amount":1030,"card_last4":"4242"}]'::jsonb)) AS result;
GRANT SELECT ON sale TO authenticated;
SELECT FROM post_return(jsonb_build_object('request_id','00000000-0000-0000-0000-0000000ef002',
 'sale_id',(SELECT result->'sale'->>'id' FROM sale),'reason','Wrong size','refund_method','cash',
 'lines',jsonb_build_array(jsonb_build_object('sale_line_id',(SELECT id FROM sale_lines WHERE variant_id = (SELECT m FROM ids)), 'quantity',1))));
SELECT FROM post_sale(jsonb_build_object('request_id','00000000-0000-0000-0000-0000000ef003','status','draft',
 'lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT m FROM ids),'quantity',5))));

SELECT results_eq($$ SELECT invoices, gross, discounts, net_sales, tax, returns, returns_tax,
 net_after_returns, cost, margin FROM report_sales_summary((SELECT d FROM dates),(SELECT d FROM dates)) $$,
 $$ VALUES (1,2500::numeric,200::numeric,2300::numeric,230::numeric,900::numeric,90::numeric,1400::numeric,600::numeric,800::numeric) $$,
 'summary uses line prices, discounts, tax and restocked cost, excluding drafts');
SELECT is((SELECT day FROM report_sales_summary((SELECT d FROM dates),(SELECT d FROM dates))), (SELECT d FROM dates), 'shop local day');
SELECT results_eq($$ SELECT money_in,money_out,net,count FROM report_tenders((SELECT d FROM dates),(SELECT d FROM dates)) WHERE method = 'cash' $$,
 $$ VALUES (1500::numeric,990::numeric,510::numeric,2) $$, 'cash subtracts change only once');
SELECT results_eq($$ SELECT money_in,money_out,net,count FROM report_tenders((SELECT d FROM dates),(SELECT d FROM dates)) WHERE method = 'card' $$,
 $$ VALUES (1030::numeric,0::numeric,1030::numeric,1) $$, 'split card tender');
SELECT is((SELECT count(*)::int FROM report_tenders((SELECT d FROM dates),(SELECT d FROM dates)) WHERE method = 'exchange'),0,'no internal exchange tender');
SELECT results_eq($$ SELECT quantity,net,cost,margin FROM report_top_items((SELECT d FROM dates),(SELECT d FROM dates)) WHERE label = 'Report Bike' $$,
 $$ VALUES (1::numeric,900::numeric,400::numeric,500::numeric) $$, 'style nets returned quantity, tax-exclusive refund and restocked cost');
SELECT results_eq($$ SELECT quantity,net FROM report_top_items((SELECT d FROM dates),(SELECT d FROM dates),NULL,'size') WHERE key = 'M' $$,
 $$ VALUES (1::numeric,900::numeric) $$,'size grouping');
SELECT is((SELECT key FROM report_top_items((SELECT d FROM dates),(SELECT d FROM dates),NULL,'variant',1)),(SELECT m::text FROM ids),'variant ranking and limit');
SELECT is((SELECT net FROM report_top_items((SELECT d FROM dates),(SELECT d FROM dates),NULL,'category') WHERE label = 'Report Bicycles'),900::numeric,'category grouping');
SELECT is((SELECT quantity FROM report_top_items((SELECT d FROM dates),(SELECT d FROM dates),NULL,'color') WHERE key = 'White'),1::numeric,'color grouping');
SELECT throws_ok($$ SELECT report_top_items(current_date,current_date,NULL,'bad') $$,'22023',NULL,'invalid group rejected');
SELECT throws_ok($$ SELECT report_top_items(current_date,current_date,NULL,'style',0) $$,'22023',NULL,'invalid limit rejected');
SELECT results_eq($$ SELECT size,color,sold,on_hand FROM report_size_color_matrix((SELECT d FROM dates),(SELECT d FROM dates),NULL,(SELECT style FROM ids)) $$,
 $$ VALUES ('L'::text,'Blue'::text,0::numeric,5::numeric),('M'::text,'White'::text,1::numeric,9::numeric) $$,'matrix includes unsold stock and net returns');
SELECT results_eq($$ SELECT user_id,invoices,net_sales,returns,discounts FROM report_staff_sales((SELECT d FROM dates),(SELECT d FROM dates)) $$,
 $$ VALUES ('00000000-0000-0000-0000-00000000ef01'::uuid,1,2300::numeric,900::numeric,200::numeric) $$,'staff report attributes returns to original cashier');
SELECT is((SELECT count(*)::int FROM report_sales_summary('2000-01-01','2000-01-02')),0,'empty sales period');
SELECT is((SELECT count(*)::int FROM report_tenders('2000-01-01','2000-01-02')),0,'empty tender period');
SELECT is((SELECT count(*)::int FROM report_top_items('2000-01-01','2000-01-02')),0,'empty item period');
SELECT is((SELECT count(*)::int FROM report_staff_sales('2000-01-01','2000-01-02')),0,'empty staff period');

-- Every public report must refuse both restricted roles before validation.
CREATE FUNCTION pg_temp.denied_reports() RETURNS SETOF TEXT LANGUAGE plpgsql AS $$
DECLARE f TEXT;
BEGIN
 FOREACH f IN ARRAY ARRAY['report_sales_summary','report_tenders','report_top_items',
     'report_size_color_matrix','report_staff_sales'] LOOP
   RETURN NEXT throws_ok(format('SELECT * FROM public.%I(current_date,current_date)',f),
       '42501','Only managers can see reports',current_app_role() || ' refused by ' || f);
 END LOOP;
END;
$$;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ef02","role":"authenticated"}';
SELECT * FROM pg_temp.denied_reports();
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ef03","role":"authenticated"}';
SELECT * FROM pg_temp.denied_reports();

-- A manager belongs only to MAIN. Explicit branch selection cannot bypass membership.
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ef04","role":"authenticated"}';
SELECT is((SELECT net_sales FROM report_sales_summary((SELECT d FROM dates),(SELECT d FROM dates))),2300::numeric,'manager can report own branch');
SELECT is((SELECT count(*)::int FROM report_size_color_matrix((SELECT d FROM dates),(SELECT d FROM dates),'00000000-0000-0000-0000-0000000ef0b1',(SELECT style FROM ids))),0,'matrix hides stock of inaccessible branch');

-- Fully refund the bike line: original revenue must remain in the report.
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ef01","role":"authenticated"}';
SELECT FROM post_return(jsonb_build_object('request_id','00000000-0000-0000-0000-0000000ef005',
 'sale_id',(SELECT result->'sale'->>'id' FROM sale),'reason','Damaged','refund_method','card',
 'lines',jsonb_build_array(jsonb_build_object('sale_line_id',(SELECT id FROM sale_lines WHERE variant_id = (SELECT m FROM ids) AND sale_id = (SELECT (result->'sale'->>'id')::uuid FROM sale)), 'quantity',1,'condition','damaged'))));
SELECT is((SELECT cost FROM report_sales_summary((SELECT d FROM dates),(SELECT d FROM dates))),600::numeric,'damaged return does not reverse cost');
SELECT FROM post_return(jsonb_build_object('request_id','00000000-0000-0000-0000-0000000ef006',
 'sale_id',(SELECT result->'sale'->>'id' FROM sale),'reason','Set fault','refund_method','card',
 'lines',jsonb_build_array(jsonb_build_object('sale_line_id',(SELECT id FROM sale_lines WHERE variant_id = (SELECT pack FROM ids)), 'quantity',2))));
SELECT is((SELECT status FROM sales WHERE id = (SELECT (result->'sale'->>'id')::uuid FROM sale)),'refunded','fixture fully refunded');
SELECT results_eq($$ SELECT invoices,net_sales,returns,net_after_returns,cost,margin FROM report_sales_summary((SELECT d FROM dates),(SELECT d FROM dates)) $$,
 $$ VALUES (1,2300::numeric,2300::numeric,0::numeric,400::numeric,-400::numeric) $$,'fully refunded invoice and damaged cost reconcile');

-- Time travel only fixture timestamps, without changing posted business values.
-- Move the original sale to yesterday at 00:30 Karachi (previous UTC day).
RESET ROLE;
SET LOCAL session_replication_role = replica;
UPDATE public.sales SET created_at = ((SELECT d - 1 FROM dates) + time '00:30') AT TIME ZONE 'Asia/Karachi'
 WHERE id = (SELECT (result->'sale'->>'id')::uuid FROM sale);
SET LOCAL session_replication_role = origin;
SET LOCAL ROLE authenticated;
SELECT results_eq($$ SELECT invoices,net_sales,returns,cost FROM report_sales_summary((SELECT d FROM dates),(SELECT d FROM dates)) $$,
 $$ VALUES (0,0::numeric,2300::numeric,-600::numeric) $$,'return-only day uses return date and original cost');
SELECT results_eq($$ SELECT invoices,net_sales,returns FROM report_sales_summary((SELECT d - 1 FROM dates),(SELECT d - 1 FROM dates)) $$,
 $$ VALUES (1,2300::numeric,0::numeric) $$,'inclusive local date retains previous day sale');


-- Actual exchange payments must be excluded, even when there is a nonzero ledger amount.
CREATE TEMP TABLE exchange_sale AS SELECT post_sale(jsonb_build_object('request_id','00000000-0000-0000-0000-0000000ef008',
 'lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT l FROM ids),'quantity',1)),
 'payments','[{"method":"card","amount":1100,"card_last4":"4242"}]'::jsonb)) AS result;
SELECT FROM post_exchange(jsonb_build_object('request_id','00000000-0000-0000-0000-0000000ef009',
 'sale_id',(SELECT result->'sale'->>'id' FROM exchange_sale),'reason','Change size',
 'return_lines',jsonb_build_array(jsonb_build_object('sale_line_id',
    (SELECT id FROM sale_lines WHERE sale_id = (SELECT (result->'sale'->>'id')::uuid FROM exchange_sale)), 'quantity',1)),
 'new_lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT m FROM ids),'quantity',1))));
SELECT ok(EXISTS(SELECT 1 FROM payments WHERE method = 'exchange'),'exchange fixture has internal tender');
SELECT is((SELECT count(*)::int FROM report_tenders((SELECT d FROM dates),(SELECT d FROM dates)) WHERE method = 'exchange'),0,'real exchange excluded from tenders');

-- Populate the second branch through the same catalog and sale APIs.
SELECT FROM save_style('{"kind":"item","code":"R-OTHER","name":"Other branch bike","taxable":true,
 "location_id":"00000000-0000-0000-0000-0000000ef0b2",
 "variants":[{"sku":"R-OTHER-M","size":"M","color":"White","price":1000,"cost":400,"opening_stock":10}]}');
SELECT FROM post_sale(jsonb_build_object('request_id','00000000-0000-0000-0000-0000000ef00a',
 'location_id','00000000-0000-0000-0000-0000000ef0b2',
 'lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT id FROM product_variants WHERE sku = 'R-OTHER-M'),'quantity',1)),
 'payments','[{"method":"card","amount":1100,"card_last4":"4242"}]'::jsonb));
SELECT is((SELECT net_sales FROM report_sales_summary((SELECT d FROM dates),(SELECT d FROM dates),'00000000-0000-0000-0000-0000000ef0b1')),1000::numeric,'admin can explicitly report other branch');
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ef04","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM report_sales_summary((SELECT d FROM dates),(SELECT d FROM dates),'00000000-0000-0000-0000-0000000ef0b1')),0,'manager cannot report other branch sales');
SELECT is((SELECT count(*)::int FROM report_tenders((SELECT d FROM dates),(SELECT d FROM dates),'00000000-0000-0000-0000-0000000ef0b1')),0,'manager cannot report other branch tenders');
SELECT is((SELECT count(*)::int FROM report_top_items((SELECT d FROM dates),(SELECT d FROM dates),'00000000-0000-0000-0000-0000000ef0b1')),0,'manager cannot report other branch items');
SELECT is((SELECT count(*)::int FROM report_staff_sales((SELECT d FROM dates),(SELECT d FROM dates),'00000000-0000-0000-0000-0000000ef0b1')),0,'manager cannot report other branch staff sales');
SELECT is((SELECT count(*)::int FROM report_top_items((SELECT d FROM dates),(SELECT d FROM dates)) WHERE label = 'Other branch bike'),0,'NULL branch is limited to memberships');

RESET ROLE;
SELECT ok(NOT has_function_privilege('anon','public.report_sales_summary(date,date,uuid)','EXECUTE'),'anonymous execution revoked');
SELECT ok(NOT has_function_privilege('authenticated','public.report_line_activity(date,date,uuid)','EXECUTE'),'line activity helper is internal');
SELECT ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname LIKE 'report_%' AND
 (p.provolatile <> 's' OR NOT p.prosecdef OR NOT ('search_path=public' = ANY(p.proconfig)))),
 'report functions are stable, security definer and use fixed search path');
SELECT ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname LIKE 'report_%'
 AND has_function_privilege('anon',p.oid,'EXECUTE')), 'anonymous cannot execute any report helper or wrapper');

-- Credit invoices are revenue even though no cash is collected.
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ef01","role":"authenticated"}';
CREATE TEMP TABLE credit_sale AS SELECT post_sale(jsonb_build_object('request_id','00000000-0000-0000-0000-0000000ef00b',
 'customer_id','00000000-0000-0000-0000-0000000ef0c1',
 'lines',jsonb_build_array(jsonb_build_object('variant_id',(SELECT l FROM ids),'quantity',1)),
 'payments','[{"method":"credit"}]'::jsonb)) AS result;
SELECT is((SELECT result->'sale'->>'status' FROM credit_sale),'credit','credit fixture posts on account');
SELECT is((SELECT invoices FROM report_sales_summary((SELECT d FROM dates),(SELECT d FROM dates),default_branch_id())),3,'credit included in invoice count with exchanged invoices');


SELECT * FROM finish();
ROLLBACK;
