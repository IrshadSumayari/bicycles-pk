# Release guide: shipping changes to staging and production

This is the routine for every release after launch. First-time setup of the
accounts, domains and DNS is in [DEPLOY.md](./DEPLOY.md).

Project references, account emails, passwords and keys are **not** written
here. Keep them in your password manager, and the non-secret ones (project
references, addresses, which account owns what) in the git-ignored file
`docs/operations/release-values.local`, so they never reach the repository.

## How the environments fit together

| | Staging | Production |
| --- | --- | --- |
| Git branch | `dev` | `main` |
| Staff POS (Vercel) | staging POS project, `platform-staging.<domain>` | `platform.<domain>` |
| Customer shop (Vercel) | staging project | `<domain>` |
| Database (Supabase) | staging project | production project |

- **CI:** pushes to dev and main run application, database and browser smoke checks. The smoke job uses Chromium Headless Shell, with a ten-minute install limit and twenty-minute job limit. Browser setup failure still fails CI; these limits do not bypass tests.
- **Hosted deployment:** after successful push CI, Deploy Supabase and Deploy shop run for the current branch head. They deploy only when the selected GitHub environment has all required secrets. A green run that reports a skipped deployment is not proof that either service was released. Read its job summary.
- **Database:** the configured Deploy Supabase workflow applies migrations and deploys its named functions. The manual commands below are a fallback when automation is not configured. Keep hosted apps protected until the matching schema and app releases are verified; independent hosting jobs do not guarantee migration-first ordering.
- **Current readiness (27 October 2026):** the staging GitHub environment exists but its secret listing is empty, and there is no local Vercel project link. The merged parcel-return update passed all GitHub CI checks, including browser smoke tests. No hosted parcel-return rollout was verified. Real inventory and customer checkout rehearsal are separately deferred.

Required staging secret names (values stay private): Supabase uses SUPABASE_ACCESS_TOKEN, SUPABASE_PROJECT_REF, SUPABASE_DB_PASSWORD; the shop uses VERCEL_TOKEN, VERCEL_ORG_ID, VERCEL_PROJECT_ID. Both apps must point to the dedicated staging backend. Configure POS hosting separately as described in DEPLOY.md. Do not copy production credentials into staging.

## Before every release: a 30-second check

1. Which branch am I releasing? `dev` = staging, `main` = production.
2. Does the change include files in `supabase/migrations/`? Then the database
   needs updating (Step 1b / 3b).
3. Does it change `supabase/functions/`? Then functions need deploying.
4. Is the Supabase command-line tool logged in to the **right account** for this
   environment? (See "Switching Supabase accounts".)

## Step 1: Release to staging

**1a. Open and check the pull request.** Pull request from your feature branch
into `dev`. Wait for every check to turn green.

**1b. Verify the staging database release (when there are new migrations).**
Use the successful Deploy Supabase run for the current commit when automation is configured. If using the manual fallback, log in to the staging Supabase account first, then:

```bash
npx supabase link --project-ref <staging-ref>
```

```bash
npx supabase db push --dry-run
```

The dry run lists exactly which migrations will be applied. If they look right:

```bash
npx supabase db push
```

If it fails with `uuid_generate_v4` or asks for a password, run it with the
staging database password (see "Pushing with the database password").

**1c. Deploy server functions (only if `supabase/functions/` changed).**

```bash
npx supabase functions deploy --project-ref <staging-ref>
```

**1d. Merge the pull request into `dev`.** Wait for successful CI and the configured deployment runs. Confirm the deployed commit and schema before exposing the staging apps. With missing secrets, the workflows skip deployment.

## Step 2: Test on staging

Open the staging platform and the staging shop. Sign in and try exactly what
changed, plus a quick sale and a sign-in code. Fix anything here, never in
production.

## Step 3: Release to production

**3a. Switch the Supabase tool to the production (client) account.**

**3b. Update the production database (only if there are new migrations).**

```bash
npx supabase link --project-ref <production-ref>
```

```bash
npx supabase db push --dry-run
```

```bash
npx supabase db push
```

**3c. Deploy server functions (only if they changed).**

```bash
npx supabase functions deploy --project-ref <production-ref>
```

**3d. Release the code.** On GitHub, open a pull request from **`dev`** into
**`main`**. Wait for green checks, then merge. Production rebuilds by itself.

**3e. Check production.** Open `platform.<domain>` and `<domain>`, sign in, and
try the change. Check both Vercel projects show the new deployment as
**Ready**.

## Switching Supabase accounts

The Supabase command-line tool is logged in to **one account at a time**.
Staging and production live in different accounts.

```bash
npx supabase login
```

Press Enter, approve in the browser **while signed in to the right account**,
and paste the verification code into the terminal if asked. Then confirm you
see the right project before doing anything else:

```bash
npx supabase projects list
```

Never run a `supabase` command while logged in to an account that holds other
clients' projects.

## Pushing with the database password

When `db push` needs the database password, enter it without it appearing in
your command history:

```powershell
$env:SUPABASE_DB_PASSWORD = Read-Host "Database password" -AsSecureString | ForEach-Object { [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($_)) }
```

Paste the password when it says `Database password:` and press Enter. Then
run `npx supabase db push`. Close the terminal tab afterwards so the password
is gone.

If you forget a database password, reset it in Supabase → **Project Settings →
Database → Reset database password**, and save the new one.

## Changing settings (environment variables)

These only change when an address or project changes, not on normal releases.

- **POS (Vercel POS project → Settings → Environment Variables → Production):**
  `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`.
- **Shop (Vercel → Settings → Environment Variables):**
  `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`,
  `NEXT_PUBLIC_SITE_URL`, `NEXT_TELEMETRY_DISABLED=1`.

Only the public **anon** key ever goes here, never a service-role or secret
key. After changing a variable, rerun the Deploy shop or Deploy POS
workflow for the current commit (GitHub Actions → the run → **Re-run jobs**), because the values
are built into the app.

## Shop deploys from GitHub

A GitHub account can be the login of only one Vercel account, and Vercel
blocks Git deploys whose commit author isn't in its team. So the shop is
deployed by `.github/workflows/deploy-shop.yml` with a Vercel token instead,
and nobody's GitHub login is needed in the client's Vercel account.

Secrets, per GitHub environment (repository → **Settings → Environments →
`production` or `staging` → Environment secrets**):

| Secret | Where to get it |
| --- | --- |
| `VERCEL_TOKEN` | Vercel → **Account Settings → Tokens → Create**, scoped to that environment's team |
| `VERCEL_ORG_ID` | Vercel → team **Settings → General → Team ID** |
| `VERCEL_PROJECT_ID` | Vercel → shop project **Settings → General → Project ID** |
| `VERCEL_POS_PROJECT_ID` | Vercel → POS project **Settings → General → Project ID** |

Production values come from the client's Vercel account. Staging values come
from the developer's own Vercel account, which also holds other clients'
projects: the token there can reach them too, so give it an expiry date, use
it only for the `staging` secret, limit the `staging` environment to the
`dev` branch (**Deployment branches and tags → Selected branches**), and
take the Project ID from the staging shop project only.

The POS is deployed the same way by `.github/workflows/deploy-pos.yml`.

In each shop project, set **Settings → Build and Deployment → Root
Directory** to `website` (POS projects keep the repository root). In every project use **Settings → Git → Disconnect** so Vercel doesn't
also try to deploy. An environment without these secrets is skipped with a
notice. If a token expires or is revoked, the run fails; create a new one and
replace `VERCEL_TOKEN`.

## If something goes wrong

- **The new version is broken:** roll back the code in seconds.
  - Vercel: **Deployments** → the last good one → **⋯ → Promote to Production**.
- **A migration is wrong:** migrations cannot be undone with a button. Write a
  new migration that fixes it and push it (staging first). This is why
  migrations always go to staging first.
- **A build fails:** open the failed deployment's **Build log** in Vercel or the
  GitHub Actions run. The last red lines say why.
- **Sign-in codes stop arriving:** check Resend → **Logs** for the bounce
  reason, and Supabase → **Authentication → Emails → SMTP Settings** is still
  enabled with the right sender.

## Rules worth keeping

- Staging first, always. Production only after testing on staging.
- Database before code: apply migrations, then merge.
- One environment at a time, with the Supabase tool logged in to its account.
- Keep each environment's database password separate, in a password manager.
- The first account created on an empty database becomes the administrator:
  create yours before sharing any link.
- Don't shop on the website with a staff email; staff accounts can't place
  orders. Use a separate customer email.
