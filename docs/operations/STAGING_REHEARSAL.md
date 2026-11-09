# Staging setup and test-bike rehearsal (Milestone 6)

This is the order of work to bring up **staging** for bicycles.pk and prove it end to end with one clearly labelled test bike and one cash-on-delivery (COD) test order. Account, dashboard and secret steps are the owner's; the detailed instructions for each are in [DEPLOY.md](./DEPLOY.md). Nothing here touches production; production is Milestone 7.

It assumes PRs for milestones 3 to 5 (listing, product page, fit and delivery) are merged into `dev`, so staging has the bike delivery migration.

| | Staging |
| --- | --- |
| Git branch | `dev` |
| Supabase project | `bicycles-staging` (Free) |
| Website | `https://staging.bicycles.pk` (Vercel project `bicycles-shop-staging`) |
| POS | `https://platform-staging.bicycles.pk` (Vercel project `bicycles-pos-staging`) |

## 1. Let deploys fire (one-time)

GitHub runs `workflow_run` workflows only from the **default branch**. `main` currently holds only the coming-soon page, so the deploy workflows must be added there first. Merge the PR **"Add deploy workflows to main"**. It adds only `.github/workflows/deploy-supabase.yml`, `deploy-shop.yml` and `deploy-pos.yml`. The coming-soon page and its GitHub Pages setup are unchanged, and nothing deploys until the secrets below exist.

## 2. Owner checklist

Tick these in order. Keep every value in your password manager. Never paste it into the repo, an issue or chat.

1. **Supabase:** create `bicycles-staging` ([DEPLOY.md §2](./DEPLOY.md#2-create-and-configure-supabase)). Set Auth URLs to the staging website and POS, set email OTP to 6 digits, and turn anonymous sign-ins off. Leave `PAYMENT_PROVIDER` unset and set the Edge Function secret `SITE_URL=https://staging.bicycles.pk`.
2. **GitHub:** **Settings → Environments → New environment → `staging`**. Restrict it to the `dev` branch and add these environment secrets:

   | Secret | Value from |
   | --- | --- |
   | `SUPABASE_ACCESS_TOKEN` | Supabase account access token |
   | `SUPABASE_PROJECT_REF` | `bicycles-staging` project reference |
   | `SUPABASE_DB_PASSWORD` | `bicycles-staging` database password |
   | `VERCEL_TOKEN` | Vercel account token |
   | `VERCEL_ORG_ID` | Vercel team/account ID |
   | `VERCEL_PROJECT_ID` | `bicycles-shop-staging` project ID |
   | `VERCEL_POS_PROJECT_ID` | `bicycles-pos-staging` project ID |

3. **Vercel shop:** create `bicycles-shop-staging` with Root Directory `website`, Node 22, and *Include source files outside of the Root Directory* turned on. Under Settings → Git, disconnect Git. Add these Production variables:
   - `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` (the staging anon key only)
   - `NEXT_PUBLIC_SITE_URL=https://staging.bicycles.pk`
   - `SITE_ACCESS_KEY` set to a private passphrase, marked Sensitive. This keeps staging closed to the public; the whole site asks for the key first.
4. **Vercel POS:** create `bicycles-pos-staging` with the repository root as Root Directory and Node 22, and disconnect Git. Add the Production variables `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` (staging).
5. **Domains:** add `staging.bicycles.pk` to the shop project and `platform-staging.bicycles.pk` to the POS project. Add the CNAME records Vercel shows ([DEPLOY.md §7](./DEPLOY.md#7-dns-records-and-https)). The apex `bicycles.pk` stays on the coming-soon page.
6. **First deploy:** in GitHub, go to **Actions → CI** and re-run the latest `dev` run, or merge any PR into `dev`. When CI passes, *Deploy Supabase*, *Deploy shop* and *Deploy POS* run for `staging`. Check each job's summary says it deployed rather than skipped.
7. **First login, before sharing any link:** open the staging POS and create the administrator account ([DEPLOY.md §8](./DEPLOY.md#8-first-login--immediately-before-sharing-links)).

## 3. Store settings

In the staging POS, go to **Settings → Online orders** (administrator only):

- Turn **Allow cash on delivery** on and leave card and wallet off.
- **Delivery fee:** e.g. 300.
- **Bulky item charge per bike:** e.g. 1500.
- **Assembly per bike:** e.g. 2000. If you leave it blank, assembly is not offered.

## 4. Publish the test bike

The test bike must be impossible to mistake for real stock. In **Inventory → New style**:

| Field | Value |
| --- | --- |
| Name | `NOT FOR SALE – Staging Test Bike` |
| Category | `Mountain Bikes` |
| Brand | `TEST` |
| Description | `Staging test item. Not a real product. Do not order.` |
| Bulky item (bike delivery) | on (the default for bike categories) |
| Specifications | Frame `Aluminium (test)`, Wheel size `27.5"`, Gears `21-speed`, Brakes `Mechanical disc` |
| Variants | sizes S and M, colour Black, price 1000 |
| Stock | 2 of each variant |

Upload one plain photo (anything you own), then publish it to the website from the style's **Website** panel.

On `https://staging.bicycles.pk`, check each of these:

- [ ] `/bicycles` shows the bike in the Mountain Bikes row, and `/search?section=bicycles` lists it.
- [ ] The product page shows the grey gallery, the "Aluminium (test) · 27.5" · 21-speed" line, a black swatch and S/M size buttons. The delivery box mentions the bulky charge.
- [ ] **What's my size?** with height 172 cm says size M, and **Select M** picks it.
- [ ] `/fit-guide` gives the same result.

## 5. COD test order

1. On the staging website, sign in with a customer email code. Use a mailbox you own, not the administrator email.
2. Add the test bike (size M) to the bag and open checkout:
   - [ ] **Store pickup:** delivery is 0, with the note that pickup bikes are assembled free.
   - [ ] **Courier delivery:** delivery = 300 + 1500 = 1800, and the totals show "includes bulky item delivery 1,500".
   - [ ] Tick **Deliver assembled**: delivery = 3800, with "includes assembly 2,000". Total = 1000 + tax + 3800.
3. Use a test address with line 1 `TEST ORDER – do not ship` and place the order with **Cash on delivery**.
4. In the POS online orders queue, check that:
   - [ ] the order shows *Assembly requested*
   - [ ] the packing slip says *Assemble before delivery*
   - [ ] the stock reservation is visible
5. Confirm the order, then **cancel** it with the reason "Staging test". Stock returns to 2.
6. In the customer's account, the order shows as cancelled and still shows the assembly note.

Read-only check in the staging Supabase **SQL Editor**:

```sql
select order_no, status, fulfilment, assembly, subtotal, tax, delivery_fee, total,
       subtotal + tax + delivery_fee = total as totals_add_up
from public.online_orders order by created_at desc limit 5;
select name, bulky, specs from public.product_styles where name like 'NOT FOR SALE%';
select bulky_delivery_fee, assembly_fee, delivery_fee, cod_enabled, online_card_enabled
from public.app_settings;
```

Expect `assembly = true`, `delivery_fee = 3800`, `totals_add_up = true`, `bulky = true`, card `false` and COD `true`.

## 6. Automated check

After the bike is published, run the read-only deploy check from your computer. Pass the staging anon key in the `SUPABASE_ANON_KEY` environment variable only:

```sh
node scripts/deploy/check.mjs --website https://staging.bicycles.pk --pos https://platform-staging.bicycles.pk --supabase <staging-supabase-url>
```

With `SITE_ACCESS_KEY` set, the website checks need the access key first. If they stop at the key page, clear the variable for the check, re-deploy, then set it back.

## 7. Afterwards

- Keep the test bike unpublished, but keep the record, so later rehearsals can reuse it. Never import it into production.
- Record the date, the commit SHA staging was deployed from, and the results privately.
- Production setup, real inventory and the switch from the coming-soon page are Milestone 7.
