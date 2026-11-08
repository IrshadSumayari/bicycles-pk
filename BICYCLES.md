# Bicycles.pk development

Domain: https://bicycles.pk (still serving the coming-soon page from `main`).

This repository started as an export of LadyVogue `origin/dev` at `dde73de` (tracked files only; no
environment files, data or secrets). POS source is in `src/`, the Next.js website in `website/`,
shared rules in `shared/`, and database migrations in `supabase/`. The plan is in
[docs/BICYCLES_PLAN.md](docs/BICYCLES_PLAN.md); the inherited LadyVogue history is in
[docs/LADYVOGUE_HISTORY.md](docs/LADYVOGUE_HISTORY.md).

## Configuration

Use a dedicated Bicycles.pk Supabase project. Local Supabase uses project ID `bicycles` and ports 55330–55339, so it can run beside a local LadyVogue instance (55320–55329). Search indexing stays off (`noindex`) until launch. Never reuse
LadyVogue's database, Vercel projects or deployment secrets. Install with `npm ci` and
`npm --prefix website ci`; run `npm run dev` (POS) and `npm run web:dev` (website), each with its own
environment file based on the examples. Production branch is `main`; staging is `dev`.

## Milestone 0: identity and cleanup (9 November 2026)

- Renamed packages, page titles, manifest, cart/storage keys, access gate, OTP email, CI branch
  names (`main`/`dev`), Supabase project ID and site URL to Bicycles.pk. Brand settings in
  `website/content/brand.json` have no address, phone or email yet.
- New bicycle icon and text wordmark. LadyVogue logo PNGs, campaign photos and the logo generator
  script were removed. Storefront theme switched to neutral black/white/grey with amber accents.
- **Shop sections** in `shared/bicycles.ts`: Bicycles, Kids, Sports, E-bikes, Accessories and Parts,
  each with categories and size shortcuts (frame, road-frame or wheel sizes). They replace the
  jewellery and bags departments:
  - POS: one Catalogue section per shop section (category-scoped stock), bike size/colour shortcuts
    in the style editor, and a bicycle CSV import template.
  - Website: menus, footer, sitemap and the `/bicycles`, `/kids`, `/sports`, `/e-bikes`,
    `/accessories` and `/parts` pages are built from the same list. Category links use exact names.
- Removed lingerie (attributes, band/cup sizes, filters, fit guide), jewellery, bags and the 3D
  try-on viewer from both applications. `/fit-guide` is now a bike size guide by rider height and a
  kids wheel-size chart.
- Database unchanged. Lingerie, bra band/cup and try-on columns, functions and the `try-on-models`
  bucket remain unused; omitting `try_on` when saving web details keeps the stored value. They can be
  dropped in a later migration. The website still depends on `three`, now unused.

Validation: 239 POS tests and 59 website tests passed; POS and website TypeScript, ESLint (no
errors; 9 inherited POS warnings) and both production builds passed (builds used local placeholder
Supabase settings). The homepage, `/kids` and `/fit-guide` were checked in a local browser with no
catalogue connected and no horizontal overflow. Database tests were not run (no local Supabase).
Nothing deployed or pushed.

Next: Milestone 1 (bike spec fields), then the landing page, listing and product page designs.
