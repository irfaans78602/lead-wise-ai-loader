<#
.SYNOPSIS
    Registers the nightly demo_cleanup.ps1 task in Windows Task Scheduler.
    If a task with the same name already exists, it is deleted first, so this
    script can be re-run at any time.

.EXAMPLE
    .\tools\schedule_demo_cleanup.ps1
    .\tools\schedule_demo_cleanup.ps1 -At 03:30
    .\tools\schedule_demo_cleanup.ps1 -Remove     # delete the task only
#>

param(
    [string]$TaskName = 'LeadWise demo cleanup',
    [string]$At       = '02:00',
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Script   = Join-Path $RepoRoot 'tools\demo_cleanup.ps1'

if (-not (Test-Path $Script)) {
    Write-Host "ERROR: $Script not found." -ForegroundColor Red
    exit 1
}

# Delete the existing task, if any.
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Deleted existing task '$TaskName'." -ForegroundColor Yellow
} elseif ($Remove) {
    Write-Host "Task '$TaskName' does not exist. Nothing to remove."
}

if ($Remove) { exit 0 }

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Script`"" `
    -WorkingDirectory $RepoRoot

$trigger = New-ScheduledTaskTrigger -Daily -At $At

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -WakeToRun `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -Action $action `
    -Trigger $trigger -Settings $settings `
    -Description 'Rebuilds website_demo, reloads demo JSON, regenerates demo data.' | Out-Null

$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Host "Registered '$TaskName': daily at $At." -ForegroundColor Green
Write-Host "Next run: $($info.NextRunTime)"
Write-Host "Test now: Start-ScheduledTask -TaskName '$TaskName'"
