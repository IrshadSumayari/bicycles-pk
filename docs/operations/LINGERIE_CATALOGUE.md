# Lingerie catalogue attributes

Phase 2 adds optional supplier-confirmed metadata. Unspecified values remain unknown; existing products are not automatically classified.

## POS entry

For garments, enter product type, padding, wire/support, coverage, material composition and supplier sizing system. The existing material field remains the exact material filter; composition is descriptive text, not a fibre parser. Jewellery and services retain their existing forms.

Bras and Lingerie Sets show optional supplier band/cup fields per variant. Enter both labels or leave both blank. A sizing system is required when any band/cup pair is present. Use uppercase cup labels, and two or three digits for a band. These are literal supplier labels, not measurements or a conversion calculator. DD and E remain distinct. Existing size, SKU and stock identities remain authoritative; no band/cup is inferred from an old size string.

## Website behavior

Filters combine exact metadata values with existing catalogue criteria. Band, cup, color, size and price must match the same published variant. Available options come from published catalogue facets, scoped to the collection when supplied; category selection does not separately scope facets. Products without an attribute do not match that attribute filter. Search, sorting, pagination and removable chips preserve the remaining criteria.

The product page displays only supplied approved metadata. Anonymous contracts expose no costs or exact stock quantities. The JSON allowlist rejects arbitrary keys. Draft products and hidden variants do not contribute options.

## Compatibility and rollout

Apply migration 20261102000200_lingerie_attributes.sql to the intended environment before deploying the POS. It adds default-empty style JSON and nullable variant fields, wraps the existing stock-safe save, and extends the existing public catalogue RPCs without changing their signatures. Older saves that omit the new keys preserve stored metadata. Explicit empty pairs clear labels. Invalid metadata rolls back the entire save, including opening stock.

The original save implementation is retained as save_style_base and is inaccessible to anon/authenticated callers. The new wrapper checks admin/manager access first. New website filters require lingerie_filters_version=1; selected unsupported filters show catalogue unavailable rather than silently returning unfiltered results. Ordinary browsing remains compatible with the previous public catalogue contract.

Only the isolated local database has been migrated and exercised in this phase. Hosted staging migration, schema-cache refresh, authenticated staff editing and release rehearsal remain deployment work. No production deployment or real inventory import is included.

## Validation

209 POS tests, 49 website tests, 897 transactional database assertions, both TypeScript checks, changed-file lint and production builds passed. New checks cover old-client preservation, stock identity, validation rollback, exact combined filters, DD/E distinction and public-field privacy. Browser verification used disposable local-only products, not hosted catalogue data, and a pure POS panel preview without hosted saves. No customer order or payment was placed.
