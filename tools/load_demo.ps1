<#
.SYNOPSIS
    Loads the JSON for every client folder under a data root into the demo database.

.DESCRIPTION
    For each client folder under the specified data root (default: data/website), 
    loads every *.json file (in filename order) in one transaction.
    
    This script defaults to the "website_demo" profile, allowing you to push
    the shared website data into the demo database.

.PARAMETER Commit
    Apply the transaction. Without this, the loader runs in preview mode.

.PARAMETER Client
    Optional. Load only this client folder. If omitted, loads all clients.

.PARAMETER Profile
    Optional. The loader profile to use. Defaults to "website_demo".

.PARAMETER DataRoot
    Optional. The folder to look for client JSONs. Defaults to "data\website".

.EXAMPLE
    .\tools\load_website_demo.ps1 -Commit
    .\tools\load_website_demo.ps1 -Client leadwise-ai -Commit
#>

[CmdletBinding()]
param(
    [string]$Client = "",
    [string]$Profile = "website_demo",
    [string]$DataRoot = "data\website",
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
Write-Host "=== LeadWise AI: load_website_demo.ps1 (JSON only) ===" -ForegroundColor Cyan
Write-Host "Repo root: $RepoRoot"
Write-Host "Profile:   $Profile"
Write-Host "Data root: $DataRoot"

# Find client folders
if ($Client) {
    $clientDirs = Get-ChildItem -Path $DataRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $Client }
} else {
    $clientDirs = Get-ChildItem -Path $DataRoot -Directory -ErrorAction SilentlyContinue
}

if (-not $clientDirs) {
    Write-Host "ERROR: no client folders found under $DataRoot/" -ForegroundColor Red
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
    # Note: We pass the relative path (e.g., "leadwise-ai/10-client.json") 
    # because the loader prepends the DATA_ROOT from the .env file.
    $inputs = @()
    foreach ($f in $jsonFiles) {
        $inputs += (Join-Path $d.Name $f.Name)
    }

    Write-Host ""
    Write-Host "--- loader load $($inputs -join ', ') --profile $Profile ---" -ForegroundColor Yellow

    if ($Commit) {
        loader load @inputs --profile $Profile --commit
    } else {
        Write-Host "(preview only - pass -Commit to apply)" -ForegroundColor DarkGray
        loader load @inputs --profile $Profile
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: load failed for $($d.Name) (exit $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Host ""
Write-Host "=== load_website_demo.ps1: done ===" -ForegroundColor Green