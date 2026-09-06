/// ScenarioSession hydrate 集成测试（Task 6）
///
/// 覆盖「DB → ChatMessageRecord → ChatMessage → _projectUiMessages」契约链：
/// - 写一条压缩提示 system 消息到 DB（含 `[上下文压缩|...]` 前缀 + 全部必填 KV）
/// - 用 ChatSessionRepository 读出 ChatMessageRecord
/// - 每条记录 toAgentMessage() 后塞进 ScenarioSession.projectUiMessagesForTest
/// - 断言 UI 投影结果含 AgentChatRole.marker
///
/// 这是不变量 #3（marker 渲染不依赖 CompactionEvent）和
/// #4（内存路径与 hydrate 路径走同一个 _projectUiMessages）的关键证明：
/// hydrate 后历史里的压缩提示会自动渲染成 marker，**不依赖运行时再触发 CompactionEvent**，
/// 也**复用**同一个投影函数（与 Task 5 验证的内存路径完全一致）。
///
/// 不构造 ScenarioSession 实例本身——hydrate 的核心是 DB→投影链，
/// 单独验证这条链而不依赖 Riverpod Ref / 事件流 / LLM 调用更稳定。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/core/providers/scenario_session_hydrate_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/scenario_session.dart';
import 'package:novel_app/models/agent_chat_message.dart';
import 'package:novel_app/models/chat_message_record.dart';
import 'package:novel_app/models/chat_session.dart';
import 'package:novel_app/repositories/chat_session_repository.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';

import '../../../helpers/test_database_setup.dart';

void main() {
  late ChatSessionRepository repo;

  setUp(() async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    final connection = DatabaseConnection.forTesting(db);
    await db.execute('PRAGMA foreign_keys = ON');
    repo = ChatSessionRepository(dbConnection: connection);
  });

  group('hydrate 路径投影压缩提示为 marker', () {
    test('DB 中含压缩提示 system → listMessages + toAgentMessage + 投影后含 marker',
        () async {
      // 1) 建 session
      final sid = await repo.createSession(
        ChatSession(scenarioId: 'writing', title: 'hydrate marker test'),
      );

      // 2) 写入压缩提示 system 消息（KV 全字段）
      const compactionNote =
          '[上下文压缩|droppedCount=3|keptCount=2|removedChars=420000|'
          'originalChars=580000|compactedChars=160000|rewrittenCount=2|'
          'timestamp=1706000101]\n后续继续写作。';
      await repo.appendMessage(ChatMessageRecord(
        sessionId: sid,
        agentMsgIndex: 0,
        role: 'system',
        content: compactionNote,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1706000101000),
      ));
      // 3) 再追加一条 user 消息确保 listMessages 还原顺序
      await repo.appendMessage(ChatMessageRecord(
        sessionId: sid,
        agentMsgIndex: 1,
        role: 'user',
        content: '继续',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1706000201000),
      ));

      // 4) hydrate 路径：DB → ChatMessageRecord
      final records = await repo.listMessages(sid);
      expect(records, hasLength(2));
      expect(records.first.role, 'system',
          reason: '第一条必须是 system 压缩提示');
      expect(records.first.content, compactionNote);

      // 5) hydrate 路径：ChatMessageRecord → ChatMessage（保留 role='system'）
      final agentMessages = records.map((r) => r.toAgentMessage()).toList();
      expect(agentMessages.first.role, 'system',
          reason: 'toAgentMessage 必须原样保留 role=system，'
              '否则压缩提示会被投影层当成普通 system 跳过');
      expect(agentMessages.first.content, compactionNote);
      expect(agentMessages[1].role, 'user');
      expect(agentMessages[1].content, '继续');

      // 6) hydrate 路径：ChatMessage → UI 投影（与内存路径同一函数）
      final ui = ScenarioSession.projectUiMessagesForTest(agentMessages);

      // 7) 不变量 #3：UI 含 marker（**不依赖** CompactionEvent，DB 字段即可）
      expect(
        ui.any((m) => m.role == AgentChatRole.marker),
        isTrue,
        reason: 'hydrate 后压缩提示必须投影为 marker，重启 APP 也能看到',
      );

      // 8) 进一步验证 marker 内的 segment 字段都被正确解析
      final marker = ui.firstWhere((m) => m.role == AgentChatRole.marker);
      expect(marker.segments.single, isA<CompactionMarkerSegment>());
      final seg = marker.segments.single as CompactionMarkerSegment;
      expect(seg.droppedMessageCount, 3);
      expect(seg.keptMessageCount, 2);
      expect(seg.removedChars, 420000);
      expect(seg.originalChars, 580000);
      expect(seg.compactedChars, 160000);
      expect(seg.rewrittenCount, 2);
      expect(seg.timestamp, isNotNull);

      // 9) 第二条 user 消息仍在 UI 中（不被 marker 吞掉）
      expect(ui.where((m) => m.role == AgentChatRole.user), hasLength(1));
      expect(ui.last.role, AgentChatRole.user);
    });

    test('hydrate 多条普通 system 不污染 marker（普通 system 被投影层 continue）',
        () async {
      final sid = await repo.createSession(
        ChatSession(scenarioId: 'writing', title: 'mixed system'),
      );
      // 普通 system → 投影层 continue，不进 UI
      await repo.appendMessage(ChatMessageRecord(
        sessionId: sid,
        agentMsgIndex: 0,
        role: 'system',
        content: 'You are a helpful writer.',
        timestamp: DateTime.fromMillisecondsSinceEpoch(100),
      ));
      // 压缩提示 system → marker
      await repo.appendMessage(ChatMessageRecord(
        sessionId: sid,
        agentMsgIndex: 1,
        role: 'system',
        content: '[上下文压缩|droppedCount=1|keptCount=2|removedChars=3|'
            'originalChars=4|compactedChars=5|rewrittenCount=0|timestamp=6]',
        timestamp: DateTime.fromMillisecondsSinceEpoch(200),
      ));
      // user 消息
      await repo.appendMessage(ChatMessageRecord(
        sessionId: sid,
        agentMsgIndex: 2,
        role: 'user',
        content: 'hi',
        timestamp: DateTime.fromMillisecondsSinceEpoch(300),
      ));

      final records = await repo.listMessages(sid);
      final agentMessages = records.map((r) => r.toAgentMessage()).toList();
      final ui = ScenarioSession.projectUiMessagesForTest(agentMessages);

      // 只有 marker + user，普通 system 被 continue 掉
      expect(ui, hasLength(2));
      expect(ui[0].role, AgentChatRole.marker);
      expect(ui[1].role, AgentChatRole.user);
    });

    test('与内存路径一致：同一 ChatMessage 列表两种方式获得的 marker 相同', () async {
      // 不变量 #4：内存路径（_handleCompaction 后 _projectUiMessages）和 hydrate 路径
      // 用的是同一个 _projectUiMessages 函数，所以同样的 agent messages 得到同样的 UI。
      final agentMessages = <ChatMessage>[
        const ChatMessage(
          role: 'system',
          content: '[上下文压缩|droppedCount=7|keptCount=8|removedChars=9|'
              'originalChars=10|compactedChars=11|rewrittenCount=1|timestamp=12]',
        ),
        const ChatMessage(role: 'user', content: '续写'),
      ];
      final ui = ScenarioSession.projectUiMessagesForTest(agentMessages);

      expect(ui.first.role, AgentChatRole.marker);
      final seg = ui.first.segments.single as CompactionMarkerSegment;
      expect(seg.droppedMessageCount, 7);
      expect(ui.last.role, AgentChatRole.user);
    });

    test('空 hydrate 不抛异常，投影结果为空', () async {
      final sid = await repo.createSession(
        ChatSession(scenarioId: 'writing', title: 'empty session'),
      );
      final records = await repo.listMessages(sid);
      final agentMessages = records.map((r) => r.toAgentMessage()).toList();
      final ui = ScenarioSession.projectUiMessagesForTest(agentMessages);
      expect(ui, isEmpty);
    });
  });
}