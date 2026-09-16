/// Agent 场景上下文隔离单元测试
///
/// 锁定 2026-09-16 修复：`currentChatSessionIdProvider` 曾是全局单值，
/// writing 场景聊天写入的会话 id 会被 webview_extract 场景的
/// ScenarioSession 当作初始会话 hydrate——用户从阅读/写作切到浏览器
/// Tab，场景显示切过去了，聊天窗口里却是上一个场景的上下文。
///
/// 修复后 provider 按 scenarioId 隔离（StateProvider.family），
/// 本测试用内存 DB + 真实 ChatSessionRepository 走完整 hydrate 链路：
/// 1. 新场景懒创建时只 hydrate 自己场景的最近会话（回归主 bug）
/// 2. 切回原场景，之前的上下文原样保留（内存 session 不被清掉）
/// 3. 一个场景写入"当前会话 id"不影响其他场景的值
/// 4. AgentChatNotifier.switchScenario（Tab 自动切换的兼容层入口）
///    切换后 state 携带目标场景自己的上下文
///
/// 运行:
///   flutter test test/unit/core/providers/scenario_context_isolation_test.dart
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/agent_chat_providers.dart';
import 'package:novel_app/core/providers/agent_scenario_provider.dart';
import 'package:novel_app/core/providers/chat_session_providers.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/scenario_session.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/models/chat_message_record.dart';
import 'package:novel_app/models/chat_session.dart';
import 'package:novel_app/repositories/chat_session_repository.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:sqflite_common/sqflite.dart';

import '../../../helpers/test_database_setup.dart';

/// 反复让出事件循环，直到条件满足或超次（fire-and-forget hydrate 推进用）
Future<void> _pumpUntil(bool Function() cond) async {
  for (var i = 0; i < 200 && !cond(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late ProviderContainer container;
  late ChatSessionRepository repo;
  late Database db;

  setUp(() async {
    db = await TestDatabaseSetup.createInMemoryDatabase();
    await db.execute('PRAGMA foreign_keys = ON');
    repo = ChatSessionRepository(
        dbConnection: DatabaseConnection.forTesting(db));
    container = ProviderContainer(overrides: [
      chatSessionRepositoryProvider.overrideWithValue(repo),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// 在 DB 里给指定场景造一条会话 + 一条 user 消息
  Future<int> seedSession(String scenarioId, String marker) async {
    final sid = await repo.createSession(
      ChatSession(scenarioId: scenarioId, title: '$scenarioId 会话'),
    );
    await repo.appendMessage(ChatMessageRecord(
      sessionId: sid,
      agentMsgIndex: 0,
      role: 'user',
      content: marker,
      timestamp: DateTime.now(),
    ));
    return sid;
  }

  group('场景上下文隔离（currentChatSessionIdProvider 按 scenarioId 隔离）', () {
    test('新场景懒创建只 hydrate 自己场景的最近会话，不继承其他场景上下文',
        () async {
      final writingId =
          await seedSession(ScenarioIds.writing, '写作场景的历史上下文');
      final webviewId =
          await seedSession(ScenarioIds.webviewExtract, '浏览器场景的历史上下文');

      // 模拟用户刚在 writing 场景聊过：该场景 scoped 的"当前会话"指向写作会话
      container
          .read(currentChatSessionIdProvider(ScenarioIds.writing).notifier)
          .state = writingId;

      // 模拟 Tab 切到浏览器（自动切换路径：懒创建 webview session）
      final webviewSession = container
          .read(scenarioSessionsProvider.notifier)
          .get(ScenarioIds.webviewExtract);
      await _pumpUntil(() => webviewSession.agentMessages.isNotEmpty);

      // 关键断言：拿到的是浏览器自己的会话，不是写作会话
      expect(webviewSession.sessionId, webviewId,
          reason: 'webview_extract 场景绝不能采用 writing 场景选中的会话 id');
      final contents =
          webviewSession.agentMessages.map((m) => m.content).join();
      expect(contents, contains('浏览器场景的历史上下文'));
      expect(contents, isNot(contains('写作场景的历史上下文')),
          reason: '跨场景上下文串台 = 本修复针对的 bug');
    });

    test('切回原场景，之前的上下文原样保留', () async {
      await seedSession(ScenarioIds.webviewExtract, '浏览器场景的历史上下文');
      final writingId =
          await seedSession(ScenarioIds.writing, '写作场景的历史上下文');
      container
          .read(currentChatSessionIdProvider(ScenarioIds.writing).notifier)
          .state = writingId;

      final sessions = container.read(scenarioSessionsProvider.notifier);
      final writingSession = sessions.get(ScenarioIds.writing);
      await _pumpUntil(() => writingSession.agentMessages.isNotEmpty);

      // 切走再切回
      sessions.get(ScenarioIds.webviewExtract);
      final back = sessions.get(ScenarioIds.writing);

      expect(identical(back, writingSession), isTrue,
          reason: '切回同一场景必须复用同一个 ScenarioSession 实例');
      final contents = back.agentMessages.map((m) => m.content).join();
      expect(contents, contains('写作场景的历史上下文'),
          reason: '切回原场景要能看到之前的上下文');
      expect(contents, isNot(contains('浏览器场景的历史上下文')));
    });

    test('一个场景写入当前会话 id，不影响其他场景的 scoped 值', () {
      expect(container.read(currentChatSessionIdProvider(ScenarioIds.writing)),
          isNull);
      expect(
          container.read(
              currentChatSessionIdProvider(ScenarioIds.webviewExtract)),
          isNull);

      container
          .read(currentChatSessionIdProvider(ScenarioIds.writing).notifier)
          .state = 42;

      expect(container.read(currentChatSessionIdProvider(ScenarioIds.writing)),
          42);
      expect(
          container.read(
              currentChatSessionIdProvider(ScenarioIds.webviewExtract)),
          isNull,
          reason: 'scoped 隔离是修复的根基：writing 的会话 id 不可见于 webview_extract');
    });

    test('switchScenario（Tab 自动切换入口）后兼容层 state 携带目标场景自己的上下文',
        () async {
      final writingId =
          await seedSession(ScenarioIds.writing, '写作场景的历史上下文');
      final webviewId =
          await seedSession(ScenarioIds.webviewExtract, '浏览器场景的历史上下文');
      container
          .read(currentChatSessionIdProvider(ScenarioIds.writing).notifier)
          .state = writingId;

      // 创建兼容层（初始场景 writing），并让 writing session hydrate 完成
      final chatNotifier = container.read(agentChatProvider.notifier);
      final sessions = container.read(scenarioSessionsProvider.notifier);
      final writingSession = sessions.get(ScenarioIds.writing);
      await _pumpUntil(() => writingSession.agentMessages.isNotEmpty);

      // 模拟 main.dart Tab 切换触发的自动切换
      chatNotifier.switchScenario(ScenarioIds.webviewExtract, '网页提取');
      await _pumpUntil(() =>
          container.read(agentChatProvider).scenarioId ==
              ScenarioIds.webviewExtract &&
          container.read(agentChatProvider).messages.isNotEmpty);

      final state = container.read(agentChatProvider);
      expect(state.scenarioId, ScenarioIds.webviewExtract);
      final webviewSession =
          sessions.getIfExists(ScenarioIds.webviewExtract)!;
      expect(webviewSession.sessionId, webviewId);
      // 兼容层 state 与 webview session 同源：消息条数一致且不含写作上下文
      expect(state.messages.length,
          webviewSession.state.messages.length);
      final sessionContents =
          webviewSession.agentMessages.map((m) => m.content).join();
      expect(sessionContents, contains('浏览器场景的历史上下文'));
      expect(sessionContents, isNot(contains('写作场景的历史上下文')));

      // 切回 writing：写作上下文还在
      chatNotifier.switchScenario(ScenarioIds.writing, '小说写作助手');
      await _pumpUntil(() =>
          container.read(agentChatProvider).scenarioId ==
              ScenarioIds.writing);
      expect(container.read(agentChatProvider).scenarioId,
          ScenarioIds.writing);
      expect(
        sessions.getIfExists(ScenarioIds.writing)!.agentMessages
            .map((m) => m.content)
            .join(),
        contains('写作场景的历史上下文'),
        reason: '切回 writing 要能看到之前的上下文',
      );
    });
  });
}
