#!/usr/bin/env bash

# 简单的覆盖率查看脚本 (无需 lcov)

echo "📊 Flutter 测试覆盖率报告"
echo "================================"
echo ""

# 检查覆盖率文件是否存在
if [ ! -f coverage/lcov.info ]; then
  echo "❌ 覆盖率文件不存在，请先运行: flutter test --coverage"
  exit 1
fi

# 统计总行数
TOTAL_LINES=$(grep -c "^SF:" coverage/lcov.info)
echo "📁 覆盖的文件数: $TOTAL_LINES"
echo ""

# 显示前20个最需要测试的文件
echo "🔍 覆盖率最低的文件 (Top 20):"
echo "-------------------------------------------"

# 提取文件覆盖率
grep "^SF:" coverage/lcov.info | while read -r line; do
  file=${line#:SF:}
  echo "$file"
done | head -20

echo ""
echo "💡 提示:"
echo "   - 安装 lcov 查看详细报告: brew install lcov (macOS)"
echo "   - 生成HTML报告: genhtml coverage/lcov.info -o coverage/html"
echo "   - 查看在线工具: https://codecov.io"
