<#
Builds, pushes and runs Querywise together with the two large sample databases (sample-databases/):
  Telecom & supply chain (PostgreSQL, 40 tables) and Banking & insurance (Oracle Free, 40 tables), data 1999 -> today.

  .\scripts\bigdb.ps1 build                                  # build the 3 images locally
  .\scripts\bigdb.ps1 push -Registry docker.io/<user>        # build, tag and push the 3 images (docker login first)
  .\scripts\bigdb.ps1 up                                     # start app + databases (builds missing images)
  .\scripts\bigdb.ps1 up -Pull -Registry docker.io/<user>    # on another machine: pull the pushed images and start
  .\scripts\bigdb.ps1 status                                 # containers, health and connection details
  .\scripts\bigdb.ps1 down                                   # stop and remove containers, keep the data volumes
  .\scripts\bigdb.ps1 down -Purge                            # also delete the data volumes and this stack's app settings

Images: <Registry>/querywise-app, <Registry>/querywise-telecom-postgres, <Registry>/querywise-bank-oracle (tag -Tag).
The database images hold the generator scripts, not the data: each database generates its data on the first start
(about 7 minutes for PostgreSQL and 20 for Oracle at scale 1; -Scale 0.05 for a quick try) into a named volume.
Credentials: sample-databases/.env.bigdb (git-ignored, never baked into an image). Created with random passwords
when missing; keep it, because existing data volumes only accept the passwords they were created with.
#>
param(
    [Parameter(Position = 0)][ValidateSet('build', 'push', 'up', 'down', 'status')][string]$Action = 'up',
    [string]$Registry = '',
    [string]$Tag = 'latest',
    [double]$Scale = 1,
    [switch]$Pull,
    [switch]$Purge
)
# Docker writes progress to stderr; Windows PowerShell would treat that as an error, so rely on exit codes instead.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root 'sample-databases\.env.bigdb'
$project = 'querywise-bigdb'

function New-BigdbPassword {
    # Letters and digits only (safe in URLs, PostgreSQL and Oracle), starting with a letter as Oracle requires.
    $chars = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $bytes = New-Object byte[] 20; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    'Bq' + (-join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })) + 'a7'
}

function Initialize-EnvFile {
    if (Test-Path $envFile) { return }
    $p = @{ PgOwner = New-BigdbPassword; PgReader = New-BigdbPassword; OraSys = New-BigdbPassword; OraOwner = New-BigdbPassword; OraReader = New-BigdbPassword }
    $text = @"
# Local credentials for the two large sample databases (git-ignored: .env.*). Do not commit.
# Containers: bigdb-postgres, bigdb-oracle (data in Docker volumes bigdb_pg_data, bigdb_ora_data).

# --- Telecom & supply chain: PostgreSQL 16 ---------------------------------------------
# From your machine: localhost:5433   From the Querywise app container: bigdb-postgres:5432
BIGDB_PG_DATABASE=telecom_db
BIGDB_PG_SCHEMA=telecom
BIGDB_PG_OWNER_USER=telecom_owner
BIGDB_PG_OWNER_PASSWORD=$($p.PgOwner)
BIGDB_PG_READER_USER=telecom_reader
BIGDB_PG_READER_PASSWORD=$($p.PgReader)
BIGDB_PG_URL_HOST=postgresql://telecom_reader:$($p.PgReader)@localhost:5433/telecom_db
BIGDB_PG_URL_DOCKER=postgresql://telecom_reader:$($p.PgReader)@bigdb-postgres:5432/telecom_db

# --- Banking & insurance: Oracle Free 23ai ------------------------------------------------
# From your machine: localhost:1522   From the Querywise app container: bigdb-oracle:1521
BIGDB_ORA_SERVICE=FREEPDB1
BIGDB_ORA_SCHEMA=BANK
BIGDB_ORA_OWNER_USER=BANK
BIGDB_ORA_OWNER_PASSWORD=$($p.OraOwner)
BIGDB_ORA_READER_USER=QW_READER
BIGDB_ORA_READER_PASSWORD=$($p.OraReader)
BIGDB_ORA_SYSTEM_PASSWORD=$($p.OraSys)
"@
    # UTF-8 without BOM, LF endings: docker compose reads this file.
    [IO.File]::WriteAllText($envFile, ($text -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
    Write-Host "Created $envFile with new random passwords."
}

function Invoke-Compose {
    $files = @('compose', '-p', $project, '-f', (Join-Path $root 'compose.yaml'), '-f', (Join-Path $root 'compose.bigdb.yaml'))
    $rootEnv = Join-Path $root '.env'
    if (Test-Path $rootEnv) { $files += @('--env-file', $rootEnv) }   # keeps AI provider settings from .env
    $files += @('--env-file', $envFile)
    docker @files @args
    if ($LASTEXITCODE -ne 0) { Write-Error "docker compose $($args -join ' ') failed (exit $LASTEXITCODE)."; exit $LASTEXITCODE }
}

function Remove-ManualContainers {
    # Containers with the same names started by hand (outside this compose project) would block "up".
    # Removing them keeps their data: it lives in the named volumes that compose reuses.
    foreach ($name in 'bigdb-postgres', 'bigdb-oracle') {
        $owner = docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' $name 2>$null
        if ($LASTEXITCODE -eq 0 -and $owner -ne $project) {
            Write-Host "Replacing hand-started container $name (its data volume is kept)."
            docker rm -f $name | Out-Null
        }
    }
}

function Show-Status {
    Invoke-Compose ps
    Write-Host ''
    Write-Host 'Querywise:          http://localhost:8000  (sources "Telecom & supply chain" and "Banking & insurance")'
    Write-Host 'PostgreSQL (host):  localhost:5433  database telecom_db, schema telecom'
    Write-Host 'Oracle (host):      localhost:1522  service FREEPDB1, schema BANK'
    Write-Host "Credentials:        $envFile"
    Write-Host 'First start: follow progress with  docker logs -f bigdb-postgres  /  docker logs -f bigdb-oracle'
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Write-Error 'Docker is not installed or not on PATH.'; exit 1 }
Initialize-EnvFile
$env:BIGDB_IMAGE_PREFIX = if ($Registry) { $Registry.TrimEnd('/') } else { 'querywise' }
$env:BIGDB_TAG = $Tag
$env:BIGDB_SCALE = [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $Scale)

switch ($Action) {
    'build' {
        Invoke-Compose build
        Write-Host "Built $($env:BIGDB_IMAGE_PREFIX)/querywise-app, -telecom-postgres and -bank-oracle with tag $Tag."
    }
    'push' {
        if (-not $Registry) { Write-Error 'Pass -Registry, e.g. -Registry docker.io/<user> or ghcr.io/<user> (run "docker login" first).'; exit 2 }
        Invoke-Compose build
        Invoke-Compose push app bigdb-postgres bigdb-oracle
        Write-Host "Pushed to $($env:BIGDB_IMAGE_PREFIX) with tag $Tag. On another machine: copy this repo (or compose.yaml,"
        Write-Host "compose.bigdb.yaml and scripts/bigdb.ps1), then run: .\scripts\bigdb.ps1 up -Pull -Registry $Registry -Tag $Tag"
    }
    'up' {
        $busy = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
        if ($busy -and -not (docker ps -q --filter "label=com.docker.compose.project=$project" --filter 'publish=8000')) {
            Write-Error 'Port 8000 is already in use (for example by the live test stack: .\scripts\run_live_tests.ps1 -Down). Free it and retry.'; exit 1
        }
        Remove-ManualContainers
        if ($Pull) {
            if (-not $Registry) { Write-Error '-Pull needs -Registry (where the images were pushed).'; exit 2 }
            Invoke-Compose pull app bigdb-postgres bigdb-oracle
            Invoke-Compose up -d --no-build
        } else {
            Invoke-Compose up -d
        }
        Show-Status
    }
    'down' {
        if ($Purge) { Invoke-Compose down -v --remove-orphans; Write-Host 'Removed containers and data volumes.' }
        else { Invoke-Compose down --remove-orphans; Write-Host 'Removed containers; data volumes bigdb_pg_data and bigdb_ora_data kept.' }
    }
    'status' { Show-Status }
}
