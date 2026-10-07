import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/repositories/chapter_version_repository.dart';
import 'package:novel_app/repositories/chapter_repository.dart';
import 'package:novel_app/models/chapter_version.dart';
import 'package:novel_app/models/chapter.dart';

import '../../helpers/test_database_setup.dart';

/// ChapterVersionRepository 集成测试
///
/// 使用真实内存数据库验证版本 CRUD 和淘汰逻辑
void main() {
  late ChapterVersionRepository versionRepo;
  late ChapterRepository chapterRepo;

  setUp(() async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    final connection = DatabaseConnection.forTesting(db);
    versionRepo = ChapterVersionRepository(dbConnection: connection);
    chapterRepo = ChapterRepository(
      dbConnection: connection,
      versionRepo: versionRepo,
    );
  });

  // ============================================================
  // 辅助方法
  // ============================================================

  /// 创建版本记录
  Future<int> createVersion(
    String chapterUrl, {
    String source = 'edit',
    String content = '旧内容',
    int createdAt = 0,
  }) async {
    return versionRepo.saveVersion(ChapterVersion(
      chapterUrl: chapterUrl,
      content: content,
      source: source,
      createdAt: createdAt > 0
          ? createdAt
          : DateTime.now().millisecondsSinceEpoch,
      contentLength: content.length,
    ));
  }

  // ============================================================
  // saveVersion / getVersions
  // ============================================================

  group('saveVersion & getVersions', () {
    test('应插入版本记录并返回 ID', () async {
      final id = await createVersion('url1', content: '版本1');
      expect(id, greaterThan(0));
    });

    test('应按创建时间降序返回版本列表', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await createVersion('url1', content: '最早', createdAt: now - 3000);
      await createVersion('url1', content: '居中', createdAt: now - 2000);
      await createVersion('url1', content: '最新', createdAt: now - 1000);

      final versions = await versionRepo.getVersions('url1');
      expect(versions.length, 3);
      expect(versions[0].content, '最新');
      expect(versions[2].content, '最早');
    });

    test('不同章节的版本应独立', () async {
      await createVersion('url1', content: '章节1');
      await createVersion('url2', content: '章节2');

      final v1 = await versionRepo.getVersions('url1');
      final v2 = await versionRepo.getVersions('url2');
      expect(v1.length, 1);
      expect(v2.length, 1);
      expect(v1.first.content, '章节1');
      expect(v2.first.content, '章节2');
    });
  });

  // ============================================================
  // getVersionCount
  // ============================================================

// ============================================================
  // getVersionById
  // ============================================================

// ============================================================
  // deleteVersion
  // ============================================================

// ============================================================
  // deleteVersionsByNovel
  // ============================================================

  group('deleteVersionsByNovel', () {
    test('应通过 chapter_cache JOIN 删除小说所有章节的版本', () async {
      // 先在 chapter_cache 中创建两条记录关联到同一小说
      await chapterRepo.cacheChapter(
        'novel1',
        Chapter(title: '章节1', url: 'url1'),
        '内容1',
      );
      await chapterRepo.cacheChapter(
        'novel1',
        Chapter(title: '章节2', url: 'url2'),
        '内容2',
      );

      // 为两条章节各创建一个版本
      await createVersion('url1');
      await createVersion('url2');

      final affected = await versionRepo.deleteVersionsByNovel('novel1');
      expect(affected, 2);
    });
  });

  // ============================================================
  // evictOldestVersions
  // ============================================================

// ============================================================
  // ChapterRepository 拦截测试
  // ============================================================

group('ChapterRepository 级联删除', () {
    test('deleteCachedChapters 应级联删除版本', () async {
      await chapterRepo.cacheChapter(
        'novel1',
        Chapter(title: '章节1', url: 'url1'),
        '内容1',
      );
      await chapterRepo.cacheChapter(
        'novel1',
        Chapter(title: '章节2', url: 'url2'),
        '内容2',
      );
      await createVersion('url1');
      await createVersion('url2');

      await chapterRepo.deleteCachedChapters('novel1');

      expect(await versionRepo.getVersions('url1'), isEmpty);
      expect(await versionRepo.getVersions('url2'), isEmpty);
    });
  });
}
