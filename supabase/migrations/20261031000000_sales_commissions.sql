-- Invoice-based salesperson commissions. Existing invoices are not backfilled.
CREATE TABLE public.commission_rules (
 branch_id UUID NOT NULL REFERENCES public.branches(id),
 user_id UUID NOT NULL REFERENCES public.users(id),
 kind TEXT NOT NULL CHECK(kind IN ('fixed','percentage')),
 rate NUMERIC(14,2) NOT NULL CHECK(rate >= 0 AND rate::text NOT IN ('NaN','Infinity','-Infinity')),
 enabled BOOLEAN NOT NULL DEFAULT false,
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_by UUID REFERENCES public.users(id),
 PRIMARY KEY(branch_id,user_id),
 CHECK(kind <> 'percentage' OR rate <= 100), CHECK(NOT enabled OR rate > 0)
);
CREATE TABLE public.sale_commissions (
 sale_id UUID PRIMARY KEY REFERENCES public.sales(id),
 branch_id UUID NOT NULL REFERENCES public.branches(id),
 user_id UUID REFERENCES public.users(id),
 person_name TEXT,
 kind TEXT CHECK(kind IN ('fixed','percentage')),
 rate NUMERIC(14,2) NOT NULL DEFAULT 0,
 basis NUMERIC(14,2) NOT NULL CHECK(basis >= 0),
 original_amount NUMERIC(14,2) NOT NULL CHECK(original_amount >= 0),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.commission_entries (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 branch_id UUID NOT NULL REFERENCES public.branches(id),
 user_id UUID NOT NULL REFERENCES public.users(id),
 kind TEXT NOT NULL CHECK(kind IN ('earned','return','payout')),
 amount NUMERIC(14,2) NOT NULL,
 sale_id UUID REFERENCES public.sale_commissions(sale_id),
 return_line_id UUID UNIQUE REFERENCES public.return_lines(id),
 request_id UUID UNIQUE,
 note TEXT,
 created_by UUID DEFAULT auth.uid() REFERENCES public.users(id),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK(amount::text NOT IN ('NaN','Infinity','-Infinity')),
 CHECK((kind='earned' AND amount>0 AND sale_id IS NOT NULL AND return_line_id IS NULL AND request_id IS NULL)
    OR (kind='return' AND amount<0 AND sale_id IS NOT NULL AND return_line_id IS NOT NULL AND request_id IS NULL)
    OR (kind='payout' AND amount<0 AND sale_id IS NULL AND return_line_id IS NULL AND request_id IS NOT NULL))
);
CREATE UNIQUE INDEX commission_one_earning ON public.commission_entries(sale_id) WHERE kind='earned';
CREATE INDEX commission_account ON public.commission_entries(branch_id,user_id,created_at,id);
ALTER TABLE public.commission_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_commissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commission_entries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.commission_rules,public.sale_commissions,public.commission_entries FROM anon,authenticated;
GRANT SELECT ON public.commission_rules,public.sale_commissions,public.commission_entries TO authenticated;
CREATE POLICY commission_rules_read ON public.commission_rules FOR SELECT TO authenticated
 USING(public.is_branch_member(branch_id) AND (user_id=auth.uid() OR public.has_app_role(ARRAY['admin','manager'])));
CREATE POLICY commission_sales_read ON public.sale_commissions FOR SELECT TO authenticated
 USING(public.is_branch_member(branch_id) AND (user_id=auth.uid() OR public.has_app_role(ARRAY['admin','manager'])));
CREATE POLICY commission_entries_read ON public.commission_entries FOR SELECT TO authenticated
 USING(public.is_branch_member(branch_id) AND (user_id=auth.uid() OR public.has_app_role(ARRAY['admin','manager'])));
CREATE TRIGGER commission_sales_immutable BEFORE UPDATE OR DELETE ON public.sale_commissions
 FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();
CREATE TRIGGER commission_entries_immutable BEFORE UPDATE OR DELETE ON public.commission_entries
 FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_changes();

CREATE FUNCTION public.commission_branches() RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY created_at,code)
 FROM public.branches WHERE active AND public.is_branch_member(id)),'[]'::jsonb);
END; $$;
CREATE FUNCTION public.commission_sellers(p_branch UUID) RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) OR NOT coalesce(public.is_branch_member(p_branch),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',u.id,'name',u.name) ORDER BY u.name,u.id)
 FROM public.users u JOIN public.commission_rules r ON r.user_id=u.id AND r.branch_id=p_branch
 WHERE u.active AND u.role IN ('admin','manager','cashier') AND r.enabled
 AND (u.role='admin' OR EXISTS(SELECT 1 FROM public.branch_memberships m WHERE m.user_id=u.id AND m.branch_id=p_branch))),'[]'::jsonb);
END; $$;
CREATE FUNCTION public.save_commission_rule(p_branch UUID,p_user UUID,p_kind TEXT,p_rate NUMERIC,p_enabled BOOLEAN)
 RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) OR NOT coalesce(public.is_branch_member(p_branch),false) THEN RAISE EXCEPTION 'Only branch managers can change commission rules' USING ERRCODE='42501'; END IF;
 IF p_kind IS NULL OR p_kind NOT IN ('fixed','percentage') OR p_enabled IS NULL OR p_rate IS NULL OR p_rate<0 OR p_rate<>round(p_rate,2)
 OR p_rate::text IN ('NaN','Infinity','-Infinity') OR (p_kind='percentage' AND p_rate>100) OR (p_enabled AND p_rate=0) THEN RAISE EXCEPTION 'Enter a valid commission amount or percentage'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.users u WHERE u.id=p_user AND u.role IN ('admin','manager','cashier') AND (NOT p_enabled OR u.active)
 AND (u.role='admin' OR EXISTS(SELECT 1 FROM public.branch_memberships m WHERE m.user_id=u.id AND m.branch_id=p_branch))) THEN RAISE EXCEPTION 'Choose a salesperson in this branch'; END IF;
 INSERT INTO public.commission_rules(branch_id,user_id,kind,rate,enabled,updated_by)
 VALUES(p_branch,p_user,p_kind,p_rate,p_enabled,auth.uid()) ON CONFLICT(branch_id,user_id)
 DO UPDATE SET kind=excluded.kind,rate=excluded.rate,enabled=excluded.enabled,updated_at=now(),updated_by=auth.uid();
END; $$;

-- Keep the existing checkout transaction, including all price/stock/payment checks.
-- The private base function must not be callable directly by browser roles.
ALTER FUNCTION public.post_sale(JSONB) RENAME TO post_sale_without_commission;
REVOKE ALL ON FUNCTION public.post_sale_without_commission(JSONB) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.post_sale(p_request JSONB) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_result JSONB; v_sale public.sales; v_rule public.commission_rules; v_snapshot public.sale_commissions;
 v_user UUID:=coalesce(nullif(p_request->>'salesperson_id',''),nullif(current_setting('pos.exchange_salesperson',true),''))::uuid; v_name TEXT; v_basis NUMERIC; v_amount NUMERIC;
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 v_result:=public.post_sale_without_commission(p_request);
 SELECT * INTO v_sale FROM public.sales WHERE id=(v_result->'sale'->>'id')::uuid;
 IF v_sale.cashier_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'This checkout belongs to another cashier' USING ERRCODE='42501'; END IF;
 IF v_sale.status='draft' THEN
   IF v_user IS NOT NULL THEN RAISE EXCEPTION 'Assign commission when checking out, not on a draft'; END IF;
   RETURN v_result;
 END IF;
 SELECT * INTO v_snapshot FROM public.sale_commissions WHERE sale_id=v_sale.id;
 IF FOUND THEN
   IF v_snapshot.user_id IS DISTINCT FROM v_user THEN RAISE EXCEPTION 'This sale already has a different salesperson'; END IF;
   RETURN v_result;
 END IF;
 IF v_sale.status NOT IN ('completed','credit') THEN RAISE EXCEPTION 'This sale cannot earn commission'; END IF;
 SELECT round(coalesce(sum(net),0),2) INTO v_basis FROM public.sale_lines WHERE sale_id=v_sale.id AND NOT is_gift;
 v_amount:=0;
 IF v_user IS NOT NULL THEN
   SELECT name INTO v_name FROM public.users u WHERE u.id=v_user AND u.active AND u.role IN ('admin','manager','cashier')
    AND (u.role='admin' OR EXISTS(SELECT 1 FROM public.branch_memberships m WHERE m.user_id=u.id AND m.branch_id=v_sale.branch_id));
   IF NOT FOUND THEN RAISE EXCEPTION 'Choose an active salesperson in this branch'; END IF;
   SELECT * INTO v_rule FROM public.commission_rules WHERE branch_id=v_sale.branch_id AND user_id=v_user AND enabled FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Commission is not enabled for this salesperson. Refresh checkout.'; END IF;
   IF v_basis>0 THEN v_amount:=CASE WHEN v_rule.kind='fixed' THEN v_rule.rate ELSE round(v_basis*v_rule.rate/100,2) END; END IF;
 END IF;
 INSERT INTO public.sale_commissions(sale_id,branch_id,user_id,person_name,kind,rate,basis,original_amount)
 VALUES(v_sale.id,v_sale.branch_id,v_user,v_name,v_rule.kind,coalesce(v_rule.rate,0),v_basis,v_amount);
 IF v_amount>0 THEN INSERT INTO public.commission_entries(branch_id,user_id,kind,amount,sale_id)
 VALUES(v_sale.branch_id,v_user,'earned',v_amount,v_sale.id); END IF;
 RETURN v_result;
END; $$;

ALTER FUNCTION public.post_exchange(JSONB) RENAME TO post_exchange_without_commission;
REVOKE ALL ON FUNCTION public.post_exchange_without_commission(JSONB) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.post_exchange(p JSONB) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_previous TEXT:=current_setting('pos.exchange_salesperson',true); v_result JSONB; v_user UUID:=nullif(p->>'salesperson_id','')::uuid; v_recorded UUID;
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 PERFORM set_config('pos.exchange_salesperson',coalesce(v_user::text,''),true);
 v_result:=public.post_exchange_without_commission(p);
 SELECT user_id INTO v_recorded FROM public.sale_commissions WHERE sale_id=(v_result->'sale'->>'id')::uuid;
 IF v_recorded IS DISTINCT FROM v_user THEN RAISE EXCEPTION 'This exchange already has a different salesperson'; END IF;
 PERFORM set_config('pos.exchange_salesperson',coalesce(v_previous,''),true);
 RETURN v_result;
END; $$;

CREATE FUNCTION public.reverse_sale_commission() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE c public.sale_commissions; v_returned NUMERIC; v_prior NUMERIC; v_target NUMERIC; v_delta NUMERIC;
BEGIN
 SELECT sc.* INTO c FROM public.sale_commissions sc JOIN public.sale_lines sl ON sl.sale_id=sc.sale_id WHERE sl.id=NEW.sale_line_id;
 IF c.original_amount IS NULL OR c.original_amount=0 OR c.basis=0 THEN RETURN NEW; END IF;
 -- create_return locks the sale header before inserting any return lines.
 SELECT coalesce(sum(rl.refund_amount-rl.tax_amount),0) INTO v_returned FROM public.return_lines rl
 JOIN public.sale_lines sl ON sl.id=rl.sale_line_id WHERE sl.sale_id=c.sale_id AND NOT sl.is_gift;
 SELECT -coalesce(sum(amount),0) INTO v_prior FROM public.commission_entries WHERE sale_id=c.sale_id AND kind='return';
 v_target:=least(c.original_amount,greatest(0,round(c.original_amount*v_returned/c.basis,2)));
 v_delta:=v_target-v_prior;
 IF v_delta>0 THEN INSERT INTO public.commission_entries(branch_id,user_id,kind,amount,sale_id,return_line_id,note)
 VALUES(c.branch_id,c.user_id,'return',-v_delta,c.sale_id,NEW.id,'Proportional return reversal'); END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER reverse_commission_after_return AFTER INSERT ON public.return_lines FOR EACH ROW EXECUTE FUNCTION public.reverse_sale_commission();

CREATE FUNCTION public.record_commission_payout(p_branch UUID,p_user UUID,p_amount NUMERIC,p_note TEXT,p_request UUID)
 RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_entry public.commission_entries; v_balance NUMERIC;
BEGIN
 IF NOT coalesce(public.has_app_role(ARRAY['admin','manager']),false) OR NOT coalesce(public.is_branch_member(p_branch),false) THEN RAISE EXCEPTION 'Only branch managers can record payouts' USING ERRCODE='42501'; END IF;
 IF p_request IS NULL OR p_user IS NULL OR p_amount IS NULL OR p_amount<=0 OR p_amount<>round(p_amount,2) OR p_amount::text IN ('NaN','Infinity','-Infinity') OR length(trim(coalesce(p_note,'')))=0 OR length(p_note)>500 THEN RAISE EXCEPTION 'Enter an amount and payment reference (up to 500 characters)'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('commission-request:'||p_request::text,0));
 SELECT * INTO v_entry FROM public.commission_entries WHERE request_id=p_request;
 IF FOUND THEN
   IF v_entry.branch_id IS DISTINCT FROM p_branch OR v_entry.user_id IS DISTINCT FROM p_user OR v_entry.amount<>-p_amount OR v_entry.note<>trim(p_note) OR v_entry.created_by IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Payout reference was already used for a different payment'; END IF;
   RETURN to_jsonb(v_entry);
 END IF;
 -- Serialize payouts for this account. A later return can create a carry-forward debit.
 PERFORM pg_advisory_xact_lock(hashtextextended('commission-account:'||p_branch::text||':'||p_user::text,0));
 SELECT coalesce(sum(amount),0) INTO v_balance FROM public.commission_entries WHERE branch_id=p_branch AND user_id=p_user;
 IF p_amount>v_balance THEN RAISE EXCEPTION 'Payout exceeds outstanding commission (%)',v_balance; END IF;
 INSERT INTO public.commission_entries(branch_id,user_id,kind,amount,note,request_id)
 VALUES(p_branch,p_user,'payout',-p_amount,trim(p_note),p_request) RETURNING * INTO v_entry;
 RETURN to_jsonb(v_entry);
END; $$;

CREATE FUNCTION public.commission_overview(p JSONB) RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE v_branch UUID:=(p->>'branch_id')::uuid; v_from DATE:=(p->>'from')::date; v_to DATE:=(p->>'to')::date;
 v_user UUID:=nullif(p->>'user_id','')::uuid; v_manager BOOLEAN; v_start TIMESTAMPTZ; v_end TIMESTAMPTZ; v_people JSONB; v_summary JSONB; v_rows JSONB; v_count BIGINT;
BEGIN
 IF NOT coalesce(public.is_counter_staff(),false) OR NOT coalesce(public.is_branch_member(v_branch),false) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 v_manager:=coalesce(public.has_app_role(ARRAY['admin','manager']),false);
 IF NOT v_manager THEN v_user:=auth.uid(); END IF;
 IF v_from IS NULL OR v_to IS NULL OR v_from>v_to OR v_to-v_from>366 THEN RAISE EXCEPTION 'Choose a date range up to one year'; END IF;
 v_start:=v_from::timestamp AT TIME ZONE 'Asia/Karachi'; v_end:=(v_to+1)::timestamp AT TIME ZONE 'Asia/Karachi';
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'active',u.active,'enabled',coalesce(r.enabled,false),'kind',coalesce(r.kind,'percentage'),'rate',coalesce(r.rate,0)) ORDER BY u.name,u.id),'[]'::jsonb)
 INTO v_people FROM public.users u LEFT JOIN public.commission_rules r ON r.user_id=u.id AND r.branch_id=v_branch
 WHERE (v_manager OR u.id=auth.uid()) AND ((u.role IN ('admin','manager','cashier') AND (u.role='admin' OR EXISTS(SELECT 1 FROM public.branch_memberships m WHERE m.user_id=u.id AND m.branch_id=v_branch)))
 OR EXISTS(SELECT 1 FROM public.commission_entries e WHERE e.user_id=u.id AND e.branch_id=v_branch));
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.name,x.user_id),'[]'::jsonb) INTO v_summary FROM (
 SELECT e.user_id,u.name,coalesce(sum(e.amount),0) balance,
 coalesce(sum(e.amount) FILTER(WHERE e.kind='earned' AND e.created_at>=v_start AND e.created_at<v_end),0) earned,
 -coalesce(sum(e.amount) FILTER(WHERE e.kind='return' AND e.created_at>=v_start AND e.created_at<v_end),0) reversed,
 -coalesce(sum(e.amount) FILTER(WHERE e.kind='payout' AND e.created_at>=v_start AND e.created_at<v_end),0) paid,
 count(*) FILTER(WHERE e.kind='earned' AND e.created_at>=v_start AND e.created_at<v_end) invoices
 FROM public.commission_entries e JOIN public.users u ON u.id=e.user_id WHERE e.branch_id=v_branch AND (v_user IS NULL OR e.user_id=v_user) GROUP BY e.user_id,u.name
 ) x;
 SELECT count(*) INTO v_count FROM public.commission_entries e WHERE e.branch_id=v_branch AND (v_user IS NULL OR e.user_id=v_user) AND e.created_at>=v_start AND e.created_at<v_end;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC),'[]'::jsonb) INTO v_rows FROM (
 SELECT e.id,e.user_id,u.name,e.kind,e.amount,e.note,e.created_at,s.invoice_number,sc.kind rule_kind,sc.rate rule_rate,sc.basis
 FROM public.commission_entries e JOIN public.users u ON u.id=e.user_id LEFT JOIN public.sales s ON s.id=e.sale_id LEFT JOIN public.sale_commissions sc ON sc.sale_id=e.sale_id
 WHERE e.branch_id=v_branch AND (v_user IS NULL OR e.user_id=v_user) AND e.created_at>=v_start AND e.created_at<v_end
 ORDER BY e.created_at DESC,e.id DESC LIMIT 50 OFFSET greatest(0,coalesce((p->>'offset')::int,0))
 ) x;
 RETURN jsonb_build_object('people',v_people,'summary',v_summary,'entries',v_rows,'total_count',v_count,'can_manage',v_manager);
END; $$;

REVOKE ALL ON FUNCTION public.reverse_sale_commission() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.commission_branches(),public.commission_sellers(UUID),public.save_commission_rule(UUID,UUID,TEXT,NUMERIC,BOOLEAN),public.post_sale(JSONB),public.post_exchange(JSONB),public.record_commission_payout(UUID,UUID,NUMERIC,TEXT,UUID),public.commission_overview(JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.commission_branches(),public.commission_sellers(UUID),public.save_commission_rule(UUID,UUID,TEXT,NUMERIC,BOOLEAN),public.post_sale(JSONB),public.post_exchange(JSONB),public.record_commission_payout(UUID,UUID,NUMERIC,TEXT,UUID),public.commission_overview(JSONB) TO authenticated;
