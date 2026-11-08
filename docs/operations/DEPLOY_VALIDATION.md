# Deployment preparation validation

Branch: `chore/deploy`, based on develop `4cbd02a`.

## Delivered

- Migration `20261030000100_online_card_switch.sql`: card/wallet off by default, explicit allowed methods in quotes, database refusal while disabled, administrator-only switch using the latest settings body. Existing idempotency, fabric cuts, grants, staff trigger behavior and manager receipt permissions are retained.
- Payment-create independently checks the server setting. All three payment functions reject mock configuration at startup unless SITE_URL has the exact localhost/127.0.0.1 host. Confirmation/refunds for existing payments remain possible with a real configured provider when new card checkout is disabled.
- Checkout presents only server-allowed methods and defaults to COD; the POS online settings section exposes the administrator switch with the requested help text. Regenerated database types are included.
- Vercel website configuration (Node 22, npm 10.9.9), per-environment public examples, environment-rendered POS CSP/headers (originally for Cloudflare Pages; the POS now deploys to Vercel, see DEPLOY.md), and an exact-SHA CI-gated Supabase workflow with staging/production environments.
- Owner runbook [DEPLOY.md](./DEPLOY.md), hosted storage/cron verification, and read-only deployment checker with tests. CI now includes payment/deployment helper tests and repeats database tests.

## Required check results

Logs are retained locally in ignored `backups/deploy/`; no credentials are included in this report.

| Command | Final output / result |
| --- | --- |
| `npm run db:reset` | Passed; all 35 migrations applied, including the new switch |
| `npm run test:db`, run 1 | **33 files / 1,056 tests**, Result: PASS |
| `npm run test:db`, run 2 | **33 files / 1,056 tests**, Result: PASS |
| `npm run db:types` | Passed; generated types include the new boolean |
| `npm test -- --maxWorkers=1` | **23 files / 175 tests passed** |
| `npx tsc -b` | Passed, no diagnostics |
| `npm run lint` | **0 errors / 10 existing warnings** |
| `npm run build` | Passed; existing large chart-chunk warning |
| `npm run test:e2e` | **2 passed** |
| `npm run web:lint` | Passed, no errors or warnings |
| `npm run web:test -- --maxWorkers=1` | **10 files / 43 tests passed** |
| `npm run web:build` | Passed; optimized production build, type checks and route generation |
| Website `npx -y npm@10.9.9 install` | Passed; Node 22 engine declaration synchronized |
| Website `npx -y npm@10.9.9 ci --dry-run` | Passed; **105 packages** simulated, no sync error |
| `npx vitest run --config supabase/functions/_shared/payments/vitest.config.ts --maxWorkers=1` | **54 tests passed** |
| `node --test scripts/deploy/deploy.test.mjs` | **4 tests passed** |
| `git diff --check` | Passed |

The initial full-suite attempt temporarily found no public schema. After confirming the local schema was present, the isolated new test and both complete suite runs passed. Existing payment-flow suites explicitly opt in to card payments inside their rollback transactions; the new suite verifies the real disabled default and role restrictions.

## Local deployment checker

Executed against **website localhost:3000**, **POS localhost:5173** and the existing local Supabase, using only its public anon key. A disposable published, stocked local item supplied the quote. No hosted project, hosting account, DNS, SMTP or provider secrets were accessed. The fixture is removed by a final local reset; task-owned app/function servers are stopped.

```text
PASS Website loads locally
PASS Website security headers
PASS POS loads locally
PASS POS security headers : validated dist/_headers; verify HTTP headers after Pages deploy
SKIP www redirect : no local www DNS/TLS
PASS catalog RPC answers
PASS anonymous staff functions refused
PASS payment-create refuses missing JWT
PASS quote offers COD only
PASS Website browser / network
PASS POS browser / network / sign-in
```

Vite dev does not apply Cloudflare response headers, so local mode validates the exact rendered `dist/_headers` instead. Hosted mode checks actual responses, HTTPS/HSTS, www-to-apex redirect and forbids loopback network requests. The staging URL check verifies www on the corresponding apex, not a nonexistent www.staging hostname. Public catalog data is required for the quote check; an empty catalog fails instead of claiming COD was verified. The checker never submits a customer order or authenticates as staff.

## Owner-only work and decisions

- No accounts were created/linked, no hosting CLI was run, no production deployment, push or PR was made. No Vercel project link exists in either repository root or website root. The runbook explicitly excludes the unrelated client scope and requires explicit approved scope on any future Vercel CLI command.
- Vercel outside-root source inclusion must be enabled: the website imports generated types from the POS source tree. Building with website as the working directory passed locally; the actual Vercel build remains unverified.
- Vercel Hobby's non-commercial restriction means the owner must select an appropriate commercial plan in the approved personal/shop scope. Cloudflare's develop custom alias requires proxied Cloudflare DNS. The runbook documents these provider requirements with official sources.
- GitHub required reviewers are dashboard/plan configuration, not enforceable solely by this YAML. The owner must verify the production gate. workflow_run also requires the workflow on the default branch; first-install instructions cover that. Git app builds can happen independently of the backend job, so the runbook keeps releases protected until matching migrations complete.
- Both storage buckets, their policies, pg_cron activation and the every-minute expiry job already exist in migrations. No extra migration/seed dependency was needed. Hosted privileges, extension activation, cron execution and bucket policies still require owner checks; local config is not proof.
- Hosted HTTPS/redirects, custom domains, DNS, SMTP/email delivery, environment isolation, review gates, live manual COD/shift/return/tailoring tests and backup recovery remain unverified. Follow the staging checklist in DEPLOY.md before releasing.
- Easypaisa is still a deliberately disabled adapter pending the real integration task. Launch keeps both its UI and new card/wallet orders off. No sandbox credentials were used. No new dependency package was added; website install continues to report the five pre-existing high-severity advisories, outside this deployment-preparation change.
- The owner examples contain only variable names/placeholders/public configuration. All function/SMTP/GitHub credentials remain owner-managed. Unrelated local plan documents, screenshots and source logo are excluded from commits.

Final review also moved the existing inline POS appearance bootstrap into a self-hosted script so the static script-src self policy preserves pre-paint dark mode. An existing stock-count test SQL helper compared its sku argument ambiguously with the column name, producing an arbitrary result on one repeated run; qualifying the argument as $1 fixes the test without changing stock-count application logic.

The final local POS rehearsal used a static production preview on port 5173 that applied the generated Pages headers to HTTP responses. The browser check passed with CSP-console violation detection enabled. A separate check confirmed the actual script-src self response, external bootstrap execution and persisted dark appearance with zero CSP violations.
