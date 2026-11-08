-- Positive entries increase udhaar; negative entries reduce it.
CREATE TABLE IF NOT EXISTS public.customer_ledger (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 customer_id UUID NOT NULL REFERENCES public.customers(id),
 entry_type TEXT NOT NULL CHECK (entry_type IN ('opening','sale_credit','return_credit','tailoring_credit','payment','adjustment')),
 amount NUMERIC(14,2) NOT NULL CHECK (amount <> 0),
 sale_id UUID REFERENCES public.sales(id), return_id UUID REFERENCES public.returns(id),
 tailoring_order_id UUID REFERENCES public.tailoring_orders(id), payment_id UUID,
 note TEXT, created_by UUID DEFAULT auth.uid(), created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_customer_ledger_time ON public.customer_ledger(customer_id,created_at,id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_ledger_opening ON public.customer_ledger(customer_id) WHERE entry_type='opening';
ALTER TABLE public.customer_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS customer_ledger_select ON public.customer_ledger;
CREATE POLICY customer_ledger_select ON public.customer_ledger FOR SELECT TO authenticated USING (public.is_counter_staff());
DROP TRIGGER IF EXISTS customer_ledger_append_only ON public.customer_ledger;
CREATE TRIGGER customer_ledger_append_only BEFORE UPDATE OR DELETE ON public.customer_ledger FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();

CREATE OR REPLACE FUNCTION public.guard_customer_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF (TG_OP='INSERT' AND coalesce(NEW.credit_used,0)<>0) THEN
   RAISE EXCEPTION 'The balance changes only through payments and sales' USING ERRCODE='42501';
 ELSIF TG_OP='UPDATE' AND NEW.credit_used IS DISTINCT FROM OLD.credit_used
       AND current_setting('app.customer_ledger',true) IS DISTINCT FROM 'on' THEN
   RAISE EXCEPTION 'The balance changes only through payments and sales' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.guard_customer_balance() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS customers_guard_balance ON public.customers;
CREATE TRIGGER customers_guard_balance BEFORE INSERT OR UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.guard_customer_balance();

CREATE OR REPLACE FUNCTION public.apply_customer_ledger()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_flag TEXT:=current_setting('app.customer_ledger',true);
BEGIN
 PERFORM set_config('app.customer_ledger','on',true);
 UPDATE public.customers SET credit_used=coalesce(credit_used,0)+NEW.amount WHERE id=NEW.customer_id;
 -- Do not leave an authorization flag enabled for the rest of the transaction.
 PERFORM set_config('app.customer_ledger',coalesce(v_flag,''),true);
 RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.apply_customer_ledger() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS customer_ledger_apply ON public.customer_ledger;
CREATE TRIGGER customer_ledger_apply AFTER INSERT ON public.customer_ledger FOR EACH ROW EXECUTE FUNCTION public.apply_customer_ledger();

-- Private and reusable so upgrades can be tested with pre-ledger balances.
CREATE OR REPLACE FUNCTION public.backfill_customer_ledger()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE c public.customers; v_flag TEXT:=current_setting('app.customer_ledger',true);
BEGIN
 FOR c IN SELECT * FROM public.customers ORDER BY id FOR UPDATE LOOP
   -- Already ledger-backed customers need no opening entry, including accounts
   -- first created after this migration. This also makes reapplication safe.
   IF coalesce(c.credit_used,0)<>0 AND NOT EXISTS (SELECT 1 FROM public.customer_ledger l WHERE l.customer_id=c.id) THEN
     PERFORM set_config('app.customer_ledger','on',true);
     UPDATE public.customers SET credit_used=0 WHERE id=c.id;
     INSERT INTO public.customer_ledger(customer_id,entry_type,amount,note) VALUES(c.id,'opening',c.credit_used,'Balance brought forward');
     PERFORM set_config('app.customer_ledger',coalesce(v_flag,''),true);
   END IF;
 END LOOP;
END; $$;
REVOKE ALL ON FUNCTION public.backfill_customer_ledger() FROM PUBLIC,anon,authenticated;
SELECT public.backfill_customer_ledger();

CREATE SEQUENCE IF NOT EXISTS public.customer_payment_no_seq START 1;
REVOKE ALL ON SEQUENCE public.customer_payment_no_seq FROM PUBLIC,anon,authenticated;
CREATE TABLE IF NOT EXISTS public.customer_payments (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), payment_no TEXT NOT NULL UNIQUE,
 request_id UUID NOT NULL UNIQUE, customer_id UUID NOT NULL REFERENCES public.customers(id),
 total NUMERIC(14,2) NOT NULL CHECK(total>0), note TEXT,
 created_by UUID DEFAULT auth.uid(), created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- One ledger entry references the collection header, which can have several tenders.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='customer_ledger_payment_header_fkey' AND conrelid='public.customer_ledger'::regclass) THEN
   ALTER TABLE public.customer_ledger ADD CONSTRAINT customer_ledger_payment_header_fkey FOREIGN KEY(payment_id) REFERENCES public.customer_payments(id);
 END IF;
END $$;
ALTER TABLE public.customer_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS customer_payments_select ON public.customer_payments;
CREATE POLICY customer_payments_select ON public.customer_payments FOR SELECT TO authenticated USING(public.is_counter_staff());
DROP TRIGGER IF EXISTS customer_payments_append_only ON public.customer_payments;
CREATE TRIGGER customer_payments_append_only BEFORE UPDATE OR DELETE ON public.customer_payments FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();
REVOKE ALL ON public.customer_ledger,public.customer_payments FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.customer_ledger,public.customer_payments TO authenticated;
REVOKE ALL ON SEQUENCE public.customer_ledger_id_seq FROM PUBLIC,anon,authenticated;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS customer_payment_id UUID REFERENCES public.customer_payments(id);
CREATE INDEX IF NOT EXISTS idx_payments_customer_payment ON public.payments(customer_payment_id) WHERE customer_payment_id IS NOT NULL;
DROP POLICY IF EXISTS payments_customer_collection_select ON public.payments;
CREATE POLICY payments_customer_collection_select ON public.payments FOR SELECT TO authenticated USING(customer_payment_id IS NOT NULL AND public.is_counter_staff());

CREATE OR REPLACE FUNCTION public.post_customer_payment(p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_request UUID; v_customer public.customers; v_existing JSONB; v_header public.customer_payments;
 v_pay JSONB; v_amount NUMERIC; v_total NUMERIC:=0; v_tendered NUMERIC;
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) THEN RAISE EXCEPTION 'Only counter staff can collect payments' USING ERRCODE='42501'; END IF;
 v_request:=nullif(p->>'request_id','')::uuid;
 v_existing:=public.idempotency_begin(v_request,'post_customer_payment');
 IF v_existing IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM public.customer_payments h WHERE h.request_id=v_request AND h.created_by=auth.uid() AND h.customer_id=(p->>'customer_id')::uuid) THEN
     RAISE EXCEPTION 'Request id belongs to another payment' USING ERRCODE='42501';
   END IF;
   RETURN v_existing;
 END IF;
 IF v_request IS NULL THEN RAISE EXCEPTION 'request_id is required'; END IF;
 SELECT * INTO v_customer FROM public.customers WHERE id=(p->>'customer_id')::uuid FOR UPDATE;
 IF v_customer.id IS NULL THEN RAISE EXCEPTION 'Choose a customer'; END IF;
 IF jsonb_typeof(p->'payments') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Add at least one payment'; END IF;
 FOR v_pay IN SELECT * FROM jsonb_array_elements(p->'payments') LOOP
   IF coalesce(v_pay->>'method','') NOT IN ('cash','card','digital') THEN RAISE EXCEPTION 'Choose cash, card or digital for collecting payments'; END IF;
   v_amount:=nullif(v_pay->>'amount','')::numeric;
   IF v_amount IS NULL OR v_amount<=0 OR v_amount<>round(v_amount,2) OR v_amount::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'Each payment needs an amount greater than zero with at most two decimals'; END IF;
   v_total:=v_total+v_amount;
 END LOOP;
 IF v_total=0 THEN RAISE EXCEPTION 'Add at least one payment'; END IF;
 IF v_total>coalesce(v_customer.credit_used,0) THEN RAISE EXCEPTION 'This is more than the customer owes (PKR %)',coalesce(v_customer.credit_used,0); END IF;
 INSERT INTO public.customer_payments(payment_no,request_id,customer_id,total,note)
 VALUES('PAY-'||lpad(nextval('public.customer_payment_no_seq')::text,6,'0'),v_request,v_customer.id,v_total,nullif(trim(p->>'note'),'')) RETURNING * INTO v_header;
 FOR v_pay IN SELECT * FROM jsonb_array_elements(p->'payments') LOOP
   v_amount:=(v_pay->>'amount')::numeric;
   v_tendered:=coalesce(nullif(v_pay->>'tendered','')::numeric,v_amount);
   IF v_pay->>'method'='cash' AND (v_tendered<v_amount OR v_tendered<>round(v_tendered,2) OR v_tendered::text IN ('NaN','Infinity','-Infinity')) THEN RAISE EXCEPTION 'Cash received must cover the payment amount'; END IF;
   INSERT INTO public.payments(customer_payment_id,method,amount,direction,tendered,change_given,reference,card_last4)
   VALUES(v_header.id,v_pay->>'method',v_amount,'in',CASE WHEN v_pay->>'method'='cash' THEN v_tendered END,
     CASE WHEN v_pay->>'method'='cash' THEN v_tendered-v_amount ELSE 0 END,
     nullif(left(v_pay->>'reference',100),''),CASE WHEN v_pay->>'method'='card' THEN nullif(v_pay->>'card_last4','') END);
 END LOOP;
 INSERT INTO public.customer_ledger(customer_id,entry_type,amount,payment_id,note)
 VALUES(v_customer.id,'payment',-v_total,v_header.id,nullif(trim(p->>'note'),''));
 RETURN public.idempotency_finish(v_request,jsonb_build_object('payment_no',v_header.payment_no,'paid',v_total,'balance',v_customer.credit_used-v_total,
   'payments',(SELECT jsonb_agg(jsonb_build_object('method',pay.method,'amount',pay.amount,'reference',pay.reference) ORDER BY pay.created_at,pay.id)
               FROM public.payments pay WHERE pay.customer_payment_id=v_header.id)));
END; $$;

CREATE OR REPLACE FUNCTION public.adjust_customer_balance(p_customer UUID,p_amount NUMERIC,p_reason TEXT,p_request_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_existing JSONB; v_customer public.customers;
BEGIN
 IF NOT public.has_app_role(ARRAY['admin','manager']) THEN RAISE EXCEPTION 'Only managers can adjust balances' USING ERRCODE='42501'; END IF;
 v_existing:=public.idempotency_begin(p_request_id,'adjust_customer_balance');
 IF v_existing IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=p_request_id AND user_id=auth.uid()) OR v_existing->>'customer_id' IS DISTINCT FROM p_customer::text THEN
     RAISE EXCEPTION 'Request id belongs to another adjustment' USING ERRCODE='42501'; END IF;
   RETURN v_existing;
 END IF;
 IF p_request_id IS NULL THEN RAISE EXCEPTION 'request_id is required'; END IF;
 IF coalesce(trim(p_reason),'')='' THEN RAISE EXCEPTION 'Add a reason for this balance adjustment'; END IF;
 IF p_amount IS NULL OR p_amount=0 OR p_amount<>round(p_amount,2) OR p_amount::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'Enter a non-zero adjustment with at most two decimals'; END IF;
 SELECT * INTO v_customer FROM public.customers WHERE id=p_customer FOR UPDATE;
 IF v_customer.id IS NULL THEN RAISE EXCEPTION 'Customer not found'; END IF;
 INSERT INTO public.customer_ledger(customer_id,entry_type,amount,note) VALUES(p_customer,'adjustment',p_amount,trim(p_reason));
 RETURN public.idempotency_finish(p_request_id,jsonb_build_object('customer_id',p_customer,'balance',coalesce(v_customer.credit_used,0)+p_amount));
END; $$;

CREATE OR REPLACE FUNCTION public.customer_statement(p_customer UUID,p_from DATE,p_to DATE)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE c public.customers; v_opening NUMERIC; v_entries JSONB; v_delta NUMERIC;
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) THEN RAISE EXCEPTION 'Only counter staff can see statements' USING ERRCODE='42501'; END IF;
 IF p_from IS NULL OR p_to IS NULL OR p_from>p_to THEN RAISE EXCEPTION 'Choose a valid statement date range'; END IF;
 SELECT * INTO c FROM public.customers WHERE id=p_customer;
 IF c.id IS NULL THEN RAISE EXCEPTION 'Customer not found'; END IF;
 SELECT coalesce(sum(amount),0) INTO v_opening FROM public.customer_ledger WHERE customer_id=p_customer AND created_at<(p_from::timestamp AT TIME ZONE public.report_tz());
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'date',x.created_at,'type',x.entry_type,'document_no',x.document_no,
   'note',x.note,'debit',greatest(x.amount,0),'credit',greatest(-x.amount,0),'balance',x.balance) ORDER BY x.created_at,x.id),'[]'::jsonb),coalesce(sum(x.amount),0)
 INTO v_entries,v_delta FROM (
   SELECT l.*,coalesce(s.invoice_number,r.return_no,o.order_no,h.payment_no) document_no,
     v_opening+sum(l.amount) OVER(ORDER BY l.created_at,l.id ROWS UNBOUNDED PRECEDING) balance
   FROM public.customer_ledger l LEFT JOIN public.sales s ON s.id=l.sale_id LEFT JOIN public.returns r ON r.id=l.return_id
   LEFT JOIN public.tailoring_orders o ON o.id=l.tailoring_order_id LEFT JOIN public.customer_payments h ON h.id=l.payment_id
   WHERE l.customer_id=p_customer AND l.created_at>=(p_from::timestamp AT TIME ZONE public.report_tz()) AND l.created_at<((p_to+1)::timestamp AT TIME ZONE public.report_tz())
 ) x;
 RETURN jsonb_build_object('customer',jsonb_build_object('id',c.id,'name',c.name,'phone',c.phone,'credit_limit',c.credit_limit,'balance',c.credit_used),
   'opening_balance',v_opening,'entries',v_entries,'closing_balance',v_opening+v_delta);
END; $$;

CREATE OR REPLACE FUNCTION public.customers_with_balance(p JSONB DEFAULT '{}'::jsonb)
RETURNS TABLE(customer JSONB,oldest_unpaid_date DATE,last_payment_date DATE,total_count BIGINT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE v_q TEXT:=replace(replace(replace(trim(coalesce(p->>'q','')),E'\\',E'\\\\'),'%',E'\\%'),'_',E'\\_');
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) THEN RAISE EXCEPTION 'Only counter staff can see customer balances' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT to_jsonb(c),
   (SELECT (min(l.created_at) AT TIME ZONE public.report_tz())::date FROM public.customer_ledger l WHERE l.customer_id=c.id AND l.amount>0),
   (SELECT (max(l.created_at) AT TIME ZONE public.report_tz())::date FROM public.customer_ledger l WHERE l.customer_id=c.id AND l.entry_type='payment'),count(*) OVER()
 FROM public.customers c WHERE c.credit_used>0 AND (v_q='' OR c.name ILIKE '%'||v_q||'%' OR c.phone ILIKE '%'||v_q||'%' OR c.email ILIKE '%'||v_q||'%')
 ORDER BY c.name,c.id LIMIT least(200,greatest(1,coalesce((p->>'limit')::int,50))) OFFSET greatest(0,coalesce((p->>'offset')::int,0));
END; $$;

REVOKE ALL ON FUNCTION public.post_customer_payment(JSONB) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.adjust_customer_balance(UUID,NUMERIC,TEXT,UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.customer_statement(UUID,DATE,DATE) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.customers_with_balance(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.post_customer_payment(JSONB),public.adjust_customer_balance(UUID,NUMERIC,TEXT,UUID),public.customer_statement(UUID,DATE,DATE),public.customers_with_balance(JSONB) TO authenticated;

-- Latest existing posting bodies; only balance writes change.
CREATE OR REPLACE FUNCTION public.post_sale(p_request JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_request_id UUID := NULLIF(p_request->>'request_id', '')::uuid;
    v_existing JSONB;
    v_quote JSONB;
    v_status TEXT := COALESCE(NULLIF(p_request->>'status', ''), 'completed');
    v_profile public.users;
    v_total NUMERIC;
    v_payments JSONB := COALESCE(p_request->'payments', '[]'::jsonb);
    v_pay JSONB;
    v_pay_total NUMERIC := 0;
    v_amount NUMERIC;
    v_tendered NUMERIC;
    v_change NUMERIC := 0;
    v_credit NUMERIC := 0;
    v_customer public.customers;
    v_sale public.sales;
    v_line JSONB;
    v_line_no INTEGER := 0;
    v_invoice TEXT;
    v_primary_method TEXT;
    v_card JSONB;
    v_items_snapshot JSONB := '[]'::jsonb;
    v_result JSONB;
BEGIN
    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'request_id is required';
    END IF;
    IF v_status NOT IN ('completed', 'draft') THEN
        RAISE EXCEPTION 'Invalid sale status: %', v_status;
    END IF;

    v_existing := public.idempotency_begin(v_request_id, 'post_sale');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    v_quote := public.quote_sale(p_request);
    v_total := (v_quote->>'total')::numeric;
    SELECT * INTO v_profile FROM public.users WHERE id = auth.uid();

    -- Payments (not needed for drafts)
    IF v_status = 'completed' THEN
        IF jsonb_typeof(v_payments) <> 'array' OR jsonb_array_length(v_payments) = 0 THEN
            IF v_total = 0 THEN
                v_payments := '[]'::jsonb;
            ELSE
                RAISE EXCEPTION 'Add a payment';
            END IF;
        END IF;
        IF jsonb_array_length(v_payments) = 1 AND NULLIF(v_payments->0->>'amount', '') IS NULL THEN
            v_payments := jsonb_build_array(v_payments->0 || jsonb_build_object('amount', v_total));
        END IF;

        FOR v_pay IN SELECT * FROM jsonb_array_elements(v_payments)
        LOOP
            v_amount := (v_pay->>'amount')::numeric;
            IF v_amount IS NULL OR v_amount <= 0 THEN
                RAISE EXCEPTION 'Each payment needs an amount greater than zero';
            END IF;
            IF v_pay->>'method' = 'exchange' AND COALESCE(current_setting('pos.allow_exchange_payment', true), '') <> 'on' THEN
                RAISE EXCEPTION 'Exchange credit can only be used through an exchange' USING ERRCODE = '42501';
            END IF;
            IF v_pay->>'method' NOT IN ('cash', 'card', 'digital', 'credit', 'exchange') THEN
                RAISE EXCEPTION 'Invalid payment method: %', v_pay->>'method';
            END IF;
            IF v_pay->>'method' = 'cash' AND NULLIF(v_pay->>'tendered', '') IS NOT NULL THEN
                v_tendered := (v_pay->>'tendered')::numeric;
                IF v_tendered < v_amount THEN
                    RAISE EXCEPTION 'Cash received is less than the cash amount';
                END IF;
                v_change := v_change + (v_tendered - v_amount);
            END IF;
            IF v_pay->>'method' = 'credit' THEN
                v_credit := v_credit + v_amount;
            END IF;
            v_pay_total := v_pay_total + v_amount;
        END LOOP;

        IF v_pay_total <> v_total THEN
            RAISE EXCEPTION 'Payments (%) do not match the total (%)', v_pay_total, v_total;
        END IF;

        IF v_credit > 0 THEN
            IF NULLIF(v_quote->>'customer_id', '') IS NULL THEN
                RAISE EXCEPTION 'Store credit needs a customer';
            END IF;
            SELECT * INTO v_customer FROM public.customers WHERE id = (v_quote->>'customer_id')::uuid FOR UPDATE;
            IF COALESCE(v_customer.credit_limit, 0) - COALESCE(v_customer.credit_used, 0) < v_credit THEN
                RAISE EXCEPTION 'Customer credit limit exceeded (available: %)',
                    COALESCE(v_customer.credit_limit, 0) - COALESCE(v_customer.credit_used, 0);
            END IF;
            -- The customer stays locked; record the credit after the sale header exists.
        END IF;
    END IF;

    SELECT p->>'method' INTO v_primary_method
    FROM jsonb_array_elements(v_payments) p ORDER BY (p->>'amount')::numeric DESC LIMIT 1;

    SELECT p INTO v_card FROM jsonb_array_elements(v_payments) p WHERE p->>'method' = 'card' LIMIT 1;

    IF v_status = 'draft' THEN
        v_invoice := 'DRAFT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    ELSE
        v_invoice := public.generate_invoice_number();
    END IF;

    -- Snapshot in the legacy `items` shape so existing screens keep working
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'product', jsonb_build_object('id', l->>'variant_id', 'name', l->>'description', 'sku', l->>'sku',
                                      'price', (l->>'unit_price')::numeric, 'unit', l->>'unit'),
        'quantity', (l->>'quantity')::numeric,
        'discount', (l->>'manual_discount')::numeric + (l->>'promotion_discount')::numeric,
        'discountType', 'fixed',
        'subtotal', (l->>'net')::numeric
    )), '[]'::jsonb) INTO v_items_snapshot
    FROM jsonb_array_elements(v_quote->'lines') l
    WHERE NOT (l->>'is_gift')::boolean;

    INSERT INTO public.sales (
        invoice_number, receipt_number, request_id, branch_id, location_id, channel,
        customer_id, customer_name, items, subtotal, discount_amount, tax_amount, total,
        payment_method, card_details, status, cashier, cashier_id, cashier_role, notes,
        applied_discounts, free_gifts, change_due
    ) VALUES (
        v_invoice, v_invoice, v_request_id, (v_quote->>'branch_id')::uuid, (v_quote->>'location_id')::uuid, 'pos',
        NULLIF(v_quote->>'customer_id', '')::uuid, v_quote->>'customer_name', v_items_snapshot,
        (v_quote->>'subtotal')::numeric, (v_quote->>'discount_amount')::numeric,
        (v_quote->>'tax_amount')::numeric, v_total,
        CASE WHEN v_status = 'draft' THEN NULL ELSE COALESCE(v_primary_method, 'cash') END,
        CASE WHEN v_card IS NULL THEN NULL ELSE public.sanitize_card_details(jsonb_build_object(
            'bankName', v_card->>'bank_name', 'cardType', v_card->>'card_type',
            'lastFourDigits', v_card->>'card_last4', 'holderName', v_card->>'holder_name')) END,
        CASE WHEN v_status = 'draft' THEN 'draft' WHEN v_credit > 0 THEN 'credit' ELSE 'completed' END,
        v_profile.name, v_profile.id, v_profile.role, left(p_request->>'notes', 1000),
        COALESCE(v_quote->'applied_discounts', '[]'::jsonb),
        COALESCE((SELECT jsonb_agg(l) FROM jsonb_array_elements(v_quote->'lines') l WHERE (l->>'is_gift')::boolean), '[]'::jsonb),
        v_change
    )
    RETURNING * INTO v_sale;
    IF v_credit > 0 THEN
        INSERT INTO public.customer_ledger(customer_id,entry_type,amount,sale_id)
        VALUES(v_customer.id,'sale_credit',v_credit,v_sale.id);
    END IF;

    FOR v_line IN SELECT * FROM jsonb_array_elements(v_quote->'lines')
    LOOP
        v_line_no := v_line_no + 1;
        INSERT INTO public.sale_lines (
            sale_id, line_no, variant_id, description, sku, unit, quantity, unit_price, gross,
            manual_discount, promotion_discount, net, taxable, tax, total, unit_cost, is_gift, promotion_id
        ) VALUES (
            v_sale.id, v_line_no, (v_line->>'variant_id')::uuid, v_line->>'description', v_line->>'sku',
            v_line->>'unit', (v_line->>'quantity')::numeric, (v_line->>'unit_price')::numeric,
            (v_line->>'gross')::numeric, (v_line->>'manual_discount')::numeric,
            (v_line->>'promotion_discount')::numeric, (v_line->>'net')::numeric,
            (v_line->>'taxable')::boolean, (v_line->>'tax')::numeric, (v_line->>'total')::numeric,
            NULLIF(v_line->>'unit_cost', '')::numeric, (v_line->>'is_gift')::boolean,
            NULLIF(v_line->>'promotion_id', '')::uuid
        );
    END LOOP;

    -- Stock: one movement per item, locked in variant order so two tills
    -- selling the same items can never deadlock each other
    IF v_status = 'completed' THEN
        FOR v_line IN
            SELECT jsonb_build_object(
                'variant_id', l->>'variant_id',
                'quantity', SUM((l->>'quantity')::numeric),
                'unit_cost', MAX(l->>'unit_cost'))
            FROM jsonb_array_elements(v_quote->'lines') l
            WHERE (l->>'track_inventory')::boolean
            GROUP BY l->>'variant_id'
            ORDER BY l->>'variant_id'
        LOOP
            PERFORM public.post_stock_movement(
                (v_quote->>'location_id')::uuid, (v_line->>'variant_id')::uuid,
                -((v_line->>'quantity')::numeric), 'sale', 'pos', 'sale', v_sale.id,
                NULLIF(v_line->>'unit_cost', '')::numeric, NULL
            );
        END LOOP;
    END IF;

    IF v_status = 'completed' THEN
        FOR v_pay IN SELECT * FROM jsonb_array_elements(v_payments)
        LOOP
            INSERT INTO public.payments (
                sale_id, method, amount, tendered, change_given, reference,
                card_type, card_last4, bank_name, holder_name
            ) VALUES (
                v_sale.id, v_pay->>'method', (v_pay->>'amount')::numeric,
                NULLIF(v_pay->>'tendered', '')::numeric,
                CASE WHEN v_pay->>'method' = 'cash' AND NULLIF(v_pay->>'tendered', '') IS NOT NULL
                     THEN (v_pay->>'tendered')::numeric - (v_pay->>'amount')::numeric ELSE 0 END,
                left(v_pay->>'reference', 100),
                CASE WHEN v_pay->>'method' = 'card' THEN left(v_pay->>'card_type', 20) END,
                CASE WHEN v_pay->>'method' = 'card' THEN NULLIF(right(regexp_replace(COALESCE(v_pay->>'card_last4', ''), '\D', '', 'g'), 4), '') END,
                CASE WHEN v_pay->>'method' = 'card' THEN left(v_pay->>'bank_name', 100) END,
                CASE WHEN v_pay->>'method' = 'card' THEN left(v_pay->>'holder_name', 100) END
            );
        END LOOP;
    END IF;

    v_result := jsonb_build_object(
        'sale', to_jsonb(v_sale),
        'lines', (SELECT jsonb_agg(to_jsonb(sl) ORDER BY sl.line_no) FROM public.sale_lines sl WHERE sl.sale_id = v_sale.id),
        'payments', COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.created_at) FROM public.payments p WHERE p.sale_id = v_sale.id), '[]'::jsonb),
        'change_due', v_change
    );
    RETURN public.idempotency_finish(v_request_id, v_result);
END;
$$;

CREATE OR REPLACE FUNCTION public.create_return(p JSONB, p_refund_method TEXT)
RETURNS public.returns
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role TEXT := public.current_app_role();
    v_sale public.sales;
    v_settings public.app_settings;
    v_needs_manager BOOLEAN := false;
    v_req JSONB;
    v_line public.sale_lines;
    v_returned NUMERIC;
    v_qty NUMERIC;
    v_refund NUMERIC;
    v_tax NUMERIC;
    v_total NUMERIC := 0;
    v_restock BOOLEAN;
    v_condition TEXT;
    v_return public.returns;
    v_roll public.fabric_rolls;
    v_track BOOLEAN;
    v_customer public.customers;
BEGIN
    IF v_role IS NULL OR v_role NOT IN ('admin', 'manager', 'cashier') THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
    IF COALESCE(trim(p->>'reason'), '') = '' THEN
        RAISE EXCEPTION 'A reason is required for a return';
    END IF;
    IF jsonb_typeof(p->'lines') <> 'array' OR jsonb_array_length(p->'lines') = 0 THEN
        RAISE EXCEPTION 'Choose at least one item to return';
    END IF;

    -- Locking the sale serialises returns of the same sale
    SELECT * INTO v_sale FROM public.sales WHERE id = NULLIF(p->>'sale_id', '')::uuid FOR UPDATE;
    IF v_sale.id IS NULL OR NOT public.is_branch_member(v_sale.branch_id) THEN
        RAISE EXCEPTION 'Sale not found';
    END IF;
    IF v_sale.status NOT IN ('completed', 'credit', 'refunded') THEN
        RAISE EXCEPTION 'Only completed sales can be returned';
    END IF;

    SELECT * INTO v_settings FROM public.app_settings ORDER BY created_at LIMIT 1;
    IF v_sale.created_at < now() - make_interval(days => COALESCE(v_settings.return_window_days, 7)) THEN
        v_needs_manager := true;
    END IF;

    INSERT INTO public.returns (return_no, request_id, sale_id, branch_id, location_id, customer_id, reason,
                                refund_total, refund_method)
    VALUES ('RTN-' || lpad(nextval('public.return_no_seq')::text, 6, '0'), NULLIF(p->>'request_id', '')::uuid,
            v_sale.id, v_sale.branch_id, COALESCE(v_sale.location_id, (
                SELECT id FROM public.locations WHERE branch_id = v_sale.branch_id AND kind = 'shop_floor' ORDER BY created_at LIMIT 1)),
            v_sale.customer_id, trim(p->>'reason'), 0, p_refund_method)
    RETURNING * INTO v_return;

    FOR v_req IN
        SELECT l FROM jsonb_array_elements(p->'lines') l ORDER BY l->>'sale_line_id'
    LOOP
        SELECT * INTO v_line FROM public.sale_lines
        WHERE id = NULLIF(v_req->>'sale_line_id', '')::uuid AND sale_id = v_sale.id;
        IF v_line.id IS NULL THEN
            RAISE EXCEPTION 'That item is not on this sale';
        END IF;

        v_qty := COALESCE(NULLIF(v_req->>'quantity', '')::numeric, 0);
        IF v_qty <= 0 THEN
            RAISE EXCEPTION 'Return quantity for "%" must be greater than zero', v_line.description;
        END IF;
        IF v_line.unit = 'meter' THEN
            IF v_qty <> round(v_qty, 2) THEN
                RAISE EXCEPTION 'Length for "%" can have at most 2 decimals', v_line.description;
            END IF;
        ELSIF v_qty <> trunc(v_qty) THEN
            RAISE EXCEPTION 'Whole quantities only for "%"', v_line.description;
        END IF;
        IF v_line.unit IN ('meter', 'job') THEN
            v_needs_manager := true;
        END IF;

        SELECT COALESCE(sum(quantity), 0) INTO v_returned FROM public.return_lines WHERE sale_line_id = v_line.id;
        IF v_returned + v_qty > v_line.quantity THEN
            RAISE EXCEPTION 'Only % of "%" can still be returned', trim_scale(v_line.quantity - v_returned), v_line.description;
        END IF;

        -- Exact share of what was paid: earlier returns + this one never exceed the line total
        v_refund := round(v_line.total * (v_returned + v_qty) / v_line.quantity, 2)
                  - round(v_line.total * v_returned / v_line.quantity, 2);
        v_tax := round(v_line.tax * (v_returned + v_qty) / v_line.quantity, 2)
               - round(v_line.tax * v_returned / v_line.quantity, 2);

        v_condition := COALESCE(NULLIF(v_req->>'condition', ''), 'resaleable');
        IF v_condition NOT IN ('resaleable', 'damaged', 'faulty') THEN
            RAISE EXCEPTION 'Invalid condition: %', v_condition;
        END IF;
        v_restock := COALESCE((v_req->>'restock')::boolean, v_condition = 'resaleable');

        SELECT s.track_inventory INTO v_track
        FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id WHERE v.id = v_line.variant_id;
        v_restock := v_restock AND COALESCE(v_track, false);

        INSERT INTO public.return_lines (return_id, sale_line_id, variant_id, description, quantity, refund_amount,
                                         tax_amount, restocked, condition)
        VALUES (v_return.id, v_line.id, v_line.variant_id, v_line.description, v_qty, v_refund, v_tax, v_restock, v_condition);

        IF v_restock THEN
            IF v_line.unit = 'meter' THEN
                -- Returned fabric becomes a remnant roll
                PERFORM public.lock_stock_balance(v_return.location_id, v_line.variant_id);
                INSERT INTO public.fabric_rolls (variant_id, branch_id, location_id, roll_code, initial_length,
                                                 remaining_length, unit_cost, notes)
                VALUES (v_line.variant_id, v_return.branch_id, v_return.location_id, public.next_roll_code(), v_qty, 0,
                        v_line.unit_cost, 'Returned on ' || v_return.return_no)
                RETURNING * INTO v_roll;
                INSERT INTO public.barcodes (code, variant_id, roll_id) VALUES (v_roll.roll_code, v_line.variant_id, v_roll.id);
                PERFORM public.post_stock_movement(v_return.location_id, v_line.variant_id, v_qty, 'return', 'pos',
                                                   'return', v_return.id, v_line.unit_cost, v_return.return_no, v_roll.id);
            ELSE
                PERFORM public.post_stock_movement(v_return.location_id, v_line.variant_id, v_qty, 'return', 'pos',
                                                   'return', v_return.id, v_line.unit_cost, v_return.return_no);
            END IF;
        END IF;

        v_total := v_total + v_refund;
    END LOOP;

    IF v_needs_manager AND v_role NOT IN ('admin', 'manager') THEN
        RAISE EXCEPTION 'This return needs a manager (fabric, services, or outside the % day return window)',
            COALESCE(v_settings.return_window_days, 7) USING ERRCODE = '42501';
    END IF;

    -- Refund
    IF v_total > 0 THEN
        IF p_refund_method = 'credit' THEN
            SELECT * INTO v_customer FROM public.customers WHERE id = v_sale.customer_id FOR UPDATE;
            IF v_customer.id IS NULL THEN
                RAISE EXCEPTION 'Store credit refunds need the sale to have a customer';
            END IF;
            IF COALESCE(v_customer.credit_used, 0) < v_total THEN
                RAISE EXCEPTION 'Store credit refunds can only reduce what the customer owes (owes %)',
                    COALESCE(v_customer.credit_used, 0);
            END IF;
            INSERT INTO public.customer_ledger(customer_id,entry_type,amount,return_id)
            VALUES(v_customer.id,'return_credit',-v_total,v_return.id);
        END IF;

        INSERT INTO public.payments (sale_id, return_id, method, amount, direction, reference)
        VALUES (v_sale.id, v_return.id, p_refund_method, v_total, 'out', v_return.return_no);
    END IF;

    IF v_sale.customer_id IS NOT NULL THEN
        UPDATE public.customers SET total_purchases = GREATEST(COALESCE(total_purchases, 0) - v_total, 0)
        WHERE id = v_sale.customer_id;
    END IF;

    -- Fully returned sales are marked refunded
    IF NOT EXISTS (
        SELECT 1 FROM public.sale_lines sl
        WHERE sl.sale_id = v_sale.id
          AND sl.quantity > COALESCE((SELECT sum(quantity) FROM public.return_lines rl WHERE rl.sale_line_id = sl.id), 0)
    ) THEN
        UPDATE public.sales SET status = 'refunded' WHERE id = v_sale.id;
    END IF;

    UPDATE public.returns SET refund_total = v_total WHERE id = v_return.id RETURNING * INTO v_return;
    RETURN v_return;
END;
$$;

CREATE OR REPLACE FUNCTION public.post_exchange(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_request_id UUID := NULLIF(p->>'request_id', '')::uuid;
    v_existing JSONB;
    v_return public.returns;
    v_sale_req JSONB;
    v_quote JSONB;
    v_new_total NUMERIC;
    v_credit NUMERIC;
    v_due NUMERIC;
    v_back NUMERIC;
    v_payments JSONB;
    v_new_sale JSONB;
    v_back_method TEXT := COALESCE(NULLIF(p->>'refund_method', ''), 'cash');
    v_orig public.sales;
BEGIN
    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'request_id is required';
    END IF;
    IF v_back_method NOT IN ('cash', 'card', 'digital', 'credit') THEN
        RAISE EXCEPTION 'Invalid refund method: %', v_back_method;
    END IF;
    v_existing := public.idempotency_begin(v_request_id, 'post_exchange');
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    SELECT * INTO v_orig FROM public.sales WHERE id = NULLIF(p->>'sale_id', '')::uuid;

    -- 1. Return: the value becomes exchange credit
    v_return := public.create_return(jsonb_build_object(
        'request_id', NULL, 'sale_id', p->'sale_id', 'reason', p->'reason', 'lines', p->'return_lines'), 'exchange');
    v_credit := v_return.refund_total;

    -- 2. Price the replacement items
    v_sale_req := jsonb_build_object('customer_id', v_orig.customer_id, 'lines', p->'new_lines',
                                     'location_id', v_return.location_id);
    v_quote := public.quote_sale(v_sale_req);
    v_new_total := (v_quote->>'total')::numeric;
    v_due := GREATEST(v_new_total - v_credit, 0);
    v_back := GREATEST(v_credit - v_new_total, 0);

    v_payments := CASE WHEN LEAST(v_credit, v_new_total) > 0
                       THEN jsonb_build_array(jsonb_build_object('method', 'exchange', 'amount', LEAST(v_credit, v_new_total),
                                                                 'reference', v_return.return_no))
                       ELSE '[]'::jsonb END;
    IF v_due > 0 THEN
        IF jsonb_typeof(p->'payments') <> 'array' OR jsonb_array_length(p->'payments') = 0 THEN
            RAISE EXCEPTION 'The customer owes % more; add a payment', v_due;
        END IF;
        IF jsonb_array_length(p->'payments') = 1 AND NULLIF(p->'payments'->0->>'amount', '') IS NULL THEN
            v_payments := v_payments || jsonb_build_array(p->'payments'->0 || jsonb_build_object('amount', v_due));
        ELSE
            v_payments := v_payments || (p->'payments');
        END IF;
    END IF;

    -- 3. The replacement sale, paid first with the exchange credit
    PERFORM set_config('pos.allow_exchange_payment', 'on', true);
    v_new_sale := public.post_sale(v_sale_req || jsonb_build_object(
        'request_id', gen_random_uuid(), 'payments', v_payments,
        'notes', 'Exchange for ' || v_orig.invoice_number || ' (' || v_return.return_no || ')'));
    PERFORM set_config('pos.allow_exchange_payment', 'off', true);

    -- 4. Anything left over goes back to the customer
    IF v_back > 0 THEN
        IF v_back_method = 'credit' THEN
            INSERT INTO public.customer_ledger(customer_id,entry_type,amount,return_id)
            SELECT id,'return_credit',-v_back,v_return.id FROM public.customers
            WHERE id = v_orig.customer_id AND credit_used >= v_back FOR UPDATE;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Store credit refunds can only reduce what the customer owes';
            END IF;
        END IF;
        INSERT INTO public.payments (sale_id, return_id, method, amount, direction, reference)
        VALUES (v_orig.id, v_return.id, v_back_method, v_back, 'out', v_return.return_no);
    END IF;

    UPDATE public.returns SET exchange_sale_id = (v_new_sale->'sale'->>'id')::uuid WHERE id = v_return.id
    RETURNING * INTO v_return;

    RETURN public.idempotency_finish(v_request_id, jsonb_build_object(
        'return', to_jsonb(v_return),
        'sale', v_new_sale->'sale',
        'customer_paid', v_due,
        'refunded', v_back
    ));
END;
$$;

CREATE OR REPLACE FUNCTION public.record_tailoring_payments(p_order_id UUID, p_payments JSONB, p_direction TEXT)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pay JSONB;
    v_amount NUMERIC;
    v_total NUMERIC := 0;
    v_order public.tailoring_orders;
BEGIN
    SELECT * INTO v_order FROM public.tailoring_orders WHERE id = p_order_id;
    FOR v_pay IN SELECT * FROM jsonb_array_elements(COALESCE(p_payments, '[]'::jsonb))
    LOOP
        v_amount := NULLIF(v_pay->>'amount', '')::numeric;
        IF v_amount IS NULL OR v_amount <= 0 OR v_amount <> round(v_amount, 2) THEN
            RAISE EXCEPTION 'Each payment needs an amount greater than zero';
        END IF;
        IF v_pay->>'method' NOT IN ('cash', 'card', 'digital', 'credit') THEN
            RAISE EXCEPTION 'Invalid payment method: %', v_pay->>'method';
        END IF;
        IF v_pay->>'method' = 'credit' THEN
            IF p_direction = 'in' THEN
                INSERT INTO public.customer_ledger(customer_id,entry_type,amount,tailoring_order_id)
                SELECT id,'tailoring_credit',v_amount,p_order_id FROM public.customers
                WHERE id = v_order.customer_id AND COALESCE(credit_limit, 0) - COALESCE(credit_used, 0) >= v_amount FOR UPDATE;
                IF NOT FOUND THEN
                    RAISE EXCEPTION 'Customer credit limit exceeded';
                END IF;
            ELSE
                INSERT INTO public.customer_ledger(customer_id,entry_type,amount,tailoring_order_id)
                SELECT id,'return_credit',-v_amount,p_order_id FROM public.customers
                WHERE id = v_order.customer_id AND credit_used >= v_amount FOR UPDATE;
                IF NOT FOUND THEN
                    RAISE EXCEPTION 'Store credit refunds can only reduce what the customer owes';
                END IF;
            END IF;
        END IF;
        INSERT INTO public.payments (tailoring_order_id, method, amount, direction, tendered, change_given, reference,
                                     card_type, card_last4)
        VALUES (p_order_id, v_pay->>'method', v_amount, p_direction,
                CASE WHEN v_pay->>'method' = 'cash' AND p_direction = 'in' THEN NULLIF(v_pay->>'tendered', '')::numeric END,
                CASE WHEN v_pay->>'method' = 'cash' AND p_direction = 'in' AND NULLIF(v_pay->>'tendered', '') IS NOT NULL
                     THEN (v_pay->>'tendered')::numeric - v_amount ELSE 0 END,
                COALESCE(left(v_pay->>'reference', 100), v_order.order_no),
                CASE WHEN v_pay->>'method' = 'card' THEN left(v_pay->>'card_type', 20) END,
                CASE WHEN v_pay->>'method' = 'card' THEN NULLIF(right(regexp_replace(COALESCE(v_pay->>'card_last4', ''), '\D', '', 'g'), 4), '') END);
        IF v_pay->>'method' = 'cash' AND p_direction = 'in' AND NULLIF(v_pay->>'tendered', '') IS NOT NULL
           AND (v_pay->>'tendered')::numeric < v_amount THEN
            RAISE EXCEPTION 'Cash received is less than the cash amount';
        END IF;
        v_total := v_total + v_amount;
    END LOOP;
    RETURN v_total;
END;
$$;
