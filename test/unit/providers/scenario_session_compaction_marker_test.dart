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
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/core/providers/scenario_session.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/novel_agent_service.dart';
import 'package:novel_app/utils/cancellation_token.dart';

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

  /// 为 true 时每轮 sendMessage 在 TextDelta 后发一次完整工具调用
  /// （Start + End(success)），让链里产生 assistant(toolCalls) + tool 消息
  bool emitToolCalls = false;
  int _toolCallSeq = 0;

  @override
  Ref get ref => throw UnimplementedError();

  @override
  bool get isRunning => _running.values.any((v) => v);

  @override
  bool isRunningFor(String scenarioId) => _running[scenarioId] == true;
  /// 取消令牌：mock 不做令牌簿记（cancelFor 直接放行 completer），恒为 null
  @override
  CancellationToken? tokenFor(String scenarioId) => null;


  @override
  Stream<AgentEvent> get events => _controller.stream;

  @override
  Future<void> sendMessage({
    required String userInput,
    required List<dynamic> history,
    required String scenarioId,
    required AgentScenarioContext scenarioContext,
    String? runId,
  }) async {
    if (_running[scenarioId] == true) {
      _controller.add(AgentErrorEvent('场景 $scenarioId 的 Agent 正在运行中'));
      return;
    }
    _running[scenarioId] = true;
    try {
      await Future<void>.delayed(Duration.zero);
      _controller.add(TextDeltaEvent('回复: $userInput'));
      if (emitToolCalls) {
        final id = 'call_${_toolCallSeq++}';
        _controller.add(ToolCallStartEvent('read_chapter_content', {}, id));
        _controller.add(ToolCallEndEvent('read_chapter_content', id,
            '原始超长工具结果 $id', success: true));
      }
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
    String? runId,
  }) async {}

  @override
  void cancelFor(String scenarioId) {
    _running.remove(scenarioId);
  }

  @override
  void cancelAll() {
    _running.clear();
  }

  @override
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
    List<({int index, String newContent})> rewrittenContent = const [],
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
      rewrittenContent: rewrittenContent,
    );
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
    unawaited(session.sendMessage(content: '压缩触发消息'));
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

  group('_handleCompaction 预剪枝改写落点（off-by-one 回归）', () {
    // 回归背景：marker 插入使压缩后索引 = 压缩前 index - cut + 1，此前误用
    // `- cut`——每条改写落到前一条消息上：应裁剪的超长 tool 结果没裁，
    // 反而把它前面那条的内容改坏（内存与 DB 同步写错值，测试难以察觉）。
    //
    // 链布局（每轮 = user + assistant(toolCalls) + tool）：
    //   压缩前 [u1,A1,T1, u2,A2,T2, u3,A3,T3]，cut=2 → 压缩后
    //   [M, T1, u2, A2, T2, u3, A3, T3]
    //   entry(2)→T1、entry(5)→T2（正确落点 = index - cut + 1）；
    //   entry(4) 是 assistant，应被 role 守卫跳过。
    //   旧代码用 `- cut`：三条分别落到 marker / u2 / A2，全部被守卫跳过，
    //   T1、T2 保持超长原文——本测试即在旧代码下失败。
    test('改写精确落到目标 tool 消息，assistant 不被波及', () async {
      mockService.emitToolCalls = true;
      final event = buildEvent(
        droppedAgentFromIndex: 2,
        rewrittenContent: [
          (index: 2, newContent: '精简后的 T1'),
          (index: 4, newContent: 'assistant 不应被改写'),
          (index: 5, newContent: '精简后的 T2'),
        ],
      );
      final session = await setupWithCompactionEvent(
        historyUserCount: 2,
        event: event,
      );

      final msgs = session.agentMessages;
      // 前置：布局符合预期 [M, T1, u2, A2, T2, ...]
      expect(msgs[0].role, 'system', reason: '头部是压缩提示');
      expect(msgs[1].role, 'tool', reason: 'T1 位置');
      expect(msgs[2].role, 'user');
      expect(msgs[3].role, 'assistant');
      expect(msgs[4].role, 'tool', reason: 'T2 位置');

      // 正确落点：两条 tool 都被改写
      expect(msgs[1].content, '精简后的 T1',
          reason: 'T1 应被 entry(2) 改写（旧代码落到 marker 上被跳过，T1 保持超长原文）');
      expect(msgs[4].content, '精简后的 T2',
          reason: 'T2 应被 entry(5) 改写（旧代码落到 A2 上被 role 守卫跳过）');
      // assistant 不被波及
      expect(msgs[3].content, contains('回复: 历史消息'),
          reason: 'entry(4) 指向 assistant，应被 role 守卫跳过');
    });
  });
}
