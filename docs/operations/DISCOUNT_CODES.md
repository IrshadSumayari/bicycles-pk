# Discount codes

Two kinds of code, both managed under **Discounts → Discount codes** (admins and managers).

## Welcome codes for new customers

- **Welcome code for new customers**: tick the box, choose percent or amount, the value,
  how many days it lasts, and optionally a minimum spend and (for percent) the most it can
  take off. It is off until someone switches it on.
- Every customer added after that (POS, Customers screen or website) gets a personal code
  such as `LV-7KQ2XH`. It works only for that customer and only once.
- Changing the offer applies to codes given from then on. Codes already given keep theirs.
- Existing customers: open the customer, **Give welcome code** (managers).

## Codes for sales and campaigns

**Create code**: type a code (e.g. `EID14`) or leave it empty to make one. Choose percent or
amount, optional minimum spend / maximum discount, start and last day, and the number of
uses (empty means unlimited). Click a code's status to switch it off or on.

## At the till

In **Complete Payment**, type the code and press **Apply**, or tap one of the selected
customer's codes. The server checks it and shows a clear reason if it cannot be used
(misspelt, expired, used, belongs to another customer, minimum spend). The receipt lists
the code. A code is used up only when the sale is saved; drafts do not use it.
Returning items does **not** give the code back.

Codes add to any automatic promotions running at the same time. They work at the POS
only, not yet in website checkout.

## Emailing a code

The customer screen shows an email button for a ready code when the customer has an email
and has agreed to email offers. It opens the staff member's own mail app with the message
written; the POS itself sends nothing. Automatic sending waits for the email provider
(see `CUSTOMER_PROMOTIONS.md`).

## Deployment

Apply `20261103000000_discount_codes.sql`, then deploy the POS. Welcome codes stay off
until a manager switches them on.
