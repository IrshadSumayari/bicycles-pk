# Online return requests

Owner decision (28 October 2026): accept every request for **staff review**. No automatic eligibility, refund, exchange, request window, hygiene exclusions or return-postage promises have been approved.

## Customer and staff flow

A signed-in website customer opens a delivered order, selects affected lines and quantities, chooses a reason and preferred resolution, and describes the problem. One request is allowed per order; all affected items should be included. Other order problems and further concerns on closed requests use the Contact page.

Admins and branch managers use POS → Online orders → Return requests. Cashiers cannot access reviews or evidence. The queue defaults to active requests and also supports completed statuses and pagination.

- Awaiting staff review → More information needed, Return instructions provided or Request declined.
- More information needed → the same review choices; a customer reply returns it to Awaiting staff review.
- Return instructions provided → Items received for review or Request closed.
- Items received for review → Request closed.
- Closed/declined requests cannot reopen through these controls.

Every staff transition requires a public customer update. Internal notes are separate and never included in customer responses. Before providing instructions, staff must confirm eligibility, condition/hygiene concerns, where/how to return, postage and the proposed resolution individually. Customers must wait for instructions before sending parcels.

This workflow records a review only. It does not issue refunds, create exchange sales, restock items or change order payment status. Handle the agreed financial/stock resolution separately through the appropriate existing POS/provider process. Courier returned-to-sender COD handling is unchanged. There are no automatic email/SMS notifications; staff check the queue and customers refresh their order.

## Private photos and safeguards

Customers can add up to three product photos while awaiting review or additional information. Photos are optional. Ask for the product/issue only, without bodies, faces, payment information or address labels.

The browser accepts JPEG/PNG/WebP up to 10 MiB, rejects over 40 million pixels, resizes to a maximum 1600-pixel edge and re-encodes to WebP. The private return-evidence bucket accepts WebP up to 5 MiB. Reservations use UUID-only paths; incomplete reservations can be retried. Uploaded images cannot be overwritten or deleted through customer/staff interfaces.

Storage RLS permits reads only by the order owner or active admin/branch manager, and inserts only by the owner while the request is open for information. Views use 60-second signed links and disappear from the screen after 55 seconds. They bypass the public image optimizer. A copied signed link remains usable until expiry.

Owner-approved retention and evidence-removal procedures are still required before production rollout. Authorized operators should use the Storage API/dashboard for approved removal requests; never make the bucket public or grant browser service-role access. No retention duration is advertised.

RPCs check roles and ownership before returning data; raw request tables and the private serializer are inaccessible to browser roles. Item quantities are validated against the order snapshot. Order/request locks, idempotency keys and version checks prevent duplicate submissions and stale review updates. Requests do not reuse the counter-sale return_window_days setting.

## Rollout

Return requests are part of the baseline migration; deploy it to staging before either app.

Verify private bucket access, owner/customer separation, staff branch permissions, customer replies, failure retries and photo removal operations in staging. Confirm the operating process and responsible staff before production. Real product data, the owner's deferred checkout rehearsal, hosting/domain work and final policy decisions remain separate launch tasks.

## Verification

- 216 POS unit tests, 54 website tests and 993 local database assertions (74 new return assertions).
- POS and website TypeScript, lint and production builds passed. Existing POS lint warnings and the pre-existing large chart bundle warning remain.
- Browser: local customer sign-in, validation without losing the form, selecting a purchased quantity, submission, PNG-to-WebP upload, private photo view, POS active queue/detail, staff request for information, customer reply and internal-note separation.
- Storage API: owner/staff signed views succeeded; another customer and public object URL were denied.
- Customer layout checked at 345 CSS px and POS review at 354 CSS px with no document overflow, including dark appearance. Product page exposed conditional COD, courier coverage and review/support links beside purchase controls.
- Disposable local users, order, product and photo fixtures were removed by a local reset; migration replay and database suite were rerun. No hosted data was changed.

Implementation references: [Storage access control](https://supabase.com/docs/guides/storage/security/access-control) and [signed URLs](https://supabase.com/docs/reference/javascript/storage-from-createsignedurl).

CI follow-up: photo React components now live inside their respective independently installed apps. Shared code contains only types and validation. This avoids relying on POS node_modules when the website is installed alone. The POS viewer exposes no upload control; signed-link lifetimes and access policies are unchanged.
