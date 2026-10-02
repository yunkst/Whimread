import '../models/text_game.dart';
import '../services/logger_service.dart';
import 'base_repository.dart';

/// 文字游戏仓库
///
/// 表：text_games（v52）。剧情历史不在本表——每个游戏关联一个
/// chat_session（chatSessionId），消息链复用 chat_sessions/chat_messages。
///
/// 删除联动：delete() 单事务内先删 chat_session 行（chat_messages 经现有
/// FK CASCADE 随之删除），再删 text_games 行，保证不留孤儿会话。
/// 小说删除不级联删游戏：settingsJson 是创建时的快照，sourceNovelTitle
/// 已冗余存储展示用标题。
class TextGameRepository extends BaseRepository {
  static const String _table = 'text_games';

  TextGameRepository({required super.dbConnection});

  /// 新建游戏，返回行 id
  Future<int> create(TextGame game) {
    return guard(
      'text_game.create',
      () async {
        final db = await database;
        final id = await db.insert(_table, game.toMap());
        LoggerService.instance.i(
          '创建文字游戏: id=$id title=${game.title} sessionId=${game.chatSessionId}',
          category: LogCategory.database,
          tags: ['text_game', 'create', 'success'],
        );
        return id;
      },
      message: (e) => '创建文字游戏失败: $e',
      category: LogCategory.database,
      tags: ['text_game', 'create', 'failed'],
    );
  }

  /// 按 id 查单条，不存在返回 null
  Future<TextGame?> getById(int id) {
    return guard(
      'text_game.getById',
      () async {
        final db = await database;
        final maps = await db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
        if (maps.isEmpty) return null;
        return TextGame.fromMap(maps.first);
      },
      message: (e) => '查询文字游戏失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['text_game', 'get', 'failed'],
    );
  }

  /// 按剧情会话 id 反查游戏（ScenarioSession 构建上下文时用）
  Future<TextGame?> getByChatSessionId(int chatSessionId) {
    return guard(
      'text_game.getByChatSessionId',
      () async {
        final db = await database;
        final maps = await db.query(
          _table,
          where: 'chatSessionId = ?',
          whereArgs: [chatSessionId],
          limit: 1,
        );
        if (maps.isEmpty) return null;
        return TextGame.fromMap(maps.first);
      },
      message: (e) => '按会话查文字游戏失败: chatSessionId=$chatSessionId - $e',
      category: LogCategory.database,
      tags: ['text_game', 'get_by_session', 'failed'],
    );
  }

  /// 列出全部游戏（lastPlayedAt DESC，null 视为最旧；同为空按 createdAt DESC）
  Future<List<TextGame>> listAll() {
    return guard(
      'text_game.listAll',
      () async {
        final db = await database;
        final maps = await db.query(
          _table,
          orderBy:
              'COALESCE(lastPlayedAt, createdAt) DESC, createdAt DESC',
        );
        return maps.map(TextGame.fromMap).toList();
      },
      message: (e) => '列出文字游戏失败: $e',
      category: LogCategory.database,
      tags: ['text_game', 'list', 'failed'],
    );
  }

  /// 整体更新（title/settings/status/cover 等，updatedAt 自动刷新）
  Future<int> update(TextGame game) {
    return guard(
      'text_game.update',
      () async {
        final db = await database;
        final map = game.copyWith(updatedAt: DateTime.now()).toMap()
          ..remove('id');
        final affected = await db.update(
          _table,
          map,
          where: 'id = ?',
          whereArgs: [game.id],
        );
        LoggerService.instance.i(
          '更新文字游戏: id=${game.id} affected=$affected',
          category: LogCategory.database,
          tags: ['text_game', 'update', 'success'],
        );
        return affected;
      },
      message: (e) => '更新文字游戏失败: id=${game.id} - $e',
      category: LogCategory.database,
      tags: ['text_game', 'update', 'failed'],
    );
  }

  /// 更新游戏状态
  Future<int> updateStatus(int id, TextGameStatus status) {
    return guard(
      'text_game.updateStatus',
      () async {
        final db = await database;
        return await db.update(
          _table,
          {
            'status': status.name,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      },
      message: (e) => '更新游戏状态失败: id=$id status=${status.name} - $e',
      category: LogCategory.database,
      tags: ['text_game', 'update_status', 'failed'],
    );
  }

  /// 触达 lastPlayedAt（进入游玩页/每回合开始时调用）
  Future<int> touchLastPlayed(int id) {
    return guard(
      'text_game.touchLastPlayed',
      () async {
        final db = await database;
        final now = DateTime.now().millisecondsSinceEpoch;
        return await db.update(
          _table,
          {'lastPlayedAt': now},
          where: 'id = ?',
          whereArgs: [id],
        );
      },
      message: (e) => '刷新最后游玩时间失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['text_game', 'touch', 'failed'],
    );
  }

  /// 删除游戏（单事务：先删关联会话→messages 经 FK CASCADE，再删游戏行）
  Future<int> delete(int id) {
    return guard(
      'text_game.delete',
      () async {
        final db = await database;
        return await db.transaction((txn) async {
          final game = await txn.query(
            _table,
            columns: ['chatSessionId'],
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );
          if (game.isNotEmpty) {
            final sessionId = game.first['chatSessionId'] as int?;
            if (sessionId != null) {
              await txn.delete('chat_sessions', where: 'id = ?', whereArgs: [sessionId]);
            }
          }
          final affected = await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
          LoggerService.instance.i(
            '删除文字游戏: id=$id affected=$affected（关联会话与消息已级联清理）',
            category: LogCategory.database,
            tags: ['text_game', 'delete', 'success'],
          );
          return affected;
        });
      },
      message: (e) => '删除文字游戏失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['text_game', 'delete', 'failed'],
    );
  }
}
