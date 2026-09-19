/// v47 迁移测试：site_scripts 加来源/共享/启用列（脚本共享）
///
/// 验证：
/// - 升级路径 v46 → v47：7 个新列被添加
/// - 新装路径：列存在且默认值正确（source='local'、enabled=1、shared=0）
/// - 旧脚本升级后默认 source='local' / enabled=1，与原行为一致
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

  test('升级路径 v46 → v47：site_scripts 来源/共享/启用 7 列被添加', () async {
    final db = await openAtVersion(46);

    // 回归前提：v46 时这些列均不存在
    final columnsBefore = await db.rawQuery(
      "PRAGMA table_info(site_scripts)",
    );
    final namesBefore = columnsBefore.map((c) => c['name']).toSet();
    for (final col in const [
      'source',
      'remote_id',
      'remote_version',
      'sha256',
      'shared',
      'last_synced_at',
      'enabled',
    ]) {
      expect(namesBefore, isNot(contains(col)), reason: 'v46 不应存在 $col');
    }

    await DatabaseMigrations.upgrade(db, 46, DatabaseMigrations.currentVersion);

    final columnsAfter = await db.rawQuery("PRAGMA table_info(site_scripts)");
    final namesAfter = columnsAfter.map((c) => c['name']).toSet();
    for (final col in const [
      'source',
      'remote_id',
      'remote_version',
      'sha256',
      'shared',
      'last_synced_at',
      'enabled',
    ]) {
      expect(namesAfter, contains(col), reason: 'v47 应存在 $col');
    }
    await db.close();
  });

  test('升级路径：存量脚本默认 source=local / shared=0 / enabled=1', () async {
    final db = await openAtVersion(46);
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
      'preferred_mode': 1,
    });

    await DatabaseMigrations.upgrade(db, 46, DatabaseMigrations.currentVersion);

    final rows = await db.query('site_scripts');
    expect(rows.single['source'], 'local');
    expect(rows.single['shared'], 0);
    expect(rows.single['enabled'], 1);
    expect(rows.single['remote_version'], 0);
    expect(rows.single['last_synced_at'], 0);
    expect(rows.single['remote_id'], isNull);
    expect(rows.single['sha256'], isNull);
    // 老字段不受影响
    expect(rows.single['preferred_mode'], 1);
    expect(rows.single['verified'], 0);
    await db.close();
  });

  test('新装路径：云端下载脚本可正常写入并按 remote_id 查询', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('site_scripts', {
      'id': 'remote1',
      'domain': 'www.cloud-site.com',
      'url_pattern': '',
      'chapter_list_js': 'L',
      'chapter_content_js': 'C',
      'bookshelf_js': 'B',
      'sample_url': '',
      'display_name': '云端站',
      'created_at': now,
      'last_used_at': now,
      'use_count': 0,
      'verified': 1,
      'preferred_mode': 2,
      'source': 'remote',
      'remote_id': '8e1c2b40-1234-4abc-9def-000000000001',
      'remote_version': 3,
      'sha256': 'a' * 64,
      'shared': 0,
      'last_synced_at': now,
      'enabled': 1,
    });

    // 按 remote_id 索引查询
    final rows = await db.query(
      'site_scripts',
      where: 'remote_id = ?',
      whereArgs: ['8e1c2b40-1234-4abc-9def-000000000001'],
    );
    expect(rows, hasLength(1));
    expect(rows.first['source'], 'remote');
    expect(rows.first['remote_version'], 3);
    expect(rows.first['bookshelf_js'], 'B');
    await db.close();
  });
}
