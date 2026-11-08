# P5-03 Transactions screen on server data, with paging

**Branch:** `feat/transactions-v2`
**Migration:** `supabase/migrations/20261024000100_transaction_search.sql`
**Test file:** `supabase/tests/database/transaction_search.test.sql`
**Files:** `src/components/transactions/TransactionsManager.tsx` (rewrite, split into
`TransactionList.tsx` and `TransactionDetail.tsx`), `src/lib/services.ts`, `src/lib/queryClient.ts`.

## Why
`TransactionsManager.tsx` filters `state.sales` (every sale loaded at startup, legacy JSON
`items`). It cannot show split payments, returns against a sale, or tailoring payments, and it
will get slow after a few months of trading.

## Database

1. **`search_sales(p jsonb)`** → `TABLE(id UUID, invoice_number TEXT, created_at TIMESTAMPTZ,
   status TEXT, customer_id UUID, customer_name TEXT, cashier_name TEXT, total NUMERIC,
   paid_methods TEXT[], returned_amount NUMERIC, line_count INT, total_count BIGINT)`.
   Input keys (all optional): `from`, `to` (dates, shop-local, see `report_tz()` from P5-01 —
   if P5-01 is not merged yet, use `'Asia/Karachi'` directly), `status`
   (`completed|credit|draft|returned`; `returned` = has at least one return), `method`,
   `q` (matches invoice number prefix, customer name `ILIKE`, customer phone, or SKU on a line),
   `limit` (default 50, max 200), `offset`.
   `total_count` = full match count (window function `count(*) OVER ()`).
   - `SECURITY INVOKER` is fine **only if** RLS already limits cashiers to their own sales
     (policy `sales_select_own_or_back_office`). Check it; keep that behaviour: cashiers see
     their own sales, managers/admins see all. Tailors see nothing.
   - Order by `created_at DESC`.
   - Add a trigram or plain index only if needed (`CREATE INDEX IF NOT EXISTS`).

2. **`sale_detail(p_sale_id UUID)`** → JSON: header, `lines` (from `sale_lines`, with
   `returned_quantity` per line), `payments` (all directions, including refunds from returns),
   `returns` (number, date, reason, refund total, method). Same visibility rules as above.

Tests (~12): filters by date, status, method, `q` by invoice / phone / SKU; paging and
`total_count`; a cashier sees only own sales; a tailor sees none; draft visible to its cashier;
detail shows returned quantities and refund payments.

## App

1. `salesService.search(filters, page)` and `salesService.detail(id)` calling the functions.
2. **List**: filters bar (date preset — reuse `src/lib/reportDates.ts` if P5-02 is merged,
   otherwise create it the same way —, status, payment method, search box with 300 ms debounce),
   table with paging (50 per page, "Showing 51–100 of 834"). `useQuery` with
   `placeholderData: keepPreviousData`.
3. **Detail** modal: lines with returned quantity, payments (in and out), returns list,
   buttons kept from today: **Reprint receipt** (`ReceiptPrint`), **Return / exchange**
   (`ReturnModal`), and for drafts **Complete draft** and **Delete draft**.
   - Completing a draft today loads it into the cart and deletes the draft after checkout:
     keep that flow, but the draft's lines must be loaded from `sale_detail`, not `state.sales`.
4. **Export CSV** of the current filter (fetch pages of 200 until done, max 5,000 rows, then
   warn). Use `src/lib/csv.ts` if present (P5-02); otherwise create it as described there.
5. After a return, invalidate the list and detail queries.
6. Remove all reads of `state.sales` from the transactions components. Leave the context itself alone.

## Done when
All guide checks pass; transactions screen works with 0 sales and with paging over 50+ sales
(make them with a small SQL seed in your local database, not committed).
