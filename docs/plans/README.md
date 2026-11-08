# Execution plans

Each file is **one pull request**, written so a coding agent can do it without any other
context than this repository. Hand them over **one at a time, in this order**.

## How to use

1. Give the agent `docs/plans/00-AGENT-GUIDE.md` plus **one** plan file.
   Prompt: *"Read docs/plans/00-AGENT-GUIDE.md, then implement docs/plans/<file>. Follow the
   guide exactly. Work on the branch named in the plan, commit locally, do not push. Report
   back as section 6 of the guide describes."*
2. Bring the result back for review (branch name or `git diff develop...<branch>`).
3. After review it is pushed and a PR is opened into `develop`. Merge it, then start the next plan
   from the updated `develop`.

## Order

| # | Plan | Branch | Depends on |
|---|---|---|---|
| 1 | [P5-01 Report functions](P5-01-report-functions.md) | `feat/reports-db` | â€“ |
| 2 | [P5-02 Reports screen](P5-02-reports-screen.md) | `feat/reports-ui` | P5-01 |
| 3 | [P5-03 Transactions on server data](P5-03-transactions.md) | `feat/transactions-v2` | â€“ |
| 4 | [P5-04 Shift history and variances](P5-04-shift-history.md) | `feat/shift-history` | â€“ |
| 5 | [P5-05 Customer accounts and credit collection](P5-05-customer-credit.md) | `feat/customer-credit` | â€“ |
| 6 | [P5-06 Settings cleanup and garment types editor](P5-06-settings.md) | `feat/settings-v2` | â€“ |
| 7 | [P5-07 Stop loading everything at startup](P5-07-startup-data.md) | `refactor/startup-data` | P5-02, P5-03, P5-05 |
| 8 | [P5-08 Backups, connection status, paper fallback](P5-08-resilience.md) | `chore/resilience` | â€“ |
| 9 | [P6-01 Data migration and go-live](P6-01-go-live.md) | `feat/go-live-import` | P5-05 |
| 10 | [P6-02 FBR invoice integration](P6-02-fbr.md) | `feat/fbr` | **only if the tax adviser says it is required** |
| 11 | [P7-01 Website catalog: database](P7-01-catalog-db.md) | `feat/web-catalog-db` | â€“ |
| 12 | [P7-02 Publishing from the POS](P7-02-publish-ui.md) | `feat/web-publish-ui` | P7-01 |
| 13 | [P7-03 Website app: catalog pages](P7-03-website-catalog.md) | `feat/website-catalog` | P7-01 |
| 14 | [P8-01 Tailoring requests: database and customer login](P8-01-tailoring-requests-db.md) | `feat/web-tailoring-db` | P7-03 |
| 15 | [P8-02 Tailoring requests: website form and POS inbox](P8-02-tailoring-requests-ui.md) | `feat/web-tailoring-ui` | P8-01 |
| 16 | [P9-01 Online orders: database](P9-01-online-orders-db.md) | `feat/web-orders-db` | P7-01 |
| 17 | [P9-02 Easypaisa payments (card + wallet)](P9-02-payment-webhook.md) | `feat/web-payments` | P9-01, Easypaisa sandbox credentials |
| 18 | [P9-03 Cart, checkout and POS order queue](P9-03-cart-checkout-ui.md) | `feat/web-checkout-ui` | P9-01, P9-02, P7-03 |
| 19 | [P10-01 Website launch checklist](P10-01-launch.md) | `chore/web-launch` | all of the above |

### MatDash design system (after the storefront plans P19 and P20 are merged)

Give the agent `00-AGENT-GUIDE.md` + [P11-00 overview](P11-00-matdash-overview.md) + one plan.

| # | Plan | Branch | Depends on |
|---|---|---|---|
| M1 | [P11-01 POS design system](P11-01-pos-design-system.md) | `feat/ui-theme` | P19, P20 |
| M2 | [P11-02 POS shell and dashboard](P11-02-pos-shell-dashboard.md) | `feat/ui-shell` | P11-01 |
| M3 | [P11-03 POS screens](P11-03-pos-screens.md) | `feat/ui-screens` | P11-02 |
| M4 | [P11-04 Website on the MatDash design system](P11-04-website-theme.md) | `feat/web-theme` | P11-01, P19, P20 |

Plans marked "â€“" in *Depends on* only need the current `develop`, but still do them in order:
each migration timestamp in the plans is chosen so they apply in sequence.

## Decisions confirmed by the owner

- Website: **Next.js** app in `website/` (P7-03 onward).
- Online payments: **Easypaisa** gateway for **credit/debit cards** and the **Easypaisa wallet**;
  cash on delivery stays as a configurable option (P9-01 to P9-03).

## Review checklist (used when a result comes back)

- Scope: only the files the plan names (plus generated `database.types.ts`).
- Migration: new file, later timestamp, re-runnable, RLS on new tables, grants revoked from `anon`.
- Every write function: role check, idempotency, row locks, plain-English errors.
- pgTAP tests cover the happy path, retries, and every refused role.
- No `any`, no direct `supabase` calls in components, no secrets in `VITE_` variables.
- All checks in section 2 of the guide pass; `test:db` passes twice in a row.
