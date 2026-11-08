# LadyVogue shopping improvements

28 October 2026. Based on the owner's seven Pakistani reference stores and inspection of LadyVogue's current implementation. New work starts from latest origin/dev; each phase receives a PR to dev for owner review. Real inventory and customer checkout rehearsal remain deferred. No deployment, copied competitor assets, invented reviews or unapproved business promises are included.

## Phase 1 — Navigation and support access (implement now)

- Replace the flat header with accessible grouped desktop menus and mobile accordions for Bras, Panties, Nightwear, Jewellery, More and Help.
- Use actual published collection links when available. Broad fallbacks use exact existing catalogue categories, not ambiguous name searches. Show bra/panty subcollections only when the backend supplies the matching collection; do not pretend keyword matches are structured padding/wire/fit filters.
- Expose existing contact, FAQ, order tracking, shipping, returns, payment, privacy and terms pages in mobile navigation/footer. Show only configured contact channels.
- Preserve the current mobile bag, gallery, purchase controls and appearance support.
- Acceptance: safe category links without collection data; collection-aware submenus; keyboard open/close/focus behavior; readable phone menu without horizontal overflow; footer links resolve. Run website tests, lint, TypeScript and production build. No database changes.

## Phase 2 — Lingerie catalogue attributes and filters

- Add consistently defined POS attributes for product type, padding, wire/support, coverage and material composition, retaining existing size/color variants and stock ledger.
- Agree category and attribute semantics before migration. Provide old-record defaults and generated types, server-side exact filtering and anonymous catalogue privacy tests.
- Add separate band/cup discovery controls and supplier sizing-system labels without automatically equating DD and E or guessing measurements.
- Acceptance: product entry and website filters agree, no false padded/non-padded or wired/wireless matches, old products remain editable, stock identity unchanged.

## Phase 3 — Fit confidence and product information

- Add original measuring illustrations and clearer band/bust/waist/hip steps.
- Improve the existing product-specific chart display and POS chart entry, unit labels, included pieces, fit and care information.
- Any calculator must use a clearly identified supplier/chart system. No universal conversion or unsupported fit guarantee.
- Acceptance: mobile-readable chart, accessible units and guidance, and honest behavior when measurements are unavailable. Product data can be added later.

## Phase 4 — Purchase reassurance and online returns

- Place concise delivery/COD/policy information beside purchase controls using approved settings and wording.
- Replace store-visit-only help with an online support path. Define hygiene eligibility, evidence, request window, return postage and refund handling with owner approval before publication.
- Add a customer claim workflow with private evidence storage, ownership checks and staff review; keep customer exchanges separate from the existing courier-returned COD parcel flow.
- Packaging, dispatch dates and delivery promises require operational confirmation. No automatic approval or invented promises.

## Phase 5 — Merchandising and retention

- Add wishlist, matching-set suggestions and quick view where mobile usability benefits.
- Present true multipacks and curated collections without changing stock accounting. Distinguish curated picks from sales-derived best sellers.
- Add verified-purchase reviews only after real orders exist. No fabricated ratings, sales counters or urgency.
- Newsletter and abandoned-bag messaging need consent and configured email delivery; they are later work.

## Phase 6 — Checkout and hosted acceptance

- Evaluate guest COD checkout separately: customer privacy, order ownership, abuse limits and retry protection must remain enforced.
- Complete the deferred customer order/fulfilment/return rehearsal when the owner resumes it.
- Verify staging schema/app compatibility, configured email, deployment credentials, domain/security and approved policies before production release. Merge/deployment remain owner-controlled.

## Current status

Phases 1–3 merged in PRs #17–19. Phase 4 merged in PR #20. The owner chose staff review for every request, without automatic eligibility or refund promises. Phases 5–6 remain pending; final policy details, real product data and hosted acceptance remain dependencies.


Phase 1 verification: 47 website tests passed; TypeScript, changed-file ESLint and the production webpack build passed. Browser checks used the production preview: desktop keyboard Enter/Escape with focus retained, outside-click dismissal, mobile single-open accordion behavior, Escape closing with focus restored, contact navigation closing the drawer, return-policy link resolution, and light/dark appearance. No page overflow was observed at the available narrow (358 CSS px) and desktop viewport sizes. Specialist collection mapping was covered by automated tests because staging currently supplies no specialist collections. No product, stock, order or database settings were changed.


Phase 2 verification: 209 POS tests, 49 website tests and 897 database assertions passed. Both app TypeScript checks, changed-file ESLint and production builds passed. Local browser checks covered exact combined metadata filters, DD/E distinction, same-variant band/cup matching, sorting/search preservation, confirmed product details, and the isolated POS metadata panel. Website filter layout was checked at 360 CSS px without horizontal overflow; POS panel entry was checked separately at the available narrow preview width. The migration was applied only to the local development database. Disposable local fixtures were unpublished after verification. Hosted staging and production were unchanged. See ../operations/LINGERIE_CATALOGUE.md for rollout and field semantics.


Phase 3 verification: 212 POS tests, 54 website tests and 919 local database assertions passed. Both production builds, TypeScript and changed-file lint passed. Added four original measuring illustrations, product-specific supplier chart entry, explicit units/body-or-garment basis, included pieces, fit and care notes. Browser checks covered narrow and desktop guide layouts, contained phone chart scrolling, keyboard close/focus return, unknown chart data and POS validation. Disposable local fixtures and preview files were removed. Hosted staging/production were unchanged. See ../operations/PRODUCT_FIT_GUIDANCE.md for field semantics, test details and rollout dependencies.

Phase 4: customer item/quantity return requests, optional private photos, a branch-scoped admin/manager review queue, customer follow-up and separate internal notes. Purchase controls now show conditional COD, coverage and review/support links. Both builds passed; 216 POS tests, 54 website tests and 993 local database assertions passed. Mobile customer/staff flows and Storage API privacy were verified with disposable local fixtures. See ../operations/ONLINE_RETURN_REQUESTS.md for operating rules and rollout dependencies.

Additional owner-requested feature: authenticated order-number lookup, customer progress/copy/refresh, PostEx and Leopards official tracking links, POS tracking/CN search and branch-scoped staff shipment updates. Automatic courier updates remain dependent on the selected courier and API access. See ../operations/ORDER_TRACKING.md for rollout and verification.
