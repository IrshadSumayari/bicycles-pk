# Bicycles.pk: Development Plan

Version 0.2 · 9 November 2026 · Repository: `IrshadSumayari/bicycles-pk` · Branch: `dev`

## 1. Starting point

This repository starts as an independent copy of LadyVogue `origin/dev` at `dde73de`, exported as
tracked files only. No environment files, secrets, database data or deployment settings were copied.

| Part | Location | Stack |
|---|---|---|
| POS (staff app) | `src/` | React 19, Vite 8, Tailwind 4 |
| Storefront | `website/` | Next.js 16 |
| Shared rules | `shared/` | TypeScript used by both apps |
| Database | `supabase/` (52 migrations) | Postgres, Auth, Edge Functions |
| CI/CD | `.github/workflows/` | ci, deploy-pos, deploy-shop, deploy-supabase |

`main` still serves the bicycles.pk "coming soon" page. It stays live until launch.

**Kept from LadyVogue:** POS selling, inventory with variants and barcodes, stock movements, online
orders, COD, returns and exchanges, discount codes, customer accounts, bag and checkout, the
mobile-first storefront and filters.

**Removed or replaced:** the LadyVogue brand, lingerie sizes and filters, jewellery, handbags, the 3D
dressing room and try-on, the lingerie fit guide and the campaign imagery.

## 2. Site sections

| Section | Sub-categories |
|---|---|
| **Bicycles** | City and commuter, hybrid, folding, cruiser, women's |
| **Kids bicycles** | Balance bikes, 12", 16", 20" and 24" bikes, and bikes with training wheels |
| **Sports bicycles** | Road, mountain (MTB), gravel, BMX |
| **E-bikes** *(added)* | City e-bikes, e-MTB, folding e-bikes |
| **Accessories** | Helmets, lights, locks, pumps, bottles and cages, bags and racks, bells, mudguards, phone mounts |
| **Parts and spares** *(added)* | Tyres and tubes, chains, brakes and pads, pedals, saddles, grips, gears |
| **Apparel** *(added, optional)* | Gloves, jerseys, shorts, eyewear |
| **Service** *(added, later)* | Book a repair, tune-up or test ride |

**Bicycle variants:** frame size (XS–XL or cm), wheel size, colour and, optionally, gear count.
**Kids variants:** wheel size, colour and the recommended age/height range.
**Spec fields (the "At a glance" panel):** frame material, wheel size, gears/drivetrain, brakes,
suspension, weight, max rider weight, rider height range, and battery/range for e-bikes.

## 3. Page designs

These sites are layout references only. No assets, copy or logos are reused from them.

### 3a. Landing page: Cowboy reference
- Thin announcement bar at the top (offer or news), which can be dismissed.
- Transparent header over the hero: wordmark on the left, centred section links, account and bag
  icons, and a white pill CTA ("Visit store" or "Book a test ride").
- Full-bleed hero video or photo with a very large two-line headline, a muted subline and a white
  pill button ("Shop bicycles").
- A three-item USP strip along the bottom of the hero: warranty, free assembly, delivery across
  Pakistan.
- Below the hero: category tiles, new arrivals carousel, kids feature, accessories, store/service
  block, footer.

### 3b. Listing: Specialized home reference
- Two large rounded split tiles ("Shop Bicycles" and "Shop Accessories") with an overlaid title and a
  circular ↗ arrow.
- Horizontal product carousels ("New arrivals", "Kids", "Sports") with cards on a light-grey
  (#f2f2f2) background, the bike photographed side-on, name in bold, a spec subtitle (for example
  "Shimano 21-speed") and the price. Previous/next arrows sit at the bottom right.
- Category pages (`/bicycles`, `/kids`, `/sports`, `/accessories`) reuse this card plus the existing
  filter panel and bottom sheet. Filters: price, wheel size, frame size, rider height, brand, brake
  type, gears, colour, in stock.

### 3c. Product detail: Specialized PDP reference
- **Left:** a large gallery on light grey with a zoom button and a thumbnail strip underneath.
- **Right (sticky):** breadcrumb, name, spec subtitle, a model/trim switcher (sibling models as
  cards), price, rating, colour swatches with the colour name, size buttons with "What's my size?" and
  "Size guide", delivery method (Ship to home / Store pickup), full-width black "Add to bag",
  wishlist and share.
- **"Complete your ride":** helmet, lock and light suggestions, each with swatches and a quick-add
  button.
- **Below:** name and tagline, description, an "At a glance" spec list with expandable sections, and
  reviews (later milestone).
- **Mobile:** keep the existing fixed bottom purchase bar.

## 4. Milestones

Each milestone is a feature branch from `dev` with a PR into `dev`, matching the LadyVogue workflow.

| # | Milestone | Main work |
|---|---|---|
| 0 | **Identity and cleanup** | Rename the packages and the Supabase `project_id` (with new ports), replace `LADYVOGUE.md` with `BICYCLES.md`, add a new wordmark and theme, set `noindex`, point the CI workflows at new Vercel/Supabase projects. Remove the lingerie, jewellery, bags and try-on modules from `shared/`, the POS and the website. Tests and builds must pass. |
| 1 | **Bicycle catalogue model** | `shared/bicycles.ts` (sections, sub-categories, spec fields). POS product entry: frame and wheel size shortcuts, spec fields, kids age/height, a CSV import template. Shop navigation built from these sections. |
| 2 | **Landing page** | The hero, USP strip, announcement bar and homepage sections from 3a. Original generated hero imagery until real photos are available. |
| 3 | **Listing** | Split tiles, carousels, new product card, category pages with bicycle filters (3b). |
| 4 | **Product detail** | Gallery, trim switcher, size buttons, delivery method, spec list, "Complete your ride" (3c). |
| 5 | **Fit and delivery** | Size guide by rider height and inseam, a kids age chart, a "What's my size?" helper. Delivery charges for bulky items, an assembly option, store pickup. |
| 6 | **Backend and staging** | New Supabase project, migrations, a staging publishing test (a labelled NOT-FOR-SALE test bike), a COD test order on staging. |
| 7 | **Launch** | Real inventory and photos, policies (warranty, returns), turn indexing on, deploy, switch bicycles.pk from the coming-soon page. Runbook: `docs/operations/LAUNCH.md`. |
| Later | Reviews, service/test-ride booking, EMI/installments, trade-in. | |

## 5. Open questions for the owner

1. Store/brand name and logo: is it "Bicycles.pk" or a separate shop name?
2. Own brand or multi-brand reseller? This decides whether there's a Brand filter and brand pages.
3. Should E-bikes, Parts and Apparel be included at launch?
4. One store or several branches? This affects store pickup and stock locations.
5. Should "Book a test ride" or service booking be in the first release?
