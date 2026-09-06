#!/usr/bin/env python3
"""迁移dify_service.dart中的debugPrint到LoggerService"""

import re

# 读取文件
with open('lib/services/dify_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 第一步：添加import
if "import 'logger_service.dart';" not in content:
    content = content.replace(
        "import 'stream_state_manager.dart';",
        "import 'stream_state_manager.dart';\nimport 'logger_service.dart';"
    )

# 第二步：移除debugPrint的import
content = content.replace(
    "import 'package:flutter/foundation.dart';",
    ""
)

# 第三步：替换所有debugPrint调用
# 使用正则表达式匹配所有debugPrint调用并转换
def replace_debug_print(match):
    indent = match.group(1)
    message = match.group(2)

    # 确定日志级别和标签
    if message.startswith('❌') or '失败' in message or '错误' in message or '异常' in message:
        level = 'e'
        tags = "['error']"
    elif message.startswith('⚠️') or '警告' in message:
        level = 'w'
        tags = "['warning']"
    elif message.startswith('✅') or '成功' in message or '完成' in message:
        level = 'i'
        tags = "['success']"
    elif message.startswith('🚀') or '开始' in message or 'API请求' in message:
        level = 'i'
        tags = "['api', 'request']"
    elif message.startswith('📡') or '响应' in message or '状态' in message:
        level = 'i'
        tags = "['api', 'response']"
    elif message.startswith('🔥') or '文本块' in message:
        level = 'd'
        tags = "['stream', 'chunk']"
    elif message.startswith('📝') or '流结束' in message:
        level = 'i'
        tags = "['stream', 'end']"
    elif message.startswith('🎯') or '最终' in message or '结果' in message:
        level = 'i'
        tags = "['result']"
    elif message.startswith('⏰') or '超时' in message:
        level = 'w'
        tags = "['timeout']"
    elif message.startswith('🌐') or 'URL' in message:
        level = 'i'
        tags = "['network']"
    elif message.startswith('📊') or '统计' in message or '长度' in message or '数量' in message:
        level = 'i'
        tags = "['stats']"
    elif message.startswith('==='):
        # 分隔线，使用debug级别
        level = 'd'
        tags = "['debug']"
    else:
        level = 'i'
        tags = "['info']"

    # 构建新的日志调用
    return f'{indent}LoggerService.instance.{level}(\n{indent}  {message},\n{indent}  category: LogCategory.ai,\n{indent}  tags: {tags},\n{indent});'

# 使用正则表达式匹配所有debugPrint调用
pattern = r"(\s+)debugPrint\('(.+?)'\);"
content = re.sub(pattern, replace_debug_print, content, flags=re.MULTILINE)

# 写回文件
with open('lib/services/dify_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("OK - dify_service.dart migration complete")
print("All debugPrint calls have been migrated to LoggerService")
