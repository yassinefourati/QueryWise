<#
Runs every test against every supported engine in Docker (compose.test.yaml), including the running backend
and the standalone frontend (nginx) in headless Chromium, then leaves both running: frontend http://localhost:8080, backend :8000.
Generates throwaway passwords for this run only (process environment, never written to disk).
-AcceptLicenses is required: it accepts the SQL Server Developer EULA, the Microsoft ODBC Driver 18 EULA
and the IBM Db2 Community Edition license for these local test containers.
-Down   stops and deletes the whole stack (containers and volumes).
-Clean  deletes the stack right after the tests instead of leaving the app running.
Results: test-results/ (git-ignored).
#>
param([switch]$AcceptLicenses, [switch]$Down, [switch]$Clean)
# Docker writes progress to stderr; Windows PowerShell would treat that as an error, so rely on exit codes instead.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$compose = @('compose', '-f', (Join-Path $root 'compose.test.yaml'), '-p', 'querywise-live')
function Stop-Stack {
    # Interpolation needs values even for "down"; these placeholders are never used to connect.
    $env:QW_ADMIN_PASSWORD = 'unused'; $env:QW_READER_PASSWORD = 'unused'; $env:QW_ACCEPT_LICENSES = 'Y'; $env:QW_DB2_LICENSE = 'accept'
    docker @compose down -v --remove-orphans
}
if ($Down) { Stop-Stack; exit $LASTEXITCODE }
if (-not $AcceptLicenses) { Write-Error 'Pass -AcceptLicenses to accept the SQL Server, ODBC Driver 18 and Db2 Community licenses for the test containers.'; exit 2 }
function New-TestPassword {
    # Letters and digits only (safe in URLs and every engine's SQL), always with upper, lower and digit.
    $chars = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $bytes = New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    'Qw' + (-join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })) + 'a7Z'
}
$env:QW_ADMIN_PASSWORD = New-TestPassword
$env:QW_READER_PASSWORD = New-TestPassword
$env:QW_ACCEPT_LICENSES = 'Y'
$env:QW_DB2_LICENSE = 'accept'
$env:QW_ACCEPT_LICENSES_BUILD = 'yes'
New-Item -ItemType Directory -Force (Join-Path $root 'test-results') | Out-Null
docker @compose build app
if ($LASTEXITCODE) { exit $LASTEXITCODE }
Write-Host 'Starting 8 databases, the backend and the frontend (Db2 first-time setup takes several minutes)...'
docker @compose up -d --wait --wait-timeout 1800 app frontend
if ($LASTEXITCODE) { docker @compose ps; exit $LASTEXITCODE }
docker @compose run --rm runner
$code = $LASTEXITCODE
if ($Clean) { Stop-Stack }
else {
    Write-Host ''
    Write-Host 'Still running with every database: frontend http://localhost:8080 (nginx + API proxy), backend http://localhost:8000 (API docs at /docs).'
    Write-Host 'Stop and delete everything with: .\scripts\run_live_tests.ps1 -Down'
}
Remove-Item Env:QW_ADMIN_PASSWORD, Env:QW_READER_PASSWORD -ErrorAction SilentlyContinue
exit $code
