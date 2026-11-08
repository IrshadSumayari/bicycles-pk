# P6-02 FBR invoice integration (conditional)

**Do this plan only after the tax adviser confirms the shop must integrate with FBR
(Tier-1 retailer POS integration) and gives the POS ID and the API credentials.**

**Branch:** `feat/fbr`
**Migration:** `supabase/migrations/20261025000100_fbr_invoices.sql`
**Test file:** `supabase/tests/database/fbr.test.sql`
**Files:** new edge function `supabase/functions/fbr-submit/index.ts`, `src/components/pos/ReceiptPrint.tsx`,
settings UI (FBR section), `src/lib/services.ts`, `docs/operations/FBR.md`.

## Why
Tier-1 retailers in Pakistan must report each sale to FBR in real time and print the FBR invoice
number and QR code on the receipt. Sales must never be blocked by FBR being down: submit
asynchronously and retry.

## Database
1. `fbr_submissions` (one row per sale **and** per return): `id, sale_id NULL, return_id NULL,
   status ('pending','submitted','failed'), attempts INT, fbr_invoice_number TEXT,
   last_error TEXT, payload JSONB, response JSONB, created_at, submitted_at`.
   RLS: managers/admins read; no client writes.
2. Trigger after `post_sale` completes (AFTER INSERT on `sales` where status <> 'draft', and on
   `returns`) inserts a `pending` row with the payload built from `sale_lines` (item code = SKU,
   name, quantity, price, tax rate, tax, discount), buyer NTN/CNIC optional, POS ID from settings.
   Build the payload in a SQL function `fbr_payload_for_sale(sale_id)` so it is testable.
3. Settings (`app_settings`): `fbr_enabled BOOLEAN DEFAULT false`, `fbr_pos_id TEXT`.
   **The API token is NOT stored in the database**: it is an edge-function secret
   (`npx supabase secrets set FBR_TOKEN=...`).
4. Internal function `fbr_mark_result(id, ok, invoice_number, response, error)` callable only by
   the `service_role` (edge function).
5. Draft sales and the internal `exchange` tender are handled as FBR requires (document what you
   assumed in `docs/operations/FBR.md`; leave clear TODOs where the adviser must confirm).

## Edge function `fbr-submit`
- Triggered every minute by `pg_cron` + `pg_net` (or Supabase scheduled function) and also
  callable by managers ("Retry now").
- Picks `pending`/`failed` rows with `attempts < 10` (`FOR UPDATE SKIP LOCKED` via an SQL function),
  posts to the FBR endpoint from env var `FBR_URL` with `FBR_TOKEN`, stores the result.
- Sandbox first: env var `FBR_URL` points to FBR's sandbox; document both URLs in `FBR.md`
  **as given by the adviser** (do not invent them; leave placeholders).
- Unit-test the payload mapping and response parsing with Deno tests or Vitest on a shared pure module.

## App
- Receipt: when the sale has an FBR invoice number, print it and a QR code (use the existing
  barcode approach; add `qrcode` npm package only if needed, pinned version). If still pending,
  print "FBR: pending" — reprinting later shows the number.
- Manager screen: list of failed/pending submissions with retry.

## Tests
pgTAP: payload for a sale with tax and discount; return creates a submission; drafts do not;
cashier cannot read submissions; `fbr_mark_result` refused for `authenticated`.

## Done when
All guide checks pass; with `FBR_URL` pointed at a local mock (a tiny script you run locally),
a sale gets an FBR number on its reprinted receipt.
