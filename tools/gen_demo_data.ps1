<#
.SYNOPSIS
    Wrapper script to generate demo data with a specific date range.

.DESCRIPTION
    Passes the start and end dates directly to generate_demo_data.py.
    This script uses the $args array instead of param() so you can pass
    double-dash arguments (--start-date).

    If --end-date is not provided, it defaults to the current date.

.EXAMPLE
    .\tools\gen_demo_data.ps1 --start-date "2026-07-01"
    .\tools\gen_demo_data.ps1 --start-date "2026-07-01" --end-date "2026-10-30"
#>

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$PythonScript = Join-Path $ScriptDir 'generate_demo_data.py'

if (-not (Test-Path $PythonScript)) {
    Write-Host "Error: generate_demo_data.py not found at $PythonScript" -ForegroundColor Red
    exit 1
}

# Default to today for end-date
$StartDate = $null
$EndDate = (Get-Date -Format "yyyy-MM-dd")

# Parse the $args array manually
for ($i = 0; $i -lt $args.Length; $i++) {
    switch ($args[$i]) {
        "--start-date" {
            if ($i + 1 -lt $args.Length) {
                $StartDate = $args[$i + 1]
                $i++ # skip the value in the next loop iteration
            }
        }
        "--end-date" {
            if ($i + 1 -lt $args.Length) {
                $EndDate = $args[$i + 1]
                $i++
            }
        }
    }
}

if (-not $StartDate) {
    Write-Host "Error: --start-date is required." -ForegroundColor Red
    Write-Host "Usage: .\tools\gen_demo_data.ps1 --start-date YYYY-MM-DD [--end-date YYYY-MM-DD]" -ForegroundColor Yellow
    exit 1
}

Write-Host "Generating demo data from $StartDate to $EndDate..." -ForegroundColor Cyan

Push-Location $ProjectRoot
try {
    # Pass the arguments to Python
    & python $PythonScript --start-date $StartDate --end-date $EndDate
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Demo data generation failed." -ForegroundColor Red
        exit $LASTEXITCODE
    }
} finally {
    Pop-Location
}