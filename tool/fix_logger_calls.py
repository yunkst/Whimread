#!/usr/bin/env python3
"""
修复 LoggerService 错误调用
将 error: e 参数合并到 message 中
"""
import re
import sys

def fix_logger_calls(content):
    """修复 LoggerService 调用中的 error 参数"""
    # 匹配 LoggerService.instance.e/w/i/d 调用中包含 error 参数的情况
    pattern = r"(LoggerService\.instance\.[ewid]\(\s*'[^']*',?\s*)(error:\s*\w+,?\s*)(.*?\))"

    def replacer(match):
        prefix = match.group(1)
        error_param = match.group(2)
        rest = match.group(3)

        # 提取 error 变量名
        error_match = re.search(r'error:\s*(\w+)', error_param)
        if not error_match:
            return match.group(0)

        error_var = error_match.group(1)

        # 检查 message 是否已经有内容
        message_match = re.search(r"'([^']*)'", prefix)
        if not message_match:
            return match.group(0)

        original_message = message_match.group(1)

        # 构建新的 message
        if original_message:
            new_message = f"{original_message}: ${{{error_var}}}"
        else:
            new_message = f"${{{error_var}}}"

        # 替换 message
        new_prefix = prefix.replace(f"'{original_message}'", f"'{new_message}'")

        # 移除 error 参数
        new_rest = rest

        return f"{new_prefix}{new_rest}"

    # 多次应用直到没有更多匹配
    prev_content = None
    while content != prev_content:
        prev_content = content
        content = re.sub(pattern, replacer, content, flags=re.DOTALL)

    return content

def main():
    if len(sys.argv) < 2:
        print("Usage: fix_logger_calls.py <file1> [file2] ...")
        sys.exit(1)

    for filepath in sys.argv[1:]:
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()

            fixed_content = fix_logger_calls(content)

            if content != fixed_content:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(fixed_content)
                print(f"✅ Fixed: {filepath}")
            else:
                print(f"⏭️  No changes: {filepath}")

        except Exception as e:
            print(f"❌ Error processing {filepath}: {e}")

if __name__ == '__main__':
    main()
