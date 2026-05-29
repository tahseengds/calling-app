<#
.SYNOPSIS
  Build the release Flutter app and upload it to Firebase App Distribution.

.DESCRIPTION
  Runs `flutter build apk --release` (production by default) and uploads the
  resulting artifact to Firebase App Distribution via the Firebase CLI.

  Prerequisites:
    - Flutter SDK on PATH
    - Firebase CLI on PATH        ->  npm install -g firebase-tools
    - Authenticated, one of:
        * firebase login           (interactive, persists on your machine)
        * $env:FIREBASE_TOKEN      (CI token)
        * $env:GOOGLE_APPLICATION_CREDENTIALS pointing at a service-account
          JSON with the "Firebase App Distribution Admin" role
    - android/app/google-services.json present (the App ID is read from it,
      unless -AppId / $env:FIREBASE_APP_ID is supplied)

.PARAMETER Groups
  Comma-separated Firebase App Distribution tester groups. Default: "testers".

.PARAMETER Testers
  Comma-separated individual tester emails (optional).

.PARAMETER Notes
  Release notes. Defaults to "v<version>  -  <git sha>  -  <date>".

.PARAMETER Aab
  Build an Android App Bundle (.aab) instead of an APK.

.PARAMETER AppId
  Override the Firebase Android App ID (otherwise auto-detected).

.PARAMETER NoBuild
  Skip the flutter build and upload the most recent existing artifact.

.EXAMPLE
  .\scripts\distribute.ps1
  .\scripts\distribute.ps1 -Groups "qa,internal" -Notes "Fixes call crash"
  .\scripts\distribute.ps1 -NoBuild        # re-upload the last build
#>
param(
  [string]$Groups = "testers",
  [string]$Testers = "",
  [string]$Notes = "",
  [switch]$Aab,
  [string]$AppId = "",
  [switch]$NoBuild
)

$ErrorActionPreference = "Stop"

# Resolve the flutter_app directory (parent of this script's folder) so the
# script works no matter where it's invoked from.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppDir    = Split-Path -Parent $ScriptDir
Set-Location $AppDir

function Require-Cmd($name, $hint) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "'$name' not found on PATH. $hint"
  }
}

Require-Cmd flutter  "Install the Flutter SDK and add it to PATH."
Require-Cmd firebase "Install the Firebase CLI: npm install -g firebase-tools"

$AppPackage = "com.lumin.app"

# ── Resolve the Firebase App ID ───────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($AppId)) {
  if ($env:FIREBASE_APP_ID) {
    $AppId = $env:FIREBASE_APP_ID
  } else {
    $gsPath = Join-Path $AppDir "android/app/google-services.json"
    if (-not (Test-Path $gsPath)) {
      throw "Firebase App ID not provided and '$gsPath' not found. " +
            "Pass -AppId 1:NNN:android:XXXX or set `$env:FIREBASE_APP_ID."
    }
    $gs = Get-Content $gsPath -Raw | ConvertFrom-Json
    $client = $gs.client |
      Where-Object { $_.client_info.android_client_info.package_name -eq $AppPackage } |
      Select-Object -First 1
    if (-not $client) { $client = $gs.client | Select-Object -First 1 }
    $AppId = $client.client_info.mobilesdk_app_id
    if ([string]::IsNullOrWhiteSpace($AppId)) {
      throw "Could not read 'mobilesdk_app_id' from '$gsPath'."
    }
  }
}
Write-Host "Firebase App ID : $AppId" -ForegroundColor Cyan

# ── Build ─────────────────────────────────────────────────────────────────────
if ($Aab) {
  $artifact  = Join-Path $AppDir "build/app/outputs/bundle/release/app-release.aab"
  $buildArgs = @("build", "appbundle", "--release")
} else {
  $artifact  = Join-Path $AppDir "build/app/outputs/flutter-apk/app-release.apk"
  $buildArgs = @("build", "apk", "--release")
}

if (-not $NoBuild) {
  Write-Host "Building release artifact ($($buildArgs -join ' '))..." -ForegroundColor Cyan
  & flutter @buildArgs
  if ($LASTEXITCODE -ne 0) { throw "flutter build failed." }
}

if (-not (Test-Path $artifact)) {
  throw "Artifact not found: $artifact. Run a build first (omit -NoBuild)."
}
Write-Host "Artifact        : $artifact" -ForegroundColor Cyan

# ── Release notes ─────────────────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($Notes)) {
  $verMatch = Select-String -Path (Join-Path $AppDir "pubspec.yaml") `
              -Pattern '^version:\s*(.+)$' | Select-Object -First 1
  $ver  = if ($verMatch) { $verMatch.Matches[0].Groups[1].Value.Trim() } else { "unknown" }
  $sha  = (& git rev-parse --short HEAD 2>$null)
  $date = Get-Date -Format "yyyy-MM-dd HH:mm"
  $Notes = "v$ver  -  $sha  -  $date"
}
Write-Host "Release notes   : $Notes" -ForegroundColor Cyan

# ── Distribute ────────────────────────────────────────────────────────────────
$distArgs = @("appdistribution:distribute", $artifact, "--app", $AppId, "--release-notes", $Notes)
if (-not [string]::IsNullOrWhiteSpace($Groups))  { $distArgs += @("--groups",  $Groups) }
if (-not [string]::IsNullOrWhiteSpace($Testers)) { $distArgs += @("--testers", $Testers) }
if ($env:FIREBASE_TOKEN) { $distArgs += @("--token", $env:FIREBASE_TOKEN) }

Write-Host "Uploading to Firebase App Distribution..." -ForegroundColor Cyan
& firebase @distArgs
if ($LASTEXITCODE -ne 0) { throw "Firebase distribution failed." }

Write-Host "Done - release uploaded to Firebase App Distribution." -ForegroundColor Green
