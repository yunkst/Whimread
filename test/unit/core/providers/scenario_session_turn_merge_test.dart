/// 回合级气泡合并的端到端回归测试
///
/// 背景：一个回合在 agent 协议里会被拆成多条 assistant 消息（每轮工具调用
/// 一条 + 各自的 tool 结果），finalize 后经 _projectUiMessages 投影到 UI。
/// 合并前该回合会渲染成 N+1 个气泡，与流式期间（一个尾部气泡）不一致。
/// 修复后：相邻 user 之间的连续 assistant 消息合并为一条，segments 形状
/// 与流式 _pendingSegments 对齐；rollbackToMessage 的 UI 索引映射同步按
/// 回合组计数。
///
/// 运行:
///   flutter test test/unit/core/providers/scenario_session_turn_merge_test.dart
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/models/agent_chat_message.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/novel_agent_service.dart';
import 'package:novel_app/utils/cancellation_token.dart';

/// 脚本化 fake：sendMessage 时按脚本依次 emit 事件（脚本尾部自动补 AgentDone）
class ScriptedAgentService implements NovelAgentService {
  final _controller = StreamController<AgentEvent>.broadcast();
  final Map<String, Completer<void>> _completers = {};
  final Map<String, bool> _runningByScenario = {};

  /// 每轮 sendMessage 对应一份事件脚本（不含 AgentDone，由 fake 追加）
  final List<List<AgentEvent>> scripts = [];

  @override
  Ref get ref => throw UnimplementedError();

  @override
  bool get isRunning => _runningByScenario.values.any((v) => v);

  @override
  bool isRunningFor(String scenarioId) => _runningByScenario[scenarioId] == true;

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
    if (_runningByScenario[scenarioId] == true) {
      _controller.add(AgentErrorEvent('场景 $scenarioId 的 Agent 正在运行中'));
      return;
    }
    _runningByScenario[scenarioId] = true;
    final completer = Completer<void>();
    _completers[scenarioId] = completer;
    final script = scripts.isEmpty ? <AgentEvent>[] : scripts.removeAt(0);
    try {
      // 等一帧让 ScenarioSession 的 listen 先注册上
      await Future<void>.delayed(Duration.zero);
      for (final e in script) {
        _controller.add(e);
        await Future<void>.delayed(Duration.zero);
      }
      _controller.add(const AgentDoneEvent());
      await Future<void>.delayed(Duration.zero);
    } finally {
      _runningByScenario.remove(scenarioId);
      _completers.remove(scenarioId);
      if (!completer.isCompleted) completer.complete();
    }
  }

  @override
  Future<void> resumeFromMessages({
    required String scenarioId,
    required List<dynamic> initialMessages,
    required AgentScenarioContext scenarioContext,
    String? runId,
  }) async {
    if (_runningByScenario[scenarioId] == true) {
      _controller.add(AgentErrorEvent('场景 $scenarioId 的 Agent 正在运行中'));
      return;
    }
    _runningByScenario[scenarioId] = true;
    final completer = Completer<void>();
    _completers[scenarioId] = completer;
    try {
      await Future<void>.delayed(Duration.zero);
      for (final e in scripts.isEmpty ? <AgentEvent>[] : scripts.removeAt(0)) {
        _controller.add(e);
        await Future<void>.delayed(Duration.zero);
      }
      _controller.add(const AgentDoneEvent());
      await Future<void>.delayed(Duration.zero);
    } finally {
      _runningByScenario.remove(scenarioId);
      _completers.remove(scenarioId);
      if (!completer.isCompleted) completer.complete();
    }
  }

  @override
  void cancelFor(String scenarioId) {
    final completer = _completers[scenarioId];
    if (completer != null && !completer.isCompleted) completer.complete();
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
  void addEvent(AgentEvent event) => _controller.add(event);

  @override
  void injectUserMessage(String scenarioId, String text) {}

  @override
  void dispose() => _controller.close();
}

/// 一次「文本1 → 工具1 → 文本2 → 工具2 → 文本3」的多轮工具回合
List<AgentEvent> multiRoundTurn(String tag) => [
      TextDeltaEvent('文本1$tag'),
      ToolCallStartEvent('read_chapter', const {}, 'c1_$tag'),
      ToolCallEndEvent('read_chapter', 'c1_$tag', '章节内容',
          fullResult: '章节内容'),
      TextDeltaEvent('文本2$tag'),
      ToolCallStartEvent('create_chapter', const {}, 'c2_$tag'),
      ToolCallEndEvent('create_chapter', 'c2_$tag', '已创建',
          fullResult: '已创建'),
      TextDeltaEvent('文本3$tag'),
    ];

void main() {
  late ScriptedAgentService service;
  late ProviderContainer container;

  setUp(() {
    service = ScriptedAgentService();
    container = ProviderContainer(overrides: [
      novelAgentServiceProvider.overrideWith((ref) => service),
    ]);
  });

  tearDown(() {
    container.dispose();
  });

  group('多轮工具回合合并为一个气泡', () {
    test('回合结束后 5 段内容（文本/工具交替）合并为一条 assistant 消息', () async {
      final session =
          container.read(scenarioSessionsProvider.notifier).get(ScenarioIds.writing);
      service.scripts.add(multiRoundTurn('A'));

      await session.sendMessage(content: '写第一章');

      final messages = session.state.messages;
      expect(messages, hasLength(2),
          reason: 'user + 合并后的 assistant，两次工具调用不应拆出 3 个气泡');
      expect(messages[0].role, AgentChatRole.user);
      expect(messages[1].role, AgentChatRole.assistant);

      final segs = messages[1].segments;
      expect(segs, hasLength(5));
      expect((segs[0] as TextSegment).content, '文本1A');
      expect((segs[1] as ToolCallSegment).call.id, 'c1_A');
      expect((segs[2] as TextSegment).content, '文本2A');
      expect((segs[3] as ToolCallSegment).call.id, 'c2_A');
      expect((segs[4] as TextSegment).content, '文本3A');
      // 工具段已结束 → completed（终态不再残留 running）
      for (final s in segs.whereType<ToolCallSegment>()) {
        expect(s.call.status, AgentToolStatus.completed);
      }
    });

    test('合并后的 segments 形状与回合流式时一致', () async {
      final session =
          container.read(scenarioSessionsProvider.notifier).get(ScenarioIds.writing);
      service.scripts.add(multiRoundTurn('B'));
      await session.sendMessage(content: '写第一章');

      // 回合进行中：streamingSegments 就是流式时序
      final session2 =
          container.read(scenarioSessionsProvider.notifier).get(ScenarioIds.writing);

      expect(session2.state.streamingSegments, isEmpty,
          reason: '回合已结束，流式段已清空');

      // 终态消息的 segments 形状应与流式 [text, tool, text, tool, text] 一致
      final shape = session2.state.messages[1].segments
          .map((s) => s is TextSegment ? 'text' : 'tool')
          .toList();
      expect(shape, ['text', 'tool', 'text', 'tool', 'text']);
    });

    test('第二个回合作为 user 边界，渲染成独立的第二个 assistant 气泡', () async {
      final session =
          container.read(scenarioSessionsProvider.notifier).get(ScenarioIds.writing);
      service.scripts
        ..add(multiRoundTurn('X'))
        ..add(multiRoundTurn('Y'));

      await session.sendMessage(content: '第一问');
      await session.sendMessage(content: '第二问');

      final messages = session.state.messages;
      expect(messages, hasLength(4));
      expect(messages.map((m) => m.role).toList(), [
        AgentChatRole.user,
        AgentChatRole.assistant,
        AgentChatRole.user,
        AgentChatRole.assistant,
      ]);
      expect((messages[1].segments.first as TextSegment).content, '文本1X');
      expect((messages[3].segments.first as TextSegment).content, '文本1Y');
    });

    test('合并后回滚到第二个 user 仍定位正确（UI 索引按回合组计数）', () async {
      final session =
          container.read(scenarioSessionsProvider.notifier).get(ScenarioIds.writing);
      service.scripts
        ..add(multiRoundTurn('X'))
        ..add(multiRoundTurn('Y'));

      await session.sendMessage(content: '第一问');
      await session.sendMessage(content: '第二问');
      expect(session.state.messages, hasLength(4));

      // UI index 2 = 第二条 user（第一回合的多条 assistant 合并为 1 条，
      // 因此第二条 user 的 UI 索引不会因工具轮次而偏移）
      String? callbackContent;
      final result = await session.rollbackToMessage(
        2,
        contentCallback: (c) => callbackContent = c,
      );

      expect(result, isTrue);
      expect(callbackContent, '第二问');
      // 回滚后应保留第一回合：user + 合并后的 assistant
      final remaining = session.state.messages;
      expect(remaining, hasLength(2));
      expect(remaining[0].role, AgentChatRole.user);
      expect(remaining[0].content, '第一问');
      expect(remaining[1].role, AgentChatRole.assistant);
      expect(remaining[1].segments, hasLength(5),
          reason: '第一回合的 5 段内容应完整保留');
    });
  });
}
