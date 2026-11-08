# P6-01 Data migration and go-live

**Branch:** `feat/go-live-import`
**Needs:** P5-05 merged (customer ledger with `opening` entries).
**Migration:** `supabase/migrations/20261025000000_go_live_import.sql`
**Test file:** `supabase/tests/database/go_live_import.test.sql`
**Files:** new `src/components/settings/GoLiveImport.tsx`, `src/lib/goLiveImport.ts` (+ test),
`src/lib/services.ts`, new `docs/operations/GO_LIVE_CHECKLIST.md`.

## Why
On day one the shop has: open tailoring orders taken on paper (with deposits already paid),
customers who owe money, and stock already on the shelves. Products and stock can already be
imported (`ProductImportPanel` + opening stock in `save_style`). This plan adds the other two
imports and a checklist.

## Database
1. **`import_opening_balances(p jsonb)`** admin only: `request_id`, `rows: [{name, phone, amount, note}]`.
   Finds or creates each customer by normalised phone (reuse the existing phone normalisation
   function/trigger — search migrations for `+92`), inserts a `customer_ledger` row `opening`
   (refuse if the customer already has an `opening` row — return it in a `skipped` list with
   the reason). Returns `{created_customers, balances, skipped: [{row, reason}]}`. One transaction:
   any **invalid** row (bad phone, amount ≤ 0) fails the whole import with the row number in the message.

2. **`import_open_tailoring_order(p jsonb)`** admin/manager: like `create_tailoring_order` but:
   - `paper_ref` (the paper slip number, required, unique — new nullable unique column on
     `tailoring_orders`), `order_date` (in the past), `deposit_already_paid` amount;
   - the deposit was paid before go-live, so it must not appear in today's cash or reports.
     Add method value `'opening'` to the `payments_method_check`
     constraint (keep all existing values), never accepted by `post_sale`, `post_tailoring_payment`
     or `post_customer_payment` (add explicit refusals and tests), and excluded from
     `report_tenders` (update that function with `CREATE OR REPLACE` if P5-01 is merged).
   - status of items may be given (`cutting`, `stitching`, `ready`) so the workshop queue is correct.
   Reuse `create_tailoring_order` internals; do not copy the whole body if you can call it and
   then adjust (explain your choice in the report).

Tests (~12): balances import creates customers and ledger rows; duplicate opening skipped;
invalid phone aborts all; tailoring import with deposit shows correct balance; the `opening`
payment is not in the cash shift and not in tenders; `post_sale` refuses method `opening`;
duplicate `paper_ref` refused; cashier refused.

## App
- `src/lib/goLiveImport.ts`: parse CSV (reuse `src/lib/csvImport.ts` patterns) for
  balances (`name,phone,amount,note`) and tailoring orders (one row per item:
  `paper_ref,order_date,customer_name,phone,garment_type,promised_date,stitching_charge,
  deposit_paid,status,notes` + measurement columns named by garment field key). Validate and
  return row errors **before** sending. Unit tests for parsing and validation.
- `GoLiveImport.tsx` (admin, under Settings → "Go-live import"): download template CSV,
  upload, preview table with errors highlighted, **Import** button, result summary.

## Checklist document
`docs/operations/GO_LIVE_CHECKLIST.md`: the ordered steps for the day before and the first day:
create Supabase Pro project, apply migrations (`npx supabase db push`), deploy edge functions,
set Auth settings (disable public sign-ups for staff, site URL), create admin, create staff
accounts, settings (tax, return window, deposit %, receipt text), import products + opening
stock, print labels, import customer balances, import open tailoring orders, stock count of a
sample, test sale/return/shift close with real printer and scanner, backup + restore rehearsal
(P5-08), paper fallback books ready, cashier training points. Each step with "who" and a
checkbox.

## Done when
All guide checks pass; importing the sample CSVs in `docs/operations/samples/` (create 2 small
example files, fake names and numbers) works from the UI on local Supabase.
