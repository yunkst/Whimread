#!/usr/bin/env python3
"""
Repository提取辅助脚本

用于从database_service.dart中提取特定领域的Repository类
使用方法：
  python extract_repository.py <domain_name>

示例：
  python extract_repository.py character
  python extract_repository.py illustration
"""

import re
import sys
from pathlib import Path

# 配置
DATABASE_SERVICE_PATH = Path("lib/services/database_service.dart")
REPOSITORIES_DIR = Path("lib/repositories")

# 领域配置
DOMAIN_CONFIG = {
    "character": {
        "class_name": "CharacterRepository",
        "comment": "角色数据仓库",
        "start_marker": "// ========== 人物卡操作 ==========",
        "end_marker": "// ========== 角色图集缓存管理功能 ==========",
        "model_imports": ["../models/character.dart", "../models/character_update.dart"],
    },
    "character_relation": {
        "class_name": "CharacterRelationRepository",
        "comment": "角色关系数据仓库",
        "start_marker": "// ========== 角色关系操作 ==========",
        "end_marker": "// ========== 场景插图操作 ==========",
        "model_imports": ["../models/character_relationship.dart"],
    },
    "illustration": {
        "class_name": "IllustrationRepository",
        "comment": "场景插图数据仓库",
        "start_marker": "// ========== 场景插图操作 ==========",
        "end_marker": "// ========== 大纲操作 ==========",
        "model_imports": ["../models/scene_illustration.dart"],
    },
    "outline": {
        "class_name": "OutlineRepository",
        "comment": "大纲数据仓库",
        "start_marker": "// ========== 大纲操作 ==========",
        "end_marker": "// ========== 聊天场景操作 ==========",
        "model_imports": ["../models/outline.dart"],
    },
    "chat_scene": {
        "class_name": "ChatSceneRepository",
        "comment": "聊天场景数据仓库",
        "start_marker": "// ========== 聊天场景操作 ==========",
        "end_marker": "// ==========",
        "model_imports": ["../models/chat_scene.dart"],
    },
    "bookshelf": {
        "class_name": "BookshelfRepository",
        "comment": "书架分类数据仓库",
        "start_marker": "// ========== 多书架管理 ==========",
        "end_marker": "// ===========================",
        "model_imports": ["../models/bookshelf.dart"],
    },
}


def extract_methods(content, start_marker, end_marker):
    """提取指定标记区域的方法"""
    # 找到开始和结束位置
    start_idx = content.find(start_marker)
    if start_idx == -1:
        print(f"错误: 找不到开始标记 '{start_marker}'")
        return None

    end_idx = content.find(end_marker, start_idx)
    if end_idx == -1:
        # 如果没有结束标记，提取到文件末尾
        end_idx = len(content)
        print(f"警告: 找不到结束标记 '{end_marker}'，将提取到文件末尾")

    # 提取内容
    extracted = content[start_idx:end_idx]
    return extracted


def extract_method_signatures(extracted_content):
    """从提取的内容中获取方法签名"""
    # 匹配方法定义：Future<void/bool/int/String/List/Map> methodName(...)
    pattern = r"^\s+(?:Future<\w+(?:<[^>]+>)?>\s+)?(\w+)\s*\("
    matches = re.findall(pattern, extracted_content, re.MULTILINE)
    return matches


def generate_repository_class(domain, config, extracted_content, method_signatures):
    """生成Repository类代码"""

    # 生成导入语句
    imports = [
        "import 'package:sqflite/sqflite.dart';",
        "import '../services/logger_service.dart';",
        "import 'base_repository.dart';",
    ]
    for model_import in config.get("model_imports", []):
        imports.append(f"import '{model_import}';")

    imports_code = "\n".join(imports) + "\n"

    # 生成类文档
    class_doc = f"""/// {config['comment']}
///
/// 负责{domain.replace('_', ' ')}相关的数据库操作
"""

    # 生成类开始
    class_start = f"class {config['class_name']} extends BaseRepository {{"

    # 提取方法实现（简化版，只提取方法签名）
    methods_code = f"""
  // TODO: 从database_service.dart中提取{config['class_name']}的完整实现
  // 找到的方法：{', '.join(method_signatures[:10])}{'...' if len(method_signatures) > 10 else ''}

"""

    repository_code = f"""{imports_code}

{class_doc}{class_start}{methods_code}
}}
"""

    return repository_code


def main():
    if len(sys.argv) < 2:
        print("使用方法: python extract_repository.py <domain_name>")
        print("支持的领域:", ", ".join(DOMAIN_CONFIG.keys()))
        sys.exit(1)

    domain = sys.argv[1].lower()

    if domain not in DOMAIN_CONFIG:
        print(f"错误: 不支持的领域 '{domain}'")
        print("支持的领域:", ", ".join(DOMAIN_CONFIG.keys()))
        sys.exit(1)

    config = DOMAIN_CONFIG[domain]

    # 读取database_service.dart
    if not DATABASE_SERVICE_PATH.exists():
        print(f"错误: 找不到文件 {DATABASE_SERVICE_PATH}")
        sys.exit(1)

    with open(DATABASE_SERVICE_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # 提取方法
    extracted = extract_methods(
        content, config["start_marker"], config["end_marker"]
    )

    if extracted is None:
        sys.exit(1)

    # 获取方法签名
    method_signatures = extract_method_signatures(extracted)

    print(f"\n找到 {len(method_signatures)} 个方法:")
    for method in method_signatures:
        print(f"  - {method}()")

    # 生成Repository类
    repository_code = generate_repository_class(
        domain, config, extracted, method_signatures
    )

    # 写入文件
    output_path = REPOSITORIES_DIR / f"{domain}_repository.dart"

    # 确保目录存在
    REPOSITORIES_DIR.mkdir(exist_ok=True)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(repository_code)

    print(f"\n✅ 成功生成: {output_path}")
    print(f"\n下一步:")
    print(f"  1. 打开 {output_path}")
    print(f"  2. 从database_service.dart中复制完整的方法实现")
    print(f"  3. 更新DatabaseService使用新的Repository")
    print(f"  4. 运行测试验证")


if __name__ == "__main__":
    main()
