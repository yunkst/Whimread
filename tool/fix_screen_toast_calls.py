#!/usr/bin/env python3
"""
修复 Screen 文件中的 ToastUtils 方法调用
将 showError/showSuccess/showWarning/showInfo 改为 ToastUtils.*
"""
import re
import sys

def fix_toast_calls(file_path, dry_run=False):
    """修复文件中的 Toast 调用"""
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    original_content = content

    # 替换模式
    patterns = [
        (r'\bshowInfo\(', 'ToastUtils.showInfo('),
        (r'\bshowError\(', 'ToastUtils.showError('),
        (r'\bshowSuccess\(', 'ToastUtils.showSuccess('),
        (r'\bshowWarning\(', 'ToastUtils.showWarning('),
        (r'\bshowWarningWithAction\(', 'ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('),  # 这个需要特殊处理
    ]

    for pattern, replacement in patterns:
        content = re.sub(pattern, replacement, content)

    # 特殊处理 showWarningWithAction
    # showWarningWithAction('message', 'action', callback) -> 需要使用 SnackBar
    # 先跳过这个复杂的转换

    if content != original_content:
        if dry_run:
            print(f"Would modify: {file_path}")
            print(f"  Changes: {content.count('ToastUtils.')} replacements")
        else:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            print(f"✅ Fixed: {file_path}")
            print(f"  Changes: {content.count('ToastUtils.')} replacements")
        return True
    else:
        print(f"⏭️  No changes: {file_path}")
        return False

def main():
    files = [
        'lib/screens/character_edit_screen.dart',
        'lib/screens/character_chat_screen.dart',
        'lib/screens/character_management_screen.dart',
    ]

    for file_path in files:
        try:
            fix_toast_calls(file_path, dry_run=False)
        except Exception as e:
            print(f"❌ Error processing {file_path}: {e}")

if __name__ == '__main__':
    main()
