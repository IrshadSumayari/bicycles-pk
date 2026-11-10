# Salesperson commissions

Added 23 October 2026. One rule per salesperson per branch: **fixed amount per invoice** or **percentage**. A rule uses one of these options at a time.

## Use

1. An administrator creates the salesperson as an active staff account under Users. Eligible roles are cashier, manager and administrator; non-admins must belong to the selling branch.
2. Open **Commissions → Salesperson rules**, choose the branch, set a fixed amount or percentage, enable it and save. Rules default to disabled; no existing employee receives an invented rate.
3. At checkout select **Salesperson (commission)**. The cashier who processes payment remains separately recorded. Leaving the selection blank means no commission. The same selection is available for an exchange's replacement invoice.
4. Use Commissions to filter by branch, dates and salesperson. Managers see the branch; cashiers can only see their own statement. Earned, reversed and paid amounts refer to the selected period; outstanding includes all dates.
5. After paying a salesperson outside the app, use **Record commission payout** with the payment reference. This records a payment already made; it does not transfer money or withdraw from the till. It cannot exceed outstanding commission. Retrying an unconfirmed payout reuses its saved request reference. Check activity before clearing a saved request.

## Calculation rules

- Fixed: one configured amount for the whole invoice, regardless of item count. Percentage: configured percent of the posted sale-line net amounts after all discounts, excluding tax and free gifts. Zero-value invoices do not earn commission.
- This is invoice-based commission: posted credit invoices earn immediately, even before the customer pays. It is not collection-based commission. Drafts do not earn commission.
- Each invoice snapshots its salesperson, type, rate, eligible sale value and earned commission. Future rule changes do not alter history. Checkout retries do not create another earning; the original salesperson cannot be silently changed on a retry.
- Partial returns reverse the same proportion of the original commission as the returned net sale value, for both fixed and percentage rules. Cumulative rounding ensures a full return reverses exactly the original amount. This applies even to non-restockable returns.
- Returns after a payout can make outstanding commission negative; the debit carries forward. The original payout is preserved. Two payout requests for the same account are serialized and duplicate request IDs are checked against the original payment details.
- An exchange reverses the original invoice's commission and calculates commission on its replacement invoice only if a salesperson is selected for that new invoice.
- Existing historical invoices are not backfilled. Disabling a salesperson's rule keeps their earned commission and statements. Disable staff accounts rather than deleting accounts referenced by commission history.
- Attribution currently applies to POS invoices and replacement invoices posted through checkout. Website orders do not automatically earn a salesperson commission. Services such as assembly or a tune-up sold as POS invoice lines follow the normal POS rule.

## Deployment and verification

Forward migration: `supabase/migrations/20261031000000_sales_commissions.sql`. It adds commission rules, immutable invoice snapshots and an append-only commission ledger, and wraps existing checkout/exchange functions without changing their price, payment or stock checks. Direct browser access to the private base functions is revoked. Rule editing and payout recording require a branch manager or administrator on the server.

The migration was applied to local Supabase after a database backup in `D:\POS\output`. Existing pending local branding and customer-consent migrations were applied first through the normal migration runner. No production deployment or database reset was performed. Review and apply this forward migration in staging/production before deploying the corresponding frontend; take a backup and run the database tests first.

Validation: isolated PostgreSQL tests exercise the new migration; the real local Supabase integration test uses actual checkout, discounts, taxes, refunds, payments and exchanges and rolls back its fixtures. Checkout, returns and customer-credit regression checks also passed using rollback-only fixtures. Some legacy tests assume an empty store; their test-only administrator metadata and phone numbers were adapted in memory for the existing local store, without changing existing production data or the legacy test files.

Run `npm test`, `npm run typecheck`, `npm run build` and, against a prepared test database, `supabase test db`. The new integration test is `supabase/tests/database/commissions.test.sql`. Production concurrency and a staff acceptance exercise remain part of staging sign-off.
