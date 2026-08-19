param(
    [switch]$SkipFlutterBuild,
    [switch]$DryRun,
    [string]$Configuration = 'Release',
    [switch]$Sign,
    [string]$CertPath = $env:MASAPP_CERT_PATH,
    [string]$CertPassword = $env:MASAPP_CERT_PASSWORD,
    [string]$SignToolPath = $env:SIGNTOOL_PATH,
    [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
$InstallerScriptPath = Join-Path $ProjectRoot 'masapp_installer.iss'
$BuildDir = Join-Path $ProjectRoot "build\windows\x64\runner\$Configuration"
$OutputDir = Join-Path $ProjectRoot 'Output'
$AppExePath = Join-Path $BuildDir 'masapp.exe'

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
        'C:\Program Files\Inno Setup 6\ISCC.exe',
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -Path $candidate)) {
            return $candidate
        }
    }

    throw 'ISCC.exe not found. Install Inno Setup 6 or set ISCC_PATH.'
}

function Find-SignTool {
    param([string]$PreferredPath)

    $candidates = @()
    if ($PreferredPath) {
        $candidates += $PreferredPath
    }

    $candidates += @(
        'C:\Program Files (x86)\Windows Kits\10\App Certification Kit\signtool.exe',
        'C:\Program Files (x86)\Windows Kits\10\bin\x64\signtool.exe',
        'C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe',
        'C:\Program Files (x86)\Windows Kits\10\bin\10.0.22000.0\x64\signtool.exe'
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -Path $candidate)) {
            return $candidate
        }
    }

    throw 'signtool.exe not found. Install Windows SDK or set SIGNTOOL_PATH.'
}

function Invoke-CodeSigning {
    param(
        [string]$FilePath,
        [string]$ResolvedSignToolPath,
        [string]$ResolvedCertPath,
        [string]$ResolvedCertPassword,
        [string]$ResolvedTimestampUrl
    )

    if (-not (Test-Path -Path $FilePath)) {
        throw "Cannot sign missing file: $FilePath"
    }

    $args = @(
        'sign',
        '/fd', 'SHA256',
        '/td', 'SHA256',
        '/tr', $ResolvedTimestampUrl,
        '/f', $ResolvedCertPath
    )

    if ($ResolvedCertPassword) {
        $args += @('/p', $ResolvedCertPassword)
    }

    $args += $FilePath

    Write-Host "Signing: $FilePath"
    & $ResolvedSignToolPath @args
    if ($LASTEXITCODE -ne 0) {
        throw "Code signing failed for $FilePath"
    }
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

if (-not (Test-Path -Path $AppExePath)) {
    if ($DryRun) {
        Write-Warning "App executable not found yet: $AppExePath"
    }
    else {
        throw "App executable not found: $AppExePath"
    }
}

if ($DryRun) {
    Write-Host "Expected build dir: $BuildDir"
    Write-Host "Expected output dir: $OutputDir"
    if ($Sign) {
        Write-Host "Expected signing cert: $CertPath"
    }
    Write-Host 'Dry run complete. No installer was built.'
    exit 0
}

$resolvedSignTool = $null
if ($Sign) {
    if (-not $CertPath) {
        throw 'Signing requested but MASAPP_CERT_PATH / -CertPath is not set.'
    }
    if (-not (Test-Path -Path $CertPath)) {
        throw "Certificate file not found: $CertPath"
    }
    $resolvedSignTool = Find-SignTool -PreferredPath $SignToolPath
    Invoke-CodeSigning `
        -FilePath $AppExePath `
        -ResolvedSignToolPath $resolvedSignTool `
        -ResolvedCertPath $CertPath `
        -ResolvedCertPassword $CertPassword `
        -ResolvedTimestampUrl $TimestampUrl
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

$installerOutputPath = Join-Path $OutputDir "MASAPP_Setup_v$AppVersion.exe"
if ($Sign) {
    Invoke-CodeSigning `
        -FilePath $installerOutputPath `
        -ResolvedSignToolPath $resolvedSignTool `
        -ResolvedCertPath $CertPath `
        -ResolvedCertPassword $CertPassword `
        -ResolvedTimestampUrl $TimestampUrl
}

Write-Host "Installer completed in $OutputDir"
