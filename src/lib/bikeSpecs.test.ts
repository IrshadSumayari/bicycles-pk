import { PGlite } from '@electric-sql/pglite';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import migration from '../../supabase/migrations/20261109000000_bike_specs.sql?raw';
import { cleanSpecs, primarySpecKeys, specFields, specRows } from '../../shared/bicycles';

// Minimal stand-ins for the objects the migration wraps and patches.
const fixture = `
CREATE ROLE anon; CREATE ROLE authenticated;
CREATE SCHEMA app_private;
CREATE TABLE public.product_styles(id UUID PRIMARY KEY, name TEXT, web_description TEXT);
CREATE TABLE public.roles_now(role TEXT);
CREATE FUNCTION public.has_app_role(r TEXT[]) RETURNS BOOLEAN LANGUAGE sql AS $$ SELECT EXISTS(SELECT 1 FROM public.roles_now WHERE role=ANY(r)) $$;
CREATE FUNCTION public.save_style(p JSONB) RETURNS UUID LANGUAGE plpgsql AS $$
BEGIN
 IF p ? 'specs' THEN RAISE EXCEPTION 'base received specs'; END IF;
 INSERT INTO public.product_styles(id,name) VALUES((p->>'style_id')::uuid,p->>'name')
 ON CONFLICT(id) DO UPDATE SET name=excluded.name;
 RETURN (p->>'style_id')::uuid;
END $$;
CREATE FUNCTION public.catalog_product(p_slug TEXT) RETURNS JSONB LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('title',st.name,'description',st.web_description,'slug',p_slug)
 FROM public.product_styles st WHERE st.name=p_slug
$$;
INSERT INTO public.roles_now VALUES('manager');
`;
const id = '00000000-0000-4000-8000-000000000001';
let db: PGlite;
const save = (p: object) => db.query<{ save_style: string }>('SELECT public.save_style($1::jsonb)', [JSON.stringify({ style_id: id, name: 'city', ...p })]);
const stored = async () => (await db.query<{ specs: Record<string, string> }>('SELECT specs FROM public.product_styles WHERE id=$1', [id])).rows[0].specs;

describe('bike specs migration', () => {
  beforeAll(async () => {
    db = new PGlite();
    await db.exec(fixture);
    await db.exec(migration);
  }, 30000);
  afterAll(async () => { await db.close(); });

  it('allows exactly the spec keys defined for the app', async () => {
    for (const { key } of specFields) {
      const ok = await db.query<{ v: boolean }>('SELECT app_private.valid_bike_specs($1::jsonb) v', [JSON.stringify({ [key]: 'x' })]);
      expect(ok.rows[0].v, key).toBe(true);
    }
    const bad = await db.query<{ v: boolean }>(`SELECT app_private.valid_bike_specs('{"colour":"red"}') v`);
    expect(bad.rows[0].v).toBe(false);
  });

  it('saves trimmed specs, drops blanks and keeps them when omitted', async () => {
    await save({ specs: { gears: ' 21-speed ', brakes: '  ', frame: 'Aluminium' } });
    expect(await stored()).toEqual({ gears: '21-speed', frame: 'Aluminium' });
    await save({ name: 'city' });
    expect(await stored()).toEqual({ gears: '21-speed', frame: 'Aluminium' });
    await save({ specs: {} });
    expect(await stored()).toEqual({});
  });

  it('rejects unknown keys, long values and non-managers', async () => {
    await expect(save({ specs: { colour: 'Red' } })).rejects.toThrow('listed specifications');
    await expect(save({ specs: { gears: 'x'.repeat(121) } })).rejects.toThrow('120 characters');
    await expect(save({ specs: [] })).rejects.toThrow('must be an object');
    await db.exec(`UPDATE public.roles_now SET role='cashier'`);
    await expect(save({ specs: {} })).rejects.toThrow('Not authorized');
    await db.exec(`UPDATE public.roles_now SET role='manager'`);
  });

  it('returns specs with the public product', async () => {
    await save({ specs: { wheel_size: '20"' } });
    const r = await db.query<{ p: { specs: object } }>(`SELECT public.catalog_product('city') p`);
    expect(r.rows[0].p.specs).toEqual({ wheel_size: '20"' });
  });
});

describe('spec helpers', () => {
  it('cleans values to known, trimmed, non-empty strings', () => {
    expect(cleanSpecs({ gears: ' 7 ', brakes: '', colour: 'Red', weight: 12, range: 'x'.repeat(130) }))
      .toEqual({ gears: '7', range: 'x'.repeat(120) });
    expect(cleanSpecs(null)).toEqual({});
    expect(cleanSpecs(['gears'])).toEqual({});
  });
  it('lists filled specs in display order', () => {
    expect(specRows({ weight: '14 kg', frame: 'Steel' }).map(r => r.label)).toEqual(['Frame', 'Weight']);
  });
  it('picks section-relevant fields first', () => {
    expect(primarySpecKeys('Balance Bikes')).toContain('age_range');
    expect(primarySpecKeys('City E-bikes')).toContain('battery');
    expect(primarySpecKeys(undefined)).toContain('frame');
  });
});
