# P5-04 Shift history, variances and manager close

**Branch:** `feat/shift-history`
**Migration:** `supabase/migrations/20261024000200_shift_history.sql`
**Test file:** `supabase/tests/database/shift_history.test.sql`
**Files:** new `src/components/reports/ShiftHistory.tsx` (or `src/components/cash/ShiftHistory.tsx`),
`src/lib/services.ts` (`shiftsService` additions), `src/lib/queryClient.ts`, navigation entry.

## Why
Cash shifts exist (`cash_sessions`, `cash_movements`, `open_cash_session`, `close_cash_session`,
`cash_session_summary`, `current_cash_session` in migration `20261022000000_cash_shifts.sql`),
but the owner cannot see past shifts, who was short, or close a shift a cashier forgot to close.

## Database

1. **`list_cash_sessions(p jsonb)`** → `TABLE(id, session_no, user_id, user_name, status,
   opened_at, closed_at, opening_float, cash_sales, refunds, cash_in, cash_out, expected_cash,
   counted_cash, variance, closing_notes, closed_by_name, total_count BIGINT)`.
   Filters: `from`, `to`, `user_id`, `status`, `only_variance` (variance <> 0), `limit`, `offset`.
   Managers/admins see all; a cashier sees only own sessions; tailors refused (`42501`).
   For open sessions compute the running figures with `cash_session_summary`.

2. **`cash_session_detail(p_session_id)`** → JSON: the summary plus every `cash_movements` row
   (time, type, amount, reason, invoice/return/tailoring order number when linked through
   `payment_id`, who). Same visibility.

3. **`force_close_cash_session(p_session_id UUID, p_counted_cash NUMERIC, p_notes TEXT, p_request_id UUID)`**
   Managers/admins only. Closes **another user's** open session exactly like
   `close_cash_session` does (reuse its logic; do not duplicate the arithmetic — refactor
   into an internal `close_cash_session_internal(session_id, counted, notes)` used by both,
   keeping `close_cash_session`'s signature and behaviour unchanged). Notes are required and
   must be prefixed with `'Closed by manager: '`. Idempotent.

4. **Variance alert setting**: add `app_settings.cash_variance_alert NUMERIC(14,2) NOT NULL DEFAULT 500`.
   `list_cash_sessions` returns an extra boolean column `over_limit` (`abs(variance) > setting`).

Tests (~12): list filters, own-only for cashier, tailor refused, detail lists movements with
linked numbers, manager force-close computes expected/variance, cashier cannot force-close,
force-close retry is safe, closing an already closed session raises, `over_limit` flag.

## App

1. **Shift history** screen for managers/admins (put it as a tab in Reports if P5-02 is merged,
   otherwise as its own navigation item "Shifts"): table with filters (date range, cashier,
   "only with difference"), red badge for `over_limit`, row click opens a detail modal with the
   movements list and a **Print** button (simple printable summary, same approach as
   `OrderSlip`'s `printSlip`).
2. Open shifts of other users show **Close for cashier**: modal asking counted cash + notes,
   calls `force_close_cash_session`, then invalidates `queryKeys.cashShift`.
3. Cashiers: in `CashShiftBar`, a "My shifts" link showing their own last 30 shifts (read-only).
4. Settings: number input for the variance alert (admins), next to the other cash settings.
   If P5-06 is already merged, put it in its "Cash & tills" section.

## Done when
All guide checks pass; a manager can find yesterday's short shift in two clicks.
