import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/models/chat_message_record.dart';
import 'package:novel_app/models/chat_session.dart';
import 'package:novel_app/repositories/chat_session_repository.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';

import '../../helpers/test_database_setup.dart';

/// ChatSessionRepository 集成测试（v32 统一历史模型）
///
/// 覆盖：
/// - createSession / listSessionsByScenario / getSession / renameSession
/// - deleteSession（FK CASCADE 自动清消息）
/// - appendMessage 写完整 agent ChatMessage（含 toolCalls/toolCallId/agentMsgIndex）
/// - fromAgentMessage / toAgentMessage round-trip
/// - deleteMessagesBefore（压缩/retry/rollback 用）
void main() {
  late ChatSessionRepository repo;

  setUp(() async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    final connection = DatabaseConnection.forTesting(db);
    await db.execute('PRAGMA foreign_keys = ON');
    repo = ChatSessionRepository(dbConnection: connection);
  });

  group('ChatSessionRepository', () {
    test('createSession + getSession round-trip', () async {
      final id = await repo.createSession(ChatSession(
        scenarioId: 'writing',
        title: '测试会话',
        currentNovelId: 42,
        currentNovelTitle: '测试书',
      ));
      expect(id, greaterThan(0));

      final session = await repo.getSession(id);
      expect(session, isNotNull);
      expect(session!.scenarioId, 'writing');
      expect(session.title, '测试会话');
      expect(session.currentNovelId, 42);
      expect(session.currentNovelTitle, '测试书');
    });

    test('listSessionsByScenario 按 scenarioId 过滤 + 按 updatedAt DESC 排序',
        () async {
      // 显式设 updatedAt（而非依赖 DateTime.now() 默认值）：
      // 两次 createSession 间隔可能 <1ms，默认 updatedAt 相同会让 DESC 排序不稳定（flaky）。
      final idA = await repo.createSession(ChatSession(
        scenarioId: 'writing',
        title: 'A',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
      final idB = await repo.createSession(ChatSession(
        scenarioId: 'writing',
        title: 'B',
        createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      ));
      await repo.createSession(ChatSession(
        scenarioId: 'webview_extract',
        title: 'C',
      ));

      final list = await repo.listSessionsByScenario('writing');
      expect(list.length, 2);
      expect(list.map((e) => e.id).toList(), [idB, idA]);
    });

    test('appendMessage + listMessages 按 agentMsgIndex ASC 还原顺序', () async {
      final sid = await repo.createSession(
          ChatSession(scenarioId: 'writing', title: 't'));
      final before = await repo.getSession(sid);
      await Future.delayed(const Duration(milliseconds: 5));

      await repo.appendMessage(ChatMessageRecord.fromAgentMessage(
          sid, 0, ChatMessage(role: 'user', content: 'hi')));
      await repo.appendMessage(ChatMessageRecord.fromAgentMessage(
          sid, 1, ChatMessage(role: 'assistant', content: 'hello')));
      await repo.appendMessage(ChatMessageRecord.fromAgentMessage(
          sid,
          2,
          ChatMessage(
              role: 'tool', content: '{"ok":true}', toolCallId: 'c1')));

      final messages = await repo.listMessages(sid);
      expect(messages.length, 3);
      expect(messages[0].role, 'user');
      expect(messages[1].role, 'assistant');
      expect(messages[2].role, 'tool');
      expect(messages.map((m) => m.agentMsgIndex).toList(), [0, 1, 2]);
      expect(messages[2].toolCallId, 'c1');

      final after = await repo.getSession(sid);
      expect(after!.updatedAt.isAfter(before!.updatedAt), isTrue);
      expect(await repo.getMessageCount(sid), 3);
    });

    test('agent ChatMessage 含 toolCalls 能完整 round-trip', () async {
      final sid = await repo.createSession(
          ChatSession(scenarioId: 'writing', title: 'tool rt'));

      final original = ChatMessage(
        role: 'assistant',
        content: '我先想一下',
        toolCalls: [
          ToolCall(id: 'call-1', name: 'search_novel', arguments: {'query': '修仙'}),
          ToolCall(id: 'call-2', name: 'select_novel', arguments: {'novelId': 7}),
        ],
      );
      await repo.appendMessage(
          ChatMessageRecord.fromAgentMessage(sid, 0, original));

      final loaded = (await repo.listMessages(sid)).first;
      final restored = loaded.toAgentMessage();
      expect(restored.role, 'assistant');
      expect(restored.content, '我先想一下');
      expect(restored.toolCalls!.length, 2);
      expect(restored.toolCalls![0].id, 'call-1');
      expect(restored.toolCalls![0].name, 'search_novel');
      expect(restored.toolCalls![0].arguments['query'], '修仙');
      expect(restored.toolCalls![1].name, 'select_novel');
    });

    test('assistant 只有 toolCalls 无 content 时 round-trip 保持 null', () async {
      final sid = await repo.createSession(
          ChatSession(scenarioId: 'writing', title: 'null content'));
      final original = ChatMessage(
        role: 'assistant',
        content: null,
        toolCalls: [ToolCall(id: 'x', name: 't', arguments: {})],
      );
      await repo.appendMessage(
          ChatMessageRecord.fromAgentMessage(sid, 0, original));

      final restored = (await repo.listMessages(sid)).first.toAgentMessage();
      expect(restored.role, 'assistant');
      expect(restored.content, isNull);
      expect(restored.toolCalls!.length, 1);
    });

    test('toolCallsJson 坏数据降级为 null（不抛异常）', () async {
      final sid = await repo.createSession(
          ChatSession(scenarioId: 'writing', title: 'bad json'));
      await repo.appendMessage(ChatMessageRecord(
        sessionId: sid,
        role: 'assistant',
        content: 'x',
        toolCallsJson: '{broken json',
        agentMsgIndex: 0,
      ));
      final restored = (await repo.listMessages(sid)).first.toAgentMessage();
      expect(restored.toolCalls, isNull);
      expect(restored.content, 'x');
    });

    test('deleteMessagesBefore 删除指定索引前的消息', () async {
      final sid = await repo.createSession(
          ChatSession(scenarioId: 'writing', title: 'deleteBefore'));
      for (var i = 0; i < 5; i++) {
        await repo.appendMessage(ChatMessageRecord.fromAgentMessage(
            sid, i, ChatMessage(role: 'user', content: 'm$i')));
      }
      expect(await repo.getMessageCount(sid), 5);

      final deleted = await repo.deleteMessagesBefore(sid, 3);
      expect(deleted, 3);

      final remaining = await repo.listMessages(sid);
      expect(remaining.length, 2);
      expect(remaining.map((m) => m.agentMsgIndex).toList(), [3, 4]);
    });

    test('deleteSession 经 FK CASCADE 自动删 messages', () async {
      final sid = await repo.createSession(
          ChatSession(scenarioId: 'writing', title: 'CASCADE'));
      await repo.appendMessage(ChatMessageRecord.fromAgentMessage(
          sid, 0, ChatMessage(role: 'user', content: 'm1')));
      await repo.appendMessage(ChatMessageRecord.fromAgentMessage(
          sid, 1, ChatMessage(role: 'assistant', content: 'm2')));
      expect(await repo.getMessageCount(sid), 2);

      final affected = await repo.deleteSession(sid);
      expect(affected, 1);
      expect(await repo.getSession(sid), isNull);
      expect(await repo.getMessageCount(sid), 0);
    });

    test('listMessages 分页 limit/offset', () async {
      final sid = await repo.createSession(
          ChatSession(scenarioId: 'writing', title: 'paging'));
      for (var i = 0; i < 10; i++) {
        await repo.appendMessage(ChatMessageRecord.fromAgentMessage(
            sid, i, ChatMessage(role: 'user', content: 'm$i')));
      }
      final page = await repo.listMessages(sid, limit: 3, offset: 2);
      expect(page.length, 3);
      expect(page.map((m) => m.agentMsgIndex).toList(), [2, 3, 4]);
    });

    test('touchSession 单独刷 updatedAt', () async {
      final sid = await repo.createSession(
          ChatSession(scenarioId: 'writing', title: 'touch'));
      final before = await repo.getSession(sid);
      await Future.delayed(const Duration(milliseconds: 5));
      await repo.touchSession(sid);
      final after = await repo.getSession(sid);
      expect(after!.updatedAt.isAfter(before!.updatedAt), isTrue);
    });

    test('updateMessageContent 覆盖单条消息 content（重试落库）', () async {
      final sid = await repo.createSession(
          ChatSession(scenarioId: 'writing', title: 'retry update'));
      // 先写一条 tool 消息
      await repo.appendMessage(ChatMessageRecord.fromAgentMessage(
          sid,
          0,
          ChatMessage(
              role: 'tool', content: '{"old":true}', toolCallId: 'c1')));
      final before = await repo.getSession(sid);
      await Future.delayed(const Duration(milliseconds: 5));

      final messages = await repo.listMessages(sid);
      final msgId = messages.first.id!;
      final affected = await repo.updateMessageContent(msgId, '{"new":true}');

      expect(affected, 1);
      final reloaded = await repo.listMessages(sid);
      expect(reloaded.first.content, '{"new":true}',
          reason: 'content 应被新结果覆盖');

      final after = await repo.getSession(sid);
      expect(
          after!.updatedAt == before!.updatedAt,
          isTrue,
          reason:
              'updateMessageContent 不应刷新 session.updatedAt（重试不改会话活跃度）');
    });

    test('updateMessageContent 不存在的 messageId 返回 0（不抛异常）', () async {
      final affected = await repo.updateMessageContent(99999, '{"x":1}');
      expect(affected, 0);
    });
  });
}
