# Store setup and courier returns

## Store identity

POS receipt identity is edited in **Settings → Store**. The website identity is in `website/content/brand.json`; editing the POS receipt does not change that file. The address, phone, hours and contact details must be confirmed by the owner before launch (see section 1 of [LAUNCH.md](./LAUNCH.md)).

## Catalogue entry

**Inventory → Import products from a spreadsheet** offers a header-only blank template and a separate example download. Fill the blank CSV with one row per real variant, using the real price, cost and physically counted opening stock. Do not import the example rows as real inventory.

- `size` is the frame size (XS–XL) or, for kids bikes, the wheel size.
- `fit` is the variant, for example `7-speed`.
- Specifications (frame, wheel size, gears, brakes, motor, battery and so on) and the *Bulky item* setting are added per style in the style editor after import.

Photos and publishing are separate, through each style's **Website** tab.

## Delivery settings

An administrator sets these under **Settings → Online orders**:

- delivery fee and optional free-delivery subtotal
- bulky charge per bike, added to delivery for each bulky item
- assembly fee per bike; leave blank to not offer assembly
- cash on delivery on or off, and the optional maximum COD total

Blank thresholds save as empty; zero amounts and disabled COD are kept. The database validates amounts and decides checkout eligibility. Pickup has no delivery fee. The fees are flat amounts, not courier quotes; get real courier prices for packed bike boxes (weight, dimensions, destinations, returns) before choosing them.

## Undelivered COD parcel returned by courier

This is different from a customer returning a paid purchase. A manager or admin opens a **shipped, uncollected COD delivery order** in Online orders:

1. Wait until the complete parcel is physically back. For missing or partial contents, resolve the difference before using this whole-parcel action.
2. Enter the actual return reason and the total courier cost (outgoing plus return charges, zero when none). This is a reconciliation record, not an expense payment.
3. Inspect every item and choose resaleable, damaged or faulty. Check bikes for transit damage to the frame, wheels, derailleur and brakes.
4. Confirm physical receipt and select **Receive parcel**. One database transaction records the return, reverses the sale value including the delivery charge, and restores only resaleable tracked items to their original locations.
5. The order becomes *Returned to sender* with payment status *Unpaid*. No customer payment, cash refund, store credit or courier payment is created. Recorded courier costs stay visible to managers.

Retrying the request reuses the same receipt; the order cannot be received twice. Customers, cashiers, other branches, packed or unshipped orders and paid orders cannot use this action. A returned order cannot continue to delivery or COD collection.

Paid returns go through the normal sales return and refund workflow.
