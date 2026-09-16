/// v46 迁移测试：site_scripts 加 preferred_mode 列（脚本创作模式）
///
/// 验证：
/// - 升级路径 v45 → v46：列被添加（v45 时不存在）
/// - 新装路径：列存在且默认 0（未设置，执行时回退全局模式）
/// - preferred_mode 可正常写入读出（桌面=1 / 手机=2）
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

  test('升级路径 v45 → v46：site_scripts.preferred_mode 列被添加', () async {
    final db = await openAtVersion(45);

    // 回归前提：v45 时列不存在
    final columnsBefore = await db.rawQuery(
      "PRAGMA table_info(site_scripts)",
    );
    expect(
      columnsBefore.map((c) => c['name']),
      isNot(contains('preferred_mode')),
    );

    await DatabaseMigrations.upgrade(db, 45, DatabaseMigrations.currentVersion);

    final columnsAfter = await db.rawQuery("PRAGMA table_info(site_scripts)");
    expect(
      columnsAfter.map((c) => c['name']),
      contains('preferred_mode'),
    );
    await db.close();
  });

  test('升级路径：存量脚本 preferred_mode 默认 0（回退全局模式）', () async {
    final db = await openAtVersion(45);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('site_scripts', {
      'id': 'legacy',
      'domain': 'www.example.com',
      'url_pattern': '',
      'chapter_list_js': 'L',
      'chapter_content_js': 'C',
      'sample_url': '',
      'display_name': '',
      'created_at': now,
      'last_used_at': now,
      'use_count': 0,
      'verified': 0,
    });

    await DatabaseMigrations.upgrade(db, 45, DatabaseMigrations.currentVersion);

    final rows = await db.query('site_scripts');
    expect(rows.single['preferred_mode'], 0);
    await db.close();
  });

  test('新装路径：preferred_mode 写入读出（桌面=1 / 手机=2）', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('site_scripts', {
      'id': 's1',
      'domain': 'www.desktop-site.com',
      'url_pattern': '',
      'chapter_list_js': 'L',
      'chapter_content_js': 'C',
      'sample_url': '',
      'created_at': now,
      'last_used_at': now,
      'use_count': 0,
      'verified': 0,
      'preferred_mode': 1,
    });
    await db.insert('site_scripts', {
      'id': 's2',
      'domain': 'm.mobile-site.com',
      'url_pattern': '',
      'chapter_list_js': 'L',
      'chapter_content_js': 'C',
      'sample_url': '',
      'created_at': now,
      'last_used_at': now,
      'use_count': 0,
      'verified': 0,
      'preferred_mode': 2,
    });

    final rows = await db.query('site_scripts', orderBy: 'id');
    expect(rows.first['preferred_mode'], 1);
    expect(rows.last['preferred_mode'], 2);
    await db.close();
  });
}
