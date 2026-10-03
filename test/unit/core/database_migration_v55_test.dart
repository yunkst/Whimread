/// v55 迁移测试：image_models 加 default_aspect_ratio 列
///
/// 验证：
/// - 升级路径 v54 → v55：default_aspect_ratio 列被添加
/// - 存量行该列为空（回退 1:1 语义由门面处理）
/// - 可写入/回读比例值；repair() 幂等重放无副作用
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> openAtVersion(int version) => openDatabase(
        inMemoryDatabasePath,
        version: version,
        singleInstance: false,
        onCreate: (db, v) async {
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, v);
        },
      );

  test('升级路径 v54 → v55：default_aspect_ratio 列被添加', () async {
    final db = await openAtVersion(54);

    final before = await db.rawQuery('PRAGMA table_info(image_models)');
    expect(before.map((c) => c['name']).toSet(),
        isNot(contains('default_aspect_ratio')),
        reason: 'v54 不应存在该列');

    await DatabaseMigrations.upgrade(db, 54, DatabaseMigrations.currentVersion);

    final after = await db.rawQuery('PRAGMA table_info(image_models)');
    expect(after.map((c) => c['name']).toSet(), contains('default_aspect_ratio'));
    await db.close();
  });

  test('存量行升级后 default_aspect_ratio 为空', () async {
    final db = await openAtVersion(54);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('image_models', {
      'name': 'legacy-pack',
      'backend_type': 'local_dream_embedded',
      'remote_model_id': 'sdxl',
      'created_at': now,
      'updated_at': now,
    });

    await DatabaseMigrations.upgrade(db, 54, DatabaseMigrations.currentVersion);

    final rows = await db.query('image_models');
    expect(rows.single['default_aspect_ratio'], anyOf(isNull, isEmpty));
    await db.close();
  });

  test('新装路径：可写入并回读比例', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('image_models', {
      'name': 'sdxl-pack',
      'backend_type': 'local_dream_embedded',
      'remote_model_id': 'sdxl',
      'default_aspect_ratio': '3:4',
      'created_at': now,
      'updated_at': now,
    });

    final rows = await db.query(
      'image_models',
      where: 'default_aspect_ratio = ?',
      whereArgs: ['3:4'],
    );
    expect(rows, hasLength(1));

    // repair() 幂等重放
    await DatabaseMigrations.repair(db);
    final after = await db.query('image_models');
    expect(after.single['default_aspect_ratio'], '3:4');
    await db.close();
  });
}
