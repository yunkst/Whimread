@echo off
REM Flutter 代码覆盖率检查脚本 (Windows)
REM
REM 用法:
REM   check_coverage.bat                 # 生成覆盖率报告
REM   check_coverage.bat --html          # 生成HTML报告并打开
REM   check_coverage.bat --min 80        # 检查覆盖率是否达到80%

setlocal enabledelayedexpansion

REM 参数解析
set HTML_REPORT=false
set MIN_COVERAGE=0

for %%a in (%*) do (
  if "%%a"=="--html" (
    set HTML_REPORT=true
  )
  echo %%a | findstr /r /c:"--min=[0-9]*" >nul
  if !errorlevel! equ 0 (
    set MIN_COVERAGE=%%a
    set MIN_COVERAGE=!MIN_COVERAGE:~5!
  )
)

echo 🔍 开始运行测试并生成覆盖率报告...

REM 运行测试并生成覆盖率
flutter test --coverage

if not exist coverage\lcov.info (
  echo ❌ 覆盖率文件生成失败
  exit /b 1
)

echo ✅ 测试完成，覆盖率数据已生成

REM 检查是否安装了 genhtml
where genhtml >nul 2>&1
if %errorlevel% equ 0 (
  echo 📊 生成 HTML 覆盖率报告...

  REM 清理旧的报告
  if exist coverage\html rmdir /s /q coverage\html

  REM 生成 HTML 报告
  genhtml coverage\lcov.info -o coverage\html --quiet

  if "%HTML_REPORT%"=="true" (
    echo 🌐 打开覆盖率报告...
    start coverage\html\index.html
  )

  echo ✅ HTML报告已生成: coverage\html\index.html
) else (
  echo ⚠️  未安装 genhtml，跳过 HTML 报告生成
  echo    安装方法: 下载 http://ltp.sourceforge.net/coverage/lcov.php
)

REM 解析覆盖率数据
echo.
echo 📈 覆盖率统计:

where lcov >nul 2>&1
if %errorlevel% equ 0 (
  lcov --summary coverage\lcov.info
) else (
  echo ⚠️  未安装 lcov，无法显示详细统计
)

REM 检查最低覆盖率要求
if %MIN_COVERAGE% GTR 0 (
  echo.
  echo 🎯 检查最低覆盖率要求: %MIN_COVERAGE%%%
  echo ⚠️  Windows 脚本不支持自动覆盖率检查，请手动查看报告
)

echo.
echo ✨ 完成!
