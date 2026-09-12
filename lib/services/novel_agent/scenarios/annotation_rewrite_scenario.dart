/// 按标注重写章节场景 — 阅读页段落标注驱动的局部改写 Agent
///
/// 从早期 headless 版 AnnotationRewriteAgent 演化为正式 AgentScenario，
/// 由 NovelAgentService → AgentLoop 驱动，改写过程（读章/替换/思考）通过
/// 全局事件流进入 ScenarioSession，可在 agent 对话窗口完整查看。
///
/// 锁定设计（与 headless 版一致）：
/// - 目标绑定：小说 URL + 章节 URL + 章节列表 position 全部来自构造时注入的
///   [AnnotationRewriteTarget]（经 AgentScenarioContext.rewriteTarget 传递），
///   LLM 看到的工具 schema 不含任何标识参数，物理上无法触达其它章节。
/// - 最小工具面：3 个工具
///   - `read_chapter_content`   —— 读取当前章节正文
///   - `update_chapter_content` —— 对当前章节做精确字符串替换
///   - `list_chapters`          —— 查看当前小说的章节列表（context）
/// - 写库后即时刷前端：每次成功替换后调 [chapterContentStateNotifierProvider]，
///   阅读页 ref.watch 自动重建 → 触发段落级延迟揭示动画。
/// - 写版本快照：source='ai_rewrite'，复用「版本历史」还原能力。
/// - 成功 update 次数累计在 [successfulUpdateCount]，供会话层判定改写结果。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/chapter_mutation_provider.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/providers/reader_state_providers.dart';
import '../../logger_service.dart';
import '../agent_scenario.dart';

class AnnotationRewriteScenario
    with AgentScenarioCleanupMixin
    implements AgentScenario {
  final Ref _ref;
  final AnnotationRewriteTarget _target;

  AnnotationRewriteScenario(this._ref, this._target);

  @override
  String get id => ScenarioIds.annotationRewrite;

  @override
  String get displayName => '按标注重写';

  /// 本次运行中成功写库的 update_chapter_content 次数。
  /// ScenarioSession 在回合结束后据此生成 AnnotationRewriteOutcome。
  int successfulUpdateCount = 0;

  @override
  List<Map<String, dynamic>> get tools => const [
        _kReadChapterContentTool,
        _kUpdateChapterContentTool,
        _kListChaptersTool,
      ];

  // 标注重写场景不需要 patch_memory / 经验记忆 —— 显式禁用基类默认实现。
  @override
  Future<List<String>> getMemories() async => const [];

  @override
  Future<String?> onNoToolCalls(List<ChatMessage> messages) async => null;

  @override
  Future<MemoryPatchResult> patchMemory(int? index, String newText) async =>
      MemoryPatchResult.error('patch_memory 在当前场景不可用', const []);

  // ============================== 系统提示词 ==============================

  @override
  String buildSystemPrompt(AgentScenarioContext context) {
    final annotations = _target.annotations;
    final annotationList = annotations
        .map((a) =>
            '- 第 ${a.paragraphIndex + 1} 段（"${a.paragraphPreview}"）：${a.content}')
        .join('\n');

    return '''你是按标注重写章节的 Agent。用户在阅读时对若干段落写下了批注，这些批注表达的是用户对这一章的修改意图。你的任务：调用工具改写当前章节正文，让章节符合批注意图。

## 关键理解
- 批注不是"只改被标注的那一段"的指令。它往往牵动上下文：伏笔要提前埋、后文要跟着圆、节奏和章节走向可能需要调整。
- 你需要通读全章，判断批注意图波及的范围，然后一并修改受影响的段落（包括标注段本身、它的前后文、以及为保持连贯必须联动的其它段落）。
- 与批注无关、且不受改动影响的内容保持原样，不要为了改而改。

## 规则
1. **必须先用 `read_chapter_content` 读取章节原文**，再决定改写方案；需要了解全书的章节脉络时可用 `list_chapters`。
2. 改写通过 `update_chapter_content(oldString, newString)` 完成精确字符串替换。每次替换的 oldString 必须与 read_chapter_content 返回内容逐字一致，且包含完整的待改写段落（含换行）。
3. 多个不相邻的修改拆成多次替换调用，不要一次替换过大的范围。
4. 不创建/删除章节，不调用任何写场景插图/改人物/改大纲/媒体/提示词标签等工具。
5. 完成所有改写后，无需调用工具直接输出简短总结结束（loop 看到无 tool_calls 即终止）。

## 工具说明
- `read_chapter_content()`：读取本章节正文（无需参数）
- `update_chapter_content(oldString, newString, replaceAll?)`：在本章节内替换（无需章节标识）
- `list_chapters()`：查看当前小说的章节列表（仅供了解上下文）

## 当前任务
- 小说：《${_target.novelTitle}》
- 章节：${_target.chapterTitle}（已锁定，整个会话只能改这一章）
- 用户标注（${annotations.length} 条）：
$annotationList

先读全文，规划需要联动的修改范围，再逐段替换；完成后输出一句简短总结。
''';
  }

  // ============================== 工具实现（绑定到 target） ==============================

  Future<String> _readChapterContent() async {
    final repo = _ref.read(chapterRepositoryProvider);
    final content = await repo.getCachedChapter(_target.chapterUrl);
    if (content == null || content.isEmpty) {
      LoggerService.instance.w(
        '标注重写 read_chapter_content: 章节未缓存 url=${_target.chapterUrl}',
        category: LogCategory.ai,
        tags: ['agent', 'rewrite', 'read', 'not_cached'],
      );
      return jsonEncode({
        'error': 'not_cached',
        'message': '当前章节内容尚未缓存，请先在阅读页加载章节。',
      });
    }
    return content;
  }

  /// 精确字符串替换并写库（source='ai_rewrite'）。成功后即时刷新前端内容状态。
  Future<String> _updateChapterContent(Map<String, dynamic> args) async {
    final oldString = args['oldString'];
    final newString = args['newString'];
    final replaceAll = args['replaceAll'] == true;

    if (oldString is! String || oldString.isEmpty) {
      return jsonEncode({
        'error': 'invalid_args',
        'message': 'oldString 必须是非空字符串。',
      });
    }
    if (newString is! String) {
      return jsonEncode({
        'error': 'invalid_args',
        'message': 'newString 必须是字符串。',
      });
    }
    if (oldString == newString) {
      return jsonEncode({
        'error': 'no_change',
        'message': 'newString 与 oldString 相同，跳过。',
      });
    }

    final repo = _ref.read(chapterRepositoryProvider);
    final current = await repo.getCachedChapter(_target.chapterUrl);
    if (current == null || current.isEmpty) {
      return jsonEncode({
        'error': 'not_cached',
        'message': '当前章节内容尚未缓存。',
      });
    }

    String updatedContent;
    if (replaceAll) {
      if (!current.contains(oldString)) {
        return jsonEncode({
          'error': 'not_found',
          'message': 'oldString 在原文中未找到，无法替换。请先用 read_chapter_content 核对原文。',
        });
      }
      updatedContent = current.replaceAll(oldString, newString);
    } else {
      final occurrences = oldString.allMatches(current).length;
      if (occurrences == 0) {
        return jsonEncode({
          'error': 'not_found',
          'message': 'oldString 在原文中未找到，无法替换。请先用 read_chapter_content 核对原文。',
        });
      }
      if (occurrences > 1) {
        return jsonEncode({
          'error': 'ambiguous_match',
          'message': 'oldString 在原文中出现 $occurrences 次，请补更多上下文行让匹配唯一，或设 replaceAll=true。',
          'occurrences': occurrences,
        });
      }
      updatedContent = current.replaceFirst(oldString, newString);
    }

    // 写库：source='ai_rewrite' → 版本历史打 ai_rewrite 标签，支持还原。
    final mutation = _ref.read(chapterMutationProvider.notifier);
    final affected = await mutation.updateChapterContent(
      _target.chapterUrl,
      updatedContent,
      source: 'ai_rewrite',
      novelUrl: _target.novelUrl,
    );
    if (affected <= 0) {
      return jsonEncode({
        'error': 'write_failed',
        'message': '写库失败，请稍后重试。',
      });
    }

    // 即时刷新前端内容：让阅读页触发段落级延迟揭示动画。
    // setContent 是同步写入；下游 ref.watch 会在下一帧重建 ListView。
    _ref
        .read(chapterContentStateNotifierProvider.notifier)
        .setContent(updatedContent);
    successfulUpdateCount++;

    LoggerService.instance.i(
      '标注重写 update_chapter_content 成功: chapter=${_target.chapterTitle} '
      'oldLen=${oldString.length} newLen=${newString.length} '
      'replaceAll=$replaceAll affected=$affected',
      category: LogCategory.ai,
      tags: ['agent', 'rewrite', 'update'],
    );

    return jsonEncode({
      'success': true,
      'message': '已替换并写库。',
      'oldStringLength': oldString.length,
      'newStringLength': newString.length,
    });
  }

  /// list_chapters：当前小说的章节列表（agent 上下文用，不会被改写）
  Future<String> _listChapters() async {
    final repo = _ref.read(chapterRepositoryProvider);
    final chapters = await repo.getCachedNovelChapters(_target.novelUrl);
    final list = chapters.map((c) => {
          'position': c.chapterIndex != null
              ? (c.chapterIndex! + 1)
              : (chapters.indexOf(c) + 1),
          'title': c.title,
          'url': c.url,
          'isCached': c.isCached,
        }).toList();
    return jsonEncode({
      'chapters': list,
      'count': list.length,
      'note':
          '本会话仅可改写章节 position=${_target.lockedPosition}（"${_target.chapterTitle}"）。',
    });
  }

  // ============================== 工具调度 ==============================

  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    switch (name) {
      case 'read_chapter_content':
        return _readChapterContent();
      case 'update_chapter_content':
        return _updateChapterContent(args);
      case 'list_chapters':
        return _listChapters();
      default:
        return jsonEncode({
          'error': 'unknown_tool',
          'message': '工具 $name 不在白名单内',
        });
    }
  }
}

// ============================== 工具定义（LLM 可见 schema） ==============================

const Map<String, dynamic> _kReadChapterContentTool = {
  'type': 'function',
  'function': {
    'name': 'read_chapter_content',
    'description':
        '读取当前被锁定章节的完整正文内容。修改前必须先调用此工具了解当前内容。'
        '返回的是章节原文（可能含换行）。',
    'parameters': {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    },
  },
};

const Map<String, dynamic> _kUpdateChapterContentTool = {
  'type': 'function',
  'function': {
    'name': 'update_chapter_content',
    'description':
        '对当前被锁定章节的正文做精确字符串替换。'
        'oldString 必须是 read_chapter_content 返回内容中逐字一致的子串。'
        'oldString/newString 参数说明：\n'
        '- oldString：要被替换的原文片段（必须与 read_chapter_content 返回内容一致）\n'
        '- newString：替换后的内容（必须与 oldString 不同）\n'
        '- replaceAll：可选，默认 false。true 表示替换所有匹配；false 时若 oldString 在正文中出现多次会返回 ambiguous_match。\n'
        '失败情况：\n'
        '- oldString 找不到 → not_found\n'
        '- oldString 多处且未设 replaceAll=true → ambiguous_match\n'
        '成功后会立即刷新阅读页内容并保留版本快照（source=ai_rewrite，可走版本历史还原）。',
    'parameters': {
      'type': 'object',
      'properties': {
        'oldString': {
          'type': 'string',
          'description': '要被替换的原文片段',
        },
        'newString': {
          'type': 'string',
          'description': '替换后的内容',
        },
        'replaceAll': {
          'type': 'boolean',
          'description': '是否替换所有匹配（默认 false）',
        },
      },
      'required': ['oldString', 'newString'],
    },
  },
};

const Map<String, dynamic> _kListChaptersTool = {
  'type': 'function',
  'function': {
    'name': 'list_chapters',
    'description':
        '查看当前小说的所有章节目录（含 position、title、url、isCached）。'
        '注意：本会话已被锁定，只能改写单个章节——其它章节仅供了解上下文，不能修改。',
    'parameters': {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    },
  },
};
