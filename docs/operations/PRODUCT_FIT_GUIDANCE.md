# Product fit guidance (Phase 3)

## Product entry

In the POS, open a saved style's Website tab. Included pieces, fit notes and care instructions are optional public text (up to 2,000 characters each). Enter only confirmed product information.

Enable a product-specific supplier chart only when one is available. Explicitly choose centimetres or inches and whether its values describe the body or garment. Supply the supplier/chart reference and 1–30 unique size rows. Each row needs a size and at least one of underbust, bust, waist or hips. Copy ranges as supplied; cells accept literal text up to 60 characters. No measurement or size conversion occurs. The editor does not preselect a unit or measurement basis.

Saving Website details uses the existing idempotent editorial transaction. It does not create variants, adjust stock, change prices or edit shared size schemes. Disabling the product-specific chart removes the override; an existing size-scheme chart remains the fallback. If no chart exists, the website offers a sizing enquiry instead of inventing values.

## Customer experience

The fit guide has four original SVG measuring illustrations with descriptive accessible names, preparation steps and guidance on supplier systems. It collects no body measurements. Underbust measurements are explicitly distinguished from bra band labels.

Product charts identify their source, unit and body/garment basis. Missing cells say Not supplied. Wider tables scroll within a labelled keyboard-focusable region inside a centered bounded dialog. Escape and Close restore focus to the chart trigger. Supplied included pieces, fit and care text appear in the product information accordions. Legacy chart content remains supported with explicit guidance that missing units must not be assumed. No fit guarantee or universal conversion is offered.

## Schema and release

Apply pending migrations through 20261102000300_product_fit_guidance.sql before deploying the updated POS. product_styles.product_guide defaults to an empty object. A validator in the unexposed app_private schema enforces allowed fields, types and limits both for editorial saves and table writes. The public RPC allowlist is unchanged.

save_style_web_details retains its signature, permission checks, locking and request ownership/retry semantics. Older clients omitting product_guide preserve it. Explicit {} clears it. Invalid guide data rolls back the complete editorial update. catalog_product adds approved guidance only for publicly visible products; costs and exact stock remain private.

Only local development was migrated here. Hosted migration and an authenticated staff save rehearsal are release dependencies. No hosted product, policy, order or environment settings were changed. Real product chart data remains an owner/supplier dependency.

## Verification

- 212 POS tests and 54 website tests passed, including shared validation and rendering regressions for SVG title hydration, literal unit/basis labels, missing cells, escaped supplier text and accessible chart markup.
- 919 database assertions passed after a clean local migration reset, including old-client preservation, explicit clearing, idempotent retries, customer/cashier rejection, rollback and the unchanged anonymous function surface.
- Both app production builds, TypeScript and changed-file lint passed. Vite retains the existing large-chunk warning.
- Browser checks used disposable local fixtures and an isolated POS panel. The fit guide was checked at 345 CSS px and 1265 CSS px with one/two-column layouts and no page overflow. The mobile chart had contained table overflow, supplier/unit labels, unknown cells, Escape/Close behavior and focus return. Missing-chart messaging and supplied product accordions were checked. POS entry at 537 CSS px covered unselected required unit/basis, garment/inch entry, duplicate rejection and row removal without page overflow.
- A browser-discovered SVG title hydration issue was fixed and covered by a rendering regression. Temporary fixture styles, variants, users, preview files and servers were removed after checks. No customer order was placed.
