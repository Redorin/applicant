# Creates the "Applicants System" shortcut on the Desktop, pointing at
# Start-HRMDO.ps1. Run once (and again only if this folder moves).

$ErrorActionPreference = 'Stop'
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop 'Applicants System.lnk'
$starter = Join-Path $PSScriptRoot 'Start-HRMDO.ps1'
$appExe  = Join-Path $PSScriptRoot 'app\applicants_app.exe'

$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath = 'powershell.exe'
$lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$starter`""
$lnk.WorkingDirectory = $PSScriptRoot
if (Test-Path $appExe) { $lnk.IconLocation = "$appExe,0" }
$lnk.Description = 'HRMDO Applicants Information System'
$lnk.Save()

Write-Host "Shortcut created: $lnkPath" -ForegroundColor Green
