#!/usr/bin/env python3
"""迁移dify_service.dart中的debugPrint到LoggerService - 简化版"""

import re

# 读取文件
with open('lib/services/dify_service.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

result = []
in_multiline_string = False

for line in lines:
    # 跳过import行中的debugPrint
    if "import 'package:flutter/foundation.dart'" in line:
        continue

    # 添加logger_service import（在最后一个import之后）
    if "import 'stream_state_manager.dart';" in line:
        result.append(line)
        result.append("import 'logger_service.dart';\n")
        continue

    # 处理debugPrint调用
    if 'debugPrint(' in line:
        # 获取缩进
        indent_match = re.match(r'^(\s*)', line)
        indent = indent_match.group(1) if indent_match else ''

        # 提取消息内容
        msg_match = re.search(r"debugPrint\('(.+?)'\);", line)
        if msg_match:
            message = msg_match.group(1)

            # 确定日志级别和标签
            if any(x in message for x in ['❌', '失败', '错误', '异常']):
                level = 'e'
                tags = "['error', 'dify']"
            elif any(x in message for x in ['⚠️', '警告']):
                level = 'w'
                tags = "['warning', 'dify']"
            elif any(x in message for x in ['✅', '成功', '完成']):
                level = 'i'
                tags = "['success', 'dify']"
            elif any(x in message for x in ['🚀', '开始', 'API 请求']):
                level = 'i'
                tags = "['api', 'request', 'dify']"
            elif any(x in message for x in ['📡', '响应', '状态码']):
                level = 'i'
                tags = "['api', 'response', 'dify']"
            elif any(x in message for x in ['🔥', '文本块', 'onChunk']):
                level = 'd'
                tags = "['stream', 'chunk', 'dify']"
            elif any(x in message for x in ['📝', '流结束']):
                level = 'i'
                tags = "['stream', 'end', 'dify']"
            elif any(x in message for x in ['⏰', '超时']):
                level = 'w'
                tags = "['timeout', 'dify']"
            elif any(x in message for x in ['🌐', 'URL']):
                level = 'd'
                tags = "['network', 'dify']"
            elif any(x in message for x in ['📊', '统计', '长度', '数量', '数组长度']):
                level = 'd'
                tags = "['stats', 'dify']"
            elif '=====' in message or '---' in message:
                level = 'd'
                tags = "['debug', 'separator', 'dify']"
            else:
                level = 'i'
                tags = "['info', 'dify']"

            # 构建新的日志调用
            new_line = f"{indent}LoggerService.instance.{level}(\n"
            new_line += f"{indent}  '{message}',\n"
            new_line += f"{indent}  category: LogCategory.ai,\n"
            new_line += f"{indent}  tags: {tags},\n"
            new_line += f"{indent});\n"
            result.append(new_line)
        else:
            # 多行debugPrint，暂时保留原样
            result.append(line)
    else:
        result.append(line)

# 添加import（如果还没有）
if any("import 'logger_service.dart';" in line for line in result):
    pass
else:
    # 在stream_state_manager import后添加
    new_result = []
    for line in result:
        new_result.append(line)
        if "import 'stream_state_manager.dart';" in line:
            new_result.append("import 'logger_service.dart';\n")
    result = new_result

# 写回文件
with open('lib/services/dify_service.dart', 'w', encoding='utf-8') as f:
    f.writelines(result)

print("OK - dify_service.dart migration complete")
print("Migrated single-line debugPrint calls to LoggerService")
