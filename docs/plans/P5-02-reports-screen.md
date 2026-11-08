# P5-02 Reports screen on server data

**Branch:** `feat/reports-ui`
**Needs:** P5-01 merged (report functions exist).
**Files:** `src/components/reports/ReportsManager.tsx` (rewrite), new `src/components/reports/*`
sub-components, `src/lib/services.ts` (add `reportsService`), `src/lib/queryClient.ts` (keys),
new `src/lib/csv.ts` + `src/lib/csv.test.ts`, `src/lib/reportDates.ts` + test.

## Why
The current screen calculates from `state.sales` (legacy JSON, all sales loaded at startup).
Replace it with screens that call the P5-01 functions.

## Steps

1. **Service** in `services.ts`:
   ```ts
   export const reportsService = {
     salesSummary(from: string, to: string, branchId?: string) { ... supabase.rpc('report_sales_summary', { p_from, p_to, p_branch }) },
     tenders(...), topItems(..., group, limit), sizeColorMatrix(..., styleId), fabricUsage(...), tailoring(...), staffSales(...)
   };
   ```
   Throw on `error` like the other services. Dates are `YYYY-MM-DD` strings.

2. **Date ranges** `src/lib/reportDates.ts`: presets `today`, `yesterday`, `this_week` (Mon–Sun),
   `this_month`, `last_month`, `custom`. Pure function `rangeFor(preset, now: Date)` →
   `{ from, to }`. Unit-test each preset, including month boundaries and a Sunday.

3. **CSV** `src/lib/csv.ts`: `toCsv(rows: Record<string, string|number|null>[], columns: {key, label}[])`
   with correct quoting (commas, quotes, newlines), a UTF-8 BOM prefix (`'﻿'`, written as
   `String.fromCharCode(0xfeff)` to be safe), and `downloadCsv(filename, csv)`. Unit-test quoting.

4. **Screen** `ReportsManager.tsx`: header with preset picker + custom dates, tabs:
   - **Sales**: KPI cards (net after returns, tax, returns, margin, margin %), a daily table,
     and a simple bar chart (plain divs or SVG; **do not add a chart library**).
   - **Payments**: tenders table (in, out, net per method).
   - **Products**: group selector (style/variant/category/size/color), top items table;
     a style picker opens the size × color matrix (`sold / on hand` per cell).
   - **Fabric**: fabric usage table.
   - **Tailoring**: KPI cards from `report_tailoring`.
   - **Staff**: staff sales table.
   Each tab: `useQuery` with key `queryKeys.reports(tab, from, to, extra)`; loading and error
   states (`getErrorMessage`); an **Export CSV** button exporting exactly the visible table.
   Money via `state.settings.currency`. Split the tabs into components in
   `src/components/reports/` (e.g. `SalesReport.tsx`, `TendersReport.tsx`, ...), each < 250 lines.

5. **Access**: only admin and manager see the Reports navigation item (check `Header.tsx` /
   `App.tsx`; keep existing behaviour if already restricted). A cashier opening the screen must
   see a friendly "Managers only" message, not a crash.

6. Remove the old calculations from `ReportsManager.tsx` and any now-unused helpers. Do **not**
   touch `SupabaseAppContext` in this plan (P5-07 does that).

## Tests
- Vitest: `reportDates.test.ts`, `csv.test.ts`.
- Manual: run the app against local Supabase, make a sale, a return and a tailoring deposit,
  confirm the Sales and Payments tabs show them, export a CSV and open it in Excel
  (Urdu/English names display correctly).

## Done when
All guide checks pass; `ReportsManager.tsx` no longer reads `state.sales`.
