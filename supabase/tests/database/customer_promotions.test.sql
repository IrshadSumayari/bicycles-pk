BEGIN;
SELECT no_plan();
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('00000000-0000-0000-0000-00000000ab01','marketing-admin@t.local','{"name":"Marketing admin"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000ab02','marketing-cashier@t.local','{"name":"Marketing cashier"}','{"account_type":"staff"}'),
 ('00000000-0000-0000-0000-00000000ab03','marketing-person@t.local','{"name":"Marketing person"}','{}');
SELECT app_private.bootstrap_admin('marketing-admin@t.local'); -- first administrator (no longer the first sign-up)
UPDATE public.users SET role='admin',active=true WHERE id='00000000-0000-0000-0000-00000000ab01';
UPDATE public.users SET role='cashier',active=true WHERE id='00000000-0000-0000-0000-00000000ab02';
INSERT INTO customers(id,name,email,phone,email_marketing_consent,sms_marketing_consent) VALUES
 ('00000000-0000-0000-0000-00000000abc1','Promo fixture',' Promo-Test@example.test ','03009990001',true,true),
 ('00000000-0000-0000-0000-00000000abc2','Promo unknown','unknown@example.test','03009990002',null,null);
SELECT ok((SELECT email_consent_at IS NOT NULL AND sms_consent_at IS NOT NULL FROM customers WHERE id='00000000-0000-0000-0000-00000000abc1'),'server timestamps affirmative preferences');
SELECT is((SELECT count(*)::int FROM marketing_consent_events WHERE subject_id='00000000-0000-0000-0000-00000000abc1'),2,'separate channel audit records');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"00000000-0000-0000-0000-00000000ab01","role":"authenticated","aal":"aal2"}';
SELECT is((SELECT count(*)::int FROM marketing_audience('email','promo-test')),1,'opted-in email audience');
SELECT is((SELECT contact FROM marketing_audience('sms','9990001')),'+923009990001','SMS destination normalized');
SELECT is((SELECT count(*)::int FROM marketing_audience('email','unknown@example.test')),0,'unknown is excluded');
SELECT throws_ok($$SELECT * FROM marketing_audience('fax')$$,'P0001','Choose email or SMS','reject unknown channel');
INSERT INTO marketing_campaigns(id,name,channel,subject,body) VALUES('00000000-0000-0000-0000-00000000abd1','Test draft','email','Offer','Hello');
SELECT is((SELECT status FROM marketing_campaigns WHERE id='00000000-0000-0000-0000-00000000abd1'),'draft','campaign stays draft');
SELECT throws_ok($$UPDATE marketing_campaigns SET status='sent' WHERE id='00000000-0000-0000-0000-00000000abd1'$$,'23514',NULL,'delivery state cannot be faked');
UPDATE customers SET email_marketing_consent=false WHERE id='00000000-0000-0000-0000-00000000abc1';
SELECT is((SELECT count(*)::int FROM marketing_audience('email','promo-test')),0,'withdrawal immediately suppresses');
SELECT is((SELECT count(*)::int FROM marketing_audience('sms','9990001')),1,'email withdrawal does not change SMS');
UPDATE customers SET phone='03009990003',sms_marketing_consent=true WHERE id='00000000-0000-0000-0000-00000000abc1';
SELECT ok((SELECT sms_marketing_consent IS NULL FROM customers WHERE id='00000000-0000-0000-0000-00000000abc1'),'new phone requires fresh consent');
SELECT throws_ok($$INSERT INTO customers(name,email,email_marketing_consent) VALUES('Invalid permission','',true)$$,'P0001','A valid email is required for email offers','email opt-in requires a valid email');
RESET ROLE;
-- Two records sharing a destination do not allow an opt-out to be bypassed.
UPDATE customer_accounts SET email='promo-test@example.test',email_marketing_consent=true WHERE id='00000000-0000-0000-0000-00000000ab03';
UPDATE customer_accounts SET email_marketing_consent=true WHERE id='00000000-0000-0000-0000-00000000ab03';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"00000000-0000-0000-0000-00000000ab01","role":"authenticated","aal":"aal2"}';
SELECT is((SELECT count(*)::int FROM marketing_audience('email','promo-test')),0,'duplicate website opt-in cannot bypass POS opt-out');
UPDATE customers SET email_marketing_consent=true WHERE id='00000000-0000-0000-0000-00000000abc1';
SELECT is((SELECT count(*)::int FROM marketing_audience('email','promo-test')),1,'duplicate opted-in destinations exported once');
SELECT is((SELECT source FROM marketing_audience('email','promo-test')),'POS + Website','sources retained');
SET LOCAL request.jwt.claims='{"sub":"00000000-0000-0000-0000-00000000ab02","role":"authenticated","aal":"aal2"}';
SELECT throws_ok($$SELECT * FROM marketing_audience('email')$$,'42501','Marketing audiences are for managers only','cashier cannot export');
SELECT is((SELECT count(*)::int FROM marketing_campaigns),0,'cashier cannot read campaign drafts');
SELECT throws_ok($$INSERT INTO marketing_campaigns(name,channel,body) VALUES('No','sms','No')$$,'42501',NULL,'cashier cannot create campaign');
SELECT is((SELECT count(*)::int FROM marketing_consent_events),0,'cashier cannot read consent audit');
INSERT INTO customers(name,phone,email,sms_marketing_consent) VALUES('Phone only','03009990004',null,true);
SELECT ok((SELECT sms_marketing_consent FROM customers WHERE phone='+923009990004'),'cashier can capture phone-only customer');
SET LOCAL request.jwt.claims='{"sub":"00000000-0000-0000-0000-00000000ab03","role":"authenticated","aal":"aal2"}';
UPDATE customer_accounts SET email_marketing_consent=false WHERE id=auth.uid();
SELECT ok((SELECT email_marketing_consent IS FALSE FROM customer_accounts WHERE id=auth.uid()),'customer can withdraw own email consent');
SELECT throws_ok($$SELECT * FROM marketing_audience('sms')$$,'42501','Marketing audiences are for managers only','website customer cannot export');
SELECT throws_ok($$INSERT INTO marketing_consent_events(subject_id,source,channel,consent) VALUES(auth.uid(),'customer_accounts','email',true)$$,'42501',NULL,'audit records cannot be forged');
RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
