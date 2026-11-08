# P9-03 Website cart and checkout, POS online order queue

**Branch:** `feat/web-checkout-ui`
**Needs:** P7-03, P9-01 and P9-02 merged.
**Files:** `website/` (cart, checkout, order pages), POS new `src/components/online/OnlineOrders.tsx`
(+ `OnlineOrderDetail.tsx`), `src/App.tsx` / `src/components/layout/Header.tsx` (navigation),
`src/lib/services.ts` (`onlineOrdersService`), `src/lib/queryClient.ts`.
**No migration** (report any missing database piece instead).

## Website
1. **Cart** (client state in `localStorage` with a version key; only `variant_id` + quantity are
   stored — prices always come from `quote_online_order`): add from product page (replace the
   WhatsApp placeholder button with **Add to bag**, keep WhatsApp as a secondary link), cart drawer
   and `/cart` page with quantity changes, server quote, unavailable lines highlighted with "Remove".
2. **Checkout** `/checkout` (requires sign-in from P8-02; redirect back after sign-in):
   contact (name, phone), pickup or delivery (address form, city list), payment, three options:
   **Credit / debit card** and **Easypaisa wallet** (both through Easypaisa's hosted checkout, P9-02)
   and **Cash on delivery** (hidden when not allowed by the quote). Show card brand logos and the
   line "Card details are entered on Easypaisa's secure page". Generate `request_id` once per
   checkout attempt and keep it across retries (sessionStorage). Call `create_online_order`; for
   card / Easypaisa call `payment-create` with `method` `card` or `wallet` and redirect (auto-submit the
   returned form fields when present); for COD go to the confirmation page.
3. **Return pages**: `/checkout/return?order=WEB-...` polls `my_online_order` every 2 s (max 60 s)
   until `paid` and shows confirmation; on timeout shows "We are confirming your payment" with a
   link to the order. `/checkout/cancel` explains the hold time (show `expires_at` countdown) and
   offers retry payment.
4. **My orders** `/account/orders` and `/account/orders/[orderNo]`: status timeline (public events),
   lines, totals, tracking number/courier, **Cancel** while allowed.
5. Clear the cart only after the order is created.

## POS
1. **Online orders** screen (counter staff) with a header badge for new orders (`placed`):
   filters by status, search by order number/phone; auto-refresh every 30 s (`refetchInterval`).
2. Detail: customer + address, lines with location to pick from, payment status (with
   method: card / Easypaisa / COD, `needs_refund` warning, and a **Check payment status** button that
   calls the `payment-check` edge function from P9-02 for `initiated` payments), staff notes, event timeline, and actions by status:
   Confirm → Pack (fulfils: deducts stock, creates the sale) → Ready for pickup / Shipped (courier,
   tracking no) → Delivered; **Collect COD payment** at delivery/pickup; **Cancel** (reason);
   managers: **Record refund**.
3. Print a **packing slip** (order number, lines, address, COD amount) — same print approach as
   `OrderSlip`.
4. WhatsApp link to the customer with order number and status text.
5. After packing, invalidate stock/product queries and `queryKeys.cashShift` after cash COD.

## Tests
- Website Vitest: cart reducer (add/merge/remove/limit 10 per line), checkout form validation,
  countdown formatting.
- POS Vitest: status → allowed actions mapping (pure function).
- Manual E2E with the mock provider, and with the Easypaisa sandbox if credentials are available
  (report results): card-paid and wallet-paid orders → POS confirm/pack/ship/
  deliver; COD order → pack → collect cash at delivery (cash shows in the shift); abandoned payment
  → reservation expires and the item is available again; last unit bought online is refused at the till.

## Done when
All POS and website checks pass and the manual E2E works on local Supabase.
