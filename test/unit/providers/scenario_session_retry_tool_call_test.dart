/// ScenarioSession.retryToolCall 单元测试（拒绝路径 + 落库一致性）
///
/// 覆盖：
/// - 无 sessionId 时拒绝
/// - 找不到 toolCallId 时拒绝
/// - dispatch_subagent 拒绝（即便历史里真有，本层再守一道）
/// - webview_extract 场景拒绝
///
/// happy path（真正重跑 WritingScenario.executeTool）依赖 ToolExecutor 的
/// 大量 Repository/Service 链路，本测试不覆盖；其落库一致性由
/// chat_session_repository_test.dart 的 updateMessageContent 用例保证。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/providers/scenario_session_retry_tool_call_test.dart
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/models/agent_chat_message.dart';
import 'package:novel_app/models/chat_message_record.dart';
import 'package:novel_app/models/chat_session.dart';
import 'package:novel_app/repositories/chat_session_repository.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/novel_agent_service.dart';

import '../../helpers/test_database_setup.dart';

// ---------------------------------------------------------------------------
// MockNovelAgentService — 与 scenario_session_test 同款，仅用于让 ScenarioSession
// 能跑通 sendMessage（创建 sessionId）+ 不依赖真实 LLM。
// ---------------------------------------------------------------------------

class _MockNovelAgentService implements NovelAgentService {
  final _controller = StreamController<AgentEvent>.broadcast();
  final Map<String, bool> _running = {};

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
      await Future<void>.delayed(Duration.zero);
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
  void cancelFor(String scenarioId) => _running.remove(scenarioId);

  @override
  void cancelAll() => _running.clear();

  @override
  void addEvent(AgentEvent event) => _controller.add(event);

  @override
  void dispose() => _controller.close();

  @override
  void injectUserMessage(String scenarioId, String text) {}
}

// ---------------------------------------------------------------------------
// 测试
// ---------------------------------------------------------------------------

void main() {
  late _MockNovelAgentService mock;
  late ProviderContainer container;

  setUp(() async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    final repo =
        ChatSessionRepository(dbConnection: DatabaseConnection.forTesting(db));
    mock = _MockNovelAgentService();
    container = ProviderContainer(overrides: [
      novelAgentServiceProvider.overrideWith((ref) => mock),
      chatSessionRepositoryProvider.overrideWith((ref) => repo),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await DatabaseConnection.resetInstance();
  });

  group('retryToolCall 拒绝路径', () {
    test('无 sessionId 时拒绝并设置 error 提示', () async {
      final session = container
          .read(scenarioSessionsProvider.notifier)
          .get(ScenarioIds.writing);

      // 不发任何消息 → sessionId 为 null
      expect(session.sessionId, isNull);
      await session.retryToolCall('any-id');
      expect(session.state.error, '当前会话未保存，无法重试');
    });

    test('找不到 toolCallId 时拒绝', () async {
      final session = container
          .read(scenarioSessionsProvider.notifier)
          .get(ScenarioIds.writing);

      // 发一条消息让 sessionId 创建（mock 回 TextDelta + Done，无工具调用）
      await session.sendMessage(content: 'hello');
      expect(session.sessionId, isNotNull, reason: '发过消息后应有 sessionId');

      await session.retryToolCall('not-found-id');
      expect(session.state.error, '找不到该工具调用');
    });

    test('dispatch_subagent 调用拒绝重试（即便历史里有这条 toolCall）', () async {
      // 直接往 DB 注入一段含 dispatch_subagent 的历史，再 hydrate。
      final repo = container.read(chatSessionRepositoryProvider);
      final sid = await repo.createSession(
          ChatSession(scenarioId: ScenarioIds.writing, title: 'subagent'));
      await repo.appendMessage(ChatMessageRecord.fromAgentMessage(
          sid, 0, ChatMessage(role: 'user', content: '派个子任务')));
      await repo.appendMessage(ChatMessageRecord.fromAgentMessage(
          sid,
          1,
          ChatMessage(
            role: 'assistant',
            content: '好的',
            toolCalls: [
              ToolCall(
                  id: 'sa1',
                  name: 'dispatch_subagent',
                  arguments: {'task': '查资料'}),
            ],
          )));
      await repo.appendMessage(ChatMessageRecord.fromAgentMessage(
          sid,
          2,
          ChatMessage(
              role: 'tool',
              content: '{"status":"done"}',
              toolCallId: 'sa1')));

      final session = container
          .read(scenarioSessionsProvider.notifier)
          .get(ScenarioIds.writing);
      // 切到这条 session，触发 hydrate
      await session.adoptSession(sid);
      await session.hydrateIfNeeded();

      expect(session.sessionId, sid);
      // hydrate 后应能看到这条 assistant 工具调用
      final hasSubagent = session.state.messages.any((m) =>
          m.segments.whereType<ToolCallSegment>().any(
              (s) => s.call.name == 'dispatch_subagent'));
      expect(hasSubagent, isTrue, reason: 'hydrate 应还原 dispatch_subagent 调用');

      await session.retryToolCall('sa1');
      // dispatch_subagent 被拒绝：不应抛异常，error 为 null（静默拒绝，无误导提示）
      // 或携带提示。这里只断言：没有真的派子 Agent、tool 消息内容未变。
      final toolContent = session.state.messages
          .expand((m) => m.segments)
          .whereType<ToolCallSegment>()
          .firstWhere((s) => s.call.id == 'sa1')
          .call
          .result;
      expect(toolContent, '{"status":"done"}',
          reason: 'dispatch_subagent 拒绝重试后，原 tool 消息内容不应被改写');
    });

    test('webview_extract 场景拒绝重试', () async {
      final repo = container.read(chatSessionRepositoryProvider);
      final sid = await repo.createSession(
          ChatSession(scenarioId: ScenarioIds.webviewExtract, title: 'extract'));
      await repo.appendMessage(ChatMessageRecord.fromAgentMessage(
          sid, 0, ChatMessage(role: 'user', content: '提取正文')));
      await repo.appendMessage(ChatMessageRecord.fromAgentMessage(
          sid,
          1,
          ChatMessage(
            role: 'assistant',
            content: '',
            toolCalls: [
              ToolCall(
                  id: 'js1',
                  name: 'execute_js',
                  arguments: {'code': 'document.title'}),
            ],
          )));
      await repo.appendMessage(ChatMessageRecord.fromAgentMessage(
          sid,
          2,
          ChatMessage(
              role: 'tool',
              content: '{"title":"旧"}',
              toolCallId: 'js1')));

      final session = container
          .read(scenarioSessionsProvider.notifier)
          .get(ScenarioIds.webviewExtract);
      await session.adoptSession(sid);
      await session.hydrateIfNeeded();

      await session.retryToolCall('js1');
      expect(session.state.error, contains('网页提取工具'),
          reason: 'webview_extract 场景工具应拒绝重试并给出提示');
    });
  });
}
