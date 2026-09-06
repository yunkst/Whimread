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

  /// 创建一个测试章节缓存
  Future<void> createTestChapterCache(
      String novelUrl, String chapterUrl, String content) async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    // 直接用 chapterRepo.cacheChapter
    await chapterRepo.cacheChapter(
      novelUrl,
      Chapter(title: '测试章节', url: chapterUrl),
      content,
    );
  }

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

  group('getVersionCount', () {
    test('无版本时应返回 0', () async {
      final count = await versionRepo.getVersionCount('url1');
      expect(count, 0);
    });

    test('应返回正确数量', () async {
      await createVersion('url1');
      await createVersion('url1');
      await createVersion('url1');

      final count = await versionRepo.getVersionCount('url1');
      expect(count, 3);
    });
  });

  // ============================================================
  // getVersionById
  // ============================================================

  group('getVersionById', () {
    test('不存在的 ID 应返回 null', () async {
      final version = await versionRepo.getVersionById(9999);
      expect(version, isNull);
    });

    test('应返回对应版本', () async {
      final id = await createVersion('url1', content: '特定版本');
      final version = await versionRepo.getVersionById(id);
      expect(version, isNotNull);
      expect(version!.content, '特定版本');
    });
  });

  // ============================================================
  // deleteVersion
  // ============================================================

  group('deleteVersion', () {
    test('应删除指定版本', () async {
      final id = await createVersion('url1');
      final affected = await versionRepo.deleteVersion(id);
      expect(affected, 1);

      final version = await versionRepo.getVersionById(id);
      expect(version, isNull);
    });

    test('删除不存在的 ID 应返回 0', () async {
      final affected = await versionRepo.deleteVersion(9999);
      expect(affected, 0);
    });
  });

  // ============================================================
  // deleteVersionsByChapter
  // ============================================================

  group('deleteVersionsByChapter', () {
    test('应删除章节的所有版本', () async {
      await createVersion('url1');
      await createVersion('url1');
      await createVersion('url2');

      final affected = await versionRepo.deleteVersionsByChapter('url1');
      expect(affected, 2);

      final remaining = await versionRepo.getVersions('url1');
      expect(remaining.length, 0);

      final other = await versionRepo.getVersions('url2');
      expect(other.length, 1);
    });
  });

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

  group('evictOldestVersions', () {
    test('版本数 <= 5 时不应删除', () async {
      for (int i = 0; i < 5; i++) {
        await createVersion('url1', createdAt: DateTime.now().millisecondsSinceEpoch + i * 1000);
      }

      final deleted = await versionRepo.evictOldestVersions('url1', maxCount: 5);
      expect(deleted, 0);

      final count = await versionRepo.getVersionCount('url1');
      expect(count, 5);
    });

    test('版本数 > 5 时应删除最老的版本', () async {
      final baseTime = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < 8; i++) {
        await createVersion('url1', createdAt: baseTime + i * 1000);
      }

      final deleted = await versionRepo.evictOldestVersions('url1', maxCount: 5);
      expect(deleted, 3);

      final versions = await versionRepo.getVersions('url1');
      expect(versions.length, 5);

      // 确认保留的是最新的 5 个（createdAt 最大的）
      final times = versions.map((v) => v.createdAt).toList();
      for (int i = 0; i < times.length - 1; i++) {
        expect(times[i], greaterThanOrEqualTo(times[i + 1]));
      }
    });

    test('多次调用应是幂等的', () async {
      final baseTime = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < 8; i++) {
        await createVersion('url1', createdAt: baseTime + i * 1000);
      }

      await versionRepo.evictOldestVersions('url1', maxCount: 5);
      final deleted2 = await versionRepo.evictOldestVersions('url1', maxCount: 5);
      expect(deleted2, 0);

      final count = await versionRepo.getVersionCount('url1');
      expect(count, 5);
    });
  });

  // ============================================================
  // ChapterRepository 拦截测试
  // ============================================================

  group('ChapterRepository.updateChapterContent 拦截', () {
    test('更新内容前应自动保存旧版本', () async {
      // 先缓存章节
      await chapterRepo.cacheChapter(
        'novel1',
        Chapter(title: '测试', url: 'url1'),
        '原始内容',
      );

      // 更新内容
      await chapterRepo.updateChapterContent('url1', '新内容');

      // 验证版本表中有旧内容
      final versions = await versionRepo.getVersions('url1');
      expect(versions.length, 1);
      expect(versions.first.content, '原始内容');
      expect(versions.first.source, 'edit');
    });

    test('source 参数应正确传递', () async {
      await chapterRepo.cacheChapter(
        'novel1',
        Chapter(title: '测试', url: 'url1'),
        '原始内容',
      );

      await chapterRepo.updateChapterContent(
        'url1', 'AI改写内容',
        source: 'ai_rewrite',
      );

      final versions = await versionRepo.getVersions('url1');
      expect(versions.first.source, 'ai_rewrite');
    });

    test('更新后应自动淘汰超限版本', () async {
      await chapterRepo.cacheChapter(
        'novel1',
        Chapter(title: '测试', url: 'url1'),
        'v0',
      );

      // 连续更新 6 次，应只保留 5 个版本
      for (int i = 1; i <= 6; i++) {
        await chapterRepo.updateChapterContent('url1', 'v$i');
      }

      final count = await versionRepo.getVersionCount('url1');
      expect(count, 5);
    });

    test('空内容不应保存版本', () async {
      await chapterRepo.cacheChapter(
        'novel1',
        Chapter(title: '测试', url: 'url1'),
        '', // 空内容
      );

      await chapterRepo.updateChapterContent('url1', '新内容');

      final versions = await versionRepo.getVersions('url1');
      expect(versions.length, 0);
    });

    test('新内容与旧内容相同时不应创建版本', () async {
      await chapterRepo.cacheChapter(
        'novel1',
        Chapter(title: '测试', url: 'url1'),
        '相同内容',
      );

      // 用相同内容更新，不应创建版本
      await chapterRepo.updateChapterContent('url1', '相同内容');

      final versions = await versionRepo.getVersions('url1');
      expect(versions.length, 0);
    });

    test('还原到已有版本时内容重复不应创建版本', () async {
      await chapterRepo.cacheChapter(
        'novel1',
        Chapter(title: '测试', url: 'url1'),
        '原始内容',
      );

      // 第一次编辑：旧内容不同，应创建版本
      await chapterRepo.updateChapterContent('url1', '修改后内容');
      expect(await versionRepo.getVersionCount('url1'), 1);

      // 还原到原始内容：当前内容='修改后内容'，目标='原始内容'，不同 → 应创建版本
      await chapterRepo.updateChapterContent('url1', '原始内容', source: 'restore');
      expect(await versionRepo.getVersionCount('url1'), 2);

      // 再次还原到相同内容：当前='原始内容'，目标='原始内容'，相同 → 不应创建版本
      await chapterRepo.updateChapterContent('url1', '原始内容', source: 'restore');
      expect(await versionRepo.getVersionCount('url1'), 2);
    });
  });

  group('ChapterRepository 级联删除', () {
    test('deleteChapterCache 应级联删除版本', () async {
      await chapterRepo.cacheChapter(
        'novel1',
        Chapter(title: '测试', url: 'url1'),
        '内容',
      );
      await createVersion('url1');

      await chapterRepo.deleteChapterCache('url1');

      final versions = await versionRepo.getVersions('url1');
      expect(versions.length, 0);
    });

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

      expect(await versionRepo.getVersionCount('url1'), 0);
      expect(await versionRepo.getVersionCount('url2'), 0);
    });
  });
}
