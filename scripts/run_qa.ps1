# MASAPP Unified QA Runner
# Usage: powershell -ExecutionPolicy Bypass -File .\scripts\run_qa.ps1

$ErrorActionPreference = "Continue"
$startTime = Get-Date

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "          MASAPP AUTOMATED QA RUNNER              " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Target: Windows Desktop / SQLite / Flutter" -ForegroundColor Gray
Write-Host "Started at: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
Write-Host ""

$hasFailure = $false

# 1. Static Analysis
Write-Host "[1/2] Running Flutter Analyze..." -ForegroundColor Yellow
$analyzeOutput = & flutter analyze 2>&1
$analyzeExitCode = $LASTEXITCODE

$errorLines = $analyzeOutput | Where-Object { $_ -match "^\s*error\s*-" }
$warningLines = $analyzeOutput | Where-Object { $_ -match "^\s*warning\s*-" }
$infoLines = $analyzeOutput | Where-Object { $_ -match "^\s*info\s*-" }

if ($errorLines.Count -gt 0) {
    Write-Host "  FAILED: Found $($errorLines.Count) error(s) in code analysis!" -ForegroundColor Red
    $errorLines | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
    $hasFailure = $true
} else {
    Write-Host "  PASSED: 0 fatal analysis errors found." -ForegroundColor Green
    if ($warningLines.Count -gt 0) {
        Write-Host "  Note: $($warningLines.Count) warnings, $($infoLines.Count) infos." -ForegroundColor DarkYellow
    }
}

Write-Host ""

# 2. Automated Tests (Unit, Widget, SQLite)
Write-Host "[2/2] Running Automated Test Suite..." -ForegroundColor Yellow
$testOutput = & flutter test --reporter=expanded 2>&1
$testExitCode = $LASTEXITCODE

$testOutput | ForEach-Object {
    if ($_ -match "\[E\]" -or $_ -match "Some tests failed" -or $_ -match "TestFailure") {
        Write-Host "  $_" -ForegroundColor Red
    } elseif ($_ -match "All tests passed!") {
        Write-Host "  $_" -ForegroundColor Green
    } else {
        Write-Host "  $_" -ForegroundColor Gray
    }
}

if ($testExitCode -ne 0) {
    Write-Host "  FAILED: One or more automated tests failed." -ForegroundColor Red
    $hasFailure = $true
} else {
    Write-Host "  PASSED: All automated test suites passed successfully!" -ForegroundColor Green
}

$duration = (Get-Date) - $startTime
Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
if ($hasFailure) {
    Write-Host "  QA RESULT: FAILED (Elapsed: $($duration.Minutes)m $($duration.Seconds)s)" -ForegroundColor Red
    Write-Host "==================================================" -ForegroundColor Cyan
    exit 1
} else {
    Write-Host "  QA RESULT: ALL CHECKS PASSED (Elapsed: $($duration.Minutes)m $($duration.Seconds)s)" -ForegroundColor Green
    Write-Host "==================================================" -ForegroundColor Cyan
    exit 0
}
