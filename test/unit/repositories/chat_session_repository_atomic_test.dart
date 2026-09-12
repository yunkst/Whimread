/// ChatSessionRepository 事务原子性测试（appendMessages / replaceMessages）
///
/// 背景：此前 ScenarioSession 落库/重写消息走"逐条独立事务"，中途崩溃会留下
/// 断裂的 ReAct 链（assistant/tool 错位，直接破坏 hydrate 后的 LLM 上下文）。
/// 本文件验证：
/// - appendMessages：整批单事务、按序写入、空批不动 DB
/// - replaceMessages：原子重写（清空 + 整批写入同事务）、失败全量回滚
///   —— 用 FK 冲突制造"批量中途失败"，断言旧数据原样保留（事务性核心证据）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/models/chat_message_record.dart';
import 'package:novel_app/models/chat_session.dart';
import 'package:novel_app/repositories/chat_session_repository.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';
import 'package:sqflite_common/sqflite.dart';

import '../../helpers/test_database_setup.dart';

void main() {
  late Database db;
  late ChatSessionRepository repo;
  late int sid;

  setUp(() async {
    db = await TestDatabaseSetup.createInMemoryDatabase();
    final connection = DatabaseConnection.forTesting(db);
    await db.execute('PRAGMA foreign_keys = ON');
    repo = ChatSessionRepository(dbConnection: connection);
    sid = await repo.createSession(ChatSession(scenarioId: 'writing', title: 't'));
  });

  ChatMessageRecord rec(int idx, String role, String content,
          {String? toolCallId}) =>
      ChatMessageRecord.fromAgentMessage(
          sid, idx, ChatMessage(role: role, content: content, toolCallId: toolCallId));

  group('appendMessages', () {
    test('整批单事务：按序写入 + agentMsgIndex 保持 + session.updatedAt 刷新',
        () async {
      final before = (await repo.getSession(sid))!.updatedAt;
      await Future.delayed(const Duration(milliseconds: 5));

      final lastId = await repo.appendMessages([
        rec(0, 'assistant', '我想一下', toolCallId: null),
        rec(1, 'tool', '{"ok":1}', toolCallId: 'call-1'),
        rec(2, 'assistant', '结果如下'),
      ]);

      final messages = await repo.listMessages(sid);
      expect(messages.map((m) => m.agentMsgIndex).toList(), [0, 1, 2]);
      expect(messages.map((m) => m.role).toList(),
          ['assistant', 'tool', 'assistant']);
      expect(messages[1].toolCallId, 'call-1');
      expect(lastId, greaterThan(0));

      final after = (await repo.getSession(sid))!.updatedAt;
      expect(after.isAfter(before), isTrue);
    });

    test('空批返回 0 且不动 DB', () async {
      expect(await repo.appendMessages([]), 0);
      expect(await repo.getMessageCount(sid), 0);
    });

    test('中途 FK 冲突整批回滚（无半批落库）', () async {
      final bad = ChatMessageRecord.fromAgentMessage(
          999999, 1, ChatMessage(role: 'user', content: '孤儿消息'));

      await expectLater(
        repo.appendMessages([rec(0, 'user', '第一条'), bad]),
        throwsA(anything),
      );

      // 第 1 条也必须被回滚，不能留下"前半已落库"的断裂状态
      expect(await repo.getMessageCount(sid), 0);
    });
  });

  group('replaceMessages', () {
    test('原子重写：旧消息全部清掉，新消息按序写入', () async {
      await repo.appendMessages(
          List.generate(5, (i) => rec(i, 'user', '旧消息 $i')));

      final written =
          await repo.replaceMessages(sid, [rec(0, 'user', '新A'), rec(1, 'tool', '新B', toolCallId: 'c9')]);

      expect(written, 2);
      final messages = await repo.listMessages(sid);
      expect(messages.length, 2);
      expect(messages[0].content, '新A');
      expect(messages[1].content, '新B');
      expect(messages[1].toolCallId, 'c9');
      expect(messages.map((m) => m.agentMsgIndex).toList(), [0, 1]);
    });

    test('空列表等价于清空', () async {
      await repo.appendMessages([rec(0, 'user', 'x')]);
      expect(await repo.replaceMessages(sid, []), 0);
      expect(await repo.getMessageCount(sid), 0);
    });

    test('中途 FK 冲突全量回滚：旧消息原样保留', () async {
      await repo.appendMessages([rec(0, 'user', '旧1'), rec(1, 'assistant', '旧2')]);

      final bad = ChatMessageRecord.fromAgentMessage(
          999999, 2, ChatMessage(role: 'tool', content: '孤儿'));

      await expectLater(
        repo.replaceMessages(sid, [rec(0, 'user', '新1'), bad]),
        throwsA(anything),
      );

      // 事务回滚：清空 + 部分写入都不能生效，旧两条必须原样保留
      final messages = await repo.listMessages(sid);
      expect(messages.length, 2);
      expect(messages[0].content, '旧1');
      expect(messages[1].content, '旧2');
    });

    test('混入其他 session 的记录抛 ArgumentError 且不动 DB', () async {
      final otherSid =
          await repo.createSession(ChatSession(scenarioId: 'writing', title: 'other'));
      await repo.appendMessages([rec(0, 'user', '本会话消息')]);

      final foreign = ChatMessageRecord.fromAgentMessage(
          otherSid, 0, ChatMessage(role: 'user', content: '别人的'));

      expect(
        () => repo.replaceMessages(sid, [foreign]),
        throwsArgumentError,
      );
      // 拒绝发生在触碰 DB 之前，本会话数据不受影响
      expect(await repo.getMessageCount(sid), 1);
      expect(await repo.getMessageCount(otherSid), 0);
    });
  });
}
