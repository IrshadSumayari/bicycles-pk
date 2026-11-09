import { PGlite } from '@electric-sql/pglite';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import migration from '../../supabase/migrations/20261109000100_catalog_section_filter.sql?raw';

// A stand-in catalog_list containing the fragment the migration patches.
const fixture = `
CREATE TABLE public.items(title TEXT, category TEXT);
INSERT INTO public.items VALUES('City 1','City & Commuter'),('Hybrid 1','Hybrid Bikes'),('Helmet','Helmets');
CREATE FUNCTION public.catalog_list(p JSONB) RETURNS SETOF TEXT LANGUAGE sql STABLE AS $$
 SELECT c.title FROM public.items c WHERE true
  AND (nullif(p->>'category','') IS NULL OR c.category=p->>'category')
 ORDER BY c.title
$$;`;
let db: PGlite;
const list = async (p: object) => (await db.query<{ t: string }>('SELECT public.catalog_list($1::jsonb) t', [JSON.stringify(p)])).rows.map(r => r.t);

describe('catalog section filter migration', () => {
  beforeAll(async () => { db = new PGlite(); await db.exec(fixture); await db.exec(migration); }, 30000);
  afterAll(async () => { await db.close(); });
  it('filters by a category list and keeps the single category filter', async () => {
    expect(await list({ categories: ['City & Commuter', 'Hybrid Bikes'] })).toEqual(['City 1', 'Hybrid 1']);
    expect(await list({ category: 'Helmets' })).toEqual(['Helmet']);
    expect(await list({})).toHaveLength(3);
    expect(await list({ categories: 'Helmets' })).toHaveLength(3);
    expect(await list({ categories: ['Hybrid Bikes'], category: 'Helmets' })).toEqual([]);
  });
});
