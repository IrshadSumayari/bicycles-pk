# P7-03 Website app: catalog pages

**Branch:** `feat/website-catalog`
**Needs:** P7-01 merged (public catalog functions). P7-02 is helpful for test data but not required.
**Files:** new folder `website/` only, plus root `package.json` scripts, `.github/workflows/ci.yml`
(add a website job), `.gitignore`.
**Not in scope:** cart, checkout, accounts (later plans). Brand design: use a clean neutral
layout with CSS variables for colours and fonts so the designer's look can be dropped in later.

## Decisions (already made, see `docs/DEVELOPMENT_PLAN.md` D13, D17)
- Separate app in `website/`, own `package.json`, own build and deploy, same Supabase project.
- **Framework: Next.js (confirmed by the owner; latest stable, App Router, TypeScript)** for server
  rendering and SEO. Host on Vercel or any Node host; do not use features that lock it to one host.
  Pin exact versions. Tailwind 4 like the POS.
- Data only through the public functions (`catalog_list`, `catalog_product`,
  `catalog_collections`, `catalog_facets`) with the **anon** key, on the server
  (`@supabase/supabase-js`, no service-role key anywhere in `website/`).
- Generated types: import from `../src/lib/database.types.ts` via a path alias, or copy with a
  script `npm run types` in `website/` that runs `supabase gen types` — choose the path alias
  if it works with the Next.js build; report the choice.

## Pages
- `/` home: hero (from the first published collection), featured collections, new arrivals
  (`catalog_list` sort `new`, 8 items).
- `/collections/[slug]`: grid with filters (size, color, price) and sort, paging via
  `?page=`; filters in the URL query so pages are shareable and crawlable.
- `/products/[slug]`: gallery, title, price (and compare-at struck through), size and color picker
  (only combinations that exist; out-of-stock combinations shown disabled), stock band text
  ("Only a few left"), size chart modal if present, description, related products,
  "Order on WhatsApp" button (link with product title and URL) — a placeholder for the cart.
- `/search?q=`: same grid.
- `not-found` page; unpublished slugs return 404.
- Rendering: product and collection pages use ISR with `revalidate = 60`; stock band is
  fetched **again on the client** on the product page so a POS sale shows on refresh.
- SEO: `generateMetadata` (title, description, Open Graph image = first product image),
  `app/sitemap.ts` (all published product and collection slugs), `app/robots.ts`,
  Product JSON-LD (`offers.availability` from the stock band, price in PKR).
- Images: `next/image` with the Supabase public URL domain allowed in `next.config`.
- Mobile first; Lighthouse performance ≥ 85 and accessibility ≥ 90 on the product page locally.

## Config
- `website/.env.example`: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`,
  `NEXT_PUBLIC_SITE_URL`, `NEXT_PUBLIC_WHATSAPP_NUMBER`. Real `.env*` ignored.
- Root `package.json`: `"web:dev": "npm --prefix website run dev"`, `"web:build": ...`,
  `"web:lint": ...`.
- CI: new job `website` — `npm ci` + lint + type-check + build in `website/` (use dummy env values).

## Tests
- Vitest in `website/` for pure helpers: filter query parsing/serialising, price formatting
  (`PKR 4,500`), variant matrix (which size/color combos are available), JSON-LD builder.
- One Playwright test (in `website/e2e/`, may be skipped in CI if no DB) that opens home →
  collection → product against local Supabase with seeded published data.

## Done when
`npm run web:build` succeeds, POS checks still pass, the three page types work against local
Supabase with a published product, and an unpublished slug gives 404.
