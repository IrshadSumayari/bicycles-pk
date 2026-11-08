# P5-06 Settings cleanup and garment types editor

**Branch:** `feat/settings-v2`
**Migration:** `supabase/migrations/20261024000400_settings_v2.sql`
**Test file:** `supabase/tests/database/settings.test.sql`
**Files:** `src/components/settings/Settings.tsx` (split into sections),
new `src/components/settings/GarmentTypesEditor.tsx`, `src/lib/services.ts`
(`settingsService`, new `garmentTypesService` or extend `tailoringService`), `src/types/*` as needed.

## Why
`Settings.tsx` still shows options from the original template (theme, interface mode, "auto
backup", invoice prefix/counter) while the settings that matter for this shop
(`tax_rate` as %, `return_window_days`, `max_cashier_discount_percent`) are partly missing in
the UI. Tailoring garment types and their measurement fields (`garment_types`) can only be
changed with SQL. Settings are updated with a direct table `UPDATE` (policy
`settings_update_back_office`), with no validation and no history.

## Database

1. New columns on `app_settings` (all `ADD COLUMN IF NOT EXISTS`, with CHECKs):
   - `min_tailoring_deposit_percent NUMERIC(5,2) NOT NULL DEFAULT 0` (0–100)
   - `receipt_footer TEXT` (e.g. exchange policy text), `receipt_header TEXT`
   - `ntn TEXT`, `strn TEXT` (tax numbers printed on receipts, optional)
   - set `currency` default to `'PKR'` and update the existing row if it is still `'USD'`.
2. **`update_settings(p jsonb)`**: admin only (managers: only `receipt_footer`/`receipt_header`).
   Accepts only known keys, validates ranges, writes, and inserts a row into new append-only
   `settings_history (id, changed_by, changed_at, old jsonb, new jsonb)`. Then **drop the direct
   update policy** `settings_update_back_office` so the function is the only way.
3. **Use the deposit setting** in `create_tailoring_order` / `confirm_tailoring_order`: when the
   setting is > 0 and the order is confirmed, the deposit paid must be at least that % of the total;
   error `'A deposit of at least X% (PKR Y) is required'`. Managers/admins may pass
   `"waive_deposit": true` (record it in the order notes or a column `deposit_waived_by`).
   Copy the latest function bodies (`20261023000000_tailoring_core.sql` and any later override)
   and change only what is needed.
4. **Garment types**: `save_garment_type(p jsonb)` (admin/manager): code (upper snake, immutable
   once used by any `tailoring_items`), name, `fields` (array of `{key,label,required}`; keys
   `^[a-z_]+$`, unique; at least one), `default_charge`, `lead_days`, `fabric_meters`, `active`,
   `sort_order`. Removing a field key that is used in existing `measurement_sets` is allowed
   (history keeps its snapshot) but changing a key's meaning is not detectable — just document it
   in the UI help text.

Tests (~14): admin updates tax and return window; manager can change only receipt text;
cashier refused; invalid values refused (tax 150, negative window); history row written;
direct `UPDATE app_settings` now fails for an admin; deposit rule enforced and waivable by a
manager only; garment type create/update/validation; cashier cannot edit garment types.

## App
1. Settings screen sections: **Store** (name, address, phone, logo, NTN/STRN),
   **Sales & tax** (tax %, currency read-only "PKR", cashier discount limit %, return window days),
   **Receipts** (header, footer, printer on/off), **Tailoring** (minimum deposit %, garment types
   editor), **Cash** (leave a placeholder section heading; P5-04 adds its field).
   Remove options that do nothing (theme, interface mode, auto backup, invoice counter) after
   checking with `grep` that nothing reads them; if something reads them, keep it and say so in
   your report.
2. Save through `settingsService.update(patch)` → `update_settings`. Show validation errors.
3. **Garment types editor**: list, add/edit modal with a field list (add, remove, reorder with
   up/down buttons, required toggle). Preview of the measurement form as the counter will see it
   (reuse the measurement inputs from `OrderIntake.tsx` if they can be extracted cleanly).
4. Receipt (`ReceiptPrint`) prints header/footer and NTN/STRN when set.
5. `OrderIntake` shows "Minimum deposit: PKR X" and blocks confirm locally with the same message
   (the server still decides).

## Done when
All guide checks pass; an admin can add a "Waistcoat" garment type with 6 fields from the UI and
take an order for it.
