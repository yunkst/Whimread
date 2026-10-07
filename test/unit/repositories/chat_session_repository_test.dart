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
  });
}
