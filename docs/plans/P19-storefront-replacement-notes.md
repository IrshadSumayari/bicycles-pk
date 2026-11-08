# Storefront replacement handoff

Branch: `feat/storefront-replace`, from develop `6674a53`.

The owner requested a full replacement using the separate Lawrencepur storefront
and then clarified the appearance: keep the Lawrencepur layout/brand, but use
MatDash components, with light/dark/system appearance settings. This clarification
supersedes exact visual parity for controls and the earlier light-only notes.

## Implementation and scope

The old presentation was removed. The source storefront's component names and
page structure now serve the website, reconnected to the existing POS catalog
and customer integration. MatDash buttons, inputs, textarea, cards, badges and
sheets are copied selectively from the local starterkit. The customizer, demo
assets, unrelated apps and backend are excluded. Poppins remains local to keep
the Lawrencepur typography; the appearance setting is shared across controls,
persisted locally, and follows system changes when selected.

All pre-existing `website/lib` files/tests retain their implementation, as do
`proxy.ts`, the email template, Next/TypeScript/ESLint/Vitest/PostCSS configuration,
environment example, robots and sitemap. Added helpers cover owner content,
navigation and appearance. No POS source or Supabase files are changed.

Catalog pages still render on the server with 60-second revalidation. Filters,
sorting and pagination stay in the URL and use the existing server functions.
Product variant combinations, no-store availability refresh (mount, focus and
visibility), the size chart, bag and WhatsApp action remain operational. Bag
storage contains only versioned variant IDs and quantities. Quotes and checkout
totals come from the server. Checkout retry identifiers, hosted payment redirects,
return polling, cancellation holds and customer access checks remain intact.

Fourteen owner pages/policies are sanitized at build time using pinned
`sanitize-html` 2.18.1. Unsupported legacy contact forms use owner email links;
appointment actions enter the existing protected stitching flow. No unsupported
form pretends to submit. No production domain/DNS changes were made.

## Copied and adapted files

From the source storefront, into `website/components/` (same source names):

- `header.tsx`, `footer.tsx`, `home.tsx`
- `collection-browser.tsx`, `product-card.tsx`, `product-detail.tsx`, `search-page.tsx`
- `store-provider.tsx`, `cart.tsx`, `checkout.tsx`, `account.tsx`
- `tailoring-page.tsx`, `request-form.tsx`

The source render structures were adapted to the existing POS types, server
queries and customer flows. In particular, the source bag/checkout/account/request
backend behavior is replaced by the already working integration, rather than
retaining the source's independent backend or client-supplied prices.

The source layout/home/catalog/product/cart/search/content/policy/404 page
structure and `globals.css` were copied/adapted. The source font declarations are
replaced by `next/font/local`. All existing protected account/order/request and
checkout return/cancel URLs are retained with the replacement component imports.

Brand assets copied to `website/public/brand/`: `logo.png`, `favicon.png`, and
`poppins-400.woff2`, `poppins-500.woff2`, `poppins-600.woff2`, `poppins-700.woff2`.

MatDash files copied/adapted under `website/components/ui/`: `button.tsx`,
`input.tsx`, `textarea.tsx`, `card.tsx`, `badge.tsx`, `sheet.tsx`, `utils.ts`.
The card's template customizer dependency is removed. Keyboard focus remains
visible. MatDash token blocks live in `website/styles/tokens.css`; integration
styles preserve the storefront structure in both appearances.

Reused from `feat/storefront-design`: `lib/contentSanitizer.ts` and its test,
`lib/content.ts`, `content/pages/index.json`, `lib/navigation.ts` and its test.
Homepage campaign metadata is reused without any bundled product catalog.

## Removed old files

All paths below are under `website/components/`. Their required integration
behavior now lives in the replacement components; none is imported any more.

- `CartProvider.tsx`, `CartView.tsx`, `CatalogPage.tsx`
- `CheckoutForm.tsx`, `CustomerOrder.tsx`, `OrderReturn.tsx`
- `ProductDetails.tsx`, `ProductGrid.tsx`
- `RequestActions.tsx`, `RequestForm.tsx`, `SignIn.tsx`
- `Profile.tsx` renamed to `profile.tsx`, with MatDash controls

The old global styles, root/home/catalog/product/cart/search layouts and old
markup were replaced in place. Protected server query/authorization behavior is
retained in rebuilt routes. No existing tests were deleted or altered.

## Checks

| Command | Result |
| --- | --- |
| `npm run db:reset` | Passed |
| `npm run test:db`, twice consecutively | Passed both times: 29 files, 975 checks each |
| `npm test` | Passed: 19 files, 117 tests |
| `npx tsc -b` | Passed |
| `npm run lint` | Passed: 0 errors, 8 existing warnings |
| `npm run build` | Passed; existing chunk-size/dynamic-import warnings; largest POS JS chunk 1,094.93 kB, unchanged by this website-only work |
| `npm run web:lint` | Passed: 0 errors, 0 warnings |
| `npm run web:test` | Passed: 7 files, 31 tests |
| Website type check / `npm run web:build` | Passed, including 30 generated pages |
| Website npm 10.9.9 install and `ci --dry-run` | Passed; no lockfile sync error |
| Required prohibited-reference `rg` command | No matches |
| `git diff --check` | Passed |

The original 24 website tests are unchanged. Added coverage comprises five
navigation/sanitizing tests and two appearance-mode tests. Dependency installation
reports five high audit findings; no unrelated forced dependency upgrades were
performed as part of this replacement.

Lighthouse 12.8.2, production mobile product page with local fixture images:
**99 performance / 100 accessibility** (targets 85 / 90). The preceding build
measured 93/100; the final build was measured again after the catalog/search
presentation adjustment. This measures the local
rehearsal, not the later imported production catalog or a real payment provider.

## Manual results and visual differences

Local Supabase was reset and four published products, three collections and
isolated test accounts were created through the existing APIs. The browser
rehearsal passed:

- Home/carousel, collection index and URL filters/sort, server search, a real
  92-character product handle, gallery, stock bands, unavailable variants, refresh
  and size chart.
- Persistent bag, quantity changes, server quotes/totals, protected checkout,
  email-code sign-in, account/profile/orders and request history.
- COD order creation and customer cancellation; mock card hosted redirect,
  unpaid state before the signed notification, return polling to confirmation,
  duplicate notification and the cancel/return route.
- Stitching request submission with a resized private photo and real timeline.
- Content/policy sanitizing, keyboard menus/dialogs, no Google Fonts calls,
  all requested page types at desktop and 375px without horizontal overflow.
- Light/dark persistence, cross-control synchronization, live system appearance,
  and production smoke checks with no browser console/network errors. Account
  responses remain private and uncached.

The source storefront ran on port 3100 for comparison. Paired screenshots cover
home, collection, product, search, content, policy, cart, checkout, account and
tailoring at 1440px and 375px. Review images and raw audit reports are in the
ignored local cache `node_modules/.cache/website-work/replace-*`; test credentials
are never included in this commit. Anonymous comparisons intentionally show
sign-in on protected replacement routes; signed-in checkout/order/request screens
were separately exercised and captured.

Visible differences, by design:

- MatDash rounded cards, blue actions, form controls, accessible sheets and the
  light/dark/system selector; the source has square black actions and no dark mode.
- Navigation and product/collection imagery reflect published POS data rather
  than the source snapshot; local rehearsal images are fixtures. Product cards
  show the image exposed by the catalog list rather than importing source photos.
- Collection sort choices are the existing POS choices (newest and price), with
  server-supported size/color/price filters. Search keeps the source's prominent
  search field; the filter toolbar opens the sidebar as in the source layout.
- The customer flows require sign-in and retain the existing pickup/delivery,
  card/wallet/COD, order timeline/cancellation, quote and private-photo controls.
  The source independent backend and decimal cart quantities are not transferred.
- Product information displays the available POS fields; descriptions stay safe
  text. Delivery/payment promises refer to checkout settings rather than asserting
  unconditional free delivery. Header/footer include local account/order links.
- Content pages contain owner text only. Legacy media/widgets/forms are stripped;
  tailoring/contact actions use real existing routes or email links.

External image hosts: **`lawrencepur.com` only**, for homepage campaign images.
Product/collection images come from the configured POS storage bucket. Fonts,
logo and favicon are local. No MatDash demo image or remote icon loader is used.

Real Easypaisa sandbox credentials were not used; payment UI was tested with the
existing mock provider. The previously deferred real provider integration remains
outside this presentation replacement. Production catalog/media import is the
next plan and was not started. No missing database change was needed.
