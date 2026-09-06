import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqflite.dart';

import 'package:novel_app/repositories/novel_repository.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/core/database/database_connection.dart';
import '../../helpers/test_database_setup.dart' as test_db;

/// updateCoverMediaIdById 集成测试（真实内存 SQLite，跑完整迁移）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late NovelRepository repo;

  setUp(() async {
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    repo = NovelRepository(dbConnection: DatabaseConnection.forTesting(db));
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedNovel(String url) async {
    final id = await repo.addToBookshelf(Novel(
      title: '测试小说',
      author: '作者',
      url: url,
    ));
    return id;
  }

  test('写入 mediaId 后可读回', () async {
    final id = await seedNovel('custom://n1');
    final affected = await repo.updateCoverMediaIdById(id, 'media-1');
    expect(affected, 1);

    final novel = await repo.getNovelById(id);
    expect(novel?.coverMediaId, 'media-1');
  });

  test('传入 null 清空封面', () async {
    final id = await seedNovel('custom://n2');
    await repo.updateCoverMediaIdById(id, 'media-2');
    await repo.updateCoverMediaIdById(id, null);

    final novel = await repo.getNovelById(id);
    expect(novel?.coverMediaId, isNull);
  });

  test('不存在的 id 返回 0', () async {
    final affected = await repo.updateCoverMediaIdById(99999, 'media-x');
    expect(affected, 0);
  });

  // ========== updateCoverMediaIdByUrl（书架页 UI 清封面用） ==========

  test('updateCoverMediaIdByUrl 写入 mediaId 后可读回', () async {
    final id = await seedNovel('custom://u1');
    final affected =
        await repo.updateCoverMediaIdByUrl('custom://u1', 'media-u1');
    expect(affected, 1);

    final novel = await repo.getNovelByUrl('custom://u1');
    expect(novel?.coverMediaId, 'media-u1');
    // 交叉验证 id-based 也读到一致
    final byId = await repo.getNovelById(id);
    expect(byId?.coverMediaId, 'media-u1');
  });

  test('updateCoverMediaIdByUrl 传入 null 清空封面', () async {
    await seedNovel('custom://u2');
    await repo.updateCoverMediaIdByUrl('custom://u2', 'media-u2');
    final affected = await repo.updateCoverMediaIdByUrl('custom://u2', null);
    expect(affected, 1);

    final novel = await repo.getNovelByUrl('custom://u2');
    expect(novel?.coverMediaId, isNull);
  });

  test('updateCoverMediaIdByUrl 不存在的 url 返回 0', () async {
    final affected = await repo.updateCoverMediaIdByUrl(
      'custom://not-exist',
      'media-x',
    );
    expect(affected, 0);
  });
}
