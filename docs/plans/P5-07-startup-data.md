# P5-07 Stop loading everything at startup

**Branch:** `refactor/startup-data`
**Needs:** P5-02, P5-03 and P5-05 merged (they remove the biggest users of `state.sales`).
**Migration (only if needed):** `supabase/migrations/20261024000500_catalog_search.sql`
**Files:** `src/context/SupabaseAppContext.tsx`, `src/lib/services.ts`, `src/lib/queryClient.ts`,
and the components listed below.

## Why
`src/context/SupabaseAppContext.tsx` (around line 280) loads **all** products, customers,
sales, discounts, users, settings and sales tabs at login. With a year of sales this makes
login slow and memory heavy on the counter PC, and data goes stale (another till's sale is not
seen until reload). Server data should be fetched per screen with TanStack Query.

## Target state
`SupabaseAppContext` keeps only: `currentUser`, `settings`, the **cart / held tabs** (UI state),
and dispatch actions for the cart. Everything else comes from `useQuery` hooks.

## Steps (do them in this order, commit after each)

1. **Find every consumer**: `grep -rn "state\.\(products\|customers\|sales\|discounts\|users\|salesTabs\)" src`.
   At the time of writing: CustomerDetailModal, CustomerManager, DiscountManager, DiscountModal,
   GoodsReceiptPanel, InventoryManager, LabelPrintModal, ProductImportPanel, StockCountPanel,
   StyleModal, Cart, ProductGrid, ReturnModal, SalesTabManager, ReportsManager,
   OrderIntake, TransactionsManager, UserManager, UserModal. List them in your report.

2. **Sales**: after P5-02/P5-03/P5-05 nothing should read `state.sales`. Remove `salesService.getAll()`
   from startup, remove `sales` from state and reducer actions (`ADD_SALE`, `DELETE_SALE`, ...),
   and fix compile errors by using queries/invalidation instead. After checkout,
   `queryClient.invalidateQueries` for transactions/reports keys.

3. **Products** — the POS grid and search:
   - Add `productsService.search({ q, category, kind, limit, offset })` (server-side: SKU or
     barcode exact match first, then name `ILIKE`). If the current query layer can't do it
     efficiently, add an SQL function `search_variants(p jsonb)` in the migration
     (counter staff; returns variant id, sku, name, size, color, price, available stock, image;
     `total_count`), with a pgTAP test file `catalog_search.test.sql`.
   - `ProductGrid`: paged / infinite list (`useInfiniteQuery`, 60 per page) with search.
   - Barcode scan path: `productsService.byBarcode(code)` → one round trip, no full list needed.
   - Inventory screens: same search + paging.
   - `staleTime` 60 s; invalidate after style save, receipt, count, adjustment.

4. **Customers**: `customersService.search(q, limit 20)` by name/phone; the customer picker in
   the cart and tailoring intake uses it (debounced). Customer manager list is paged.

5. **Discounts, users**: small tables — move to `useQuery` hooks (`useDiscounts()`,
   `useUsers()`) loaded when their screen opens. The server already applies promotions in
   `quote_sale`, so the cart does not need the discount list (check `Cart.tsx`; if it shows
   promotion names, use what `quote_sale` returns).

6. **Sales tabs (held carts)**: keep in the context, but load only the current user's tabs (as today).

7. **Realtime (optional, only if simple)**: none in this plan. Note in your report where
   it would help.

## Rules
- Each hook lives next to its service (e.g. `src/lib/hooks/useProducts.ts`), with keys in
  `queryKeys`.
- No component may import `supabase` directly.
- Behaviour must stay the same for the cashier: scanning a barcode adds the item immediately;
  typing searches within 300 ms.

## Tests
- Unit tests for any pure helper you add (e.g. search term parsing: barcode vs text).
- Manual: seed 3,000 variants and 20,000 sales locally (SQL script in your scratch area, not
  committed); login must be under 2 s and the POS grid must scroll smoothly. Report timings.
- `npm run test:e2e` must still pass (the smoke test logs in and opens the POS).

## Done when
All guide checks pass; `SupabaseAppContext.tsx` no longer calls `productsService.getAll`,
`customersService.getAll`, `salesService.getAll`, `discountsService.getAll` or `usersService.getAll`.
