/// ScenarioSession._handleCompaction 单元测试（压缩提示 system 消息插入）
///
/// 覆盖 Task 4：
/// - 收到 CompactionEvent 后 _agentMessages 头部插入 system(role='system') 消息
/// - system.content 即 CompactionEvent.compactionNote（KV 文本）
/// - marker 独占头部 index 0（不论 droppedAgentFromIndex 多大）
/// - cut=0（无裁剪）时不插入
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/providers/scenario_session_compaction_marker_test.dart
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/agent_chat_providers.dart' show novelAgentServiceProvider;
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/core/providers/scenario_session.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart' show ChatMessage;
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/novel_agent_service.dart';
import 'package:novel_app/services/novel_agent/scenarios/writing_scenario.dart' show ScenarioIds;

// ---------------------------------------------------------------------------
// _SlowCompactionMock — 慢 sendMessage（不立即 complete），让事件流 listener
// 在 sendMessage 运行期间保持活跃，从而接收 addEvent 注入的 CompactionEvent。
// ---------------------------------------------------------------------------

class _SlowCompactionMock implements NovelAgentService {
  final _controller = StreamController<AgentEvent>.broadcast();
  final Map<String, bool> _running = {};
  final Duration _delay;

  _SlowCompactionMock({Duration delay = const Duration(milliseconds: 100)})
      : _delay = delay;

  @override
  Ref get ref => throw UnimplementedError();

  @override
  bool get isRunning => _running.values.any((v) => v);

  @override
  bool isRunningFor(String scenarioId) => _running[scenarioId] == true;

  @override
  Stream<AgentEvent> get events => _controller.stream;

  @override
  Future<void> sendMessage({
    required String userInput,
    required List<dynamic> history,
    required String scenarioId,
    required AgentScenarioContext scenarioContext,
  }) async {
    if (_running[scenarioId] == true) {
      _controller.add(AgentErrorEvent('场景 $scenarioId 的 Agent 正在运行中'));
      return;
    }
    _running[scenarioId] = true;
    try {
      await Future<void>.delayed(Duration.zero);
      _controller.add(TextDeltaEvent('回复: $userInput'));
      // 延迟，让 CompactionEvent 有机会在 AgentDoneEvent 之前被处理
      await Future<void>.delayed(_delay);
      _controller.add(const AgentDoneEvent());
      await Future<void>.delayed(Duration.zero);
    } finally {
      _running.remove(scenarioId);
    }
  }

  @override
  Future<void> resumeFromMessages({
    required String scenarioId,
    required List<dynamic> initialMessages,
    required AgentScenarioContext scenarioContext,
  }) async {}

  @override
  void cancelFor(String scenarioId) {
    _running.remove(scenarioId);
  }

  @override
  void cancelAll() {
    _running.clear();
  }

  void addEvent(AgentEvent event) {
    _controller.add(event);
  }

  @override
  void injectUserMessage(String scenarioId, String text) {}

  @override
  void dispose() {
    _controller.close();
  }
}

ProviderContainer _createContainer(_SlowCompactionMock mockService) {
  return ProviderContainer(overrides: [
    novelAgentServiceProvider.overrideWith((ref) => mockService),
  ]);
}

void main() {
  late _SlowCompactionMock mockService;
  late ProviderContainer container;

  setUp(() {
    mockService = _SlowCompactionMock();
    container = _createContainer(mockService);
  });

  tearDown(() {
    container.dispose();
  });

  CompactionEvent buildEvent({
    required int droppedAgentFromIndex,
    String? note,
  }) {
    final compactionNote = note ??
        '[上下文压缩|droppedCount=$droppedAgentFromIndex|keptCount=15|removedChars=420000|originalChars=580000|'
            'compactedChars=160000|rewrittenCount=0|timestamp=1706000101]\n'
            '后续。';
    return CompactionEvent(
      removedChars: 420000,
      originalChars: 580000,
      compactedChars: 160000,
      keptMessageCount: 15,
      droppedMessageCount: droppedAgentFromIndex,
      droppedAgentFromIndex: droppedAgentFromIndex,
      compactionNote: compactionNote,
      rewrittenContent: const [],
    );
  }

  /// 走 N 次 sendMessage 让 _agentMessages 积累 N 轮对话。
  /// 慢 mock 会等 100ms 再 emit AgentDoneEvent —— 我们在每轮 send 完成后
  /// 才注入 CompactionEvent（因为每轮完 listener 才被取消）。
  Future<ScenarioSession> setupSessionWithHistory({
    required int historyUserCount,
  }) async {
    final sessions = container.read(scenarioSessionsProvider.notifier);
    final session = sessions.get(ScenarioIds.writing);

    for (var i = 0; i < historyUserCount; i++) {
      await session.sendMessage(content: '历史消息 $i');
    }

    return session;
  }

  /// 在 sendMessage 运行期间注入 CompactionEvent（listener 活跃）
  Future<ScenarioSession> setupWithCompactionEvent({
    required int historyUserCount,
    required CompactionEvent event,
  }) async {
    final sessions = container.read(scenarioSessionsProvider.notifier);
    final session = sessions.get(ScenarioIds.writing);

    // 先发 historyUserCount 轮完成
    for (var i = 0; i < historyUserCount; i++) {
      await session.sendMessage(content: '历史消息 $i');
    }

    // 再发一轮，但在这轮 sendMessage 运行期间注入 CompactionEvent
    final sendFuture = session.sendMessage(content: '压缩触发消息');
    // 等 TextDelta 被 listener 处理后（约 0ms）注入 CompactionEvent
    await Future<void>.delayed(const Duration(milliseconds: 10));
    mockService.addEvent(event);
    // 等 _handleCompaction 处理完
    await Future<void>.delayed(const Duration(milliseconds: 200));

    return session;
  }

  group('_handleCompaction 头部插入压缩提示 system 消息', () {
    test('收到 CompactionEvent 后 _agentMessages 头部含 system 压缩提示', () async {
      final event = buildEvent(droppedAgentFromIndex: 2);
      final session = await setupWithCompactionEvent(
        historyUserCount: 2,
        event: event,
      );

      // 前置确认有消息
      expect(session.agentMessages, isNotEmpty);

      // 断言：头部是 system 压缩提示
      expect(session.agentMessages.first.role, 'system',
          reason: '压缩后头部应是 system 压缩提示');
      expect(session.agentMessages.first.content, event.compactionNote);
      expect(session.agentMessages.first.content, startsWith('[上下文压缩|'));

      // 第二、三条应是保留的用户/assistant 消息
      expect(session.agentMessages[1].role, anyOf('user', 'assistant'),
          reason: 'marker 后应是保留的对话消息');
    });

    test('droppedAgentFromIndex 覆盖整段历史时，system marker 仍独占头部', () async {
      final event = buildEvent(droppedAgentFromIndex: 4);
      final session = await setupWithCompactionEvent(
        historyUserCount: 1,
        event: event,
      );

      // 前置：至少 1 条 marker
      expect(session.agentMessages, isNotEmpty);
      expect(session.agentMessages.first.role, 'system');
      expect(session.agentMessages.first.content, event.compactionNote);
    });

    test('cut=0 时不插入 marker（无裁剪 = 无 system 消息）', () async {
      final event = buildEvent(droppedAgentFromIndex: 0);
      final session = await setupWithCompactionEvent(
        historyUserCount: 2,
        event: event,
      );

      // 断言：头部仍是 user（marker 未插入）
      expect(session.agentMessages.first.role, 'user');
      // 不应包含任何 system 消息
      expect(
          session.agentMessages.any((m) => m.role == 'system'), isFalse,
          reason: 'cut=0 时不应插入 marker');
    });

    test('marker 的 ChatMessage role 严格为 "system"（与 LLM ChatMessage 兼容）',
        () async {
      final event = buildEvent(droppedAgentFromIndex: 1);
      final session = await setupWithCompactionEvent(
        historyUserCount: 1,
        event: event,
      );

      final marker = session.agentMessages.first;
      expect(marker, isA<ChatMessage>());
      expect(marker.role, 'system',
          reason: 'marker 角色必须为 "system"，agent_loop / LLM 才认');
    });
  });
}