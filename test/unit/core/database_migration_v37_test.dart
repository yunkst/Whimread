import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:novel_app/core/database/database_migrations.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v37 迁移给 site_scripts 加 ocr 列', () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 37,
        onCreate: (db, v) async {
      await DatabaseMigrations.createV1Tables(db);
      await DatabaseMigrations.upgrade(db, 1, 37);
    });

    final cols = await db.rawQuery(
      'PRAGMA table_info(site_scripts)',
    );
    final ocrCol = cols.firstWhere(
      (c) => c['name'] == 'ocr',
      orElse: () => throw StateError('ocr 列不存在'),
    );
    expect(ocrCol['type'], 'INTEGER');
    expect(ocrCol['dflt_value'], '0');
    expect(ocrCol['notnull'], 1);

    // 现有行 ocr 默认 0（插一行不传 ocr 验证）
    await db.insert('site_scripts', {
      'id': 't1',
      'domain': 'x.com',
      'chapter_list_js': '',
      'chapter_content_js': '',
      'created_at': 0,
      'last_used_at': 0,
      'use_count': 0,
      'verified': 0,
    });
    final row = await db.query('site_scripts', where: 'id = ?', whereArgs: ['t1']);
    expect(row.first['ocr'], 0);

    await db.close();
  });

  test('currentVersion == 39', () {
    expect(DatabaseMigrations.currentVersion, 39);
  });
}
