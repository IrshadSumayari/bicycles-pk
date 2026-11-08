# P9-01 Online orders: database

**Branch:** `feat/web-orders-db`
**Needs:** P7-01 merged. P8-01 merged is assumed for customer sign-in (`customer_accounts`).
**Migration:** `supabase/migrations/20261028000000_online_orders.sql`
**Test files:** `supabase/tests/database/online_orders.test.sql`, `supabase/tests/database/online_orders_concurrency.test.sql`
**Scope:** database and types only.

## Context
- One stock pool: `stock_balances(on_hand, reserved)`, `stock_reservations` (channel `web`,
  `expires_at`, status `active|consumed|released|expired`), `post_stock_movement(...)` is the only way
  stock changes, `lock_stock_balance(location, variant)` locks a balance row.
- Locations: shop floor, stockroom, workroom, and an `ONLINE` location (kind `online`).
  Online orders reserve from **sellable locations** (`shop_floor`, `stockroom`, `online`), the location
  with most available stock first; one order line may need two reservations if split — keep it simple:
  reserve the whole line from one location; if none has enough, refuse with "sold out".
- Decision D16: unpaid online orders hold stock **30 minutes** (setting
  `app_settings.online_hold_minutes`, default 30); cash-on-delivery orders hold until staff confirm
  or cancel.

## Database
1. **`online_orders`**: `id, order_no ('WEB-000001'), request_id UUID UNIQUE, account_id,
   customer_id, status ('pending_payment','placed','confirmed','packed','ready_for_pickup',
   'shipped','delivered','cancelled','expired'), payment_status ('unpaid','paid','refunded',
   'partially_refunded','cod'), fulfilment ('pickup','delivery'), contact_name, phone, email,
   address JSONB (line1, line2, city, postal_code), delivery_fee, subtotal, discount, tax, total,
   tracking_no, courier, notes_customer, notes_staff, sale_id (set at fulfilment),
   expires_at, created_at, updated_at, cancelled_reason`.
2. **`online_order_lines`**: `id, order_id, line_no, variant_id, description, sku, size, color,
   quantity, unit_price, total, reservation_id`.
3. **`online_order_events`** (append-only): status changes with `public_message`.
4. **`online_payments`**: `id, order_id, provider, provider_ref UNIQUE, amount, status
   ('initiated','paid','failed','refunded'), raw JSONB, created_at` — written only by the
   service role (P9-02 webhook) and staff refund functions.
5. **Settings**: `online_hold_minutes INT DEFAULT 30`, `delivery_fee NUMERIC DEFAULT 250`,
   `free_delivery_over NUMERIC NULL`, `cod_enabled BOOL DEFAULT true`, `cod_max_total NUMERIC NULL`.

## Functions
- **`quote_online_order(p jsonb)`** (anon and authenticated): lines `[{variant_id, quantity}]`,
  fulfilment → server prices from published variants only, delivery fee, tax (same tax rule as
  `quote_sale`: reuse its helpers, do not copy logic you can call), availability per line.
  No reservation. Unpublished/inactive variants → error naming the item.
- **`create_online_order(p jsonb)`** (authenticated customer account only — not staff, not anon):
  idempotent by `request_id`; re-prices on the server (ignore client prices), validates
  contact/phone (normalise) and address for delivery, `payment_method` `card`, `easypaisa`
  (both paid online through the Easypaisa gateway, see P9-02) or `cod` (refuse `cod` if disabled or
  over `cod_max_total`). Store the chosen method on the order (`payment_method` column). Locks balances **in variant id order**,
  creates `web` reservations (`expires_at = now() + hold` for `card`/`easypaisa`, NULL for `cod`), increases
  `reserved`. Status `pending_payment` (card/easypaisa) or `placed` (cod). Links/creates `customers`
  from the account (only link to an existing customer if the account is already linked).
  Returns order number, totals, `expires_at`.
- **`expire_online_orders()`** (service role / `pg_cron` every minute): for `pending_payment`
  orders past `expires_at`: release reservations (status `expired`, decrease `reserved`), status
  `expired`, event. Uses `FOR UPDATE SKIP LOCKED`. Schedule it with `pg_cron` in the migration
  (`cron.schedule('expire-online-orders', '* * * * *', ...)`) guarded so re-running doesn't duplicate.
- **`mark_online_order_paid(p_order UUID, p_provider TEXT, p_provider_ref TEXT, p_amount NUMERIC, p_raw JSONB)`**
  (service role only): exactly once per `provider_ref`; amount must equal total; if the order is
  `pending_payment` → `placed` + `paid`, extend reservation (clear `expires_at`); if the order already
  **expired** → record the payment with a flag `needs_refund` (new column on `online_payments`) and an
  event, **do not** fulfil (test 21 in the development plan).
- **Customer**: `my_online_orders()`, `my_online_order(p_order_no)` (public fields + public events),
  `cancel_my_online_order(p_order_no)` while `pending_payment`/`placed` (releases reservations; if
  paid → `payment_status` stays `paid` and status `cancelled` with `needs_refund` for staff).
- **Staff** (counter staff): `list_online_orders(p jsonb)`, `online_order_detail(id)`,
  `advance_online_order(p jsonb)` with allowed transitions
  `placed→confirmed→packed→ready_for_pickup|shipped→delivered`; at **packed** (fulfilment) the
  reservations are **consumed** and stock deducted exactly once by creating a sale through the same
  internals as `post_sale` with channel `web` (payments: an online card payment as method `card`, an Easypaisa wallet payment as
  method `digital` with bank name `Easypaisa`, both with the provider reference, or COD collected at delivery/pickup as `cash`/`card` via `collect_cod_payment`).
  Explain in the report how you reused `post_sale` (preferred: an internal function shared by both).
- `cancel_online_order(p jsonb)` (staff, reason required): releases reservations or, after
  fulfilment, requires the returns flow (`post_return`) instead — refuse with that message.
- `record_online_refund(p jsonb)` (manager): marks `online_payments` refunded (the money is sent in
  the provider's dashboard), updates `payment_status`, event.

## Tests
`online_orders.test.sql` (~25): quote ignores client prices; unpublished variant refused; create
reserves and reduces available (and `public_catalog` band); retry returns same order; staff and anon
cannot create; expiry releases stock; late payment on expired order flagged `needs_refund`; duplicate
payment notification recorded once; amount mismatch refused; customer A cannot read B's orders;
staff notes not in customer results; packing deducts stock once and consumes reservations; cancel
before packing releases; COD limit; event trail.
`online_orders_concurrency.test.sql`: last unit — reserve online then try `post_sale` of the same
unit at the till → till refused "sold out"; and the reverse order. (True parallel tests can't run in
pgTAP; document a manual two-session `psql` check in the test file header and in your report.)

## Done when
All guide checks pass; types regenerated.
