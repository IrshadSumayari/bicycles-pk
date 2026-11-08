# Jewellery catalogue

The Jewellery section is available to administrators and managers beside Inventory. It opens on All jewellery, which lists stock in every jewellery category. Select Jewellery (general), Earrings, Necklaces, Rings, Bracelets, Bangles, Anklets or Jewellery Sets to view one category. The ordinary Inventory view continues to include all products.

## Product entry

1. Choose a category in Jewellery, then Add style. The category is prefilled for new items.
2. Use Ready-made item for a single sellable item, pair or complete set. Describe what is included in the product name/description. Count a pair/set sold together as one stock unit; this does not create component-level bundle inventory.
3. Enter the actual material and supplier product details. A finish such as Gold tone is an appearance label, not a purity claim.
4. Use the size/length and finish shortcuts or enter custom supplier labels. Ring presets explicitly say US; there is no automatic conversion between size systems. Bangles and other supplier-specific sizes can be entered manually.
5. Add variant rows. Each size/finish/design combination has its own SKU, barcode, price, cost and stock. Repeated selections do not create duplicate combinations. Opening stock is for new rows; use Adjust stock for existing rows.
6. Publish through the existing Website tab with real product photographs and accurate details.

The Jewellery Import tab downloads earrings/ring examples using the existing CSV format and import validation. The example rows are not real inventory; replace their names, materials, prices and quantities before importing. Shared receiving and stock-count operations remain in Inventory.

## Website

The /jewellery page is linked from the main menu, mobile category strip, footer, homepage and collections page. It has original SVG category illustrations, not product photography. Category cards use exact category filters (for example /search?category=Rings); jewellery products must be saved under those category names to appear. Searching from a category keeps that category filter. More jewellery links to the general Jewellery category; it does not aggregate the other categories.

Jewellery product options use Size / length, Finish and Design labels. Cart/order processing still uses variant IDs, and stock is shared with POS through the existing catalogue and order workflows. No separate stock pool, new database tables or migration is required by this feature. Internally it reuses the ready-made item kind and the size/color/fit variant fields. The database's existing save_style transaction creates a category when the first product in it is saved.

## Validation

Automated checks cover jewellery recognition, category filter URLs, explicit size labels, duplicate-safe ring variants, CSV examples and navigation permissions. Browser checks cover mobile/tablet/desktop jewellery discovery, category-preserving searches and the isolated POS option builder. No live database records were created, edited or published during development; live saving and fulfilment need testing against the owner's configured LadyVogue environment before launch.

### Connected staging rehearsal — 27 October 2026

The subsequent authenticated POS rehearsal created a labelled test ring, uploaded its test image, published it, checked its storefront category/product and mobile bag totals (2 × PKR 100 = PKR 200), then cleared the bag and unpublished it. The listing disappeared after the catalogue cache refreshed; refreshed product availability blocked further adding. The staging test style remains unpublished with its opening stock of two. No order or payment was created in that roundtrip. See `LADYVOGUE.md` for the pending customer checkout and cancellation rehearsal.

The next-step local validation passed 177 database checks for orders, safeguards, concurrency, COD switching and returns, plus 14 website/POS unit checks. Hosted customer checkout and fulfilment are still pending a customer sign-in and their own rehearsal.
