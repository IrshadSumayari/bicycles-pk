# P7-01 Website catalog: database

**Branch:** `feat/web-catalog-db`
**Migration:** `supabase/migrations/20261026000000_web_catalog.sql`
**Test file:** `supabase/tests/database/web_catalog.test.sql`
**Scope:** database, storage config and types only.

## Context
`product_styles` already has `published`, `slug`, `web_title`, `web_description`;
`product_variants.published`; and the view `public_catalog` (migration
`20261020000100_catalog_and_stock_ledger.sql`, around line 609) is the only thing `anon` can read.
It returns a stock **band** (`in_stock` / `low_stock` / `out_of_stock`), never quantities or costs.
This plan adds images, collections and catalog query functions for the website.

## Database
1. **`product_images`**: `id, style_id NOT NULL, variant_color TEXT NULL` (image for one color),
   `storage_path TEXT NOT NULL` (path inside the bucket), `alt TEXT, sort_order INT, created_at`.
   Staff read; writes only via `save_product_images`.
2. **`collections`**: `id, slug UNIQUE (same slug CHECK as styles), name, description,
   hero_image_path, published BOOL, sort_order, starts_at, ends_at`;
   **`collection_styles`**: `(collection_id, style_id) PK, sort_order`.
3. **Storage buckets** (create in the migration with `INSERT INTO storage.buckets ... ON CONFLICT DO NOTHING`):
   - `product-images` **public** (read by anyone), max 5 MB, MIME `image/jpeg, image/png, image/webp`.
   - Storage policies: insert/update/delete only for `has_app_role(ARRAY['admin','manager'])`.
   Also add the bucket to `supabase/config.toml` (`[storage.buckets.product-images]`) for local dev.
4. **Functions for staff** (admin/manager, idempotent where they write):
   - `save_product_images(p_style UUID, p_images jsonb)` replaces the image list (order, alt,
     color) — paths must start with `styles/<style_id>/`.
   - `save_collection(p jsonb)` / `set_collection_styles(p_collection UUID, p_style_ids UUID[])`.
   - `publish_style(p_style UUID, p_published BOOL)`: refuses to publish without slug, web title
     (or name), at least one image, at least one published active variant with price > 0.
     Returns a list of problems instead of raising when `p_dry_run` is true
     (signature `publish_style(p_style, p_published, p_dry_run BOOL DEFAULT false)`), so the UI can show a checklist.
5. **Public functions** (`SECURITY DEFINER`, `STABLE`, granted to `anon` and `authenticated`),
   which read **only** published/active rows and return no cost, supplier, stock quantity or
   internal ids beyond `style_id`/`variant_id`:
   - `catalog_list(p jsonb)` → styles (one row per style: slug, title, min price, max price,
     compare-at, first image path, colors array, sizes array, stock band "any size available"),
     filters `collection` (slug), `category`, `size`, `color`, `price_min`, `price_max`,
     `q` (title ILIKE), `sort` (`new`, `price_asc`, `price_desc`), `limit` (max 48), `offset`,
     plus `total_count`.
   - `catalog_product(p_slug TEXT)` → JSON: style info, images (ordered), variants (size,
     color, fit, price, compare_at, stock band), size chart if a size scheme has one (null otherwise),
     related styles from the same collection (max 8). Unknown or unpublished slug → `NULL`.
   - `catalog_collections()` → published collections inside their date window.
   - `catalog_facets(p_collection TEXT)` → available sizes, colors, price range.
   Keep the `public_catalog` view; you may build the functions on top of it.
6. **Indexes** for slug lookups and collection membership.
7. `anon` must still have **no** direct table privileges. Re-assert at the end of the migration
   with the same pattern used in `20261019000100_security_hardening.sql` (revoke all on all
   public tables from anon) and grant only the new public functions.

## Tests (~20)
- anon: `catalog_list` returns only published+active styles; `catalog_product` for an
  unpublished slug is NULL; no column named like `cost`, `supplier`, `on_hand`, `reserved` in
  any public function result (check JSON keys); anon `SELECT` on `product_styles`,
  `variant_costs`, `stock_balances`, `product_images`, `collections` → permission denied.
- Filters: collection, size, color, price range, search, sorting, paging + `total_count`.
- Stock band changes after a sale (sell the last unit → `out_of_stock`).
- `publish_style` refuses with missing image / slug / price; dry run lists the problems.
- Cashier cannot save images/collections or publish; manager can.
- Storage policy: insert into `storage.objects` for bucket `product-images` as a cashier is refused
  (test via `SET LOCAL ROLE authenticated` insert into `storage.objects`).

## Done when
All guide checks pass; `database.types.ts` regenerated.
