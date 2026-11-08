# P11-04 Website on the MatDash design system

**Branch:** `feat/web-theme`
**Needs:** P19 (storefront design and pages in `website/`) and P20 (storefront catalog) merged,
P11-01 merged (to reuse its token file).
**Files:** `website/app/globals.css` (+ new `website/styles/*`), `website/components/ui/*`,
`website/components/**` (presentation only), `website/app/**/page.tsx` / `layout.tsx` (markup only),
`website/package.json`, `website/package-lock.json` (npm 10.9.9).
**No migration. No change to data fetching, server actions, Supabase calls, `proxy.ts`, cart or
checkout logic.**

## Principle

The website is a **clothing shop**, not an admin panel. After P19 it has the storefront's pages
and brand content. This plan gives it the MatDash **design system** (same tokens, font, buttons,
inputs, cards, badges, tables) and MatDash's **shop and account pages** as the layout reference,
so the website and the POS look like one product. Brand photos, banners and the brand name from
P19 stay; MatDash's SaaS marketing sections (pricing, team, companies, "purchase template") are
**not** used.

## Steps

1. **Tokens**: copy `src/css/theme/tokens.css` from the POS (P11-01) to `website/styles/tokens.css`
   and import it in `globals.css`. Keep both files identical (add a comment at the top of each
   naming the other). Manrope through `next/font/google` (`variable: '--font-manrope'`) in
   `app/layout.tsx`.
2. **UI components**: copy the needed shadcn files from the template's
   `starterkit/src/components/ui/` into `website/components/ui/` (`button`, `input`, `label`,
   `select`, `checkbox`, `radio-group`, `badge`, `card`, `dialog`, `sheet`, `tabs`, `separator`,
   `skeleton`, `toast`/`toaster`, `breadcrumb`, `accordion`, `carousel` if P19 uses a slider).
   Add `'use client'` where they use state or Radix. Keep server components server-side: only
   leaf interactive parts become client components.
3. **Header and footer** (MatDash `front-pages/layout/Header.tsx`, `Navigation.tsx`,
   `MobileMenu.tsx`, `Footer.tsx`, `AnnouncementBar.tsx` look): announcement bar (text from
   P19 content), logo, collections menu, search, account and bag icons with count, mobile `Sheet`
   menu. Our links only.
4. **Shop pages** (follow `views/apps/eCommerce/*` and `components/apps/ecommerce/*`):
   - Collection / search: left filter `CardBox` (size, colour, price, availability) as in
     `productGrid` sidebar, grid of product cards (MatDash product card: image with hover zoom,
     name, price, sale badge, quick "Add to bag"), sort select. Mobile: filters in a `Sheet`.
   - Product page: `productDetail` layout (gallery with thumbnails left, info right: name, price,
     size/colour selectors as pill buttons, quantity, Add to bag, stitching request link,
     description/size guide tabs, related products row).
   - Cart and checkout: `checkout` look (stepper Cart → Details → Payment, order summary card on
     the right). Logic, `request_id` handling and payment redirects unchanged.
5. **Account area**: `account-setting` look for profile; orders and stitching requests as MatDash
   tables with status badges; order detail with the timeline style from P11-03.
6. **Sign-in, stitching request form, not-found, error pages**: MatDash `auth2` and form styles;
   404 like MatDash `Error.tsx` without the template illustration.
7. **Performance**: no chart library on the website; images through `next/image` with the sizes
   P20 set up; Lighthouse (mobile) on home, collection and product page: report Performance,
   Accessibility, Best practices and SEO scores before and after. Do not lower any of them.

## Tests and checks

- Existing website tests pass unchanged (`npm --prefix website test`), `website` lint, type-check
  and build; lock file valid with npm 10.9.9.
- Screenshots (desktop + 390 px) of home, collection, product, cart, checkout, sign-in, account
  orders, order detail, stitching request, 404.
