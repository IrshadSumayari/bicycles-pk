#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Local)

$ErrorActionPreference = 'Stop'

function Get-DumpHash([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '') }
    finally { $stream.Dispose(); $algorithm.Dispose() }
}

$repo = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $repo
try {
    if (-not $Local -and [string]::IsNullOrWhiteSpace($env:SUPABASE_DB_PASSWORD)) {
        throw 'Set SUPABASE_DB_PASSWORD in this PowerShell session before backing up the linked project.'
    }
    $dateFolder = Join-Path $repo ('backups\' + (Get-Date -Format 'yyyy-MM-dd'))
    $folder = $dateFolder
    if (Test-Path -LiteralPath $folder) {
        $folder = Join-Path $dateFolder ((Get-Date -Format 'HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    }
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $schema = Join-Path $folder 'schema.sql'
    $data = Join-Path $folder 'data.sql'
    $target = '--linked'
    if ($Local) { $target = '--local' }

    & npx.cmd --no-install supabase db dump $target --file $schema
    if ($LASTEXITCODE -ne 0) { throw 'Schema backup failed. This folder is incomplete; do not restore it.' }
    & npx.cmd --no-install supabase db dump $target --data-only --file $data
    if ($LASTEXITCODE -ne 0) { throw 'Data backup failed. This folder is incomplete; do not restore it.' }
    if ((Get-Item -LiteralPath $schema).Length -eq 0 -or (Get-Item -LiteralPath $data).Length -eq 0) {
        throw 'A dump file is empty. This backup is incomplete.'
    }
    # Written last: a failed or interrupted dump never becomes a restore candidate.
    $manifest = [ordered]@{
        createdAt = [DateTime]::UtcNow.ToString('o')
        source = $target.Substring(2)
        schemaSha256 = (Get-DumpHash $schema)
        dataSha256 = (Get-DumpHash $data)
    }
    [IO.File]::WriteAllText((Join-Path $folder 'manifest.json'), ($manifest | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    Write-Host ('Backup complete: ' + $folder)
    Write-Host ('Schema: ' + $schema)
    Write-Host ('Data:   ' + $data)
    Write-Host 'Copy the whole folder to an encrypted external drive or private cloud storage.'
    Write-Host 'Storage files (images) need a separate copy; see docs/operations/BACKUP_AND_RESTORE.md.'
} finally {
    Pop-Location
}
