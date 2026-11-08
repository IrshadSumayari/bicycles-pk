# P5-01 Report functions in the database

**Branch:** `feat/reports-db`
**Migration:** `supabase/migrations/20261024000000_report_functions.sql`
**Test file:** `supabase/tests/database/reports.test.sql`
**Scope:** database only (plus `npm run db:types`). No UI in this plan.

## Why
`ReportsManager.tsx` computes everything in the browser from the legacy `sales.items` JSON,
which ignores returns, split payments, tailoring income and cost of goods. Reports must come
from the ledgers (`sale_lines`, `payments`, `returns`, `return_lines`, `stock_movements`,
`tailoring_*`) and be computed by the server, so numbers are the same on every screen.

## Rules for all report functions
- `LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public` (or plpgsql if needed).
- First line of logic: refuse unless `has_app_role(ARRAY['admin','manager'])`
  (raise `'Only managers can see reports'` with ERRCODE `42501`). Use a plpgsql wrapper
  if a SQL function cannot raise.
- Parameters: `p_from DATE, p_to DATE` (inclusive, shop-local dates) and
  `p_branch UUID DEFAULT NULL` (NULL = all branches the caller is a member of).
- Shop-local date: `(created_at AT TIME ZONE 'Asia/Karachi')::date`. Put the zone in one helper
  `report_tz()` returning `'Asia/Karachi'` so it can be changed later.
- Exclude sales with `status = 'draft'`. Include `completed` and `credit`.
- Return `TABLE(...)` with explicit column types (not JSON), so `database.types.ts` types them.
- `REVOKE ALL ... FROM PUBLIC, anon; GRANT EXECUTE ... TO authenticated;`
- Add indexes only where needed: `sales(branch_id, created_at)`, `payments(created_at)`,
  `sale_lines(sale_id)` if not present (`CREATE INDEX IF NOT EXISTS`).

## Functions to create

1. **`report_sales_summary(p_from, p_to, p_branch)`** → one row per day:
   `day DATE, invoices INT, gross NUMERIC, discounts NUMERIC, net_sales NUMERIC, tax NUMERIC,
   returns NUMERIC, returns_tax NUMERIC, net_after_returns NUMERIC, cost NUMERIC, margin NUMERIC`.
   - From `sale_lines` joined to `sales`: `gross = sum(gross)`, `discounts = sum(manual_discount + promotion_discount)`,
     `net_sales = sum(net)`, `tax = sum(tax)`.
   - `returns = sum(return_lines.refund_amount - return_lines.tax_amount)` by **return date**,
     `returns_tax = sum(return_lines.tax_amount)`.
   - `cost = sum(sale_lines.quantity * coalesce(unit_cost,0))` minus cost of restocked returned
     quantities (use the original sale line's `unit_cost`).
   - `net_after_returns = net_sales - returns`; `margin = net_after_returns - cost`.
   - Days with no activity are omitted.

2. **`report_tenders(p_from, p_to, p_branch)`** → `method TEXT, money_in NUMERIC, money_out NUMERIC, net NUMERIC, count INT`.
   From `payments` (all sources: sales, returns, tailoring orders). Exclude `method = 'exchange'`
   (internal). `amount - change_given` is the real cash in for cash. Branch: from the linked
   sale/return/tailoring order, or the cash session.

3. **`report_top_items(p_from, p_to, p_branch, p_group TEXT DEFAULT 'style', p_limit INT DEFAULT 50)`**
   → `key TEXT, label TEXT, quantity NUMERIC, net NUMERIC, cost NUMERIC, margin NUMERIC`.
   `p_group` in (`'style'`, `'variant'`, `'category'`, `'size'`, `'color'`); anything else raises.
   Net of returns (subtract returned quantity and refund). Order by `net DESC`.

4. **`report_size_color_matrix(p_from, p_to, p_branch, p_style UUID)`**
   → `size TEXT, color TEXT, sold NUMERIC, on_hand NUMERIC`.
   Sold = quantity sold minus returned; on_hand = current `stock_balances.on_hand` summed over
   locations. Used to decide reorders by size.

5. **`report_fabric_usage(p_from, p_to, p_branch)`**
   → `variant_id UUID, sku TEXT, name TEXT, meters_sold NUMERIC, meters_tailoring NUMERIC,
   meters_waste NUMERIC, meters_on_hand NUMERIC`.
   From `stock_movements` for styles with `kind = 'fabric'`, grouped by `movement_type`
   (look at the existing movement types in the migrations: sale, tailoring issue, adjustment
   with negative quantity = waste).

6. **`report_tailoring(p_from, p_to, p_branch)`** → one row:
   `orders_taken INT, order_value NUMERIC, deposits NUMERIC, balance_collected NUMERIC,
   delivered_items INT, open_orders INT, open_balance NUMERIC, overdue_items INT`.
   `open_*` and `overdue_items` are "as of now" (not limited to the period). Overdue = item not
   delivered and `promised_date < current_date`. Use `tailoring_order_totals()` for balances.

7. **`report_staff_sales(p_from, p_to, p_branch)`** → `user_id UUID, name TEXT, invoices INT,
   net_sales NUMERIC, returns NUMERIC, discounts NUMERIC`. Uses `sales.cashier_id`.

## Tests (`reports.test.sql`, about 20 assertions)
Build fixtures through real functions (`save_style` with costs, `open_cash_session`,
`post_sale` with split cash/card, `post_return` of one line, `create_tailoring_order` with a deposit,
`adjust_fabric_roll` waste). Then assert:
- summary: net, tax, returns, cost and margin for today match hand-computed values;
- a draft sale is not counted;
- tenders: cash and card totals; the refund appears in `money_out`; `exchange` never appears;
- top items by style and by size; returned quantity is subtracted;
- size/color matrix shows sold and on-hand for each variant;
- fabric usage: meters sold and waste;
- tailoring: deposit, open balance;
- a cashier and a tailor get `42501` from every report function (test at least 3 functions each);
- dates outside the range return no rows.

## Done when
All checks of the guide pass, `src/lib/database.types.ts` is regenerated, and no UI files changed.
