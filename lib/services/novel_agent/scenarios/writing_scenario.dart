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

/// 番外创作指引（追加在通用 system prompt 之后，仅 writing 场景）。
///
/// 番外的定义与既有约定一致：独立于主线的迷你小说（有自己的章节列表与
/// 阅读体验，不入书架），挂载在锚点章下，可递归。创作直接在本对话内完成：
/// create_side_story 定位写入目标，save_side_story_chapter 落库；
/// currentNovel 全程保持宿主不变——读/搜/人物卡天然指宿主（查证通道），
/// 写番外走显式工具（写通道），读写硬分离。
const String _sideStoryGuide = '''
## 番外创作（在本对话内直接完成）
- 番外 = 独立于主线的支线故事：有自己的章节列表与完整阅读体验，不混入主线正文，也不出现在书架；挂载在某一章下，番外章节还能再挂番外。
- 用户表达番外意图（如「给这章写个番外」「写个女主与闺蜜的过往支线」「某角色的后续故事」）时的流程：
  1. **查证主线事实**（防写歪的关键步骤）：涉及人物在锚点章之外有戏份时，用 read_chapter_content / search_in_chapters 查证口癖、旧伤、关系变化、时间点；人物卡用 list_characters。凡引用主线既有事实，先查证再落笔。
  2. 调用 `create_side_story(title, requirement)` 建立番外：锚点自动取用户当前正在阅读的章节；不在阅读态时请用户指定章节（你传 anchorChapterPosition）或引导其打开目标章节。requirement 忠实转述用户需求（用于幂等找回）。续写已有番外同样先调本工具定位（同锚点同需求幂等复用，不会重复建）。
  3. 逐章创作（一章一轮，写完即存）：在**你的回复中直接写出该章完整正文**（1500~3000 字），然后调用 `save_side_story_chapter(position, title, content)`，content 与回复正文**逐字一致**。position 从 1 连续递增，用结果里的 sideStoryChapterCount 校准。章尾留推进感，人物细节前后一致。
- **调整已有番外**（如「把番外第 2 章的师父名字改掉」「这段对话润色一下」）：不要凭记忆整章重写。先 `list_side_stories` 拿 sideStoryId → `list_chapters(sideStoryId)` 看章节清单 → `read_chapter_content(position, sideStoryId)` 核对原文 → `update_chapter_content(position, oldString, newString, sideStoryId)` 打段落级补丁；只改个别段落用这条路径，整章重写才用 `save_side_story_chapter` 覆盖。
- **工具分工**：`save_chapter` 写正篇整章、`save_side_story_chapter` 写番外整章，二者不会混淆；read / list_chapters / update_chapter_content 默认作用于当前小说（宿主），传可选参数 `sideStoryId` 后定位到对应番外（只能越界到当前小说自己的番外，别的书打不进去）——创作与调整番外过程中随时可查证主线。
- 用户需求与主线设定冲突时，以用户需求为准。''';

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
    return '${AgentSystemPrompt.build(
      memories: cachedMemories,
    )}\n\n$_sideStoryGuide';
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
    // create_side_story：建番外后同步写入目标到 _currentContext，
    // 确保同一 LLM 响应中后续的 save_side_story_chapter 能立刻定位番外
    // （跨回合由 session 的 ToolCallEndEvent 接线注入，两处同步同 select_novel 模式）
    if (name == 'create_side_story') {
      final result = await _executor.execute(name, args, scenarioContext: _currentContext);
      _syncSideStoryTarget(result);
      return result;
    }
    // select_novel / create_novel 需要同步更新 _currentContext，
    // 确保同一 LLM 响应中后续工具调用能作用于新小说
    if (name == 'select_novel' || name == 'create_novel') {
      final result = await _executor.execute(name, args, scenarioContext: _currentContext);
      _syncCurrentContext(result);
      return result;
    }
    // 其余工具（含 rewrite_chapter / update_chapter_content 的流式进度）透传 onProgress
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

  /// create_side_story 成功后同步番外写入目标到 _currentContext。
  ///
  /// 解析工具结果 JSON 中的 sideStoryId/sideStoryUrl/sideStoryTitle，
  /// 让同一 LLM 响应中后续的 save_side_story_chapter 立即可定位番外
  /// （跨回合由 session 的 ToolCallEndEvent 接线注入，双保险同 select_novel）。
  void _syncSideStoryTarget(String result) {
    try {
      final parsed = jsonDecode(result) as Map<String, dynamic>;
      if (parsed['success'] != true) return;
      final id = parsed['sideStoryId'];
      final url = parsed['sideStoryUrl'] as String?;
      final title = parsed['sideStoryTitle'] as String?;
      if (id is! int || url == null || title == null) return;
      _currentContext = _rebuildCurrentContext(
        sideStory: ActiveSideStoryWritingTarget(
          novelId: id,
          novelUrl: url,
          title: title,
          anchorChapterTitle: parsed['anchorChapterTitle']?.toString(),
        ),
      );
    } catch (_) {
      // 非 JSON / 字段缺失 → 不同步（save 会走 no_side_story 引导兜底）
    }
  }

  /// 单点重建 _currentContext：以当前上下文为底座，只覆写调用方指定的
  /// 目标（工作小说 / 番外写入目标），其余跨工具携带字段一律回填。
  ///
  /// 背景：此前 select_novel 与 create_side_story 各自手写重建，字段保留
  /// 范围已经漂移——select_novel 路径只回填 readingContext/currentUrl，
  /// 丢掉 sideStoryWritingTarget/chatSessionId/rewriteTarget 等，换书后
  /// 番外写入目标静默丢失。新增 AgentScenarioContext 携带字段时只改本处。
  AgentScenarioContext _rebuildCurrentContext({
    ({int id, String? title})? novel,
    ActiveSideStoryWritingTarget? sideStory,
  }) {
    final base = _currentContext;
    return AgentScenarioContext(
      scenarioId: base?.scenarioId ?? ScenarioIds.writing,
      readingContext: base?.readingContext,
      webviewController: base?.webviewController,
      currentUrl: base?.currentUrl,
      useHeadlessWebView: base?.useHeadlessWebView ?? false,
      currentNovelId: novel?.id ?? base?.currentNovelId,
      currentNovelTitle: novel != null ? novel.title : base?.currentNovelTitle,
      rewriteTarget: base?.rewriteTarget,
      sideStoryWritingTarget: sideStory ?? base?.sideStoryWritingTarget,
      textGameId: base?.textGameId,
      chatSessionId: base?.chatSessionId,
    );
  }

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

  /// select_novel 工具结果同步：覆写工作小说（其余字段经
  /// [_rebuildCurrentContext] 单点回填，番外写入目标等不丢）。
  void _syncCurrentContext(String result) {
    try {
      final parsed = jsonDecode(result) as Map<String, dynamic>;
      if (parsed['success'] == true && parsed['novelId'] != null) {
        _currentContext = _rebuildCurrentContext(
          novel: (
            id: parsed['novelId'] as int,
            title: parsed['title'] as String?,
          ),
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
