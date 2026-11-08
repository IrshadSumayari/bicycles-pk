# Clothing Store & Tailoring POS: Development Plan

Version 1.1 · 19 October 2026 · Repository: `IrshadSumayari/clothing-pos`

This plan turns the current retail POS into a system for a clothing store with in-house stitching.
It merges the original business review with the follow-up review points (tax compliance, outages,
WhatsApp, seasonal capacity, testing, and a staged launch).

**v1.1:** adds the company website (online orders and tailoring requests) as Release 3, sharing one
Supabase backend with the POS. The Release 1 data model is designed for it from the start.

---

## 1. Goal and scope

**Business:** one store now, designed so more branches can be added later.

**Sells:**
- Ready-made garments: suits, shalwar kameez, sherwanis, office wear (size / color / fit variants)
- Packaged unstitched suits (2-piece / 3-piece sets, sold as whole packs)
- Loose fabric cut from rolls, sold by meter or yard
- In-house stitching, using fabric bought in the store or brought by the customer

**Complete journey the system must support:**
receive stock → sell garments or fabric → take a tailoring order → collect deposits → issue fabric →
stitch and fit → deliver → reconcile payments, cash and stock.

**Also sells online:** the brand website (separate app, same backend) shows published products, takes
online orders, and accepts stitching requests and appointments (Release 3).

**Out of scope for the first releases:** outsourced stitching, loyalty, payroll, full accounting,
robust offline multi-device selling, branch transfers, marketplace integrations.

---

## 2. Starting point (verified)

| Item | Status |
|---|---|
| Stack | React 19, TypeScript 6, Vite 8, Tailwind CSS 4, Supabase (Postgres + Auth + Edge Functions) |
| Security | Role-based database rules, server-side staff creation, atomic `process_sale()`, no stored card numbers |
| Build | `npm run build` (type-check + bundle) passes |
| Dependencies | `npm audit`: 0 vulnerabilities |
| Lint | 53 errors / 10 warnings, all inherited (mostly `any` types) |
| Tests | None. README mentions `npm run test`, which does not exist |
| Live data | **None.** The app has never run in a store, so there is no legacy database to migrate. The schema can be redesigned cleanly. |

**Known defects in the current code that the new design replaces:**
- Fabric stock is an integer and measured cuts are rounded up (`CEIL`); length is not multiplied by quantity.
- Discounts and tax come from the browser; tax ignores each product's `taxable` flag.
- Free gifts leave the store without reducing stock.
- Reports count drafts as revenue and do not subtract refunds.
- Completing a draft (create sale + delete draft) is two separate requests; there is no retry protection.
- Stock can be overwritten directly; posted sales can be edited or deleted; there is no movement history.
- Barcodes are not unique; there are no size/color variants.
- All data is loaded into the browser at once; reports are computed client-side.
- "Auto backup" is a setting with no implementation.

---

## 3. Decisions (to confirm in Phase 0)

Each has a recommended default so work can start; the owner confirms or changes it in Phase 0.

| # | Decision | Recommended default |
|---|---|---|
| D1 | **Commercial license** from the original author (README requires written consent) | Request it now, before Phase 1. If refused, the new schema and screens replace nearly all original code anyway. Decide before the first live sale. |
| D2 | **Go-live strategy** | **Three releases.** Release 1 = retail (garments, packs, fabric, returns, cash shifts). Tailoring stays on paper for 4–6 weeks, then Release 2 = tailoring. Release 3 = website: catalog first, then tailoring requests, then online checkout. |
| D3 | **Tax** | Confirm with the tax adviser whether FBR POS integration (real-time invoice reporting, FBR invoice number + QR on the receipt) applies, and whether provincial sales tax on services applies to stitching. If yes, it is mandatory for Release 1. |
| D4 | **Internet outages** | Online posting only, plus: UPS for router and till, mobile-hotspot backup, and a written paper-invoice procedure with later entry. Revisit offline selling if outages are frequent in the pilot. |
| D5 | Units | Base unit meter, `NUMERIC(18,6)`; entry to 2 decimals (e.g. 2.25 m); yards optional per product (1 yd = 0.9144 m) |
| D6 | Currency / locale | PKR, timezone Asia/Karachi, configurable in settings (no hard-coded country) |
| D7 | Size charts | Letter sizes (S–XXL), chest sizes (36–46), trouser waist × inseam; configurable order |
| D8 | Packs | Packs are sold whole; opening a pack for tailoring is an explicit conversion with cost allocation |
| D9 | Returns policy | Ready-made: 7 days, unworn, with receipt; cut fabric and stitched items: not returnable unless a manager overrides with a reason |
| D10 | Deposits | Minimum deposit configurable (default 50% of stitching charge); balance due at delivery |
| D11 | Hardware | 80 mm thermal receipt printer, label printer (model to be chosen), USB/Bluetooth barcode scanner, Code 128 labels |
| D12 | Busy-season limits | Booking cut-off date before Eid; daily job capacity per tailor (warning, manager can override) |
| D13 | **Website codebase** | Separate **Next.js** app in this repository under `website/` (own build and deploy), sharing `supabase/` migrations and generated types. POS stays at the repository root. |
| D14 | **Online payment provider** | **Easypaisa** merchant gateway (hosted checkout): credit/debit cards and the Easypaisa wallet. Payments confirmed server-side through Easypaisa's transaction inquiry API. Cash on delivery supported from day one. Card data never touches our servers. |
| D15 | Online fulfilment | Store pickup and courier delivery; courier booking done manually at first (tracking number entered in the POS) |
| D16 | Online reservation hold | Unpaid online orders hold stock for 30 minutes (configurable); cash-on-delivery orders hold until staff confirm or cancel |
| D17 | Domains | Website on the main domain (e.g. `brand.pk`), POS on a staff subdomain (e.g. `platform.brand.pk`), separate hosting and releases |

---

## 4. Architecture principles

1. **The database is the authority.** Prices, discounts, tax, stock and payments are calculated and
   posted inside Postgres functions, in one transaction each. The browser only sends intent
   (items, quantities, chosen promotions, tenders).
2. **Ledgers, not editable totals.** Stock, payments and customer balances change only through
   append-only movement rows. Corrections are reversal documents, never edits or deletes.
3. **Idempotency.** Every posting call carries a client-generated request ID. A retry returns the
   original result instead of posting twice.
4. **Snapshots.** Sale lines store name, unit, price, discount, tax and cost at posting time.
   Tailoring orders store the measurement and design snapshot used for that order.
5. **Branch-ready.** `branch_id` on stock, sales, cash sessions, jobs and memberships from day one.
   One branch seeded; branch switching hidden until a second branch exists.
6. **Server state via TanStack Query.** Replace the single global context for server data with
   paged, cached queries that refresh after each posting. Keep React context only for UI state
   (cart, active tab, interface mode).
7. **Generated types.** Run `supabase gen types typescript` after every migration; no hand-edited
   database types.
8. **Exact numbers.** Money `NUMERIC(14,2)`, quantities `NUMERIC(18,6)`, never floats in the database.
   Lock rows in a consistent order (by ID) to avoid deadlocks.
9. **Private files.** Design photos, fabric photos and measurements live in a private Supabase
   Storage bucket with role-based access. Published product images live in a separate public bucket.
10. **Two kinds of accounts.** Staff (`users` table: admin, manager, cashier, tailor) and customers
    (`customer_accounts`, linked to `customers`) are both Supabase Auth users but never mix: a
    website sign-up creates a customer account only and gets no staff access. Staff accounts are
    created only by an admin through the `admin-users` edge function.
11. **One stock pool, many channels.** POS and website use the same stock ledger.
    *Available = on hand − reserved*, where reservations come from stitching material, online orders,
    and POS drafts that hold stock. Every sale, order and reservation records its `channel`
    (`pos`, `web`).
12. **Public data through narrow contracts.** Visitors read published catalog data through
    dedicated views/functions that never expose cost, supplier or stock-movement data (only an
    "in stock / low / out" level). Customers read only their own orders and approved tailoring updates.
13. **Payments are confirmed by the provider, not the browser.** Online orders are marked paid only by
    a verified server-to-server notification (edge function), processed idempotently.

---

## 5. Data model (new schema)

Because there is no live data, the new schema replaces the old catalog/sales tables directly.
Users, roles and the security helpers from `001_security_hardening.sql` are kept and extended.

| Area | Tables | Notes |
|---|---|---|
| Organisation | `branches`, `branch_memberships`, `locations` | Locations: shop floor, stockroom, workroom. Policies check branch membership. |
| Roles | extend `users.role` with `tailor` | Tailor: assigned jobs only; no prices, refunds or customer list |
| Catalog | `product_styles`, `product_variants`, `size_schemes`, `variant_barcodes` | `product_kind`: garment, pack, fabric, service. Unique SKU; unique non-blank barcode across variants and rolls. |
| Fabric | `fabric_rolls` | Roll barcode, width, shade/lot, composition, cost, remaining length |
| Stock | `stock_balances`, `stock_movements`, `stock_reservations` | On-hand / reserved / available per variant-or-roll per location. Movement types: receive, sale, return, adjust, waste, reserve, issue, consume, convert. |
| Receiving | `goods_receipts`, `goods_receipt_lines`, `stock_counts`, `stock_count_lines` | Supplier reference, unit cost, approved count variances |
| Customers | `customers` (phone normalised to E.164, unique), `wearer_profiles`, `customer_accounts` | One customer, several wearers (family members). `customer_accounts` links a website login to a customer record; staff and customer logins never share tables. |
| Sales | `sales`, `sale_lines`, `payments`, `payment_allocations` | Idempotency key, branch, till, cashier; line snapshots; split tenders with references |
| Returns | `returns`, `return_lines`, `exchange_links` | Linked to original sale lines; returnable quantity enforced |
| Promotions | `promotions`, `promotion_rules`, `discount_approvals` | Evaluated on the server; manual discounts limited by role |
| Tax | `tax_rates`, `fiscal_submissions` | Per-product tax class; FBR submission status, invoice number, QR payload, retries |
| Measurements | `measurement_templates`, `measurement_versions` | Per garment type; unit, taken by, date; versioned |
| Tailoring | `tailoring_orders`, `tailoring_order_items`, `tailoring_charges`, `tailoring_jobs`, `job_events` | Snapshots of measurements/design; stage history; assigned tailor; due/fitting dates; rework reasons |
| Materials | `tailoring_materials`, `material_custody_events`, `delivery_lines` | Store vs customer ownership; received / reserved / issued / consumed / wasted / returned |
| Cash | `cash_sessions`, `cash_movements` | Opening float, collections, refunds, cash in/out, counted vs expected |
| Audit | `audit_events` | Overrides, price changes, cancellations, voids |
| Settings | `app_settings` extended | Currency, timezone, return windows, deposit %, booking cut-off, capacity, receipt text |
| Website catalog | `product_styles.published`, `slug`, `web_description`, `product_images`, `collections` | "Publish on website" per style (and per variant if needed); public views expose only published, active items and a stock level band |
| Online orders | `online_orders`, `online_order_lines`, `order_status_events`, `shipments` | Source `web`; statuses: pending payment → paid / COD confirmed → preparing → ready for pickup / shipped → delivered; cancelled, expired, returned |
| Online payments | `payment_intents`, `payment_events` | Provider reference, amount, status; every webhook stored once (unique provider event ID) |
| Tailoring requests | `tailoring_requests`, `appointments` | From the website; staff review measurements, fabric, charges and dates before converting to a `tailoring_order` |
| Customer updates | `tailoring_jobs.customer_visible_status`, `order_status_events.visible_to_customer` | Customers see only approved progress messages, never internal notes or tailor details |

**Key transactional functions:** `post_sale`, `post_return`, `post_goods_receipt`, `post_stock_count`,
`post_adjustment`, `convert_pack`, `confirm_tailoring_order`, `reserve_material`, `issue_material`,
`record_job_stage`, `post_tailoring_payment`, `deliver_tailoring_items`, `open_cash_session`,
`close_cash_session`. All are idempotent and check role and branch membership.

**Fabric rules:**
- A cut records roll, length, count. Several equal cuts store `count × length` once.
- One cut must come from one roll (two short rolls never pretend to make one long piece).
- Reserving reduces *available*, not *on hand*. Issuing a reservation moves material to the job
  without reducing available twice.
- Remnants stay sellable and identifiable; waste needs a reason.

---

## 6. Phases

Estimates are for one experienced full-time developer with weekly owner feedback.
Contingency of 20% is included in the calendar totals.

### Release 1: Retail

#### Phase 0: Foundations and decisions (4–6 days)
- Confirm decisions D1–D12; collect size charts, sample products, receipt layout, return policy.
- Tax adviser answer on FBR / provincial tax (D3).
- Choose and order hardware (D11); test scanner + printers with a browser page.
- Local Supabase (`supabase start`) and a separate staging project; migrations applied by CLI.
- Testing setup: **pgTAP** (or SQL test scripts) for database functions, **Vitest** for calculation
  helpers, **Playwright** for end-to-end flows; `npm run test` wired up; CI on GitHub Actions
  (build + lint + tests on every push).
- Lint clean-up to 0 errors; add TanStack Query.
- **Gate:** build, lint and tests pass in CI; decisions signed off; hardware prints a test label and receipt.

#### Phase 1: Data and transaction foundation (5–8 days)
- New schema (section 5) for branches, catalog, stock ledger, sales, payments, audit; seed one branch.
- `tailor` role; branch-aware policies; posted documents cannot be updated or deleted.
- `post_sale` with idempotency, server-side prices/promotions/tax, gift lines that move stock.
- Website-ready foundations (no website screens yet): `channel` on sales/reservations/movements;
  reservations with expiry; staff vs customer accounts separated (sign-ups no longer create staff
  rows); `published` flag and public catalog view skeleton.
- Generated types; services split into `catalog`, `inventory`, `checkout`, `payments`, `customers`.
- **Gate:** tampered prices/discounts rejected; two tills selling the last item → one succeeds;
  repeated request posts once; gifts reduce stock; a website sign-up gets no staff access.

#### Phase 2: Clothing and fabric inventory (7–10 days)
- Product forms by kind; style + variant matrix (sizes × colors) with per-variant barcode, price, stock.
- Packs; fabric rolls with width/shade; meter/yard entry; remnants and waste.
- Goods receiving, stock counts with approval, adjustments with reasons, movement history screen.
- Label printing (Code 128) for variants and rolls; CSV import with preview and row errors.
- Indexed search and pagination.
- **Gate:** one garment variant, one pack and a 2.5 m cut from a 10 m roll reconcile exactly
  (7.5 m left); yards convert correctly; wrong shade/short roll is refused.

#### Phase 3: Retail checkout, returns and cash (8–11 days)
- Barcode-first POS; size/color chooser; mixed cart (garments + packs + fabric cuts).
- Split tenders (cash/card/digital) with references; drafts that convert to a sale atomically.
- Receipt snapshot (original cashier, store details) and reprint.
- Returns and exchanges against original lines with allocated discount/tax; restock vs quarantine.
- Cash sessions: opening float, cash in/out, refunds, expected vs counted, variance.
- Phone-first customer lookup (normalised numbers), optional email.
- **Gate:** sale → partial return → size exchange reconciles stock, tax, discounts and payments;
  till closes with correct variance.

#### Phase 3b: Tax compliance (5–8 days, only if D3 = required)
- FBR integration (server side, in an Edge Function): submit each invoice, store fiscal invoice
  number, print QR on the receipt, queue and retry when FBR is unreachable.
- Provincial service tax on stitching charges if applicable (used again in Release 2).
- **Gate:** test invoices accepted in the FBR sandbox; receipt shows fiscal number and QR;
  an offline period re-submits automatically.

#### Phase 5a: Retail reports and operations (3–5 days)
- Server-side report functions: net sales (excluding drafts, minus returns), tax, tenders,
  margin from cost snapshots, size/color demand, fabric sold, slow movers.
- Backup: scheduled database export + documented, rehearsed restore into staging.
- Connection status indicator and the paper-invoice fallback procedure (D4).
- **Gate:** reports match a hand-calculated test day; backup restored successfully.

#### Phase 6a: Retail import and pilot (4–6 days)
- Import products from the current records (Excel/paper/other POS) with a mapping sheet; dry run.
- Physical count of garments and packs; measure every fabric roll; post opening balances.
- Opening customer debts and till float as opening entries (not sales).
- Staff training; 1–2 week pilot; one system of record during the pilot.
- **Gate:** owner signs off stock, opening balances and sample receipts. **Release 1 live.**

**Release 1 effort: 31–46 days (+5–8 if FBR) → about 8–12 calendar weeks.**

### Release 2: Tailoring

#### Phase 4: In-house tailoring (12–18 days)
- Order intake: customer + wearer, garment type, quantity, design notes and reference photos,
  agreed price, promised and fitting dates, fabric source.
- Measurement templates (shalwar kameez, sherwani, suit, shirt, trousers); versions per wearer;
  snapshot on each order; incomplete measurements block release to cutting.
- Fabric: store fabric reserved from specific rolls and linked to the order (billed once,
  issued once); customer fabric recorded with description, length, photo and custody receipt;
  mixed sources per material line.
- Jobs per garment: Awaiting → Cutting → Stitching → Fitting → Finishing → QC → Ready → Delivered;
  rework back to stitching with a reason; cancellation policy by stage.
- Tailor work queue (assigned jobs, due dates, overdue); capacity warning and booking cut-off (D12).
- **Printable tailor job slip:** large measurements, fabric photo, design notes, optional Urdu labels.
- Charges as separate lines (stitching, lining, buttons, embroidery, alteration); deposits and
  balance collections through the payment ledger with a receipt for each.
- Partial delivery; return of unused customer fabric with acknowledgement; delivery receipt.
- **WhatsApp "ready" message:** button that opens a `wa.me` link with the order number, items
  and balance due (no paid API needed).
- **Gate:** store-fabric order and customer-fabric order both run end to end; no double stock
  issue or charge; balances correct; measurement changes do not alter confirmed orders.

#### Phase 5b: Tailoring reports and controls (3–5 days)
- Open jobs by stage and tailor, overdue jobs, outstanding balances, deposits held,
  fabric issued vs consumed, job margin (material + standard labour cost).
- Deposits and balance collections included in cash-session close.
- **Gate:** open-job and balance reports reconcile with the payment ledger; till closes correctly
  with deposits and collections.

#### Phase 6b: Tailoring import and pilot (2–4 days)
- Import open paper orders: wearer, measurements, stage, tailor, customer material held,
  material already issued (no second deduction), deposits, balance.
- Pilot outside the pre-Eid peak (no go-live in the 6–8 weeks before Eid).
- **Gate:** owner signs off every open order and balance. **Release 2 live.**

**Release 2 effort: 17–27 days → about 4–7 calendar weeks.**

### Release 3: Website and online orders

Built as a separate app (`website/`, decision D13) on the same backend, rolled out in three steps.
The storefront's visual design (brand look, photography) is supplied by the owner or a designer; the
estimates cover building it, not creating the brand.

#### Phase 7: Shared catalog on the website (6–9 days)
- POS: "Publish on website" toggle, web title/description, slug, collections, image upload and ordering
  (public bucket, resized), preview of how the product appears online.
- Backend: public catalog views/functions (published + active only, no cost/supplier fields, stock
  level band), search and filtering by collection, size, color, price.
- Website: home, collection, product (size/color picker, size chart), search; SEO metadata and sitemap.
- Hosting on the main domain; POS moved to the staff subdomain (D17).
- **Gate:** unpublished items and cost fields are unreachable from the public API (tested); a stock
  change in the POS shows on the website within one refresh.

#### Phase 8: Tailoring requests and appointments online (5–8 days)
- Website: stitching request form (garment type, design photos, fabric source, preferred dates),
  appointment booking for measurements, customer sign-in (phone OTP or email) and "My requests".
- POS: request inbox with review → quote (measurements, fabric needs, charges, delivery date) →
  customer accepts → converts into a normal `tailoring_order` (Release 2 workflow).
- Customer progress page shows only approved status updates; WhatsApp link to the same page.
- **Gate:** a customer sees only their own requests and approved updates; nothing becomes a job
  until staff confirm it; rate limits and file checks on uploads.

#### Phase 9: Online checkout and order management (10–15 days)
- Website: cart, checkout (pickup or delivery, address, phone), payment via provider (D14) or cash
  on delivery, order confirmation, "My orders", cancellation while unprocessed.
- Backend: `create_online_order` validates prices on the server and reserves stock (expiry D16);
  `payment-webhook` edge function verifies provider signatures and marks orders paid exactly once;
  scheduled job releases expired reservations; idempotency keys on order creation.
- POS: online order queue (source "Online"): confirm, prepare, pack, ready for pickup / shipped with
  tracking, delivered, cancel (releases stock, triggers refund), returns through the Release 1
  returns flow; stock deducted once at fulfilment.
- Customer notifications: order confirmation and status changes (email + WhatsApp link).
- **Gate:** simultaneous last-item sale online and in store → one succeeds; abandoned payment
  releases stock on expiry; duplicate webhooks and retries create one payment and one deduction;
  refund updates order, payment and stock correctly.

#### Phase 10: Website launch (3–5 days)
- Privacy policy, terms, returns and shipping pages; analytics with consent.
- Load test catalog pages; security review of public endpoints; backup includes online orders.
- Soft launch with a limited collection, then full catalog.
- **Gate:** owner signs off test orders (paid, COD, cancelled, refunded) end to end. **Release 3 live.**

**Release 3 effort: 24–37 days → about 6–9 calendar weeks.**

**Total: 72–110 days (+5–8 if FBR) → about 18–28 calendar weeks including contingency.**

---

## 7. Acceptance tests (automated where possible)

Database tests (pgTAP) unless marked E2E.

1. Last size-L navy item sold from two tills at once: one succeeds; other sizes/colors untouched.
2. Variant and roll barcodes resolve exactly; duplicate or unknown codes give a clear message.
3. Pack sale deducts one pack; pack conversion creates components and allocates cost.
4. 2.5 m cut from 10 m leaves 7.5 m; yards convert; multiple cuts; short roll refused; different
   shade lot refused unless chosen; remnant stays sellable; waste needs a reason.
5. Reservation vs concurrent retail sale from the same roll: neither consumes the other's length;
   issuing a reservation twice (retry) issues once.
6. Tampered price/discount/tax in a request is ignored or rejected; gifts move stock; rounding stable.
7. Lost response after posting a sale or deposit: retry returns the same document; no duplicates.
8. Draft completed once; no longer open; not counted twice in revenue.
9. Partial return of a discounted sale and exchange to a higher/lower price: allocated discount and
   tax respected; returnable quantity enforced, including two simultaneous returns.
10. (E2E) Store-fabric tailoring order: deposit → reserve → issue → fitting → rework → partial
    delivery → balance; no double billing or deduction.
11. Customer fabric: custody recorded; stock value and fabric revenue unchanged; leftovers returned.
12. Measurement change after confirmation: confirmed order snapshot unchanged; other wearers unaffected.
13. Cancellation before and after cutting follows the configured policy.
14. Tailor sees only assigned jobs; cannot change prices, see the customer list or refund.
    Cross-branch access denied by the database.
15. Reports exclude drafts, separate deposits from sales, subtract returns; old margins unchanged
    after cost changes; large date ranges correct beyond one API page.
16. (E2E) Till close with sales, deposits, collections, refunds and cash expenses; variance shown.
17. Backup restore recovers sales, measurements, fabric custody and open jobs.
18. (If FBR) Invoice submitted once; offline queue re-submits; QR printed.
19. Public API: anonymous visitors see only published, active products; cost, supplier and
    movement data unreachable; unpublished product URL returns not found.
20. Same last item bought online and sold in store at the same moment: exactly one succeeds; the
    other gets a clear "sold out" result.
21. Online order reservation expires: stock returns to available; a late payment notification for
    an expired order is flagged for refund, not silently fulfilled.
22. Duplicate or replayed payment webhooks, invalid signatures and client retries: one payment, one
    order, one stock deduction; invalid signatures rejected.
23. Online cancellation and refund: reservation released or stock returned; refund recorded against
    the payment; reports show it as a return, not a negative sale.
24. Customer privacy: customer A cannot read customer B's orders, requests, measurements or
    progress updates; staff-only notes never reach the website; a customer login has no POS access.
25. (E2E) Website tailoring request → staff quote → customer accepts → tailoring order created with
    the confirmed measurements and charges; customer sees approved progress only.

---

## 8. Risks and mitigations

| Risk | Mitigation |
|---|---|
| License refused | Ask in Phase 0 (D1); new schema/screens replace most original code |
| FBR integration effort or approval delays | Decide in Phase 0; build in Phase 3b with sandbox first |
| Internet/power outages stop sales | UPS + hotspot + paper procedure (D4); review after pilot |
| Tailoring is the largest, least certain phase | Separate Release 2; real retail data first; weekly owner demos |
| Messy existing stock data | Mapping sheet, dry-run imports, physical count before go-live |
| Busy season overload | No go-live before Eid; booking cut-off and capacity warnings |
| Hardware surprises | Buy and test in Phase 0 |
| Staff adoption | Training in each pilot; printed quick guides; simple tailor slips |
| Online payment integration delays | Launch online checkout with cash on delivery first; add the provider when approved |
| Overselling between website and store | One stock ledger, server-side reservations, row locks, concurrency tests (tests 20–22) |
| Customer data exposure | Separate staff/customer accounts, narrow public views, privacy tests (test 24), security review in Phase 10 |

---

## 9. After Release 3 (prioritise from real usage)

Pickup reminders (WhatsApp Business API with consent), alteration-only jobs, tailor capacity
scheduling, piece-rate labour settlement, purchase orders and supplier balances, seasonal markdowns,
loyalty, courier API integration, marketplace listings, branch transfers (dispatched / in transit / received),
full offline selling, accounting export.

---

## 10. Immediate next steps

1. Send the license request to the original author (D1).
2. Ask the tax adviser about FBR POS integration and service tax on stitching (D3).
3. Confirm decisions D2 and D4–D12 (defaults above are fine to start).
4. Start Phase 0: local Supabase, test tooling, CI, lint clean-up, TanStack Query.
5. Apply for the Easypaisa merchant account (D14) early, with card payments enabled; approval can take weeks.
6. Collect brand assets for the website (logo, colors, fonts, product photography guidelines).
