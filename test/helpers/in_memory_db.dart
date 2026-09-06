import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:novel_app/core/database/database_migrations.dart';

/// 测试用:初始化 sqflite_ffi 并返回一个跑完所有迁移的 in-memory 数据库。
///
/// DatabaseMigrations 暴露的是 `createV1Tables(db)` 与 `upgrade(db, from, to)`
/// (不是 onCreate/onUpgrade),这与 database_connection.dart 的 _onCreate/_onUpgrade
/// 实现一致:createV1Tables 建基础表,再 upgrade(db, 1, version) 跑全部迁移。
Future<Database> setupInMemoryDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(
    ':memory:',
    version: DatabaseMigrations.currentVersion,
    // SQLite 默认关闭 foreign_keys,PRAGMA 是 per-connection 的;
    // 在 onConfigure 里开,让 ON DELETE CASCADE 生效(与生产
    // database_connection.dart 的 PRAGMA foreign_keys = ON 一致)。
    onConfigure: (db) async {
      await db.execute('PRAGMA foreign_keys = ON');
    },
    onCreate: (db, version) async {
      await DatabaseMigrations.createV1Tables(db);
      await DatabaseMigrations.upgrade(db, 1, version);
    },
  );
  return db;
}
