#!/usr/bin/env python3
"""迁移database_service.dart中的debugPrint到LoggerService"""

import re

# 读取文件
with open('lib/services/database_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 定义替换规则
replacements = [
    # 数据库升级日志
    (r"debugPrint\('数据库升级：添加了 novel_chapters\.readAt 字段'\);",
     "LoggerService.instance.i(\n          '数据库升级：添加了 novel_chapters.readAt 字段',\n          category: LogCategory.database,\n          tags: ['migration', 'schema', 'readAt'],\n        );"),

    (r"debugPrint\('数据库升级：添加了 characters\.aliases 字段'\);",
     "LoggerService.instance.i(\n          '数据库升级：添加了 characters.aliases 字段',\n          category: LogCategory.database,\n          tags: ['migration', 'schema', 'aliases'],\n        );"),

    (r"debugPrint\('数据库升级：创建了 character_relationships 表和索引'\);",
     "LoggerService.instance.i(\n          '数据库升级：创建了 character_relationships 表和索引',\n          category: LogCategory.database,\n          tags: ['migration', 'schema', 'relationships'],\n        );"),

    (r"debugPrint\('数据库升级：添加了AI伴读设置字段'\);",
     "LoggerService.instance.i(\n          '数据库升级：添加了AI伴读设置字段',\n          category: LogCategory.database,\n          tags: ['migration', 'schema', 'ai_accompaniment'],\n        );"),

    # 内存缓存日志
    (r"debugPrint\('🧹 内存缓存已满，已清空 \(\$_maxMemoryCacheSize条\)'\);",
     "LoggerService.instance.i(\n          '内存缓存已满，已清空 ($_maxMemoryCacheSize条)',\n          category: LogCategory.cache,\n          tags: ['memory', 'cleanup'],\n        );"),

    (r"debugPrint\('🧹 DatabaseService内存状态已清理'\);",
     "LoggerService.instance.i(\n          'DatabaseService内存状态已清理',\n          category: LogCategory.database,\n          tags: ['memory', 'cleanup'],\n        );"),

    # 角色操作日志
    (r"debugPrint\('更新角色: \$\{newCharacter\.name\} \(ID: \$\{existingCharacter\.id\}\)'\);",
     "LoggerService.instance.i(\n          '更新角色: ${newCharacter.name} (ID: ${existingCharacter.id})',\n          category: LogCategory.character,\n          tags: ['update', 'success'],\n        );"),

    (r"debugPrint\('创建新角色: \$\{newCharacter\.name\} \(ID: \$id\)'\);",
     "LoggerService.instance.i(\n          '创建新角色: ${newCharacter.name} (ID: $id)',\n          category: LogCategory.character,\n          tags: ['create', 'success'],\n        );"),

    (r"debugPrint\('批量更新角色失败: \$\{character\.name\}, 错误: \$e'\);",
     "LoggerService.instance.e(\n          '批量更新角色失败: ${character.name}, 错误: $e',\n          category: LogCategory.character,\n          tags: ['batch', 'error'],\n        );"),

    (r"debugPrint\(\n?'批量更新完成，成功更新 \$\{updatedCharacters\.length\}/\$\{newCharacters\.length\} 个角色'\n?\);",
     "LoggerService.instance.i(\n          '批量更新完成，成功更新 ${updatedCharacters.length}/${newCharacters.length} 个角色',\n          category: LogCategory.character,\n          tags: ['batch', 'update'],\n        );"),

    # 章节读取日志
    (r"debugPrint\('✅ 章节已标记为已读: \$chapterUrl'\);",
     "LoggerService.instance.i(\n          '章节已标记为已读: $chapterUrl',\n          category: LogCategory.database,\n          tags: ['chapter', 'read', 'success'],\n        );"),

    (r"debugPrint\('获取章节内容失败: \$e'\);",
     "LoggerService.instance.e(\n          '获取章节内容失败: $e',\n          category: LogCategory.database,\n          tags: ['chapter', 'content', 'error'],\n        );"),

    # 关系操作日志
    (r"debugPrint\('✅ 创建关系成功: \$id'\);",
     "LoggerService.instance.i(\n          '创建关系成功: $id',\n          category: LogCategory.character,\n          tags: ['relationship', 'create', 'success'],\n        );"),

    (r"debugPrint\('❌ 创建关系失败: \$e'\);",
     "LoggerService.instance.e(\n          '创建关系失败: $e',\n          category: LogCategory.character,\n          tags: ['relationship', 'create', 'error'],\n        );"),

    (r"debugPrint\('✅ 更新关系成功: \$\{relationship\.id\}\)'\);",
     "LoggerService.instance.i(\n          '更新关系成功: ${relationship.id}',\n          category: LogCategory.character,\n          tags: ['relationship', 'update', 'success'],\n        );"),

    (r"debugPrint\('❌ 更新关系失败: \$e'\);",
     "LoggerService.instance.e(\n          '更新关系失败: $e',\n          category: LogCategory.character,\n          tags: ['relationship', 'update', 'error'],\n        );"),

    (r"debugPrint\('✅ 删除关系成功: \$relationshipId'\);",
     "LoggerService.instance.i(\n          '删除关系成功: $relationshipId',\n          category: LogCategory.character,\n          tags: ['relationship', 'delete', 'success'],\n        );"),

    (r"debugPrint\('❌ 删除关系失败: \$e'\);",
     "LoggerService.instance.e(\n          '删除关系失败: $e',\n          category: LogCategory.character,\n          tags: ['relationship', 'delete', 'error'],\n        );"),

    # AI伴读日志
    (r"debugPrint\('⚠️ 新增背景设定为空，跳过更新'\);",
     "LoggerService.instance.w(\n          '新增背景设定为空，跳过更新',\n          category: LogCategory.ai,\n          tags: ['background', 'validation'],\n        );"),

    (r"debugPrint\('⚠️ 未找到小说: \$novelUrl'\);",
     "LoggerService.instance.w(\n          '未找到小说: $novelUrl',\n          category: LogCategory.database,\n          tags: ['novel', 'not_found'],\n        );"),

    (r"debugPrint\('✅ 背景设定追加成功: \$novelUrl \(新增 \$\{newBackground\.length\} 字符\)'\);",
     "LoggerService.instance.i(\n          '背景设定追加成功: $novelUrl (新增 ${newBackground.length} 字符)',\n          category: LogCategory.ai,\n          tags: ['background', 'update', 'success'],\n        );"),

    (r"debugPrint\('⚠️ AI返回角色列表为空，跳过更新'\);",
     "LoggerService.instance.w(\n          'AI返回角色列表为空，跳过更新',\n          category: LogCategory.ai,\n          tags: ['character', 'batch', 'empty'],\n        );"),

    (r"debugPrint\('✅ 更新角色: \$\{aiRole\.name\}\)'\);",
     "LoggerService.instance.i(\n          '更新角色: ${aiRole.name}',\n          category: LogCategory.ai,\n          tags: ['character', 'update', 'success'],\n        );"),

    (r"debugPrint\('✅ 新增角色: \$\{aiRole\.name\}\)'\);",
     "LoggerService.instance.i(\n          '新增角色: ${aiRole.name}',\n          category: LogCategory.ai,\n          tags: ['character', 'create', 'success'],\n        );"),

    (r"debugPrint\('❌ 更新/插入角色失败: \$\{aiRole\.name\}, 错误: \$e'\);",
     "LoggerService.instance.e(\n          '更新/插入角色失败: ${aiRole.name}, 错误: $e',\n          category: LogCategory.ai,\n          tags: ['character', 'error'],\n        );"),

    (r"debugPrint\('✅ 批量更新角色完成: \$successCount/\$\{aiRoles\.length\}\)'\);",
     "LoggerService.instance.i(\n          '批量更新角色完成: $successCount/${aiRoles.length}',\n          category: LogCategory.ai,\n          tags: ['character', 'batch', 'success'],\n        );"),

    (r"debugPrint\('⚠️ AI返回关系列表为空，跳过更新'\);",
     "LoggerService.instance.w(\n          'AI返回关系列表为空，跳过更新',\n          category: LogCategory.ai,\n          tags: ['relationship', 'batch', 'empty'],\n        );"),

    (r"debugPrint\('⚠️ 未找到source角色: \$\{aiRelation\.source\}，跳过关系: \$aiRelation'\);",
     "LoggerService.instance.w(\n          '未找到source角色: ${aiRelation.source}，跳过关系: $aiRelation',\n          category: LogCategory.ai,\n          tags: ['relationship', 'character_not_found'],\n        );"),

    (r"debugPrint\('⚠️ 未找到target角色: \$\{aiRelation\.target\}，跳过关系: \$aiRelation'\);",
     "LoggerService.instance.w(\n          '未找到target角色: ${aiRelation.target}，跳过关系: $aiRelation',\n          category: LogCategory.ai,\n          tags: ['relationship', 'character_not_found'],\n        );"),

    (r"debugPrint\('✅ 更新关系: \$\{aiRelation\.source\} -> \$\{aiRelation\.target\} \(\$\{aiRelation\.type\}\)'\);",
     "LoggerService.instance.i(\n          '更新关系: ${aiRelation.source} -> ${aiRelation.target} (${aiRelation.type})',\n          category: LogCategory.ai,\n          tags: ['relationship', 'update', 'success'],\n        );"),

    (r"debugPrint\('✅ 新增关系: \$\{aiRelation\.source\} -> \$\{aiRelation\.target\} \(\$\{aiRelation\.type\}\)'\);",
     "LoggerService.instance.i(\n          '新增关系: ${aiRelation.source} -> ${aiRelation.target} (${aiRelation.type})',\n          category: LogCategory.ai,\n          tags: ['relationship', 'create', 'success'],\n        );"),

    (r"debugPrint\('❌ 更新/插入关系失败: \$aiRelation, 错误: \$e'\);",
     "LoggerService.instance.e(\n          '更新/插入关系失败: $aiRelation, 错误: $e',\n          category: LogCategory.ai,\n          tags: ['relationship', 'error'],\n        );"),

    (r"debugPrint\('✅ 批量更新关系完成: \$successCount/\$\{aiRelations\.length\}\)'\);",
     "LoggerService.instance.i(\n          '批量更新关系完成: $successCount/${aiRelations.length}',\n          category: LogCategory.ai,\n          tags: ['relationship', 'batch', 'success'],\n        );"),
]

# 执行替换
for pattern, replacement in replacements:
    content = re.sub(pattern, replacement, content)

# 写回文件
with open('lib/services/database_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("OK - database_service.dart migration complete")
print(f"Applied {len(replacements)} replacement rules")
