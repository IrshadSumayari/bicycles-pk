# Lookup management and removal of legacy examples

23 October 2026 · Local project: `D:\LadyVogue\POS`.

## What changed

- The category dropdown reads active database categories and refreshes on opening/focus. Historical initial migrations are retained; the final schema removes unused generic-store templates such as Electronics, Automotive, Food & Beverage and Books & Media. If an old template still has products, its assignment is retained and the template is deactivated instead of deleting products.
- Removed the hard-coded Sri Lankan bank list. Checkout and bank-based discounts now use the same owner-managed list. No invented bank, brand, customer or product records were added.
- Customer tiers, return reasons and stock-adjustment reasons now use saved choices. `Standard` is the required default customer tier and `Other` is the free-text reason fallback; those remain system options.
- Existing catalog brands, materials, seasons, colors and fits are registered from actual product metadata. Newly entered catalog values are registered automatically. This is existing shop data, not a demo seed.
- Unused, unconfirmed original stitching prices, lead times and fabric estimates were cleared and their garment forms deactivated. Exact known seed tuples are targeted only when there is no measurement/order/request history or recorded owner save. Owner-configured values and used forms are preserved. Measurement forms remain available for configuration. Existing alteration forms with no measurements remain editable without inventing measurement fields.
- No product, variant, customer, invoice or stock records were removed. Before/after counts were checked. Local database backups were saved in `D:\POS\output` before changes.

The audit covered POS runtime code, its `website/` storefront, the separate reference storefront, public defaults and local database categories. No other unrelated demo-product injection was found. Historical SQL and automated-test fixtures may still contain example strings; these do not populate the final running application. Sample documentation files are not imported into the business database automatically.

## Managing values

Open **Settings → Lookups** as an administrator or manager. You can add, edit, activate/deactivate and delete unused values for:

- Categories
- Size lists (name, code and ordered sizes)
- Brands, materials, seasons/collections, colors and fits
- Banks and customer tiers
- Return reasons and stock-adjustment reasons

Used values show a record count and cannot be deleted through the app. Deactivate them to remove them from new-choice suggestions, or reassign their records before deleting. Existing products and historical snapshots stay intact. Lookup changes have an append-only audit trail.

Renaming catalog values updates their current catalog references. Size-list edits affect future variant building; existing variant sizes are not rewritten. Bank/tier renames update configured discount conditions, but posted payment and sale snapshots are preserved.

Garment types and their measurement fields remain under **Settings → Tailoring**, with add/edit/activate controls and safe deletion of unused types. **Set actual prices, lead times and fabric estimates before activating a form for new orders.** New forms start inactive with no guessed lead time.

Payment methods, staff roles, transaction/order statuses, stock movement types and stock units control application behavior; these are not arbitrary editable lookups. Clothing size presets and measurement definitions are relevant configuration, not sample inventory.

## Deployment

Applied locally:

- `20261101000000_business_lookups.sql`
- `20261101000100_clear_unconfirmed_tailoring_examples.sql`
- `20261101000200_edit_existing_measurement_free_forms.sql`

Deploy these forward migrations with the matching frontend after staging checks and a backup. No production database or public deployment was changed in this task. Do not reset a production database to obtain the cleanup.

The app tests and rollback-only PostgreSQL checks cover lookup CRUD, in-use safeguards, catalog references, bank promotion changes, historical payments, garment measurement history and staff/customer permissions. Additional tests ensure cleanup preserves owner-confirmed and used stitching settings. Existing SQL tailoring tests now configure their own explicit test-only rates instead of relying on production examples.
