# Website launch record

> **Bicycles.pk:** this document is from the LadyVogue clothing shop and is kept for reference. For the bicycles.pk launch follow [LAUNCH.md](./LAUNCH.md).

This branch prepares a local rehearsal. It does not change DNS, hosted Auth,
production data or payment-provider configuration. Owner approval and staging
checks below remain launch gates. The real Easypaisa integration remains deferred;
do not enable live card or wallet payments until the official integration and
sandbox checks are complete.

## Security review

The review queries `pg_proc` joined to `pg_namespace` and checks
`has_function_privilege('anon', oid, 'EXECUTE')` and the same for `authenticated`.
The complete reviewed public-schema function inventory is below. Authenticated is
the shared database role for staff and website customers: a grant alone never
establishes staff access. Staff functions must check the active staff role and
retain their existing branch and narrower role restrictions.

The review found anonymous EXECUTE grants on twelve trigger/helper functions.
The launch migration revokes them from PUBLIC, anon and authenticated. It revokes
PUBLIC/anon execution across the public schema, restores only the eight intended
public RPCs, and removes implicit public execution from future functions.
`needs_bootstrap` exposes only whether initial staff setup is needed;
`quote_online_order` exposes the public quote, not customer orders.
`catalog_policy` returns only `return_window_days`, leaving settings private.

Fifteen staff entry points needed explicit customer denial. Some returned empty
results; others validated inputs before authorization, including nullable
`current_app_role() NOT IN (...)` checks that do not reject a missing role.
The migration copies their latest bodies and adds an early `is_staff()` check,
preserving their existing role, branch, ownership and transaction behavior.
The public-surface test enumerates all executable staff functions, invokes each
as a website customer and requires SQLSTATE 42501. Existing role-specific tests
remain in the full suite. Internal helpers without caller execution remain private.

The anonymous function test is an exact allow-list. It also rejects public table
privileges except SELECT on the existing safe `public_catalog` view. Storage tests
require `product-images` to be the only public bucket and `tailoring-photos` private.
No table policy is broadened by this migration.

## Website behavior

Campaign photographs are local WebPs; Poppins is self-hosted. The browser must make
no automatic requests to the former supplier site. Old contact links are removed; optional contacts render only when configured. CSP permits self, the configured Supabase origin and its websocket
origin. Product image optimization retains the exact Storage path allow-list.
Script execution uses a fresh nonce per HTML response, including appearance and
Next.js bootstrap scripts; script `unsafe-inline` is never enabled. Styles retain
`unsafe-inline` for component inline styles. Development alone permits unsafe-eval
for Next.js tooling. Production adds HSTS, frame denial, nosniff, strict referrer
policy and restrictive camera/microphone/geolocation/payment permissions.

Fresh nonces require dynamic HTML, so HTML ISR is disabled. Catalog fetches retain
their 60-second data cache. A CDN must not cache/replay nonce-bearing HTML across
requests. Measure the real dynamic configuration on staging before launch.
`PAYMENT_CHECKOUT_ORIGINS` is a server-only comma-separated list of exact HTTPS
origins verified against the eventual provider guide. It defaults empty; no
unverified Easypaisa endpoint has been added. Add the real hosted checkout origin
before enabling that provider, then test both redirect and form-post checkout.

Analytics is absent by default. An optional `NEXT_PUBLIC_ANALYTICS_ID` accepts a
GA4 `G-...` measurement ID; it is public configuration, not a secret. The script
loads only after acceptance. Reject and Accept have equal styling. The cookie
stores the choice for six months with SameSite=Lax and Secure on HTTPS. Privacy
choices allows later rejection, disables collection and clears matching GA cookies.
No advertising consent is granted. Check both appearance modes and approve the
provider/privacy wording before enabling analytics.

New original short legal pages are used. Review notes are kept here, not on the public
pages. Before launch the owner checks:

- Shipping: supported cities, dispatch and delivery times, courier and fees match
  the checkout settings.
- Privacy: retention periods for accounts, orders, measurements and photos; the
  privacy contact; hosting, payment and delivery providers.
- Terms: legal business name, address, governing law and disputes; order
  acceptance, cancellation, pricing corrections, refunds and liability wording.

Returns use the database return
window; the refund processing deadline remains separate. The owner must reconcile
existing fee and delivery promises with checkout configuration, approve legal
business/contact details and arrange appropriate local legal review.

## Hosted Auth and deployment gates

- Set the hosted Auth Site URL to `https://brand.pk`; allow only the actual website
  callback URL and required `https://platform.brand.pk` recovery/callback URLs. Remove
  localhost and preview wildcards from production. Local `config.toml` is not proof
  of the hosted values.
- Keep website customer sign-up enabled, anonymous sign-in disabled, email
  confirmation enabled, and use production SMTP. Set six-digit OTP expiry to ten
  minutes and tune resend/email/IP verification limits with a staging rehearsal;
  enable CAPTCHA where appropriate. Record final dashboard values privately.
- The POS offers no public staff signup after bootstrap. Staff are created by
  admins. Auth settings are project-wide: do not claim that an Origin header can
  disable customer signup on only the POS hostname. Database staff routing and
  active-role checks enforce the separation.
- Confirm both bucket policies after deployment. Customer photographs require
  ownership checks and short-lived signed URLs. Never put a service key or payment
  secret in the website or a VITE variable.
- Set A/AAAA or ALIAS/CNAME records for `brand.pk` and CNAME for `platform.brand.pk`
  using the values supplied by each hosting provider. Verify domain ownership,
  TLS, apex/www redirect and certificate renewal. Use the real chosen domain,
  not the former supplier site; no DNS changes are made by this branch.
- Set public site/Supabase URLs for each environment, the website server's verified
  payment origin list, and Edge Function `SITE_URL`. Configure Auth redirects for
  both applications. Restrict payment-function CORS to the chosen website and POS
  origins; public catalog RPC access remains intentional. CORS is not authorization.
  Test preflight, customer JWT and staff JWT from the deployed origins.
- Deploy matching migrations, Edge Functions and both app builds to staging first.
  Confirm payment-create/check authorization and verify notification handling with
  the mock provider. Real provider credentials, live SMTP, DNS, hosted Auth values
  and owner signoff have not been verified locally.

## Rehearsal and release gates

The local dry run checked 1,119 products / 6,061 variants and 185 collections.
576 products map cleanly; 543 remain problems: 338 mixed Length/package conversions,
196 varying `Style`, one varying `style`, six fabric products without an explicit
per-metre unit and two invalid/oversized handles. Case-sensitive source option names
are listed separately here for traceability; mapping recognizes dimensions without
case sensitivity. The detailed private problem list is in `backups/catalog-import/`.

Applying 50 created 50 styles in 1.114 seconds. Repeating updated 50 web records,
created none, and retained 50 styles in 0.598 seconds. The full dry run took 0.157
seconds. Image import uploaded 116 WebPs / 7,287,298 bytes in 104.583 seconds;
peak temporary download was 667,331 bytes, with zero retained downloads and an
86,016-byte observed local free-space delta. Repeating skipped all 116 images,
uploaded zero, and completed in 0.638 seconds. Docker's storage may be on another
drive, so free-space delta is distinct from uploaded bytes. Campaign assets total
809,894 bytes. These are local measurements, not production estimates.

Run the isolated script tests, database reset and tests twice, generated types,
POS unit/type/lint/build/e2e, website lint/test/build and npm 10.9.9 lockfile dry run.
Check three imported products published through the POS, image rendering, legacy
308 redirects, dark/light appearance, sign-in, protected checkout and WhatsApp.
Use `scripts/load-test/README.md` for the 50-connection run; require p95 below
800 ms and no failed requests on staging before launch. Local measured results
and remaining manual limitations are recorded in the final handover.

## Owner launch runbook

1. Take and verify encrypted database and both-bucket backups. Record deployment
   versions and recovery point following [BACKUP_AND_RESTORE.md](./BACKUP_AND_RESTORE.md).
2. Review the import problem list. Correct source data explicitly; never guess
   fabric conversions or enable all products to hide import problems. Review each
   price, cost, physical stock count, image, option and web description.
3. Publish one reviewed collection. In staging, place and fulfil a COD order,
   reconcile the cash shift, cancel another order, and record a real-world refund
   only after money has actually been returned. Verify expired holds release stock
   and the last online unit is refused at the till. Owner: record date and signoff.
4. Keep live card and wallet disabled until the real Easypaisa task is complete.
   Then test sandbox card and wallet success/failure, duplicate notifications,
   late payment/needs_refund and provider settlement reconciliation. Owner: sign off.
5. Approve legal text, delivery settings, security/SMTP settings, staging load
   measurements and mobile checkout. Publish the remaining reviewed catalog in
   batches, monitor failures and reconcile daily. No owner signoff is implied here.

Rollback: stop taking new orders and unpublish styles through the POS. For an
emergency approved by the owner, an administrator can run
`UPDATE public.product_styles SET published=false;` in the SQL editor. This hides
the catalog without deleting orders or changing stock. Cached server data can
last 60 seconds; checkout always rechecks availability/publication. Keep access
to existing orders for fulfilment, cancellation and refunds. Restore a prior app
build only if it is compatible with the current schema; never discard payment
history to make a rollback easier.

## Local validation results

| Required check | Result |
| --- | --- |
| Catalog mapping tests | 9 passed |
| Database reset | Passed |
| Database tests, consecutive runs | 31 files / 1,006 tests passed on each run |
| Generated database types | Passed; included in commit |
| POS unit tests | 19 files / 117 tests passed |
| `npx tsc -b` | Passed |
| POS lint | 0 errors; 8 existing warnings |
| POS production build | Passed |
| POS Playwright | 2 passed |
| Website lint | 0 errors / warnings |
| Website unit tests | 9 files / 36 tests passed |
| Website production build | Passed |
| npm 10.9.9 `ci --dry-run` | Passed; no lockfile sync error or file dependency |

With 50 connections for 15 seconds per target, the warmed production server
measured home p95 **625.521 ms** (1,436 responses), catalog search p95
**597.5864 ms** (1,300 responses) and `catalog_list` p95 **399.3807 ms**
(4,866 responses). All had zero HTTP failures, network errors and timeouts.
This clears the local target; repeat on staging with a representative stocked catalog.

Three imported styles were published through the POS. The website rendered all
three with optimized images; legacy collection/product paths returned 308 redirects.
Real customer email-code sign-in worked under the production CSP. The appearance
script applied dark mode, consent rejection persisted, legal aliases worked and
checkout redirected a signed-out visitor to sign-in. No automatic old-domain
requests or browser runtime/CSP errors were observed. A temporary configured GA4
test ID verified no script before consent or after rejection, loading only after
acceptance, persistence and withdrawal; all Google requests were intercepted locally.
The final build restores the default with no configured analytics provider.

The rehearsal database contained 50 styles, three published, 116 image rows,
zero cost rows, zero stock movements and zero on-hand stock. Final database
validation resets these disposable local fixtures. Uploaded product images,
reports, manifests, test accounts and credentials are not committed.

Staging/production deployment, owner legal and order signoff, real-provider checkout
redirects, settlement and live SMTP/DNS/Auth configuration remain unverified.
The imported zero-stock items cannot produce an actual purchase or an enabled
WhatsApp ordering action; existing link/unit tests cover its URL generation.
Do not treat the catalog browser rehearsal as a completed live order/payment test.

## Reviewed function inventory

The following table is generated from the final local migration state. Public
RPCs are intentionally callable without a staff role. Customer functions enforce
ownership/profile checks. Role/pure helpers expose no shop records. Staff RPCs
retain their narrower role/branch checks and pass the customer-denial sweep.

| Function                                                                       | anon | authenticated | Intended use                   |
| ------------------------------------------------------------------------------ | ---- | ------------- | ------------------------------ |
| `adjust_customer_balance(uuid,numeric,text,uuid)`                              | no   | yes           | Staff; customer denied (42501) |
| `adjust_fabric_roll(uuid,numeric,text,text,uuid)`                              | no   | yes           | Staff; customer denied (42501) |
| `adjust_stock(uuid,uuid,numeric,text,text,uuid)`                               | no   | yes           | Staff; customer denied (42501) |
| `advance_online_order(jsonb)`                                                  | no   | yes           | Staff; customer denied (42501) |
| `advance_tailoring_job(uuid,text,text)`                                        | no   | yes           | Staff; customer denied (42501) |
| `apply_customer_ledger()`                                                      | no   | no            | Internal only; no caller grant |
| `appointment_slots(date)`                                                      | no   | yes           | Customer account/ownership     |
| `approve_stock_count(uuid)`                                                    | no   | yes           | Staff; customer denied (42501) |
| `assign_tailor(uuid,uuid)`                                                     | no   | yes           | Staff; customer denied (42501) |
| `auto_generate_invoice_number()`                                               | no   | no            | Internal only; no caller grant |
| `backfill_customer_ledger()`                                                   | no   | no            | Internal only; no caller grant |
| `cancel_appointment(uuid,text,uuid)`                                           | no   | yes           | Customer account/ownership     |
| `cancel_my_online_order(text)`                                                 | no   | yes           | Customer account/ownership     |
| `cancel_online_order_internal(uuid,text)`                                      | no   | no            | Internal only; no caller grant |
| `cancel_online_order(jsonb)`                                                   | no   | yes           | Staff; customer denied (42501) |
| `cancel_stock_count(uuid)`                                                     | no   | yes           | Staff; customer denied (42501) |
| `cancel_tailoring_order(jsonb)`                                                | no   | yes           | Staff; customer denied (42501) |
| `cancel_tailoring_request(uuid)`                                               | no   | yes           | Customer account/ownership     |
| `cash_session_detail(uuid)`                                                    | no   | yes           | Staff; customer denied (42501) |
| `cash_session_summary(uuid)`                                                   | no   | yes           | Staff; customer denied (42501) |
| `catalog_collections()`                                                        | yes  | yes           | Public bootstrap/catalog/quote |
| `catalog_facets(text)`                                                         | yes  | yes           | Public bootstrap/catalog/quote |
| `catalog_garment_types()`                                                      | yes  | yes           | Public bootstrap/catalog/quote |
| `catalog_list(jsonb)`                                                          | yes  | yes           | Public bootstrap/catalog/quote |
| `catalog_policy()`                                                             | yes  | yes           | Public bootstrap/catalog/quote |
| `catalog_product(text)`                                                        | yes  | yes           | Public bootstrap/catalog/quote |
| `catalog_style_rows()`                                                         | no   | no            | Internal only; no caller grant |
| `check_tailoring_deposit(uuid)`                                                | no   | no            | Internal only; no caller grant |
| `close_cash_session_internal(uuid,numeric,text,uuid)`                          | no   | no            | Internal only; no caller grant |
| `close_cash_session(numeric,text)`                                             | no   | yes           | Staff; customer denied (42501) |
| `close_online_reservations(uuid,text)`                                         | no   | no            | Internal only; no caller grant |
| `close_reservation(uuid,text)`                                                 | no   | no            | Internal only; no caller grant |
| `close_roll_reservation(uuid,boolean,uuid)`                                    | no   | no            | Internal only; no caller grant |
| `collect_cod_payment(jsonb)`                                                   | no   | yes           | Staff; customer denied (42501) |
| `confirm_appointment(uuid,uuid)`                                               | no   | yes           | Staff; customer denied (42501) |
| `confirm_tailoring_order_internal(uuid)`                                       | no   | no            | Internal only; no caller grant |
| `confirm_tailoring_order(uuid,jsonb)`                                          | no   | yes           | Staff; customer denied (42501) |
| `confirm_tailoring_order(uuid)`                                                | no   | yes           | Staff; customer denied (42501) |
| `convert_tailoring_request(jsonb)`                                             | no   | yes           | Staff; customer denied (42501) |
| `create_online_order(jsonb)`                                                   | no   | yes           | Customer account/ownership     |
| `create_return(jsonb,text)`                                                    | no   | no            | Internal only; no caller grant |
| `create_tailoring_order(jsonb)`                                                | no   | yes           | Staff; customer denied (42501) |
| `current_app_role()`                                                           | no   | yes           | Role or pure helper            |
| `current_cash_session()`                                                       | no   | yes           | Staff; customer denied (42501) |
| `customer_statement(uuid,date,date)`                                           | no   | yes           | Staff; customer denied (42501) |
| `customers_with_balance(jsonb)`                                                | no   | yes           | Staff; customer denied (42501) |
| `default_branch_id()`                                                          | no   | yes           | Role or pure helper            |
| `deliver_tailoring_items(jsonb)`                                               | no   | yes           | Staff; customer denied (42501) |
| `expire_online_orders()`                                                       | no   | no            | Internal only; no caller grant |
| `expire_stock_reservations()`                                                  | no   | no            | Internal only; no caller grant |
| `find_sale_for_return(text)`                                                   | no   | yes           | Staff; customer denied (42501) |
| `force_close_cash_session(uuid,numeric,text,uuid)`                             | no   | yes           | Staff; customer denied (42501) |
| `generate_invoice_number()`                                                    | no   | no            | Internal only; no caller grant |
| `guard_cash_variance_alert()`                                                  | no   | no            | Internal only; no caller grant |
| `guard_customer_balance()`                                                     | no   | no            | Internal only; no caller grant |
| `handle_auth_user_marked_staff()`                                              | no   | no            | Internal only; no caller grant |
| `handle_new_auth_user()`                                                       | no   | no            | Internal only; no caller grant |
| `has_app_role(text[])`                                                         | no   | yes           | Role or pure helper            |
| `idempotency_begin(uuid,text)`                                                 | no   | no            | Internal only; no caller grant |
| `idempotency_finish(uuid,jsonb)`                                               | no   | no            | Internal only; no caller grant |
| `import_open_tailoring_order(jsonb)`                                           | no   | yes           | Staff; customer denied (42501) |
| `import_opening_balances(jsonb)`                                               | no   | yes           | Staff; customer denied (42501) |
| `initiate_online_payment(text,uuid,text,text,text)`                            | no   | no            | Internal only; no caller grant |
| `is_branch_member(uuid)`                                                       | no   | yes           | Role or pure helper            |
| `is_counter_staff()`                                                           | no   | yes           | Role or pure helper            |
| `is_staff()`                                                                   | no   | yes           | Role or pure helper            |
| `is_website_customer()`                                                        | no   | yes           | Role or pure helper            |
| `keep_roll_barcodes()`                                                         | no   | no            | Internal only; no caller grant |
| `limit_open_online_orders()`                                                   | no   | no            | Internal only; no caller grant |
| `link_customer_account()`                                                      | no   | yes           | Customer account/ownership     |
| `list_cash_sessions(jsonb)`                                                    | no   | yes           | Staff; customer denied (42501) |
| `list_online_orders(jsonb)`                                                    | no   | yes           | Staff; customer denied (42501) |
| `list_tailoring_requests(jsonb)`                                               | no   | yes           | Staff; customer denied (42501) |
| `list_tailors()`                                                               | no   | yes           | Staff; customer denied (42501) |
| `lock_stock_balance(uuid,uuid)`                                                | no   | no            | Internal only; no caller grant |
| `mark_online_order_paid(text,text,text,numeric,text,jsonb)`                    | no   | no            | Internal only; no caller grant |
| `missing_measurements(text,jsonb)`                                             | no   | yes           | Role or pure helper            |
| `my_appointments()`                                                            | no   | yes           | Customer account/ownership     |
| `my_online_order(text)`                                                        | no   | yes           | Customer account/ownership     |
| `my_online_orders()`                                                           | no   | yes           | Customer account/ownership     |
| `my_order_progress(uuid)`                                                      | no   | yes           | Customer account/ownership     |
| `my_tailoring_requests()`                                                      | no   | yes           | Customer account/ownership     |
| `needs_bootstrap()`                                                            | yes  | yes           | Public bootstrap/catalog/quote |
| `next_roll_code()`                                                             | no   | no            | Internal only; no caller grant |
| `normalize_customer_phone()`                                                   | no   | no            | Internal only; no caller grant |
| `normalize_phone(text)`                                                        | no   | no            | Internal only; no caller grant |
| `online_order_detail(uuid)`                                                    | no   | yes           | Staff; customer denied (42501) |
| `online_order_public(uuid)`                                                    | no   | no            | Internal only; no caller grant |
| `open_cash_session(numeric,uuid)`                                              | no   | yes           | Staff; customer denied (42501) |
| `post_customer_payment(jsonb)`                                                 | no   | yes           | Staff; customer denied (42501) |
| `post_exchange(jsonb)`                                                         | no   | yes           | Staff; customer denied (42501) |
| `post_goods_receipt(jsonb)`                                                    | no   | yes           | Staff; customer denied (42501) |
| `post_return(jsonb)`                                                           | no   | yes           | Staff; customer denied (42501) |
| `post_sale(jsonb)`                                                             | no   | yes           | Staff; customer denied (42501) |
| `post_stock_movement(uuid,uuid,numeric,text,text,text,uuid,numeric,text,uuid)` | no   | no            | Internal only; no caller grant |
| `post_tailoring_payment(jsonb)`                                                | no   | yes           | Staff; customer denied (42501) |
| `prevent_ledger_changes()`                                                     | no   | no            | Internal only; no caller grant |
| `promotion_item_matches(text,uuid)`                                            | no   | yes           | Role or pure helper            |
| `protect_customer_account_columns()`                                           | no   | no            | Internal only; no caller grant |
| `protect_user_privileged_columns()`                                            | no   | no            | Internal only; no caller grant |
| `publish_style(uuid,boolean,boolean)`                                          | no   | yes           | Staff; customer denied (42501) |
| `quote_online_order(jsonb)`                                                    | yes  | yes           | Public bootstrap/catalog/quote |
| `quote_sale(jsonb)`                                                            | no   | yes           | Staff; customer denied (42501) |
| `quote_tailoring_request(jsonb)`                                               | no   | yes           | Staff; customer denied (42501) |
| `receive_fabric_roll(jsonb)`                                                   | no   | yes           | Staff; customer denied (42501) |
| `record_cash_movement(numeric,text)`                                           | no   | yes           | Staff; customer denied (42501) |
| `record_cash_payment()`                                                        | no   | no            | Internal only; no caller grant |
| `record_measurements(uuid,text,jsonb,text,text)`                               | no   | yes           | Staff; customer denied (42501) |
| `record_online_payment_event(text,text,text,numeric,text,text,jsonb)`          | no   | no            | Internal only; no caller grant |
| `record_online_refund(jsonb)`                                                  | no   | yes           | Staff; customer denied (42501) |
| `record_stock_count(uuid,uuid,numeric,uuid)`                                   | no   | yes           | Staff; customer denied (42501) |
| `record_tailoring_payments(uuid,jsonb,text)`                                   | no   | no            | Internal only; no caller grant |
| `refresh_tailoring_order_status(uuid)`                                         | no   | no            | Internal only; no caller grant |
| `release_reservation(uuid)`                                                    | no   | yes           | Staff; customer denied (42501) |
| `report_fabric_usage(date,date,uuid)`                                          | no   | yes           | Staff; customer denied (42501) |
| `report_line_activity(date,date,uuid)`                                         | no   | no            | Internal only; no caller grant |
| `report_sales_summary(date,date,uuid)`                                         | no   | yes           | Staff; customer denied (42501) |
| `report_size_color_matrix(date,date,uuid,uuid)`                                | no   | yes           | Staff; customer denied (42501) |
| `report_staff_sales(date,date,uuid)`                                           | no   | yes           | Staff; customer denied (42501) |
| `report_tailoring(date,date,uuid)`                                             | no   | yes           | Staff; customer denied (42501) |
| `report_tenders(date,date,uuid)`                                               | no   | yes           | Staff; customer denied (42501) |
| `report_top_items(date,date,uuid,text,integer)`                                | no   | yes           | Staff; customer denied (42501) |
| `report_tz()`                                                                  | no   | yes           | Role or pure helper            |
| `request_appointment(jsonb)`                                                   | no   | yes           | Customer account/ownership     |
| `require_online_service()`                                                     | no   | no            | Internal only; no caller grant |
| `require_website_customer()`                                                   | no   | no            | Internal only; no caller grant |
| `reserve_roll_length(uuid,uuid,numeric,uuid,text,uuid)`                        | no   | no            | Internal only; no caller grant |
| `reserve_stock(uuid,uuid,numeric,text,text,uuid,timestamp with time zone)`     | no   | yes           | Staff; customer denied (42501) |
| `respond_to_quote(uuid,boolean,uuid)`                                          | no   | yes           | Customer account/ownership     |
| `return_customer_material(uuid,numeric,text)`                                  | no   | yes           | Staff; customer denied (42501) |
| `sale_detail(uuid)`                                                            | no   | yes           | Staff; customer denied (42501) |
| `sale_returnable(uuid)`                                                        | no   | yes           | Staff; customer denied (42501) |
| `sanitize_card_details(jsonb)`                                                 | no   | no            | Internal only; no caller grant |
| `save_collection(jsonb)`                                                       | no   | yes           | Staff; customer denied (42501) |
| `save_garment_type(jsonb)`                                                     | no   | yes           | Staff; customer denied (42501) |
| `save_product_images(uuid,jsonb,uuid)`                                         | no   | yes           | Staff; customer denied (42501) |
| `save_style_web_details(uuid,jsonb,uuid)`                                      | no   | yes           | Staff; customer denied (42501) |
| `save_style(jsonb)`                                                            | no   | yes           | Staff; customer denied (42501) |
| `search_sales(jsonb)`                                                          | no   | yes           | Staff; customer denied (42501) |
| `search_variants(jsonb)`                                                       | no   | yes           | Staff; customer denied (42501) |
| `set_collection_styles(uuid,uuid[],uuid)`                                      | no   | yes           | Staff; customer denied (42501) |
| `staff_link_customer_account(uuid,uuid,uuid)`                                  | no   | yes           | Staff; customer denied (42501) |
| `start_stock_count(uuid,text)`                                                 | no   | yes           | Staff; customer denied (42501) |
| `submit_tailoring_request(jsonb)`                                              | no   | yes           | Customer account/ownership     |
| `tailor_queue()`                                                               | no   | yes           | Staff; customer denied (42501) |
| `tailoring_order_summary(uuid)`                                                | no   | yes           | Staff; customer denied (42501) |
| `tailoring_order_totals(uuid)`                                                 | no   | no            | Internal only; no caller grant |
| `tailoring_request_begin(uuid,text)`                                           | no   | no            | Internal only; no caller grant |
| `tailoring_request_detail(uuid)`                                               | no   | yes           | Staff; customer denied (42501) |
| `update_customer_stats()`                                                      | no   | no            | Internal only; no caller grant |
| `update_settings(jsonb)`                                                       | no   | yes           | Staff; customer denied (42501) |
| `update_tailoring_request(jsonb)`                                              | no   | yes           | Staff; customer denied (42501) |
| `update_updated_at_column()`                                                   | no   | no            | Internal only; no caller grant |
| `variant_by_code(text,uuid)`                                                   | no   | yes           | Staff; customer denied (42501) |

## LadyVogue brand review

No shop address or contact is configured yet. Central settings are website/content/brand.json. Confirm the legal business identity, address, privacy retention and service providers, eligible return conditions and delivery coverage before launch. No opening hours, refund deadline or delivery date is promised by the public copy. Card/wallet availability follows the existing provider configuration; live provider integration remains a separate approval.

Per the owner's latest instruction, existing campaign/product photos are kept temporarily. Automatic source-photo importing is removed. Replace retained photos with approved owner assets before claiming an entirely original photographic catalog. This rebrand does not modify database content, provider secrets, DNS or the POS.

## Deployment preparation

Use [DEPLOY.md](./DEPLOY.md) for the two-project hosted setup and owner release steps. Launch is COD-only: the new card/wallet setting defaults off, checkout follows server methods and hosted mock is refused. Older mock rehearsal instructions above apply only to local development with explicit administrator opt-in. Hosted configuration, DNS, SMTP, approval gates, storage and cron must still be verified by the owner.
