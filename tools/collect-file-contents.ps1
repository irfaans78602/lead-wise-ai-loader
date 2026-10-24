<#
.SYNOPSIS
    Collects files by extension from the current folder tree and writes one
    output file per routed destination.

.DESCRIPTION
    This variant is tuned for the lead-wise-ai-loader repo layout.

    Output routing (all under $OutputRoot):

      bases\        dotfiles.txt, env-real.txt, env-example.txt, no-extension.txt, md.txt, txt.txt, etc.

      others\loader\py.txt                        src/loader/*.py, entities/*.py, planning/*.py
      others\tests\py.txt                         tests/*.py
      others\ps1\ps1.txt                          *.ps1
      others\schema\master\sql.txt                schema/master/*.sql
      others\schema\rag\sql.txt                   schema/rag/*.sql
      others\schema\leadwise\sql.txt              schema/leadwise/*.sql

      others\data\json.txt                        ALL *.json files (master, rag, leadwise, and any others)
      
      bases\python.txt                            *.py elsewhere
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet(
        'js', 'mjs', 'cjs', 'ts', 'cts', 'mts', 'd.ts',
        'json', 'map',
        'html', 'css',
        'svg', 'png', 'woff2',
        'md', 'txt', 'xml', 'webmanifest',
        'ps1', 'py', 'sql',
        'yml', 'toml',
        'gitignore'
    )]
    [string]$Extension
)

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------
$SearchPath = (Get-Location).Path
$OutputRoot = 'C:\Irfaan\leadwiseai\lead-wise-ai-extensions'
$BasesDir   = Join-Path -Path $OutputRoot -ChildPath 'bases'
$OthersDir  = Join-Path -Path $OutputRoot -ChildPath 'others'

# Extensions routed to the "bases" folder (flat file per extension).
$BasesExtensions = @(
    'md', 'txt', 'xml', 'webmanifest', 'toml'
)

$ExcludedFolders = @(
    'node_modules',
    '__pycache__',
    '.pytest_cache',
    '.mypy_cache',
    '.venv',
    'venv',
    'build',
    'dist',
    'htmlcov',
    'logs',
    '.git'
)

$ExcludedExtensions = @('log')

$AllowedExtensions = @(
    'js', 'mjs', 'cjs', 'ts', 'cts', 'mts', 'd.ts',
    'json', 'map',
    'html', 'css',
    'svg', 'png', 'woff2',
    'md', 'txt', 'xml', 'webmanifest',
    'ps1', 'py', 'sql',
    'yml', 'toml',
    'gitignore'
)

$NoExtensionAllowList = @()

# Real .env files (never shared outside the team) vs. committed templates.
$RealEnvNames = @(
    '.env', '.env.master', '.env.rag', '.env.leadwise', '.env.loader'
)
$EnvExamplePattern = '.env.*.example'

# ------------------------------------------------------------------
# Shared helpers
# ------------------------------------------------------------------

function Test-IsExcludedFolder {
    param([string]$Path)
    $segments = $Path -split '[\\/]'
    foreach ($segment in $segments) {
        foreach ($folder in $ExcludedFolders) {
            if ($segment -ieq $folder) { return $true }
        }
    }
    return $false
}

function Test-IsDotFile {
    param([System.IO.FileInfo]$File)
    return $File.Name.StartsWith('.')
}

function Get-FileExtension {
    param([System.IO.FileInfo]$File)
    $name = $File.Name
    if ($name.StartsWith('.')) {
        $rest = $name.Substring(1)
        if ($rest.Length -eq 0) { return '__noext__' }
        if ($rest.IndexOf('.') -ge 0) {
            return $File.Extension.TrimStart('.').ToLower()
        }
        return $rest.ToLower()
    }
    if ($name.IndexOf('.') -lt 0) { return '__noext__' }
    return $File.Extension.TrimStart('.').ToLower()
}

function Test-IsAllowedNoExtensionFile {
    param([System.IO.FileInfo]$File)
    foreach ($name in $NoExtensionAllowList) {
        if ($File.Name -ieq $name) { return $true }
    }
    return $false
}

function Get-RelativePath {
    param(
        [string]$FullPath,
        [string]$RootPath
    )
    $root = $RootPath.TrimEnd('\','/')
    $rel  = $FullPath.Substring($root.Length).TrimStart('\','/')
    return ($rel -replace '\\','/')
}

function Read-FileContent {
    param([System.IO.FileInfo]$File)
    try {
        return [System.IO.File]::ReadAllText($File.FullName, [System.Text.Encoding]::UTF8)
    }
    catch {
        Write-Warning "    Failed to read: $($File.FullName) -- $($_.Exception.Message)"
        return "[ERROR reading file: $($_.Exception.Message)]"
    }
}

# ------------------------------------------------------------------
# Routing
# ------------------------------------------------------------------

function Get-Destination {
    param(
        [System.IO.FileInfo]$File,
        [string]$RootPath
    )

    $ext = Get-FileExtension -File $File
    $rel = Get-RelativePath -FullPath $File.FullName -RootPath $RootPath
    $relLower = $rel.ToLower()
    $name = $File.Name
    $nameLower = $name.ToLower()

    # --- Real .env files (contain credentials) -> bases\env-real.txt ----------
    foreach ($envName in $RealEnvNames) {
        if ($nameLower -eq $envName.ToLower()) {
            return @{ DestDir = $BasesDir; BaseName = 'env-real' }
        }
    }

    # --- .env.*.example templates (safe to share) -> bases\env-example.txt ---
    if ($nameLower -match '^\.env(\.[a-z0-9_]+)?\.example$') {
        return @{ DestDir = $BasesDir; BaseName = 'env-example' }
    }

    # --- Other dotfiles -> bases\dotfiles.txt --------------------------------
    if (Test-IsDotFile -File $File) {
        return @{ DestDir = $BasesDir; BaseName = 'dotfiles' }
    }

    # --- Bases (flat file per extension) -------------------------------------
    if ($ext -eq '__noext__' -or $BasesExtensions -contains $ext) {
        return @{
            DestDir  = $BasesDir
            BaseName = if ($ext -eq '__noext__') { 'no-extension' } else { $ext -replace '\.','-' }
        }
    }

    # --- PS1 ---------------------------------------------------------------
    if ($ext -eq 'ps1') {
        return @{
            DestDir  = Join-Path -Path $OthersDir -ChildPath 'ps1'
            BaseName = 'ps1'
        }
    }

    # --- SQL: routed per schema profile --------------------------------------
    if ($ext -eq 'sql') {
        if ($relLower -match '(^|/)schema/(master|rag|leadwise)/') {
            $profile = $Matches[1]
            return @{
                DestDir  = Join-Path (Join-Path $OthersDir 'schema') $profile
                BaseName = 'sql'
            }
        }
        return @{
            DestDir  = Join-Path $OthersDir 'schema'
            BaseName = 'sql'
        }
    }

    # --- PY: routed by tree location ----------------------------------------
    if ($ext -eq 'py') {
        if ($relLower -match '(^|/)src/loader/[^/]+\.py$') {
            return @{ DestDir = (Join-Path $OthersDir 'loader'); BaseName = 'py' }
        }
        if ($relLower -match '(^|/)src/loader/(entities|planning)/[^/]+\.py$') {
            return @{ DestDir = (Join-Path $OthersDir 'loader'); BaseName = 'py' }
        }
        if ($relLower -match '(^|/)tests/') {
            return @{ DestDir = (Join-Path $OthersDir 'tests'); BaseName = 'py' }
        }
        return @{ DestDir = $BasesDir; BaseName = 'python' }
    }

    # --- JSON: routed to a single data folder ---------------------------------
    if ($ext -eq 'json') {
        return @{
            DestDir  = Join-Path $OthersDir 'data'
            BaseName = 'json'
        }
    }

    # --- HTML: loader has none today, but route it if it appears ------------
    if ($ext -eq 'html') {
        return @{
            DestDir  = Join-Path (Join-Path $OthersDir 'common') 'html_json'
            BaseName = 'html'
        }
    }

    # --- Any other allowed extension (yml, map, ts, …) ----------------------
    return @{
        DestDir  = $OthersDir
        BaseName = $ext -replace '\.','-'
    }
}

# ------------------------------------------------------------------
# Writers
# ------------------------------------------------------------------

function Write-FlatGroup {
    param(
        [System.IO.FileInfo[]]$Files,
        [string]$Label,
        [string]$BaseName,
        [string]$DestDir,
        [System.Collections.Generic.List[string]]$Summary
    )

    $fileList = @($Files)
    $outFile  = Join-Path -Path $DestDir -ChildPath "$BaseName.txt"

    if (-not (Test-Path -Path $DestDir)) {
        New-Item -Path $DestDir -ItemType Directory -Force | Out-Null
    }

    Write-Host ("Writing {0,4} file(s) -> {1}" -f $fileList.Count, $outFile)

    if (Test-Path -Path $outFile) { Remove-Item -Path $outFile -Force }

    $sb = [System.Text.StringBuilder]::new()
    foreach ($file in $fileList) {
        [void]$sb.AppendLine($file.FullName)
        $content = Read-FileContent -File $file
        if ($null -ne $content) { [void]$sb.AppendLine($content) }
        [void]$sb.AppendLine()
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($outFile, $sb.ToString(), $utf8NoBom)

    $Summary.Add(("{0,-48} {1,5} file(s)  ->  {2}" -f $Label, $fileList.Count, $outFile))
}

# ------------------------------------------------------------------
# Step 1 - Discover files
# ------------------------------------------------------------------
$SpecificExtension = -not [string]::IsNullOrWhiteSpace($Extension)

foreach ($dir in @($BasesDir, $OthersDir)) {
    if (Test-Path -Path $dir) {
        Write-Host "Deleting previous output folder: $dir"
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

foreach ($dir in @($BasesDir, $OthersDir)) {
    if (-not (Test-Path -Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
        Write-Host "Created output directory: $dir"
    }
}

Write-Host "Search root    : $SearchPath"
Write-Host "Output root    : $OutputRoot"
Write-Host "Excluded dirs  : $($ExcludedFolders -join ', ')"
Write-Host "Excluded exts  : $($ExcludedExtensions -join ', ')"
Write-Host ("-" * 80)

$files = New-Object System.Collections.Generic.List[System.IO.FileInfo]

$dirQueue = New-Object System.Collections.Generic.Queue[string]
$dirQueue.Enqueue($SearchPath)

while ($dirQueue.Count -gt 0) {
    $currentDir = $dirQueue.Dequeue()
    if ($currentDir -like "$OutputRoot*") { continue }

    try {
        Get-ChildItem -Path $currentDir -File -Force -ErrorAction SilentlyContinue |
            Where-Object {
                if ($_.Name -ieq 'tree.txt') { return $false }
                $ext = Get-FileExtension -File $_
                if ($ExcludedExtensions -contains $ext) { return $false }
                if (Test-IsDotFile -File $_) {
                    if ($SpecificExtension) { return ($ext -eq $Extension) }
                    return $true
                }
                if ($SpecificExtension) {
                    return ($ext -eq $Extension)
                }
                if ($ext -eq '__noext__') {
                    return (Test-IsAllowedNoExtensionFile -File $_)
                }
                return ($AllowedExtensions -contains $ext)
            } |
            ForEach-Object { $files.Add($_) }
    }
    catch {
        Write-Warning "Could not read files in: $currentDir -- $($_.Exception.Message)"
    }

    try {
        Get-ChildItem -Path $currentDir -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { -not (Test-IsExcludedFolder -Path $_.FullName) -and $_.FullName -notlike "$OutputRoot*" } |
            ForEach-Object { $dirQueue.Enqueue($_.FullName) }
    }
    catch {
        Write-Warning "Could not read directories in: $currentDir -- $($_.Exception.Message)"
    }
}

Write-Host ("Discovered {0} candidate file(s)." -f $files.Count)
Write-Host ("-" * 80)

# ------------------------------------------------------------------
# Step 2 - Route and write
# ------------------------------------------------------------------
$buckets = @{}

foreach ($f in $files) {
    $dest = Get-Destination -File $f -RootPath $SearchPath
    if ($null -eq $dest) { continue }
    $key = ($dest.DestDir + '|' + $dest.BaseName)
    if (-not $buckets.ContainsKey($key)) {
        $buckets[$key] = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    }
    $buckets[$key].Add($f)
}

$summary = New-Object System.Collections.Generic.List[string]

foreach ($key in ($buckets.Keys | Sort-Object)) {
    $parts    = $key -split '\|', 2
    $destDir  = $parts[0]
    $baseName = $parts[1]
    $relDest  = $destDir.Replace($OutputRoot, '').TrimStart('\')
    $label    = "$relDest\$baseName.txt"
    Write-FlatGroup -Files @($buckets[$key]) -Label $label `
                    -BaseName $baseName -DestDir $destDir -Summary $summary
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
Write-Host ("-" * 80)
Write-Host "Summary:"
$summary | ForEach-Object { Write-Host "  $_" }
Write-Host ("-" * 80)
Write-Host ("Total files collected: {0}" -f $files.Count)
Write-Host ("Output root          : {0}" -f $OutputRoot)