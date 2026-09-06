import '../../core/interfaces/repositories/i_llm_config_repository.dart';
import '../../models/llm_config.dart';
import '../../services/logger_service.dart';
import 'base_repository.dart';

class LlmConfigRepository extends BaseRepository
    implements ILlmConfigRepository {
  static const String _table = 'llm_configs';

  LlmConfigRepository({required super.dbConnection});

  @override
  Future<List<LlmConfig>> getAll() async {
    final db = await database;
    final maps = await db.query(_table, orderBy: 'sort_order ASC, id ASC');
    return maps.map(LlmConfig.fromMap).toList();
  }

  @override
  Future<LlmConfig?> getById(int id) async {
    final db = await database;
    final maps =
        await db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return LlmConfig.fromMap(maps.first);
  }

  @override
  Future<LlmConfig?> getDefault() async {
    final db = await database;
    final maps = await db.query(_table,
        where: 'is_default = ?', whereArgs: [1], limit: 1);
    if (maps.isEmpty) return null;
    return LlmConfig.fromMap(maps.first);
  }

  @override
  Future<int> save(LlmConfig config) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (config.id == null) {
      final newId = await db.insert(_table, {
        'name': config.name,
        'api_url': config.apiUrl,
        'api_key': config.apiKey,
        'model': config.model,
        'is_default': config.isDefault ? 1 : 0,
        'sort_order': config.sortOrder,
        'created_at': now,
        'updated_at': now,
      });
      LoggerService.instance.i('新增 LLM 配置: "${config.name}" (id=$newId)',
          category: LogCategory.database,
          tags: ['llm_config', 'insert']);
      return newId;
    }

    await db.update(
      _table,
      {
        'name': config.name,
        'api_url': config.apiUrl,
        'api_key': config.apiKey,
        'model': config.model,
        'is_default': config.isDefault ? 1 : 0,
        'sort_order': config.sortOrder,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [config.id],
    );
    LoggerService.instance.i('更新 LLM 配置: "${config.name}" (id=${config.id})',
        category: LogCategory.database,
        tags: ['llm_config', 'update']);
    return config.id!;
  }

  @override
  Future<void> delete(int id) async {
    final db = await database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    LoggerService.instance.i('删除 LLM 配置: id=$id',
        category: LogCategory.database, tags: ['llm_config', 'delete']);
  }

  @override
  Future<void> setDefault(int id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    // 两步 UPDATE 必须原子：先清除旧默认、再设置新默认，使用事务保证
    // 任一步失败则整体回滚，避免出现"无默认"或"多默认"的不一致状态。
    await db.transaction((txn) async {
      await txn.update(
        _table,
        {'is_default': 0, 'updated_at': now},
        where: 'is_default = ?',
        whereArgs: [1],
      );
      await txn.update(
        _table,
        {'is_default': 1, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    LoggerService.instance.i('设置默认 LLM 配置: id=$id',
        category: LogCategory.database,
        tags: ['llm_config', 'set_default']);
  }

  @override
  Future<int> getNextSortOrder() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT MAX(sort_order) as max_sort FROM $_table');
    final maxSort = result.first['max_sort'] as int? ?? -1;
    return maxSort + 1;
  }

  @override
  Future<int> count() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as count FROM $_table');
    return result.first['count'] as int;
  }
}
