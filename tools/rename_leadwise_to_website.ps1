<#
.SYNOPSIS
    Renames everything in the loader repo from "leadwise" to "website".

.DESCRIPTION
    This script performs the full rename from the old layout:

        .env.leadwise               ->  .env.website
        data\leadwise\              ->  data\website\
        schema\leadwise\            ->  schema\website\
        src\loader\planning\leadwise.py  ->  src\loader\planning\website.py
        src\loader\entities\leadwise.py  ->  src\loader\entities\website.py

    And updates every file that references the old names:
        - .env.website            (LEADWISE_* -> WEBSITE_*)
        - .env.loader             (LW_DEFAULT_PROFILE)
        - .gitignore
        - src\loader\config.py    (_PROFILE_NAMES, _ENV_FILES)
        - src\loader\planning\__init__.py
        - src\loader\entities\__init__.py
        - src\loader\planning\website.py      (import line)
        - src\loader\diff.py, preflight.py, write.py
        - src\loader\planning\master.py, rag.py
        - tools\load_website.ps1
        - tests\test_plan.py      (if present)

    Also creates the two missing .client-slug files:
        data\master\.client-slug
        data\rag\leadwise-ai\.client-slug

    The script is idempotent: running it twice is safe.

.EXAMPLE
    # From the repo root:
    .\tools\rename_leadwise_to_website.ps1

    # Or preview what it would do:
    .\tools\rename_leadwise_to_website.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Resolve repo root whether run as a file or pasted.
if ($PSScriptRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
} else {
    $RepoRoot = (Get-Location).Path
}
Set-Location $RepoRoot

function Step($msg) {
    if ($DryRun) { Write-Host "[dry-run] $msg" -ForegroundColor DarkGray }
    else         { Write-Host $msg -ForegroundColor Cyan }
}

function Rename-Dir($old, $new) {
    $oldPath = Join-Path $RepoRoot $old
    $newPath = Join-Path $RepoRoot $new
    if (Test-Path -LiteralPath $oldPath) {
        Step "Rename folder: $old -> $new"
        if (-not $DryRun) {
            Rename-Item -Path $oldPath -NewName (Split-Path -Leaf $new)
        }
    } elseif (Test-Path -LiteralPath $newPath) {
        Write-Host "Already renamed: $new" -ForegroundColor DarkYellow
    } else {
        Write-Host "Neither $old nor $new exists, skipping" -ForegroundColor Red
    }
}

function Rename-File($old, $new) {
    $oldPath = Join-Path $RepoRoot $old
    $newPath = Join-Path $RepoRoot $new
    if (Test-Path -LiteralPath $oldPath) {
        Step "Rename file: $old -> $new"
        if (-not $DryRun) {
            Rename-Item -Path $oldPath -NewName (Split-Path -Leaf $new)
        }
    } elseif (Test-Path -LiteralPath $newPath) {
        Write-Host "Already renamed: $new" -ForegroundColor DarkYellow
    } else {
        Write-Host "Neither $old nor $new exists, skipping" -ForegroundColor Red
    }
}

function Replace-In-File($file, $pairs) {
    $path = Join-Path $RepoRoot $file
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "Not found, skipping: $file" -ForegroundColor DarkYellow
        return
    }

    $original = [System.IO.File]::ReadAllText($path)
    $updated = $original
    foreach ($pair in $pairs) {
        $updated = $updated.Replace($pair[0], $pair[1])
    }

    if ($original -eq $updated) {
        Write-Host "No changes needed: $file" -ForegroundColor DarkYellow
        return
    }

    Step "Update contents: $file"
    if (-not $DryRun) {
        # Preserve encoding (write UTF-8 without BOM, matching repo convention).
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($path, $updated, $utf8NoBom)
    }
}

function Ensure-Slug($file, $content) {
    $path = Join-Path $RepoRoot $file
    if (Test-Path -LiteralPath $path) {
        Write-Host "Slug exists: $file" -ForegroundColor DarkYellow
        return
    }
    Step "Create slug: $file = '$content'"
    if (-not $DryRun) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
    }
}

# -------------------------------------------------------------------
# 1. Rename folders and files
# -------------------------------------------------------------------

Rename-Dir  "data\leadwise"                    "data\website"
Rename-Dir  "schema\leadwise"                  "schema\website"
Rename-File ".env.leadwise"                    ".env.website"
Rename-File "src\loader\planning\leadwise.py"  "src\loader\planning\website.py"
Rename-File "src\loader\entities\leadwise.py"  "src\loader\entities\website.py"

# -------------------------------------------------------------------
# 2. Update .env.website (LEADWISE_* -> WEBSITE_*)
# -------------------------------------------------------------------

Replace-In-File ".env.website" @(
    @("LEADWISE_DATABASE_URL",           "WEBSITE_DATABASE_URL"),
    @("LEADWISE_SCHEMA_ROOT=./schema/leadwise",   "WEBSITE_SCHEMA_ROOT=./schema/website"),
    @("LEADWISE_DATA_ROOT=./data/leadwise",       "WEBSITE_DATA_ROOT=./data/website"),
    @("LEADWISE_EXPECTED_SCHEMA_VERSION", "WEBSITE_EXPECTED_SCHEMA_VERSION"),
    @("LEADWISE_SCHEMA_ROOT",            "WEBSITE_SCHEMA_ROOT"),
    @("LEADWISE_DATA_ROOT",              "WEBSITE_DATA_ROOT")
)

# -------------------------------------------------------------------
# 3. Update .env.loader (default profile)
# -------------------------------------------------------------------

Replace-In-File ".env.loader" @(
    @("LW_DEFAULT_PROFILE=leadwise", "LW_DEFAULT_PROFILE=website")
)

# -------------------------------------------------------------------
# 4. Update .gitignore
# -------------------------------------------------------------------

Replace-In-File ".gitignore" @(
    @(".env.leadwise", ".env.website")
)

# -------------------------------------------------------------------
# 5. Update config.py
# -------------------------------------------------------------------

Replace-In-File "src\loader\config.py" @(
    @('_PROFILE_NAMES = ("master", "rag", "leadwise")',
      '_PROFILE_NAMES = ("master", "rag", "website")'),
    @('_ENV_FILES = (".env.loader", ".env.master", ".env.rag", ".env.leadwise")',
      '_ENV_FILES = (".env.loader", ".env.master", ".env.rag", ".env.website")'),
    @("LEADWISE_DATABASE_URL", "WEBSITE_DATABASE_URL")
)

# -------------------------------------------------------------------
# 6. Update planning/__init__.py
# -------------------------------------------------------------------

Replace-In-File "src\loader\planning\__init__.py" @(
    @("from loader.planning import leadwise, master, rag",
      "from loader.planning import website, master, rag"),
    @('"leadwise": leadwise.load_plan',
      '"website": website.load_plan')
)

# -------------------------------------------------------------------
# 7. Update entities/__init__.py
# -------------------------------------------------------------------

Replace-In-File "src\loader\entities\__init__.py" @(
    @("from loader.entities import leadwise, master, rag",
      "from loader.entities import website, master, rag"),
    @('"leadwise": leadwise',
      '"website": website')
)

# -------------------------------------------------------------------
# 8. Update the renamed planning/website.py (its import of entities)
# -------------------------------------------------------------------

Replace-In-File "src\loader\planning\website.py" @(
    @("from loader.entities import leadwise as entities",
      "from loader.entities import website as entities")
)

# -------------------------------------------------------------------
# 9. Update the files that import Plan from planning.leadwise
# -------------------------------------------------------------------

$importsToFix = @(
    "src\loader\diff.py",
    "src\loader\preflight.py",
    "src\loader\write.py",
    "src\loader\planning\master.py",
    "src\loader\planning\rag.py"
)

foreach ($f in $importsToFix) {
    Replace-In-File $f @(
        @("from loader.planning.leadwise import Plan, PlanOp",
          "from loader.planning.website import Plan, PlanOp")
    )
}

# -------------------------------------------------------------------
# 10. Update load_website.ps1 (profile name, sanity-check paths)
# -------------------------------------------------------------------

Replace-In-File "tools\load_website.ps1" @(
    @(".env.leadwise", ".env.website"),
    @("schema\leadwise\", "schema\website\"),
    @("--profile leadwise", "--profile website"),
    @("data/leadwise/", "data/website/")
)

# -------------------------------------------------------------------
# 11. Update tests/test_plan.py (if present)
# -------------------------------------------------------------------

if (Test-Path -LiteralPath (Join-Path $RepoRoot "tests\test_plan.py")) {
    Replace-In-File "tests\test_plan.py" @(
        @("from loader.planning.leadwise import load_plan",
          "from loader.planning.website import load_plan")
    )
}

# -------------------------------------------------------------------
# 12. Create the two missing .client-slug files
# -------------------------------------------------------------------

Ensure-Slug "data\master\.client-slug"        "leadwise-ai"
Ensure-Slug "data\rag\leadwise-ai\.client-slug" "leadwise-ai"

# -------------------------------------------------------------------
# Done
# -------------------------------------------------------------------

Write-Host ""
Write-Host "=== rename_leadwise_to_website.ps1: done ===" -ForegroundColor Green
if ($DryRun) {
    Write-Host "Dry run — no files were changed." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Reinstall the package to refresh egg-info metadata:"
Write-Host "         .\.venv\Scripts\Activate.ps1"
Write-Host "         pip install -e ."
Write-Host "  2. Verify the new layout:"
Write-Host "         ls .env.*"
Write-Host "         ls schema\"
Write-Host "         ls data\"
Write-Host "  3. Run the website load in preview mode:"
Write-Host "         .\tools\load_website.ps1"