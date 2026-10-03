/// v54 迁移测试：生图后端收敛（嵌入式引擎为唯一后端）
///
/// 验证：
/// - 升级路径 v53 → v54：local_sd / local_dream 后端的模型行被删除
/// - local_dream_embedded 行保留
/// - image_models 加 catalog_id 列；embedded 行可带 catalog_id 写入与查询
/// - repair()（幂等重放）后 embedded 行不受影响
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

  test('升级路径 v53 → v54：catalog_id 列被添加', () async {
    final db = await openAtVersion(53);

    final columnsBefore = await db.rawQuery("PRAGMA table_info(image_models)");
    final namesBefore = columnsBefore.map((c) => c['name']).toSet();
    expect(namesBefore, isNot(contains('catalog_id')),
        reason: 'v53 不应存在 catalog_id');

    await DatabaseMigrations.upgrade(db, 53, DatabaseMigrations.currentVersion);

    final columnsAfter = await db.rawQuery("PRAGMA table_info(image_models)");
    final namesAfter = columnsAfter.map((c) => c['name']).toSet();
    expect(namesAfter, contains('catalog_id'));
    await db.close();
  });

  test('升级路径：local_sd / local_dream 行被删除，embedded 行保留', () async {
    final db = await openAtVersion(53);
    final now = DateTime.now().millisecondsSinceEpoch;
    Future<void> insert(String name, String backendType) => db.insert(
          'image_models',
          {
            'name': name,
            'backend_type': backendType,
            'file_path': '/models/$name',
            'created_at': now,
            'updated_at': now,
          },
        );
    await insert('legacy-sd', 'local_sd');
    await insert('legacy-device', 'local_dream');
    await insert('legacy-comfyui', 'comfyui');
    await insert('embedded-pack', 'local_dream_embedded');

    await DatabaseMigrations.upgrade(db, 53, DatabaseMigrations.currentVersion);

    final rows = await db.query('image_models');
    expect(rows, hasLength(1), reason: '只保留 embedded 行');
    expect(rows.single['name'], 'embedded-pack');
    expect(rows.single['backend_type'], 'local_dream_embedded');
    await db.close();
  });

  test('新装路径：embedded 模型可带 catalog_id 写入并按其查询', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('image_models', {
      'name': 'Illustrious v16（SDXL NPU）',
      'backend_type': 'local_dream_embedded',
      'remote_model_id': 'sdxl',
      'catalog_id': 'illustrious_v16',
      'file_path': '/models/illustrious_v16',
      'created_at': now,
      'updated_at': now,
    });
    // 目录导入的包：catalog_id 为空
    await db.insert('image_models', {
      'name': '本地导入包（SD1.5 CPU）',
      'backend_type': 'local_dream_embedded',
      'remote_model_id': 'sd15cpu',
      'catalog_id': '',
      'file_path': '/models/imported',
      'created_at': now,
      'updated_at': now,
    });

    final byCatalog = await db.query(
      'image_models',
      where: 'catalog_id = ?',
      whereArgs: ['illustrious_v16'],
    );
    expect(byCatalog, hasLength(1));
    expect(byCatalog.single['remote_model_id'], 'sdxl');

    final emptyCatalog = await db.query(
      'image_models',
      where: 'catalog_id = ?',
      whereArgs: [''],
    );
    expect(emptyCatalog, hasLength(1));
    await db.close();
  });

  test('repair() 幂等重放：v54 的 DELETE 对 embedded 行无副作用', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('image_models', {
      'name': 'embedded-pack',
      'backend_type': 'local_dream_embedded',
      'remote_model_id': 'sd15cpu',
      'catalog_id': 'anythingv5cpu',
      'file_path': '/models/pack',
      'created_at': now,
      'updated_at': now,
    });

    await DatabaseMigrations.repair(db);

    final rows = await db.query('image_models');
    expect(rows, hasLength(1));
    expect(rows.single['catalog_id'], 'anythingv5cpu');
    await db.close();
  });
}
