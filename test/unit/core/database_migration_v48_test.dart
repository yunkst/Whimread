/// v48 迁移测试：image_models 加远程设备列（Local Dream 生图）
///
/// 验证：
/// - 升级路径 v47 → v48：remote_host / remote_model_id 两列被添加
/// - 存量 local_sd 行默认值为空串（不影响本地引擎语义）
/// - 新装路径：local_dream 模型可正常写入并按 remote_model_id 查询
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

  test('升级路径 v47 → v48：image_models 远程设备两列被添加', () async {
    final db = await openAtVersion(47);

    final columnsBefore = await db.rawQuery("PRAGMA table_info(image_models)");
    final namesBefore = columnsBefore.map((c) => c['name']).toSet();
    expect(namesBefore, isNot(contains('remote_host')), reason: 'v47 不应存在 remote_host');
    expect(namesBefore, isNot(contains('remote_model_id')),
        reason: 'v47 不应存在 remote_model_id');

    await DatabaseMigrations.upgrade(db, 47, DatabaseMigrations.currentVersion);

    final columnsAfter = await db.rawQuery("PRAGMA table_info(image_models)");
    final namesAfter = columnsAfter.map((c) => c['name']).toSet();
    expect(namesAfter, contains('remote_host'));
    expect(namesAfter, contains('remote_model_id'));
    await db.close();
  });

  test('升级路径：存量 local_sd 模型默认 remote_host / remote_model_id 为空串', () async {
    final db = await openAtVersion(47);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('image_models', {
      'name': 'legacy-local',
      'file_path': '/models/a.gguf',
      'created_at': now,
      'updated_at': now,
    });

    await DatabaseMigrations.upgrade(db, 47, DatabaseMigrations.currentVersion);

    final rows = await db.query('image_models');
    expect(rows.single['backend_type'], 'local_sd');
    expect(rows.single['remote_host'], '');
    expect(rows.single['remote_model_id'], '');
    await db.close();
  });

  test('新装路径：local_dream 模型可正常写入并按 remote_model_id 查询', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('image_models', {
      'name': '手机 SDXL',
      'backend_type': 'local_dream',
      'remote_host': '192.168.31.76',
      'remote_model_id': 'illustrious_v16',
      'default_width': 1024,
      'default_height': 1024,
      'created_at': now,
      'updated_at': now,
    });

    final rows = await db.query(
      'image_models',
      where: 'remote_model_id = ?',
      whereArgs: ['illustrious_v16'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['remote_host'], '192.168.31.76');
    expect(rows.single['default_width'], 1024);
    await db.close();
  });
}
