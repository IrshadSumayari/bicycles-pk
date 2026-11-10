# Customer and POS order tracking

The customer website now has an authenticated /account/track lookup and a progress panel on order details. Customers enter a WEB order number using the email account that placed it. Existing ownership checks apply; there is no public phone/order-number lookup or anonymous tracking token. Invalid, foreign and unavailable orders share a generic failure message.

The panel shows preparation and shipping progress, the courier/CN, a copy button, the latest staff shipment note and the existing timestamped order timeline. Refresh order status retrieves current data and shows the time checked in Pakistan time. Pickup uses Ready for pickup / Collected stages and no courier links. Cancelled, expired and returned-to-sender cases show explicit notices rather than claiming successful delivery.

## Staff operation

POS → Online orders supports search by order number, phone, courier or tracking number. Submitting a nonempty search clears the initial status filter so shipped orders can be found; staff can then apply a status filter. The table displays courier and CN.

After a delivery order is shipped, use Shipment tracking to correct courier/CN or record In transit, Out for delivery, Delivery attempted or Delivery delayed. A 3–500 character public message is mandatory; it appears in the customer's timeline. Each entry includes the courier/CN at the time of the update. Admins, managers and cashiers can update permitted branches; inactive staff and website customers cannot.

Only tracking corrections remain available after delivery or returned-to-sender. Shipment notes do not mark an order delivered, collect COD, send refunds or move stock. Continue using the existing fulfilment, COD payment and returned-parcel actions for those operations.

A tracking_version counter rejects stale edits. Request IDs protect retries, including cross-user and cross-order reuse. The edit form preserves an uncertain request until retry or order refresh. Order list/detail and raw order, line, event and payment reads enforce branch membership.

## Courier support and limits

The owner has not chosen a courier. Both supported names open a fixed official page in a new tab; the customer enters their CN there:

- [PostEx](https://postex.pk/tracking)
- [Leopards Pakistan](https://pk.leopardscourier.com/)

These pages were checked against the official websites. No customer CN, address or contact details are placed in external link URLs; arbitrary courier URLs are not accepted. Other courier names retain the CN and support path without inventing a tracking link.

This is staff-recorded tracking with links to courier scans. No courier API polling, webhook, label booking, GPS, delivery-date estimate or email/SMS notification is implemented. Automatic updates require the chosen courier's merchant/API access and a separately reviewed integration.

## Rollout and verification

Order tracking is part of the baseline migration, which adds tracking_version, the guarded update RPC and branch-scoped search/read policies. Existing orders default to version zero. No API credentials are needed for manual tracking.

This task applied and replayed the migration only in the isolated local database. Hosted staging and production were not changed by the task.

Verification:
- 221 POS tests, 54 website tests and 1,035 database assertions, including 42 tracking checks.
- Both apps passed TypeScript, lint and production builds. Existing POS lint warnings and the chart bundle size warning remain.
- Browser checks covered sign-in redirect preservation, invalid/unavailable lookup, normalized order lookup, pickup, courier correction, CN search across statuses, staff update → customer refresh, copy feedback, PostEx/Leopards links and dark/light appearance.
- Customer layout fit 345 CSS px and POS 354 CSS px without document overflow. The tracking table scrolls within its container.
- Disposable local accounts/orders/product/stock fixtures were removed through a verified local reset. All migrations replayed and the database suite passed again.

Real courier scans and automated updates have not been tested because no merchant account/provider is selected.
