#!/bin/bash
# 修复 LoggerService 调用中的 error 参数

files=(
  "lib/mixins/reader/illustration_handler_mixin.dart"
  "lib/screens/backend_settings_screen.dart"
  "lib/screens/background_setting_screen.dart"
  "lib/screens/bookshelf_screen.dart"
  "lib/screens/chapter_list_screen.dart"
  "lib/screens/chapter_search_screen.dart"
  "lib/screens/reader_screen.dart"
  "lib/screens/search_screen.dart"
  "lib/services/api_service_wrapper.dart"
  "lib/services/database_service.dart"
  "lib/utils/error_helper.dart"
  "lib/widgets/bookshelf_selector.dart"
  "lib/widgets/generate_more_dialog.dart"
  "lib/widgets/immersive/immersive_init_screen.dart"
  "lib/widgets/scene_image_preview.dart"
  "lib/widgets/scene_illustration_dialog.dart"
  "lib/services/stream_state_manager.dart"
)

for file in "${files[@]}"; do
  if [ -f "$file" ]; then
    echo "处理: $file"

    # 使用 Python 进行复杂的文本替换
    python3 << 'PYTHON_SCRIPT'
import re
import sys

def fix_logger_error_param(content):
    """
    修复 LoggerService 调用中的 error 参数
    将 error: e 合并到 message 中
    """
    # 匹配 LoggerService 调用
    pattern = r"(LoggerService\.instance\.[ewid]\(\s*'[^']*',?\s*\n?\s*)error:\s*\w+,?\s*\n?"

    def replacer(match):
        prefix = match.group(1)

        # 提取 message
        msg_match = re.search(r"'([^']*)'", prefix)
        if not msg_match:
            return match.group(0)

        original_msg = msg_match.group(1)

        # 构建新的 message（追加 : $e）
        if original_msg:
            # 检查是否已经包含变量占位符
            if '$' not in original_msg:
                new_msg = f"{original_msg}: $e"
            else:
                new_msg = original_msg
        else:
            new_msg = "$e"

        # 替换 message
        new_prefix = prefix.replace(f"'{original_msg}'", f"'{new_msg}'")

        # 返回没有 error 参数的版本
        return new_prefix

    # 应用替换
    return re.sub(pattern, replacer, content, flags=re.MULTILINE)

if __name__ == '__main__':
    file_path = sys.argv[1]
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()

        fixed = fix_logger_error_param(content)

        if content != fixed:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(fixed)
            print(f"  ✅ 已修复")
        else:
            print(f"  ⏭️  无需修改")
    except Exception as e:
        print(f"  ❌ 错误: {e}")
PYTHON_SCRIPT
    "$file"
  fi
done

echo "完成！"
