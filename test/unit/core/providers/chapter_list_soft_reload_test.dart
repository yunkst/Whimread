/// ChapterList softReload 集成测试
///
/// 验证 `chapterMutationSignalProvider` 的 bump 触发 [ChapterList.softReload]：
/// - state.chapters 反映最新 DB 数据
/// - currentPage 保留（不跳页）
/// - isLoading 不闪（保持 false）
///
/// 用真实 in-memory DB + fake ChapterLoader（loadChapters 返回可控列表），
/// 避免 mock 整个 loader 依赖链。
///
/// chaptersPerPage=100，故填 101 章使 totalPages=2，goToPage(2) 才能成功——
/// 验证"softReload 保留非默认 currentPage"语义。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/core/providers/chapter_list_soft_reload_test.dart
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novel_app/controllers/chapter_list/chapter_loader.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/database/database_migrations.dart';
import 'package:novel_app/core/providers/chapter_list_providers.dart';
import 'package:novel_app/core/providers/chapter_mutation_signal_provider.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/services/database_service_providers.dart';
import 'package:novel_app/models/chapter.dart';
import 'package:novel_app/models/novel.dart';

/// Fake ChapterLoader：loadChapters 返回由测试设置的 chapters 列表。
///
/// ChapterList.build 的 _initializeData 会调 initApi / checkBookshelfStatus /
/// loadLastReadChapter / _loadChapters；softReload 只调 loadChapters。
/// fakeLoader 给所有方法 no-op / 返回初始 chapters。
class _FakeChapterLoader implements ChapterLoader {
  List<Chapter> chaptersToReturn;
  Object? throwOnLoad;

  _FakeChapterLoader(this.chaptersToReturn);

  @override
  Future<List<Chapter>> loadChapters(String novelUrl,
          {bool forceRefresh = false}) async {
    if (throwOnLoad != null) {
      final e = throwOnLoad!;
      throwOnLoad = null;
      throw e;
    }
    return chaptersToReturn;
  }

  @override
  Future<void> initApi() async {}

  @override
  Future<List<Chapter>> refreshFromBackend(String novelUrl,
          {bool forceRefresh = false}) async =>
      chaptersToReturn;

  @override
  Future<int> loadLastReadChapter(String novelUrl) async => -1;
}

List<Chapter> _chapters(int n) => List.generate(
      n,
      (i) => Chapter(title: '第 ${i + 1} 章', url: 'u$i', chapterIndex: i),
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late ProviderContainer container;
  late _FakeChapterLoader fakeLoader;

  setUp(() async {
    // 真实 in-memory DB（ChapterRepository 需要 versionRepo，但 softReload 路径
    // 不经 writer，versionRepo 不会被触发；fakeLoader 接管 loadChapters）。
    final db = await openDatabase(
      ':memory:',
      version: DatabaseMigrations.currentVersion,
      singleInstance: false,
    );
    await DatabaseMigrations.createV1Tables(db);
    await DatabaseMigrations.upgrade(db, 1, DatabaseMigrations.currentVersion);

    fakeLoader = _FakeChapterLoader([]);

    container = ProviderContainer(overrides: [
      databaseConnectionProvider
          .overrideWithValue(DatabaseConnection.forTesting(db)),
      chapterLoaderProvider.overrideWithValue(fakeLoader),
    ]);
  });

  tearDown(() {
    container.dispose();
  });

  test('bump signal → softReload 重读 chapters，currentPage 保留', () async {
    final novel = Novel(title: '测试', author: '作者', url: 'https://ex.com/n1');

    // 初始：101 章（让 totalPages=2）
    fakeLoader.chaptersToReturn = _chapters(101);

    // 预热 chapterListProvider（触发 build → _initializeData 异步加载）
    container.listen(chapterListProvider(novel), (_, __) {}, fireImmediately: true);
    await Future.delayed(const Duration(milliseconds: 50));

    // 手动切到第 2 页（模拟用户翻页）
    container.read(chapterListProvider(novel).notifier).goToPage(2);
    expect(container.read(chapterListProvider(novel)).currentPage, 2);

    // agent 加了一章 → 模拟 ChapterMutationNotifier 写库后 bump signal
    fakeLoader.chaptersToReturn = _chapters(102);
    container
        .read(chapterMutationSignalProvider(novel.url).notifier)
        .bump();

    // 等 softReload（listen 回调内 async）完成
    await Future.delayed(const Duration(milliseconds: 50));

    final state = container.read(chapterListProvider(novel));

    expect(state.chapters.length, 102, reason: 'chapters 应反映新增的第 102 章');
    expect(state.currentPage, 2, reason: 'currentPage 必须保留，不跳页');
    expect(state.isLoading, isFalse, reason: 'isLoading 不应闪');
  });

  test('softReload 静默失败：loadChapters 抛异常不打断当前 state',
      () async {
    final novel = Novel(title: '测试', author: '作者', url: 'https://ex.com/n2');

    fakeLoader.chaptersToReturn = _chapters(3);

    container.listen(chapterListProvider(novel), (_, __) {}, fireImmediately: true);
    await Future.delayed(const Duration(milliseconds: 50));

    // 让下次 loadChapters 抛异常
    fakeLoader.throwOnLoad = _LoadException();
    container
        .read(chapterMutationSignalProvider(novel.url).notifier)
        .bump();

    // bump 本身不抛（softReload 内部 catch）；旧 chapters 仍在
    await Future.delayed(const Duration(milliseconds: 50));

    final state = container.read(chapterListProvider(novel));
    expect(state.chapters.length, 3, reason: '软刷新失败时旧 state 应保留');
  });
}

class _LoadException implements Exception {}
