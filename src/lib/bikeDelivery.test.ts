import { PGlite } from '@electric-sql/pglite';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import migration from '../../supabase/migrations/20261109000200_bike_delivery.sql?raw';

// Stand-ins for the functions the migration wraps or patches. The base quote
// prices each line at 1000 with a flat 250 delivery fee.
const fixture = `
CREATE ROLE anon; CREATE ROLE authenticated;
CREATE TABLE public.product_styles(id UUID PRIMARY KEY, name TEXT, specs JSONB DEFAULT '{}');
CREATE TABLE public.product_variants(id UUID PRIMARY KEY, style_id UUID);
CREATE TABLE public.app_settings(id UUID PRIMARY KEY, created_at TIMESTAMPTZ DEFAULT now(), store_name TEXT,
 cod_enabled BOOLEAN DEFAULT true, cod_max_total NUMERIC, online_card_enabled BOOLEAN DEFAULT false);
CREATE TABLE public.online_orders(id UUID PRIMARY KEY, order_no TEXT, delivery_fee NUMERIC, total NUMERIC);
INSERT INTO public.app_settings(id,store_name) VALUES('00000000-0000-0000-0000-000000000001','Shop');
INSERT INTO public.product_styles(id,name) VALUES('10000000-0000-0000-0000-000000000001','Bike'),('10000000-0000-0000-0000-000000000002','Helmet');
INSERT INTO public.product_variants VALUES('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002');
CREATE TABLE public.role(name TEXT); INSERT INTO public.role VALUES('admin');
CREATE FUNCTION public.has_app_role(r TEXT[]) RETURNS BOOLEAN LANGUAGE sql AS $$ SELECT (SELECT name FROM public.role)=ANY(r) $$;
CREATE FUNCTION public.save_style(p JSONB) RETURNS UUID LANGUAGE plpgsql AS $$
BEGIN IF p ? 'bulky' THEN RAISE EXCEPTION 'base received bulky'; END IF; RETURN (p->>'id')::uuid; END $$;
CREATE FUNCTION public.update_settings(p JSONB) RETURNS JSONB LANGUAGE plpgsql AS $$
BEGIN IF p ? 'bulky_delivery_fee' OR p ? 'assembly_fee' THEN RAISE EXCEPTION 'base received new keys'; END IF;
 UPDATE public.app_settings SET store_name=coalesce(p->>'store_name',store_name);
 RETURN (SELECT to_jsonb(s) FROM public.app_settings s); END $$;
CREATE FUNCTION public.quote_online_order(p JSONB) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE sub NUMERIC; fee NUMERIC;
BEGIN IF p ? 'assembly' THEN RAISE EXCEPTION 'base received assembly'; END IF;
 SELECT sum((l->>'quantity')::numeric*1000) INTO sub FROM jsonb_array_elements(p->'lines') l;
 fee:=CASE WHEN p->>'fulfilment'='pickup' THEN 0 ELSE 250 END;
 RETURN jsonb_build_object('lines',p->'lines','subtotal',sub,'tax',0,'delivery_fee',fee,'total',sub+fee,'cod_allowed',true,'payment_methods','["cod"]'::jsonb); END $$;
CREATE FUNCTION public.create_online_order(p JSONB) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE q JSONB:=public.quote_online_order(p); o UUID:=gen_random_uuid();
BEGIN INSERT INTO public.online_orders VALUES(o,'W1',(q->>'delivery_fee')::numeric,(q->>'total')::numeric);
 RETURN jsonb_build_object('id',o,'order_no','W1'); END $$;
CREATE FUNCTION public.catalog_product(p_slug TEXT) RETURNS JSONB LANGUAGE sql AS $$
 SELECT jsonb_build_object('description',st.name,'specs',st.specs,'title',st.name) FROM public.product_styles st WHERE st.name=p_slug $$;
CREATE FUNCTION public.online_order_public(p_id UUID) RETURNS JSONB LANGUAGE sql AS $$
 SELECT jsonb_build_object('order_no',o.order_no,'delivery_fee',o.delivery_fee,'total',o.total) FROM public.online_orders o WHERE o.id=p_id $$;`;

const bike = '20000000-0000-0000-0000-000000000001';
const helmet = '20000000-0000-0000-0000-000000000002';
let db: PGlite;
const call = async <T = Record<string, unknown>>(fn: string, p: object) =>
  (await db.query<{ r: T }>(`SELECT public.${fn}($1::jsonb) r`, [JSON.stringify(p)])).rows[0].r;
const quote = (p: object) => call<Record<string, unknown>>('quote_online_order', p);
const lines = [{ variant_id: bike, quantity: 2 }, { variant_id: helmet, quantity: 1 }];

describe('bike delivery migration', () => {
  beforeAll(async () => {
    db = new PGlite();
    await db.exec(fixture);
    await db.exec(migration);
    await call('save_style', { id: '10000000-0000-0000-0000-000000000001', bulky: true });
    await call('update_settings', { bulky_delivery_fee: 1500, assembly_fee: 2000, store_name: 'Bicycles' });
  }, 30000);
  afterAll(async () => { await db.close(); });

  it('saves bulky and the new settings without passing them to the base functions', async () => {
    expect((await db.query<{ bulky: boolean }>('SELECT bulky FROM public.product_styles ORDER BY name')).rows.map(r => r.bulky)).toEqual([true, false]);
    const s = (await db.query<Record<string, unknown>>('SELECT store_name,bulky_delivery_fee,assembly_fee FROM public.app_settings')).rows[0];
    expect(s).toEqual({ store_name: 'Bicycles', bulky_delivery_fee: '1500.00', assembly_fee: '2000.00' });
    await expect(call('save_style', { id: '10000000-0000-0000-0000-000000000002', bulky: 'yes' })).rejects.toThrow('bulky');
    await expect(call('update_settings', { assembly_fee: -1 })).rejects.toThrow('non-negative');
  });

  it('adds the bulky charge per bike on delivery only', async () => {
    const q = await quote({ fulfilment: 'delivery', lines });
    expect(q).toMatchObject({ bulky_units: 2, bulky_fee: 3000, delivery_fee: 3250, total: 6250, assembly: false, assembly_available: true, assembly_unit_fee: 2000 });
    const pickup = await quote({ fulfilment: 'pickup', lines, assembly: true });
    expect(pickup).toMatchObject({ delivery_fee: 0, total: 3000, assembly: false, assembly_available: false });
  });

  it('adds assembly when asked and rejects it when not offered', async () => {
    expect(await quote({ fulfilment: 'delivery', lines, assembly: true })).toMatchObject({ assembly: true, assembly_fee: 4000, delivery_fee: 7250, total: 10250 });
    await expect(quote({ fulfilment: 'delivery', lines: [{ variant_id: helmet, quantity: 1 }], assembly: true })).rejects.toThrow('Assembly is not available');
    await expect(quote({ fulfilment: 'delivery', lines, assembly: 'yes' })).rejects.toThrow('assembly');
  });

  it('applies the cash on delivery limit to the new total', async () => {
    await db.exec('UPDATE public.app_settings SET cod_max_total=7000');
    expect(await quote({ fulfilment: 'delivery', lines, assembly: true })).toMatchObject({ cod_allowed: false, payment_methods: [] });
    await db.exec('UPDATE public.app_settings SET cod_max_total=NULL');
  });

  it('records assembly on the order and shows it to the customer', async () => {
    const r = await call<{ id: string; assembly: boolean }>('create_online_order', { fulfilment: 'delivery', lines, assembly: true });
    expect(r.assembly).toBe(true);
    const o = (await db.query<{ r: Record<string, unknown> }>('SELECT public.online_order_public($1) r', [r.id])).rows[0].r;
    expect(o).toMatchObject({ assembly: true, delivery_fee: 7250, total: 10250 });
    const p = (await db.query<{ r: Record<string, unknown> }>("SELECT public.catalog_product('Bike') r")).rows[0].r;
    expect(p.bulky).toBe(true);
  });
});
