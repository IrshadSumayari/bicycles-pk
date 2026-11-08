# P11-03 POS screens in MatDash style

**Branch:** `feat/ui-screens`
**Needs:** P11-02 merged.
**Files:** `src/components/**` (presentation only), `src/components/shared/*` (new shared pieces).
**No migration. No changes to `src/lib/services.ts`, contexts, hooks' data logic or tests' expectations.**

Restyle each screen with the P11-01 components and the MatDash page patterns. **Markup and
classes only**: keep state, effects, handlers, props, texts, labels and `aria-*` the same. One
commit per area so the review can follow it.

## Shared pieces first (`src/components/shared/`)

- `DataTable` styling wrapper around the existing tables (MatDash `shadcn-table` look: header
  `bg-lightgray text-link font-semibold text-sm`, rows `border-b border-border hover:bg-lighthover`,
  cells `py-3 px-4`, sticky header, empty state row). Not a data-grid library; it wraps `<table>`.
- `StatusBadge` (MatDash badge look: `bg-light{tone} text-{tone}` rounded-full) with one mapping
  for sale, online order, payment, tailoring order, tailoring request and shift statuses. Reuse
  the existing status texts.
- `StatCard` (icon in a `bg-light{tone}` rounded square, label, value, optional change %).
- `ModalShell`: shadcn `Dialog` look (header with title + close, body, footer with actions)
  used by restyled modals. Keep focus behaviour and close-on-escape as today (`modalUtils.ts`).
- `FormField` (label, control, help/error text) in MatDash form style.
- `EmptyState` (lucide icon in a soft circle, title, text, optional action).

## Screens (order of work)

1. **Login** (`auth/LoginPage.tsx`): MatDash `auth2/Login` split layout: left panel with gradient
   from the tokens and the store name/logo (no template illustration), right card with the form.
2. **Till** (`pos/*`): product grid cards like MatDash `ecommerce/productGrid` (image, name, SKU,
   price chip, stock badge), category/search bar in a `CardBox`, cart as a right-side `CardBox`
   with clear totals block and a large primary **Checkout** button; `SalesTabManager` tabs as
   MatDash pill tabs; `CashShiftBar` as a slim card. Touch mode keeps the larger hit areas
   (min 48 px). Checkout and return modals with `ModalShell`; tender buttons as large tiles.
   **Speed matters**: no animations on the till beyond 150 ms transitions; no chart library.
3. **Online orders** (`online/*`): list as `DataTable` with `StatusBadge`, filter pills, search in
   the card header; detail as two columns (order + lines | customer, payment, timeline). Timeline
   in MatDash `DailyActivities` look.
4. **Tailoring** (`tailoring/*`): manager tabs as pill tabs; requests inbox and orders panel as
   tables with badges; work queue as cards (MatDash kanban-card look, without drag and drop).
5. **Inventory** (`inventory/*`): product list like MatDash `EcomProductList` (thumbnail, name,
   SKU, stock, price, status, actions menu via `DropdownMenu`); `StyleModal`, `WebsitePanel`,
   `ImageManager`, stock panels with `ModalShell`/`CardBox` and `FormField`.
6. **Customers, discounts, users, transactions**: list = `DataTable`, header = `PageHeader` with
   the primary action button on the right, detail/edit modals with `ModalShell`.
7. **Reports** (`reports/*`): KPIs as `StatCard`s; tables with `DataTable`; if a report already
   shows a chart, switch it to the lazily loaded ApexCharts setup from P11-02 with the same data.
8. **Settings** (`settings/*`): MatDash `account-setting` layout: left vertical tabs, right section
   cards with `FormField`s and a save bar.

Print components (`ReceiptPrint`, `PackingSlip`, `OrderSlip`, `LabelPrintModal` print area) keep
their print layout; only the on-screen preview chrome changes.

## Done when

- Before/after screenshots for every screen (desktop and 390 px, light and dark) in the report.
- Every new or restyled element has its `dark:` styling; no hard-coded `bg-white` / `text-black`
  without a dark variant (`rg -n "bg-white|text-black" src/components` reviewed and listed).
- `rg -n "(blue|indigo|gray|slate)-[0-9]{2,3}" src/components` returns nothing (all tokens).
- `recharts` removed from `package.json` if nothing imports it.
- All checks, unit tests and e2e pass with **no test expectation changed**.
