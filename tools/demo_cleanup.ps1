<#
.SYNOPSIS
    Rebuilds the website_demo DB, reloads the demo JSON, regenerates demo data.
    Safe to run unattended (Task Scheduler).

.EXAMPLE
    .\tools\demo_cleanup.ps1
    .\tools\demo_cleanup.ps1 -StartDate 2026-08-01
#>

param(
    # Default: today minus 4 months (rolling window).
    [string]$StartDate = (Get-Date).AddMonths(-4).ToString('yyyy-MM-dd')
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$LogDir = Join-Path $RepoRoot 'tools\logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogFile = Join-Path $LogDir ("{0}.load" -f (Get-Date -Format 'yyyy-MM-dd-HHmmss'))
Start-Transcript -Path $LogFile | Out-Null

function Invoke-Step {
    param([string]$Name, [scriptblock]$Block)
    Write-Host ""
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    $global:LASTEXITCODE = 0
    & $Block
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed (exit $LASTEXITCODE)"
    }
}

try {
    # Task Scheduler does not inherit an activated venv.
    . (Join-Path $RepoRoot '.venv\Scripts\Activate.ps1')

    Invoke-Step 'Rebuild website_demo schema' {
        loader db rebuild --profile website_demo --commit
    }
    Invoke-Step 'Load demo JSON' {
        & (Join-Path $RepoRoot 'tools\load_demo.ps1') --commit
    }
    Write-Host "Start date: $StartDate"
    Invoke-Step 'Generate demo data' {
        & (Join-Path $RepoRoot 'tools\gen_demo_data.ps1') --start-date $StartDate
    }

    Write-Host ""
    Write-Host "demo_cleanup: done" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "demo_cleanup FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    Stop-Transcript | Out-Null
}
