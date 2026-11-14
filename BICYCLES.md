# Bicycles.pk development

Domain: https://bicycles.pk (still serving the coming-soon page from `main`).

POS source is in `src/`, the Next.js website in `website/`, shared rules in `shared/`, and the
database in `supabase/` (one baseline migration plus any later ones). The plan is in
[docs/BICYCLES_PLAN.md](docs/BICYCLES_PLAN.md) and the launch runbook in
[docs/operations/LAUNCH.md](docs/operations/LAUNCH.md).

## Configuration

Use a dedicated Bicycles.pk Supabase project. Local Supabase uses project ID `bicycles` and ports 55330–55339. Search engines index only the live shop: pages are `noindex` and `robots.txt` disallows everything unless `NEXT_PUBLIC_SITE_URL` is `https://bicycles.pk`, so indexing starts with the first production deploy. Install with `npm ci` and
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
- The leftover database objects were removed later in the bikes-only cleanup (below).

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

## Milestone 3: listing pages (9 November 2026)

- Product cards follow the listing reference: photo on a light-grey panel,
  bold name, a sizes/colours line and the price (`components/product-card.tsx`,
  styles in `website/styles/listing.css`).
- `catalog_list` accepts a `categories` array, so `/search?section=<id>` lists
  every category in a section (migration `20261109000100_catalog_section_filter`).
- Search and section pages show category pills. Section pages and Shop all
  have two large split tiles and a carousel per category or section.
- The card subtitle uses sizes and colours because `catalog_list` does not
  return specs yet; returning specs needs a change to its return type.

## Milestone 4: product page (9 November 2026)

- Product page follows the detail reference: large grey gallery with zoom and
  thumbnails, and a sticky panel with breadcrumb, spec subtitle, models,
  price, colour swatches, size buttons, delivery, Add to bag and Share.
- Bikes show up to three related products as "Models" and a "Complete your
  ride" row (newest helmet, lock and light). Quick add puts an add-on straight
  in the bag when it has one in-stock option, otherwise opens it.
- Specifications are grouped (`specGroups` in `shared/bicycles.ts`) and shown
  as expandable sections under the overview. Styles: `website/styles/pdp.css`.

## Milestone 5: fit and delivery (9 November 2026)

- "What's my size?" finder (`shared/fit.ts`, `components/size-finder.tsx`): adult
  size from rider height (frame sizes from inside leg), kids wheel from height
  or age. On the size guide, and as a dialog on the product page that can
  select the matching size.
- Bulky items: `product_styles.bulky` (POS "Bulky item" checkbox, on by
  default for bike sections). Courier delivery adds
  `app_settings.bulky_delivery_fee` per bulky unit, even when delivery is free.
- Assembly: courier orders with bulky items can add `assembly_fee` per unit
  (blank setting = not offered). Recorded as `online_orders.assembly` and shown
  on the POS order, packing slip and customer order. Pickup bikes are
  assembled free.
- Both charges are folded into `delivery_fee`, so order totals still equal
  subtotal + tax + delivery (migration `20261109000200_bike_delivery`).

## Bikes-only cleanup (10 November 2026)

- **Database:** the 56 inherited migrations were replaced by one baseline,
  `supabase/migrations/20261110000000_bicycles_baseline.sql`, generated from the final schema. It has
  no clothing objects: the lingerie, bra band/cup, product guide (garment size chart), size-scheme
  chart and try-on columns, their checks and functions, the `try-on-models` bucket and the workroom
  location are gone. Product kind `garment` is now `item`. The wrapper chains for `save_style`,
  `update_settings`, `quote_online_order` and `create_online_order` were merged into single
  functions. Starting data: store name Bicycles.pk, the main branch with shop floor, stockroom and
  online locations, and Frame, Wheel and One size presets.
- **Listing filters:** `catalog_list` and `catalog_facets` add brand, wheel size, brakes, gears,
  suspension and in-stock filters; search also matches the brand. The listing filter panel shows
  each filter only when the catalogue has values for it.
- **Code:** removed the garment size-chart editor and display, the old storefront catalogue import
  script, the unused `three` and PGlite packages, and the LadyVogue documents and plans. POS labels
  now read *Model year* (stored as `season`), *Frame materials* and *Variants* (stored as `fit`).
- **Tests:** database tests use bike fixtures; `supabase/tests/database/bikes.test.sql` covers specs,
  bulky items, the new filters, the bulky charge, assembly and admin-only fees. The PGlite tests that
  loaded individual migration files were removed with those files.

## Local sample catalogue (10 November 2026)

For local testing only; nothing here is deployed.

```sh
npx supabase db reset      # schema plus supabase/seed.sql
npm run seed:photos        # uploads the sample photos to local storage
npm run web:dev            # website on http://localhost:3000
```

- `supabase/seed.sql`: ten real bike models (Trek FX 2 Disc, Giant Escape 3, Brompton C Line
  Explore, Electra Townie 7D, Specialized Rockhopper Sport 29, Cannondale CAAD Optimo 3, Mongoose
  Legion L20, Strider 12 Sport, Trek Precaliber 16, Aventon Pace 500.3) plus a helmet and a light,
  with specs, sizes, colours, sample prices and stock, one collection per section, and sample
  bulky (PKR 1,500) and assembly (PKR 2,000) fees.
- Photos: free Unsplash photos listed in `scripts/seed-local/photos.json`. They show similar bikes,
  not the exact models; the script refuses any non-local Supabase.
- Homepage video: a free Pexels clip streamed from `videos.pexels.com` (allowed in the website CSP
  in `website/lib/security.ts`). Before launch, put the shop's own video in `website/public/hero/`,
  point `website/content/home.json` at it and remove the Pexels hosts from the CSP.

## Staff account security (14 November 2026)

Fixes for review findings S1 and S2. Migration `20261114000000_staff_account_security.sql`.

- **No automatic administrator.** The first sign-up on an empty database used to become the
  administrator, so a website customer could take the shop if they signed up first. Now every
  sign-up without staff app metadata is a customer. The owner creates the first administrator in
  Supabase (Authentication → Users → Add user), then runs
  `SELECT app_private.bootstrap_admin('email')` in the SQL Editor. It is refused once an active
  administrator exists. The POS login page no longer offers sign-up and shows setup instructions
  instead.
- **Authenticator app for administrators and managers.** `current_app_role()` ignores the admin
  and manager roles unless the session is verified with an authenticator code (JWT `aal` =
  `aal2`), so every role check and row level security policy requires it. Cashiers keep
  password-only sign-in. The POS shows a set-up screen (QR code and key) on first sign-in and a
  code screen after that (`src/components/auth/MfaGate.tsx`). `admin-users` also requires `aal2`.
- **Passwords:** minimum 12 characters in `config.toml`, the user form and `admin-users`.
- **Tests:** database tests bootstrap their admin explicitly and use `aal2` sessions;
  `security.test.sql` checks password-only admin sessions get no rights and cashiers are
  unaffected; `accounts_and_branches.test.sql` checks the first sign-up is a customer.
- **Runbooks:** DEPLOY §2 and §8, LAUNCH, STAGING_REHEARSAL, RELEASE_GUIDE and README describe the
  new setup, the hosted Auth settings (TOTP on, minimum 12) and resetting a lost authenticator.

Not run yet: database tests, unit tests, lint, type-check, builds, or a browser check of the new
screens. Hosted Auth settings must be changed by hand in each Supabase project.
