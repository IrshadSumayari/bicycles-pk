# P5-08 Backups, connection status and paper fallback

**Branch:** `chore/resilience`
**Files:** new `src/components/layout/ConnectionStatus.tsx`, `src/lib/connection.ts` (+ test),
`src/components/layout/Header.tsx`, new `docs/operations/BACKUP_AND_RESTORE.md`,
new `docs/operations/OFFLINE_PROCEDURE.md`, new `scripts/backup.ps1` and `scripts/restore-rehearsal.ps1`,
`package.json` scripts.
**No migration.**

## Why
The shop runs on one internet connection and a hosted Supabase project. Staff need to know
immediately when the till is offline (so they don't press Pay twice or lose a sale), the owner
needs a tested backup, and there must be a written paper procedure for outages.

## 1. Connection status (app)
- `src/lib/connection.ts`: a small store (`useSyncExternalStore`) combining
  `navigator.onLine` events with a **health check** every 30 s (and immediately on the
  `online` event): a cheap call such as `supabase.from('app_settings').select('id').limit(1)`
  with a 5 s timeout (`AbortController`). States: `online`, `slow` (> 2 s), `offline`.
  Pure state-transition logic in a function you unit-test (`nextState(prev, event)`).
- `ConnectionStatus.tsx` in the header: green dot (hidden text), amber "Slow connection",
  red "Offline — use the paper sales book". Tooltip with last successful check time.
- `CheckoutModal`: when offline, disable **Pay** with the message above. When a `post_sale`
  call fails with a network error, show: "We could not confirm this sale. Check the
  Transactions screen before taking payment again." — safe because `post_sale` is idempotent
  (the same `request_id` must be reused if the cashier retries: verify the modal keeps the
  same request id for retries of the same basket, fix it if not, and add a test if the logic
  is in a pure function).
- TanStack Query: set `networkMode: 'online'` defaults and `retry` 2 for queries, 0 for mutations
  (check `src/lib/queryClient.ts`).

## 2. Backups (docs + scripts)
`docs/operations/BACKUP_AND_RESTORE.md`, written for the owner (plain language), covering:
- Supabase plan backups (daily backups on Pro, Point-in-Time Recovery as an add-on); what the
  free plan does **not** give; recommendation to be on Pro before go-live.
- Weekly own backup: `scripts/backup.ps1` runs `npx supabase db dump` for schema and data
  (`--data-only`) against the linked project into `backups/<date>/` (git-ignored; add to
  `.gitignore`), and reminds to copy the folder to an external drive / cloud storage.
  The DB password comes from an environment variable, never from the script file.
- Storage (product images, later) is **not** in the DB dump: document how to download the
  bucket.
- **Restore rehearsal** (`scripts/restore-rehearsal.ps1`): start local Supabase, reset, load the
  latest dump into the local database (`psql` via `npx supabase db ...` or `docker exec`), then
  run a few sanity queries (count sales, sum of today's payments, stock rows) and print them.
  The doc says: do this once a month and write the date in a log table in the doc.
- npm scripts: `"backup": "powershell -File scripts/backup.ps1"`,
  `"restore:rehearsal": "powershell -File scripts/restore-rehearsal.ps1"`.

## 3. Paper procedure
`docs/operations/OFFLINE_PROCEDURE.md` (one printable page, English with short Urdu headings):
- When the red "Offline" shows: use the numbered paper sales book (carbon copy); write item,
  size, price, payment method; cash only or card on the standalone card machine.
- No returns or tailoring deliveries while offline (unless the paper slip shows the balance).
- When back online: a manager enters each paper sale on the POS with the note "Paper #123"
  (the `notes` field), in order, then files the book. Stock and cash then match.
- Who to call (placeholders for names/numbers).

## Done when
All guide checks pass; unit tests for `connection.ts` cover online → slow → offline → online;
both scripts run on Windows PowerShell 5.1 without errors against local Supabase (the backup
script may target local with a `-Local` switch for testing). Report the rehearsal output.
