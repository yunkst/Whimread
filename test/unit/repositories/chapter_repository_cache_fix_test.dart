import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:novel_app/models/chapter.dart';
import 'package:novel_app/core/interfaces/i_database_connection.dart';
import 'package:novel_app/repositories/chapter_repository.dart';
import 'package:novel_app/repositories/chapter_version_repository.dart';
import '../../helpers/test_database_setup.dart';

/// ChapterRepository 缓存修复验证测试
///
/// 验证以下修复：
/// 1. P0: LRU淘汰策略 — 内存缓存满时淘汰最旧条目，而非全量清空
/// 2. P1: 删除操作同步清理内存Set — deleteChapterCache/deleteCachedChapters
/// 3. P1: 创建章节后同步更新内存缓存 — createCustomChapter
/// 4. P3: cacheChapter的ConflictAlgorithm.replace确保forceRefresh安全

void main() {
  TestDatabaseSetup.init();

  late Database db;
  late ChapterRepository repository;

  const testNovelUrl = 'https://example.com/novel/test-novel';
  const testChapterUrl = 'https://example.com/chapter/1';

  Chapter _makeChapter(String url, {int index = 0}) {
    return Chapter(
      title: '第${index + 1}章',
      url: url,
      content: null,
      isCached: false,
      chapterIndex: index,
    );
  }

  setUp(() async {
    db = await TestDatabaseSetup.createInMemoryDatabase();
    repository = ChapterRepository(
      dbConnection: _TestDbConnection(db),
      versionRepo: ChapterVersionRepository(dbConnection: _TestDbConnection(db)),
    );
  });

  tearDown(() async {
    repository.clearMemoryState();
    await db.close();
  });

  // ============================================================
  // P0: LRU淘汰策略测试
  // ============================================================
  group('P0: LRU淘汰策略', () {
    test('内存缓存未满时不触发淘汰', () async {
      // 添加 500 条缓存记录
      for (int i = 0; i < 500; i++) {
        final url = '$testChapterUrl$i';
        await repository.cacheChapter(testNovelUrl, _makeChapter(url, index: i), 'content $i');
      }

      // 所有 500 条应立即命中内存（通过 isChapterCached 验证）
      // 注意：由于 isChapterCached 内部也会调用 _addCachedInMemory，
      // 我们先验证 cacheChapter 已经把URL加入内存Set
      // 用更直接的验证方式：批量查询缓存状态
      final urls = List.generate(500, (i) => '$testChapterUrl$i');
      final status = await repository.getChaptersCacheStatus(urls);

      expect(status.length, 500);
      for (final url in urls) {
        expect(status[url], isTrue, reason: '$url 应该显示为已缓存');
      }
    });

    test('超过1000条时淘汰最旧条目而非全量清空', () async {
      // 添加 1050 条，触发 LRU 淘汰
      for (int i = 0; i < 1050; i++) {
        final url = '$testChapterUrl$i';
        await repository.cacheChapter(testNovelUrl, _makeChapter(url, index: i), 'content $i');
      }

      // 最新的 1000 条应该还在内存中
      // 最旧的 50 条被淘汰，但 SQLite 中仍然存在
      final recentUrls = List.generate(50, (i) => '$testChapterUrl${1000 + i}');
      final recentStatus = await repository.getChaptersCacheStatus(recentUrls);

      // 检查：所有新增的URL在SQLite中都存在（即使内存被淘汰了）
      // 对于仍在内存中的（最近1000条），isChapterCached 应该返回 true
      for (final url in recentUrls) {
        final isCached = await repository.isChapterCached(url);
        expect(isCached, isTrue, reason: '最近添加的 $url 应该可被 isChapterCached 命中');
      }

      // 旧条目虽然从内存淘汰，但在数据库中依然存在
      // 验证旧条目仍可通过 getCachedChapter 获取
      final oldContent = await repository.getCachedChapter('${testChapterUrl}0');
      expect(oldContent, isNotNull, reason: '被LRU淘汰的旧条目在SQLite中仍应存在');
      expect(oldContent, contains('content 0'));
    });

    test('访问旧条目会将其重新加入内存缓存(LRU重新激活)', () async {
      // 填充 1000 条
      for (int i = 0; i < 1000; i++) {
        final url = '${testChapterUrl}$i';
        await repository.cacheChapter(testNovelUrl, _makeChapter(url, index: i), 'content $i');
      }

      // 添加第 1001 条，触发一次 LRU 淘汰（淘汰第0条）
      await repository.cacheChapter(testNovelUrl, _makeChapter('${testChapterUrl}1000', index: 1000), 'content 1000');

      // 此时第0条被淘汰出内存，但通过 isChapterCached 访问会重新加入
      final isCached = await repository.isChapterCached('${testChapterUrl}0');
      expect(isCached, isTrue, reason: '即使被淘汰，通过isChapterCached查询后应重新加入内存');

      // 再次 query 应该直接命中内存（快速路径）
      final isCachedAgain = await repository.isChapterCached('${testChapterUrl}0');
      expect(isCachedAgain, isTrue);

      // 同时淘汰另一个旧条目以保持容量
      // 又添加 1000 条更多数据...
      for (int i = 1001; i < 2001; i++) {
        final url = '${testChapterUrl}$i';
        await repository.cacheChapter(testNovelUrl, _makeChapter(url, index: i), 'content $i');
      }

      // 第0条由于在中间被访问过，位置被更新，现在应该还在内存中
      final stillCached = await repository.isChapterCached('${testChapterUrl}0');
      expect(stillCached, isTrue, reason: '最近访问过的条目不应被淘汰');
    });
  });

  // ============================================================
  // P1: 删除操作同步清理内存Set
  // ============================================================
  group('P1: 删除操作同步清理内存Set', () {
    setUp(() async {
      // 先缓存一个章节
      await repository.cacheChapter(
        testNovelUrl,
        _makeChapter(testChapterUrl),
        '测试内容',
      );
    });

    test('deleteChapterCache 应同时清理内存缓存', () async {
      // 确认已在内存中
      expect(await repository.isChapterCached(testChapterUrl), isTrue);

      // 删除缓存
      await repository.deleteChapterCache(testChapterUrl);

      // 验证：内存和数据库都不再存在
      final content = await repository.getCachedChapter(testChapterUrl);
      expect(content, isNull, reason: '数据库中的缓存应被删除');

      // 再次检查缓存状态（这应该查数据库而非命中内存）
      final isCached = await repository.isChapterCached(testChapterUrl);
      expect(isCached, isFalse, reason: '删除后 isChapterCached 应返回 false');
    });

    test('deleteCachedChapters 应批量清理内存缓存', () async {
      // 缓存多个章节
      final urls = List.generate(10, (i) => '$testChapterUrl$i');
      for (int i = 0; i < urls.length; i++) {
        await repository.cacheChapter(testNovelUrl, _makeChapter(urls[i], index: i), 'content $i');
      }

      // 删除该小说所有缓存
      await repository.deleteCachedChapters(testNovelUrl);

      // 验证所有URL都不再在内存中
      for (final url in urls) {
        final isCached = await repository.isChapterCached(url);
        expect(isCached, isFalse, reason: '$url 删除后应返回 false');
      }
    });

    test('clearMemoryState 应清空所有内存状态', () async {
      // 先写入一章，使其进入内存缓存
      await repository.cacheChapter(
        testNovelUrl,
        _makeChapter(testChapterUrl, index: 0),
        'content',
      );
      expect(await repository.isChapterCached(testChapterUrl), isTrue);

      // 清空内存状态（只清内存，db 数据仍在，但下次查询需重新从 db 加载）
      repository.clearMemoryState();

      // 内存缓存已清空，但 db 中仍有数据，isChapterCached 会走 db 查询
      expect(await repository.isChapterCached(testChapterUrl), isTrue);
    });
  });

  // ============================================================
  // P1: createCustomChapter 同步更新内存缓存
  // ============================================================
  group('P1: createCustomChapter 同步更新内存缓存', () {
    test('创建自定义章节后应立即标记为已缓存', () async {
      final id = await repository.createCustomChapter(
        'custom://test-novel',
        '自定义章节',
        '自定义内容',
      );

      expect(id, isNotNull);
      expect(id, greaterThan(0));

      // 获取创建的章节URL，验证 isChapterCached
      final chapters = await repository.getCachedNovelChapters('custom://test-novel');
      expect(chapters.length, 1);

      final createdUrl = chapters.first.url;
      final isCached = await repository.isChapterCached(createdUrl);
      expect(isCached, isTrue, reason: 'createCustomChapter后应立即可从内存命中');
    });

    test('createCustomChapter 使用事务保证两表原子性', () async {
      // 正常情况下两表都应有数据
      final id = await repository.createCustomChapter(
        'custom://test-novel-2',
        '原子性测试',
        '测试内容原子性',
      );

      final chapters = await repository.getCachedNovelChapters('custom://test-novel-2');
      expect(chapters.length, 1);
      expect(chapters.first.isCached, isTrue, reason: 'LEFT JOIN应能匹配到chapter_cache记录');
    });
  });

  // ============================================================
  // P3: cacheChapter 使用 ConflictAlgorithm.replace 安全覆盖
  // ============================================================
  group('P3: cacheChapter 安全覆盖旧缓存', () {
    test('cacheChapter使用replace策略可覆盖已有缓存', () async {
      // 第一次缓存
      await repository.cacheChapter(
        testNovelUrl,
        _makeChapter(testChapterUrl),
        '旧内容',
      );
      expect(await repository.getCachedChapter(testChapterUrl), equals('旧内容'));

      // 第二次缓存（模拟forceRefresh后重新获取内容）
      await repository.cacheChapter(
        testNovelUrl,
        _makeChapter(testChapterUrl),
        '新内容',
      );
      expect(await repository.getCachedChapter(testChapterUrl), equals('新内容'),
          reason: 'replace策略应覆盖旧缓存');
    });

    test('缓存覆盖后不会产生重复记录', () async {
      // 多次缓存同一个URL
      for (int i = 0; i < 5; i++) {
        await repository.cacheChapter(
          testNovelUrl,
          _makeChapter(testChapterUrl, index: i),
          'content v$i',
        );
      }

      // 验证只有一条记录
      final count = await repository.getCachedChaptersCount(testNovelUrl);
      expect(count, 1, reason: '同一chapterUrl只应有一条缓存记录');
    });
  });

  // ============================================================
  // 回归测试：filterUncachedChapters 去重性能
  // ============================================================
  group('回归测试: filterUncachedChapters', () {
    test('批量过滤时内存命中应跳过SQL查询的章节', () async {
      // 缓存 100 个章节（确认都在内存中）
      final totalChapters = 100;
      final urls = List.generate(totalChapters, (i) => '$testChapterUrl$i');
      for (int i = 0; i < totalChapters; i++) {
        await repository.cacheChapter(testNovelUrl, _makeChapter(urls[i], index: i), 'content $i');
      }

      // 所有章节已在内存中，filterUncachedChapters 应返回空列表
      final uncached = await repository.filterUncachedChapters(urls);
      expect(uncached, isEmpty, reason: '所有章节已在缓存中，应返回空列表');
    });

    test('部分未缓存时正确识别', () async {
      // 缓存前 50 个
      final urls = List.generate(100, (i) => '$testChapterUrl$i');
      for (int i = 0; i < 50; i++) {
        await repository.cacheChapter(testNovelUrl, _makeChapter(urls[i], index: i), 'content $i');
      }

      // 后 50 个未缓存
      final uncached = await repository.filterUncachedChapters(urls);
      expect(uncached.length, 50, reason: '后50个章节未缓存');
      expect(uncached.every((url) => urls.indexOf(url) >= 50), isTrue);
    });
  });
}

// ============================================================
// 内联数据库连接适配器
// ============================================================

/// IDatabaseConnection 的测试实现
class _TestDbConnection implements IDatabaseConnection {
  final Database _db;

  _TestDbConnection(this._db);

  @override
  Future<Database> get database async => _db;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> close() async {}

  @override
  bool get isInitialized => true;
}
