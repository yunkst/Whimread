/// Agent 场景经验记忆 Repository
///
/// 管理 agent_memory 表的 CRUD 操作。
/// 每个场景（writing / webview_extract）的记忆通过 scenario_id 隔离。
library;

import '../services/logger_service.dart';
import 'base_repository.dart';

class AgentMemoryRepository extends BaseRepository {
  AgentMemoryRepository({required super.dbConnection});

  /// 获取指定场景的所有记忆内容（按创建时间排序）
  Future<List<String>> getAllByScenario(String scenarioId) async {
    try {
      final db = await database;
      final results = await db.query(
        'agent_memory',
        columns: ['content'],
        where: 'scenario_id = ?',
        whereArgs: [scenarioId],
        orderBy: 'created_at ASC',
      );
      return results.map((r) => r['content'] as String).toList();
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '查询记忆失败: scenarioId=$scenarioId - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['agent_memory', 'query', 'failed'],
      );
      rethrow;
    }
  }

  /// 获取指定场景的所有记忆（含 id，供 patch_memory 报错时返回）
  Future<List<Map<String, dynamic>>> getAllWithId(String scenarioId) async {
    try {
      final db = await database;
      return await db.query(
        'agent_memory',
        where: 'scenario_id = ?',
        whereArgs: [scenarioId],
        orderBy: 'created_at ASC',
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '查询记忆（含id）失败: scenarioId=$scenarioId - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['agent_memory', 'query_with_id', 'failed'],
      );
      rethrow;
    }
  }

  /// 添加一条记忆
  Future<int> addMemory(String scenarioId, String content) async {
    try {
      final db = await database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await db.insert('agent_memory', {
        'scenario_id': scenarioId,
        'content': content,
        'created_at': now,
        'updated_at': now,
      });
      LoggerService.instance.i(
        '添加记忆: scenarioId=$scenarioId id=$id',
        category: LogCategory.database,
        tags: ['agent_memory', 'add', 'success'],
      );
      return id;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '添加记忆失败: scenarioId=$scenarioId - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['agent_memory', 'add', 'failed'],
      );
      rethrow;
    }
  }

  /// 更新记忆内容（同时更新 updated_at）
  Future<int> updateMemory(int id, String newContent) async {
    try {
      final db = await database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final affected = await db.update(
        'agent_memory',
        {'content': newContent, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      LoggerService.instance.i(
        '更新记忆: id=$id affected=$affected',
        category: LogCategory.database,
        tags: ['agent_memory', 'update', 'success'],
      );
      return affected;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '更新记忆失败: id=$id - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['agent_memory', 'update', 'failed'],
      );
      rethrow;
    }
  }

  /// 删除记忆
  Future<int> deleteMemory(int id) async {
    try {
      final db = await database;
      final affected = await db.delete(
        'agent_memory',
        where: 'id = ?',
        whereArgs: [id],
      );
      LoggerService.instance.i(
        '删除记忆: id=$id affected=$affected',
        category: LogCategory.database,
        tags: ['agent_memory', 'delete', 'success'],
      );
      return affected;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '删除记忆失败: id=$id - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['agent_memory', 'delete', 'failed'],
      );
      rethrow;
    }
  }

  /// 精确匹配查找记忆（按 content 完全匹配）
  Future<Map<String, dynamic>?> findByContent(
    String scenarioId,
    String oldText,
  ) async {
    try {
      final db = await database;
      final results = await db.query(
        'agent_memory',
        where: 'scenario_id = ? AND content = ?',
        whereArgs: [scenarioId, oldText],
        limit: 1,
      );
      return results.isNotEmpty ? results.first : null;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '查找记忆失败: scenarioId=$scenarioId - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['agent_memory', 'find', 'failed'],
      );
      rethrow;
    }
  }

  /// 获取指定场景的记忆总数
  Future<int> countByScenario(String scenarioId) async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM agent_memory WHERE scenario_id = ?',
        [scenarioId],
      );
      return (result.first['cnt'] as int?) ?? 0;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '统计记忆数量失败: scenarioId=$scenarioId - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['agent_memory', 'count', 'failed'],
      );
      rethrow;
    }
  }
}
