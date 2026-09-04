# Daily launcher: makes sure the Applicants service (API) is running, then
# opens the app. Safe to run repeatedly - it reuses a healthy API.

$ErrorActionPreference = 'Stop'
$apiDll = Join-Path $PSScriptRoot 'api\ApplicantsApi.dll'
$appExe = Join-Path $PSScriptRoot 'app\applicants_app.exe'
$health = 'http://127.0.0.1:5080/health'

function Test-Api {
  try { Invoke-RestMethod $health -TimeoutSec 2 | Out-Null; return $true }
  catch { return $false }
}

if (-not (Test-Api)) {
  if (-not (Test-Path $apiDll)) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
      "The Applicants service is not built yet.`nRun deploy\build.ps1 first.",
      'Applicants System', 'OK', 'Error') | Out-Null
    exit 1
  }
  # WorkingDirectory matters: appsettings.json (DB + port) lives beside the dll.
  Start-Process 'dotnet' -ArgumentList $apiDll -WorkingDirectory (Split-Path $apiDll) -WindowStyle Hidden

  $deadline = (Get-Date).AddSeconds(30)
  while (-not (Test-Api)) {
    if ((Get-Date) -gt $deadline) {
      Add-Type -AssemblyName System.Windows.Forms
      [System.Windows.Forms.MessageBox]::Show(
        "Could not start the Applicants service.`nCheck that SQL Server is running, then try again.",
        'Applicants System', 'OK', 'Error') | Out-Null
      exit 1
    }
    Start-Sleep -Milliseconds 500
  }
}

# The API deliberately stays running after the app closes - relaunches are
# instant and the daily backup task rides on API startup.
Start-Process $appExe
