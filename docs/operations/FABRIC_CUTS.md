# Fabric cuts handover

Branch: `feat/fabric-cuts`, based on `develop` at `60045ed` (PR #54).

Fabric cuts are named choices on the existing metre variant, not separate stock or SKUs. The database validates cut definitions, metre quantities, piece counts and cut labels. Quotes use the server price; creation uses the existing single-roll reservation and packing ledger. Cut descriptions are snapshotted on order lines and flow through existing sale, detail, packing-slip and customer-order rendering.

The POS has cut buttons and a quarter-metre input, the inventory website panel edits cuts, and the storefront preserves its existing LadyVogue/MatDash layout. Bag version 2 stores only variant ID, metre quantity and optional cut label. Different cuts remain separate; repeated matching cuts merge. The bag badge counts lines rather than adding metres to piece counts.

## Checks

| Command | Final output/result |
|---|---|
| `npm run db:reset` | Reset local database successfully |
| `npm run test:db`, twice consecutively | Both: `Files=32, Tests=1045`, `All tests successful`, `Result: PASS` |
| `npm run db:types` | Passed; generated types committed |
| `npm test` | 23 files, 175 tests passed |
| `npx tsc -b` | Passed, no diagnostics |
| `npm run lint` | 0 errors, 10 existing warnings |
| `npm run build` | Passed; existing lazy-chart large-chunk warning remains |
| `npm run test:e2e` | 2 passed, expectations unchanged |
| `npm run web:lint` | Passed, no diagnostics |
| `npm run web:test` | 9 files, 38 tests passed |
| `npm run web:build` | Passed |
| `cd website && npx -y npm@10.9.9 ci --dry-run` | Passed; no synchronization error (105 simulated additions) |
| `npm --prefix scripts/catalog-import test` | 14 tests passed |
| `git diff --check` | Passed |

The new database file adds 37 assertions. No existing database test was changed: the old fractional-quantity refusal in `online_orders.test.sql` is for a garment and remains correct. New tests cover 3.75 m, rejected fractional/bounded quantities, cut label and piece validation, roles, catalog exposure, mixed metre/cut lines, one-roll reservation and packing deductions.

Existing website cart tests now use storage version 2 and continue to reject fractional garment actions. Added cases cover quarter metres, merging, caps, cut identity, and dropping version 1. The importer tests that previously rejected mixed Length choices and varying Style options now assert the approved mappings; additional cases cover parsing, rate derivation, price tolerance, fit conflicts, and duplicate cut labels.

## Full catalog dry run

Source: `D:/LadyVogue/storefront/src/data`, unchanged.

- Source: 1,119 products, 6,061 variants, 185 collections.
- Mappable: **1,116 products**, producing **5,116 POS variants**.
- Includes **337 fabrics / 942 named cuts** and **198 products with varying Style mapped to fit**.
- Remaining: **3 products**, no silent partial import:
  - `wool-blend-estash-suiting-fabric-_01`: invalid handle.
  - `shalwar-kameez-lyla-p-black-plain12_12`: invalid handle.
  - `white-boski-shalwar-kameez-fabric-12-03`: `4.5m Fabric + Box` includes a box surcharge and cannot be a metre-priced cut.

The final dry-run JSON/CSV and detailed check logs are local, ignored artifacts under `backups/catalog-import/` and `backups/fabric-cuts/`.

## Local apply and browser verification

Applied 30 fabrics plus 30 varying-Style products through the existing importer and manager RPCs, authenticated with a disposable local admin. First apply: 60 created, zero problems. Second apply: zero created, 60 web updates, zero problems. Counts stayed **60 styles / 354 variants**. The sample contains 421 source variants; fabric Length alternatives collapse into cuts on one metre variant.

Published two fabrics and two varying-Style products locally. Used a disposable one-pixel image solely to satisfy the publication image requirement; source images were not imported. Added local roll/garment stock through receiving functions. Browser checks passed for all four product pages and all four till searches/selections; an additional bag check confirmed two matching cuts merge and a separate 3.75 m line remains distinct. No browser runtime errors. Inspected desktop bag/till and mobile product screenshots under `backups/fabric-cuts/screenshots/`.

Packing, customer cut descriptions and stock deduction were verified by the database tests. Existing detail and packing slip components already render the snapshotted description and metre unit, so their source did not need changes. Physical printing was not tested.

After verification, stopped both dev servers, removed temporary browser credentials and reset the local database to clear fixtures before the final two database suites. The imported/published sample is therefore not left in the database.

## Decisions

- The source product_type is inaccurate on several products. The explicit Length option identifies fabric; Style/size products remain garments even when their category says Fabric. Category text itself is preserved. This recovers valid products rather than guessing stock units from prices.
- Different lengths with the same cut name remain distinct using labels such as `Suit (3.5 m)` and `Suit (4.5 m)`. Corrected `Wait Coat` to `Waist Coat`; accepted the source punctuation `Half Meter:` as Half Meter. Truly duplicate label/length pairs are still reported.
- A missing Per Meter rate is inferred only when all cuts yield the same price with at most two decimals. The box surcharge product stays excluded.
- The unique online-line key now includes cut label, allowing metre and cut lines for the same variant in one order. Each line continues to reserve from one roll, including all pieces in that line.
- Online metre lines keep the requested 0.5-50 m bound even for a 0.25 m cut: at least two such pieces are required. Cut definitions can still be 0.25 m for POS use.
- Fixed a Windows file-handle conflict in `db:types`: the small Node wrapper buffers CLI output, formats it with the existing Prettier dependency, then writes once. No dependency versions changed.

No push or PR. Unrelated local documentation and screenshot work was preserved and excluded from these commits.
