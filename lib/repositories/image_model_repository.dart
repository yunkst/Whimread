import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/interfaces/repositories/i_image_model_repository.dart';
import '../../models/image_model.dart';
import '../../services/logger_service.dart';
import 'base_repository.dart';

class ImageModelRepository extends BaseRepository
    implements IImageModelRepository {
  static const String _table = 'image_models';

  ImageModelRepository({required super.dbConnection});

  /// save 走的列字典（insert/update 共用，避免两处漂移）
  Map<String, dynamic> _rowMap(ImageModel model, {required bool isInsert}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return {
      'name': model.name,
      'description': model.description,
      'tags': jsonEncode(model.tags),
      'backend_type': model.backendType.dbName,
      'file_path': model.filePath,
      'file_size': model.fileSize,
      'preview_media_id': model.previewMediaId,
      'default_width': model.defaultWidth,
      'default_height': model.defaultHeight,
      'default_steps': model.defaultSteps,
      'default_cfg': model.defaultCfg,
      'is_enabled': model.isEnabled ? 1 : 0,
      'is_default': model.isDefault ? 1 : 0,
      'sort_order': model.sortOrder,
      'updated_at': now,
      'negative_prompt': model.negativePrompt,
      'status': model.status.dbName,
      'progress': model.progress,
      'source_url': model.sourceUrl,
      'source_page_url': model.sourcePageUrl,
      'page_snapshot': model.pageSnapshot,
      'error_message': model.errorMessage,
      if (isInsert) 'created_at': now,
    };
  }

  @override
  Future<List<ImageModel>> getAll() async {
    final db = await database;
    final maps = await db.query(_table, orderBy: 'sort_order ASC, id ASC');
    return maps.map(ImageModel.fromMap).toList();
  }

  @override
  Future<List<ImageModel>> getEnabled() async {
    final db = await database;
    final maps = await db.query(
      _table,
      where: "is_enabled = ? AND status = 'ready'",
      whereArgs: [1],
      orderBy: 'sort_order ASC, id ASC',
    );
    return maps.map(ImageModel.fromMap).toList();
  }

  @override
  Future<ImageModel?> getById(int id) async {
    final db = await database;
    final maps =
        await db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return ImageModel.fromMap(maps.first);
  }

  @override
  Future<ImageModel?> getByName(String name) async {
    final db = await database;
    final maps = await db.query(
      _table,
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ImageModel.fromMap(maps.first);
  }

  @override
  Future<ImageModel?> getDefault() async {
    final db = await database;
    final maps = await db.query(_table,
        where: 'is_default = ?', whereArgs: [1], limit: 1);
    if (maps.isEmpty) return null;
    return ImageModel.fromMap(maps.first);
  }

  @override
  Future<int> save(ImageModel model) async {
    final db = await database;

    try {
      if (model.id == null) {
        return await db.insert(_table, _rowMap(model, isInsert: true));
      }

      await db.update(
        _table,
        _rowMap(model, isInsert: false),
        where: 'id = ?',
        whereArgs: [model.id],
      );
      LoggerService.instance.i('更新生图模型: "${model.name}" (id=${model.id})',
          category: LogCategory.database,
          tags: ['image_model', 'update']);
      return model.id!;
    } on DatabaseException catch (e) {
      // image_models.name 唯一索引冲突 → 映射为友好异常。
      // sqflite 在不同版本对 UNIQUE 错误的字段不同，兼容起见同时匹配
      // toString 与 toString().toLowerCase（部分平台报 'Unique violation'）。
      final msg = e.toString().toLowerCase();
      final isNameUnique = msg.contains('unique') &&
          (msg.contains('idx_image_models_name') || msg.contains('name'));
      if (isNameUnique) {
        LoggerService.instance.w('生图模型名重复: "${model.name}"',
            category: LogCategory.database,
            tags: ['image_model', 'name_conflict']);
        throw ImageModelNameConflictException(model.name);
      }
      rethrow;
    }
  }

  @override
  Future<void> delete(int id) async {
    final db = await database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    LoggerService.instance.i('删除生图模型: id=$id',
        category: LogCategory.database, tags: ['image_model', 'delete']);
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
    LoggerService.instance.i('设置默认生图模型: id=$id',
        category: LogCategory.database,
        tags: ['image_model', 'set_default']);
  }

  @override
  Future<int> getNextSortOrder() async {
    final db = await database;
    final result = await db
        .rawQuery('SELECT MAX(sort_order) as max_sort FROM $_table');
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

  // ============================================================
  // 生命周期部分更新（下载/转换高频进度写库，避免整行 UPDATE）
  // ============================================================

  @override
  Future<void> updateProgress(int id, int progress) async {
    final db = await database;
    await db.update(
      _table,
      {
        'progress': progress.clamp(0, 100),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> updateStatus(
    int id,
    ImageModelStatus status, {
    String errorMessage = '',
    int? progress,
    String? filePath,
    int? fileSize,
    int? defaultWidth,
    int? defaultHeight,
  }) async {
    final db = await database;
    await db.update(
      _table,
      {
        'status': status.dbName,
        'error_message': errorMessage,
        if (progress != null) 'progress': progress.clamp(0, 100),
        if (filePath != null) 'file_path': filePath,
        if (fileSize != null) 'file_size': fileSize,
        if (defaultWidth != null) 'default_width': defaultWidth,
        if (defaultHeight != null) 'default_height': defaultHeight,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    LoggerService.instance.i(
        '生图模型状态变更: id=$id → ${status.dbName}'
        '${errorMessage.isNotEmpty ? " ($errorMessage)" : ""}',
        category: LogCategory.database,
        tags: ['image_model', 'status']);
  }

  @override
  Future<List<ImageModel>> getByStatus(ImageModelStatus status) async {
    final db = await database;
    final maps = await db.query(
      _table,
      where: 'status = ?',
      whereArgs: [status.dbName],
      orderBy: 'sort_order ASC, id ASC',
    );
    return maps.map(ImageModel.fromMap).toList();
  }
}