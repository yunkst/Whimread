# WebView 集成测试运行脚本
#
# 用法:
#   .\integration_test\run_integration_tests.ps1
#   .\integration_test\run_integration_tests.ps1 -TestName "execute_js"
#   .\integration_test\run_integration_tests.ps1 -TestName "get_page_info"
#   .\integration_test\run_integration_tests.ps1 -Device "windows"
#
# 前提条件:
#   - Windows 10/11，Edge WebView2 Runtime 已安装（Win11 预装）
#   - Flutter SDK 3.x 在 PATH 中
#   - 从 novel_app 目录运行

param(
    [string]$TestName = "execute_js",
    [string]$Device = "windows"
)

$ErrorActionPreference = "Stop"

# 定位项目目录（脚本在 integration_test/ 下）
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Split-Path -Parent $scriptDir

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " WebView Integration Tests" -ForegroundColor Cyan
Write-Host " Platform: $Device" -ForegroundColor Cyan
Write-Host " Test: $TestName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ---- 检查 WebView2 Runtime ----
$webview2Paths = @(
    "C:\Program Files (x86)\Microsoft\EdgeWebView\Application\*\msedgewebview2.exe",
    "C:\Program Files\Microsoft\EdgeWebView\Application\*\msedgewebview2.exe"
)
$found = $false
foreach ($path in $webview2Paths) {
    if (Test-Path $path) {
        $found = $true
        break
    }
}
if (-not $found) {
    # Win11 可能用 Edge 自带的 WebView2
    $edgePath = "C:\Program Files (x86)\Microsoft\Edge\Application\*\msedge.exe"
    if (Test-Path $edgePath) {
        $found = $true
    }
}
if (-not $found) {
    Write-Host "[WARN] 未检测到 Edge WebView2 Runtime" -ForegroundColor Yellow
    Write-Host "       Win11 通常预装，如果测试失败请安装:" -ForegroundColor Yellow
    Write-Host "       https://developer.microsoft.com/microsoft-edge/webview2/" -ForegroundColor Yellow
} else {
    Write-Host "[OK] WebView2 Runtime 已检测" -ForegroundColor Green
}

# ---- 检查 Flutter SDK ----
try {
    $null = flutter --version 2>&1
    Write-Host "[OK] Flutter SDK 已检测" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Flutter SDK 未找到，请确认已在 PATH 中" -ForegroundColor Red
    exit 1
}

# ---- 运行测试 ----
$testFile = "integration_test\webview_extract\${TestName}_test.dart"
$testFullPath = Join-Path $projectDir $testFile

if (-not (Test-Path $testFullPath)) {
    Write-Host "[ERROR] 测试文件不存在: $testFullPath" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "运行: flutter test $testFile -d $Device" -ForegroundColor Yellow
Write-Host ""

Push-Location $projectDir
try {
    flutter test $testFile -d $Device
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host " ALL TESTS PASSED" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Red
        Write-Host " TESTS FAILED (exit code: $LASTEXITCODE)" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        exit $LASTEXITCODE
    }
} finally {
    Pop-Location
}
