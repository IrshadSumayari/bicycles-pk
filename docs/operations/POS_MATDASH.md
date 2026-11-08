# POS MatDash redesign handover

Branch: `feat/pos-matdash`, based on develop `bc10e30` after PR #53. Changes are committed locally by presentation area. No push or PR.

## Scope and presentation

The POS uses a trimmed MatDash token system, self-hosted Manrope, Radix/shadcn primitives, shared cards/tables/fields/status badges and modal surfaces. Existing view switching remains; no router was added. The desktop sidebar is 270 px, with an 80 px till rail and a mobile navigation Sheet. The header retains connection status, touch/traditional switching, cart count and the existing sign-out confirmation, and adds profile, notification and theme controls.

Theme preferences use `pos-theme-v1` per device: Light, Dark or System, six presets and Full/Mini sidebar. System is the default appearance; BLUE_THEME is the default preset. Reads/writes tolerate unavailable storage. An inline head script applies appearance before paint, and System follows live OS changes. Print rules were moved intact before adding light/monochrome token overrides.

All screens are restyled through semantic tokens and shared components. Existing service calls, data context logic, handlers and test expectations are retained. The new dashboard shapes existing report data only, refreshes every 60 seconds while visible, and keeps the reports screen's all-permitted-branches scope. Non-till screens and charts are lazy loaded.

## Approved data limitations and decisions

The owner approved showing the available data with a note. The tailoring report exposes totals, not a status distribution; the dashboard shows its existing KPIs. Top-products rows contain neither kind nor image fields, so the dashboard shows All products without inventing garment/fabric filters or thumbnails. Both panels explain this limitation. No service or database API was extended.

Payment mix uses positive tender inflows; it does not turn refunds into positive donut slices. Monetary values and tooltips retain the configured currency and two decimals. Staff-chart axes show the currency separately to keep mobile labels legible.

## Checks

| Command/check                 | Result                                                                        |
| ----------------------------- | ----------------------------------------------------------------------------- |
| npm test                      | 23 files, 175 tests passed                                                    |
| npx tsc -b                    | Passed                                                                        |
| npm run lint                  | 0 errors; 10 warnings (8 existing, 2 template variant-export warnings)        |
| npm run build                 | Passed; large lazy chart chunk warning remains                                |
| npm run test:e2e              | 2 passed; existing expectations unchanged                                     |
| npm run db:reset              | Passed; no database files changed                                             |
| npm run test:db, twice        | 31 files, 1,008 tests passed each run                                         |
| npm run web:build             | Passed; website files unchanged                                               |
| required colour-class rg scan | No matches (exit 1)                                                           |
| protected-scope diff          | No changes to services.ts, existing data/auth contexts, supabase/ or website/ |

The required scan is `rg -n "(blue|indigo|gray|slate)-[0-9]{2,3}" src/components src/App.tsx`.

## Bundles and visual verification

Baseline largest JavaScript chunk: **1,096.20 kB** (281.96 kB gzip). Final largest: **953.69 kB**, the separately loaded ApexCharts chunk. Final main entry: **472.90 kB**. A production-manifest traversal confirms no ApexCharts file in the entry's static import graph. A fresh cashier browser session also requests no ApexCharts module when opening the till.

93 screenshots are present in the working tree only, listed in [the visual index](../screenshots/pos-matdash/README.md) and [machine-readable list](../screenshots/pos-matdash/screenshots.json). They cover all screens at both viewport sizes and appearances, all six dashboard presets, the theme Sheet, mini till sidebar, the inventory editor and eight dark-mode print captures. Long screens use full-page screenshots; key controls also have exact-viewport captures.

Browser checks found no runtime errors across the all-screen pass. Additional checks passed for System appearance changes, unavailable theme storage, actual chart recolouring, inventory action-menu editing and till expansion with a saved Mini preference. Receipt, barcode label, packing and tailoring print components were rendered using disposable local fixtures and checked for black-on-white output. Physical printers were not tested.

The largest copied UI primitive is dropdown-menu.tsx at 7,550 bytes. No copied source exceeds 50 KB. No template demo images, avatars, flags, animations, documentation or README were copied. The forbidden runtime template integrations were excluded. Recharts was removed because there are no remaining imports. All new dependency versions were selected from registry publication records at or before 2026-10-07 and pinned exactly.

## Dependency publication evidence

| Package                       | Exact version | Published  |
| ----------------------------- | ------------- | ---------- |
| clsx                          | 2.1.1         | 2024-04-23 |
| tailwind-merge                | 3.7.0         | 2026-09-12 |
| class-variance-authority      | 0.7.1         | 2024-11-26 |
| @fontsource-variable/manrope  | 5.3.0         | 2026-07-19 |
| apexcharts                    | 7.8.0         | 2026-10-02 |
| react-apexcharts              | 2.1.1         | 2026-06-19 |
| @radix-ui/react-slot          | 1.4.0         | 2026-10-05 |
| @radix-ui/react-dialog        | 1.2.0         | 2026-10-05 |
| @radix-ui/react-dropdown-menu | 2.1.25        | 2026-10-05 |
| @radix-ui/react-tooltip       | 1.3.0         | 2026-10-05 |
| @radix-ui/react-tabs          | 1.1.22        | 2026-10-05 |
| @radix-ui/react-label         | 2.1.16        | 2026-10-05 |
| @radix-ui/react-separator     | 1.1.16        | 2026-10-05 |
| @radix-ui/react-avatar        | 1.2.7         | 2026-10-05 |
| tw-animate-css                | 1.4.0         | 2025-09-24 |

## Local artifacts and cleanup

Screenshots, fixture scripts, credentials and build artifacts are not committed. Fixture passwords were generated in memory. Local fixture users/products/sales are disposable; the final database verification resets them. Dev servers and the local Supabase stack are stopped before handover. Unrelated pre-existing plan documents and local files are preserved.
