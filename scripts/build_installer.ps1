param(
    [switch]$SkipFlutterBuild,
    [switch]$DryRun,
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
$InstallerScriptPath = Join-Path $ProjectRoot 'masapp_installer.iss'
$BuildDir = Join-Path $ProjectRoot "build\windows\x64\runner\$Configuration"
$OutputDir = Join-Path $ProjectRoot 'Output'

function Get-AppVersion {
    param([string]$Path)

    $content = Get-Content -Path $Path -Raw
    $match = [regex]::Match($content, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+\d+)?\s*$')
    if (-not $match.Success) {
        throw "Could not parse app version from $Path"
    }

    return $match.Groups[1].Value
}

function Find-Iscc {
    $candidates = @()

    if ($env:ISCC_PATH) {
        $candidates += $env:ISCC_PATH
    }

    $candidates += @(
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe'
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -Path $candidate)) {
            return $candidate
        }
    }

    throw 'ISCC.exe not found. Install Inno Setup 6 or set ISCC_PATH.'
}

$AppVersion = Get-AppVersion -Path $PubspecPath
Write-Host "MASAPP version: $AppVersion"
Write-Host "Installer script: $InstallerScriptPath"

if (-not $SkipFlutterBuild) {
    Write-Host 'Running flutter build windows --release'
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        throw 'flutter build windows --release failed.'
    }
}

if (-not (Test-Path -Path $BuildDir)) {
    if ($DryRun) {
        Write-Warning "Build output not found yet: $BuildDir"
    }
    else {
        throw "Build output not found: $BuildDir"
    }
}

if ($DryRun) {
    Write-Host "Expected build dir: $BuildDir"
    Write-Host "Expected output dir: $OutputDir"
    Write-Host 'Dry run complete. No installer was built.'
    exit 0
}

$iscc = Find-Iscc
$isccArgs = @(
    "/DMyAppVersion=$AppVersion",
    "/DMyBuildDir=$BuildDir",
    "/DMyOutputDir=$OutputDir",
    $InstallerScriptPath
)

Write-Host "ISCC: $iscc"
Write-Host "Arguments: $($isccArgs -join ' ')"

& $iscc @isccArgs
if ($LASTEXITCODE -ne 0) {
    throw 'Installer build failed.'
}

Write-Host "Installer completed in $OutputDir"
