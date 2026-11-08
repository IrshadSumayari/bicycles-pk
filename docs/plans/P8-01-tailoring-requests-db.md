# P8-01 Tailoring requests: database and customer login

**Branch:** `feat/web-tailoring-db`
**Needs:** P7-03 merged (website app exists).
**Migration:** `supabase/migrations/20261027000000_tailoring_requests.sql`
**Test file:** `supabase/tests/database/tailoring_requests.test.sql`
**Scope:** database, storage, `supabase/config.toml` auth settings, types. No UI.

## Context
- Website sign-ups already create a `customer_accounts` row (never a staff `users` row);
  see migrations `20261020000000_branches_and_accounts.sql` and `20261023000200_fix_staff_signup_routing.sql`.
  `customer_accounts.customer_id` links to a shop `customers` record **only after the phone is verified**;
  a trigger stops customers from changing `customer_id` / `phone_verified` themselves.
- Tailoring orders (`create_tailoring_order`) are staff-only and stay that way. A website request is
  a separate record that staff review, quote and convert.

## Auth
- Customers sign in with **email OTP** (Supabase built-in, no SMS cost). Phone OTP can be enabled
  later when an SMS provider is set up — write the code so either works (no assumption that
  `auth.users.email` exists).
- `link_customer_account()` (authenticated, customer only): if `auth.users.phone_confirmed_at` is set
  and the phone matches a `customers.phone` (normalised with `normalize_phone`), link it and set
  `phone_verified`. Otherwise, staff can link from the POS: `staff_link_customer_account(p_account UUID, p_customer UUID)`
  (counter staff, after checking the person in the shop). If no customer exists, the first
  request creates one (see below).

## Database
1. **`tailoring_requests`**: `id, request_no ('REQ-000001'), account_id (customer_accounts.id),
   customer_id NULL, garment_type (FK garment_types.code), quantity INT 1–10,
   fabric_source ('store','customer','undecided'), fabric_variant_id NULL, design_notes TEXT
   (max 2000), preferred_date DATE NULL, appointment_wanted BOOL, status ('submitted','reviewing',
   'quoted','accepted','declined','cancelled','converted'), quote JSONB NULL
   ({charges:[{description, amount}], fabric:{...}, total, deposit_required, promised_date, valid_until}),
   staff_notes TEXT (never visible to customers), tailoring_order_id NULL, created_at, updated_at`.
2. **`tailoring_request_photos`**: `id, request_id, storage_path, created_at` (max 5 per request).
3. **`tailoring_request_events`** (append-only): `id, request_id, event, public_message TEXT NULL,
   created_by, created_at`. Only events with a `public_message` are shown to the customer.
4. **`appointments`**: `id, request_id NULL, account_id NULL, customer_id NULL, starts_at,
   duration_minutes DEFAULT 30, purpose ('measurement','trial','pickup'), status ('requested',
   'confirmed','cancelled','done'), notes`. No double booking: exclusion constraint or a check in the function.
5. **Private bucket** `tailoring-photos` (not public): customers may upload to
   `requests/<auth.uid()>/...` only (storage policy on the first path segment), max 5 MB, images only;
   staff (counter staff) can read all; customers read only their own folder.
6. **Customer functions** (authenticated, must **not** be staff; refuse staff with a clear message):
   - `submit_tailoring_request(p jsonb)` (idempotent with `request_id`): validates garment type is
     active, lengths, photo paths belong to the caller's folder, quantity; **rate limit**: max 5
     open requests per account and max 10 submissions per day (count rows) → error message.
   - `my_tailoring_requests()` → own requests with quote and **public** events only (no `staff_notes`).
   - `respond_to_quote(p_request UUID, p_accept BOOL)` — only in `quoted` status and before `valid_until`.
   - `cancel_tailoring_request(p_request UUID)` — while `submitted` / `reviewing` / `quoted`.
   - `request_appointment(p jsonb)` and `my_appointments()`; slots from `appointment_slots(p_date)`
     (opening hours stored in `app_settings.appointment_hours JSONB`, default Mon–Sat 11:00–20:00,
     30-minute slots, minus confirmed/requested appointments).
7. **Staff functions** (counter staff):
   - `list_tailoring_requests(p jsonb)` (status filter, paging), `tailoring_request_detail(id)`
     (includes photos as storage paths and staff notes).
   - `update_tailoring_request(p jsonb)`: status `reviewing`, staff notes, public message (adds event).
   - `quote_tailoring_request(p jsonb)`: sets quote, status `quoted`, public event.
   - `convert_tailoring_request(p jsonb)`: only when `accepted`; staff provide wearer + measurements
     (taken in the shop or entered from the customer) and payments; calls
     `create_tailoring_order` with the quoted charges (link the customer, creating it from the
     account's name/phone if needed), sets `converted` and `tailoring_order_id`. Idempotent.
   - `confirm_appointment` / `cancel_appointment`.
8. **Progress for customers**: `my_order_progress(p_request UUID)` → for converted requests, the
   order number, item stages mapped to customer-friendly labels (`received`, `in work`, `ready`,
   `delivered`), promised date and balance due — nothing else (no tailor names, no internal notes).

## Tests (~25)
Customer A cannot read B's requests, photos (storage), appointments or progress; staff notes never
appear in customer function results (check JSON keys); a staff user calling customer functions is
refused; a customer calling staff functions is refused; anon refused everywhere; rate limit;
photo path outside own folder refused; quote → accept → convert creates a tailoring order with the
quoted charges and links the request; converting twice returns the same order; expired quote
cannot be accepted; appointment double booking refused; slots exclude booked times.

## Done when
All guide checks pass; types regenerated.
