# P10-01 Website launch checklist and hardening

**Branch:** `chore/web-launch`
**Needs:** all earlier website plans merged.
**Files:** `website/app/(legal)/privacy`, `terms`, `returns`, `shipping` pages; consent banner
component; `website/next.config.*` (security headers); `docs/operations/WEBSITE_LAUNCH.md`;
`scripts/load-test/` (k6 or autocannon script); optionally a migration for anything the security
review finds (`supabase/migrations/20261029000000_web_hardening.sql` + tests).

## Steps
1. **Legal pages** with placeholder text clearly marked `[OWNER TO REVIEW]` (privacy: what data,
   why, retention, contact; terms; returns policy reflecting `return_window_days`; shipping:
   cities, fees, times). Footer links.
2. **Consent banner**: analytics load **only after** consent; "Reject" as prominent as "Accept";
   choice stored in a cookie; analytics provider configurable by env (`NEXT_PUBLIC_ANALYTICS_ID`),
   none by default.
3. **Security headers** in Next.js: CSP (self, Supabase URL, image host, payment provider domains),
   `X-Frame-Options: DENY` (or `frame-ancestors 'none'`), `Referrer-Policy: strict-origin-when-cross-origin`,
   `Permissions-Policy`, HSTS in production.
4. **Security review** (write findings in `WEBSITE_LAUNCH.md`, fix what you can):
   - list every function granted to `anon` and `authenticated` (query `pg_proc` +
     `has_function_privilege`) and confirm each is intended; add a pgTAP test file
     `public_surface.test.sql` that fails if a **new** function becomes executable by `anon`
     (allow-list).
   - confirm no table is readable by `anon`; customer accounts cannot call staff functions.
   - Supabase Auth: rate limits, OTP expiry, allowed redirect URLs, site URL, disable sign-ups on
     the POS app domain (staff are created by admins).
   - storage buckets: public only `product-images`.
5. **Load test** catalog pages and `catalog_list` (script + instructions; target: 50 concurrent users,
   p95 < 800 ms for cached pages). Report local results; the real run is done on staging.
6. **Backups**: confirm `docs/operations/BACKUP_AND_RESTORE.md` covers online orders and the
   `tailoring-photos` and `product-images` buckets; update it.
7. **Domains** (D17): document DNS for `brand.pk` (website host) and `pos.brand.pk` (POS host),
   Supabase Auth redirect URLs for both, and CORS.
8. **Go-live runbook** in `WEBSITE_LAUNCH.md`: soft launch with one collection, test orders
   (paid, COD, cancelled, refunded) signed off by the owner, then full catalog; rollback plan
   (unpublish all styles with one SQL statement / admin action).

## Done when
All POS and website checks pass, `public_surface.test.sql` passes, and `WEBSITE_LAUNCH.md` has the
filled checklist with what is done and what the owner must do.
