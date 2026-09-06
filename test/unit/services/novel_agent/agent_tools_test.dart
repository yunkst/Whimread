/// AgentTools 工具定义单元测试
///
/// 验证工具的 OpenAI Function Calling schema：
/// - 工具总数正确
/// - 每个工具的 name、description、parameters 结构合法
/// - required 参数列表正确
/// - findTool 查找功能
/// - schema 声明与 tool_executor.dart 执行端实际读取的字段双向对齐
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/agent_tools.dart';

void main() {
  group('AgentTools.allTools — 基础验证', () {
    test('应该有 28 个工具（新增 get_background_setting）', () {
      expect(AgentTools.allTools.length, 28, reason: '所有工具数应为 28（2026-07 在 dispatch_subagent 基础上新增 get_background_setting：'
          'list/select/create novel + read/list/search chapter + create/update/rewrite/delete chapter + '
          'list/update/create/delete character + get_background_setting/update_background_setting + '
          'update_outline/write_outline/get_outline + set_novel_cover + prompt tags + '
          'text2img 图片工具 + 图生视频工具 + dispatch_subagent）');
    });

    test('每个工具都有 type=function', () {
      for (final tool in AgentTools.allTools) {
        expect(tool['type'], 'function',
            reason: '${tool['function']['name']} 应该 type=function');
      }
    });

    test('每个工具都有 function.name', () {
      for (final tool in AgentTools.allTools) {
        final func = tool['function'] as Map<String, dynamic>;
        expect(func['name'], isA<String>());
        expect((func['name'] as String).isNotEmpty, true);
      }
    });

    test('每个工具都有非空 description', () {
      for (final tool in AgentTools.allTools) {
        final func = tool['function'] as Map<String, dynamic>;
        final desc = func['description'] as String?;
        expect(desc, isNotNull,
            reason: '${func['name']} 缺少 description');
        expect(desc!.isNotEmpty, true,
            reason: '${func['name']} description 为空');
      }
    });

    test('每个工具都有 parameters.type=object', () {
      for (final tool in AgentTools.allTools) {
        final func = tool['function'] as Map<String, dynamic>;
        final params = func['parameters'] as Map<String, dynamic>?;
        expect(params, isNotNull,
            reason: '${func['name']} 缺少 parameters');
        expect(params!['type'], 'object',
            reason: '${func['name']} parameters.type 应为 object');
      }
    });

    test('工具名不重复', () {
      final names =
          AgentTools.allTools.map((t) => t['function']['name'] as String).toList();
      expect(names.toSet().length, names.length,
          reason: '工具名有重复: ${names.where((n) => names.where((x) => x == n).length > 1).toSet()}');
    });
  });

  group('AgentTools — 各工具 schema 详细验证', () {
    /// 辅助：验证工具 schema
    void verifyToolSchema(
      String name, {
      List<String> required = const [],
      List<String> optional = const [],
    }) {
      final tool = AgentTools.findTool(name);
      expect(tool, isNotNull, reason: '工具 $name 未找到');

      final params =
          tool!['function']['parameters'] as Map<String, dynamic>;
      final properties = params['properties'] as Map<String, dynamic>? ?? {};
      final requiredList = params['required'] as List? ?? [];

      // 验证 required 参数都在 properties 中
      for (final r in required) {
        expect(properties.containsKey(r), true,
            reason: '$name: required 参数 "$r" 不在 properties 中');
        expect(requiredList.contains(r), true,
            reason: '$name: "$r" 应在 required 列表中');
      }

      // 验证 optional 参数都在 properties 中但不在 required 中
      for (final o in optional) {
        expect(properties.containsKey(o), true,
            reason: '$name: optional 参数 "$o" 不在 properties 中');
        expect(requiredList.contains(o), false,
            reason: '$name: "$o" 不应在 required 列表中');
      }

      // 验证 required 长度
      expect(requiredList.length, required.length,
          reason: '$name: required 列表长度不匹配，期望 ${required.length}，实际 ${requiredList.length}');
    }

    test('list_novels — 无参数', () {
      verifyToolSchema('list_novels');
    });

    test('select_novel — 需要 novelId', () {
      verifyToolSchema('select_novel', required: ['novelId']);
    });

    test('create_novel — 需要 title, description 可选', () {
      verifyToolSchema('create_novel',
          required: ['title'], optional: ['description']);
    });

    test('read_chapter_content — 需要 position', () {
      verifyToolSchema('read_chapter_content', required: ['position']);
    });

    test('list_chapters — 无参数（从上下文读取当前小说）', () {
      verifyToolSchema('list_chapters');
    });

    test('search_in_chapters — 需要 keyword', () {
      verifyToolSchema('search_in_chapters', required: ['keyword']);
    });

    test('update_chapter_content — 需要 position + oldString + newString（edit 风格）', () {
      verifyToolSchema('update_chapter_content',
          required: ['position', 'oldString', 'newString']);
    });

    test('update_chapter_content — replaceAll 为可选 boolean', () {
      final tool = AgentTools.findTool('update_chapter_content');
      final props = tool!['function']['parameters']['properties']
          as Map<String, dynamic>;
      final replaceAll = props['replaceAll'] as Map<String, dynamic>?;
      expect(replaceAll, isNotNull);
      expect(replaceAll!['type'], 'boolean');
    });

    test('rewrite_chapter — 需要 position + rewriteInstruction（LLM 重写）', () {
      verifyToolSchema('rewrite_chapter',
          required: ['position', 'rewriteInstruction']);
    });

    test('delete_chapter — 需要 position（破坏性）', () {
      verifyToolSchema('delete_chapter', required: ['position']);
    });

    test('list_characters — 无参数（从上下文读取当前小说）', () {
      verifyToolSchema('list_characters');
    });

    test('update_character — 需要 name，其余结构化字段可选', () {
      verifyToolSchema('update_character',
          required: ['name'],
          optional: [
            'gender',
            'age',
            'occupation',
            'personality',
            'appearanceFeatures',
            'bodyType',
            'clothingStyle',
            'backgroundStory',
            'aliases',
            'avatarMediaId',
          ]);
    });

    test('create_character — 需要 name，其余结构化字段可选', () {
      verifyToolSchema('create_character',
          required: ['name'],
          optional: [
            'gender',
            'age',
            'occupation',
            'personality',
            'appearanceFeatures',
            'bodyType',
            'clothingStyle',
            'backgroundStory',
            'aliases',
          ]);
    });

    test('delete_character — 需要 name（破坏性）', () {
      verifyToolSchema('delete_character', required: ['name']);
    });

    test('update_background_setting — 需要 setting', () {
      verifyToolSchema('update_background_setting', required: ['setting']);
    });

    test('update_outline — 需要 oldString + newString（edit 风格）', () {
      verifyToolSchema('update_outline',
          required: ['oldString', 'newString']);
    });

    test('update_outline — replaceAll 为可选 boolean', () {
      final tool = AgentTools.findTool('update_outline');
      final props = tool!['function']['parameters']['properties']
          as Map<String, dynamic>;
      final replaceAll = props['replaceAll'] as Map<String, dynamic>?;
      expect(replaceAll, isNotNull);
      expect(replaceAll!['type'], 'boolean');
    });

    test('write_outline — 需要 content（write 风格）', () {
      verifyToolSchema('write_outline', required: ['content']);
    });

    test('get_outline — 无参数（从上下文读取当前小说）', () {
      verifyToolSchema('get_outline');
    });

    test('set_novel_cover — 需要 mediaId（null 表示清空封面）', () {
      verifyToolSchema('set_novel_cover', required: ['mediaId']);
    });
  });

  group('AgentTools — 参数类型验证', () {
    test('position 参数应为 integer 类型', () {
      final tools = [
        'read_chapter_content',
        'update_chapter_content',
        'rewrite_chapter',
      ];
      for (final name in tools) {
        final tool = AgentTools.findTool(name);
        final props = tool!['function']['parameters']['properties']
            as Map<String, dynamic>;
        final position = props['position'] as Map<String, dynamic>?;
        expect(position, isNotNull, reason: '$name 缺少 position');
        expect(position!['type'], 'integer',
            reason: '$name position 应为 integer 类型');
      }
    });

    test('novelId 参数（仅 select_novel 有）应为 integer 类型', () {
      final tool = AgentTools.findTool('select_novel');
      final props = tool!['function']['parameters']['properties']
          as Map<String, dynamic>;
      final novelId = props['novelId'] as Map<String, dynamic>?;
      expect(novelId, isNotNull, reason: 'select_novel 缺少 novelId');
      expect(novelId!['type'], 'integer',
          reason: 'select_novel novelId 应为 integer 类型');
    });

    test('任何工具都不应有 chapterId 参数（已改为 position）', () {
      for (final tool in AgentTools.allTools) {
        final props = tool['function']['parameters']['properties']
            as Map<String, dynamic>;
        expect(props.containsKey('chapterId'), false,
            reason: '${tool['function']['name']} 不应再有 chapterId 参数');
      }
    });

    test('任何工具都不应有 chapterUrl 参数', () {
      for (final tool in AgentTools.allTools) {
        final props = tool['function']['parameters']['properties']
            as Map<String, dynamic>;
        expect(props.containsKey('chapterUrl'), false,
            reason: '${tool['function']['name']} 不应再有 chapterUrl 参数');
      }
    });

    test('任何工具都不应有 novelUrl 参数', () {
      for (final tool in AgentTools.allTools) {
        final props = tool['function']['parameters']['properties']
            as Map<String, dynamic>;
        expect(props.containsKey('novelUrl'), false,
            reason: '${tool['function']['name']} 不应再有 novelUrl 参数');
      }
    });

    test('除 select_novel 外，任何工具都不应有 novelId 参数', () {
      for (final tool in AgentTools.allTools) {
        final name = tool['function']['name'] as String;
        if (name == 'select_novel') continue;
        final props = tool['function']['parameters']['properties']
            as Map<String, dynamic>;
        expect(props.containsKey('novelId'), false,
            reason: '$name 不应再有 novelId 参数（已改为上下文驱动）');
      }
    });

    test('create_novel 不暴露 author 字段（硬编码为"原创"）', () {
      final tool = AgentTools.findTool('create_novel');
      final props = tool!['function']['parameters']['properties']
          as Map<String, dynamic>;
      expect(props.containsKey('author'), false,
          reason: 'create_novel 不应暴露 author 字段，固定为"原创"');
    });
  });

  group('AgentTools — schema vs 执行端字段双向对齐', () {
    /// 工具名 → (子执行器文件名, 子执行器方法名)。
    ///
    /// 2026-07-10 拆分：原 tool_executor.dart 上的私有 `_xxxMethod`
    /// 已按业务域拆到 7 个子执行器（位于 tool_executor/ 子目录），方法改为
    /// 公开命名（去掉前导下划线）。本测试扫描子执行器源码切片。
    const toolMethodMap = <String, ({String file, String method})>{
      'list_novels': (file: 'novel_navigation_executor.dart', method: 'listNovels'),
      'select_novel': (file: 'novel_navigation_executor.dart', method: 'selectNovel'),
      'create_novel': (file: 'novel_navigation_executor.dart', method: 'createNovel'),
      'read_chapter_content': (file: 'chapter_read_executor.dart', method: 'readChapterContent'),
      'list_chapters': (file: 'chapter_read_executor.dart', method: 'listChapters'),
      'search_in_chapters': (file: 'chapter_read_executor.dart', method: 'searchInChapters'),
      'create_chapter': (file: 'chapter_write_executor.dart', method: 'createChapter'),
      'update_chapter_content': (file: 'chapter_write_executor.dart', method: 'updateChapterContent'),
      'rewrite_chapter': (file: 'chapter_write_executor.dart', method: 'rewriteChapterContent'),
      'delete_chapter': (file: 'chapter_write_executor.dart', method: 'deleteChapter'),
      'list_characters': (file: 'character_executor.dart', method: 'listCharacters'),
      'update_character': (file: 'character_executor.dart', method: 'updateCharacter'),
      'create_character': (file: 'character_executor.dart', method: 'createCharacter'),
      'delete_character': (file: 'character_executor.dart', method: 'deleteCharacter'),
      'update_background_setting': (file: 'outline_executor.dart', method: 'updateBackgroundSetting'),
      'update_outline': (file: 'outline_executor.dart', method: 'updateOutline'),
      'write_outline': (file: 'outline_executor.dart', method: 'writeOutline'),
      'get_outline': (file: 'outline_executor.dart', method: 'getOutline'),
      'list_prompt_tags': (file: 'prompt_tag_executor.dart', method: 'listPromptTags'),
      'get_prompt_tag': (file: 'prompt_tag_executor.dart', method: 'getPromptTag'),
      'save_prompt_tag': (file: 'prompt_tag_executor.dart', method: 'savePromptTag'),
      'delete_prompt_tag': (file: 'prompt_tag_executor.dart', method: 'deletePromptTag'),
      'set_novel_cover': (file: 'novel_navigation_executor.dart', method: 'setNovelCover'),
    };

    /// 执行端接受、但 schema **有意不声明** 的字段。
    /// 白名单必须小且每项有理由；新增条目请补充注释。
    const intentionallyUndeclared = <String, Set<String>>{
      // description 是 appearanceFeatures 的旧用法别名，
      // 执行端做兜底（appearanceFeatures ?? description ?? ...）。
      // schema 不暴露，避免引导模型在 description 与 appearanceFeatures 间二选一。
      'create_character': {'description'},
      'update_character': {'description'},
    };

    /// 读取子执行器源码并按方法签名切片。
    /// 返回 {methodName: methodBody}，键不含前导下划线（与 toolMethodMap 对齐）。
    Map<String, String> _resolveExecutorMethodBodies(String source) {
      // 子执行器方法签名：Future<String> methodName( ... )
      // 不要求前导下划线；方法按 public 命名。
      final sigPattern = RegExp(r'Future<String>\s+(\w+)\s*\(');
      final sigs = sigPattern.allMatches(source).toList();

      final bodies = <String, String>{};
      for (var i = 0; i < sigs.length; i++) {
        final name = sigs[i].group(1)!;
        // 跳过 Dart 内置/库关键字方法名（例如 builder 之类），但匹配的列表很短。
        final start = sigs[i].end;
        // 切片到下一个方法签名（或文件末尾），不处理嵌套大括号
        // —— 字段提取正则只看 parser.xxx('...')，跨方法切片不影响结果。
        final end = i + 1 < sigs.length ? sigs[i + 1].start : source.length;
        bodies[name] = source.substring(start, end);
      }
      return bodies;
    }

    /// 从方法体中提取所有 parser.xxx('field') 的字段名集合。
    Set<String> _parsedFields(String body) {
      final re = RegExp(r"parser\.\w+\(\s*'([^']+)'");
      return re.allMatches(body).map((m) => m.group(1)!).toSet();
    }

    test('每个执行端读取的字段都在 schema 中声明（防 A 类 bug）', () {
      for (final entry in toolMethodMap.entries) {
        final toolName = entry.key;
        final file = entry.value.file;
        final methodName = entry.value.method;
        final executorPath =
            'lib/services/novel_agent/tool_executor/$file';
        final src = File(executorPath).readAsStringSync();
        final bodies = _resolveExecutorMethodBodies(src);

        final body = bodies[methodName];
        expect(body, isNotNull,
            reason: '执行端找不到方法 $methodName（工具 $toolName @ $file）—— '
                '若方法被重命名，请同步更新 toolMethodMap');

        var fields = _parsedFields(body!);
        fields = fields.difference(intentionallyUndeclared[toolName] ?? const {});

        final schemaProps = (AgentTools.findTool(toolName)!
                ['function']['parameters']['properties']
            as Map<String, dynamic>).keys.toSet();

        final missing = fields.difference(schemaProps);
        expect(missing, isEmpty,
            reason: '$toolName：执行端读取了字段 $missing，但 schema 未声明。'
                '若该字段是有意保留的兜底/兼容字段，请加到 intentionallyUndeclared 并附注释');
      }
    });

    test('每个 schema 声明的字段都被执行端读取（防 B 类 bug）', () {
      for (final entry in toolMethodMap.entries) {
        final toolName = entry.key;
        final file = entry.value.file;
        final methodName = entry.value.method;
        final executorPath =
            'lib/services/novel_agent/tool_executor/$file';
        final src = File(executorPath).readAsStringSync();
        final bodies = _resolveExecutorMethodBodies(src);

        final body = bodies[methodName];
        expect(body, isNotNull,
            reason: '执行端找不到方法 $methodName（工具 $toolName @ $file）');

        final fields = _parsedFields(body!);

        final schemaProps = (AgentTools.findTool(toolName)!
                ['function']['parameters']['properties']
            as Map<String, dynamic>).keys.toSet();

        final unused = schemaProps.difference(fields);
        expect(unused, isEmpty,
            reason: '$toolName：schema 声明了字段 $unused，但执行端未读取。'
                '要么删除 schema 字段，要么补上 parser.xxx(\'$unused\')');
      }
    });
  });

  group('AgentTools.findTool', () {
    test('找到存在的工具', () {
      final tool = AgentTools.findTool('list_novels');
      expect(tool, isNotNull);
      expect(tool!['function']['name'], 'list_novels');
    });

    test('找到新增的 select_novel', () {
      final tool = AgentTools.findTool('select_novel');
      expect(tool, isNotNull);
      expect(tool!['function']['name'], 'select_novel');
    });

    test('找不到不存在的工具 → 返回 null', () {
      final tool = AgentTools.findTool('non_existent_tool');
      expect(tool, isNull);
    });

    test('所有工具都能被 findTool 找到', () {
      final names =
          AgentTools.allTools.map((t) => t['function']['name'] as String).toList();
      expect(names, isNotEmpty);
      for (final name in names) {
        expect(AgentTools.findTool(name), isNotNull,
            reason: 'findTool("$name") 应该能找到');
      }
    });
  });

  group('AgentTools — 工具 JSON 序列化兼容性', () {
    test('每个工具定义都能被 jsonEncode 序列化', () {
      for (final tool in AgentTools.allTools) {
        expect(
          () => jsonEncode(tool),
          returnsNormally,
          reason: '${tool['function']['name']} 无法序列化为 JSON',
        );
      }
    });

    test('序列化后能被反序列化回来', () {
      for (final tool in AgentTools.allTools) {
        final json = jsonEncode(tool);
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        expect(decoded['function']['name'],
            tool['function']['name']);
      }
    });
  });
}
