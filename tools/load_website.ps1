<#
.SYNOPSIS
    Loads the JSON for every client folder under a data root.

.DESCRIPTION
    This script uses $args parsing so you can pass double-dash arguments
    like --commit, --client, --profile, and --data-root.

.EXAMPLE
    .\tools\load_website.ps1 --commit
    .\tools\load_website.ps1 --profile website_demo --data-root "data/website_demo" --commit
#>

$ErrorActionPreference = 'Stop'

if ($PSScriptRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
} else {
    $RepoRoot = (Get-Location).Path
}
Set-Location $RepoRoot

# Defaults
$Client = ""
$Profile = "website"
$DataRoot = "data\website"
$Commit = $false

# Manual argument parsing for double-dashes
for ($i = 0; $i -lt $args.Length; $i++) {
    switch ($args[$i]) {
        "--commit" {
            $Commit = $true
        }
        "--client" {
            if ($i + 1 -lt $args.Length) {
                $Client = $args[$i + 1]
                $i++
            }
        }
        "--profile" {
            if ($i + 1 -lt $args.Length) {
                $Profile = $args[$i + 1]
                $i++
            }
        }
        "--data-root" {
            if ($i + 1 -lt $args.Length) {
                $DataRoot = $args[$i + 1]
                $i++
            }
        }
        default {
            Write-Host "Unknown argument: $($args[$i])" -ForegroundColor Red
            exit 1
        }
    }
}

# Make the DataRoot path absolute relative to the Repo Root
if (-not [System.IO.Path]::IsPathRooted($DataRoot)) {
    $DataRoot = Join-Path $RepoRoot $DataRoot
}

Write-Host ""
Write-Host "=== LeadWise AI: load_website.ps1 (JSON only) ===" -ForegroundColor Cyan
Write-Host "Repo root: $RepoRoot"
Write-Host "Profile:   $Profile"
Write-Host "Data root: $DataRoot"

if (-not (Test-Path $DataRoot)) {
    Write-Host "ERROR: Data root does not exist: $DataRoot" -ForegroundColor Red
    exit 1
}

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
        Write-Host "(preview only - pass --commit to apply)" -ForegroundColor DarkGray
        loader load @inputs --profile $Profile
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: load failed for $($d.Name) (exit $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Host ""
Write-Host "=== load_website.ps1: done ===" -ForegroundColor Green