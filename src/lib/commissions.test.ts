import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { PGlite } from '@electric-sql/pglite';
import migration from '../../supabase/migrations/20261031000000_sales_commissions.sql?raw';

const admin = '00000000-0000-0000-0000-000000000001';
const seller = '00000000-0000-0000-0000-000000000002';
const manager = '00000000-0000-0000-0000-000000000003';
const other = '00000000-0000-0000-0000-000000000004';
const branch = '00000000-0000-0000-0000-000000000010';
const away = '00000000-0000-0000-0000-000000000011';
let db: PGlite;
const asUser = (id: string) => db.query(`SELECT set_config('request.jwt.claim.sub',$1,false)`, [id]);
async function scalar<T = number>(sql: string, args: unknown[] = []) { return (await db.query<{ value: T }>(sql, args)).rows[0].value; }
async function rule(kind = 'percentage', rate = 5, user = seller) { await db.query('SELECT public.save_commission_rule($1,$2,$3,$4,true)', [branch, user, kind, rate]); }
async function sale(extra: Record<string, unknown> = {}) {
  const p = { request_id: crypto.randomUUID(), salesperson_id: seller, branch_id: branch, test_net: 900, ...extra };
  const result = await scalar<{ sale: { id: string } }>('SELECT public.post_sale($1::jsonb) value', [JSON.stringify(p)]);
  return { p, id: result.sale.id };
}

// A minimal checkout fixture isolates the NEW migration. Existing checkout pricing,
// payments, stock and return authorization have their own full Supabase SQL tests.
const fixture = `
CREATE ROLE anon; CREATE ROLE authenticated;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
GRANT USAGE ON SCHEMA auth TO authenticated,anon;
CREATE TABLE public.users(id uuid PRIMARY KEY,name text,role text,active boolean DEFAULT true);
CREATE TABLE public.branches(id uuid PRIMARY KEY,name text,code text,active boolean DEFAULT true,created_at timestamptz DEFAULT now());
CREATE TABLE public.branch_memberships(user_id uuid,branch_id uuid);
CREATE FUNCTION public.has_app_role(text[]) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT EXISTS(SELECT 1 FROM public.users WHERE id=auth.uid() AND active AND role=ANY($1)) $$;
CREATE FUNCTION public.is_counter_staff() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT public.has_app_role(ARRAY['admin','manager','cashier']) $$;
CREATE FUNCTION public.is_branch_member(uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT public.has_app_role(ARRAY['admin']) OR EXISTS(SELECT 1 FROM public.branch_memberships WHERE user_id=auth.uid() AND branch_id=$1) $$;
CREATE TABLE public.sales(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),request_id uuid UNIQUE,branch_id uuid,cashier_id uuid,status text,invoice_number text);
CREATE TABLE public.sale_lines(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),sale_id uuid,net numeric,is_gift boolean DEFAULT false);
CREATE TABLE public.return_lines(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),sale_line_id uuid,refund_amount numeric,tax_amount numeric);
CREATE FUNCTION public.prevent_ledger_changes() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Ledger is append-only'; END $$;
CREATE FUNCTION public.post_sale(p_request jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE s public.sales;
BEGIN
 SELECT * INTO s FROM public.sales WHERE request_id=(p_request->>'request_id')::uuid;
 IF s.id IS NULL THEN
 INSERT INTO public.sales(request_id,branch_id,cashier_id,status,invoice_number)
 VALUES((p_request->>'request_id')::uuid,(p_request->>'branch_id')::uuid,auth.uid(),coalesce(p_request->>'status','completed'),'INV-'||(p_request->>'request_id')) RETURNING * INTO s;
 INSERT INTO public.sale_lines(sale_id,net) VALUES(s.id,(p_request->>'test_net')::numeric);
 INSERT INTO public.sale_lines(sale_id,net,is_gift) VALUES(s.id,100,true);
 END IF;
 RETURN jsonb_build_object('sale',to_jsonb(s));
END $$;
CREATE FUNCTION public.post_exchange(p jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN RETURN public.post_sale(p - 'salesperson_id'); END $$;
INSERT INTO public.users(id,name,role) VALUES('${admin}','Admin','admin'),('${seller}','Salesperson','cashier'),('${manager}','Manager','manager'),('${other}','Other cashier','cashier');
INSERT INTO public.branches(id,name,code) VALUES('${branch}','Main store','A'),('${away}','Other store','B');
INSERT INTO public.branch_memberships VALUES('${seller}','${branch}'),('${manager}','${branch}'),('${other}','${branch}');
`;

describe('sales commission PostgreSQL migration', () => {
  beforeAll(async () => {
    db = new PGlite(); await db.exec(fixture);
    await db.exec(migration);
  }, 30000);
  beforeEach(async () => { await db.exec('BEGIN'); await asUser(admin); });
  afterEach(async () => { await db.exec('ROLLBACK; RESET ROLE'); });
  afterAll(async () => { await db.close(); });

  it('uses discounted net, excludes gifts/tax, snapshots rates and posts once on retries', async () => {
    await rule(); const { p, id } = await sale();
    expect(Number(await scalar('SELECT original_amount value FROM sale_commissions WHERE sale_id=$1', [id]))).toBe(45);
    await rule('percentage', 20);
    await db.query('SELECT post_sale($1::jsonb)', [JSON.stringify(p)]);
    expect(Number(await scalar('SELECT sum(amount) value FROM commission_entries'))).toBe(45);
    const next = await sale();
    expect(Number(await scalar('SELECT original_amount value FROM sale_commissions WHERE sale_id=$1', [next.id]))).toBe(180);
    await expect(db.query('SELECT post_sale($1::jsonb)', [JSON.stringify({ ...p, salesperson_id: other })])).rejects.toThrow('different salesperson');
  });

  it('earns a fixed amount per invoice, includes credit, and excludes drafts and zero-value invoices', async () => {
    await rule('fixed', 250); await sale({ status: 'credit', test_net: 12000 });
    await sale({ status: 'draft', salesperson_id: null }); await sale({ test_net: 0 }); await sale({ salesperson_id: null });
    expect(Number(await scalar('SELECT sum(amount) value FROM commission_entries'))).toBe(250);
    expect(Number(await scalar('SELECT count(*) value FROM sale_commissions'))).toBe(3);
  });

  it('reverses fixed commission cumulatively on partial/full returns without a rounding residue', async () => {
    await rule('fixed', 100); const { id } = await sale({ test_net: 300 });
    const line = await scalar<string>('SELECT id value FROM sale_lines WHERE sale_id=$1 AND NOT is_gift', [id]);
    const amounts = [];
    for (let n = 0; n < 3; n++) {
      await db.query('INSERT INTO return_lines(sale_line_id,refund_amount,tax_amount) VALUES($1,110,10)', [line]);
      amounts.push(Number(await scalar("SELECT -sum(amount) value FROM commission_entries WHERE kind='return'")));
    }
    expect(amounts).toEqual([33.33, 66.67, 100]);
    expect(Number(await scalar('SELECT sum(amount) value FROM commission_entries'))).toBe(0);
  });

  it('records idempotent payouts, prevents overpayment, and carries back returns after payment', async () => {
    await rule('fixed', 250); const { id } = await sale();
    const request = crypto.randomUUID();
    const pay = () => db.query('SELECT record_commission_payout($1,$2,100,$3,$4)', [branch, seller, 'Bank transfer 123', request]);
    await pay(); await pay();
    expect(Number(await scalar("SELECT count(*) value FROM commission_entries WHERE kind='payout'"))).toBe(1);
    const line = await scalar<string>('SELECT id value FROM sale_lines WHERE sale_id=$1 AND NOT is_gift', [id]);
    await db.query('INSERT INTO return_lines(sale_line_id,refund_amount,tax_amount) VALUES($1,990,90)', [line]);
    expect(Number(await scalar('SELECT sum(amount) value FROM commission_entries'))).toBe(-100);
    await expect(db.query('SELECT record_commission_payout($1,$2,1,$3,$4)', [branch, seller, 'Another payment', crypto.randomUUID()])).rejects.toThrow('exceeds outstanding');
  });

  it('limits staff to their own commissions and prevents direct writes or private checkout bypass', async () => {
    await rule(); await sale(); await asUser(other); await db.exec('SET ROLE authenticated');
    expect(Number(await scalar('SELECT count(*) value FROM commission_entries'))).toBe(0);
    const report = await scalar<{ summary: unknown[]; can_manage: boolean }>('SELECT commission_overview($1) value', [JSON.stringify({ branch_id: branch, from: '2000-01-01', to: '2000-01-31', user_id: seller })]);
    expect(report.summary).toEqual([]); expect(report.can_manage).toBe(false);
    expect(await scalar<boolean>("SELECT has_function_privilege('authenticated','public.post_sale_without_commission(jsonb)','EXECUTE') value")).toBe(false);
    expect(await scalar<boolean>("SELECT has_function_privilege('anon','public.post_sale(jsonb)','EXECUTE') value")).toBe(false);
    await expect(db.query('SELECT save_commission_rule($1,$2,$3,90,true)', [branch, other, 'percentage'])).rejects.toThrow('Only branch managers');
  });

  it('passes replacement-sale attribution through the existing exchange transaction', async () => {
    await rule('fixed', 60);
    const p = { request_id: crypto.randomUUID(), salesperson_id: seller, branch_id: branch, test_net: 1200 };
    await db.query('SELECT post_exchange($1::jsonb)', [JSON.stringify(p)]);
    expect(Number(await scalar('SELECT sum(amount) value FROM commission_entries'))).toBe(60);
    expect(await scalar<string>("SELECT current_setting('pos.exchange_salesperson',true) value")).toBe('');
  });

  it('refuses manager changes outside their branch', async () => {
    await asUser(manager);
    await expect(db.query('SELECT save_commission_rule($1,$2,$3,5,true)', [away, seller, 'percentage'])).rejects.toThrow('Only branch managers');
  });

  it('rolls back the checkout when salesperson validation fails', async () => {
    await db.exec('SAVEPOINT invalid_seller');
    await expect(sale()).rejects.toThrow('not enabled');
    await db.exec('ROLLBACK TO SAVEPOINT invalid_seller');
    expect(Number(await scalar('SELECT count(*) value FROM sales'))).toBe(0);
    expect(Number(await scalar('SELECT count(*) value FROM commission_entries'))).toBe(0);
  });

  it('rejects invalid percentage rates', async () => {
    await expect(rule('percentage', 101)).rejects.toThrow('valid commission');
  });
});
