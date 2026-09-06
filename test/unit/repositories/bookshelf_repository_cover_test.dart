import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqflite.dart';

import 'package:novel_app/models/novel.dart';
import 'package:novel_app/repositories/novel_repository.dart';
import 'package:novel_app/repositories/bookshelf_repository.dart';
import 'package:novel_app/core/database/database_connection.dart';
import '../../helpers/test_database_setup.dart' as test_db;

/// getNovelsByBookshelf 应携带 coverMediaId（NovelCover 渲染依赖）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late BookshelfRepository bookshelfRepo;
  late NovelRepository novelRepo;

  setUp(() async {
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    bookshelfRepo =
        BookshelfRepository(dbConnection: DatabaseConnection.forTesting(db));
    novelRepo =
        NovelRepository(dbConnection: DatabaseConnection.forTesting(db));
  });

  tearDown(() async {
    await db.close();
  });

  test('全部小说书架(id=1)返回的 Novel 带 coverMediaId', () async {
    final id = await novelRepo.addToBookshelf(
      Novel(title: '书1', author: '作者', url: 'custom://b1'),
    );
    await novelRepo.updateCoverMediaIdById(id, 'cover-media-1');

    final novels = await bookshelfRepo.getNovelsByBookshelf(1);
    final target = novels.firstWhere((n) => n.url == 'custom://b1');

    expect(target.coverMediaId, 'cover-media-1');
  });
}
