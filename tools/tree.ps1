<#
.SYNOPSIS
    Writes an ASCII folder tree of the current directory to tree.txt
    in the current folder, encoded as UTF-8 without BOM.

.DESCRIPTION
    Walks the current directory recursively and writes an ASCII tree
    (+--- and \--- box characters, files included) to tree.txt.

    Excluded folders (at any depth):
        .venv, venv, __pycache__, .pytest_cache, .mypy_cache,
        node_modules, build, dist, htmlcov, logs, .git

    Output is UTF-8 without a BOM so the file displays cleanly in VS Code,
    git diffs, and any UTF-8-aware tool.

.EXAMPLE
    .\tree.ps1
    # Writes: .\tree.txt
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$SearchPath = (Get-Location).Path
$TreeFile   = Join-Path -Path $SearchPath -ChildPath 'tree.txt'

# Folders to skip entirely (case-insensitive, matched on the folder name only).
$ExcludedFolders = @(
    '.venv',
    'venv',
    '__pycache__',
    '.pytest_cache',
    '.mypy_cache',
    'node_modules',
    'build',
    'dist',
    'htmlcov',
    'logs',
    '.git'
)

Write-Host "Generating ASCII tree in $SearchPath ..."
Write-Host "Excluded folders: $($ExcludedFolders -join ', ')"

function Test-IsExcluded([string]$name) {
    foreach ($ex in $ExcludedFolders) {
        if ($name -ieq $ex) { return $true }
    }
    return $false
}

# Recursively walk the directory tree, building ASCII lines.
function Get-TreeLines {
    param(
        [string]$Path,
        [string]$Prefix
    )

    $lines = New-Object System.Collections.Generic.List[string]

    # List files and dirs in a stable order.
    $entries = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
        Where-Object {
            # Hide tree.txt itself at the root level.
            -not ($Path -eq $SearchPath -and $_.Name -ieq 'tree.txt')
        } |
        Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name

    $i = 0
    $count = $entries.Count

    foreach ($entry in $entries) {
        $i++
        $isLast = ($i -eq $count)
        $branch = if ($isLast) { '\---' } else { '+---' }
        $nextPrefix = $Prefix + $(if ($isLast) { '    ' } else { '|   ' })

        if ($entry.PSIsContainer) {
            if (Test-IsExcluded $entry.Name) {
                # Skip the entire subtree but still mention it's excluded.
                $lines.Add("$Prefix$branch$($entry.Name) [excluded]")
            } else {
                $lines.Add("$Prefix$branch$($entry.Name)")
                foreach ($l in (Get-TreeLines -Path $entry.FullName -Prefix $nextPrefix)) {
                    $lines.Add($l)
                }
            }
        } else {
            $lines.Add("$Prefix$branch$($entry.Name)")
        }
    }

    return $lines
}

try {
    $header = "Folder: $SearchPath"
    $body   = Get-TreeLines -Path $SearchPath -Prefix ''
    $treeText = (@($header) + $body) -join [Environment]::NewLine

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($TreeFile, $treeText, $utf8NoBom)

    $size = (Get-Item -Path $TreeFile).Length
    Write-Host ("tree.txt created: {0} ({1:N0} bytes)" -f $TreeFile, $size)
}
catch {
    Write-Warning "Failed to generate tree.txt: $($_.Exception.Message)"
    exit 1
}