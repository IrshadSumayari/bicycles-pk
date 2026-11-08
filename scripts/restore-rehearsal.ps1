#Requires -Version 5.1
[CmdletBinding()]
param([string]$BackupFolder)

$ErrorActionPreference = 'Stop'

function Get-DumpHash([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '') }
    finally { $stream.Dispose(); $algorithm.Dispose() }
}

$repo = Split-Path -Parent $PSScriptRoot
$backupRoot = [IO.Path]::GetFullPath((Join-Path $repo 'backups'))
$containerDirectory = $null
$localRestoreFile = $null
Push-Location -LiteralPath $repo
try {
    if (-not $BackupFolder) {
        $latest = Get-ChildItem -LiteralPath $backupRoot -Filter 'manifest.json' -File -Recurse |
            Sort-Object { (Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json).createdAt } -Descending |
            Select-Object -First 1
        if (-not $latest) { throw 'No complete backup found. Run npm.cmd run backup -- -Local first.' }
        $BackupFolder = $latest.DirectoryName
    }
    $folder = (Resolve-Path -LiteralPath $BackupFolder).Path
    if (-not $folder.StartsWith($backupRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Copy the backup into this repository backups folder before rehearsing.'
    }
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $folder 'manifest.json') | ConvertFrom-Json
    $schema = Join-Path $folder 'schema.sql'
    $data = Join-Path $folder 'data.sql'
    if ((Get-DumpHash $schema) -ne $manifest.schemaSha256 -or
        (Get-DumpHash $data) -ne $manifest.dataSha256) {
        throw 'The backup files do not match their checksums. Local data has not been changed.'
    }
    $config = Get-Content -Raw -LiteralPath (Join-Path $repo 'supabase\config.toml')
    $projectMatch = [regex]::Match($config, '(?m)^\s*project_id\s*=\s*"([A-Za-z0-9_-]+)"')
    if (-not $projectMatch.Success) { throw 'Cannot identify the local Supabase project.' }
    $container = 'supabase_db_' + $projectMatch.Groups[1].Value
    $dockerHost = $env:DOCKER_HOST
    if (-not $dockerHost) {
        $dockerHost = & docker context inspect --format '{{.Endpoints.docker.Host}}'
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the Docker connection.' }
    }
    if ($dockerHost -notmatch '^(npipe://|unix://|tcp://(127\.0\.0\.1|localhost)(:|/))') {
        throw 'Use a local Docker Desktop connection for the rehearsal.'
    }

    Write-Host ('Rehearsing: ' + $folder)
    Write-Host ('Replacing LOCAL development data only in ' + $container + '. The linked project is never reset.')
    & npx.cmd --no-install supabase start | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not start local Supabase.' }
    & npx.cmd --no-install supabase db reset --local --no-seed
    if ($LASTEXITCODE -ne 0) { throw 'Could not reset local Supabase.' }
    $actualName = & docker inspect --format '{{.Name}}' $container
    if ($LASTEXITCODE -ne 0 -or $actualName.Trim() -ne ('/' + $container)) { throw 'Local database container did not match.' }

    # The CLI schema dump omits managed schemas. Preserve this repository's
    # custom Auth/Storage triggers from the migrations just applied locally.
    $triggerSql = @'
SET search_path = '';
SELECT coalesce(string_agg(pg_get_triggerdef(t.oid) || ';', E'\n' ORDER BY t.oid), '')
FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
JOIN pg_namespace pn ON pn.oid=p.pronamespace
JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE NOT t.tgisinternal AND pn.nspname='public' AND n.nspname IN ('auth','storage');
'@
    $customTriggers = (& docker exec $container psql -X -qAt -U postgres -v ON_ERROR_STOP=1 -c $triggerSql) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Could not preserve the local Auth triggers.' }

    $containerDirectory = '/tmp/clothing-pos-rehearsal-' + [guid]::NewGuid().ToString('N')
    & docker exec $container mkdir -p $containerDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Could not prepare restore files.' }
    & docker cp $schema ($container + ':' + $containerDirectory + '/schema.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Could not copy the schema dump.' }
    & docker cp $data ($container + ':' + $containerDirectory + '/data.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Could not copy the data dump.' }

    $restoreSql = @'
SET client_min_messages = warning;
BEGIN;
DROP SCHEMA public CASCADE;
CREATE SCHEMA public AUTHORIZATION postgres;
\i SCHEMA_FILE
SET session_replication_role = replica;
-- Managed migration and protected Storage tables are not writable by postgres.
-- Leave their local platform state intact; any unsupported dump rows still fail.
DO $$
DECLARE r RECORD;
BEGIN
 FOR r IN SELECT schemaname,tablename FROM pg_tables
  WHERE schemaname IN ('auth','storage','supabase_functions')
    AND tablename NOT IN ('schema_migrations','migrations')
    AND has_table_privilege(format('%I.%I',schemaname,tablename),'TRUNCATE')
 LOOP EXECUTE format('TRUNCATE TABLE %I.%I CASCADE',r.schemaname,r.tablename); END LOOP;
END $$;
\i DATA_FILE
CUSTOM_TRIGGERS
COMMIT;
SELECT count(*) AS sales FROM public.sales;
SELECT coalesce(sum(amount) FILTER (WHERE direction='in'),0) AS today_payments_in,
 coalesce(sum(amount) FILTER (WHERE direction='out'),0) AS today_payments_out,
 coalesce(sum(CASE WHEN direction='in' THEN amount ELSE -amount END),0) AS today_payments_net
FROM public.payments
WHERE created_at >= ((current_timestamp AT TIME ZONE 'Asia/Karachi')::date::timestamp AT TIME ZONE 'Asia/Karachi')
 AND created_at < (((current_timestamp AT TIME ZONE 'Asia/Karachi')::date+1)::timestamp AT TIME ZONE 'Asia/Karachi');
SELECT count(*) AS stock_balance_rows FROM public.stock_balances;
SELECT count(*) AS customers FROM public.customers;
'@
    $restoreSql = $restoreSql.Replace('SCHEMA_FILE', ($containerDirectory + '/schema.sql')).Replace('DATA_FILE', ($containerDirectory + '/data.sql')).Replace('CUSTOM_TRIGGERS', $customTriggers)
    $localRestoreFile = [IO.Path]::GetTempFileName()
    # docker cp preserves UTF-8 bytes, unlike PowerShell 5.1 native stdin piping.
    [IO.File]::WriteAllText($localRestoreFile, $restoreSql, (New-Object Text.UTF8Encoding($false)))
    & docker cp $localRestoreFile ($container + ':' + $containerDirectory + '/restore.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Could not copy the restore instructions.' }
    & docker exec $container psql -X -q -U postgres -v ON_ERROR_STOP=1 -f ($containerDirectory + '/restore.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Restore rehearsal failed. Do not treat this backup as verified.' }
    Write-Host 'Restore rehearsal PASSED. Compare the counts and payment totals with the shop records, and fill in the monthly log.'
} finally {
    if ($localRestoreFile -and (Test-Path -LiteralPath $localRestoreFile)) { Remove-Item -LiteralPath $localRestoreFile }
    if ($containerDirectory -and $containerDirectory -match '^/tmp/clothing-pos-rehearsal-[a-f0-9]{32}$') {
        & docker exec $container rm -f -- ($containerDirectory + '/schema.sql') ($containerDirectory + '/data.sql') ($containerDirectory + '/restore.sql')
        & docker exec $container rmdir -- $containerDirectory
    }
    Pop-Location
}
