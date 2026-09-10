/// v42 迁移测试：image_models 加生命周期/负向预设/来源快照 7 列
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/database/database_migrations.dart';
import 'package:novel_app/models/image_model.dart';
import 'package:novel_app/repositories/image_model_repository.dart';
import '../../helpers/test_database_setup.dart' as test_db;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v42 迁移给 image_models 加 7 列', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 42,
      onCreate: (db, v) async {
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, 42);
      },
    );

    final cols = await db.rawQuery('PRAGMA table_info(image_models)');
    final colNames = cols.map((c) => c['name'] as String).toSet();
    expect(
        colNames,
        containsAll(<String>[
          'negative_prompt', 'status', 'progress', 'source_url',
          'source_page_url', 'page_snapshot', 'error_message',
        ]));

    // status 默认 'ready'
    final statusCol = cols.firstWhere((c) => c['name'] == 'status');
    expect(statusCol['dflt_value'], "'ready'");

    await db.close();
  });

  test('存量行（不写新列）读出 status=ready，新列取默认值', () async {
    final db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    final repo = ImageModelRepository(dbConnection: DatabaseConnection.forTesting(db));

    // 直插一行不带新列（模拟 v41 存量数据语义）
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('image_models', {
      'name': '老模型',
      'created_at': now,
      'updated_at': now,
    });

    final all = await repo.getAll();
    expect(all, hasLength(1));
    expect(all.first.status, ImageModelStatus.ready); // parse 兜底
    expect(all.first.negativePrompt, '');
    expect(all.first.progress, 0);

    // getEnabled：ready 且 enabled → 可见
    expect((await repo.getEnabled()).map((m) => m.name), ['老模型']);
    await db.close();
  });

  test('getEnabled 过滤非 ready 状态（agent 看不到半成品）', () async {
    final db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    final repo = ImageModelRepository(dbConnection: DatabaseConnection.forTesting(db));
    final now = DateTime.now();

    await repo.save(ImageModel(
        name: 'ready模型',
        status: ImageModelStatus.ready,
        createdAt: now,
        updatedAt: now));
    await repo.save(ImageModel(
        name: '下载中',
        status: ImageModelStatus.downloading,
        createdAt: now,
        updatedAt: now));
    await repo.save(ImageModel(
        name: '转换中',
        status: ImageModelStatus.converting,
        createdAt: now,
        updatedAt: now));
    await repo.save(ImageModel(
        name: '失败',
        status: ImageModelStatus.failed,
        createdAt: now,
        updatedAt: now));

    final enabled = await repo.getEnabled();
    expect(enabled.map((m) => m.name), ['ready模型']);
    await db.close();
  });

  test('updateProgress / updateStatus / getByStatus', () async {
    final db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    final repo = ImageModelRepository(dbConnection: DatabaseConnection.forTesting(db));
    final now = DateTime.now();

    final id = await repo.save(ImageModel(
        name: '任务',
        status: ImageModelStatus.downloading,
        createdAt: now,
        updatedAt: now));

    await repo.updateProgress(id, 42);
    expect((await repo.getById(id))!.progress, 42);

    await repo.updateStatus(id, ImageModelStatus.failed, errorMessage: '网络超时');
    final failed = (await repo.getById(id))!;
    expect(failed.status, ImageModelStatus.failed);
    expect(failed.errorMessage, '网络超时');

    await repo.updateStatus(id, ImageModelStatus.ready,
        progress: 100, filePath: '/x/m.gguf', fileSize: 999);
    final ready = (await repo.getById(id))!;
    expect(ready.status, ImageModelStatus.ready);
    expect(ready.filePath, '/x/m.gguf');
    expect(ready.fileSize, 999);
    expect(ready.progress, 100);

    expect((await repo.getByStatus(ImageModelStatus.downloading)), isEmpty);
    expect((await repo.getByStatus(ImageModelStatus.ready)).first.name, '任务');
    await db.close();
  });
}
