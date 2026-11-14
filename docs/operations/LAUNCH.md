# Launch runbook: bicycles.pk (Milestone 7)

Launching means:
- production is set up and holds real inventory and photos
- the policies are signed off
- search indexing is turned on
- `bicycles.pk` is switched from the GitHub Pages coming-soon page to the shop

Work through the sections in order. Each one names who does it. Accounts, dashboards, DNS and secrets are always the owner's; values stay in the password manager.

**Before you start:** the staging rehearsal in [STAGING_REHEARSAL.md](./STAGING_REHEARSAL.md) is complete and recorded. Production must not be the first place anything is tried.

| | Production |
| --- | --- |
| Git branch | `main` |
| Supabase project | `bicycles-production` (Pro, for daily backups) |
| Website | `https://bicycles.pk` (`www` redirects to the apex). Vercel project `bicycles-shop` |
| POS | `https://platform.bicycles.pk`. Vercel project `bicycles-pos` |

## 1. Owner decisions

These shape the policies and settings. Answer them first. Nothing below invents terms on your behalf.

| Decision | Where it ends up |
| --- | --- |
| **Warranty:** frame (years), parts and components (months), e-bike motor and battery, what voids it (racing, crashes, unauthorised modification), who honours it (you or the brand distributor), and what proof is needed | New *Warranty* policy page; spec field "Warranty" on each bike |
| **Returns for bikes:** window in days; unridden and boxed only?; who pays return delivery for a bulky item; assembly fee refundable? | *Returns and exchanges* page; POS **Settings → Return window** |
| **Delivery:** cities served, base fee, bulky charge per bike, free-delivery threshold (does it apply to bikes?), typical delivery days | **Settings → Online orders**; *Pickup and delivery* page |
| **Assembly:** offered? fee per bike? what's included (brakes, gears, first service?) | **Settings → Assembly per bike**; *Pickup and delivery* and *FAQ* pages |
| **Pickup:** store address, hours, ID or order number needed | *Store location* and *Pickup and delivery* pages; `website/content/brand.json` |
| **Cash on delivery:** maximum order total for COD (bikes are high value) | **Settings → Maximum COD order total** |
| **Free first service:** offered? after how many weeks or km? | *FAQ*; product descriptions |
| **Contact:** phone, WhatsApp, email, business hours | `brand.json`, footer, *Contact* page |

## 2. Policies and content (owner reviews, developer edits)

All storefront pages live in `website/content/pages/index.json` and are edited through a pull request into `dev`.

- [ ] **Add a Warranty policy page** (`/policies/warranty-policy`) from the decisions above. Link it from the footer and from the product page's *Delivery and returns* section.
- [ ] **Returns and exchanges:** add the bike-specific rules (window, condition, packaging, return delivery for bulky items, whether assembly is refundable).
- [ ] **Pickup and delivery:** cities, delivery times, the bulky charge, assembly, and that pickup bikes are assembled free.
- [ ] **FAQ:** sizing (link `/fit-guide`), assembly, first service, warranty claims, COD.
- [ ] **About, Contact, Store location, Privacy, Terms, Payment methods:** read every page in full and correct names, addresses, numbers and hours. Remove anything you can't stand behind.
- [ ] **Home page:**
  - **`website/content/home.json`:** the hero headline and subline, the announcement bar text and link, and the three USPs. Each USP claim (warranty, free assembly, nationwide delivery) must match the policies.
  - **`website/public/hero/`:** replace the generated hero with your own photo or video, and update the paths in `home.json`.
- [ ] Have someone outside the project read the policies once for clarity. Take legal advice if the terms carry risk.

## 3. Real inventory and photos (owner and staff, in the production POS)

Enter products only after section 5 (production setup) is done, or enter them on staging first to practise.

**Bikes**, in **Inventory → New style**:
- Category from the bike sections (this also ticks *Bulky item* automatically).
- Brand.
- Specifications: frame, wheel size, gears, brakes and suspension at least, plus motor, battery and range for e-bikes, and age and rider height for kids bikes. Fill **Warranty** to match the policy.
- Sizes and colours: frame sizes such as S/M/L, or wheel sizes for kids bikes.
- Price, cost and opening stock.

**Bulk entry:** **Inventory → Import products from a spreadsheet**. Download the template and fill one row per size and colour. Specifications aren't in the spreadsheet; add them per style afterwards.

**Accessories and parts:** the same flow. Leave *Bulky item* off unless the item needs a big box, such as a bike rack or trainer.

**Photos** (they decide how the listing looks):
- Your own photos only, or the brand's photos with written permission.
- Bike side-on, drive side (chain side) facing right, whole bike in frame.
- Plain white or light-grey background, landscape **4:3**, at least 2000 px wide. The site shows bikes on a light-grey panel and doesn't crop them.
- Extra angles: cockpit, drivetrain, brakes, wheel or tyre, plus a detail of any special feature. Tag photos by colour so choosing a colour swaps the gallery.
- Accessories: square or 4:3, same background.

**Publishing:**
- [ ] Publish a small reviewed set first (e.g. 10 bikes across sections and 10 accessories). Check each listing, product page, size buttons and price on the production URL before DNS points to it (section 6).
- [ ] Do a physical stock count of what you published and match it to the POS.

## 4. Code changes for launch (developer: one PR into `dev`)

Search indexing needs no code change. `isProductionSite()` in `website/lib/helpers.ts` turns it on only when `NEXT_PUBLIC_SITE_URL` is `https://bicycles.pk`, so it starts with the first production deploy. Staging, previews and local builds stay `noindex`, and their `robots.txt` disallows everything.

- [ ] **Check the production variable:** `bicycles-shop` has `NEXT_PUBLIC_SITE_URL=https://bicycles.pk` exactly (no `www`, no trailing path).
- [ ] **Update the indexing note:** in `BICYCLES.md`, add the launch date to the search indexing note.
- [ ] **Warranty page and footer link** from section 2.
- [ ] **Release PR `dev → main`:** expect a conflict on the root `index.html`. `main` has the coming-soon page and `dev` has the POS app's `index.html`. Resolve it by keeping **dev's** version, and **delete `CNAME`** in the same PR. The domain moves to Vercel, so GitHub Pages must stop claiming it.

Merge the release PR only during the cutover window in section 6. Merging deploys production (once its secrets exist) and removes the coming-soon page from `main`.

## 5. Production setup (owner)

Follow [DEPLOY.md](./DEPLOY.md) sections 2–8 with the production names above. In brief:

1. **Supabase:** create `bicycles-production` (Pro). Set Auth URLs to `https://bicycles.pk` and `https://platform.bicycles.pk`, set up SMTP through Resend with sender **Bicycles.pk** `orders@bicycles.pk`, and turn anonymous sign-ins off. Set the function secret `SITE_URL=https://bicycles.pk`; leave `PAYMENT_PROVIDER` unset.
2. **GitHub environment `production`:** restricted to `main`, with **required reviewer = you**, and the same seven secrets as staging, using the production values.
3. **Vercel:** `bicycles-shop` (Root Directory `website`) and `bicycles-pos` (repository root), on a **Pro** plan (Hobby is non-commercial only), with Git disconnected.
   - Shop production variables: the production `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`, plus `NEXT_PUBLIC_SITE_URL=https://bicycles.pk`.
   - **Do not set `SITE_ACCESS_KEY`** on production.
   - POS production variables: `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
4. **First admin:** create the administrator in the production Supabase project with `app_private.bootstrap_admin` ([DEPLOY.md §8](./DEPLOY.md#8-first-login--immediately-before-sharing-links)), sign in to the POS and set up the authenticator app, then add the staff accounts. Confirm TOTP is enabled and the password minimum is 12 in the production Auth settings.
5. **Store settings** from section 1: online orders, COD limit, delivery, bulky, assembly and the return window. Card and wallet stay **off**.
6. **Backups:** confirm Pro daily backups and schedule the off-site export ([BACKUP_AND_RESTORE.md](./BACKUP_AND_RESTORE.md)).

## 6. Cutover: coming-soon page to shop (owner, with developer on hand)

Pick a quiet time and allow 2 hours plus DNS propagation. The coming-soon page stays live until the new site is proven.

1. **The day before:** at your DNS host, lower the TTL of the `bicycles.pk` apex and `www` records to 300 seconds.
2. **Merge the release PR** (section 4). Approve the `production` deployment in GitHub Actions and wait for *Deploy Supabase*, *Deploy shop* and *Deploy POS* to finish.
3. **Test on Vercel's own URL** (`bicycles-shop-<hash>.vercel.app`) before any DNS change:
   - home
   - every section page
   - search
   - three product pages, including a kids bike
   - the size finder
   - the bag
   - checkout quote with pickup, courier, and courier with assembly
4. **Turn off GitHub Pages:** go to repository **Settings → Pages**, remove the custom domain `bicycles.pk`, then unpublish the site.
5. **Add the domains in Vercel:** `bicycles.pk` and `www.bicycles.pk` (redirecting to the apex) on `bicycles-shop`, and `platform.bicycles.pk` on `bicycles-pos`.
6. **Change DNS:** replace the GitHub Pages apex records (`185.199.108–111.153`) with the exact apex record Vercel shows. Point `www` and `platform` to the CNAME targets Vercel shows. Keep the email records (Resend, DMARC) untouched.
7. **Wait** until Vercel shows the domains *Valid* and HTTPS works. Then run the read-only check with the production anon key in `SUPABASE_ANON_KEY`:

   ```sh
   node scripts/deploy/check.mjs --website https://bicycles.pk --pos https://platform.bicycles.pk --supabase <production-supabase-url>
   ```

8. **One real COD order:** place it with your own account, for an accessory, to your own address with pickup. Follow it through confirm → ready → delivered → collect cash in a shift.
9. **Search:** in Google Search Console, verify `bicycles.pk` (DNS TXT record) and submit `https://bicycles.pk/sitemap.xml`. Check that a product page shows `index, follow` in its robots meta.
10. Raise the DNS TTL back to its normal value after 48 hours.

**Rollback:** if the shop misbehaves after the DNS switch, pause publishing in the POS, restore the previous good Vercel deployment, or point the apex back to the GitHub Pages records and re-add the custom domain in Pages. Never reset or re-seed the production database; fix forward with a reviewed migration.

## 7. First week (owner and staff)

- **Daily:** the online order queue, COD collections and shift reconciliation, plus stock against the shelf for published bikes.
- **Quality:** check delivery quotes against real courier costs for bulky items, and adjust the bulky charge if needed. Read the first customer questions; recurring ones become FAQ entries.
- **Admin:** confirm the first daily backup exists and do the first off-site export. Record the launch date, the release commit and signoff privately.

## Related documents

[BACKUP_AND_RESTORE.md](./BACKUP_AND_RESTORE.md) and [OFFLINE_PROCEDURE.md](./OFFLINE_PROCEDURE.md) cover backups and working without the internet.
