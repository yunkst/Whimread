import '../core/interfaces/repositories/i_chat_session_repository.dart';
import '../models/chat_session.dart';
import '../models/chat_message_record.dart';
import '../services/logger_service.dart';
import 'base_repository.dart';

/// AI 对话会话仓库实现
///
/// 表常量说明：
/// - chat_sessions: id PK（自增）+ scenarioId + 标题/时间/currentNovel
/// - chat_messages(v32): id PK（自增）+ sessionId FK（CASCADE 删除）+
///   role/content/toolCallsJson/toolCallId/timestamp/agentMsgIndex
///
/// appendMessage 用 db.transaction 把 2 步合成原子操作：
/// 1) INSERT chat_messages（agentMsgIndex 由调用方传入）
/// 2) UPDATE chat_sessions SET updatedAt = now
/// 任何一步异常都会回滚，DB 状态保持一致。
///
/// v32 变更：messages 改存完整 agent ChatMessage（含 tool/system 角色、toolCalls、
/// toolCallId、agentMsgIndex）。不再从 UI 视角重建，hydrate 时 1:1 还原。
class ChatSessionRepository extends BaseRepository
    implements IChatSessionRepository {
  static const String _tableSessions = 'chat_sessions';
  static const String _tableMessages = 'chat_messages';

  ChatSessionRepository({required super.dbConnection});

  // ===== 会话 =====

  @override
  Future<int> createSession(ChatSession session) {
    return guard(
      'chat_session.createSession',
      () async {
        final db = await database;
        final id = await db.insert(_tableSessions, session.toMap());
        LoggerService.instance.i(
          '创建会话: id=$id scenarioId=${session.scenarioId} title=${session.title}',
          category: LogCategory.database,
          tags: ['chat_session', 'create', 'success'],
        );
        return id;
      },
      message: (e) => '创建会话失败: $e',
      category: LogCategory.database,
      tags: ['chat_session', 'create', 'failed'],
    );
  }

  @override
  Future<List<ChatSession>> listSessionsByScenario(
    String scenarioId, {
    int limit = 200,
  }) {
    return guard(
      'chat_session.listSessionsByScenario',
      () async {
        final db = await database;
        final maps = await db.query(
          _tableSessions,
          where: 'scenarioId = ?',
          whereArgs: [scenarioId],
          orderBy: 'updatedAt DESC',
          limit: limit,
        );
        return maps.map((m) => ChatSession.fromMap(m)).toList();
      },
      message: (e) => '列出会话失败: scenarioId=$scenarioId - $e',
      category: LogCategory.database,
      tags: ['chat_session', 'list', 'failed'],
    );
  }

  @override
  Future<ChatSession?> getSession(int id) {
    return guard(
      'chat_session.getSession',
      () async {
        final db = await database;
        final maps = await db.query(
          _tableSessions,
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (maps.isEmpty) return null;
        return ChatSession.fromMap(maps.first);
      },
      message: (e) => '查询会话失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['chat_session', 'get', 'failed'],
    );
  }

  @override
  Future<int> renameSession(int id, String title) {
    return guard(
      'chat_session.renameSession',
      () async {
        final db = await database;
        final now = DateTime.now().millisecondsSinceEpoch;
        final affected = await db.update(
          _tableSessions,
          {'title': title, 'updatedAt': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        LoggerService.instance.i(
          '重命名会话: id=$id affected=$affected',
          category: LogCategory.database,
          tags: ['chat_session', 'rename', 'success'],
        );
        return affected;
      },
      message: (e) => '重命名会话失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['chat_session', 'rename', 'failed'],
    );
  }

  @override
  Future<int> deleteSession(int id) {
    return guard(
      'chat_session.deleteSession',
      () async {
        final db = await database;
        final affected = await db.delete(
          _tableSessions,
          where: 'id = ?',
          whereArgs: [id],
        );
        LoggerService.instance.i(
          '删除会话: id=$id affected=$affected（messages 经 FK CASCADE 自动删除）',
          category: LogCategory.database,
          tags: ['chat_session', 'delete', 'success'],
        );
        return affected;
      },
      message: (e) => '删除会话失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['chat_session', 'delete', 'failed'],
    );
  }

  @override
  Future<int> touchSession(int id) {
    return guard(
      'chat_session.touchSession',
      () async {
        final db = await database;
        final now = DateTime.now().millisecondsSinceEpoch;
        // await 明确等待 update 完成，异步异常由 guard 记日志后统一上抛
        return await db.update(
          _tableSessions,
          {'updatedAt': now},
          where: 'id = ?',
          whereArgs: [id],
        );
      },
      message: (e) => '刷新会话时间失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['chat_session', 'touch', 'failed'],
    );
  }

  @override
  Future<void> updateCurrentNovel(
    int id, {
    int? novelId,
    String? novelTitle,
  }) {
    return guard(
      'chat_session.updateCurrentNovel',
      () async {
        final db = await database;
        await db.update(
          _tableSessions,
          {
            'currentNovelId': novelId,
            'currentNovelTitle': novelTitle,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      },
      message: (e) => '更新 currentNovel 失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['chat_session', 'update_novel', 'failed'],
    );
  }

  // ===== 消息 =====

  @override
  Future<int> appendMessage(ChatMessageRecord record) {
    return guard(
      'chat_session.appendMessage',
      () async {
        final db = await database;
        // 用 transaction 把 插入消息 + 更新 session 时间戳合并
        return await db.transaction((txn) async {
          final insertable = record.toMap();
          final messageId = await txn.insert(_tableMessages, insertable);

          // 刷新 session.updatedAt，让列表排序稳定
          final now = DateTime.now().millisecondsSinceEpoch;
          await txn.update(
            _tableSessions,
            {'updatedAt': now},
            where: 'id = ?',
            whereArgs: [record.sessionId],
          );

          LoggerService.instance.d(
            '追加消息: sessionId=${record.sessionId} role=${record.role} agentIdx=${record.agentMsgIndex} messageId=$messageId',
            category: LogCategory.database,
            tags: ['chat_message', 'append', 'success'],
          );
          return messageId;
        });
      },
      message: (e) => '追加消息失败: sessionId=${record.sessionId} - $e',
      category: LogCategory.database,
      tags: ['chat_message', 'append', 'failed'],
    );
  }

  @override
  Future<int> appendMessages(List<ChatMessageRecord> records) async {
    if (records.isEmpty) return 0;
    final sessionId = records.first.sessionId;
    return guard(
      'chat_session.appendMessages',
      () async {
        final db = await database;
        return await db.transaction((txn) async {
          var lastId = 0;
          for (final record in records) {
            lastId = await txn.insert(_tableMessages, record.toMap());
          }
          await txn.update(
            _tableSessions,
            {'updatedAt': DateTime.now().millisecondsSinceEpoch},
            where: 'id = ?',
            whereArgs: [sessionId],
          );
          return lastId;
        });
      },
      message: (e) =>
          '批量追加消息失败: sessionId=$sessionId count=${records.length} - $e',
      category: LogCategory.database,
      tags: ['chat_message', 'append_batch', 'failed'],
    );
  }

  @override
  Future<int> replaceMessages(
      int sessionId, List<ChatMessageRecord> records) async {
    // 防御：混入其他 session 的记录会污染对方会话，宁可提前抛错
    final foreign =
        records.where((r) => r.sessionId != sessionId).map((r) => r.sessionId);
    if (foreign.isNotEmpty) {
      throw ArgumentError.value(
          foreign.toSet().toList(), 'records', 'records 含非 session $sessionId 的消息');
    }
    return guard(
      'chat_session.replaceMessages',
      () async {
        final db = await database;
        return await db.transaction((txn) async {
          await txn.delete(
            _tableMessages,
            where: 'sessionId = ?',
            whereArgs: [sessionId],
          );
          for (final record in records) {
            await txn.insert(_tableMessages, record.toMap());
          }
          await txn.update(
            _tableSessions,
            {'updatedAt': DateTime.now().millisecondsSinceEpoch},
            where: 'id = ?',
            whereArgs: [sessionId],
          );
          return records.length;
        });
      },
      message: (e) =>
          '原子重写消息失败: sessionId=$sessionId count=${records.length} - $e',
      category: LogCategory.database,
      tags: ['chat_message', 'replace', 'failed'],
    );
  }

  @override
  Future<int> updateMessageContent(int messageId, String content) async {
    final db = await database;
    final updated = await db.update(
      _tableMessages,
      {
        'content': content,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
    LoggerService.instance.d(
      '更新消息内容: messageId=$messageId 影响 $updated 行',
      category: LogCategory.database,
      tags: ['chat_message', 'update_content', 'success'],
    );
    // 真实错误（db 已关闭、表不存在、唯一约束冲突等）抛给上层，
    // 让 UI 层决定重试或回滚；不再静默吞错返回 0，避免 UI/DB 数据漂移。
    return updated;
  }

  @override
  Future<List<ChatMessageRecord>> listMessages(
    int sessionId, {
    int? limit,
    int offset = 0,
  }) {
    return guard(
      'chat_session.listMessages',
      () async {
        final db = await database;
        final maps = await db.query(
          _tableMessages,
          where: 'sessionId = ?',
          whereArgs: [sessionId],
          orderBy: 'agentMsgIndex ASC',
          limit: limit,
          offset: offset,
        );
        return maps.map((m) => ChatMessageRecord.fromMap(m)).toList();
      },
      message: (e) => '列举消息失败: sessionId=$sessionId - $e',
      category: LogCategory.database,
      tags: ['chat_message', 'list', 'failed'],
    );
  }

  @override
  Future<int> getMessageCount(int sessionId) {
    return guard(
      'chat_session.getMessageCount',
      () async {
        final db = await database;
        final result = await db.rawQuery(
          'SELECT COUNT(*) AS cnt FROM $_tableMessages WHERE sessionId = ?',
          [sessionId],
        );
        return (result.first['cnt'] as int?) ?? 0;
      },
      message: (e) => '统计消息数失败: sessionId=$sessionId - $e',
      category: LogCategory.database,
      tags: ['chat_message', 'count', 'failed'],
    );
  }

  @override
  Future<int> deleteMessagesBefore(int sessionId, int beforeIndex) {
    return guard(
      'chat_session.deleteMessagesBefore',
      () async {
        final db = await database;
        return await db.transaction((txn) async {
          final deleted = await txn.delete(
            _tableMessages,
            where: 'sessionId = ? AND agentMsgIndex < ?',
            whereArgs: [sessionId, beforeIndex],
          );
          await txn.update(
            _tableSessions,
            {'updatedAt': DateTime.now().millisecondsSinceEpoch},
            where: 'id = ?',
            whereArgs: [sessionId],
          );
          LoggerService.instance.d(
            '删除消息: sessionId=$sessionId beforeIdx=$beforeIndex 删除 $deleted 行',
            category: LogCategory.database,
            tags: ['chat_message', 'delete_before', 'success'],
          );
          return deleted;
        });
      },
      message: (e) =>
          '删除消息失败: sessionId=$sessionId beforeIndex=$beforeIndex - $e',
      category: LogCategory.database,
      tags: ['chat_message', 'delete_before', 'failed'],
    );
  }

  @override
  Future<int> clearMessages(int sessionId) {
    return guard(
      'chat_session.clearMessages',
      () async {
        final db = await database;
        // await 明确等待 transaction 完成，异步异常由 guard 记日志后统一上抛
        return await db.transaction((txn) async {
          final deleted = await txn.delete(
            _tableMessages,
            where: 'sessionId = ?',
            whereArgs: [sessionId],
          );
          await txn.update(
            _tableSessions,
            {'updatedAt': DateTime.now().millisecondsSinceEpoch},
            where: 'id = ?',
            whereArgs: [sessionId],
          );
          return deleted;
        });
      },
      message: (e) => '清空会话消息失败: sessionId=$sessionId - $e',
      category: LogCategory.database,
      tags: ['chat_message', 'clear', 'failed'],
    );
  }
}
