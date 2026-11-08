# P9-02 Online payment: Easypaisa (card and wallet) and payment notifications

**Branch:** `feat/web-payments`
**Needs:** P9-01 merged, plus Easypaisa merchant **sandbox** credentials from the owner (store ID,
hash key, inquiry API username and password). Without credentials, build everything with the
`mock` provider and leave the Easypaisa adapter tested only against sample payloads; say so in
your report.
**Files:** `supabase/functions/payment-create/index.ts`, `supabase/functions/payment-webhook/index.ts`,
`supabase/functions/payment-check/index.ts`,
shared `supabase/functions/_shared/payments/` (provider adapters + pure helpers), tests,
`docs/operations/PAYMENTS.md`, `supabase/config.toml` (function settings).
**Migration (only if needed):** `supabase/migrations/20261028000100_payment_sessions.sql`.

## Decision (D14, final)
- **Provider: Easypaisa merchant online payment gateway ("Easypay" hosted checkout).** One
  integration gives the customer two ways to pay online:
  - **Credit / debit card** (Visa, Mastercard) on Easypaisa's hosted card page;
  - **Easypaisa mobile wallet** (customer approves in the Easypaisa app / by OTP).
- **Cash on delivery** stays available as the third option (controlled by `cod_enabled` and
  `cod_max_total` from P9-01).
- Card numbers are entered only on Easypaisa's pages. They never reach our website, our
  functions or our database.

## Why
The website redirects the customer to Easypaisa's hosted checkout. Easypaisa then notifies our
server, and only our server decides that an order is paid. It does so by calling
`mark_online_order_paid` with the service role, after **confirming the payment with Easypaisa's
transaction inquiry API**. Never trust the notification body or the browser's return URL alone.

## Design
- **Adapter interface** (`_shared/payments/types.ts`):
  ```ts
  type PayMethod = 'card' | 'wallet';
  interface PaymentProvider {
    name: 'easypaisa' | 'mock';
    createCheckout(order: { orderNo: string; amount: number; currency: 'PKR'; method: PayMethod;
      phone: string; email?: string; returnUrl: string }): Promise<{ redirectUrl: string; formFields?: Record<string, string>; providerRef: string }>;
    // Turns an incoming notification into a *confirmed* status by asking the provider.
    confirm(req: { url: URL; headers: Headers; rawBody: string }): Promise<{ valid: boolean; event?: {
      providerRef: string; orderNo: string; amount: number; status: 'paid' | 'failed' | 'refunded'; raw: unknown } }>;
  }
  ```
  `formFields` exists because hosted checkouts are often started with an auto-submitted POST form
  rather than a plain redirect.
- **Easypaisa adapter** (`_shared/payments/easypaisa.ts`). Implement it from the **official
  Easypaisa merchant integration guide** that comes with the merchant account. Put the guide's
  version and date in `PAYMENTS.md`. Typical shape; **confirm every name against the guide**:
  - Checkout request: store ID, amount (2 decimals), our order reference (= `orderNo`), the
    post-back/return URL, a payment method selector (card vs mobile account), an expiry time
    matching our hold (`expires_at` from P9-01), and a request hash. The hash is computed with the
    merchant hash key exactly as the guide specifies (field order and encryption mode matter), in a
    pure function with unit tests.
  - Notification: Easypaisa calls our **IPN / notification URL**. The handler extracts the order
    reference or transaction reference, then calls the **transaction inquiry API** with our
    credentials. It treats the order as paid only when the inquiry returns a paid/success status
    **and** the amount equals the order total.
  - Map Easypaisa's status codes to `paid` / `failed` / `refunded` in one table-driven function with
    tests. Unknown codes are treated as `failed`, and the raw response is logged.
- **Mock adapter**: HMAC-SHA256 of the raw body with `PAYMENT_WEBHOOK_SECRET`, used for local tests
  and E2E.
- Select the adapter with env `PAYMENT_PROVIDER` (`easypaisa` | `mock`).
- **`payment-create`** (called by the website with the customer's JWT, body `{ orderNo, method }`):
  - Load the order through a security-definer function as that user. It must be theirs, in
    `pending_payment`, and not expired.
  - Create the checkout and store an `online_payments` row `initiated` with `provider = 'easypaisa'`
    and the method (`card` / `wallet`) in `raw` (add a `method` column in the migration if you
    prefer).
  - Return `redirectUrl` (+ `formFields`).
- **`payment-webhook`** (no JWT, so set `verify_jwt = false` in `config.toml` for this function only):
  - Read the raw body first.
  - Call `confirm()`. If it is not valid, return 400/401 and log without secrets.
  - Make it idempotent by `providerRef`, then call `mark_online_order_paid` with the service-role client.
  - Answer quickly with whatever acknowledgement Easypaisa expects.
  - Also handle `failed` (event only) and `refunded`.
- **Return URL**: the website's `/checkout/return` page only **displays** the status by polling
  `my_online_order`. It never marks anything paid.
- **Secrets** live only as function secrets: `PAYMENT_PROVIDER`, `EASYPAISA_STORE_ID`,
  `EASYPAISA_HASH_KEY`, `EASYPAISA_API_USER`, `EASYPAISA_API_PASSWORD`, `EASYPAISA_BASE_URL`
  (sandbox vs live, taken from the guide; do not hard-code), `PAYMENT_WEBHOOK_SECRET`, `SITE_URL`.
  Never return or log `SUPABASE_SERVICE_ROLE_KEY` or any of these.
- **Reconciliation**: a scheduled `payment-reconcile` job is **out of scope**. Document a manual
  daily check in `PAYMENTS.md`: compare the Easypaisa merchant portal with `online_payments`.
  Also add an SQL query that lists `initiated` payments older than the hold time, so staff can
  check each one with the inquiry API.
- **`payment-check`** (counter staff JWT, body `{ orderNo }`): runs the same `confirm()` path via the
  inquiry API for that order's `initiated` payment and applies the result exactly like the webhook
  (idempotent). P9-03 adds the POS button that calls it. Refuse non-staff callers (check
  `is_counter_staff()` through an RPC with the caller's JWT).

## Tests
- Deno tests (`deno test` in `supabase/functions/`) or Vitest on the shared pure module:
  - Easypaisa request hash against a worked example from the guide (or a fixed test vector you
    document).
  - Status-code mapping, and the amount-mismatch decision.
  - Mock signature: valid, invalid and tampered body.
  - The idempotency decision helper.
- Manual, report the output:
  - Run `npx supabase functions serve` and create an order on the local database.
  - Call `payment-create` (both `card` and `wallet`) with a test user's JWT.
  - POST a signed mock notification twice and once with a bad signature. Expected: the order is
    paid once, and the bad one gets 4xx.
  - Send a late notification on an expired order. Expected: `needs_refund`.
  - With sandbox credentials, also complete one sandbox card payment and one sandbox wallet
    payment end to end.

## Done when
POS checks pass and the function tests pass. `PAYMENTS.md` explains:
- applying for the Easypaisa merchant account, including enabling **card payments** on it, which
  may need a separate approval;
- sandbox then live setup, the secrets, and the notification URL to register with Easypaisa
  (`https://<project>.functions.supabase.co/payment-webhook`);
- the refund procedure: refunds are made in the Easypaisa merchant portal and then recorded with
  `record_online_refund`;
- what customers see for each method.
