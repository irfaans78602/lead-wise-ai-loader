<#
.SYNOPSIS
    Loads the JSON for every client folder under data/rag/.

.DESCRIPTION
    This script uses $args parsing so you can pass double-dash arguments
    like --commit and --client.

.EXAMPLE
    .\tools\load_rag.ps1 --commit
    .\tools\load_rag.ps1 --client leadwise-ai --commit
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
        default {
            Write-Host "Unknown argument: $($args[$i])" -ForegroundColor Red
            exit 1
        }
    }
}

Write-Host ""
Write-Host "=== LeadWise AI: load_rag.ps1 (JSON only) ===" -ForegroundColor Cyan
Write-Host "Repo root: $RepoRoot"

# Find client folders
if ($Client) {
    $clientDirs = Get-ChildItem -Path "data\rag" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $Client }
} else {
    $clientDirs = Get-ChildItem -Path "data\rag" -Directory -ErrorAction SilentlyContinue
}

if (-not $clientDirs) {
    Write-Host "ERROR: no client folders found under data/rag/" -ForegroundColor Red
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
    Write-Host "--- loader load $($inputs -join ', ') --profile rag ---" -ForegroundColor Yellow

    if ($Commit) {
        loader load @inputs --profile rag --commit
    } else {
        Write-Host "(preview only - pass --commit to apply)" -ForegroundColor DarkGray
        loader load @inputs --profile rag
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: load failed for $($d.Name) (exit $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Host ""
Write-Host "=== load_rag.ps1: done ===" -ForegroundColor Green