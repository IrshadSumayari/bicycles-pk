# Agent guide: how to work on this repository

Read this file completely before starting any plan in `docs/plans/`.
Each plan is one pull request. Do **one plan at a time**.

## 1. The project in one paragraph

A point-of-sale system for a clothing store with in-house tailoring (Pakistan, currency PKR).
React 19 + TypeScript 6 + Vite 8 + Tailwind CSS 4 in the browser; Supabase (Postgres 17,
Auth, Edge Functions) as the only backend. **All business rules live in Postgres functions**
(`SECURITY DEFINER`, one transaction each). The browser sends intent and shows results; it
never decides prices, stock, totals or permissions. Read `docs/DEVELOPMENT_PLAN.md` for the
business context.

## 2. Setup and the checks you must run

Requirements: Node 22, Docker Desktop running.

```bash
npm ci
npm run db:start        # local Supabase in Docker, applies every migration
npm run db:reset        # rebuild the local database from migrations (run after adding one)
npm run test:db         # pgTAP database tests (supabase/tests/database/*.test.sql)
npm run db:types        # regenerate src/lib/database.types.ts after any schema change
npm test                # Vitest unit tests (src/**/*.test.ts)
npx tsc -b              # type-check
npm run lint            # ESLint: must report 0 errors (warnings are allowed)
npm run build
npm run test:e2e        # Playwright smoke tests (optional locally, CI runs them)
```

For the app against the local database, create `.env.local` (git-ignored):
```
VITE_SUPABASE_URL=<API_URL from `npx supabase status`>
VITE_SUPABASE_ANON_KEY=<ANON_KEY from `npx supabase status`>
```
Then `npx vite`. The first account created on the login page becomes the admin.

**Definition of done for every plan:** all of these pass, with no new lint errors:
`npm run db:reset && npm run test:db`, `npm test`, `npx tsc -b`, `npm run lint`, `npm run build`.
Run `npm run test:db` **twice** in a row: tests must not depend on a fresh sequence.

## 3. Database conventions (follow exactly)

- **New migration per plan**: `supabase/migrations/<YYYYMMDDHHMMSS>_<snake_name>.sql`.
  The timestamp must be later than every existing file (latest is `20261023000200`).
  **Never edit an existing migration**: they may already run in production. Fix forward.
- Migrations must be re-runnable: `CREATE TABLE IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`,
  `DROP POLICY IF EXISTS` before `CREATE POLICY`, `DROP TRIGGER IF EXISTS` before `CREATE TRIGGER`.
- Money: `NUMERIC(14,2)`. Quantities: `NUMERIC(18,6)`. Never floats.
- Every table: `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` plus explicit policies.
  Write access normally goes **only** through functions (no INSERT/UPDATE policies).
- History tables (ledgers, events, documents) are append-only:
  `CREATE TRIGGER ... BEFORE UPDATE OR DELETE ... EXECUTE FUNCTION public.prevent_ledger_changes();`
- Functions that change data:
  - `LANGUAGE plpgsql SECURITY DEFINER SET search_path = public`
  - check the role first; raise `USING ERRCODE = '42501'` for permission errors
  - take a `request_id` and use `public.idempotency_begin(request_id, 'name')` /
    `public.idempotency_finish(request_id, result)` so a retry returns the first result.
    Call `idempotency_begin` **before** other validation.
  - lock rows in a consistent order (by id) with `FOR UPDATE`
  - end with `REVOKE ALL ... FROM PUBLIC, anon;` and `GRANT EXECUTE ... TO authenticated;`
    (internal helpers: revoke from `authenticated` too)
- Error messages are shown to shop staff: plain English, say what to do
  (e.g. `'Open a cash shift before taking or refunding cash'`).

### Helpers that already exist (use them, do not re-create)
| Helper | Purpose |
|---|---|
| `current_app_role()` | role of the signed-in **active** staff member, or NULL |
| `has_app_role(ARRAY['admin','manager'])` | role check |
| `is_staff()`, `is_counter_staff()` | any active staff / admin+manager+cashier (not tailors) |
| `is_branch_member(branch_id)` | admins: all branches |
| `default_branch_id()` | the single branch for now |
| `idempotency_begin/finish` | retries (see above) |
| `lock_stock_balance(location, variant)` | row-lock a balance |
| `post_stock_movement(location, variant, qty, type, channel, ref_type, ref_id, unit_cost, reason, roll_id)` | the **only** way stock changes; internal |
| `quote_sale(json)`, `post_sale(json)` | checkout; server prices, promotions, tax, stock, payments |
| `post_return(json)`, `post_exchange(json)` | returns/exchanges |
| `generate_invoice_number()` | INV-000001 numbers |
| `tailoring_order_totals(order_id)` | total / paid / balance |

### Main tables (see migrations for full columns)
`branches, locations, branch_memberships, users (staff), customer_accounts (website logins),
customers (phone normalised to +92…, unique), product_styles, product_variants, variant_costs
(managers only), barcodes, fabric_rolls, stock_balances, stock_movements, stock_reservations,
sales (+ legacy JSON items kept for old screens), sale_lines, payments (direction in/out;
sale_id / return_id / tailoring_order_id; cash_session_id), returns, return_lines,
cash_sessions, cash_movements, goods_receipts(+lines), stock_counts(+lines), discounts
(promotions), app_settings, garment_types, wearer_profiles, measurement_sets,
tailoring_orders, tailoring_items, tailoring_charges, tailoring_materials,
material_custody_events, tailoring_job_events`.

### Roles
`admin` (everything), `manager` (back office, approvals), `cashier` (till, returns within
window, tailoring orders), `tailor` (only `tailor_queue()`; must never see prices, costs or
phone numbers). Website customers have **no** staff row and no access to staff tables.
Anonymous visitors (`anon`) have **no table access** (only the `public_catalog` view).

### Known gotchas
- Auth admin API sets `app_metadata` in an UPDATE after insert (see migration
  `20261023000200`): never rely on `raw_app_meta_data` inside an INSERT trigger only.
- Sequences don't roll back in tests: match numbers with regex (`'^INV-[0-9]{6}$'`).
- Every cash payment needs the cashier's open shift (trigger on `payments`). In tests call
  `SELECT FROM open_cash_session(0);` as the acting user before taking cash.

## 4. Database tests (pgTAP)

One file per plan in `supabase/tests/database/<name>.test.sql`. Copy the pattern of
`checkout.test.sql`:
```sql
BEGIN;
SELECT plan(N);
INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
  ('00000000-0000-0000-0000-0000000xx001', 'admin@t.local', '{"name":"Admin"}', '{}'),            -- first user = admin
  ('00000000-0000-0000-0000-0000000xx002', 'cashier@t.local', '{"name":"C"}', '{"account_type":"staff"}');
UPDATE public.users SET active = true WHERE id = '...002';
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"...001","role":"authenticated"}';
-- fixtures through the real functions (save_style, post_sale, ...)
SELECT is(...), throws_ok(...), lives_ok(...);
SELECT * FROM finish();
ROLLBACK;
```
Use unique UUID prefixes per file. Test permissions (who is refused) as well as results.
To go back to superuser inside a test: `RESET ROLE; SET LOCAL "request.jwt.claims" = '';`.

## 5. App conventions

- Data access lives in `src/lib/services.ts` (`xxxService` objects) or a domain file such as
  `src/lib/tailoring.ts`. Components never call `supabase` directly.
- Server data: **TanStack Query** (`useQuery`, `queryKeys` in `src/lib/queryClient.ts`).
  The old `src/context/SupabaseAppContext.tsx` still holds products/customers/settings; do not
  add new server data to it.
- Errors: `getErrorMessage(error)` from `src/lib/errors.ts`; messages via `swalConfig`
  (`src/lib/sweetAlert.ts`).
- Money in the UI: `` `${state.settings.currency} ${n.toFixed(2)}` ``. Rounding: `roundMoney` from `src/lib/pricing.ts`.
- Styling: existing Tailwind utility classes (`card`, `btn btn-primary btn-md`, `input`,
  `select`, `textarea`, `modal-overlay`/`modal`/`modal-header`/`modal-body`/`modal-footer`,
  `table`/`table-header`/`table-cell`). Look at `src/components/tailoring/OrdersPanel.tsx`.
- TypeScript: no `any` (lint error). Unused names may start with `_`.
- Pure logic (calculations, formatting, parsing) goes in `src/lib/*.ts` with Vitest tests.
- Never put secrets or the service-role key in `VITE_` variables. Server secrets belong in
  Edge Functions (`supabase/functions/`).

## 6. Git and handing work back

- Start from the latest `develop`: `git checkout develop && git pull`.
- Branch name: the one given in the plan (e.g. `feat/reports-db`).
- Commit with clear messages describing *what changed and why*. Do **not** add AI-tool
  attribution lines or tool names to commits, branches or files.
- **Do not push and do not open PRs.** When done, report back: branch name, summary, the
  output of the checks in section 2, anything you could not finish or verify, and any
  decision you had to make. The repository owner will have it reviewed, pushed and merged.
- Do not modify files outside the plan's scope. Do not commit `.env*`, `storefront/`,
  `docs/lawrencepur-*`, `.claude/`.

## 7. Order of plans

See `docs/plans/README.md`. Plans build on each other; do them in order unless a plan says
it is independent.
