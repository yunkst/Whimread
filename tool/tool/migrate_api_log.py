#!/usr/bin/env python3
"""迁移api_service_wrapper.dart中的debugPrint到LoggerService"""

import re

# 读取文件
with open('lib/services/api_service_wrapper.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

result = []

for line in lines:
    # 跳过import行中的debugPrint
    if "import 'package:flutter/foundation.dart'" in line:
        continue

    # 添加logger_service import
    if "import 'chapter_manager.dart';" in line:
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
                tags = "['error', 'api']"
            elif any(x in message for x in ['⚠️', '警告']):
                level = 'w'
                tags = "['warning', 'api']"
            elif any(x in message for x in ['✅', '成功']):
                level = 'i'
                tags = "['success', 'api']"
            elif any(x in message for x in ['🔄', '重新初始化', '检测到']):
                level = 'i'
                tags = "['retry', 'reinit']"
            elif any(x in message for x in ['🔌', '记录']):
                level = 'd'
                tags = "['connection', 'track']"
            elif any(x in message for x in ['===', '---', 'ApiServiceWrapper']):
                level = 'd'
                tags = "['debug', 'lifecycle']"
            elif '请求' in message or 'URL' in message or 'token' in message:
                level = 'i'
                tags = "['api', 'request']"
            elif '响应' in message or '状态' in message:
                level = 'i'
                tags = "['api', 'response']"
            elif '生成' in message or '图片' in message:
                level = 'i'
                tags = "['image', 'generation']"
            elif '模型' in message:
                level = 'i'
                tags = "['model']"
            elif '数据' in message or '解析' in message:
                level = 'd'
                tags = "['data', 'parse']"
            else:
                level = 'i'
                tags = "['api']"

            # 构建新的日志调用
            new_line = f"{indent}LoggerService.instance.{level}(\n"
            new_line += f"{indent}  '{message}',\n"
            new_line += f"{indent}  category: LogCategory.network,\n"
            new_line += f"{indent}  tags: {tags},\n"
            new_line += f"{indent});\n"
            result.append(new_line)
        else:
            # 多行debugPrint，暂时保留原样
            result.append(line)
    else:
        result.append(line)

# 确保import存在
if not any("import 'logger_service.dart';" in line for line in result):
    new_result = []
    for line in result:
        new_result.append(line)
        if "import 'chapter_manager.dart';" in line:
            new_result.append("import 'logger_service.dart';\n")
    result = new_result

# 写回文件
with open('lib/services/api_service_wrapper.dart', 'w', encoding='utf-8') as f:
    f.writelines(result)

print("OK - api_service_wrapper.dart migration complete")
print("Migrated debugPrint calls to LoggerService")
