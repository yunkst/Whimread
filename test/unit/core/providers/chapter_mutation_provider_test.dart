/// ChapterMutationNotifier 单元测试
///
/// 收口所有章节写路径的 Notifier 测试：
/// - 7 个公共方法（updateChapterContent / deleteCachedChapters / createChapter /
///   deleteChapter / cacheNovelChapters / updateChaptersOrder / markChapterAsRead）
/// - 每次成功 → 对应 writer 方法被调一次 + `chapterMutationSignalProvider(novelUrl)`
///   tick +1（触发 ChapterList softReload）
/// - writer 抛异常 → 异常向上抛 + **不** bump（避免半真半假 UI）
///
/// 与 `bookshelf_mutation_provider_test.dart` 同构，差异：
/// - invalidate 目标是 family by String 的 signal tick（直接读 int 验证），
///   而非全局 `bookshelfNovelsProvider` 的 reload count
/// - `IChapterWriter` 是 `chapter_repository.dart` 内部 abstract interface，
///   Mockito `mockBuilder` 无法索引 → 手写 `_FakeChapterWriter`
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/core/providers/chapter_mutation_provider_test.dart
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/core/providers/chapter_mutation_provider.dart';
import 'package:novel_app/core/providers/chapter_mutation_signal_provider.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/models/chapter.dart';
import 'package:novel_app/repositories/chapter_repository.dart';

/// `IChapterWriter` 是 `chapter_repository.dart` 内部定义的 abstract interface，
/// Mockito `mockBuilder` 无法索引到（同 `_FakeBookshelfWriter` 的理由）。
/// 手写最小 fake：Notifier 实际调用的 7 个方法计数 + 记录入参 + 可选一次性抛异常；
/// 其余 7 个方法空实现（Notifier 不调用）。
class _FakeChapterWriter implements IChapterWriter {
  int updateChapterContentCalls = 0;
  int deleteCachedChaptersCalls = 0;
  int createCustomChapterWithShiftCalls = 0;
  int deleteChapterAndReindexCalls = 0;
  int cacheNovelChaptersCalls = 0;
  int cacheChapterCalls = 0;
  int updateChaptersOrderCalls = 0;
  int markChapterAsReadCalls = 0;

  ({String url, String content, String source})? lastUpdate;
  String? lastDeleteCached;
  ({String novelUrl, String title, int? insertIndex})? lastCreate;
  ({String novelUrl, String chapterUrl})? lastDelete;
  ({String novelUrl, List<Chapter> chapters})? lastCache;
  ({String novelUrl, Chapter chapter, String content})? lastCacheOne;
  ({String novelUrl, List<Chapter> chapters})? lastReorder;
  ({String novelUrl, String chapterUrl})? lastMarkRead;

  /// 让测试塞入一次性的抛异常（任意计数方法命中即抛一次后清空）。
  Object? throwOnce;

  void _maybeThrow() {
    if (throwOnce != null) {
      final e = throwOnce!;
      throwOnce = null;
      throw e;
    }
  }

  // ===== Notifier 实际调用的 7 个方法 =====

  @override
  Future<int> updateChapterContent(String chapterUrl, String content,
      {String source = 'edit'}) async {
    _maybeThrow();
    updateChapterContentCalls++;
    lastUpdate = (url: chapterUrl, content: content, source: source);
    return 1;
  }

  @override
  Future<int> deleteCachedChapters(String novelUrl) async {
    _maybeThrow();
    deleteCachedChaptersCalls++;
    lastDeleteCached = novelUrl;
    return 1;
  }

  @override
  Future<int> createCustomChapterWithShift(
    String novelUrl,
    String title,
    String content, [
    int? insertIndex,
  ]) async {
    _maybeThrow();
    createCustomChapterWithShiftCalls++;
    lastCreate = (
      novelUrl: novelUrl,
      title: title,
      insertIndex: insertIndex,
    );
    return 1;
  }

  @override
  Future<void> deleteChapterAndReindex(
      String novelUrl, String chapterUrl) async {
    _maybeThrow();
    deleteChapterAndReindexCalls++;
    lastDelete = (novelUrl: novelUrl, chapterUrl: chapterUrl);
  }

  @override
  Future<void> cacheNovelChapters(
      String novelUrl, List<Chapter> chapters) async {
    _maybeThrow();
    cacheNovelChaptersCalls++;
    lastCache = (novelUrl: novelUrl, chapters: chapters);
  }

  @override
  Future<int> cacheChapter(
      String novelUrl, Chapter chapter, String content) async {
    _maybeThrow();
    cacheChapterCalls++;
    lastCacheOne = (novelUrl: novelUrl, chapter: chapter, content: content);
    return 1;
  }

  @override
  Future<void> updateChaptersOrder(
      String novelUrl, List<Chapter> chapters) async {
    _maybeThrow();
    updateChaptersOrderCalls++;
    lastReorder = (novelUrl: novelUrl, chapters: chapters);
  }

  @override
  Future<void> markChapterAsRead(String novelUrl, String chapterUrl) async {
    _maybeThrow();
    markChapterAsReadCalls++;
    lastMarkRead = (novelUrl: novelUrl, chapterUrl: chapterUrl);
  }

  // ===== Notifier 不调用的 7 个方法（空实现，满足接口）=====

  @override
  Future<int> updateChapterContentById(int id, String content) async => 0;

  @override
  Future<int> deleteChapterCache(String chapterUrl) async => 0;

  @override
  Future<int> createCustomChapter(String novelUrl, String title, String content,
      [int? index]) async => 0;

  @override
  Future<void> updateCustomChapter(
      String chapterUrl, String title, String content) async {}

  @override
  Future<void> deleteCustomChapter(String chapterUrl) async {}

  @override
  Future<void> shiftChapterIndicesFrom(String novelUrl, int fromIndex) async {}
}

void main() {
  const novelUrl = 'https://example.com/n1';

  late _FakeChapterWriter fakeWriter;
  late ProviderContainer container;

  setUp(() {
    fakeWriter = _FakeChapterWriter();
    container = ProviderContainer(
      overrides: [
        chapterWriterProvider.overrideWithValue(fakeWriter),
      ],
    );
    // 预热 signal：保持订阅避免 autoDispose 重置 tick 计数。
    // fireImmediately: true 触发首次 build（tick = 0）。
    container.listen(
      chapterMutationSignalProvider(novelUrl),
      (_, __) {},
      fireImmediately: true,
    );
  });

  tearDown(() {
    container.dispose();
  });

  /// 读取当前 tick（封装一处）。
  int tick() => container.read(chapterMutationSignalProvider(novelUrl));

  Chapter makeChapter(String url) =>
      Chapter(title: '章 $url', url: url, chapterIndex: 0);

  group('updateChapterContent', () {
    test('调 writer + bump signal', () async {
      final before = tick();
      final affected = await container
          .read(chapterMutationProvider.notifier)
          .updateChapterContent(
            'chapter_1',
            'new content',
            novelUrl: novelUrl,
            source: 'ai_edit',
          );

      expect(affected, 1);
      expect(fakeWriter.updateChapterContentCalls, 1);
      expect(fakeWriter.lastUpdate?.url, 'chapter_1');
      expect(fakeWriter.lastUpdate?.content, 'new content');
      expect(fakeWriter.lastUpdate?.source, 'ai_edit');
      expect(tick(), before + 1, reason: '写库成功 → signal tick +1');
    });

    test('writer 抛异常 → 不 bump', () async {
      final before = tick();
      fakeWriter.throwOnce = StateError('db down');

      await expectLater(
        container.read(chapterMutationProvider.notifier).updateChapterContent(
              'chapter_1',
              'x',
              novelUrl: novelUrl,
            ),
        throwsA(isA<StateError>()),
      );

      expect(tick(), before, reason: '写库失败 → signal tick 不变');
    });
  });

  group('deleteCachedChapters', () {
    test('调 writer + bump signal', () async {
      final before = tick();
      final deleted = await container
          .read(chapterMutationProvider.notifier)
          .deleteCachedChapters(novelUrl);

      expect(deleted, 1);
      expect(fakeWriter.deleteCachedChaptersCalls, 1);
      expect(fakeWriter.lastDeleteCached, novelUrl);
      expect(tick(), before + 1);
    });

    test('writer 抛异常 → 不 bump', () async {
      final before = tick();
      fakeWriter.throwOnce = StateError('db down');

      await expectLater(
        container
            .read(chapterMutationProvider.notifier)
            .deleteCachedChapters(novelUrl),
        throwsA(isA<StateError>()),
      );

      expect(tick(), before);
    });
  });

  group('createChapter', () {
    test('调 writer (事务 createCustomChapterWithShift) + bump signal', () async {
      final before = tick();
      final id = await container.read(chapterMutationProvider.notifier).createChapter(
            novelUrl: novelUrl,
            title: '第 3 章',
            content: 'body',
            insertIndex: 2,
          );

      expect(id, 1);
      expect(fakeWriter.createCustomChapterWithShiftCalls, 1);
      expect(fakeWriter.lastCreate?.novelUrl, novelUrl);
      expect(fakeWriter.lastCreate?.title, '第 3 章');
      expect(fakeWriter.lastCreate?.insertIndex, 2);
      expect(tick(), before + 1);
    });

    test('insertIndex 为 null (追加) 也透传 + bump', () async {
      await container.read(chapterMutationProvider.notifier).createChapter(
            novelUrl: novelUrl,
            title: '末章',
            content: 'body',
          );

      expect(fakeWriter.lastCreate?.insertIndex, isNull);
      expect(fakeWriter.createCustomChapterWithShiftCalls, 1);
    });

    test('writer 抛异常 → 不 bump', () async {
      final before = tick();
      fakeWriter.throwOnce = StateError('db down');

      await expectLater(
        container.read(chapterMutationProvider.notifier).createChapter(
              novelUrl: novelUrl,
              title: 'x',
              content: 'x',
            ),
        throwsA(isA<StateError>()),
      );

      expect(tick(), before);
    });
  });

  group('deleteChapter', () {
    test('调 writer (事务 deleteChapterAndReindex) + bump signal', () async {
      final before = tick();
      await container
          .read(chapterMutationProvider.notifier)
          .deleteChapter(novelUrl, 'chapter_5');

      expect(fakeWriter.deleteChapterAndReindexCalls, 1);
      expect(fakeWriter.lastDelete?.novelUrl, novelUrl);
      expect(fakeWriter.lastDelete?.chapterUrl, 'chapter_5');
      expect(tick(), before + 1);
    });

    test('writer 抛异常 → 不 bump', () async {
      final before = tick();
      fakeWriter.throwOnce = StateError('db down');

      await expectLater(
        container
            .read(chapterMutationProvider.notifier)
            .deleteChapter(novelUrl, 'chapter_5'),
        throwsA(isA<StateError>()),
      );

      expect(tick(), before);
    });
  });

  group('cacheNovelChapters', () {
    test('调 writer + bump signal', () async {
      final before = tick();
      final chapters = [makeChapter('c1'), makeChapter('c2')];
      await container
          .read(chapterMutationProvider.notifier)
          .cacheNovelChapters(novelUrl, chapters);

      expect(fakeWriter.cacheNovelChaptersCalls, 1);
      expect(fakeWriter.lastCache?.chapters.length, 2);
      expect(tick(), before + 1);
    });

    test('writer 抛异常 → 不 bump', () async {
      final before = tick();
      fakeWriter.throwOnce = StateError('db down');

      await expectLater(
        container
            .read(chapterMutationProvider.notifier)
            .cacheNovelChapters(novelUrl, [makeChapter('c1')]),
        throwsA(isA<StateError>()),
      );

      expect(tick(), before);
    });
  });

  group('updateChaptersOrder', () {
    test('调 writer + bump signal', () async {
      final before = tick();
      final chapters = [makeChapter('c1'), makeChapter('c2')];
      await container
          .read(chapterMutationProvider.notifier)
          .updateChaptersOrder(novelUrl, chapters);

      expect(fakeWriter.updateChaptersOrderCalls, 1);
      expect(fakeWriter.lastReorder?.chapters.length, 2);
      expect(tick(), before + 1);
    });

    test('writer 抛异常 → 不 bump', () async {
      final before = tick();
      fakeWriter.throwOnce = StateError('db down');

      await expectLater(
        container
            .read(chapterMutationProvider.notifier)
            .updateChaptersOrder(novelUrl, [makeChapter('c1')]),
        throwsA(isA<StateError>()),
      );

      expect(tick(), before);
    });
  });

  group('cacheChapter', () {
    test('调 writer + bump signal', () async {
      final before = tick();
      final ch = makeChapter('c_single');
      final id = await container
          .read(chapterMutationProvider.notifier)
          .cacheChapter(novelUrl, ch, 'body');

      expect(id, 1);
      expect(fakeWriter.cacheChapterCalls, 1);
      expect(fakeWriter.lastCacheOne?.novelUrl, novelUrl);
      expect(fakeWriter.lastCacheOne?.chapter.url, 'c_single');
      expect(fakeWriter.lastCacheOne?.content, 'body');
      expect(tick(), before + 1);
    });

    test('writer 抛异常 → 不 bump', () async {
      final before = tick();
      fakeWriter.throwOnce = StateError('db down');

      await expectLater(
        container.read(chapterMutationProvider.notifier).cacheChapter(
              novelUrl,
              makeChapter('c_single'),
              'body',
            ),
        throwsA(isA<StateError>()),
      );

      expect(tick(), before);
    });
  });

  group('markChapterAsRead', () {
    test('调 writer + bump signal', () async {
      final before = tick();
      await container
          .read(chapterMutationProvider.notifier)
          .markChapterAsRead(novelUrl, 'chapter_7');

      expect(fakeWriter.markChapterAsReadCalls, 1);
      expect(fakeWriter.lastMarkRead?.chapterUrl, 'chapter_7');
      expect(tick(), before + 1);
    });

    test('writer 抛异常 → 不 bump', () async {
      final before = tick();
      fakeWriter.throwOnce = StateError('db down');

      await expectLater(
        container
            .read(chapterMutationProvider.notifier)
            .markChapterAsRead(novelUrl, 'chapter_7'),
        throwsA(isA<StateError>()),
      );

      expect(tick(), before);
    });
  });

  test('signal 按 novelUrl 分桶：bump u1 不影响 u2', () async {
    const otherUrl = 'https://example.com/other';
    container.listen(
      chapterMutationSignalProvider(otherUrl),
      (_, __) {},
      fireImmediately: true,
    );

    final u1Before = tick();
    final u2Before = container.read(chapterMutationSignalProvider(otherUrl));

    await container
        .read(chapterMutationProvider.notifier)
        .markChapterAsRead(novelUrl, 'c1');

    expect(container.read(chapterMutationSignalProvider(novelUrl)),
        u1Before + 1,
        reason: 'u1 的 signal 应 +1');
    expect(container.read(chapterMutationSignalProvider(otherUrl)), u2Before,
        reason: 'u2 的 signal 不应受影响');
  });
}
