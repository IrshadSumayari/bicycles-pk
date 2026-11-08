# P20 — Bags & handbags section

Sell women's handbags, purses, clutches and wallets in POS and on the storefront, following the Jewellery module pattern (category-scoped POS section + dedicated storefront landing page). No new database tables or migrations.

## Reference research (7 Nov 2026)

Looked at Charles & Keith (bags listing and product page) and the Coach storefront. Patterns worth adopting, without copying assets or copy:

- **Shop by shape** strip at the top of the bags page: Tote, Shoulder, Crossbody, Top handle, Clutch, Mini, Backpack, Wallets.
- **Filters**: shape, colour, size (XS–XL / Mini–Large), material, price.
- **Product page** leads with name, colour and price, then colour swatches; details are grouped as *Editor's note* (description), *Product details* (dimensions H × W × D, strap drop, closure, compartments, material) and *Shipping & returns*.
- **"What fits"** guidance (phone, wallet, A4 file, 13" laptop) is what shoppers use instead of a size chart.
- Cross-selling: "You may also like" in the same colour/shape.

## Scope

### Shared (`shared/bags.ts`)
- Categories: Bags (general), Tote Bags, Shoulder Bags, Crossbody Bags, Top Handle Bags, Clutches, Mini Bags, Backpacks, Wallets & Purses — each with a slug, short description and size shortcuts.
- Bag sizes Mini / Small / Medium / Large / One size, with typical dimensions and what fits.
- Colour shortcuts (Black, Brown, Tan, Beige, Ivory, Maroon, Blush, Olive).
- Structured bag details (width, height, depth, strap drop, closure, compartments, what fits), stored as labelled lines in the existing `product_guide.fit` text so no migration is needed; parse/format helpers shared by POS and website.

### POS
- New **Bags** section (admin/manager) beside Inventory and Jewellery: All bags, or one bag category; Stock and Import tabs.
- Style editor: bag-aware placeholders and labels (Size, Colour, Style), a **Bag options** builder with size and colour shortcuts.
- Website tab: **Bag details** form (dimensions, strap drop, closure, compartments, what fits) instead of the lingerie fit notes for bag categories.
- Bags import template with example tote/crossbody rows.

### Storefront
- `/bags` landing page: editorial hero, shop-by-shape grid (newest real product photo per category, original SVG illustration fallback), size & "what fits" guide, care guidance.
- Homepage and collections feature block, header menu + mobile strip, footer, sitemap, site metadata.
- Product page for bags: Size / Colour / Style option labels, a **Product details** list (dimensions, strap drop, closure, compartments, what fits, material), "Bag size guide" link instead of the lingerie fit guide, no lingerie size-chart notice.

## Out of scope / later
- Filtering bags by material or dimension on the search page (needs catalogue facets in the database).
- A dedicated bag attributes column; the labelled-lines format can be migrated later.
- Real product photography and inventory.

## Acceptance
- Unit tests for bag categories, details parsing/formatting, navigation permissions, category filter, import template.
- POS + website TypeScript, lint, tests, production builds.
- Browser check of `/bags`, header menu, and the POS Bags section at phone and desktop widths on the local site before any push.
