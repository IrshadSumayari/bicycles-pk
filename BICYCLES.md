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

## Milestone 1: bike specifications (9 November 2026)

- `specFields` in `shared/bicycles.ts`: frame, fork, wheel size, tyres, gears, drivetrain, brakes,
  suspension, weight, max rider weight, rider height, age, motor, battery, range, folded size,
  warranty. Free text, max 120 characters each; only filled values show.
- Migration `20261109000000_bike_specs.sql` adds `product_styles.specs` (checked keys and lengths),
  wraps `save_style` (an omitted `specs` keeps the stored value; blanks are removed) and returns
  `specs` from `catalog_product`.
- POS style editor: a Specifications panel shows the fields relevant to the category's section
  first, with "More specifications" for the rest.
- Website product page: an "At a glance" list above the description.

## Milestone 2: landing page (9 November 2026)

- Full-bleed homepage hero with the header laid over it (transparent, white text), a very large
  two-line headline, subline, white pill button and a three-item USP strip along the bottom.
- Hero text, image/video, USPs, announcement and header button are edited in
  `website/content/home.json`. Set `hero.video` (and `poster`) to use a video; otherwise
  `hero.image` is shown. The current image is an original placeholder illustration
  (`website/public/hero/dusk-ride.svg`) until real photography is supplied.
- Dismissible announcement bar (remembered per announcement text in that browser) and a
  "Book a test ride" pill in the header on wide screens.
- Below the hero: shop-by-section tiles, a new-arrivals carousel, a kids feature with a kids
  carousel, and a dark "assembled and checked" service band.
