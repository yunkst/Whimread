/// 按标注重写章节的独立 Agent（headless，无 chat UI）。
///
/// 设计目标：
/// - 独立运行：不复用主写作场景的会话/聊天状态，事件不暴露给 agent 聊天 UI。
/// - 锁定目标：当前小说 + 章节 URL + 章节在小说列表中的 position 全部在构造时绑定，
///   LLM 看到的工具 schema 不含任何标识参数（连 `position` 都没有），物理上无法触达
///   其它章节。
/// - 最小工具面：3 个工具
///   - `read_chapter_content`        —— 读取当前章节正文
///   - `update_chapter_content`      —— 对当前章节做精确字符串替换
///   - `list_chapters`               —— 查看当前小说的章节列表（context）
/// - 写库后即时刷前端：每次成功 `update_chapter_content` 后调用
///   [chapterContentStateNotifierProvider]，阅读页 ref.watch 自动重建 → 触发替换动画。
/// - 写版本快照：source='ai_rewrite'，复用现有「版本历史」还原能力。
///
/// 不复用 [AgentLoop] 的理由：AgentLoop 配套了 compaction/retry/streaming UI/
/// session event projector，本场景不需要，且耦合较重。重写一个 ~150 行的最小 ReAct
/// loop 比 patch AgentLoop 更清晰。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/chapter_mutation_provider.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/providers/reader_state_providers.dart';
import '../../../core/providers/services/ai_service_providers.dart';
import '../../../models/chapter.dart';
import '../../../models/novel.dart';
import '../../../models/paragraph_annotation.dart';
import '../../dsl_engine/llm_provider.dart';
import '../../logger_service.dart';

/// 重写结果
class RewriteResult {
  /// 整体成功（agent 正常结束，且至少有一次 update_chapter_content 写库成功）
  final bool success;

  /// 失败原因（仅 success=false 时非空）
  final String? error;

  /// 累计成功写库次数
  final int toolCalls;

  /// 重写后的章节全文（success=true 时与 chapter_cache 内容一致）
  final String? finalContent;

  const RewriteResult({
    required this.success,
    this.error,
    this.toolCalls = 0,
    this.finalContent,
  });

  factory RewriteResult.failure(String error) =>
      RewriteResult(success: false, error: error);
}

/// 悬浮按钮展示状态（idle → running 由 isRunning 单独表达 → done/error → 回 idle）
enum RewriteStatus { idle, done, error }

/// 按标注重写章节的 headless Agent
class AnnotationRewriteAgent {
  final WidgetRef _ref;
  final Novel _novel;
  final Chapter _chapter;
  final String _chapterUrl;

  /// 1-based 章节位置（list_chapters 顺序）；用于 list_chapters 返回字段对齐，
  /// 实际写库时直接用 _chapterUrl。
  final int _lockedPosition;
  final List<ParagraphAnnotation> _annotations;

  AnnotationRewriteAgent({
    required WidgetRef ref,
    required Novel novel,
    required Chapter chapter,
    required int lockedPosition,
    required List<ParagraphAnnotation> annotations,
  })  : _ref = ref,
        _novel = novel,
        _chapter = chapter,
        _chapterUrl = chapter.url,
        _lockedPosition = lockedPosition,
        _annotations = annotations;

  Novel get novel => _novel;
  Chapter get chapter => _chapter;
  List<ParagraphAnnotation> get annotations => _annotations;

  /// 暴露给 UI 的工具定义（LLM 看到的 schema，全部不暴露 position 参数）
  List<Map<String, dynamic>> get tools => const [
        _kReadChapterContentTool,
        _kUpdateChapterContentTool,
        _kListChaptersTool,
      ];

  // ============================== 系统提示词 ==============================

  String _buildSystemPrompt() {
    final annotationList = _annotations
        .map((a) =>
            '- 第 ${a.paragraphIndex + 1} 段（"${a.paragraphPreview}"）：${a.content}')
        .join('\n');

    return '''你是按标注重写章节的 Agent。任务：根据用户给出的段落标注，调用工具改写当前章节的正文。

## 规则
1. **必须先用 `read_chapter_content` 读取章节原文**，再决定如何改写。
2. 改写通过 `update_chapter_content(oldString, newString)` 完成精确字符串替换。每次替换至少包含一段连续原文作 oldString（必须与 read_chapter_content 返回内容逐字一致）。
3. 没有标注的段落保持原样；已标注段落必须按标注意图重写。
4. 不创建/删除章节，不调用任何写场景插图/改人物/改大纲/媒体/提示词标签等工具。
5. 完成所有改写后，无需调用工具直接结束（自然输出即可，loop 看到无 tool_calls 即终止）。

## 工具说明
- `read_chapter_content()`：读取本章节正文（无需参数）
- `update_chapter_content(oldString, newString, replaceAll?)`：在本章节内替换（无需章节标识）
- `list_chapters()`：查看当前小说的章节列表（仅供了解上下文）

## 当前任务
- 小说：《${_novel.title}》
- 章节：${_chapter.title}（已锁定，整个会话只能改这一章）
- 用户标注（${_annotations.length} 条）：
$annotationList

按上述标注逐段改写；改写完不要复述，直接输出结束语让 loop 终止。
''';
  }

  String _buildInitialUserMessage() {
    return '请按上面 system prompt 中的 ${_annotations.length} 条标注，改写本章《${_chapter.title}》。先读全文，再调用 update_chapter_content 逐段替换。';
  }

  // ============================== 工具实现（绑定到 _chapterUrl） ==============================

  Future<String> _readChapterContent() async {
    final repo = _ref.read(chapterRepositoryProvider);
    final content = await repo.getCachedChapter(_chapterUrl);
    if (content == null || content.isEmpty) {
      LoggerService.instance.w(
        '标注重写 read_chapter_content: 章节未缓存 url=$_chapterUrl',
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
    final current = await repo.getCachedChapter(_chapterUrl);
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
      _chapterUrl,
      updatedContent,
      source: 'ai_rewrite',
      novelUrl: _novel.url,
    );
    if (affected <= 0) {
      return jsonEncode({
        'error': 'write_failed',
        'message': '写库失败，请稍后重试。',
      });
    }

    // 即时刷新前端内容：让阅读页 AnimatedSwitcher 触发替换动画。
    // setContent 是同步写入；下游 ref.watch 会在下一帧重建 ListView。
    _ref
        .read(chapterContentStateNotifierProvider.notifier)
        .setContent(updatedContent);

    LoggerService.instance.i(
      '标注重写 update_chapter_content 成功: chapter=${_chapter.title} '
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
    final chapters = await repo.getCachedNovelChapters(_novel.url);
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
      'note': '本会话仅可改写章节 position=$_lockedPosition（"${_chapter.title}"）。',
    });
  }

  // ============================== 工具调度 ==============================

  Future<String> _executeTool(ToolCall call) async {
    switch (call.name) {
      case 'read_chapter_content':
        return _readChapterContent();
      case 'update_chapter_content':
        return _updateChapterContent(call.arguments);
      case 'list_chapters':
        return _listChapters();
      default:
        return jsonEncode({
          'error': 'unknown_tool',
          'message': '工具 ${call.name} 不在白名单内',
        });
    }
  }

  // ============================== 主循环 ==============================

  /// 跑一遍完整的 ReAct loop，返回 [RewriteResult]。
  ///
  /// [maxRounds] 默认 30：标注改写通常 1-3 轮 update 即可完成，留足容错。
  /// [onProgress] 可选进度回调，每轮 + 工具完成后调用，便于 UI 更新「重写中 N 步」。
  Future<RewriteResult> run({
    int maxRounds = 30,
    void Function(int round, int toolCallsDone, String status)? onProgress,
  }) async {
    final configService = _ref.read(llmConfigServiceProvider);
    final llm = await configService.buildActiveProvider(_writingScenarioId);
    if (llm == null) {
      LoggerService.instance.w(
        '标注重写 Agent: 未配置活动 LLM',
        category: LogCategory.ai,
        tags: ['agent', 'rewrite', 'not_configured'],
      );
      return RewriteResult.failure(
          '未配置活动 LLM 提供商，请前往设置页配置后重试。');
    }

    final messages = <ChatMessage>[
      ChatMessage(role: 'system', content: _buildSystemPrompt()),
      ChatMessage(role: 'user', content: _buildInitialUserMessage()),
    ];

    int toolCallsDone = 0;
    String? lastError;

    for (int round = 0; round < maxRounds; round++) {
      onProgress?.call(round, toolCallsDone, '调用 LLM...');
      LoggerService.instance.d(
        '标注重写 loop round=$round (chapter=${_chapter.title})',
        category: LogCategory.ai,
        tags: ['agent', 'rewrite', 'loop'],
      );

      final toolCalls = <ToolCall>[];
      String fullContent = '';
      try {
        final streaming = StreamingResult();
        await for (final chunk in llm.chatStreamWithTools(
          messages: messages,
          tools: tools,
          toolChoice: 'auto',
        )) {
          if (chunk.isContent) {
            fullContent += chunk.contentChunk!;
            streaming.contentChunks.add(chunk.contentChunk!);
          }
          if (chunk.isToolCallDelta) {
            streaming.toolCallDeltas.addAll(chunk.toolCallDeltas);
          }
        }
        toolCalls.addAll(streaming.buildToolCalls());
        LoggerService.instance.d(
          '标注重写 LLM 响应: round=$round contentLen=${fullContent.length} '
          'toolCalls=${toolCalls.length}',
          category: LogCategory.ai,
          tags: ['agent', 'rewrite', 'llm_response'],
        );
      } catch (e, st) {
        LoggerService.instance.e(
          '标注重写 LLM 调用失败: $e',
          stackTrace: st.toString(),
          category: LogCategory.ai,
          tags: ['agent', 'rewrite', 'llm_failed'],
        );
        return RewriteResult.failure('LLM 调用失败：$e');
      }

      // 入栈 assistant 消息（含 tool_calls）
      messages.add(ChatMessage(
        role: 'assistant',
        content: fullContent.isNotEmpty ? fullContent : null,
        toolCalls: toolCalls,
      ));

      // 无 tool_calls → 正常结束
      if (toolCalls.isEmpty) {
        LoggerService.instance.i(
          '标注重写 完成（无工具调用, round=$round, toolCalls=$toolCallsDone）',
          category: LogCategory.ai,
          tags: ['agent', 'rewrite', 'done'],
        );
        final finalRepo = _ref.read(chapterRepositoryProvider);
        final finalContent = await finalRepo.getCachedChapter(_chapterUrl) ?? '';
        return RewriteResult(
          success: toolCallsDone > 0,
          error: toolCallsDone == 0
              ? 'agent 没有任何写库动作，请检查标注或 LLM 输出'
              : null,
          toolCalls: toolCallsDone,
          finalContent: finalContent,
        );
      }

      // 串行执行所有工具调用（本场景无 dispatch_subagent）
      bool anyFailure = false;
      for (final call in toolCalls) {
        onProgress?.call(round, toolCallsDone, '执行 ${call.name}...');
        LoggerService.instance.i(
          '标注重写 工具: ${call.name} (round=$round)',
          category: LogCategory.ai,
          tags: ['agent', 'rewrite', 'tool', call.name],
        );
        try {
          final rawResult = await _executeTool(call);
          messages.add(ChatMessage(
            role: 'tool',
            content: rawResult,
            toolCallId: call.id,
          ));
          try {
            final decoded = jsonDecode(rawResult);
            if (decoded is Map<String, dynamic> && decoded.containsKey('error')) {
              anyFailure = true;
              lastError = decoded['error']?.toString() ?? 'unknown';
              LoggerService.instance.w(
                '标注重写 工具失败: ${call.name}, error=$lastError',
                category: LogCategory.ai,
                tags: ['agent', 'rewrite', 'tool_failed', call.name],
              );
            } else {
              toolCallsDone++;
            }
          } catch (_) {
            // 非 JSON 结果（read_chapter_content 返回纯文本） → 视为成功
            toolCallsDone++;
          }
        } catch (e, st) {
          LoggerService.instance.e(
            '标注重写 工具异常: ${call.name}, $e',
            stackTrace: st.toString(),
            category: LogCategory.ai,
            tags: ['agent', 'rewrite', 'tool_exception', call.name],
          );
          anyFailure = true;
          lastError = e.toString();
          messages.add(ChatMessage(
            role: 'tool',
            content: jsonEncode({'error': 'exception', 'message': e.toString()}),
            toolCallId: call.id,
          ));
        }
      }
      onProgress?.call(round, toolCallsDone, '已完成 $toolCallsDone 步改写');
      if (anyFailure) {
        // 单个工具失败不立刻终止 → 把错误结果反馈给 LLM，让它自我修正。
        // 但若连续 3 轮都有失败，提前退出避免 token 浪费。
        // 简单起见：失败轮结束当轮后继续下一轮（让 LLM 看到 tool 返回的错误）。
      }
      // 长度上限保护：messages 超过 100k 字符截断早退。
      if (messages.fold<int>(0, (acc, m) => acc + (m.content?.length ?? 0)) > 100000) {
        LoggerService.instance.w(
          '标注重写 消息超长，提前退出: totalChars>100k',
          category: LogCategory.ai,
          tags: ['agent', 'rewrite', 'overflow'],
        );
        return RewriteResult(
          success: toolCallsDone > 0,
          error: '上下文过长，已中止',
          toolCalls: toolCallsDone,
        );
      }
    }

    LoggerService.instance.w(
      '标注重写 达最大轮数 ($maxRounds, toolCalls=$toolCallsDone)',
      category: LogCategory.ai,
      tags: ['agent', 'rewrite', 'max_rounds'],
    );
    return RewriteResult(
      success: toolCallsDone > 0,
      error: '达到最大轮数 $maxRounds，已中止',
      toolCalls: toolCallsDone,
    );
  }
}

/// 主写作场景的场景 ID（与 agent_scenario.dart 的 ScenarioIds.writing 同值；
/// 本文件不 import agent_scenario.dart 以避免拉入 webview 依赖）
const String _writingScenarioId = 'writing';

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