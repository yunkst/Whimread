import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqflite.dart';

import '../../helpers/test_database_setup.dart' as test_db;

/// v36 迁移验证：bookshelf 表必须有 coverMediaId 列。
/// TestDatabaseSetup.createInMemoryDatabase 会跑 createV1Tables + upgrade(1, currentVersion)，
/// 故只要 currentVersion 升到 36 且 case 36 执行 ALTER，此处即通过。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;

  setUp(() async {
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  test('bookshelf 表包含 coverMediaId 列', () async {
    final columns = await db.rawQuery('PRAGMA table_info(bookshelf)');
    final names = columns.map((c) => c['name'] as String).toSet();

    expect(names, contains('coverMediaId'));
  });
}
