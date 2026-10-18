# PRISM Release Build Script for Windows (PowerShell)
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $repoRoot

if (-not (Test-Path ".env.json")) {
    Write-Error "Error: .env.json not found in repository root. Copy .env.json.example to .env.json and fill in your keys."
    exit 1
}

if (-not (Test-Path "dist")) {
    New-Item -ItemType Directory -Path "dist" | Out-Null
}

Write-Host "Building release APK..."
flutter build apk --release --dart-define-from-file=.env.json
if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter build failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

$outputApk = "build/app/outputs/flutter-apk/app-release.apk"
$targetApk = "dist/prism-v3.0.0-midterm.apk"

if (-not (Test-Path $outputApk)) {
    Write-Error "Error: Output APK not found at $outputApk"
    exit 1
}

Copy-Item -Path $outputApk -Destination $targetApk -Force
Write-Host "Build complete: $targetApk"

$hash = (Get-FileHash -Path $targetApk -Algorithm SHA256).Hash
Write-Host "SHA-256: $hash"
