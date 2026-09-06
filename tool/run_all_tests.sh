#!/bin/bash
# run_all_tests.sh - 全面测试脚本
#
# 运行所有测试并生成覆盖率报告
# 用于CI/CD和发布前的完整验证

echo "🧪 运行全部测试（Mock + 真实数据库 + 覆盖率）..."
echo ""

# 切换到项目目录
cd "$(dirname "$0")/.."

# 清理旧的覆盖率数据
echo "清理旧的覆盖率数据..."
rm -f coverage/lcov.info

# 运行快速单元测试
echo "=========================================="
echo "1️⃣  运行快速单元测试（Mock）..."
echo "=========================================="
tool/../run_unit_tests.sh

if [ $? -ne 0 ]; then
  echo ""
  echo "❌ 单元测试失败，终止执行"
  exit 1
fi

echo ""
echo "=========================================="
echo "2️⃣  运行数据库集成测试..."
echo "=========================================="
tool/../run_integration_tests.sh

if [ $? -ne 0 ]; then
  echo ""
  echo "❌ 集成测试失败，终止执行"
  exit 1
fi

echo ""
echo "=========================================="
echo "3️⃣  运行全量测试并生成覆盖率报告..."
echo "=========================================="
flutter test --coverage

if [ $? -ne 0 ]; then
  echo ""
  echo "❌ 全量测试失败"
  exit 1
fi

# 生成覆盖率报告
echo ""
echo "=========================================="
echo "4️⃣  生成覆盖率报告..."
echo "=========================================="

# 检查 lcov 是否安装
if command -v lcov &> /dev/null; then
  # 生成HTML覆盖率报告
  genhtml coverage/lcov.info -o coverage/html

  echo "✅ 覆盖率报告已生成"
  echo "📊 HTML报告位置: coverage/html/index.html"

  # 显示覆盖率摘要
  echo ""
  echo "📈 覆盖率摘要："
  lcov --summary coverage/lcov.info | grep lines
else
  echo "⚠️  lcov 未安装，跳过HTML报告生成"
  echo "📊 原始覆盖率数据: coverage/lcov.info"
fi

echo ""
echo "=========================================="
echo "✅ 全部测试完成"
echo "=========================================="
echo ""
echo "测试结果总结："
echo "  - 单元测试: ✅ 通过"
echo "  - 集成测试: ✅ 通过"
echo "  - 全量测试: ✅ 通过"
echo "  - 覆盖率报告: ✅ 已生成"
echo ""
