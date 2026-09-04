# Builds the release API + app into deploy\api and deploy\app.
# Rerun after any code change, then launch via Start-HRMDO.ps1 (or the
# desktop shortcut Install-Shortcut.ps1 creates).

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

function Find-Tool([string]$name, [string[]]$candidates) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
  throw "$name not found - install it or add it to PATH."
}

$dotnet  = Find-Tool 'dotnet'  @('C:\Program Files\dotnet\dotnet.exe')
$flutter = Find-Tool 'flutter' @('D:\flutter\bin\flutter.bat')

# A running instance locks the output files - stop it first (the launcher
# starts it again on next use).
Get-Process ApplicantsApi, applicants_app -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Write-Host '== Publishing ApplicantsApi (Release) ==' -ForegroundColor Cyan
& $dotnet publish (Join-Path $root 'backend\ApplicantsApi\ApplicantsApi.csproj') `
  -c Release -o (Join-Path $PSScriptRoot 'api') --nologo
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed' }

Write-Host '== Building Flutter app (Windows release) ==' -ForegroundColor Cyan
Push-Location (Join-Path $root 'frontend\applicants_app')
try {
  & $flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
} finally { Pop-Location }

$appOut = Join-Path $root 'frontend\applicants_app\build\windows\x64\runner\Release'
$appDst = Join-Path $PSScriptRoot 'app'
if (-not (Test-Path $appOut)) { throw "Flutter output not found at $appOut" }
New-Item -ItemType Directory -Force $appDst | Out-Null
Copy-Item (Join-Path $appOut '*') $appDst -Recurse -Force

Write-Host "Done. Launch with $PSScriptRoot\Start-HRMDO.ps1" -ForegroundColor Green
