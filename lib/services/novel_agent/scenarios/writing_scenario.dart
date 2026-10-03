/// 写作场景 — 封装现有的小说写作 Agent 能力
///
/// 将 AgentTools + ToolExecutor + AgentSystemPrompt 统一封装为
/// AgentScenario 实现，不改变任何行为。
///
/// 任务 7：在工具执行入口加 `dispatch_subagent` 委托分支，把 LLM 派出的
/// 子任务转交给 SubagentRunner（共享 NovelAgentService 事件流）。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/core/providers/ask_user_providers.dart';
import 'package:novel_app/core/providers/chat_session_providers.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/subagent_providers.dart';
import 'package:novel_app/services/logger_service.dart';

import '../agent_scenario.dart';
import '../agent_tools.dart';
import '../agent_system_prompt.dart';
import '../ask_user_registry.dart';
import '../novel_agent_service.dart';
import '../tool_arg_parser.dart';
import '../tool_executor.dart';

class WritingScenario with AgentScenarioCleanupMixin, AgentMemoryPatchMixin
    implements AgentScenario {
  final Ref _ref;
  late final ToolExecutor _executor = ToolExecutor(_ref);

  /// ask_user 等待用户作答的最长时间
  ///
  /// 兜底阀门：正常路径靠用户作答 / 取消令牌唤醒；超时时按 timeout 语义
  /// 放行，让 LLM 自行决策继续，避免极端情况下 run 永久悬挂。
  /// 可注入缩短（测试用），生产走默认 10 分钟。
  final Duration askUserTimeout;

  /// 缓存当前场景上下文，供 executeTool 内部使用
  AgentScenarioContext? _currentContext;

  WritingScenario(this._ref, {this.askUserTimeout = const Duration(minutes: 10)});

  @override
  String get id => ScenarioIds.writing;

  @override
  String get displayName => '小说写作助手';

  @override
  List<Map<String, dynamic>> get tools =>
      [...AgentTools.allTools, patchMemoryToolDefinition];

  @override
  String buildSystemPrompt(AgentScenarioContext context) {
    _currentContext = context;
    // 用户阅读上下文、当前工作小说 改由 NovelAgentService 在 user message 头部注入，
    // 本方法只负责相对静态的"身份 + 工作原则 + 经验记忆"。
    return AgentSystemPrompt.build(
      memories: cachedMemories,
    );
  }

  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    LoggerService.instance.d(
      'WritingScenario 执行工具: $name',
      category: LogCategory.ai,
      tags: ['agent', 'scenario', 'writing', name],
    );
    // patch_memory 由场景自行处理（复用 mixin 的统一工具执行器）
    if (name == 'patch_memory') {
      return executePatchMemoryTool(args, logTag: 'writing');
    }
    // ask_user：阻塞式向用户提问（单选 / 多选 / 自由输入）。
    // register 挂起项并 await，AgentLoop 在此暂停；用户经聊天 UI 作答后
    // Completer 完成，答案作为 tool result 回灌 LLM 继续本轮。
    if (name == 'ask_user') {
      return _executeAskUser(args, toolCallId);
    }
    // dispatch_subagent：委托给 SubagentRunner（任务 7）
    // 事件回流通过 SubagentRunner 内部 agentService.events.add 发到全局流，
    // 本方法不负责转发。
    //
    // 任务 8 #6 key 对齐：parentSessionId 必须与 SubagentToolCard 反查侧
    // 用的 key 一致——统一为该场景 scoped 的
    // `currentChatSessionIdProvider(scenarioId).toString()`。
    // 之前用 scenarioId（String）会导致 SubagentRegistry 的
    // `getByToolCallId(parentSessionId, ...)` 和
    // `cancelAllForSession(parentSessionId)` 找不到 run（两侧 key 不匹配）。
    if (name == 'dispatch_subagent') {
      try {
        final parentSessionId =
            _ref.read(currentChatSessionIdProvider(ScenarioIds.writing))
                    ?.toString() ??
                'unknown';
        return await _ref.read(subagentRunnerProvider).dispatch(
              parentSessionId: parentSessionId,
              task: (args['task'] as String?) ?? '',
              allowedTools: ((args['allowed_tools'] as List?) ?? const [])
                  .map((e) => e.toString())
                  .toList(),
              parentToolCallId: toolCallId ?? '',
              parentCurrentNovelId: _currentContext?.currentNovelId,
            );
      } catch (e) {
        // SubagentRunner.dispatch 头部 try-catch 会 rethrow（如 _waitForSlot 的
        // TimeoutException），若不在此处转 error JSON，异常会沿
        // AgentLoop._executeSingleTool 上抛到 run 外层 catch，被
        // _isTransientNetworkError 判为瞬态网络错误触发 round 整体重试，
        // LLM 永远收不到 dispatch 失败的 error JSON。
        // 改为返回 error JSON 字符串，AgentLoop 据 `error` 字段判 toolSuccess=false
        // 并把结果作为 tool result 回灌 LLM，让 LLM 决策换路径或告知用户。
        return jsonEncode({
          'error': 'subagent_dispatch_failed',
          'message': '子 Agent 派发失败: $e',
        });
      }
    }
    // select_novel / create_novel 需要同步更新 _currentContext，
    // 确保同一 LLM 响应中后续工具调用能作用于新小说
    if (name == 'select_novel' || name == 'create_novel') {
      final result = await _executor.execute(name, args, scenarioContext: _currentContext);
      _syncCurrentContext(result);
      return result;
    }
    // 其余工具（含 create_chapter / update_chapter_content 的流式进度）透传 onProgress
    return await _executor.execute(
      name,
      args,
      scenarioContext: _currentContext,
      onProgress: onProgress,
    );
  }

  /// 写作场景无需"无 tool_call 注入"，直接结束
  @override
  Future<String?> onNoToolCalls(List<ChatMessage> messages) async => null;

  /// ask_user 工具执行：校验参数 → 注册挂起提问 → await 用户作答
  ///
  /// 阻塞语义与 SubagentRunner.dispatch 一致（同一回合内挂起整个 run），
  /// 区别是唤醒方是 UI（ScenarioSession.answerAskUser）而非子 Agent。
  Future<String> _executeAskUser(
    Map<String, dynamic> args,
    String? toolCallId,
  ) async {
    final parser = ToolArgParser(args);
    final (question, questionErr) = parser.requireString('question');
    if (questionErr != null) return questionErr;
    // options 宽松解析：LLM 可能传字符串，也可能传 {label, description}
    // 对象（见 normalizeAskUserOption），统一归一为短语列表做校验；
    // 原始参数不动——UI 渲染直接读 call.arguments（含说明文字）。
    final rawOptions = args['options'];
    var options = const <String>[];
    if (rawOptions != null) {
      if (rawOptions is! List) {
        return jsonEncode({
          'error': 'param_type_error',
          'message': '参数 "options" 类型错误：期望 array，实际 '
              '${rawOptions.runtimeType}',
          'param': 'options',
        });
      }
      options = rawOptions
          .map((e) => normalizeAskUserOption(e))
          .map((o) => o.label)
          .where((label) => label.isNotEmpty)
          .toList();
    }
    final (multiSelectRaw, multiSelectErr) = parser.optionalBool('multi_select');
    if (multiSelectErr != null) return multiSelectErr;
    final (freeTextRaw, freeTextErr) = parser.optionalBool('allow_free_text');
    if (freeTextErr != null) return freeTextErr;

    final multiSelect = multiSelectRaw ?? false;
    final allowFreeText = freeTextRaw ?? true;

    // 语义校验：不存在任何可作答途径时直接回错，让 LLM 自行修正参数后重问
    if (options.isEmpty && !allowFreeText) {
      return jsonEncode({
        'error': 'invalid_args',
        'message': 'ask_user 需要提供 options 候选，或设 allow_free_text=true '
            '允许用户自由输入，否则用户无从作答',
      });
    }
    if (multiSelect && options.isEmpty) {
      return jsonEncode({
        'error': 'invalid_args',
        'message': 'multi_select=true 时必须提供 options（多选基于候选进行）',
      });
    }
    if (options.length > 8) {
      return jsonEncode({
        'error': 'invalid_args',
        'message': 'options 最多 8 个（当前 ${options.length} 个），'
            '请精简为最关键的候选',
      });
    }

    // toolCallId 理论上恒有（AgentLoop._executeSingleTool 传 call.id），
    // 兜底生成唯一值，避免与同场景其他挂起项键冲突。
    final callId = toolCallId ??
        'ask_${DateTime.now().microsecondsSinceEpoch.toString()}';
    const scenarioId = ScenarioIds.writing;
    final registry = _ref.read(askUserRegistryProvider);
    final entry = registry.register(
      scenarioId: scenarioId,
      toolCallId: callId,
      question: question,
      options: options,
      multiSelect: multiSelect,
      allowFreeText: allowFreeText,
    );

    // 取消唤醒：用户点停止 / 会话销毁 → cancelFor → token.cancel → 回调放行。
    // register 在 token 已取消时会立即执行回调，这里 await 立刻返回 cancelled。
    final token =
        _ref.read(novelAgentServiceProvider).tokenFor(scenarioId);
    final unregisterCancel =
        token?.register(() => entry.complete(const AskUserAnswer.cancelled()));

    LoggerService.instance.i(
      'ask_user 挂起等待用户作答 (toolCallId=$callId, options=${options.length}, '
      'multiSelect=$multiSelect, allowFreeText=$allowFreeText)',
      category: LogCategory.ai,
      tags: ['agent', 'writing', 'ask_user', 'await', scenarioId],
    );

    final AskUserAnswer answer;
    try {
      answer = await entry.future.timeout(
        askUserTimeout,
        onTimeout: () => const AskUserAnswer.timeout(),
      );
    } finally {
      unregisterCancel?.call();
      registry.remove(scenarioId, callId);
    }

    if (!answer.isAnswered) {
      final timedOut = answer.status == AskUserAnswerStatus.timeout;
      LoggerService.instance.i(
        'ask_user 未获作答 (status=${answer.status.name}, toolCallId=$callId)',
        category: LogCategory.ai,
        tags: ['agent', 'writing', 'ask_user', answer.status.name, scenarioId],
      );
      return jsonEncode({
        'success': true,
        'status': answer.status.name,
        'question': question,
        'note': timedOut
            ? '用户超时未回答，请基于现有信息自行决策继续任务，并在汇报中说明'
            : '本轮运行已被用户取消',
      });
    }

    LoggerService.instance.i(
      'ask_user 收到作答 (toolCallId=$callId, selected=${answer.selected}, '
      'freeText=${answer.freeText != null})',
      category: LogCategory.ai,
      tags: ['agent', 'writing', 'ask_user', 'answered', scenarioId],
    );
    return jsonEncode({
      'success': true,
      'question': question,
      if (answer.selected.isNotEmpty) 'selected': answer.selected,
      if (answer.freeText != null) 'free_text': answer.freeText,
      'note': '用户已回答，请据此继续任务',
    });
  }

  /// 从 select_novel 工具结果中提取小说信息并同步到 _currentContext
  void _syncCurrentContext(String result) {
    try {
      final parsed = jsonDecode(result) as Map<String, dynamic>;
      if (parsed['success'] == true && parsed['novelId'] != null) {
        _currentContext = AgentScenarioContext(
          scenarioId: ScenarioIds.writing,
          readingContext: _currentContext?.readingContext,
          currentUrl: _currentContext?.currentUrl,
          currentNovelId: parsed['novelId'] as int,
          currentNovelTitle: parsed['title'] as String?,
        );
      }
    } catch (e) {
      // 解析失败，保持当前 context 不变
      LoggerService.instance.e(
        '解析 select_novel 结果失败: $result',
        category: LogCategory.ai,
        tags: ['agent', 'writing', 'sync_context', 'parse_failed'],
      );
    }
  }

  /// 记忆缓存（由 AgentMemoryPatchMixin 提供，本类复用 mixin 的实现）
  @override
  Future<List<String>> getMemories() async {
    try {
      final repo = _ref.read(agentMemoryRepositoryProvider);
      return await loadMemories(repo);
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '加载写作记忆失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.ai,
        tags: ['agent', 'writing', 'get_memories', 'failed'],
      );
      rethrow;
    }
  }

  @override
  Future<MemoryPatchResult> patchMemory(int? index, String newText) async {
    final repo = _ref.read(agentMemoryRepositoryProvider);
    return patchMemoryImpl(repo, index, newText);
  }
}
