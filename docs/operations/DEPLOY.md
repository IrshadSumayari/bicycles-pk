# Deployment: owner runbook

This runbook prepares two separate environments. The owner performs all dashboard/account work and keeps credentials in a password manager or the named dashboard secret fields. No account has been created, linked or deployed by this branch.

Once both environments exist, use [RELEASE_GUIDE.md](./RELEASE_GUIDE.md) for every release. For the first staging setup and the test-bike rehearsal, follow [STAGING_REHEARSAL.md](./STAGING_REHEARSAL.md).

| Purpose | Staging | Production |
| --- | --- | --- |
| Git branch | dev | main |
| Website | https://staging.<domain> | https://<domain> |
| POS | https://platform-staging.<domain> | https://platform.<domain> |
| Supabase project | bicycles-staging (Free) | bicycles-production (Pro) |

Replace `<domain>` with the domain you buy. All other angle-bracket names are placeholders to copy privately from the relevant dashboard. Never paste passwords, project references or tokens into repository files, issues, screenshots or chat.

## 1. Buy the domain

1. Use your own registrar account and buy the shop's domain. Record the registrar, renewal date and account recovery details privately. Enable renewal and account MFA.
2. Keep control of DNS in your own account. Both apps are hosted on Vercel, so the simplest setup is Vercel DNS: at the registrar (for `.pk`, PKNIC or its reseller) set the nameservers to the pair Vercel shows for the domain. The registrar or reseller DNS panel also works if it supports the records in step 7. Copy any existing mail records before changing nameservers. `.pk` nameserver changes can take up to 48 hours.
3. Decide the four hostnames in the table above before configuring Auth.

## 2. Create and configure Supabase

1. In your own Supabase organization, click **New project**. Create `bicycles-staging` on Free and `bicycles-production` on Pro. Choose a nearby available region such as Mumbai or Singapore. Use different strong database passwords and save each in your password manager.
2. In each project, open **Project Settings → API / Connect**. Privately identify the project URL, project reference and **legacy public anon JWT key**. The current functions use JWT verification; use this public key in the apps, never service-role/secret keys. The project reference goes only into the corresponding GitHub environment secret.
3. Under **Authentication → URL Configuration**, set **Site URL** to that environment's website URL. Add that website's `/account` and root URL and that environment's POS root URL to **Redirect URLs**. Add an exact callback/recovery URL only when the app actually introduces one. Current website sign-in enters an email code on `/account`; there is no invented `/auth/callback` route. Do not use production localhost URLs or wildcard previews. Save.
4. Under **Authentication → Sign In / Providers → Email**, enable email sign-up and email confirmation. Set email OTP length **6** and expiry **600 seconds**. Turn **anonymous sign-ins off**. Review Auth rate limits: start with a 60-second resend interval, conservative hourly email/IP and verification limits supported by your SMTP quota, then record/test the final numbers privately. Do not disable rate limits to resolve a mail problem.
5. Under **Authentication → Email Templates**, paste `website/emails/otp.html` into **Magic Link / OTP** and **Confirm signup**, retaining `{{ .Token }}`. Save and send a staging test after SMTP is ready. Keep other security templates functional. [Supabase email templates](https://supabase.com/docs/guides/auth/auth-email-templates).
6. Under **Authentication → Email / SMTP Settings**, configure custom SMTP using the values from step 4 below. Return here after domain verification; do not expose customer sign-up using the default test mail service.
7. Under **Edge Functions → Secrets**, set `SITE_URL` to this environment's website URL. Leave `PAYMENT_PROVIDER` **unset** at launch (remove an old `mock` value). Do not configure mock/provider secrets on hosted projects. The runtime rejects `mock` outside localhost even if it is accidentally selected. Supabase supplies its internal function keys; do not copy them into app settings.
8. Keep the apps private/unshared until the immediate administrator bootstrap in step 8. Do not let a test website account become the first Auth account on an empty project.

`supabase/config.toml` describes local development, not proof of hosted Auth, SMTP or secrets. Hosted settings above must be saved separately in **both** projects.

## 3. Configure GitHub environments and release gating

1. Open this repository **Settings → Environments → New environment**. Create `staging` and `production` with exactly those spellings.
2. On `production`, configure **Required reviewers** to include the owner, restrict deployment branches to `main`, and disable bypass where available. Set the same approval protection for staging if desired; staging branch is `dev`. Confirm your repository visibility/GitHub plan supports required reviewers. If unavailable, stop the hosted release until an enforceable approval arrangement is chosen.
3. In each environment, **Add environment secret** for each name below. Select the correct project's value privately; do not mix environments:

   | Secret name | Copy from |
   | --- | --- |
   | SUPABASE_ACCESS_TOKEN | Supabase account access token authorized for these projects |
   | SUPABASE_PROJECT_REF | That project's reference from its dashboard |
   | SUPABASE_DB_PASSWORD | That project's saved database password |

4. Protect `main` and `dev` with reviewed pull requests and required existing CI jobs. Review deployment workflow edits as privileged code.
5. `.github/workflows/deploy-supabase.yml` responds to successful **CI** runs from **pushes** to these two branches, checks out that exact SHA, rejects an obsolete branch-head result, selects the matching environment and waits for production approval. PR/fork CI never deploys. It runs only `supabase db push` and deploys `payment-create`, `payment-webhook`, `payment-check`, `admin-users`; it never resets or seeds hosted data.
6. Important first setup: GitHub `workflow_run` workflows must exist on the repository's **default branch** before they fire. Have this reviewed workflow installed there first, without approving an unready production release. Then rerun CI for the current dev SHA and confirm the staging deployment job appears. [GitHub workflow events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run).
7. Website/POS Git integrations can start independently of backend CI. Keep deployment protection/maintenance in place until the matching Supabase job and checks pass; do not assume the two providers wait for this workflow. For a schema-dependent release, verify migrations finish before exposing the new app builds.

After the first hosted migration job, verify these in each Supabase **SQL Editor**, as the owner:

```sql
select id, public, file_size_limit from storage.buckets
where id in ('product-images','tailoring-photos');
select policyname, roles, cmd from pg_policies
where schemaname='storage' and tablename='objects';
select extname from pg_extension where extname='pg_cron';
select jobname, schedule, command, active from cron.job
where jobname='expire-online-orders';
select online_card_enabled, cod_enabled from public.app_settings;
```

Expect public `product-images`, private `tailoring-photos`, the product-image staff-write policies and private-photo ownership/counter-staff-read policies. Migration `20261026000000` creates product storage; `20261027000000` creates private photos and policies. Migration `20261028000000` enables pg_cron and schedules `SELECT public.expire_online_orders()` every minute. No seed is needed (`seed.sql` is intentionally empty). Card must be **false**, COD **true** for launch.

If pg_cron creation failed on hosted infrastructure, enable **Database → Extensions → pg_cron**, then rerun the failed migration job; do not mark the migration applied manually. If the migration succeeded but the schedule was removed, restore it as owner:

```sql
select cron.schedule('expire-online-orders', '* * * * *', 'SELECT public.expire_online_orders()');
```

Run this only when the named job is missing, then confirm exactly one active job and inspect **Integrations → Cron** / `cron.job_run_details` for successful executions. Repeat expired-hold testing on staging. Local cron success is not hosted proof. [Supabase Cron](https://supabase.com/docs/guides/cron).

## 4. Configure Resend and email DNS

1. In your own Resend account, click **Domains → Add Domain**. Add the sending domain and choose an available region.
2. Copy the displayed DKIM TXT, SPF TXT and sending/return-path MX records to DNS with their exact names and values. Resend can use a sending subdomain: keep the provided host names rather than guessing `@`. Do not add a second SPF record at an existing host; merge with your mail administrator if needed.
3. Add a DMARC TXT record at `_dmarc` (or the appropriate sending subdomain). Start with a monitoring policy approved by your mail administrator, e.g. `v=DMARC1; p=none`, then tighten after checking alignment; only add reporting addresses you control. Keep existing inbound mail MX records intact.
4. Click **Verify DNS records**. Create a least-privilege sending API key and save it privately. In each Supabase SMTP screen set host `smtp.resend.com`, port **465** with TLS, username `resend`, password = that Resend key. Sender name: Bicycles.pk; sender email: `orders@<domain>` (a verified sender). Save. SMTP supports 587 STARTTLS if your dashboard explicitly uses that mode. [Resend SMTP](https://resend.com/docs/send-with-smtp).
5. Send a staging sign-in code to an external mailbox; confirm delivery, six digits, expiry, sender and branding. Do not paste the key into GitHub app build variables or repository files. The secret belongs in the SMTP dashboard.
6. Local development can use the same Resend SMTP: copy `supabase/.env.example` to `supabase/.env` (gitignored), fill in the key and verified sender, set `SUPABASE_AUTH_EMAIL_SMTP_ENABLED=true`, then `supabase stop && supabase start`. Leave it `false` to keep local mail in Mailpit (CI never has this file). Before a domain is verified, Resend only sends from `onboarding@resend.dev` to the Resend account owner or `delivered@resend.dev`.

## 5. Set up Vercel website

1. **CHECK THE TEAM SWITCHER: it must show YOUR PERSONAL ACCOUNT or the dedicated BICYCLES.PK team. NEVER select, link or deploy under a team that belongs to another client or project. If any existing link/config targets it, stop.** This repository adds no account link and runs no Vercel CLI. If an installer later uses any Vercel CLI command, every command must explicitly pass `--scope <approved-personal-or-bicycles-scope>` and verify that scope first.
2. Use a plan suitable for this commercial shop. Vercel Hobby is restricted to personal/non-commercial use; choose Pro in the approved scope before launching. This does not authorize any account or billing change by the code agent. [Vercel plan restriction](https://vercel.com/docs/plans/hobby).
3. Click **Add New → Project → Import Git Repository**, choose this repo, and recheck the owner/team switcher. Framework **Next.js**, **Root Directory = website**. Enable **Include source files outside of the Root Directory in the Build Step**: types are imported from `../src/lib/database.types.ts`.
4. Node version **22.x**. `website/vercel.json` selects Next.js, npm **10.9.9** clean install and `npm run build`. Do not change the project root to the POS root. [Vercel outside-root setting](https://vercel.com/docs/monorepos/monorepo-faq).
5. Create one Vercel shop project per environment (for example `bicycles-shop` and `bicycles-shop-staging`). `.github/workflows/deploy-shop.yml` deploys each as that project's production with a token (see RELEASE_GUIDE.md, "Shop deploys from GitHub"), so use **Settings → Git → Disconnect**. Under **Environment Variables → Production**, add that environment's `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` and `NEXT_PUBLIC_SITE_URL`. Site URLs are the table above. Leave `PAYMENT_CHECKOUT_ORIGINS` and `NEXT_PUBLIC_ANALYTICS_ID` empty at launch; optionally set `NEXT_TELEMETRY_DISABLED=1`. See `website/.env.example`. These public values are different for each environment; never use service-role keys.
6. Under **Domains**, add `<domain>` to the production shop project and `www.<domain>` with a redirect to the apex (the bare domain). Add `staging.<domain>` to the staging shop project. Confirm each serves its own backend. Keep deployment protection on other URLs and exclude them from production Auth URLs.
7. Wait for HTTPS certificates and a successful matching deployment. CSP/security headers use that build/runtime's `NEXT_PUBLIC_SUPABASE_URL` (HTTP + websocket origins). Nonce-bearing HTML is dynamic: do not add a CDN cache-everything rule. Confirm headers with the check script after DNS.

## 6. Set up the Vercel POS

1. In the same approved Vercel scope, create one POS project per environment (for example `bicycles-pos` and `bicycles-pos-staging`). **Root Directory** is the repository root, Node **22.x**. Use **Settings → Git → Disconnect**: `.github/workflows/deploy-pos.yml` deploys it after CI with a token.
2. Under **Environment Variables → Production**, set that environment's `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`. They are public anon configuration, not backend secrets. Rerun the deploy after changes: Vite embeds them.
3. In the matching GitHub environment add `VERCEL_POS_PROJECT_ID` (project **Settings → General → Project ID**). `VERCEL_TOKEN` and `VERCEL_ORG_ID` are shared with the shop.
4. Under **Domains**, add `platform.<domain>` to the production POS project and `platform-staging.<domain>` to the staging one.
5. `public/_headers` is a template. Vercel ignores `_headers`, so the deploy runs `scripts/deploy/pos-vercel.mjs`, which renders the same CSP and security headers for that environment's Supabase HTTPS and WSS origin into a generated `vercel.json` before `vercel build`. Do not commit a root `vercel.json`. No rewrites are needed for the POS's current root-based navigation. Check a fresh browser load and response headers.

## 7. DNS records and HTTPS

At your DNS host, create records using provider dashboard values; no guessed IPs or project names are included here.

| Type | Host | Value to copy | Proxy / purpose |
| --- | --- | --- | --- |
| A (or provider-supported ALIAS) | @ | exact apex target Vercel displays | website |
| CNAME | www | exact Vercel CNAME target | Vercel redirects to apex |
| CNAME | staging | exact Vercel CNAME target | staging shop |
| CNAME | platform | exact Vercel CNAME target | production POS |
| CNAME | platform-staging | exact Vercel CNAME target | staging POS |
| TXT | provider's verification host | Vercel ownership value if requested | verification |
| TXT | Resend DKIM host | Resend DKIM value | email signing |
| TXT | Resend SPF host | Resend SPF value | email authorization |
| MX | Resend sending/return-path host | Resend MX target + priority | delivery feedback |
| TXT | _dmarc | mail administrator's DMARC policy | email alignment |

With Vercel DNS, Vercel creates the website and POS records itself once the domains are added; add the email records under **Domains → <domain> → DNS Records**. If moving DNS, first copy all existing records, then set the registrar's nameservers to Vercel's exact pair. Do not add an IPv6/AAAA record unless the provider explicitly supplies one. [Vercel domain records](https://vercel.com/docs/domains/working-with-domains/add-a-domain).

Wait until each provider says Valid/Active and each HTTPS URL opens without warnings. Verify `www` ends at the apex and staging apps use staging data. Never bypass a TLS warning.

## 8. FIRST LOGIN — immediately, before sharing links

1. As soon as each environment is ready, open **its POS** privately. On the empty database choose **Create Account**, enter your administrator identity and a strong unique password. Confirm the email if requested, then sign in. The first Auth account becomes the administrator: do this before any customer sign-in or sharing a website link.
2. Confirm the role is admin and the Online orders setting has card/wallet **off**. Create other staff through the admin interface, not public signup. Store recovery information privately. Repeat independently on production.
3. If somebody else became first admin, stop and arrange an authorized recovery; do not continue with that account or reset a hosted database. This runbook never authorizes a hosted reset.

## 9. Staging rehearsal, then release

1. Confirm the matching Supabase migration/function job passed. Inspect buckets/policies/cron as above. In POS enable COD settings as needed and keep card/wallet off. Publish one reviewed stocked test item through Inventory.
2. Sign in with a website customer code: verify sender, new/existing accounts and rejection of an incorrect/expired code. Ensure this customer cannot enter staff screens.
3. Place a COD order, view it in both account orders and the POS queue, confirm, pack, mark ready/shipped with tracking and deliver. Collect cash COD with the cashier's open shift and reconcile the shift. Cancel another unfulfilled COD order and confirm stock availability returns. Check configured COD maximums. No card/wallet radio buttons should appear.
4. Open a shift, make a POS sale, print its receipt, return it and reconcile cash/refund and stock. Submit a tailoring request with a photo; correct staff can view it, another customer cannot. Check light/dark and mobile checkout.
5. Keep the expiry cron active for historical/future online payment holds; test expiration on staging through the tested payment rehearsal when online payments are eventually enabled. Do not temporarily use mock on a hosted domain: the safety guard deliberately rejects it.
6. Installer: `npm ci` at the repository root and `npx playwright install chromium` once, then run the read-only check below. Supply only the public anon key, using the environment variable `SUPABASE_ANON_KEY` privately. Do not commit its value:

   ```sh
   node scripts/deploy/check.mjs --website https://staging.<domain> --pos https://platform-staging.<domain> --supabase <staging-supabase-url>
   ```

   This checks pages, headers/CSP, domain redirect, catalog/quote, anonymous staff denial, JWT requirement, COD-only quote, POS sign-in and browser network leakage. Publish a product first so the quote check has an item. It does not place orders, enter credentials, test SMTP or replace the manual checklist. Local mode additionally takes `--local` and three loopback URLs; it skips www/TLS and validates POS headers in `dist/_headers`, since Vite dev cannot emulate the hosted HTTP headers.
7. Record results, versions, date and owner signoff privately. Only then open/review a release PR **dev → main**. After main CI passes, approve the **production** environment deployment. Wait for migrations/functions and both Git-hosted app builds; run the same check with production URLs/key and redo a small COD rehearsal before opening sales.

## 10. Go-live, backups and rollback

1. Follow [CATALOG_IMPORT.md](./CATALOG_IMPORT.md) on production with the owner reviewing the dry-run problem list first. Automatic photo import is removed. Upload the shop's own photos through POS, enter physical stock and costs and publish a small reviewed collection first. Retained campaign photos still need owner approval/replacement before claiming an entirely original photographic site.
2. Verify all totals, contact details and delivery/return wording. Follow [WEBSITE_LAUNCH.md](./WEBSITE_LAUNCH.md) for legal/launch signoff. Monitor COD failures, fulfillment queue, stock and cash daily.
3. Follow [BACKUP_AND_RESTORE.md](./BACKUP_AND_RESTORE.md): Pro backups plus encrypted off-site exports, both public product images and private tailoring photographs, and regular local restore rehearsal. Record Auth/SMTP/secrets settings privately; SQL backups do not restore all provider configuration.
4. If release behavior is wrong, pause new sales/publication through the POS and retain existing order access. Restore the last compatible successful website deployment in Vercel and POS deployment in Vercel, checking the approved scope before any Vercel action. Both must remain compatible with the current schema. This additive switch can stay in the schema with card disabled.
5. Do not reverse migrations by deleting hosted history or use db reset/seed on hosted data. Fix forward in a reviewed migration. A data restore requires owner authorization, a verified recovery point, downtime and separate image restore/reconciliation as described in the backup runbook.

## 11. Later: Easypaisa

Only after the real adapter task, official guide review and sandbox success/failure/refund checks in [PAYMENTS.md](./PAYMENTS.md): owner configures the provider function secrets (`PAYMENT_PROVIDER=easypaisa`, `SITE_URL`, `EASYPAISA_STORE_ID`, `EASYPAISA_HASH_KEY`, `EASYPAISA_API_USER`, `EASYPAISA_API_PASSWORD`, `EASYPAISA_BASE_URL`) in the correct Supabase environment, then the website's verified server-side `PAYMENT_CHECKOUT_ORIGINS`. Register/verify the webhook and redeploy as needed. Finally the **administrator** turns on **Settings → Online orders → Card and Easypaisa wallet payments**. Managers cannot enable it. The current real adapter remains disabled; turning the setting on alone cannot make it work.
