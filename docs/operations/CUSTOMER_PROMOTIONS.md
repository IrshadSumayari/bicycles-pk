# Customer promotions - contact capture and campaign preparation

This release prepares customer records, email/SMS preferences, eligible recipient lists,
CSV exports and campaign drafts. It does not send messages. The owner will provide both
delivery providers. No live provider credentials are required for this phase.

## Operating the feature

- POS cart: select an existing customer or choose **Add new customer**. Save a name
  and at least a phone or email. The saved customer is selected for that sale.
- Customers: **Customer directory** manages contacts; **Promotional email & SMS**
  provides audiences and drafts for administrators/managers.
- Each channel has **Not asked**, **Customer agreed**, or **Declined / unsubscribed**.
  Never infer permission from a purchase or the historical general website checkbox.
- Website customers can change their two preferences in **My profile**.
- Contact edits clear the corresponding permission. Save the new contact first, then
  record fresh permission. Existing consent is never silently transferred to a new number.
- Audiences deduplicate normalized destinations across POS and website. Any explicit
  opt-out for the same destination suppresses it, even when another record opts in.
- CSV exports are explicitly **this page**, up to 50 contacts, and re-query permissions
  at export time. Phone numbers and formula-like text are spreadsheet-escaped. Exported
  lists can become stale: always recheck current permission before a future campaign.
- Drafts are stored on the server. Saving a draft sends nothing and does not freeze a
  recipient list. The latest 100 drafts are displayed.

## Deployment

Apply `20261030000300_customer_promotions.sql` before deploying the POS and website.
The migration adds nullable channel preferences to customers/customer_accounts,
server timestamps and an audit log, a manager-only audience RPC and draft-only campaigns.
Old contacts remain not asked. The POS displays a backend error if migration is missing;
do not enter fake email addresses to work around it.

## Provider phase (pending owner details)

Obtain provider names, verified sender identities and server-side credential configuration.
Implement authorized explicit campaign dispatch, current-consent checks per recipient,
durable queue/idempotency and retries, unsubscribe handling, suppression lists, provider
webhooks, delivery/failure status, SMS segmentation/cost preview and controlled tests.
Website profile withdrawal is available now; one-click email/SMS provider opt-out and
automated delivery are not yet implemented. Do not present this release as a sending system.

## Validation

`src/lib/marketing.test.ts` checks CSV escaping. Database regression tests cover per-channel
consent, contact changes, normalized deduplication, cross-source suppression, role restrictions,
audit integrity and draft-only state. Run on a rehearsal database, never reset production.
