-- Historical balances and paper orders enter through the same ledgers and jobs
-- as live work. Opening receipts settle an order but never represent today's cash.
ALTER TABLE public.tailoring_orders ADD COLUMN IF NOT EXISTS paper_ref TEXT;
ALTER TABLE public.tailoring_orders ADD COLUMN IF NOT EXISTS paper_order_date DATE;
CREATE UNIQUE INDEX IF NOT EXISTS idx_tailoring_orders_paper_ref ON public.tailoring_orders(paper_ref);
ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS payments_method_check;
ALTER TABLE public.payments ADD CONSTRAINT payments_method_check CHECK (method IN ('cash','card','digital','credit','exchange','opening'));

CREATE OR REPLACE FUNCTION public.import_opening_balances(p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
 v_request UUID; v_existing JSONB; r JSONB; n INT:=0; v_phone TEXT;
 v_amount NUMERIC; v_customer UUID; v_created INT:=0; v_balances INT:=0;
 v_total NUMERIC:=0; v_skipped JSONB:='[]'; v_count INT;
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin']),false) THEN
  RAISE EXCEPTION 'Only administrators can import opening balances' USING ERRCODE='42501';
 END IF;
 v_request:=nullif(p->>'request_id','')::uuid;
 IF v_request IS NULL THEN RAISE EXCEPTION 'request_id is required'; END IF;
 v_existing:=public.idempotency_begin(v_request,'import_opening_balances');
 IF v_existing IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=v_request AND user_id=auth.uid()) THEN
   RAISE EXCEPTION 'Request id belongs to another user' USING ERRCODE='42501'; END IF;
  RETURN v_existing;
 END IF;
 IF jsonb_typeof(p->'rows') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Choose a balances file'; END IF;
 IF jsonb_array_length(p->'rows')=0 THEN RAISE EXCEPTION 'Add at least one balance'; END IF;
 -- Validate every row before creating any customer or ledger entry.
 FOR r IN SELECT * FROM jsonb_array_elements(p->'rows') LOOP
  n:=n+1;
  IF coalesce(trim(r->>'name'),'')='' THEN RAISE EXCEPTION 'Row %: name is required',n; END IF;
  v_phone:=public.normalize_phone(r->>'phone');
  IF v_phone IS NULL OR v_phone !~ '^\+[1-9][0-9]{7,14}$' THEN RAISE EXCEPTION 'Row %: phone number is not valid',n; END IF;
  BEGIN v_amount:=(r->>'amount')::numeric;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
   RAISE EXCEPTION 'Row %: amount must be positive with at most 2 decimals',n;
  END;
  IF v_amount IS NULL OR v_amount<=0 OR v_amount>=1000000000000 OR v_amount<>round(v_amount,2)
    OR v_amount::text IN ('NaN','Infinity','-Infinity') THEN
   RAISE EXCEPTION 'Row %: amount must be positive with at most 2 decimals',n;
  END IF;
 END LOOP;
 n:=0;
 -- Serialise this small one-off import; avoid overlapping batches locking
 -- the same customers in opposite file order.
 PERFORM pg_advisory_xact_lock(hashtextextended('go_live_customer_import',0));
 FOR r IN SELECT * FROM jsonb_array_elements(p->'rows') LOOP
  n:=n+1; v_phone:=public.normalize_phone(r->>'phone');
  INSERT INTO public.customers(name,phone) VALUES(trim(r->>'name'),v_phone)
   ON CONFLICT (phone) WHERE phone IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  v_created:=v_created+v_count;
  SELECT id INTO v_customer FROM public.customers WHERE phone=v_phone FOR UPDATE;
  IF EXISTS(SELECT 1 FROM public.customer_ledger WHERE customer_id=v_customer AND entry_type='opening') THEN
   v_skipped:=v_skipped||jsonb_build_array(jsonb_build_object('row',n,'phone',v_phone,'reason','An opening balance already exists'));
  ELSE
   v_amount:=(r->>'amount')::numeric;
   INSERT INTO public.customer_ledger(customer_id,entry_type,amount,note)
    VALUES(v_customer,'opening',v_amount,nullif(trim(r->>'note'),''));
   v_balances:=v_balances+1; v_total:=v_total+v_amount;
  END IF;
 END LOOP;
 RETURN public.idempotency_finish(v_request,jsonb_build_object('created_customers',v_created,'balances',v_balances,'total_amount',v_total,'skipped',v_skipped));
END; $$;

CREATE OR REPLACE FUNCTION public.import_open_tailoring_order(p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
 v_request UUID; v_existing JSONB; v_ref TEXT; v_date DATE; v_promised DATE;
 v_phone TEXT; v_customer UUID; v_deposit NUMERIC; v_summary JSONB; v_order UUID;
 r JSONB; m JSONB; i RECORD; v_target TEXT; v_stage TEXT; v_stages TEXT[];
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) THEN
  RAISE EXCEPTION 'Only managers can import paper orders' USING ERRCODE='42501'; END IF;
 v_request:=nullif(p->>'request_id','')::uuid;
 IF v_request IS NULL THEN RAISE EXCEPTION 'request_id is required'; END IF;
 v_existing:=public.idempotency_begin(v_request,'import_open_tailoring_order');
 IF v_existing IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE key=v_request AND user_id=auth.uid()) THEN
   RAISE EXCEPTION 'Request id belongs to another user' USING ERRCODE='42501'; END IF;
  RETURN v_existing;
 END IF;
 v_ref:=nullif(trim(p->>'paper_ref'),'');
 IF v_ref IS NULL THEN RAISE EXCEPTION 'Paper slip number is required'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('paper_order:'||v_ref,0));
 IF EXISTS(SELECT 1 FROM public.tailoring_orders WHERE paper_ref=v_ref) THEN RAISE EXCEPTION 'Paper slip % has already been imported',v_ref; END IF;
 BEGIN
  v_date:=nullif(p->>'order_date','')::date;
  v_promised:=nullif(p->>'promised_date','')::date;
 EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN RAISE EXCEPTION 'Enter valid order and promised dates'; END;
 IF v_date IS NULL OR v_date>(now() AT TIME ZONE public.report_tz())::date THEN RAISE EXCEPTION 'Order date must be today or in the past'; END IF;
 IF v_promised IS NULL OR v_promised<v_date THEN RAISE EXCEPTION 'Promised date must be on or after the order date'; END IF;
 IF coalesce(trim(p->'customer'->>'name'),'')='' THEN RAISE EXCEPTION 'Customer name is required'; END IF;
 v_phone:=public.normalize_phone(p->'customer'->>'phone');
 IF v_phone IS NULL OR v_phone !~ '^\+[1-9][0-9]{7,14}$' THEN RAISE EXCEPTION 'Customer phone number is not valid'; END IF;
 BEGIN v_deposit:=(p->>'deposit_already_paid')::numeric;
 EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RAISE EXCEPTION 'Enter a valid deposit with at most 2 decimals'; END;
 IF v_deposit IS NULL OR v_deposit<0 OR v_deposit>=1000000000000 OR v_deposit<>round(v_deposit,2)
   OR v_deposit::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'Enter a valid deposit with at most 2 decimals'; END IF;
 IF jsonb_typeof(p->'items') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Add at least one garment'; END IF;
 IF jsonb_array_length(p->'items')=0 THEN RAISE EXCEPTION 'Add at least one garment'; END IF;
 FOR r IN SELECT * FROM jsonb_array_elements(p->'items') LOOP
  IF coalesce(r->>'item_status','') NOT IN ('awaiting','cutting','stitching','fitting','finishing','quality_check','ready') THEN
   RAISE EXCEPTION 'Choose an open workshop stage for every garment'; END IF;
  FOR m IN SELECT * FROM jsonb_array_elements(coalesce(r->'materials','[]')) LOOP
   IF m->>'source' IS DISTINCT FROM 'customer' THEN RAISE EXCEPTION 'Paper orders can use customer fabric only'; END IF;
  END LOOP;
 END LOOP;
 INSERT INTO public.customers(name,phone) VALUES(trim(p->'customer'->>'name'),v_phone)
  ON CONFLICT (phone) WHERE phone IS NOT NULL DO NOTHING;
 SELECT id INTO v_customer FROM public.customers WHERE phone=v_phone FOR UPDATE;
 -- Keep the real creation audit timestamp; the slip date has its own column.
 v_summary:=public.create_tailoring_order(jsonb_build_object(
  'request_id',gen_random_uuid(),'customer_id',v_customer,'status','confirmed','waive_deposit',true,
  'promised_date',v_promised,'items',p->'items','notes',
  concat('Imported from paper slip ',v_ref,' (',v_date,'). ',p->>'notes')));
 v_order:=(v_summary->>'id')::uuid;
 UPDATE public.tailoring_orders SET paper_ref=v_ref,paper_order_date=v_date WHERE id=v_order;
 IF v_deposit>(v_summary->>'total')::numeric THEN RAISE EXCEPTION 'The deposit is more than the order total'; END IF;
 IF v_deposit>0 THEN
  INSERT INTO public.payments(tailoring_order_id,method,amount,direction,reference)
   VALUES(v_order,'opening',v_deposit,'in',v_ref);
 END IF;
 FOR i IN SELECT id,line_no FROM public.tailoring_items WHERE order_id=v_order ORDER BY line_no LOOP
  v_target:=p->'items'->(i.line_no-1)->>'item_status';
  v_stages:=CASE v_target
   WHEN 'awaiting' THEN ARRAY[]::text[]
   WHEN 'cutting' THEN ARRAY['cutting']
   WHEN 'stitching' THEN ARRAY['cutting','stitching']
   WHEN 'fitting' THEN ARRAY['cutting','stitching','fitting']
   WHEN 'finishing' THEN ARRAY['cutting','stitching','finishing']
   WHEN 'quality_check' THEN ARRAY['cutting','stitching','finishing','quality_check']
   WHEN 'ready' THEN ARRAY['cutting','stitching','finishing','quality_check','ready'] END;
  FOREACH v_stage IN ARRAY v_stages LOOP
   PERFORM public.advance_tailoring_job(i.id,v_stage,'Imported from paper slip '||v_ref);
  END LOOP;
 END LOOP;
 RETURN public.idempotency_finish(v_request,public.tailoring_order_summary(v_order));
END; $$;

REVOKE ALL ON FUNCTION public.import_opening_balances(JSONB),public.import_open_tailoring_order(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.import_opening_balances(JSONB),public.import_open_tailoring_order(JSONB) TO authenticated;

-- Retain report permissions and existing logic; exclude historical tenders.
CREATE OR REPLACE FUNCTION public.report_tenders(
    p_from DATE, p_to DATE, p_branch UUID DEFAULT NULL)
RETURNS TABLE(method TEXT, money_in NUMERIC, money_out NUMERIC, net NUMERIC, count INT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
        RAISE EXCEPTION 'Only managers can see reports' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    WITH receipts AS (
        -- amount is already net of change (tendered - change_given) for cash.
        SELECT p.method, p.direction, p.amount
        FROM public.payments p
        LEFT JOIN public.sales s ON s.id = p.sale_id
        LEFT JOIN public.returns r ON r.id = p.return_id
        LEFT JOIN public.tailoring_orders o ON o.id = p.tailoring_order_id
        LEFT JOIN public.cash_sessions cs ON cs.id = p.cash_session_id
        WHERE p.method NOT IN ('exchange','opening') AND (s.id IS NULL OR s.status <> 'draft')
          AND public.is_branch_member(coalesce(r.branch_id, s.branch_id, o.branch_id, cs.branch_id))
          AND (p_branch IS NULL OR coalesce(r.branch_id, s.branch_id, o.branch_id, cs.branch_id) = p_branch)
          AND p.created_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
          AND p.created_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz())
    )
    SELECT r.method, coalesce(sum(r.amount) FILTER (WHERE r.direction = 'in'), 0),
        coalesce(sum(r.amount) FILTER (WHERE r.direction = 'out'), 0),
        sum(CASE WHEN r.direction = 'out' THEN -r.amount ELSE r.amount END), count(*)::int
    FROM receipts r GROUP BY r.method ORDER BY r.method;
END;
$$;

-- Imported orders use the slip date for order intake. Later receipts collect
-- balance even when the import had no historical deposit.
CREATE OR REPLACE FUNCTION public.report_tailoring(
    p_from DATE, p_to DATE, p_branch UUID DEFAULT NULL)
RETURNS TABLE(orders_taken INT, order_value NUMERIC, deposits NUMERIC, balance_collected NUMERIC,
    delivered_items INT, open_orders INT, open_balance NUMERIC, overdue_items INT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
        RAISE EXCEPTION 'Only managers can see reports' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    WITH orders AS MATERIALIZED (
        SELECT o.*, public.tailoring_order_totals(o.id) AS totals
        FROM public.tailoring_orders o
        WHERE public.is_branch_member(o.branch_id) AND (p_branch IS NULL OR o.branch_id = p_branch)
    ), receipts AS (
        -- There is no deposit flag: the first incoming transaction timestamp
        -- is the deposit batch (including split tenders); later batches collect balance.
        SELECT p.*, o.paper_ref, min(p.created_at) FILTER (WHERE p.direction = 'in')
            OVER (PARTITION BY p.tailoring_order_id) AS first_receipt
        FROM public.payments p JOIN orders o ON o.id = p.tailoring_order_id
        WHERE p.method <> 'exchange'
    ), period_orders AS (
        SELECT count(*)::int AS n, coalesce(sum((o.totals->>'total')::numeric), 0) AS value
        FROM orders o WHERE o.status NOT IN ('draft','cancelled')
          AND coalesce(o.paper_order_date::timestamp AT TIME ZONE public.report_tz(), o.created_at) >= (p_from::timestamp AT TIME ZONE public.report_tz())
          AND coalesce(o.paper_order_date::timestamp AT TIME ZONE public.report_tz(), o.created_at) < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz())
    ), period_payments AS (
        SELECT coalesce(sum(p.amount) FILTER (WHERE p.direction = 'in' AND p.paper_ref IS NULL AND p.created_at = p.first_receipt), 0) AS deposit,
            coalesce(sum(p.amount) FILTER (WHERE p.direction = 'in' AND (p.paper_ref IS NOT NULL OR p.created_at > p.first_receipt)), 0) AS balance
        FROM receipts p
        WHERE p.method <> 'opening' AND p.created_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
          AND p.created_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz())
    ), current_orders AS (
        SELECT count(*)::int AS n, coalesce(sum((o.totals->>'balance')::numeric), 0) AS balance
        FROM orders o WHERE o.status NOT IN ('draft','cancelled','delivered')
    ), items AS (
        SELECT count(*) FILTER (WHERE i.status = 'delivered'
            AND i.delivered_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
            AND i.delivered_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz()))::int AS delivered,
            count(*) FILTER (WHERE i.status NOT IN ('delivered','cancelled')
                AND o.status NOT IN ('draft','cancelled','delivered')
                AND o.promised_date < (now() AT TIME ZONE public.report_tz())::date)::int AS overdue
        FROM orders o JOIN public.tailoring_items i ON i.order_id = o.id
    )
    SELECT o.n, o.value, p.deposit, p.balance, i.delivered, c.n, c.balance, i.overdue
    FROM period_orders o CROSS JOIN period_payments p CROSS JOIN current_orders c CROSS JOIN items i;
END;
$$;

-- Imported deposits were paid before go-live: keep them out of the shift's
-- "other payments" even when the importing user has a shift open.
CREATE OR REPLACE FUNCTION public.cash_session_summary(p_session_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'session', to_jsonb(s),
        'cash_sales', COALESCE((SELECT sum(amount) FROM public.cash_movements WHERE session_id = s.id AND movement_type = 'sale'), 0),
        'cash_refunds', COALESCE((SELECT -sum(amount) FROM public.cash_movements WHERE session_id = s.id AND movement_type = 'refund'), 0),
        'cash_in', COALESCE((SELECT sum(amount) FROM public.cash_movements WHERE session_id = s.id AND movement_type = 'cash_in'), 0),
        'cash_out', COALESCE((SELECT -sum(amount) FROM public.cash_movements WHERE session_id = s.id AND movement_type = 'cash_out'), 0),
        'expected_cash', s.opening_float + COALESCE((SELECT sum(amount) FROM public.cash_movements WHERE session_id = s.id), 0),
        'other_payments', COALESCE((
            SELECT jsonb_object_agg(method, total) FROM (
                SELECT p.method, sum(CASE WHEN p.direction = 'out' THEN -p.amount ELSE p.amount END) AS total
                FROM public.payments p
                WHERE p.method NOT IN ('cash', 'opening') AND p.created_by = s.user_id
                  AND p.created_at >= s.opened_at AND p.created_at <= COALESCE(s.closed_at, now())
                GROUP BY p.method) t), '{}'::jsonb)
    )
    FROM public.cash_sessions s
    WHERE s.id = p_session_id
      AND (s.user_id = auth.uid() OR (public.has_app_role(ARRAY['admin', 'manager']) AND public.is_branch_member(s.branch_id)))
$$;
