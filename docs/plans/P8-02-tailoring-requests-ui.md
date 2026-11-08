# P8-02 Tailoring requests: website form and POS inbox

**Branch:** `feat/web-tailoring-ui`
**Needs:** P8-01 merged.
**Files:** `website/` (auth, request form, my account pages) and POS
`src/components/tailoring/RequestsInbox.tsx` (+ `RequestDetail.tsx`, `QuoteForm.tsx`,
`ConvertRequestModal.tsx`), `src/components/tailoring/TailoringManager.tsx` (new tab),
`src/lib/tailoring.ts`.
**No migration** (report any missing database piece instead of adding it).

## Website
1. **Sign in** `/account/sign-in`: email → 6-digit OTP (`supabase.auth.signInWithOtp` +
   `verifyOtp`), using `@supabase/ssr` cookies so server components know the user.
   Sign-out. Middleware protects `/account/*`.
2. **Profile** `/account`: name, phone (normalised display), marketing consent checkbox
   (unchecked by default); "Link my shop account" button calls `link_customer_account()`
   and explains the in-shop alternative if the phone is not verified.
3. **Stitching request** `/stitching/request`: garment type (from a public function — add
   `catalog_garment_types()` **only if** P8-01 did not; otherwise use what exists), quantity,
   fabric source (store fabric picker from `catalog_list` filtered to fabric kind / bring my own /
   not sure), design notes, up to 5 photos (client-side resize like the POS `images.ts`, upload to
   `tailoring-photos/requests/<uid>/`), preferred date, "I want a measurement appointment" with a
   slot picker (`appointment_slots`). Submit with a generated `request_id` kept across retries.
4. **My requests** `/account/requests` and detail page: status, public messages timeline, quote
   (charges, total, deposit, promised date, valid until) with **Accept** / **Decline**, cancel,
   progress (`my_order_progress`) when converted. Shareable WhatsApp link to the detail page
   (requires login to view).
5. Show friendly errors from the functions (rate limit, expired quote).

## POS
1. **Requests** tab in `TailoringManager` (counter staff): list with status filter and counts
   badge in the header nav; detail panel with photos (signed URLs, 10 min), customer info,
   preferred date, appointment, staff notes (editable), public message box (adds an event).
2. **Quote** form: charges lines (default from `garment_types.default_charge`), fabric
   (store variant + meters, or customer fabric), deposit required (default from settings
   `min_tailoring_deposit_percent` if P5-06 is merged), promised date, valid-until (default 7 days).
3. **Convert** (when accepted): reuse the measurement and payment parts of `OrderIntake.tsx`
   (extract shared components instead of copying) and call `convert_tailoring_request`; on success
   open the new order's slip (`OrderSlip`).
4. Appointments list for today/tomorrow with confirm/cancel.
5. WhatsApp quick message to the customer when a quote is sent (reuse `whatsappReadyLink` style).

## Tests
- Website Vitest: form validation helper, quote total display, status label mapping.
- POS Vitest: any pure helpers (e.g. quote totals).
- Manual E2E (describe the steps and result in your report): sign in on the website with Inbucket
  (local Supabase email testing at http://127.0.0.1:54324) → submit request with a photo → POS
  quotes → website accepts → POS converts → website shows progress; customer B cannot open A's
  request URL.

## Done when
All POS and website checks pass and the manual E2E works on local Supabase.
