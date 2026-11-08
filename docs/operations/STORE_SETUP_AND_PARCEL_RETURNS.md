# LadyVogue store setup and courier returns

## Confirmed business details

The owner confirmed an online business with a physical presence in Sector I-8/2, Islamabad, Pakistan, phone +923398844517, and Pakistan-wide delivery. Website contact/location/shipping copy reflects those details. Visitors are asked to contact the business before visiting; no exact street pin, opening hours, email or WhatsApp availability is invented.

POS receipt identity remains editable in Settings → Store. The website identity is configured in `website/content/brand.json`; editing POS receipt identity does not synchronize that file. Real product inventory, photos, legal identity and customer return eligibility still require owner input.

## Catalogue entry

Inventory → Import and Jewellery → Import now offer a header-only blank template and a separate, clearly labelled example download. Fill the blank CSV with one row per actual variant, using real price, cost and physically counted opening stock. Do not import example rows as real inventory. In jewellery, `color` describes finish and `fit` describes design; one pair/set sold together is one stock item. Photos and publication remain separate, through each style's Website tab.

## Delivery settings

An administrator can set delivery fee, optional free-delivery subtotal, COD enabled/disabled and optional maximum COD total under Settings → Online orders. Blank thresholds save as null; zero amounts and disabled COD are preserved. The existing server validates amounts and determines checkout eligibility. Pickup has no delivery fee. The flat fee is not a courier booking quote or a city-coverage engine.

No hosted delivery fee, free-delivery promise or COD limit was changed by this branch. On 27 October 2026 the official [Leopards e-commerce page](https://pk.leopardscourier.com/business/ecommerce-economy) described Retail COD and nationwide services, but did not provide one fixed nationwide booking price. Obtain a quote for actual packed weights, dimensions, destinations, collection/remittance and return terms before deciding a customer-facing flat fee. [Official rate calculator](https://pk.leopardscourier.com/rate-calculator).

## Undelivered COD parcel returned by courier

This is distinct from a customer returning a paid purchase. After deploying the migration and matching POS, a manager/admin opens a **shipped, uncollected COD delivery order** in Online orders:

1. Wait until the complete parcel is physically back. For missing/partial contents, resolve the discrepancy before using this whole-parcel action.
2. Enter the actual return reason and total courier cost (outgoing plus return charges, zero when none). This is a reconciliation record, not an expense payment.
3. Inspect every item. Choose resaleable, damaged or faulty explicitly. Apply the business's approved hygiene/resale policy; opening lingerie does not automatically make it resaleable.
4. Confirm physical receipt and select Receive parcel. The database transaction records one return, reverses the sale value including charged delivery, and restores only resaleable tracked items to their original picking locations.
5. The order becomes Returned to sender and payment status Unpaid. No customer payment, cash refund, store credit or courier payment is fabricated. Recorded courier costs remain visible in the order to managers.

Request retries reuse the same receipt; a new request cannot receive that order again. Existing sales return lines prevent a second reversal. Customers, cashiers, other branches, packed/unshipped orders and paid orders cannot use this action. A returned order cannot continue to delivery or COD collection.

Paid COD/prepaid returns continue through the existing sales return/refund workflow, reconciling the actual payment and refund. This branch does not introduce automatic prepaid refunds, partial courier returns, reshipment, courier bookings or courier remittance/expense accounting. Customer returns and paid-return lifecycle acceptance remain pending the deferred customer checkout rehearsal.

## Validation

207 POS tests, 43 website tests and 866 database checks across 32 local suites passed, including the new courier-return transaction and public-access security coverage. POS TypeScript, changed-file ESLint and both production builds passed. An isolated browser preview checked delivery controls, explicit condition selection, physical-receipt gating and the downloaded header-only CSV. Preview files were removed. Screenshot capture was unavailable, so no visual screenshot evidence is claimed.

The migration was applied only to the isolated local LadyVogue database. No staging/production schema, inventory, orders, payments or delivery settings were changed. Deployment and hosted acceptance remain separate steps after owner PR review.
