# LadyVogue development

Domain: https://ladyvogue.pk

This independent copy starts from clothing-pos develop at f704b07. POS source is in src/; the Next.js website is in website/; shared database migrations are in supabase/. Work on codex/ladyvogue.

## Configuration

Use a dedicated LadyVogue Supabase project for both applications. No private environment files, customer data, database backups or deployment secrets were copied. Local Supabase uses project ID ladyvogue and ports 55320–55329 to avoid the original project's ports. Keep localhost as NEXT_PUBLIC_SITE_URL during local testing; use https://ladyvogue.pk for production.

Install independently with npm ci and npm --prefix website ci. Run npm run dev for POS and npm run web:dev for the website. Both require their own environment files based on the provided examples. Never reuse another brand's production database or deployment secrets.

## First development pass

- Separate repository and package identities.
- LadyVogue POS identity, website wordmark and metadata.
- Cleared inherited shop address and contact configuration.
- Search indexing disabled during development.

## Next implementation milestones

1. Replace inherited menswear campaigns, pages, navigation and imagery with the LadyVogue storefront design.
2. Add lingerie size conventions, band/cup variants, multipacks and category-specific product entry.
3. Verify existing online-order, COD, return and exchange workflows against lingerie stock requirements.
4. Configure the dedicated database, real inventory, shipping and approved policies.
5. Test both applications before enabling production indexing and deploying ladyvogue.pk.

The initial identity pass is not a completed storefront redesign. Historical migrations and documentation retain their original context.

## Premium storefront design

References requested by the owner: https://www.victoriassecret.com/ and https://www.hunkemoller.com/. These are references for editorial commerce, category hierarchy, and fit guidance; their assets and copy are not used. Hunkemoller navigation was inspected; Victoria's Secret initially returned a loading page.

Implemented: responsive editorial homepage, original LadyVogue wordmark, category navigation with safe search fallbacks, warm ivory/plum theme with dark appearance support, fit guide, brand story, and redesigned footer. Product cards use real catalog data only. The dedicated Supabase catalog is not configured yet, so no purchase-ready inventory is shown. Inherited policy and tailoring routes still require a business/content review before launch.

### Campaign assets

Generated with the built-in image tool, saved as optimized WebP in website/public/ladyvogue/. These are illustrative campaign images, not product photographs or inventory.

- campaign.webp — Premium fashion still life: dusty rose satin pajamas on an ivory chair, mauve lace bra and briefs on cream linen, warm window light, burgundy curtain; no people, text or logos.
- nightwear.webp — Portrait editorial photograph of ivory satin pajama shirt and trousers on a wooden hanger against warm plaster with gentle window shadows; no people, text or logos.
- essentials.webp — Portrait overhead still life of rose, ivory and plum briefs on cream linen, lace detail and natural light; no people, text or logos.

## Step 1: shopping UI completed

Implemented the premium collections directory, searchable catalog and active filter chips, product options and fit links, shopping bag, checkout form, and customer sign-in/account navigation. Catalog outages and missing authentication configuration now have safe, readable states.

Validation: 48 website tests passed, including five tests for protected routes when configuration is missing. Desktop and mobile browser checks used an isolated read-only mock catalog to verify filtering, variant selection, quantity, bag totals, and delivery form layout. No emails or orders were submitted. Temporary test routes and mock data were removed afterward. Real authentication, payment, inventory and order integration remain pending the dedicated LadyVogue backend.

Next step: adapt POS product entry for lingerie sizes, colors and categories, then validate inventory/order workflows. Deployment remains pending full development, configuration and launch checks.

Production validation: Next.js webpack build and TypeScript passed after clearing stale generated preview types. No preview route is included in the production route list.

## Step 2: POS product entry

Added category suggestions for Bras, Panties, Nightwear, Lingerie Sets, Shapewear, Camisoles and Robes. The style editor offers band/cup combinations and letter-size shortcuts, with removable selections and custom supplier labels. Sizes remain in the existing variant size field, so stock, barcodes, receipts and website options retain their current contract. The shortcuts do not create database size schemes or a measurement chart; DD and E remain distinct supplier labels.

Variant generation now removes duplicate input choices, skips existing combinations and disambiguates generated SKU collisions. Save validation checks duplicate combinations/SKUs/barcodes, invalid costs and non-finite opening stock. Existing stock is still adjusted through the audited stock workflow. The downloadable CSV template now demonstrates bras, panties and nightwear.

Validation: 229 POS tests across 30 files passed; TypeScript and Vite build passed. The full suite and build required temporary localhost Supabase placeholders because existing modules require backend configuration at import/build time. These values were process-local, not saved to environment files. The resulting build is for validation only, not deployment. The new component was checked in a local browser with repeated band/cup selection; preview files were removed. No product or stock records were written. Database-backed saving, sales, returns and website synchronization still need integration testing with the dedicated LadyVogue backend. Multipack inventory semantics remain a separate follow-up.

Next step: order, stock and return/exchange workflow validation, plus removal/review of inherited tailoring content before launch. Nothing deployed.

## Step 3: order, stock and return workflow safeguards

Reviewed online-order transitions, reservation release, packing, COD collection and the existing SQL return/exchange tests. Fixed three client-side gaps:

- Return condition starts unselected. Staff must inspect each selected item and explicitly choose resaleable, damaged or faulty; the UI explains that only resaleable items return to sellable stock. This is an inspection workflow, not a newly defined customer eligibility or hygiene policy.
- Exchanges require valid positive replacement quantities and a completed successful quote. Pending or failed pricing no longer displays a misleading refund/even-exchange amount. Invalid, excessive and fractional piece-return quantities are blocked. Quote errors from exchange mode do not block a separate refund.
- Successful online cancellation invalidates cached POS product availability after the server releases reservations.

Validation: 236 POS tests passed across 30 files, TypeScript passed, changed-file ESLint passed, and Vite build passed using process-local localhost Supabase placeholders. No live orders, payments, inventory or database schema were changed.

Integration status: Docker's Linux engine is unavailable, so the pgTAP database suites were inspected but not executed. Their existing coverage includes reservation versus physical stock, cancellation release, packing retries, COD retries, damaged returns without restock, refund limits and exchanges. Step 3 database acceptance remains pending a running dedicated local LadyVogue Supabase instance. The final customer return/exchange policy and multipack handling are also still pending; this milestone is not deployment approval.

## Step 4: tailoring and fabric removed

Removed the inherited tailoring service and fabric-by-length selling from both applications. Jewellery and any custom-order service will be added separately.

- Website: removed the stitching request form, account requests pages, made-to-measure page and footer link, and fabric cut options. The bag now holds whole pieces only (1–10) under a new storage version, so older bags are discarded. Content pages no longer mention tailoring, fabric or measurements for tailoring.
- POS: removed the Tailoring and My work screens, the tailor role, tailoring and fabric reports, tailoring settings and garment types, the dashboard tailoring overview, the open tailoring order import, fabric rolls, cuts and length entry. Product kinds are now ready-made item, pack or multipack, and service.
- Database: unchanged. Tailoring and fabric tables and functions remain unused so they can be repurposed (for example, custom jewellery orders) or removed in a later migration. The admin-users function no longer accepts the tailor role.

Validation: 203 POS tests, 43 website tests, 1,130 database tests (37 files on a local LadyVogue Supabase), TypeScript, ESLint (no new warnings) and both production builds passed. The product page and bag were checked in a browser against a temporary local product; the local database was then discarded. Nothing deployed.

## Mobile review workflow and filter polish

Continue new changes on feature branches based on the latest origin/dev. Open a PR targeting dev for each completed change set; the owner reviews and merges. Database setup and integration testing are deferred until the end at the owner's request.

Mobile catalog filters now open in a bottom sheet with scroll containment, safe-area padding and 48px form controls. Opening focuses the heading to avoid immediately raising the phone keyboard; closing restores focus to Filter. Desktop retains the sidebar, with only one filter form mounted at a time. Bag headings reserve space for Close, and account navigation can scroll horizontally on narrow screens.

Browser checks: 320px and 390px phone layouts, filter open/close and focus restoration, minimum-price form submission, empty bag layout, and 1280px desktop sidebar. Product inventory was unavailable, so this validates layout and filter query submission rather than live catalog results. No backend changes or deployment.
Validation for this mobile change: 43 website tests, component ESLint, TypeScript and the production webpack build passed.

## Mobile product-page review

Product images now have previous/next controls and an image counter. Phone thumbnails use a horizontal strip, size choices and product details are easier to read, and a fixed mobile purchase bar shows the selected size/colour, unit price and quantity. Both purchase buttons share the same availability and quantity checks; the bar stays below dialogs and reserves space at the bottom of the page.

Browser validation used an isolated read-only sample catalog with illustrative campaign images, not real inventory. Checked gallery navigation, size 36B and quantity 2 updates, opening the bag from the mobile bar, clearing that sample bag, 320px/390px layouts without page overflow, and hiding the bar at 1280px. The temporary sample server was stopped and removed. Real payments and order integration remain deferred with database setup.
Validation completed: 43 website tests, product component ESLint, TypeScript and production webpack build passed.

## Mobile shopping bag and checkout review

Bag items now show a separate quoted item total alongside the unit price, with quantity/removal controls arranged for phone widths. Checkout shows size, colour, quantity and item totals. A mobile-only expandable summary lets shoppers review their order before entering contact details. Delivery fields have shipping autofill attributes and length limits matching existing validation. Payment choices have larger radio controls and a visible selected state.

Validation: 43 website tests and ESLint for both changed components passed. Browser checks used an isolated read-only sample catalog/quote server: quantity 1 to 2 changed the item total from PKR 2,500 to PKR 5,000; courier delivery added PKR 250; checkout review showed 36B/Rose and quantity 2. Checked 320px/390px phone layouts without horizontal page overflow and hid the mobile summary at 1280px. No order was submitted. Sample bag cleared, temporary development-only checkout route and quote server removed. Live authentication/payment/order testing and database setup remain deferred.
Production validation: TypeScript and webpack build passed after removing the sample route.

## Mobile account and order screens

Order history now uses responsive cards with order/payment status, total and a clear details link. Empty order history has a collection link. Order details use item cards instead of a wide table, with separate total, delivery and update panels. COD payment status is shown as due. Profile preferences have larger controls and name/phone autofill. Sign-in has a more compact mobile image, readable fields, a numeric verification-code style and a full-width change-email button.

Browser checks used temporary development-only sample views for order history, order details, empty history and profile, plus the actual unconfigured sign-in page. Checked 320px/390px without horizontal overflow and two-column order cards at 1280px. No emails, profile/consent changes, account links, cancellations or payments were submitted. Sample views were removed before the production build. Live account/order integration remains deferred with database setup.
Validation completed: 43 website tests, changed-file ESLint, TypeScript and production webpack build passed. The production route list contains no sample preview route.

## Jewellery module

Added a manager/admin Jewellery POS section with category-scoped stock, category-prefilled product entry, size/length and finish shortcuts, and a dedicated import template. It reuses existing variant IDs and stock/order workflows; no new database schema or live database changes were needed for this code change. Website jewellery discovery is linked from the menu, mobile strip, footer, homepage and collections, with category filtering, original SVG illustrations and jewellery-aware product labels. See docs/operations/JEWELLERY.md for entry conventions and category behavior.

Validation so far: 205 POS tests and 43 website tests passed; POS TypeScript, changed POS lint and POS Vite build passed. Phone/tablet/desktop browser checks confirmed jewellery discovery and category-preserving searches; an isolated option-builder review produced four ring size/finish variants without duplicates. Temporary preview files were removed. The owner's database setup was acknowledged but not modified or used for live saves during this feature; database integration remains to be verified in that configured environment.
Final website validation: changed-file ESLint, TypeScript and the production webpack build passed, including /jewellery. No preview files are included.

## Staging publishing acceptance — 27 October 2026

Both local applications are configured to the dedicated LadyVogue staging backend through ignored environment files. An authenticated POS administrator completed the jewellery publishing roundtrip:

- Created the clearly labelled `LV-TEST-PUBLISH-20261027` ring, with Adjustable size, Silver tone finish, PKR 100 unit price and two opening stock units.
- Uploaded an original generated test graphic with explicit NOT FOR SALE text and descriptive alt text.
- Published through the POS Website tab and verified the Rings listing and product page in the storefront.
- Verified the mobile bag quote for quantity two: PKR 200 subtotal and total, with PKR 0 quoted tax and delivery for that bag quote. This does not establish final delivery charges or tax policy.
- Cleared the bag, unpublished through POS, verified that the open product page disabled Add to bag after refreshing availability, and confirmed removal from the category listing after its 60-second catalogue cache refreshed.

The test style and its two opening stock units remain in staging, unpublished. No order, payment, shipment or production deployment was made in this publishing rehearsal. Public application settings are ignored; no credentials are included in this record.

## Next acceptance step — customer checkout and POS orders

Branch workflow remains feature branches from current `origin/dev`, with PRs targeting `dev` for owner review and merge. Database integration is now underway; earlier notes deferring it describe the previous development stage.

Completed on 27 October 2026:

- Five transactional suites against the isolated local LadyVogue database passed: online orders, order safeguards, concurrency, COD-only payment switching and returns (177 checks).
- POS online-order action tests passed (3 checks).
- Website checkout validation and bag tests passed (11 checks).

These automated checks are local results, not proof of hosted checkout or fulfilment. The staging website correctly redirects an unauthenticated checkout to customer sign-in. The POS Admin session does not provide a website customer session.

Pending staging rehearsal, requiring a separate customer/test email sign-in:

1. Temporarily publish the labelled test ring; use test-only contact details and pickup to avoid a real courier booking.
2. Place one COD test order, record its order number, and verify the customer confirmation and POS Online orders entry agree.
3. Check the reservation reduces available stock without changing physical on-hand stock; confirm the order in POS.
4. Cancel before packing with an explicit test reason, and verify reservation release and restored availability. Do not record a cash collection for this cancellation scenario.
5. Confirm customer order status, empty the test bag, and leave the test style unpublished.

Packing, pickup/delivery, cash reconciliation, returns/exchanges, real shipping configuration, approved product/policy content and hosted launch checks remain separate acceptance gates. No deployment is approved by this record.

## Store setup and returned COD parcels

Added POS delivery/COD controls, a blank product-import download separate from examples, and confirmed website contact/location/nationwide-delivery copy. Added an audited manager-only receive-parcel action for shipped, unpaid COD returns: explicit item condition, sellable-only restock, sale-value reversal with no invented cash refund, recorded courier costs and duplicate/retry protection. Paid/partial parcel returns and courier remittance remain separate workflows.

Validation and operating instructions: [Store setup and parcel returns](docs/operations/STORE_SETUP_AND_PARCEL_RETURNS.md). Passed 207 POS tests, 43 website tests, 866 local database checks and both production builds. Migration applied only locally. Customer checkout testing remains deferred; real catalogue/photo input and a confirmed courier quote are still needed. No hosted settings changed and nothing deployed.

## 360° model viewer

Shoppers see products on AI-generated (or photographed) models from several angles, like the reference stores the owner shared. The model photos themselves are produced outside the site with an AI fashion-photo tool; the site shows them.

- **Model skin tones**: angle photos are stored per model skin tone (Fair, Wheatish, Dusky, Deep), then per colour. The tone list is fixed in shared/tryOn.ts and in app_private.valid_try_on, so a shopper's choice means the same on every product. Shoppers cannot upload their own face or photo; that was ruled out for privacy.
- **Product cards** slowly fade to the next angle photo (about 1.4 s each, at most 8 angles) while hovered, with position dots, and fade back to the main photo afterwards. Angle photos load only on the first hover; touch and reduced-motion users keep the main photo. Without an angle set, a card fades through up to four of the style's photos; with one photo, it does not change.
- **Product page**: a "360° model" view appears only when the style has angle photos or a 3D model. A set of 16 or more photos plays as a slow turntable (180 ms per frame with a short crossfade); fewer photos fade more slowly. Shoppers drag, or use the rotate buttons or arrow keys, to turn the model. When a colour has photos of more than one model, labelled skin-tone buttons let the shopper pick one. The choice is remembered on that device (localStorage `lv-model-tone`, optional if storage is blocked) and used on every product; a colour without that model falls back to the first available tone. Tapping a colour swatch selects that colour; a colour without photos shows a short notice. A .glb 3D model, when uploaded, is recoloured per colour instead. There is no drawn mannequin.
- **POS** (Website details → 360° model): for each colour, upload 4–72 angle photos per model skin tone, named in turning order (front, ¾, side, back, other side…). Optionally upload a .glb model, garment material names and a shade per colour.

Data lives in product_styles.try_on (`models: {tone: {colour: [paths]}}`), validated by app_private.valid_try_on (listed tones only; files must belong to the same style). catalog_product returns it. catalog_list returns angle_paths for cards, via app_private.catalog_angle_paths: the set that contains the card's main photo, else the set for the main photo's colour on the first tone that has it, else the first set, else up to four photos, using only colours sold online. 3D files use the public try-on-models bucket (.glb only, 25 MB); angle photos use product-images. three.js loads only when a 3D model is opened.

Validation: all 37 pgTAP files passed (1,056 tests) on a fresh local reset, including try_on_viewer.test.sql (tones, card angle choice). The pgTAP suite expects an empty database, so it fails if local sample data is loaded first. public_surface.test.sql allows the try-on-models bucket explicitly. 54 website tests and 219 POS tests passed, plus POS and website TypeScript and lint; the PGlite-based commissions test could not allocate memory on the busy test machine. With local-only sample styles and a local test admin:
- Uploads and saves went through the real permissions; another style's file and a non-.glb upload were refused.
- Rose had Fair and Wheatish models: the tone buttons switched between them, the choice survived a reload, and Ivory (Fair only) fell back to Fair without buttons. Black showed the notice.
- The product card turned the model shown in its main photo.
- The POS editor listed each colour's four tones with photo counts and per-model Remove buttons.

The sample turns came from Mixkit Free License clips 52000 and 52001 (real models, not AI). The Fair sample wears beige, so it is a stand-in for the Rose test only.

## Bags & handbags

Added a Bags section to POS and a `/bags` storefront page, following the Jewellery pattern: nine bag categories (shared/bags.ts), size/colour shortcuts, a structured Bag details form in the Website tab, a bags import template, and bag-aware product pages (Size/Colour/Style, dimensions, strap drop, closure, what fits). UI direction came from the Charles & Keith bags listing and product pages (shop-by-shape strip, colour/size/material focus, measured details); no assets or copy were used. No migration: bag details live as labelled lines in product_guide.fit. See [Bags](docs/operations/BAGS.md) and [the plan](docs/plans/P20-handbags.md).

Validation: 244 POS and 63 website tests, POS and website TypeScript, changed-file ESLint and both production builds passed. Local browser check of /bags at 375px and desktop (no horizontal overflow, no console errors), homepage feature and header menu links. No bag products exist yet, so the "New in bags" row, category photos and the bag product page were verified only through unit tests; the POS Bags screens were not opened in a signed-in session. Nothing deployed or written to any database.
