/// v45 迁移测试：site_scripts 加 display_name 列（站点显示名）
///
/// 验证：
/// - 升级路径 v44 → v45：列被添加（v44 时不存在）
/// - 新装路径：列存在且默认空串；未提供时读出 ''
/// - display_name 可正常写入读出（中文站点名）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' show inMemoryDatabasePath;

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

  test('升级路径 v44 → v45：site_scripts.display_name 列被添加', () async {
    final db = await openAtVersion(44);

    // 回归前提：v44 时列不存在
    final columnsBefore = await db.rawQuery(
      "PRAGMA table_info(site_scripts)",
    );
    expect(
      columnsBefore.map((c) => c['name']),
      isNot(contains('display_name')),
    );

    await DatabaseMigrations.upgrade(db, 44, DatabaseMigrations.currentVersion);

    final columnsAfter = await db.rawQuery("PRAGMA table_info(site_scripts)");
    expect(
      columnsAfter.map((c) => c['name']),
      contains('display_name'),
    );
    await db.close();
  });

  test('新装路径：display_name 默认空串', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('site_scripts', {
      'id': 's1',
      'domain': 'www.example.com',
      'url_pattern': '',
      'chapter_list_js': 'L',
      'chapter_content_js': 'C',
      'sample_url': '',
      'created_at': now,
      'last_used_at': now,
      'use_count': 0,
      'verified': 0,
    });

    final rows = await db.query(
      'site_scripts',
      where: 'domain = ?',
      whereArgs: ['www.example.com'],
    );
    expect(rows, hasLength(1));
    expect(rows.first['display_name'], '');
    await db.close();
  });

  test('新装路径：display_name 中文站点名写入读出', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('site_scripts', {
      'id': 's2',
      'domain': 'www.qidian.com',
      'url_pattern': '',
      'chapter_list_js': 'L',
      'chapter_content_js': 'C',
      'sample_url': '',
      'display_name': '起点中文网',
      'created_at': now,
      'last_used_at': now,
      'use_count': 0,
      'verified': 0,
    });

    final rows = await db.query('site_scripts');
    expect(rows.single['display_name'], '起点中文网');
    await db.close();
  });
}
