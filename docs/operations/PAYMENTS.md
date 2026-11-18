# Online payments

## Current implementation and release gate

P9-02 currently supports **local mock payments only**. The owner deferred Easypaisa
integration on 2026-10-20 because the official merchant guide is not available.
Selecting `PAYMENT_PROVIDER=easypaisa` returns HTTP 503 and creates no checkout.
Do not enable online payments for real customers yet.

Official source to obtain the guide:
[Easypaisa merchant integration guides](https://easypaystg.easypaisa.com.pk/easypay-merchant/faces/pg/site/IntegrationGuides.jsf).
That portal timed out during implementation. **Guide version/date: not yet obtained
or verified.** No production endpoint, hash algorithm, payment selector, inquiry
field, status code, or acknowledgement format is assumed from third-party examples.
The Easypaisa adapter is a disabled placeholder, not a tested provider integration.

Before completing that adapter, obtain the merchant account's official guide and
record its exact title, version, issue date and relevant sections here. Confirm the
hosted **card and wallet** flows, expiry timezone/format, merchant reference versus
transaction reference, signing/encryption example, inquiry authentication and
response schema, terminal statuses, notification transport and acknowledgement.
Implement a fixed hash vector from that guide and sample inquiry/notification tests.
The mock HMAC vector below is not an Easypaisa hash test.

## Merchant onboarding and sandbox-to-live checklist

Apply through Easypaisa's official merchant onboarding channel. Ask the merchant
team for sandbox access, store ID, merchant hash key, transaction inquiry username
and password, and the integration guide. Explicitly request **card payments** as
well as wallet payments; card acceptance may need separate approval.

After the deferred adapter is implemented, configure sandbox secrets, register the
notification URL, and complete one sandbox card payment and one sandbox wallet
payment, including duplicate, failure, refund, mismatch and late-notification tests.
Only then switch to merchant-approved live credentials and the live base URL from
the verified guide. Do not copy endpoint paths from unofficial examples.

Notification URL to register:
`https://<project>.functions.supabase.co/payment-webhook`.
Deploy all three functions after applying database migrations. Only
`payment-webhook` has `verify_jwt=false`; `payment-create` and `payment-check`
require customer/staff JWTs respectively. They also validate the caller with Auth
and enforce database permissions using that caller's JWT.

## Function secrets

Set these using Supabase function secrets, never website/POS environment variables:

| Name                     | Purpose                                                      |
| ------------------------ | ------------------------------------------------------------ |
| `PAYMENT_PROVIDER`       | Explicitly `mock` locally; `easypaisa` is currently disabled |
| `PAYMENT_WEBHOOK_SECRET` | Random mock-only HMAC key, at least 32 characters            |
| `SITE_URL`               | Website origin; HTTPS, or HTTP localhost for local testing   |
| `EASYPAISA_STORE_ID`     | Merchant store ID, deferred                                  |
| `EASYPAISA_HASH_KEY`     | Merchant hash key, deferred                                  |
| `EASYPAISA_API_USER`     | Inquiry API username, deferred                               |
| `EASYPAISA_API_PASSWORD` | Inquiry API password, deferred                               |
| `EASYPAISA_BASE_URL`     | Verified sandbox/live base URL, deferred                     |

Supabase supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
`SUPABASE_SERVICE_ROLE_KEY` to the functions. The service key stays server-side.
Do not log JWTs, request headers, keys, checkout hashes, or unfiltered provider
responses. Current logs contain only a function name and fixed error category;
stored mock event data includes only reference, order, amount, method and status.
Never send card numbers, CVV, expiry dates or wallet OTPs to these functions.

## API and local mock testing

Create an ignored local function environment file with `PAYMENT_PROVIDER=mock`,
`SITE_URL=http://localhost:3000` and a randomly generated
`PAYMENT_WEBHOOK_SECRET`. Keep it out of version control and outside `website/`.
Run:

```sh
npx supabase functions serve --env-file <ignored-local-env-file>
npx vitest run --config supabase/functions/_shared/payments/vitest.config.ts
```

Create an online order with `create_online_order` as a website customer. Use
`payment_method=card` or `easypaisa`; COD does not create an online payment session.
POST `/functions/v1/payment-create` with the customer's Bearer JWT, the local anon
API key and JSON `{ "orderNo": "WEB-000001", "method": "card" }` (or `wallet`).
The saved order controls amount, method, expiry, ownership and return URL.
Repeating checkout uses the same mock reference `mock:WEB-000001`.

The mock redirects directly to the configured website's `/checkout/return` URL.
It displays no card form and collects no money. The return page is outside this
plan and must only poll `my_online_order`; visiting it never confirms a payment.

Send mock notifications to `/functions/v1/payment-webhook` with JSON:

```json
{
  "providerRef": "mock:WEB-000001",
  "orderNo": "WEB-000001",
  "amount": 100,
  "method": "card",
  "status": "paid"
}
```

Calculate HMAC-SHA256 over the **exact UTF-8 request body**, with the mock secret.
Send the lowercase hexadecimal digest in `x-payment-signature`. Do not reformat
or reserialize the body after signing. The supported mock statuses are `paid`,
`failed`, and `refunded`; unknown statuses become `failed`. This signing mechanism
belongs only to the mock provider. Its independent test vector is
[RFC 4231 section 4.3](https://www.rfc-editor.org/rfc/rfc4231#section-4.3): key `Jefe`,
message `what do ya want for nothing?`, SHA-256 digest
`5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843`.

Valid notifications return JSON with `received`, stored `status` and
`needs_refund`. An invalid signature gets 401; unknown/mismatched checkout gets
4xx. A captured amount mismatch gets 409 **after** recording failed/needs-refund
for staff investigation. A duplicate does not create another payment or event.
A notification after expiry or cancellation records `needs_refund=true` and does
not reopen the order or reserve stock again. Failure never downgrades paid;
paid replays never resurrect refunded payments.

POST `/functions/v1/payment-check` with counter-staff JWT and `{ "orderNo": "..." }`.
Customer and inactive staff callers are refused. The same provider
confirmation and application path is used. **Mock has no inquiry ledger**, so an
authorized mock check returns 409 instructing the tester to send a signed
notification. It never infers success from an initiated database row. The real
inquiry path is deferred with the Easypaisa adapter.

Customer checkout accepts the configured website origin. Staff payment checks
allow the separately hosted POS origin using CORS `*`; they require an explicit
Bearer JWT and never use browser cookies or credentialed CORS. Auth, counter-staff
and branch checks still apply before any payment lookup or inquiry.

## What customers will see

Once the real adapter and checkout UI are completed, card users enter their details
only on Easypaisa's hosted page; wallet users approve using Easypaisa's supported
app/OTP flow. Successful browser redirection is not proof of payment. The website
shows the database order status after server confirmation. Expired/cancelled orders
with captured money need a refund. COD follows the existing shop collection flow.
Currently these are planned production flows; only mock checkout is available.

## Daily reconciliation and refunds

There is no scheduled `payment-reconcile` job in this plan. Each day, a manager
compares merchant-portal transactions with `online_payments`, checking provider
reference, order, amount and status. Investigate `needs_refund`, failed captures,
unmatched portal transactions and initiated rows older than the hold window.
Counter staff can use `payment-check` once the real inquiry adapter is available.

Run this query in an authorized staff SQL session to find stale initiations:

```sql
SELECT p.provider_ref, p.provider, p.method, p.amount, p.created_at,
       o.order_no, o.status, o.expires_at
FROM public.online_payments p
JOIN public.online_orders o ON o.id = p.order_id
CROSS JOIN LATERAL (
  SELECT online_hold_minutes FROM public.app_settings ORDER BY created_at, id LIMIT 1
) settings
WHERE p.status = 'initiated'
  AND (p.created_at < now() - make_interval(mins => settings.online_hold_minutes)
       OR o.expires_at <= now() OR o.status IN ('expired', 'cancelled'))
ORDER BY p.created_at, p.id;
```

Do not mark an order paid by hand from a screenshot, return URL or IPN status.
Confirm with the provider inquiry API first. If inquiry is unavailable, leave it
unconfirmed and investigate in the portal. Never accept a notification body's
claimed success as a substitute for the real inquiry response.

Send refunds in the Easypaisa merchant portal. A manager then calls
`record_online_refund` with a fresh `request_id` and the payment's `provider_ref`.
This records a **full provider-payment refund**, not a transfer of money. Once
supported by the real adapter, a confirmed refund notification applies the same
payment state automatically and is idempotent. Packed orders use the POS returns
screen for stock and till accounting; a provider refund must not restock goods or
create a second cash refund. Keep refund receipts for reconciliation.

## COD-only hosted launch

Keep `app_settings.online_card_enabled=false` (the migration default) and leave hosted `PAYMENT_PROVIDER` unset. Quote responses expose the allowed `payment_methods`; checkout hides disabled options. The database and payment-create independently refuse new card/wallet checkout. Admins alone may change the switch; managers retain their existing receipt-only settings permissions. Turning it off does not prevent legitimate confirmation/refund of an existing payment.

Mock startup is rejected unless `SITE_URL` has the exact localhost or 127.0.0.1 host. Hosted staging must not use mock either. For local mock rehearsals explicitly enable the database switch as an administrator first, then disable it again before the COD-only deployment check. See [DEPLOY.md](./DEPLOY.md).
