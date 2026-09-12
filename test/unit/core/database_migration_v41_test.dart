/// v41 迁移测试：image_models 表（用户导入的本地 SD 模型 + 元数据）
///
/// 镜像 v40 迁移测试的形态：真实内存 SQLite + PRAGMA 检查新表/列/索引 +
/// 插入/读取确认整条路可走。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novel_app/core/database/database_migrations.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v41 迁移新建 image_models 表', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 41,
      onCreate: (db, v) async {
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, 41);
      },
    );

    // 1. 表存在
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='image_models'");
    expect(tables, isNotEmpty, reason: 'image_models 表必须存在');

    // 2. 列与默认值正确
    final cols = await db.rawQuery('PRAGMA table_info(image_models)');
    final colNames = cols.map((c) => c['name'] as String).toSet();
    expect(colNames, containsAll(<String>[
      'id', 'name', 'description', 'tags', 'backend_type', 'file_path',
      'file_size', 'preview_media_id', 'default_width', 'default_height',
      'default_steps', 'default_cfg', 'is_enabled', 'is_default',
      'sort_order', 'created_at', 'updated_at',
    ]));

    // name NOT NULL
    final nameCol =
        cols.firstWhere((c) => c['name'] == 'name', orElse: () => {});
    expect(nameCol['notnull'], 1);

    // 3. 唯一索引存在
    final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='image_models'");
    final idxNames = indexes.map((r) => r['name'] as String).toSet();
    expect(idxNames, contains('idx_image_models_name'));
    expect(idxNames, contains('idx_image_models_sort'));
    expect(idxNames, contains('idx_image_models_enabled'));

    // 4. 插入/读取整条路（json tags 写读）
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('image_models', {
      'name': '古风水墨',
      'description': '擅长中国古风插画',
      'tags': '["古风","水墨"]',
      'backend_type': 'local_sd',
      'file_path': '/data/models/ink.gguf',
      'file_size': 1200000000,
      'default_width': 512,
      'default_height': 768,
      'default_steps': 25,
      'default_cfg': 6.5,
      'is_enabled': 1,
      'is_default': 0,
      'sort_order': 0,
      'created_at': now,
      'updated_at': now,
    });
    expect(id, isPositive);

    final rows = await db.query('image_models', where: 'id = ?', whereArgs: [id]);
    expect(rows.first['name'], '古风水墨');
    expect(rows.first['description'], '擅长中国古风插画');
    expect(rows.first['tags'], '["古风","水墨"]');
    expect(rows.first['backend_type'], 'local_sd');
    expect(rows.first['file_size'], 1200000000);

    // 5. name 唯一性（重复 name 应抛 DatabaseException）
    expect(
      () => db.insert('image_models', {
        'name': '古风水墨',
        'backend_type': 'local_sd',
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(isA<Object>()),
      reason: 'name 唯一索引应拒绝重复值',
    );

    await db.close();
  });

  test('currentVersion >= 44（v41 image_models 迁移已包含）', () {
    expect(DatabaseMigrations.currentVersion, greaterThanOrEqualTo(44));
  });
}