# Keep a backup you can restore

The owner is responsible for checking backups. Choose a named deputy: **[name / phone]**.
Do the weekly export after closing, while tills are idle and no software update is running.
Keep the matching version of this repository with every backup.

## Before the shop goes live

Use **Supabase Pro before go-live**. Pro provides daily database backups with seven days
of retention. Free projects do not provide downloadable daily backups for the owner;
make your own exports and keep them off the shop computer. Point-in-Time Recovery (PITR)
is a paid add-on for finer recovery points. It replaces daily backups when enabled.
Confirm retention and availability in the project's Database → Backups page.
See [Supabase database backups](https://supabase.com/docs/guides/platform/backups) and
the [production checklist](https://supabase.com/docs/guides/deployment/going-into-prod).

A weekly copy can lose up to a week's entries if it is the only surviving backup.
Keep Pro backups as well. Never delete the live project to fix a till problem.

## Weekly: make your own copy

Ask the installer to install Node, this project's dependencies (`npm ci`), and Docker
Desktop. Start Docker Desktop. Open **Windows PowerShell 5.1** in the project folder.
The installer must first run `npx supabase login` and
`npx supabase link --project-ref YOUR_PROJECT_REF` for the correct live project.

Enter the database password when asked below. It is kept only in this session's
environment, not in a script, command history or backup manifest:

```powershell
$secret = Read-Host 'Supabase database password' -AsSecureString
$env:SUPABASE_DB_PASSWORD = (New-Object System.Net.NetworkCredential('', $secret)).Password
npm.cmd run backup
Remove-Item Env:SUPABASE_DB_PASSWORD
```

Look for **Backup complete**. The script uses `npx supabase db dump` for `schema.sql`
and a second `--data-only` dump for `data.sql`. The latter contains application data,
Auth records and Storage metadata; the CLI leaves out platform migration tables.
A final `manifest.json` records completion and file checksums, without passwords.
The files are under `backups/YYYY-MM-DD/`; another export on the same day uses a
time subfolder so it cannot overwrite the first. A failed folder without a manifest
is incomplete and is never selected for rehearsal.

Copy the **whole folder** to an encrypted external drive or private cloud storage.
Restrict access: it contains customer details and password hashes. Disconnect the
external drive afterwards. Keep at least the last four weekly copies and a monthly
copy. The `backups/` directory is ignored by Git; do not upload dumps to a public repository.

For a development-only test, use `npm.cmd run backup -- -Local`. This needs local
Supabase running (`npm run db:start`) and does not use the linked database or its password.

## Product images need a separate copy

Database backups contain Storage **metadata**, not the actual image files. A database
restore cannot recover deleted images. For each bucket, the installer can download
the files with the [Storage CLI](https://supabase.com/docs/reference/cli/supabase-storage-cp):

```powershell
New-Item -ItemType Directory -Force .\backups\YYYY-MM-DD\images | Out-Null
npx supabase storage cp --linked --recursive ss:///product-images/ .\backups\YYYY-MM-DD\images
```

Replace the date and `product-images` with the actual folder and bucket name. Repeat
for other buckets, check the downloaded files open, and copy them off-site too.
For a small bucket, the owner can also select files and download them from the
Dashboard's Storage page. Keep the bucket names and paths for later re-upload.

## Monthly: rehearse on the local computer

### Website orders

The full public-schema dump also includes online orders, their lines and events,
online payments/payment sessions, stock reservations, customer accounts and online return
requests. Keep these related records in the same recovery
point; restoring an order without its payments or reservations can sell stock twice.
After restoring, compare counts and totals for online orders, payments, refunds,
pending holds and return requests with the original backup records.
Check one account's order history, an unpaid expired hold, a paid order, a cancelled
order and a return request with a photograph. Do not replay payment notifications
or take live money during rehearsal. Reconcile the provider's transaction ledger
before re-enabling payments after a real recovery.

Copy both buckets at the same recovery point. The private photograph copy contains
personal data and must remain encrypted and access-restricted, including in local
rehearsals. Never make its bucket public to simplify a restore.

```powershell
npx supabase storage cp --linked --recursive ss:///return-evidence/ .\backups\YYYY-MM-DD\return-evidence
npx supabase storage cp --linked --recursive ss:///product-images/ .\backups\YYYY-MM-DD\product-images
```

Restore original object paths, MIME types and metadata. Confirm anonymous product
images work, and another customer cannot read a private return photograph;
check a short-lived signed link as the correct customer or authorized staff member.
Record bucket policies, website/POS deployment versions, Auth and SMTP settings,
redirect allow-lists, function secrets and provider configuration in the private
recovery documentation. Never put those secrets in this repository or public dumps.

### Rehearsal procedure

Tell anyone using the development database first: this replaces **local development
data**. It never resets or restores the linked live project. Close local tills before
starting. Use the same repository/migration version as the backup, and compatible
Supabase/Postgres versions. A hosted database with newer Auth/Storage columns may
need a matching local Supabase version; do not ignore restore errors.

```powershell
npm.cmd run restore:rehearsal
# To choose an older copy explicitly:
npm.cmd run restore:rehearsal -- -BackupFolder .\backups\YYYY-MM-DD
```

The script checks the latest completed backup's checksums **before** changing local
data. It requires local Docker, starts local Supabase, and runs an explicit local
reset without seed data. It then restores the dumped public schema and data in one
transaction using `docker cp` and `psql -v ON_ERROR_STOP=1`. File copies preserve
Urdu text on PowerShell 5.1. Existing Auth/Storage application triggers are taken
from this repository's local migrations and restored after loading the data; the
CLI schema dump omits managed schemas. This is why the matching code version matters.

Look for **Restore rehearsal PASSED**. Write down the printed number of sales,
today's payment inflows/outflows/net (Pakistan time), stock-balance rows and customers.
Compare them with the backup day's shop records. A successful SQL import alone does
not prove that the figures are right. Sign in to the local app and check a recent
receipt, stock, customer balance and a staff login. Keep tills idle until checked.
If anything differs, mark the rehearsal failed and call the installer.

| Date | Who | Result / counts / any problem |
| ---- | --- | ----------------------------- |
|      |     |                               |
|      |     |                               |
|      |     |                               |

Do not use this rehearsal script for a live recovery. The owner and installer should
choose the recovery point, stop all tills, restore through the Supabase Dashboard
or its [documented CLI recovery process](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore),
restore image files separately, and reconcile paper sales before reopening. Custom
roles, secrets, Edge Functions, bucket policies and project settings need their own
deployment records; the two SQL files are not a complete project clone.
