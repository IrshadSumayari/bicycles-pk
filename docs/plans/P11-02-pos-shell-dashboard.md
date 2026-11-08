# P11-02 POS shell (MatDash sidebar + header) and dashboard

**Branch:** `feat/ui-shell`
**Needs:** P11-01 merged.
**Files:** `src/App.tsx`, `src/components/layout/*` (new `AppSidebar.tsx`, `MobileSidebar.tsx`,
`TopHeader.tsx`, `ProfileMenu.tsx`, `PageHeader.tsx`, `navigation.ts`; `Header.tsx` removed or
reduced), new `src/components/dashboard/*`, `src/lib/dashboard.ts` (+ test),
`src/lib/queryClient.ts` (query keys only), `package.json`, `package-lock.json`.
**No migration. No new database functions.**

## 1. Navigation model (`src/components/layout/navigation.ts`)

One typed list replaces the role checks scattered in `Header.tsx` / `App.tsx`:

```ts
type ViewId = 'dashboard' | 'pos' | 'tailoring' | 'online' | 'transactions' | 'inventory'
  | 'customers' | 'reports' | 'discounts' | 'users' | 'settings' | 'work';
interface NavItem { id: ViewId; label: string; icon: LucideIcon; roles: Role[]; section: 'Sales' | 'Catalogue' | 'Management'; badge?: 'onlinePlaced' }
```
Keep **exactly** today's permissions (read them from the current `App.tsx`/`Header.tsx` before
changing anything): tailor → `work` only; cashier → `pos`, `tailoring`, `online`, `reports`,
`settings` as today; manager/admin → everything except `users` (admin only). New view
`dashboard` → admin and manager only. Add `canOpen(role, view)` and use it in `App.tsx` instead of
the `switch` fall-backs (and fix the current "setState during render" by redirecting in an
effect). Unit-test `canOpen` for every role × view. Default view after login: `dashboard` for
admin/manager, `pos` for cashier, `work` for tailor.

## 2. Shell (copy the look of `layouts/full/FullLayout.tsx` + `vertical/sidebar/*` + `vertical/header/*`)

- **Sidebar** (270 px, white, `shadow-md`): logo (store logo from settings, fallback text),
  section captions in small caps, items as MatDash `NavItems` (rounded pill, `bg-lightprimary
  text-primary` when active, hover the same at lower opacity), online-orders badge (reuse the
  existing `placed` query from `Header.tsx`), at the bottom the MatDash profile card (name, role,
  sign-out button with the existing confirm).
- **Mini sidebar**: on the `pos` view the sidebar collapses to 80 px icons with tooltips (MatDash
  `IconSidebar` look) to keep the till wide; a toggle button in the header expands it. Remember
  the choice in `localStorage` (wrapped in try/catch).
- **Mobile (< 1024 px)**: sidebar becomes a `Sheet` opened from the header burger.
- **Header** (70 px, sticky, white): burger/toggle, page title, then right side:
  `ConnectionStatus`, light/dark switch (MatDash header sun/moon button: one click toggles light ↔
  dark; the full choice is in Theme settings), interface-mode toggle (touch/traditional, existing
  logic), cart count chip
  on the till, notifications bell (online `placed` count, click → online orders), profile dropdown
  (MatDash `Profile.tsx` look: avatar initials, name, email, role, Settings, Sign out).
- **PageHeader** component (MatDash `BreadcrumbComp` look: title + small breadcrumb "Home / X" on a
  `bg-lightprimary` rounded card). Not used on the till.
- Content area: `bg-lightgray`, `p-6` desktop / `p-4` mobile; the till keeps full height, no padding.
- Remove the old top navigation once the sidebar works. Keep every visible label and the
  sign-out confirmation text the same (e2e uses them).

## 2b. Theme settings (every role, per device)

MatDash Customizer look, reduced: a right-side `Sheet` opened from the profile dropdown
("Theme settings") and from a palette button in the header. It contains only:
- **Theme mode**: Light / Dark / System (three cards with icons, as in the MatDash Customizer);
- **Colour**: the six MatDash presets as colour swatches;
- **Sidebar**: Full / Mini (the same choice as the header toggle).
Uses `ThemeContext` from P11-01; saved per device; no database setting. Nothing else from the
Customizer (no layout direction, boxed/full container, card shadow or border radius options).

## 3. Dashboard view (admin, manager) — follow `views/dashboard/Dashboard1.tsx` layout

12-column grid, `gap-6`, built with `CardBox`. Data only from existing services:
`reportsService.salesSummary/tenders/topItems/tailoring/staffSales`, `onlineOrdersService.list`
and the current cash session if already exposed. Put all shaping in `src/lib/dashboard.ts` (pure
functions, unit-tested): totals, change vs previous period, series per day, top-N.

| Card | MatDash source | Our data |
|---|---|---|
| Welcome box (col 5) | `WelcomeBox` | "Welcome back, {name}", today's net sales and number of sales; our own illustration-free background (gradient from the tokens), **no template image** |
| Two small stat cards | `Customer`, `Project` | Average sale value today; online orders waiting (`placed` + `confirmed`) |
| Revenue forecast (col 7) | `RevenueForcast` (bar/area chart, range select) | Net sales per day, this period vs previous; range: 7 days / 30 days / this month |
| Payment mix (col 5) | `YourPerformance` / donut | `report_tenders` by method (cash, card, Easypaisa, credit, COD) |
| Two chart cards | `CustomerChart`, `SalesOverview` | Tailoring orders by status; sales by staff |
| Top products table (col 8) | `RevenueByProduct` (tabs + table) | `report_top_items` by style, tabs: Garments / Fabric / All, product image thumbnail when present |
| Total settlement (col 4) | `TotalSettelment` | Today's tender totals list |

- Charts: `react-apexcharts` lazily loaded (`React.lazy` + `Suspense` with `Skeleton`), options
  copied from the matching MatDash component, colours from CSS variables, numbers formatted with
  the existing currency formatter (PKR).
- Branch filter: use the current branch selection the reports screen uses; nothing new.
- Loading → `Skeleton`; error → small inline error card with retry; empty → friendly empty text.
- Refresh every 60 s (`refetchInterval`), paused when the tab is hidden.

## Tests

- `navigation.test.ts` (`canOpen`, default view per role), `dashboard.test.ts` (shaping functions).
- Extend `e2e/login.spec.ts` only if a selector broke; keep it passing.
- Screenshots (light and dark): dashboard, till with mini sidebar, mobile sheet open, each role's
  sidebar, theme settings sheet, the dashboard with each colour preset.
