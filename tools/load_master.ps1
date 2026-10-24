<#
.SYNOPSIS
    Loads the JSON for every client folder under data/master/.

.DESCRIPTION
    Does NOT rebuild the schema. Use `loader db rebuild --profile master`
    separately if you need to reset the schema.

    For each client folder under data/master/, loads every *.json file
    (in filename order) in one transaction.

.PARAMETER Commit
    Apply the transaction. Without this, the loader runs in preview mode.

.PARAMETER Client
    Optional. Load only this client folder. If omitted, loads all clients.

.EXAMPLE
    .\tools\load_master.ps1 -Commit
    .\tools\load_master.ps1 -Client leadwise-ai -Commit
#>

[CmdletBinding()]
param(
    [string]$Client = "",
    [switch]$Commit
)

$ErrorActionPreference = 'Stop'
if ($PSScriptRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
} else {
    $RepoRoot = (Get-Location).Path
}
Set-Location $RepoRoot

Write-Host ""
Write-Host "=== LeadWise AI: load_master.ps1 (JSON only) ===" -ForegroundColor Cyan
Write-Host "Repo root: $RepoRoot"

# Find client folders
if ($Client) {
    $clientDirs = Get-ChildItem -Path "data\master" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $Client }
} else {
    $clientDirs = Get-ChildItem -Path "data\master" -Directory -ErrorAction SilentlyContinue
}

if (-not $clientDirs) {
    Write-Host "ERROR: no client folders found under data/master/" -ForegroundColor Red
    exit 1
}

foreach ($d in $clientDirs) {
    # Collect all *.json files in this folder, sorted by filename
    $jsonFiles = Get-ChildItem -Path $d.FullName -Filter "*.json" -File -ErrorAction SilentlyContinue |
        Sort-Object Name

    if (-not $jsonFiles) {
        Write-Host "Skipping $($d.Name): no JSON files found." -ForegroundColor DarkYellow
        continue
    }

    # Build the list of relative paths (Client/file.json)
    $inputs = @()
    foreach ($f in $jsonFiles) {
        $inputs += (Join-Path $d.Name $f.Name)
    }

    Write-Host ""
    Write-Host "--- loader load $($inputs -join ', ') --profile master ---" -ForegroundColor Yellow

    if ($Commit) {
        loader load @inputs --profile master --commit
    } else {
        Write-Host "(preview only - pass -Commit to apply)" -ForegroundColor DarkGray
        loader load @inputs --profile master
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: load failed for $($d.Name) (exit $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Host ""
Write-Host "=== load_master.ps1: done ===" -ForegroundColor Green