# Catalog import

Use Node 22. Run this on local Supabase first, then a separate staging project,
and only after owner approval on production. The source JSON stays outside Git.
The source location defaults to `D:/LadyVogue/storefront/src/data`; override it
with `--source`. Install the isolated tools with `npm ci --prefix scripts/catalog-import`.

```powershell
node scripts/catalog-import/import.mjs --url <project-url> --anon-key <public-anon-key> --dry-run
node scripts/catalog-import/import.mjs --url <project-url> --anon-key <public-anon-key> --apply --limit 50
```

Each command prompts for an active admin's email and password. Password input is
hidden in an interactive terminal; credentials and sessions are never saved.
Use the public key, never a service-role or secret key. Dry run signs in and reads
the existing catalog, but makes no changes. Reports are
written below the Git-ignored `backups/catalog-import/` directory. Keep them private.

Read every `problem` row before continuing. The CSV includes style code, source
handle, number of variants, outcome and explanation. `not_selected` means the
batch limit was reached; `would_create` is a dry-run result. Collections with
missing or unmappable members remain unchanged. Rerun without `--limit` only
after reviewing the entire problem list. The limit selects the first N mappable
products; it is not a page offset.

Styles match by source handle/code. New styles have zero stock, no recorded cost,
and remain unpublished. The importer never sends stock, cost or publication keys.
Repeat runs update web details only; they preserve existing variants,
prices and publication choices. Existing collection metadata is preserved.
Complete collection membership is replaced with the source membership; review
that source before applying. Writes use the five permitted catalog RPCs; table access is read-only. RPCs have bounded retries and stable
request IDs per operation. A style-code lookup recovers a create committed before
a timeout, rather than creating another style.

Mapping rules:

- Size, color/colour and fit option names are matched case-insensitively.
  A constant unsupported option is omitted with a warning; a varying unsupported
  option makes the product a problem. Collapsed duplicate variant combinations
  are also problems.
- A product whose product type explicitly identifies fabric is sold by the metre
  only when its sole Length value explicitly says Per Meter/Metre. Packaged lengths,
  mixed lengths and unclear conversions are problems. The importer never guesses
  metre prices from package prices. Other product types map to garment/piece.
- Prices must be present, nonnegative and have at most two decimals. Compare-at
  prices are saved through `save_style`; they do not change the actual sale price.
- A unique source SKU is retained. Missing/duplicated SKUs use handle + options +
  a stable hash. Only nonempty globally unique source barcodes are retained.
- Descriptions are not imported; only clean names and catalog dimensions are mapped.
  Handles up to 120 characters are preserved. Invalid handles, oversized text,
  inconsistent tax flags and missing required data are problems.

Automatic source-photo importing and the image-download implementation have been removed. No source CDN image is fetched or uploaded by the catalog importer. Existing campaign files and stored product photos are preserved; add approved new product photos through the POS image manager. The old --images flag fails before login or writes.

Names are cleaned of the former supplier name, the brand is always the name in `website/content/brand.json` (LadyVogue), and source product/collection descriptions are omitted. New web descriptions are empty so the owner can write original copy. An apply run can clear an existing imported web description; review the dry run first. This branch does not run an apply or update any database.

For every imported product the owner must check its description, category, options,
barcode, actual price, compare-at price and photographs; physically count stock;
record a supported stock receipt with cost; then publish through Inventory → edit
style → Website. Importing is not permission to sell unverified stock. Launch one
reviewed collection first. Check the product, its image and the permanent legacy
collection/product redirect on the website before publishing the rest.

Run `npm test --prefix scripts/catalog-import` for pure mapping tests. See
[WEBSITE_LAUNCH.md](./WEBSITE_LAUNCH.md) for local rehearsal results and launch gates.
