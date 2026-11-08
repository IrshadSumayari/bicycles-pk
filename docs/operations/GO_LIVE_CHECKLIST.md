# Go-live checklist

Store: **[name]** · Go-live date: **[date]** · Owner: **[name / phone]**

Keep this signed copy with the opening stock count and the numbered paper books.
The installer and owner must finish the rehearsal before live trading. Never run a
local reset against the live shop or import opening figures after trading starts.

## Day before — prepare and reconcile

- [ ] **Owner + installer:** Create the Supabase **Pro** project, confirm billing and
  region, and record the project reference securely. Follow the
  [backup guide](BACKUP_AND_RESTORE.md). Keep live and development projects separate.
- [ ] **Installer:** Check out the approved release, install dependencies with
  `npm ci`, link the correct live project, and apply migrations with
  `npx supabase db push`. Confirm all migrations including the go-live import applied.
- [ ] **Installer:** Deploy the Edge Functions with `npx supabase functions deploy
  admin-users`. Verify its required environment variables and administrator checks
  against `supabase/functions/admin-users/index.ts`. Keep privileged keys out of
  browser build variables and source control.
- [ ] **Installer:** Set the Auth site URL and allowed redirects for the deployed
  till. Create the first administrator through the initial setup, then disable
  public email sign-ups in Auth. The POS does not offer public staff registration;
  subsequent staff accounts are created through Users by an administrator.
- [ ] **Owner + administrator:** Create named manager, cashier and tailor accounts,
  assign roles and active status, test each login and keep passwords private.
- [ ] **Owner + manager:** Review Settings: PKR currency, tax, maximum cashier
  discount, return window, minimum tailoring deposit %, receipt header/footer,
  store address/phone and cash difference alert. Print and approve a receipt.
- [ ] **Stock manager:** Import products and opening stock with Product Import.
  Do not also enter a second opening adjustment for the same stock. Print labels
  and scan a selection of sizes, colours, packs and fabric rolls.
- [ ] **Owner + accountant:** Total the old customer debt book. Prepare
  [opening-balances.csv](samples/opening-balances.csv) with **real** names, phones,
  amounts and notes; the supplied five rows are fictitious examples. Use one
  positive opening balance per customer. Keep the signed source totals.
- [ ] **Administrator:** In **Settings → Go-live import → Customer balances**,
  download the template, upload the reviewed file and check every preview row.
  Correct errors before importing. Compare the imported total and skipped reasons
  with the book, then check customer balances. Existing openings are skipped;
  they are never overwritten. A phone such as `03001234567` matches `+923001234567`.
- [ ] **Owner + tailoring manager:** Prepare
  [open-tailoring-orders.csv](samples/open-tailoring-orders.csv) from unfinished
  slips. One row is one garment; repeat the same paper reference, customer, dates,
  **whole-order deposit** and notes on all its rows. Do not split or add up that
  repeated deposit. Set `item_status` to awaiting, cutting, stitching, fitting,
  finishing, quality_check or ready. Use YYYY-MM-DD dates and inches for measurements.
- [ ] **Administrator:** Download the current tailoring template (its measurement
  headings come from active garment types). Upload and preview the paper orders.
  Import and reconcile the final successes and failures against every slip.
  Retry failed orders with the same loaded file; completed orders are not sent again.
  A paper reference can only be imported once, including after re-uploading a file.
- [ ] **Tailoring manager:** Check each imported order's total, historical deposit,
  balance, promised date and garment stages. Imports only support customer fabric.
  The CSV has no fabric quantities: it does not invent custody lengths or move stock.
  Keep the labelled customer cloth with the paper slip. Store-fabric orders need
  reconciliation by the installer before import; never import them as customer cloth.
- [ ] **Accountant:** Customer opening debts and order balances are separate.
  Exclude unpaid tailoring balances from the customer debt CSV if they are also
  represented by imported open orders, or the same debt will be counted twice.
- [ ] **Stock manager + owner:** Count a sample of physical stock, compare it with
  the POS, and resolve discrepancies before signing the opening inventory.
- [ ] **Installer + owner:** Rehearse a sale, return, tailoring deposit, balance
  collection, delivery and shift close using the real printer, scanner and card
  machine. Reconcile the terminal receipt and POS entry; do not charge a card twice.
  Use a rehearsal project for practice. If live test transactions are required,
  retain their real receipts and reverse/reconcile them through normal functions.
- [ ] **Owner + installer:** Run a database backup and a **local-only** restore
  rehearsal using [BACKUP_AND_RESTORE.md](BACKUP_AND_RESTORE.md). Compare counts,
  receipts, Urdu names and balances. Copy the complete backup off the till and
  sign the monthly log. Copy Storage image files separately if used.
- [ ] **Owner:** Prepare numbered carbon-copy sales books, pens, contact numbers
  and the printed [offline procedure](OFFLINE_PROCEDURE.md) beside each till.

## First trading day — open carefully

- [ ] **Owner + manager:** Sign off the imported stock, customer debts and paper
  orders. Historical deposits must settle their orders but must not appear in the
  Payments report or shift cash. Tailoring order intake uses the original slip date;
  later balance receipts count as balance collected.
- [ ] **Cashier + manager:** Confirm the green connection indicator, sign in using
  individual accounts, count the float and open the cash shift before taking cash.
- [ ] **Manager:** Train cashiers: scan and check size/colour; select the right
  customer; check price and tender; give change and a receipt; follow discount and
  return permissions; collect the correct tailoring deposit; label customer cloth;
  check remaining balance before delivery; use the paper book when offline.
- [ ] **Manager:** Explain uncertain payment errors: check Transactions before
  collecting again. Reopening checkout with the same basket reuses the pending
  request for 30 minutes. Do not change the basket to bypass an uncertain payment.
- [ ] **Manager:** Observe the first real sale, return and tailoring payment.
  Check their receipts, balances and Payments report against the cash and terminal.
- [ ] **Cashier + manager:** At close, reconcile cash, card and digital payments;
  enter any paper sales once with their paper numbers; count and close the shift;
  review any cash difference. Record and assign any unresolved discrepancy.
- [ ] **Owner:** Confirm the first hosted backup is available, the weekly export
  owner is assigned and the next monthly restore rehearsal is in the diary.

Approved to trade: **[owner / signature / time]**

Opening discrepancies and action owner: **[details]**
