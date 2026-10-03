import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/interfaces/repositories/i_llm_config_repository.dart';
import '../../models/llm_config.dart';
import '../../services/logger_service.dart';
import 'base_repository.dart';

class LlmConfigRepository extends BaseRepository
    implements ILlmConfigRepository {
  static const String _table = 'llm_configs';

  /// API Key 安全存储（与设备 JWT 同一标准：2026-10 审查 P1——Key 明文
  /// 落 SQLite 可被备份导出/调试/root 读取）。平台不支持/底层异常时降级
  /// 回 DB 明文列，保持旧可用性。
  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String _secureKey(int id) => 'llm_api_key_$id';

  LlmConfigRepository({required super.dbConnection});

  @override
  Future<List<LlmConfig>> getAll() async {
    final db = await database;
    final maps = await db.query(_table, orderBy: 'sort_order ASC, id ASC');
    final configs = <LlmConfig>[];
    for (final row in maps) {
      configs.add(LlmConfig.fromMap(row)
          .copyWith(apiKey: await _resolveApiKey(row)));
    }
    return configs;
  }

  @override
  Future<LlmConfig?> getById(int id) async {
    final db = await database;
    final maps =
        await db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return LlmConfig.fromMap(maps.first)
        .copyWith(apiKey: await _resolveApiKey(maps.first));
  }

  @override
  Future<LlmConfig?> getDefault() async {
    final db = await database;
    final maps = await db.query(_table,
        where: 'is_default = ?', whereArgs: [1], limit: 1);
    if (maps.isEmpty) return null;
    return LlmConfig.fromMap(maps.first)
        .copyWith(apiKey: await _resolveApiKey(maps.first));
  }

  @override
  Future<int> save(LlmConfig config) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (config.id == null) {
      // 明文列恒为空串，真实 Key 落安全存储（见 [_writeApiKey]）
      final newId = await db.insert(_table, {
        'name': config.name,
        'api_url': config.apiUrl,
        'api_key': '',
        'model': config.model,
        'is_default': config.isDefault ? 1 : 0,
        'sort_order': config.sortOrder,
        'created_at': now,
        'updated_at': now,
      });
      await _writeApiKey(newId, config.apiKey);
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
        // 明文列不在 update 里覆盖写：真实 Key 由 [_writeApiKey] 决定落点
        'model': config.model,
        'is_default': config.isDefault ? 1 : 0,
        'sort_order': config.sortOrder,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [config.id],
    );
    await _writeApiKey(config.id!, config.apiKey);
    LoggerService.instance.i('更新 LLM 配置: "${config.name}" (id=${config.id})',
        category: LogCategory.database,
        tags: ['llm_config', 'update']);
    return config.id!;
  }

  @override
  Future<void> delete(int id) async {
    final db = await database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    try {
      await _secure.delete(key: _secureKey(id));
    } catch (_) {/* 安全存储不可用（如测试环境）：忽略 */}
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

  @override
  Future<int> clearAllApiKeys() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    // 只清空原本非空的行，避免无意义的 updated_at 写入
    final rows =
        await db.query(_table, columns: ['id'], where: "api_key != ''");
    final cleared = await db.update(
      _table,
      {'api_key': '', 'updated_at': now},
      where: "api_key != ''",
    );
    // 同步清掉安全存储副本（安全存储里也可能有 api_key 列为空的 Key）
    for (final row in rows) {
      final id = row['id'] as int?;
      if (id == null) continue;
      try {
        await _secure.delete(key: _secureKey(id));
      } catch (_) {/* 安全存储不可用（如测试环境）：忽略 */}
    }
    LoggerService.instance.i(
      '托管模式：已清空 $cleared 条 LLM 配置的 API Key',
      category: LogCategory.ai,
      tags: ['llm_config', 'clear_api_keys', 'managed'],
    );
    return cleared;
  }

  /// 解析某行配置的真实 API Key。
  ///
  /// 优先安全存储；DB 明文列非空视为存量数据——迁移到安全存储并清空列
  /// （一次性，写失败则保留明文列降级）；安全存储读取异常时明文列是唯一
  /// 来源，直接返回。
  Future<String> _resolveApiKey(Map<String, dynamic> row) async {
    final id = row['id'] as int?;
    final legacy = (row['api_key'] as String?) ?? '';
    if (id == null) return legacy;

    String? stored;
    try {
      stored = await _secure.read(key: _secureKey(id));
    } catch (_) {
      return legacy;
    }
    if (stored != null && stored.isNotEmpty) {
      if (legacy.isNotEmpty) {
        // 安全存储已是权威来源，顺手清掉存量明文列
        await _blankApiKeyColumn(id);
      }
      return stored;
    }
    if (legacy.isNotEmpty) {
      try {
        await _secure.write(key: _secureKey(id), value: legacy);
        await _blankApiKeyColumn(id);
        LoggerService.instance.i(
          '存量 LLM API Key 已从 SQLite 迁移到安全存储: id=$id',
          category: LogCategory.database,
          tags: ['llm_config', 'api_key_migrated'],
        );
      } catch (_) {
        return legacy; // 降级：安全存储不可用，保留明文列
      }
    }
    return legacy;
  }

  /// 写入 API Key：优先安全存储，成功后清空明文列；
  /// 平台不支持/底层异常时降级保留明文列（旧可用性）。
  Future<void> _writeApiKey(int id, String apiKey) async {
    if (apiKey.isEmpty) {
      try {
        await _secure.delete(key: _secureKey(id));
      } catch (_) {}
      await _blankApiKeyColumn(id);
      return;
    }
    try {
      await _secure.write(key: _secureKey(id), value: apiKey);
      await _blankApiKeyColumn(id);
    } catch (e) {
      LoggerService.instance.w(
        '安全存储写入 LLM API Key 失败，降级明文列: $e',
        category: LogCategory.database,
        tags: ['llm_config', 'secure_storage', 'write_fallback'],
      );
      final db = await database;
      await db
          .update(_table, {'api_key': apiKey}, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> _blankApiKeyColumn(int id) async {
    final db = await database;
    await db.update(_table, {'api_key': ''}, where: 'id = ?', whereArgs: [id]);
  }
}
