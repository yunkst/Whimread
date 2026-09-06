#!/usr/bin/env bash

# Flutter 代码覆盖率检查脚本
#
# 用法:
#   ./scripts/check_coverage.sh              # 生成覆盖率报告
#   ./scripts/check_coverage.sh --html       # 生成HTML报告并打开
#   ./scripts/check_coverage.sh --min 80     # 检查覆盖率是否达到80%

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 参数解析
HTML_REPORT=false
MIN_COVERAGE=0
GENHTML_CMD="genhtml"

for arg in "$@"; do
  case $arg in
    --html)
      HTML_REPORT=true
      ;;
    --min=*)
      MIN_COVERAGE="${arg#*=}"
      ;;
    *)
      echo "未知参数: $arg"
      echo "用法: $0 [--html] [--min=<覆盖率>]"
      exit 1
      ;;
  esac
done

echo -e "${GREEN}🔍 开始运行测试并生成覆盖率报告...${NC}"

# 运行测试并生成覆盖率
flutter test --coverage

if [ ! -f coverage/lcov.info ]; then
  echo -e "${RED}❌ 覆盖率文件生成失败${NC}"
  exit 1
fi

echo -e "${GREEN}✅ 测试完成，覆盖率数据已生成${NC}"

# 检查是否安装了 genhtml
if command -v genhtml &> /dev/null; then
  echo -e "${GREEN}📊 生成 HTML 覆盖率报告...${NC}"

  # 清理旧的报告
  rm -rf coverage/html

  # 生成 HTML 报告
  genhtml coverage/lcov.info -o coverage/html --quiet

  if [ "$HTML_REPORT" = true ]; then
    echo -e "${GREEN}🌐 打开覆盖率报告...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
      open coverage/html/index.html
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
      xdg-open coverage/html/index.html
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
      start coverage/html/index.html
    fi
  fi

  echo -e "${GREEN}✅ HTML报告已生成: coverage/html/index.html${NC}"
else
  echo -e "${YELLOW}⚠️  未安装 genhtml，跳过 HTML 报告生成${NC}"
  echo -e "${YELLOW}   安装方法:${NC}"
  echo -e "${YELLOW}   macOS:   brew install lcov${NC}"
  echo -e "${YELLOW}   Ubuntu:  sudo apt-get install lcov${NC}"
  echo -e "${YELLOW}   Windows: 下载 http://ltp.sourceforge.net/coverage/lcov.php${NC}"
fi

# 解析覆盖率数据
echo -e "\n${GREEN}📈 覆盖率统计:${NC}"

# 使用 lcov 解析覆盖率
if command -v lcov &> /dev/null; then
  lcov --summary coverage/lcov.info
else
  echo -e "${YELLOW}⚠️  未安装 lcov，无法显示详细统计${NC}"
fi

# 检查最低覆盖率要求
if [ "$MIN_COVERAGE" -gt 0 ]; then
  echo -e "\n${GREEN}🎯 检查最低覆盖率要求: ${MIN_COVERAGE}%${NC}"

  # 提取行覆盖率百分比
  COVERAGE=$(lcov --summary coverage/lcov.info 2>&1 | grep "lines" | grep -oP '\d+\.\d+(?=%)' | head -1)

  if [ -z "$COVERAGE" ]; then
    echo -e "${RED}❌ 无法解析覆盖率数据${NC}"
    exit 1
  fi

  # 比较覆盖率 (使用 bc 进行浮点数比较)
  if command -v bc &> /dev/null; then
    RESULT=$(echo "$COVERAGE >= $MIN_COVERAGE" | bc)
    if [ "$RESULT" -eq 1 ]; then
      echo -e "${GREEN}✅ 当前覆盖率 ${COVERAGE}% 达到要求 (>= ${MIN_COVERAGE}%)${NC}"
    else
      echo -e "${RED}❌ 当前覆盖率 ${COVERAGE}% 未达到要求 (>= ${MIN_COVERAGE}%)${NC}"
      exit 1
    fi
  else
    echo -e "${YELLOW}⚠️  未安装 bc，跳过覆盖率检查${NC}"
  fi
fi

echo -e "\n${GREEN}✨ 完成!${NC}"
