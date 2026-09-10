/// v40 迁移测试：site_scripts 加 bookshelf_js 列（网站书架提取脚本槽）
///
/// 镜像 v37 迁移测试（database_migration_v37_test.dart）的形态：
/// - 真实内存 SQLite（sqfliteFfiInit）
/// - 通过 createV1Tables + upgrade(1, 40) 构造完整库
/// - PRAGMA table_info 检查新列存在 + 默认值
/// - 插入/读取确认整条路可走
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novel_app/core/database/database_migrations.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v40 迁移给 site_scripts 加 bookshelf_js 列', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 40,
      onCreate: (db, v) async {
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, 40);
      },
    );

    final cols = await db.rawQuery('PRAGMA table_info(site_scripts)');
    final bsCol = cols.firstWhere(
      (c) => c['name'] == 'bookshelf_js',
      orElse: () => throw StateError('bookshelf_js 列不存在'),
    );
    expect(bsCol['type'], 'TEXT');
    // SQLite 把 TEXT DEFAULT '' 的默认值表达式存成字面两个单引号字符
    expect(bsCol['dflt_value'], "''");
    expect(bsCol['notnull'], 1);

    // 不传 bookshelf_js 插入一行 → 默认 ''
    await db.insert('site_scripts', {
      'id': 't_bs1',
      'domain': 'x.com',
      'chapter_list_js': '',
      'chapter_content_js': '',
      'created_at': 0,
      'last_used_at': 0,
      'use_count': 0,
      'verified': 0,
    });
    final row =
        await db.query('site_scripts', where: 'id = ?', whereArgs: ['t_bs1']);
    expect(row.first['bookshelf_js'], '');

    // 显式写入 bookshelf_js → 可读回
    await db.update(
      'site_scripts',
      {'bookshelf_js': 'const N=[...]; return JSON.stringify({novels:N});'},
      where: 'id = ?',
      whereArgs: ['t_bs1'],
    );
    final row2 =
        await db.query('site_scripts', where: 'id = ?', whereArgs: ['t_bs1']);
    expect(row2.first['bookshelf_js'], contains('novels'));

    await db.close();
  });

  test('currentVersion == 42', () {
    expect(DatabaseMigrations.currentVersion, 42);
  });
}