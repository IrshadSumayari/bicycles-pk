BEGIN;
SELECT plan(6);
SELECT results_eq($$SELECT p.oid::regprocedure::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind='f' AND has_function_privilege('anon',p.oid,'EXECUTE') ORDER BY 1$$,
 $$VALUES ('catalog_collections()'),('catalog_facets(text)'),('catalog_list(jsonb)'),('catalog_policy()'),('catalog_product(text)'),('needs_bootstrap()'),('quote_online_order(jsonb)')$$,'anonymous function surface is an exact allow-list');
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) AS grants(privilege) WHERE n.nspname='public' AND c.relkind IN('r','p','v','m','f') AND has_table_privilege('anon',c.oid,grants.privilege) AND NOT(c.relname='public_catalog' AND grants.privilege='SELECT')),0,'anon has no other public table privileges, including inherited grants');
SELECT ok(has_table_privilege('anon','public.public_catalog','SELECT'),'safe legacy catalog view remains readable');
SELECT is((SELECT count(*)::int FROM storage.buckets WHERE public AND id<>'product-images'),0,'only product images are public');
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-0000000fe201','surface-admin@t.local','{}','{}'),
 ('00000000-0000-0000-0000-0000000fe202','surface-customer@t.local','{}','{}');
SELECT app_private.bootstrap_admin('surface-admin@t.local'); -- first administrator (no longer the first sign-up)
CREATE FUNCTION pg_temp.staff_surface_violations() RETURNS text[] LANGUAGE plpgsql AS $$
DECLARE f RECORD;args TEXT;failures TEXT[]:='{}';BEGIN
 FOR f IN SELECT p.* FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind='f' AND has_function_privilege('authenticated',p.oid,'EXECUTE')
 AND p.proname<>ALL(ARRAY['catalog_collections','catalog_facets','catalog_list','catalog_product','catalog_policy','needs_bootstrap','quote_online_order','normalize_phone','current_app_role','has_app_role','is_staff','is_counter_staff','is_branch_member','is_website_customer','default_branch_id','promotion_item_matches','report_tz','cancel_my_online_order','create_online_order','link_customer_account','my_online_order','my_online_orders','my_return_request','create_return_request','reply_return_request','prepare_return_photo']) LOOP
  SELECT string_agg(CASE WHEN typ= 'jsonb'::regtype THEN quote_literal(jsonb_build_object('request_id',gen_random_uuid())::text)||'::jsonb' ELSE 'NULL::'||format_type(typ,NULL) END,',' ORDER BY ord)
  INTO args FROM unnest(f.proargtypes) WITH ORDINALITY AS types(typ,ord);
  BEGIN EXECUTE format('SELECT public.%I(%s)',f.proname,coalesce(args,''));failures:=array_append(failures,f.oid::regprocedure::text||' unexpectedly succeeded');
  EXCEPTION WHEN insufficient_privilege THEN NULL;WHEN OTHERS THEN failures:=array_append(failures,f.oid::regprocedure::text||' returned '||SQLSTATE||': '||SQLERRM);END;
 END LOOP;RETURN failures;END $$;
GRANT EXECUTE ON FUNCTION pg_temp.staff_surface_violations() TO authenticated;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims"='{"sub":"00000000-0000-0000-0000-0000000fe202","role":"authenticated","aal":"aal2"}';
SELECT is(public.is_website_customer(),true,'fixture is a website customer without a staff role');
SELECT is(pg_temp.staff_surface_violations(),ARRAY[]::text[],'website customer refused by every staff entry point');
RESET ROLE;SET LOCAL "request.jwt.claims"='';SELECT * FROM finish();ROLLBACK;
