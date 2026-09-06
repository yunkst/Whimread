/// ScenarioSession 隔离运行单元测试
///
/// 验证核心隔离行为：
/// 1. ScenarioSession 基本功能（发送消息、流式接收、取消、清空）
/// 2. 多场景并行互不干扰
/// 3. 场景切换不杀后台 Agent
/// 4. LRU 淘汰
/// 5. NovelAgentService 按 scenarioId 并行
/// 6. currentNovel 按 Session 隔离
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/providers/scenario_session_test.dart
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/agent_scenario_provider.dart';
import 'package:novel_app/core/providers/agent_chat_providers.dart';
import 'package:novel_app/core/providers/scenario_session.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/models/agent_chat_message.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/novel_agent_service.dart';

// ---------------------------------------------------------------------------
// MockNovelAgentService — 模拟 AgentService，支持按 scenarioId 并行
// ---------------------------------------------------------------------------

class MockNovelAgentService implements NovelAgentService {
  final _controller = StreamController<AgentEvent>.broadcast();
  final Map<String, Completer<void>> _completers = {};
  final Map<String, bool> _runningByScenario = {};
  int sendMessageCallCount = 0;
  final List<String> sendMessageScenarioIds = [];
  final List<String> sendMessageUserInputs = [];
  final Duration? delay;

  /// resumeFromMessages 调用计数与入参记录（retryLastRound 新语义走此路径）
  int resumeFromMessagesCallCount = 0;
  final List<String> resumeFromMessagesScenarioIds = [];
  final List<List<dynamic>> resumeFromMessagesInitialMessages = [];

  /// cancelFor 被调用的次数（按 scenarioId 累计）。
  /// 供「运行中写操作先 cancel 再执行」的新机制断言使用。
  int cancelForCallCount = 0;

  /// 失败注入：剩余多少轮调用需要模拟失败（emit AgentErrorEvent 而非正常流程）。
  /// 每次失败调用会自减。供 retryLastRound 测试使用。
  int failNextRounds = 0;

  /// 失败前是否先 emit 一段 TextDelta（模拟流式半成品）。
  /// 为 true 时失败轮会先发一个 TextDelta 再发 AgentErrorEvent。
  bool emitPartialBeforeFail = false;

  MockNovelAgentService({this.delay});

  @override
  Ref get ref => throw UnimplementedError();

  @override
  bool get isRunning => _runningByScenario.values.any((v) => v);

  @override
  bool isRunningFor(String scenarioId) =>
      _runningByScenario[scenarioId] == true;

  @override
  Stream<AgentEvent> get events => _controller.stream;

  @override
  Future<void> sendMessage({
    required String userInput,
    required List<dynamic> history,
    required String scenarioId,
    required AgentScenarioContext scenarioContext,
  }) async {
    // 同场景串行
    if (_runningByScenario[scenarioId] == true) {
      _controller.add(AgentErrorEvent('场景 $scenarioId 的 Agent 正在运行中'));
      return;
    }

    sendMessageCallCount++;
    sendMessageScenarioIds.add(scenarioId);
    sendMessageUserInputs.add(userInput);
    _runningByScenario[scenarioId] = true;

    final completer = Completer<void>();
    _completers[scenarioId] = completer;

    final shouldFail = failNextRounds > 0;
    if (shouldFail) {
      failNextRounds--;
    }

    try {
      // 等一帧让 ScenarioSession 的 listen 先注册上
      await Future<void>.delayed(Duration.zero);

      if (shouldFail) {
        // 失败路径：可选地先发一段半成品，再 emit AgentErrorEvent
        if (emitPartialBeforeFail) {
          _controller.add(TextDeltaEvent('[$scenarioId] 半成品回复...'));
          await Future<void>.delayed(Duration.zero);
        }
        _controller.add(AgentErrorEvent('模拟 LLM 调用失败'));
        await Future<void>.delayed(Duration.zero);
        return;
      }

      // 发一个文本增量模拟流式输出
      _controller.add(TextDeltaEvent('[$scenarioId] 回复: $userInput'));
      if (delay != null) {
        await Future<void>.delayed(delay!);
      }
      _controller.add(const AgentDoneEvent());

      // 再等一帧让事件传播到 listener
      await Future<void>.delayed(Duration.zero);
    } finally {
      _runningByScenario.remove(scenarioId);
      _completers.remove(scenarioId);
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  /// resumeFromMessages 实现：复用 sendMessage 的失败注入逻辑（failNextRounds / emitPartialBeforeFail）
  /// 成功路径 emit 一个 TextDelta + Done，失败路径可选 emit 半成品 + Error。
  @override
  Future<void> resumeFromMessages({
    required String scenarioId,
    required List<dynamic> initialMessages,
    required AgentScenarioContext scenarioContext,
  }) async {
    // 同场景串行
    if (_runningByScenario[scenarioId] == true) {
      _controller.add(AgentErrorEvent('场景 $scenarioId 的 Agent 正在运行中'));
      return;
    }

    resumeFromMessagesCallCount++;
    resumeFromMessagesScenarioIds.add(scenarioId);
    resumeFromMessagesInitialMessages.add(List<dynamic>.from(initialMessages));
    _runningByScenario[scenarioId] = true;

    final completer = Completer<void>();
    _completers[scenarioId] = completer;

    final shouldFail = failNextRounds > 0;
    if (shouldFail) {
      failNextRounds--;
    }

    try {
      await Future<void>.delayed(Duration.zero);

      if (shouldFail) {
        if (emitPartialBeforeFail) {
          _controller.add(TextDeltaEvent('[$scenarioId] 半成品回复...'));
          await Future<void>.delayed(Duration.zero);
        }
        _controller.add(AgentErrorEvent('模拟 LLM 调用失败'));
        await Future<void>.delayed(Duration.zero);
        return;
      }

      // 续跑成功：从 initialMessages 末尾取 user content 还原回复（便于断言）
      String lastUserContent = '';
      for (int i = initialMessages.length - 1; i >= 0; i--) {
        final m = initialMessages[i];
        if (m is ChatMessage && m.role == 'user') {
          lastUserContent = m.content ?? '';
          break;
        }
      }
      _controller.add(TextDeltaEvent('[$scenarioId] 回复: $lastUserContent'));
      if (delay != null) {
        await Future<void>.delayed(delay!);
      }
      _controller.add(const AgentDoneEvent());
      await Future<void>.delayed(Duration.zero);
    } finally {
      _runningByScenario.remove(scenarioId);
      _completers.remove(scenarioId);
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  @override
  void cancelFor(String scenarioId) {
    cancelForCallCount++;
    final completer = _completers[scenarioId];
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _completers.remove(scenarioId);
    _runningByScenario.remove(scenarioId);
  }

  @override
  void cancelAll() {
    for (final c in _completers.values) {
      if (!c.isCompleted) c.complete();
    }
    _completers.clear();
    _runningByScenario.clear();
  }

  @override
  void addEvent(AgentEvent event) {
    _controller.add(event);
  }

  @override
  void dispose() {
    _controller.close();
  }

  @override
  void injectUserMessage(String scenarioId, String text) {}
}

// ---------------------------------------------------------------------------
// 辅助：构建 ProviderContainer（注入 mock）
// ---------------------------------------------------------------------------

ProviderContainer createContainer(MockNovelAgentService mockService) {
  return ProviderContainer(overrides: [
    novelAgentServiceProvider.overrideWith((ref) => mockService),
  ]);
}

// ---------------------------------------------------------------------------
// 测试
// ---------------------------------------------------------------------------

void main() {
  late MockNovelAgentService mockService;
  late ProviderContainer container;

  setUp(() {
    mockService = MockNovelAgentService();
    container = createContainer(mockService);
  });

  tearDown(() {
    container.dispose();
  });

  // ===========================================================================
  // 1. ScenarioSession 基本功能
  // ===========================================================================

  group('ScenarioSession 基本功能', () {
    test('初始状态正确', () {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      expect(session.scenarioId, ScenarioIds.writing);
      expect(session.state.messages, isEmpty);
      expect(session.isRunning, isFalse);
      expect(session.lifecycle, SessionLifecycle.fresh);
    });

    test('sendMessage 后 isLoading 变为 true 且消息入列', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      await session.sendMessage(content: '你好');

      // 流式完成后应包含 user + assistant 消息
      expect(session.state.messages.length, 2,
          reason: '应有 1 条 user + 1 条 assistant 消息');
      expect(session.state.messages.first.role, AgentChatRole.user);
      expect(session.state.messages.last.role, AgentChatRole.assistant);
      expect(session.isRunning, isFalse);
      expect(session.lifecycle, SessionLifecycle.idle);
    });

    test('cancel 后 isLoading 变为 false', () {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      // 直接调 cancel（无运行任务时）
      session.cancel();
      expect(session.isRunning, isFalse);
      expect(session.state.isLoading, isFalse);
      expect(session.state.streamingSegments, isEmpty);
    });

    test('clearConversation 清空消息但保留 scenarioId 和 currentNovel', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      await session.sendMessage(content: '测试消息');
      expect(session.state.messages.isNotEmpty, isTrue);

      session.clearConversation();
      expect(session.state.messages, isEmpty);
      expect(session.state.scenarioId, ScenarioIds.writing);
    });

    test('空消息不触发发送', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      await session.sendMessage(content: '');
      await session.sendMessage(content: '   ');

      expect(mockService.sendMessageCallCount, 0);
      expect(session.state.messages, isEmpty);
    });
  });

  // ===========================================================================
  // 2. 多场景并行互不干扰
  // ===========================================================================

  group('多场景并行互不干扰', () {
    test('两个场景各自独立发送消息', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final writingSession = sessions.get(ScenarioIds.writing);
      final extractSession = sessions.get(ScenarioIds.webviewExtract);

      // 在 writing 场景发送消息
      await writingSession.sendMessage(content: '写作消息');
      expect(writingSession.state.messages.length, 2);
      expect(writingSession.state.messages.first.content, contains('写作消息'));

      // 在 webview_extract 场景发送消息
      await extractSession.sendMessage(content: '提取消息');
      expect(extractSession.state.messages.length, 2);
      expect(extractSession.state.messages.first.content, contains('提取消息'));

      // 各自消息互不影响
      expect(writingSession.state.messages.length, 2,
          reason: 'writing 场景消息不应受 extract 影响');
      expect(extractSession.state.messages.length, 2,
          reason: 'extract 场景消息不应受 writing 影响');
    });

    test('一个场景的 clearConversation 不影响另一个', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final writingSession = sessions.get(ScenarioIds.writing);
      final extractSession = sessions.get(ScenarioIds.webviewExtract);

      await writingSession.sendMessage(content: '写作消息');
      await extractSession.sendMessage(content: '提取消息');

      // 清空 writing 场景
      writingSession.clearConversation();
      expect(writingSession.state.messages, isEmpty);
      expect(extractSession.state.messages.isNotEmpty, isTrue,
          reason: 'extract 场景消息不应受 writing 清空影响');
    });

    test('NovelAgentService 按场景跟踪运行状态', () async {
      // 验证 MockNovelAgentService 的按场景运行状态
      expect(mockService.isRunningFor(ScenarioIds.writing), isFalse);
      expect(mockService.isRunningFor(ScenarioIds.webviewExtract), isFalse);

      // 发送消息时场景变为 running
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final writingSession = sessions.get(ScenarioIds.writing);

      // 由于 sendMessage 是同步执行的 mock，发送完成后 running 已重置
      await writingSession.sendMessage(content: '测试');
      expect(mockService.isRunningFor(ScenarioIds.writing), isFalse);
    });
  });

  // ===========================================================================
  // 3. 场景切换不杀后台 Agent（通过 ScenarioSessionsNotifier）
  // ===========================================================================

  group('场景切换不杀后台 Agent', () {
    test('切换场景时，原场景的 session 仍然存在', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);

      // 在 writing 场景发送消息
      final writingSession = sessions.get(ScenarioIds.writing);
      await writingSession.sendMessage(content: '写作消息');
      final writingMessages = writingSession.state.messages;

      // 切换到 webview_extract
      final extractSession = sessions.get(ScenarioIds.webviewExtract);
      await extractSession.sendMessage(content: '提取消息');

      // 切回 writing — session 应该还在
      final writingAgain = sessions.get(ScenarioIds.writing);
      expect(identical(writingSession, writingAgain), isTrue,
          reason: '同一个 scenarioId 应返回同一个 ScenarioSession 实例');
      expect(writingAgain.state.messages.length, writingMessages.length,
          reason: '切回 writing 时消息应保留');
    });

    test('sessions 状态 map 包含所有场景', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);

      sessions.get(ScenarioIds.writing);
      sessions.get(ScenarioIds.webviewExtract);

      // 等待微任务：_scheduleSync 将 state 写入推迟到微任务执行
      await Future<void>.delayed(Duration.zero);

      final state = container.read(scenarioSessionsProvider);
      expect(state.containsKey(ScenarioIds.writing), isTrue);
      expect(state.containsKey(ScenarioIds.webviewExtract), isTrue);
    });
  });

  // ===========================================================================
  // 4. LRU 淘汰
  // ===========================================================================

  group('LRU 淘汰', () {
    test('超过 _maxSessions 时淘汰空闲 session', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);

      // 创建最多 8 个 session
      for (int i = 0; i < 8; i++) {
        sessions.get('scenario_$i');
      }

      // 等待微任务：_scheduleSync 将 _evictIfNeeded + _syncState 推迟到微任务
      await Future<void>.delayed(Duration.zero);

      // 验证已创建 8 个
      expect(sessions.activeSessionIds.length, 8);

      // 创建第 9 个，应触发淘汰
      sessions.get('scenario_8');

      // 等待微任务执行淘汰
      await Future<void>.delayed(Duration.zero);

      // 淘汰后应仍然 <= 8
      expect(sessions.activeSessionIds.length, lessThanOrEqualTo(8));
    });

    test('disposeSession 手动销毁指定场景', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);

      final writingSession = sessions.get(ScenarioIds.writing);
      await writingSession.sendMessage(content: '消息');
      expect(sessions.hasSession(ScenarioIds.writing), isTrue);

      sessions.disposeSession(ScenarioIds.writing);
      expect(sessions.hasSession(ScenarioIds.writing), isFalse);

      // 再次 get 会创建新 session
      final newSession = sessions.get(ScenarioIds.writing);
      expect(newSession.state.messages, isEmpty,
          reason: '新 session 应该是空的');
    });
  });

  // ===========================================================================
  // 5. 兼容层 AgentChatNotifier 仍可用
  // ===========================================================================

  group('兼容层 AgentChatNotifier', () {
    test('sendMessage 通过兼容层正常工作', () async {
      final notifier = container.read(agentChatProvider.notifier);
      await notifier.sendMessage('兼容层测试');

      final state = container.read(agentChatProvider);
      expect(state.messages.length, 2);
    });

    test('switchScenario 通过兼容层切换场景', () async {
      final notifier = container.read(agentChatProvider.notifier);

      await notifier.sendMessage('写作消息');
      final writingState = container.read(agentChatProvider);
      expect(writingState.scenarioId, ScenarioIds.writing);

      notifier.switchScenario(ScenarioIds.webviewExtract, '网页提取');
      final extractState = container.read(agentChatProvider);
      expect(extractState.scenarioId, ScenarioIds.webviewExtract);
    });

    test('clearConversation 通过兼容层清空', () async {
      final notifier = container.read(agentChatProvider.notifier);

      await notifier.sendMessage('测试');
      expect(container.read(agentChatProvider).messages.isNotEmpty, isTrue);

      notifier.clearConversation();
      expect(container.read(agentChatProvider).messages, isEmpty);
    });

    test('cancelRequest 通过兼容层取消', () {
      final notifier = container.read(agentChatProvider.notifier);

      notifier.cancelRequest();
      final state = container.read(agentChatProvider);
      expect(state.isLoading, isFalse);
    });
  });

  // ===========================================================================
  // 6. currentChatStateProvider 正确映射
  // ===========================================================================

  group('currentChatStateProvider', () {
    test('返回当前场景的状态', () async {
      // 初始场景是 writing
      final state = container.read(currentChatStateProvider);
      expect(state.scenarioId, ScenarioIds.writing);

      // 发消息
      final notifier = container.read(agentChatProvider.notifier);
      await notifier.sendMessage('测试');
      final updatedState = container.read(currentChatStateProvider);
      expect(updatedState.messages.length, 2);
    });

    test('切换场景后返回新场景的状态', () async {
      final notifier = container.read(agentChatProvider.notifier);
      await notifier.sendMessage('写作消息');

      // 切换场景
      container.read(currentAgentScenarioProvider.notifier).state =
          ScenarioIds.webviewExtract;

      final state = container.read(currentChatStateProvider);
      expect(state.scenarioId, ScenarioIds.webviewExtract);
    });
  });

  // ===========================================================================
  // 7. ScenarioSession 事件处理
  // ===========================================================================

  group('ScenarioSession 事件处理', () {
    test('ToolCallStart/End 事件正确处理', () async {
      // 直接发送一个带工具调用的事件序列
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      // 发送消息会触发 MockNovelAgentService 发出 TextDelta + Done 事件
      await session.sendMessage(content: '调用工具');

      // 验证消息结构
      final lastMsg = session.state.messages.last;
      expect(lastMsg.role, AgentChatRole.assistant);
    });
  });

  // ===========================================================================
  // 8. Session 生命周期
  // ===========================================================================

  group('Session 生命周期', () {
    test('fresh → active → idle 状态转换', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      expect(session.lifecycle, SessionLifecycle.fresh);

      await session.sendMessage(content: '测试');
      expect(session.lifecycle, SessionLifecycle.idle);
    });

    test('cancel 从 active → idle', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      // 手动设置 running 状态后取消
      // 由于 mock 是同步的，我们通过直接 cancel 测试
      session.cancel();
      expect(session.lifecycle, SessionLifecycle.idle);
    });

    test('dispose 设置 disposed', () {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      session.dispose();
      expect(session.lifecycle, SessionLifecycle.disposed);
    });
  });

  // ===========================================================================
  // 8.5 cancel — partial 落库为 assistant turn
  // ===========================================================================

  group('cancel partial 落库', () {
    test('运行中有 _pendingSegments 时调 cancel → 落库为 partial assistant，状态重置',
        () async {
      final slowMock =
          MockNovelAgentService(delay: const Duration(milliseconds: 100));
      final slowContainer = ProviderContainer(overrides: [
        novelAgentServiceProvider.overrideWith((ref) => slowMock),
      ]);
      addTearDown(slowContainer.dispose);

      final slowSessions =
          slowContainer.read(scenarioSessionsProvider.notifier);
      final slowSession = slowSessions.get(ScenarioIds.writing);

      // 启动慢发送：mock 会先 emit TextDelta，再 delay 100ms
      final sendFuture = slowSession.sendMessage(content: '测试');

      // 等 _isRunning=true 并让 TextDelta 被 listener 处理进 _pendingSegments。
      // 100ms 给微任务链足够的时间窗口（_persistAgentMessage + listen + add TextDelta）。
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(slowSession.isRunning, isTrue, reason: '前置：应正在运行');

      // cancel —— 应把 _pendingSegments 落库为 partial assistant turn
      slowSession.cancel();

      expect(slowSession.isRunning, isFalse, reason: 'cancel 后应停止运行');
      expect(slowSession.state.isLoading, isFalse);
      expect(slowSession.state.streamingSegments, isEmpty);
      // user 消息 + 落库的 partial assistant = 2 条
      expect(slowSession.state.messages.length, 2,
          reason: '应有 user + 落库的 partial assistant');
      expect(slowSession.state.messages.first.role, AgentChatRole.user);
      expect(slowSession.state.messages.last.role, AgentChatRole.assistant);
      expect(slowSession.state.messages.last.content,
          contains('回复'), reason: 'partial assistant content 应保留流式文本');

      await sendFuture;
    });
  });

  // ===========================================================================
  // 9. retryLastRound — LLM 失败后重试
  // ===========================================================================

  group('retryLastRound', () {
    test('失败首轮重试 → 走 resumeFromMessages 续跑，error 清空', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      // 第一次：模拟失败
      mockService.failNextRounds = 1;
      await session.sendMessage(content: '你好');

      expect(session.state.error, isNotNull, reason: '首轮失败应设置 error');
      expect(session.state.messages.length, 1);
      expect(session.state.messages.last.role, AgentChatRole.user);
      expect(session.state.messages.last.content, '你好');
      expect(mockService.sendMessageCallCount, 1);

      // 重试（mock 此时已恢复正常）—— 新语义走 resumeFromMessages
      await session.retryLastRound();

      expect(mockService.sendMessageCallCount, 1,
          reason: '重试不应再调 sendMessage');
      expect(mockService.resumeFromMessagesCallCount, 1,
          reason: '重试应走 resumeFromMessages 续跑');
      // 续跑传给 service 的 initialMessages 末尾应是 user「你好」
      final resumedMsgs = mockService.resumeFromMessagesInitialMessages.last;
      expect(resumedMsgs.last, isA<ChatMessage>());
      expect((resumedMsgs.last as ChatMessage).role, 'user');
      expect((resumedMsgs.last as ChatMessage).content, '你好',
          reason: '续跑应保留原 user 消息，不重复 append');
      expect(session.state.error, isNull, reason: '重试后 error 应清空');
      expect(session.state.messages.length, 2,
          reason: '重试成功后应有 user + assistant');
      expect(session.state.messages.first.role, AgentChatRole.user);
      expect(session.state.messages.first.content, '你好',
          reason: '不应重复添加 user 消息');
      expect(session.state.messages.last.role, AgentChatRole.assistant);
    });

    test('前一轮成功 + 当前轮半成品失败时重试 → 保留前一轮，砍除失败轮 partial，续跑',
        () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      // 第一轮正常：messages = [user1, assistant1]
      await session.sendMessage(content: '第一条');
      expect(session.state.messages.length, 2);

      // 第二轮失败 + 半成品：messages = [user1, assistant1, user2, assistant_half]
      mockService.failNextRounds = 1;
      mockService.emitPartialBeforeFail = true;
      await session.sendMessage(content: '第二条');
      expect(session.state.error, isNotNull);
      expect(session.state.messages.length, 4,
          reason: '半成品 assistant 应已入列');
      expect(session.state.messages[2].role, AgentChatRole.user);
      expect(session.state.messages[2].content, '第二条');
      expect(session.state.messages.last.role, AgentChatRole.assistant,
          reason: '末尾应是半成品 assistant');

      // 重试：新语义保留前一轮成功 ReAct，只砍除失败轮 partial
      await session.retryLastRound();

      // 走 resumeFromMessages 而非 sendMessage
      expect(mockService.resumeFromMessagesCallCount, 1,
          reason: '重试应走 resumeFromMessages 续跑');
      expect(mockService.sendMessageCallCount, 2,
          reason: 'sendMessage 只在用户主动发消息时调用（首轮+第二轮 = 2），重试不走');

      // 续跑传给 service 的 messages 应保留 user1 + assistant1 + user2（去掉 assistant_half）
      final resumedMsgs = mockService.resumeFromMessagesInitialMessages.last;
      expect(resumedMsgs.length, 3,
          reason: '应保留前一轮 [user1, assistant1] + 失败轮的 user2');
      expect((resumedMsgs[0] as ChatMessage).role, 'user');
      expect((resumedMsgs[0] as ChatMessage).content, '第一条');
      expect((resumedMsgs[1] as ChatMessage).role, 'assistant');
      expect((resumedMsgs[2] as ChatMessage).role, 'user');
      expect((resumedMsgs[2] as ChatMessage).content, '第二条',
          reason: '失败轮的 user2 必须保留');

      // UI 状态：保留 [user1, assistant1, user2] + 重试成功 new assistant = 4
      expect(session.state.messages.length, 4,
          reason: '保留前一轮成功 + user2 + 重试新 assistant = 4');
      expect(session.state.messages[0].content, '第一条',
          reason: '前一轮 user 必须保留');
      expect(session.state.messages[1].role, AgentChatRole.assistant,
          reason: '前一轮 assistant 必须保留');
      expect(session.state.messages[2].content, '第二条',
          reason: '失败轮的 user 必须保留');
      expect(session.state.messages.last.role, AgentChatRole.assistant,
          reason: '末尾应是重试成功的新 assistant');
      expect(session.state.error, isNull);
    });

    test('运行中调 retryLastRound → 不再拒绝（interrupt-then-act，契约回归）',
        () async {
      // 用独立的慢 mock 容器，让 sendMessage 不立即完成
      final slowMock = MockNovelAgentService(delay: const Duration(milliseconds: 100));
      final slowContainer = ProviderContainer(overrides: [
        novelAgentServiceProvider.overrideWith((ref) => slowMock),
      ]);
      addTearDown(slowContainer.dispose);

      final slowSessions = slowContainer.read(scenarioSessionsProvider.notifier);
      final slowSession = slowSessions.get(ScenarioIds.writing);

      // 启动慢发送
      final sendFuture = slowSession.sendMessage(content: '慢消息');

      // 等 _isRunning=true
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(slowSession.isRunning, isTrue, reason: '前置：慢发送应正在运行');

      // 运行中调 retry：interrupt-then-act = cancel 落 partial（finalize error → 设置 _failedRoundStartIndex）
      // → 砍除失败轮残留 → resumeFromMessages 续跑（保留之前成功轮）
      await slowSession.retryLastRound();

      // 新契约：旧的拒绝文案 "Agent 正在运行，无法重试" 不再产生
      expect(slowSession.state.error, isNot('Agent 正在运行，无法重试'),
          reason: '运行中 retry 不应再被拒绝（旧文案已废弃）');
      // 最终达到一致状态（不论 retry 在 mock 环境下能否并发成功）
      expect(slowSession.isRunning, isFalse,
          reason: 'retry 完成后应回到 idle 态');

      // 清理仍在飞的 sendFuture
      await sendFuture;
    });

    test('全新 session 无失败轮时 → 拒绝并设置 error 提示', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      // 全新 session，无失败轮记录，直接调 retryLastRound
      await session.retryLastRound();

      expect(session.state.error, '当前没有可重试的失败轮次');
      expect(mockService.sendMessageCallCount, 0,
          reason: '无失败轮时不应调用 sendMessage');
      expect(mockService.resumeFromMessagesCallCount, 0,
          reason: '无失败轮时不应调用 resumeFromMessages');
    });

    test('3 轮成功 + 第 4 轮失败 → 重试只砍第 4 轮，保留前 3 轮 ReAct', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      // 前 3 轮都成功
      await session.sendMessage(content: '轮1');
      await session.sendMessage(content: '轮2');
      await session.sendMessage(content: '轮3');
      expect(session.state.messages.length, 6, reason: '3 轮各 user+assistant = 6');

      // 第 4 轮失败 + 半成品
      mockService.failNextRounds = 1;
      mockService.emitPartialBeforeFail = true;
      await session.sendMessage(content: '轮4');
      expect(session.state.error, isNotNull);
      expect(session.state.messages.length, 8,
          reason: '前 3 轮(6) + 轮4 user + 轮4 半成品 assistant = 8');

      // 重试：保留前 3 轮，砍掉第 4 轮半成品，续跑第 4 轮
      await session.retryLastRound();

      expect(mockService.resumeFromMessagesCallCount, 1,
          reason: '重试走 resumeFromMessages');

      // 续跑传给 service 的 messages：前 3 轮完整 + 轮4 user（去掉半成品 assistant）
      final resumedMsgs = mockService.resumeFromMessagesInitialMessages.last;
      expect(resumedMsgs.length, 7,
          reason: '前 3 轮(6) + 轮4 user = 7（半成品 assistant 已砍除）');
      expect((resumedMsgs.last as ChatMessage).role, 'user');
      expect((resumedMsgs.last as ChatMessage).content, '轮4',
          reason: '失败轮的 user4 必须保留');

      // UI 状态：前 3 轮完整 + 轮4 user + 重试新 assistant = 8
      expect(session.state.messages.length, 8);
      // 前 3 轮内容必须一字不变（保留成功 ReAct）
      expect(session.state.messages[0].content, '轮1');
      expect(session.state.messages[1].role, AgentChatRole.assistant);
      expect(session.state.messages[2].content, '轮2');
      expect(session.state.messages[3].role, AgentChatRole.assistant);
      expect(session.state.messages[4].content, '轮3');
      expect(session.state.messages[5].role, AgentChatRole.assistant);
      expect(session.state.messages[6].content, '轮4', reason: '用户消息 4 必须保留');
      expect(session.state.messages.last.role, AgentChatRole.assistant,
          reason: '末尾应是重试成功的新 assistant');
      expect(session.state.error, isNull);
    });
  });

  // ===========================================================================
  // 10. rollbackToMessage — 回滚到指定 user 消息
  // ===========================================================================

  group('rollbackToMessage', () {
    test('回滚到第一条 user 消息 → 删除该消息及之后所有消息，content 回传', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      // 构造两轮对话：[user1, assistant1, user2, assistant2]
      await session.sendMessage(content: '第一条');
      await session.sendMessage(content: '第二条');
      expect(session.state.messages.length, 4);

      String? callbackContent;
      final result = await session.rollbackToMessage(
        0,
        contentCallback: (c) => callbackContent = c,
      );

      expect(result, isTrue, reason: '回滚到第一条 user 应成功');
      expect(callbackContent, '第一条', reason: 'callback 应回传该 user 的 content');
      expect(session.state.messages, isEmpty,
          reason: '回滚到第一条 user 后应删除所有消息（含目标 user）');
    });

    test('回滚到最后一条 user 消息 → 删掉最后一轮回复，保留前面轮次', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      // 构造两轮对话：[user1, assistant1, user2, assistant2]
      await session.sendMessage(content: '第一条');
      await session.sendMessage(content: '第二条');
      expect(session.state.messages.length, 4);

      // UI index 2 = user2
      String? callbackContent;
      final result = await session.rollbackToMessage(
        2,
        contentCallback: (c) => callbackContent = c,
      );

      expect(result, isTrue);
      expect(callbackContent, '第二条');
      // 回滚后应保留 [user1, assistant1]，user2 及 assistant2 被删除
      expect(session.state.messages.length, 2,
          reason: '应保留第一轮的 user + assistant');
      expect(session.state.messages[0].role, AgentChatRole.user);
      expect(session.state.messages[0].content, '第一条');
      expect(session.state.messages[1].role, AgentChatRole.assistant);
    });

    test('运行中调 rollbackToMessage → 不再拒绝（interrupt-then-act，契约回归）',
        () async {
      final slowMock = MockNovelAgentService(delay: const Duration(milliseconds: 100));
      final slowContainer = ProviderContainer(overrides: [
        novelAgentServiceProvider.overrideWith((ref) => slowMock),
      ]);
      addTearDown(slowContainer.dispose);

      final slowSessions = slowContainer.read(scenarioSessionsProvider.notifier);
      final slowSession = slowSessions.get(ScenarioIds.writing);

      // 先发一条消息建立历史
      await slowSession.sendMessage(content: '前置消息');

      // 启动慢发送
      final sendFuture = slowSession.sendMessage(content: '慢消息');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(slowSession.isRunning, isTrue, reason: '前置：慢发送应正在运行');

      final result = await slowSession.rollbackToMessage(
        0,
        contentCallback: (_) {},
      );

      // 新契约：旧的拒绝文案 "Agent 正在运行，无法回滚" 不再产生
      expect(slowSession.state.error, isNot('Agent 正在运行，无法回滚'),
          reason: '运行中 rollback 不应再被拒绝（旧文案已废弃）');
      // 最终回到一致状态
      expect(slowSession.isRunning, isFalse);

      await sendFuture;
    });

    test('索引越界 → 返回 false', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      await session.sendMessage(content: '测试');
      expect(session.state.messages.length, 2);

      // 负索引
      expect(
        await session.rollbackToMessage(-1, contentCallback: (_) {}),
        isFalse,
        reason: '负索引应返回 false',
      );

      // 超出长度
      expect(
        await session.rollbackToMessage(99, contentCallback: (_) {}),
        isFalse,
        reason: '超出长度的索引应返回 false',
      );

      // 消息不应被修改
      expect(session.state.messages.length, 2, reason: '越界回滚不应影响消息');
    });

    test('目标非 user 消息（指向 assistant）→ 返回 false', () async {
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final session = sessions.get(ScenarioIds.writing);

      await session.sendMessage(content: '测试');
      // messages = [user, assistant]，index 1 是 assistant
      expect(session.state.messages.length, 2);
      expect(session.state.messages[1].role, AgentChatRole.assistant);

      final result = await session.rollbackToMessage(
        1,
        contentCallback: (_) {},
      );

      expect(result, isFalse, reason: '指向 assistant 的索引应拒绝回滚');
      expect(session.state.messages.length, 2, reason: '非 user 目标不应影响消息');
    });
  });

  // ===========================================================================
  // 6. sendMessage 图片附件（Task 4 新增）
  // ===========================================================================

  group('sendMessage 图片附件', () {
    test('双空拦截：空 content + 空 imageMediaIds 不入栈', () async {
      final mock = MockNovelAgentService();
      final c = createContainer(mock);
      final session = c.read(scenarioSessionsProvider.notifier).get(ScenarioIds.writing);

      await session.sendMessage(content: '');

      expect(session.state.messages, isEmpty);
      expect(mock.sendMessageCallCount, 0);
    });

    test('单图无文：拼占位文本，agent 收到 mediaId；UI 消息还原 ImageSegment',
        () async {
      final mock = MockNovelAgentService();
      final c = createContainer(mock);
      final session = c.read(scenarioSessionsProvider.notifier).get(ScenarioIds.writing);

      await session.sendMessage(
        content: '',
        imageMediaIds: const ['local_abc123'],
      );

      // agent 视角收到的 userInput 含占位文本
      expect(mock.sendMessageUserInputs.last,
          contains('[用户上传了图片 mediaId=local_abc123]'));
      // UI 消息：user 一条（assistant 因 mock 流式一定会加进来）
      expect(session.state.messages.length, greaterThanOrEqualTo(1));
      final userMsg = session.state.messages.first;
      expect(userMsg.role, AgentChatRole.user);
      // 投影层还原出 ImageSegment
      expect(userMsg.segments.whereType<ImageSegment>().length, 1);
      expect(userMsg.segments.whereType<ImageSegment>().first.mediaId,
          'local_abc123');
    });

    test('单图有文：占位文本 + 用户原文', () async {
      final mock = MockNovelAgentService();
      final c = createContainer(mock);
      final session = c.read(scenarioSessionsProvider.notifier).get(ScenarioIds.writing);

      await session.sendMessage(
        content: '把这张图变成水墨风视频',
        imageMediaIds: const ['local_abc123'],
      );

      expect(mock.sendMessageUserInputs.last,
          contains('[用户上传了图片 mediaId=local_abc123]'));
      expect(mock.sendMessageUserInputs.last,
          contains('把这张图变成水墨风视频'));
      final userMsg = session.state.messages.first;
      expect(userMsg.role, AgentChatRole.user);
      expect(userMsg.segments.whereType<ImageSegment>().length, 1);
      // 用户原文作为 TextSegment 保留
      expect(
          userMsg.segments
              .whereType<TextSegment>()
              .any((t) => t.content.contains('把这张图变成水墨风视频')),
          isTrue);
    });
  });
}
