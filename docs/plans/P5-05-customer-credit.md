# P5-05 Customer accounts: credit ledger, statements, collecting payments

**Branch:** `feat/customer-credit`
**Migration:** `supabase/migrations/20261024000300_customer_credit_ledger.sql`
**Test file:** `supabase/tests/database/customer_credit.test.sql`
**Files:** `src/components/customers/CustomerManager.tsx`, `CustomerDetailModal.tsx`,
new `src/components/customers/CollectPaymentModal.tsx`, new `src/components/customers/CustomerStatement.tsx`,
`src/lib/services.ts`, `src/lib/queryClient.ts`.

## Why
Store credit ("udhaar") is common. Today `customers.credit_used` is a single counter changed by
`post_sale`, `post_return`, `post_exchange` and `record_tailoring_payments`. There is **no way to
record a customer paying off their balance**, no history, and no statement to show them.

## Database

1. **`customer_ledger`** (append-only, `prevent_ledger_changes` trigger):
   `id BIGINT identity PK, customer_id UUID NOT NULL, entry_type TEXT CHECK IN
   ('opening','sale_credit','return_credit','tailoring_credit','payment','adjustment'),
   amount NUMERIC(14,2) NOT NULL` (positive = customer owes more, negative = owes less),
   `sale_id, return_id, tailoring_order_id, payment_id UUID NULL, note TEXT,
   created_by UUID DEFAULT auth.uid(), created_at TIMESTAMPTZ DEFAULT now()`.
   Index `(customer_id, created_at)`. RLS: select for counter staff (`is_counter_staff()`); no writes.

2. **Keep `customers.credit_used` as the cached balance**, but make it follow the ledger:
   an `AFTER INSERT` trigger on `customer_ledger` does
   `UPDATE customers SET credit_used = credit_used + NEW.amount`.
   Then change the four places that update `credit_used` directly so they **insert a ledger row
   instead** (`CREATE OR REPLACE` those functions in this migration — copy each function body
   from its latest migration and change only those lines):
   - `post_sale` (credit tender) → `sale_credit`, + amount
   - `post_return` / `post_exchange` (refund to credit) → `return_credit`, − amount
   - `record_tailoring_payments` (credit tender) → `tailoring_credit`, + amount
   Search all migrations for `credit_used` to be sure you found every place, and use the
   **latest** definition of each function (later migrations override earlier ones).

3. **Backfill**: for every customer with `credit_used <> 0`, insert one `opening` row equal to the
   current value **without** firing the balance trigger twice (e.g. set `credit_used = 0` first,
   then insert, in the migration as superuser). Must be safe to run twice (skip customers that
   already have an `opening` row).

4. **`post_customer_payment(p jsonb)`**: `request_id`, `customer_id`, `payments`
   (`[{method: cash|card|digital, amount, tendered?, reference?, card_last4?}]`), `note`.
   Counter staff only. Rejects `credit`/`exchange` methods, non-positive amounts, and paying more
   than the balance. Inserts `payments` rows (add nullable column `payments.customer_id UUID`;
   cash goes into the shift automatically via the existing trigger) and one ledger row
   `payment` with −total. Returns `{ receipt_no: 'PAY-000001', balance, paid }`
   (new sequence `customer_payment_no_seq`; store the number in a small `customer_payments`
   header table or in `payments.reference` — choose the header table, append-only).

5. **`adjust_customer_balance(p_customer UUID, p_amount NUMERIC, p_reason TEXT, p_request_id UUID)`**
   admins/managers only, reason required (write-off, correction).

6. **`customer_statement(p_customer UUID, p_from DATE, p_to DATE)`** → JSON:
   customer header, `opening_balance` (sum before `p_from`), `entries` (date, type, document
   number — invoice / return / TLR / PAY —, debit, credit, running balance), `closing_balance`.

7. **`customers_with_balance(p_limit, p_offset)`** → customers with `credit_used > 0`, oldest unpaid
   date, last payment date; for a "who owes us" list.

Tests (~16): credit sale adds to balance and ledger; return to credit reduces; tailoring
credit tender adds; payment reduces, cash appears in the shift; overpay refused; credit/exchange
method refused; retry safe; cashier can collect, tailor refused; adjustment manager-only with
reason; statement running balance and opening balance; backfill created one `opening` row and the
balance did not double; `credit_used` equals `sum(ledger)` for every customer at the end.

## App
1. Customer list: column **Balance** and filter **Owes money** (uses `customers_with_balance`).
2. Customer detail: balance card with **Collect payment** (opens `CollectPaymentModal`: amount,
   method, reference; reuse the tender inputs style of `CheckoutModal`), **Statement**
   (date range, printable, WhatsApp share link with a short text summary — reuse the
   `wa.me` approach of `whatsappReadyLink` in `src/lib/tailoring.ts`), and for managers
   **Adjust balance**.
3. Print a small payment receipt after collecting (reuse `ReceiptPrint` styling or a simple
   printable block).
4. Replace `CustomerDetailModal`'s use of `state.sales` with a query of that customer's sales
   (`search_sales` from P5-03 if merged; otherwise a `salesService.byCustomer(id, limit 20)`).
5. Invalidate `queryKeys.cashShift` after a cash collection.

## Done when
All guide checks pass; for every customer `credit_used = sum(customer_ledger.amount)` (assert this
in the test).
