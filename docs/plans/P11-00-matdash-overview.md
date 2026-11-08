# P11 MatDash design system: overview and shared rules

Read this file together with `00-AGENT-GUIDE.md` and **one** of the P11-0x plans.

## Source template

- Location on this machine: `D:\LadyVogue\matdash template\` (outside the repo, **never commit it
  or copy it wholesale**). Use `packages\main\src\` as the reference for pages and
  `packages\starterkit\src\` as the clean base (layout, `components/ui`, CSS).
- Stack: Vite + React 19 + TypeScript + Tailwind 4 + shadcn/ui ("new-york" style, Radix
  primitives) + ApexCharts. This is the same stack as the POS (`src/`), so its files can be copied
  almost directly. The website (`website/`, Next.js 16) uses the same Tailwind 4 and React 19.
- It is a paid template (WrapPixel MatDash Pro). Copy only the files you need into this repo.
  **Do not copy** demo images, photos, product pictures, avatars, flags, Lottie files, the
  `figma-file` folder, the `docs` folder or the template's `README.md`. Use our own logo and our
  own product images.

## What to take

| Take | From (`packages/main/src/`) | Notes |
|---|---|---|
| Design tokens | `css/globals.css` (`@theme inline` block, `:root` block), `css/theme/default-colors.css` (only `:root`) | Keep the variable names (`--color-primary`, `lightprimary`, `bodytext`, `link`, `darkgray`, `shadow-md` …) so copied markup works unchanged. |
| Layout CSS | `css/layouts/sidebar.css`, `header.css`, `container.css`, `css/override/reboot.css`, `css/pages/dashboards.css`, `auth.css` | Remove rules for features we don't use (RTL, horizontal menu, calendar, maps). |
| UI components | `components/ui/*.tsx` | Only the ones a plan uses. Keep the shadcn file names. |
| Shared cards | `components/shared/CardBox.tsx`, `TitleIconCard.tsx`, `OutlineCard.tsx` | Remove the `CustomizerContext` dependency: fixed shadow card, radius from the token. |
| Shell | `layouts/full/vertical/sidebar/*`, `layouts/full/vertical/header/Header.tsx`, `Profile.tsx`, `Notifications.tsx`, `Search.tsx`, `layouts/full/shared/breadcrumb/BreadcrumbComp.tsx` | Rewired to our views, see P11-02. |
| Dashboard widgets | `components/dashboards/Dashboard1/*`, `Dashboard2/*` | Look and chart options only; data comes from our report functions. |
| Tables, forms | `components/shadcn-table/*`, `components/react-tables/*` (styling only), `components/shadcn-form/*` | |
| Auth pages | `views/authentication/auth2/Login.tsx`, `authforms/AuthLogin.tsx` | Login look only; logic stays ours. |
| Shop pages (website) | `views/apps/eCommerce/*`, `components/apps/ecommerce/*`, `components/front-pages/layout/*` | For P11-04. |

## What NOT to take

The full Customizer panel (only its theme mode and colour preset parts are used, see decision 1),
RTL, i18n (`react-i18next`), CASL, JWT/Firebase guards,
MSW mocks and `src/api`, `@google/genai`, TipTap, kanban/chat/email/calendar apps, `react-router`
(the POS keeps its current view switching), `flowbite-react`, `moment`, `lodash`, `aos`, `simplebar`.

## Decisions (do not change without asking)

1. **Light and dark mode, both apps.** Copy MatDash's `.dark` tokens and its theme handling
   (`starterkit/src/context/ShadcnThemeContext/theme-context.tsx`, `CustomizerContext.tsx` reduced to
   the mode and colour preset): class `dark` on `<html>`, a **Light / Dark / System** choice, System
   follows `prefers-color-scheme` and updates live, choice saved per device in `localStorage`
   (every read/write in try/catch, falls back to System). **No flash on load**: a tiny inline script
   in `index.html` (POS) / `app/layout.tsx` (website, with `suppressHydrationWarning` on `<html>`)
   applies the class before the first paint. Every screen and component must look right in both
   modes, using the `dark:` variants and dark tokens the way MatDash does (cards `dark:bg-darkgray`,
   borders `dark:border-darkborder`, text `dark:text-white` / `dark:text-darklink`). Charts read
   colours from CSS variables and re-render when the mode changes. **Printing is always light**
   (`@media print` forces the light tokens).
2. **Colours**
   - POS: MatDash `BLUE_THEME` by default (`--color-primary: #635BFF`, `--color-secondary:
     #16CDC7`) plus MatDash's colour presets (`default-colors.css`: Blue, Aqua, Purple, Green, Cyan,
     Orange), chosen per device in the theme settings (P11-02).
   - Website: the **Lawrencepur brand colours** from the storefront, written into the **MatDash token
     names** (`--color-primary`, `--color-secondary`, `lightprimary`, `link`, `bodytext`, `border`,
     `darkgray` …) with a matching dark set, so MatDash components show the brand automatically.
     No colour preset switcher on the website; only Light / Dark / System.
3. **Font**: Manrope, **self-hosted** with `@fontsource-variable/manrope` (no Google Fonts `@import`,
   because the till must work on a weak connection). Website: `next/font/google` Manrope is
   acceptable because Next self-hosts it at build time.
4. **Icons**: keep `lucide-react` (already in both apps; shadcn uses it). Do not add `@iconify/react`
   (it downloads icons from the internet at runtime). Where MatDash uses a Solar icon, pick the
   closest Lucide icon at `size={20}` / `strokeWidth={1.75}` for the soft look.
5. **Charts**: use `apexcharts` + `react-apexcharts` with MatDash's chart options (gradient areas,
   rounded bars, Manrope, token colours). Read colours from CSS variables at runtime so charts
   follow the theme. Remove `recharts` only when nothing imports it any more.
6. **Pop-ups**: keep `sweetalert2` but theme it (P11-01). New dialogs use the shadcn `Dialog`.
7. **Accessible names stay the same.** Button texts, labels, headings and `aria-label`s that
   `e2e/*.spec.ts` or unit tests use must not change. Restyle, don't rename.
8. **No behaviour changes.** No service, context, database, edge function or business-logic
   changes in any P11 plan. If a design needs data the app does not load today, show what exists
   and list the gap in the report instead of adding queries (exception: P11-02 dashboard, which
   may call the existing `reportsService` and `onlineOrdersService` functions).

## New packages (pin exact versions)

Add only what the plan you are doing uses. Use the newest stable version that was published at
least two weeks ago (`npm view <pkg> time`) and pin it exactly (no `^`):
`class-variance-authority`, `clsx`, `tailwind-merge`, `tw-animate-css`,
`@fontsource-variable/manrope`, the `@radix-ui/react-*` packages that the copied `ui` files import,
`apexcharts`, `react-apexcharts`. Root lock file: `npm install` as usual. Website lock file:
`cd website && npx -y npm@10.9.9 install`, then check with `npx -y npm@10.9.9 ci --dry-run`.

## Path alias

MatDash imports use `src/...`. In the POS add an alias `@/` → `src/` (in `vite.config.ts`, which Vitest
also uses, and `tsconfig.app.json`) and rewrite copied imports to `@/components/ui/...`.
The website already has its own alias; use it.

## Order

These plans start **after** plan 19b (`feat/storefront-replace`: the storefront replaces
`website/` and is connected to the POS) and P20 (storefront catalog) are merged. Where this file
says P19, read plan 19b.

| Plan | Branch | Depends on |
|---|---|---|
| [P11-01 POS design system](P11-01-pos-design-system.md) | `feat/ui-theme` | P19, P20 merged |
| [P11-02 POS shell and dashboard](P11-02-pos-shell-dashboard.md) | `feat/ui-shell` | P11-01 |
| [P11-03 POS screens](P11-03-pos-screens.md) | `feat/ui-screens` | P11-02 |
| [P11-04 Website on the MatDash design system](P11-04-website-theme.md) | `feat/web-theme` | P11-01, P19, P20 |

## Checks for every P11 plan

All of section 2 of the guide, plus:
- `npm run build` for the POS, and `npm --prefix website run build` when `website/` changed.
- Bundle: report the size of the largest JS chunk before and after (from the Vite output).
  Load ApexCharts with `React.lazy` so the till screen does not download it.
- Screenshots in **light and dark** (Playwright, 1440×900 and 390×844) of every screen the plan touched, saved under
  `docs/screenshots/p11-0x/` **in the working tree only, not committed**, and listed in the report.
- No template demo assets in `git diff --stat`; no file from the template larger than 50 KB.
