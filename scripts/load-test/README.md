# Local and staging load test

Install with `npm ci --prefix scripts/load-test`. Build and start the production
website with local Supabase running, warm the published catalog, then run from the
repository root:

```powershell
node scripts/load-test/run.mjs --website http://127.0.0.1:3000 --api http://127.0.0.1:54321 --anon-key <public-anon-key>
```

This measures the home page, `/search` and `catalog_list`, separately,
with 50 connections and 15 seconds per target. It warms each request first,
records every response duration and calculates the nearest-rank p95. Non-success
HTTP statuses, network errors and p95 >= 800 ms fail the command. Results go to
Git-ignored `backups/load-test/latest.json`. `--seconds` accepts 5–60 seconds.

Only loopback hosts are allowed by default. An explicitly authorized staging run
must include `--allow-staging`; never run against production without a separate
approved load-test window. Use a public key, never a service key. Measure staging
from its target market too; local results cannot establish production capacity.

HTML uses fresh CSP nonces and renders dynamically; the underlying catalog data
has a 60-second cache. This test measures that actual configuration, not a static
HTML cache that would reuse nonces. The isolated autocannon dependency currently
has a moderate transitive uuid advisory; it is not shipped in either application.
The tool uses no uuid v3/v5/v6 buffer APIs implicated by that advisory. Reassess
the dependency before exposing this development tool as a service.
