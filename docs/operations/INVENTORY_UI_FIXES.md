# Inventory editor and small-screen fixes

Local changes, 23 October 2026. No hosted deployment or production database change.

## Bulk price and cost

The inspected button already mapped the amount onto row state; the screenshot's exact failure was not reproduced in a browser. The editor now validates bulk amounts, explicitly labels each control, confirms the number of changed rows and explains that Save changes is required. Empty, negative and non-finite amounts report an error instead of silently doing nothing. Zero remains valid. Late style-load responses cannot overwrite a newly opened editor. Defaults load from the first existing variant.

Regression coverage applies 3490 to variants previously priced at 13499, updates costs independently and preserves IDs, barcodes and stock data. A rollback database test confirms the full bulk save persists every price/cost without stock movements. Apply to all edits the draft; Save changes commits it.

## Responsive controls

The filter row previously combined a minimum-width search field and non-shrinking selects. It now uses a one-, two- or four-column grid with shrinking fields. Inventory tabs/actions wrap. Price/cost controls wrap within the editor. Variant tables retain horizontal scrolling.

## Measured bars

The shared StatCard used a fixed 40% fallback. Its default is now zero; measured values are clamped and animate when updated, with reduced-motion support. Inventory cards calculate:

- Matching products: rows loaded on this page / total matches.
- Low stock: positive-stock items at or below their minimum / tracked items on this page.
- Inventory value: bar shows tracked items with available stock and a recorded cost / tracked items on this page. The amount remains the actual stock cost value, not a fabricated target.
- Out of stock: items with zero or negative availability / tracked items on this page.

Each measured bar has a tooltip and accessible name explaining its denominator. Empty stores show zero. Services are excluded from stock valuation and stock-status ratios. Existing product invalidation refreshes these values after saves, receipts, sales and adjustments. Other cards without a defined denominator remain zero rather than inventing targets. User/discount totals no longer show full bars when empty.

## Categories

POS chips and the editor both use the active managed category query. The local database was checked: Electronics, Food & Beverage and General are absent. The shared query now refreshes every 30 seconds while observed and on focus, and a deleted/deactivated selected POS category falls back to All. A separate hosted database requires the existing cleanup migrations and matching frontend release; refreshing a browser cannot migrate another database.

## Verification

- 223 frontend tests passed, including 26 new pricing, inventory-ratio and rendered-bar checks.
- 17 style-editor database checks passed inside a rolled-back transaction.
- TypeScript and production Vite build passed.
- Browser control failed to initialize (missing kernel asset path), so visual verification at narrow viewport widths remains outstanding.
