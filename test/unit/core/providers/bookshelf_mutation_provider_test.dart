/// BookshelfMutationNotifier 单元测试（Task 3 + Task 1）
///
/// 收口所有书架表写路径的 Notifier 测试：
/// - 10 个公共方法（addNovel / removeNovel / toggleBookshelf /
///   updateTitle / updateCoverMediaId / removeCoverMediaId /
///   updateReadProgress / moveToBookshelf / copyToBookshelf / createNovel）
/// - 每次成功 → 对应 writer 方法被调一次 + `bookshelfNovelsProvider` 被 invalidate
/// - writer 抛异常 → 异常向上抛 + **不** invalidate（避免半真半假 UI）
/// - toggleBookshelf 双分支：isInBookshelf=true → remove / false → add
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/core/providers/bookshelf_mutation_provider_test.dart
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:novel_app/core/providers/bookshelf_mutation_provider.dart';
import 'package:novel_app/core/providers/bookshelf_providers.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/interfaces/repositories/i_novel_repository.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/repositories/bookshelf_repository.dart';
import 'package:novel_app/repositories/novel_repository.dart';

import 'bookshelf_mutation_provider_test.mocks.dart';

/// `IBookshelfWriter` / `IBookshelfAssociationWriter` 是 Repository 文件内部定义
/// 的 abstract interface，Mockito `mockBuilder` 无法索引到（与"非公开导出"无关，
/// 单纯是 generator 走 import 时扫不到）。手写最小 fake 用 verify 计数最直接。
class _FakeBookshelfWriter implements IBookshelfWriter {
  int addToBookshelfCalls = 0;
  int removeFromBookshelfCalls = 0;
  int updateTitleCalls = 0;
  int updateCoverMediaIdByUrlCalls = 0;
  int updateLastReadChapterCalls = 0;
  int moveToBookshelfCalls = 0;
  int createNovelCalls = 0;
  int nextInsertId = 1;

  Novel? lastAddedNovel;
  String? lastRemovedUrl;
  ({String url, String title})? lastTitleUpdate;
  ({String url, String? mediaId})? lastCoverUpdate;
  ({String url, int chapterIndex})? lastProgressUpdate;
  Novel? createdNovel;

  // 可选:让测试塞入一次性的抛异常
  Object? throwOnce;
  Object? progressThrowOnce;

  @override
  Future<int> addToBookshelf(Novel novel) async {
    if (throwOnce != null) {
      final e = throwOnce!;
      throwOnce = null;
      throw e;
    }
    addToBookshelfCalls++;
    lastAddedNovel = novel;
    return nextInsertId++;
  }

  @override
  Future<int> removeFromBookshelf(String novelUrl) async {
    if (throwOnce != null) {
      final e = throwOnce!;
      throwOnce = null;
      throw e;
    }
    removeFromBookshelfCalls++;
    lastRemovedUrl = novelUrl;
    return 1;
  }

  @override
  Future<int> updateTitle(String novelUrl, String newTitle) async {
    if (throwOnce != null) {
      final e = throwOnce!;
      throwOnce = null;
      throw e;
    }
    updateTitleCalls++;
    lastTitleUpdate = (url: novelUrl, title: newTitle);
    return 1;
  }

  @override
  Future<int> updateCoverMediaIdByUrl(String novelUrl, String? mediaId) async {
    if (throwOnce != null) {
      final e = throwOnce!;
      throwOnce = null;
      throw e;
    }
    updateCoverMediaIdByUrlCalls++;
    lastCoverUpdate = (url: novelUrl, mediaId: mediaId);
    return 1;
  }

  @override
  Future<int> updateLastReadChapter(String novelUrl, int chapterIndex) async {
    if (progressThrowOnce != null) {
      final e = progressThrowOnce!;
      progressThrowOnce = null;
      throw e;
    }
    updateLastReadChapterCalls++;
    lastProgressUpdate = (url: novelUrl, chapterIndex: chapterIndex);
    return 1;
  }

  @override
  Future<Novel> createNovel({
    required String title,
    required String author,
    String? description,
    String? coverUrl,
    String? backgroundSetting,
  }) async {
    if (throwOnce != null) {
      final e = throwOnce!;
      throwOnce = null;
      throw e;
    }
    createNovelCalls++;
    createdNovel = createdNovel ??
        Novel(
          title: title,
          author: author,
          url: 'created_url',
          description: description,
          coverUrl: coverUrl,
          backgroundSetting: backgroundSetting,
        );
    return createdNovel!;
  }
}

class _FakeAssocWriter implements IBookshelfAssociationWriter {
  int addCalls = 0;
  int removeCalls = 0;
  int moveCalls = 0;
  Object? throwOnce;
  Object? addThrowOnce;
  ({String url, int bookshelfId})? lastAdd;

  @override
  Future<void> addNovelToBookshelf(String novelUrl, int bookshelfId) async {
    if (addThrowOnce != null) {
      final e = addThrowOnce!;
      addThrowOnce = null;
      throw e;
    }
    addCalls++;
    lastAdd = (url: novelUrl, bookshelfId: bookshelfId);
  }

  @override
  Future<bool> removeNovelFromBookshelf(
      String novelUrl, int bookshelfId) async {
    removeCalls++;
    return true;
  }

  @override
  Future<void> moveNovelToBookshelf(
      String novelUrl, int fromBookshelfId, int toBookshelfId) async {
    if (throwOnce != null) {
      final e = throwOnce!;
      throwOnce = null;
      throw e;
    }
    moveCalls++;
  }
}

@GenerateMocks([INovelRepository])
void main() {
  late _FakeBookshelfWriter fakeWriter;
  late _FakeAssocWriter fakeAssocWriter;
  late MockINovelRepository mockNovelRepo;
  late ProviderContainer container;

  // 跟踪 bookshelfNovelsProvider 被重新求值的次数（invalidate 验证）。
  int novelsReloadCount = 0;

  setUp(() {
    fakeWriter = _FakeBookshelfWriter();
    fakeAssocWriter = _FakeAssocWriter();
    mockNovelRepo = MockINovelRepository();

    // 默认 stubs
    when(mockNovelRepo.isInBookshelf(any)).thenAnswer((_) async => false);

    container = ProviderContainer(
      overrides: [
        bookshelfWriterProvider.overrideWithValue(fakeWriter),
        bookshelfAssociationWriterProvider
            .overrideWithValue(fakeAssocWriter),
        novelRepositoryProvider.overrideWithValue(mockNovelRepo),
        // 旁路掉真正的 DB 加载：用计数器 Provider 替换。
        // 注意：必须用 `container.listen` 保持订阅活着，否则 AutoDispose
        // FutureProvider 在 await read(future) 完成后立即释放，invalidate
        // 触发的 lazy rebuild 不会执行。
        bookshelfNovelsProvider.overrideWith((ref) async {
          novelsReloadCount++;
          return <Novel>[];
        }),
      ],
    );

    // 保持 bookshelfNovelsProvider 长期订阅，确保 invalidate 触发 rebuild。
    // fireImmediately: true 触发首次求值（novelsReloadCount → 1）。
    container.listen(
      bookshelfNovelsProvider,
      (_, __) {},
      fireImmediately: true,
    );
  });

  tearDown(() {
    container.dispose();
  });

  Novel makeNovel({String url = 'https://example.com/n1'}) => Novel(
        title: '测试小说',
        author: '作者甲',
        url: url,
      );

  // ============================================================
  // addNovel
  // ============================================================
  group('addNovel', () {
    test('调 writer.addToBookshelf + 返回插入 id + invalidate bookshelfNovelsProvider',
        () async {
      final before = novelsReloadCount;
      fakeWriter.nextInsertId = 42;

      final novel = makeNovel();
      final id = await container
          .read(bookshelfMutationProvider.notifier)
          .addNovel(novel);

      // 强制等待 invalidate 触发的 rebuild 落地
      await container.read(bookshelfNovelsProvider.future);

      expect(fakeWriter.addToBookshelfCalls, 1);
      expect(fakeWriter.lastAddedNovel, equals(novel));
      expect(id, 42,
          reason: 'addNovel 应把 writer.addToBookshelf 返回的插入 id 透传给调用方');
      expect(novelsReloadCount, greaterThan(before),
          reason: 'addNovel 成功后 bookshelfNovelsProvider 应被 invalidate');
    });

    test('writer 抛异常 → 上抛 + 不 invalidate', () async {
      fakeWriter.throwOnce = StateError('db error');

      final before = novelsReloadCount;

      await expectLater(
        container.read(bookshelfMutationProvider.notifier).addNovel(makeNovel()),
        throwsA(isA<StateError>()),
      );
      // 给可能的 lazy rebuild 一些时间确认它没发生
      await Future<void>.delayed(Duration.zero);
      expect(novelsReloadCount, equals(before),
          reason: '失败路径必须不 invalidate，避免半真半假 UI');
    });
  });

  // ============================================================
  // removeNovel
  // ============================================================
  group('removeNovel', () {
    test('调 writer.removeFromBookshelf + invalidate', () async {
      final before = novelsReloadCount;

      await container
          .read(bookshelfMutationProvider.notifier)
          .removeNovel('https://example.com/n1');

      await container.read(bookshelfNovelsProvider.future);

      expect(fakeWriter.removeFromBookshelfCalls, 1);
      expect(fakeWriter.lastRemovedUrl, 'https://example.com/n1');
      expect(novelsReloadCount, greaterThan(before));
    });

    test('writer 抛异常 → 上抛 + 不 invalidate', () async {
      fakeWriter.throwOnce = StateError('db error');

      final before = novelsReloadCount;

      await expectLater(
        container.read(bookshelfMutationProvider.notifier).removeNovel('u'),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(novelsReloadCount, equals(before));
    });
  });

  // ============================================================
  // toggleBookshelf —— 双分支
  // ============================================================
  group('toggleBookshelf', () {
    test('isInBookshelf=true → removeFromBookshelf + invalidate', () async {
      when(mockNovelRepo.isInBookshelf('u1')).thenAnswer((_) async => true);

      final before = novelsReloadCount;

      final novel = makeNovel(url: 'u1');
      await container.read(bookshelfMutationProvider.notifier).toggleBookshelf(novel);

      await container.read(bookshelfNovelsProvider.future);

      verify(mockNovelRepo.isInBookshelf('u1')).called(1);
      expect(fakeWriter.removeFromBookshelfCalls, 1);
      expect(fakeWriter.lastRemovedUrl, 'u1');
      expect(fakeWriter.addToBookshelfCalls, 0);
      expect(novelsReloadCount, greaterThan(before));
    });

    test('isInBookshelf=false → addToBookshelf + invalidate', () async {
      when(mockNovelRepo.isInBookshelf('u2')).thenAnswer((_) async => false);

      final before = novelsReloadCount;

      final novel = makeNovel(url: 'u2');
      await container.read(bookshelfMutationProvider.notifier).toggleBookshelf(novel);

      await container.read(bookshelfNovelsProvider.future);

      expect(fakeWriter.addToBookshelfCalls, 1);
      expect(fakeWriter.lastAddedNovel, equals(novel));
      expect(fakeWriter.removeFromBookshelfCalls, 0);
      expect(novelsReloadCount, greaterThan(before));
    });

    test('remove 分支 writer 抛异常 → 上抛 + 不 invalidate', () async {
      when(mockNovelRepo.isInBookshelf('u1')).thenAnswer((_) async => true);
      fakeWriter.throwOnce = StateError('db error');

      final before = novelsReloadCount;

      await expectLater(
        container.read(bookshelfMutationProvider.notifier).toggleBookshelf(
              makeNovel(url: 'u1'),
            ),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(novelsReloadCount, equals(before));
    });
  });

  // ============================================================
  // updateTitle
  // ============================================================
  group('updateTitle', () {
    test('调 writer.updateTitle + invalidate', () async {
      final before = novelsReloadCount;

      await container
          .read(bookshelfMutationProvider.notifier)
          .updateTitle('u1', '新标题');

      await container.read(bookshelfNovelsProvider.future);

      expect(fakeWriter.updateTitleCalls, 1);
      expect(fakeWriter.lastTitleUpdate?.url, 'u1');
      expect(fakeWriter.lastTitleUpdate?.title, '新标题');
      expect(novelsReloadCount, greaterThan(before));
    });

    test('writer 抛异常 → 上抛 + 不 invalidate', () async {
      fakeWriter.throwOnce = StateError('db error');

      final before = novelsReloadCount;

      await expectLater(
        container
            .read(bookshelfMutationProvider.notifier)
            .updateTitle('u1', 'x'),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(novelsReloadCount, equals(before));
    });
  });

  // ============================================================
  // updateCoverMediaId
  // ============================================================
  group('updateCoverMediaId', () {
    test('调 writer.updateCoverMediaIdByUrl(new) + invalidate', () async {
      final before = novelsReloadCount;

      await container
          .read(bookshelfMutationProvider.notifier)
          .updateCoverMediaId('u1', 'media_42');

      await container.read(bookshelfNovelsProvider.future);

      expect(fakeWriter.updateCoverMediaIdByUrlCalls, 1);
      expect(fakeWriter.lastCoverUpdate?.url, 'u1');
      expect(fakeWriter.lastCoverUpdate?.mediaId, 'media_42');
      expect(novelsReloadCount, greaterThan(before));
    });

    test('writer 抛异常 → 上抛 + 不 invalidate', () async {
      fakeWriter.throwOnce = StateError('db error');

      final before = novelsReloadCount;

      await expectLater(
        container
            .read(bookshelfMutationProvider.notifier)
            .updateCoverMediaId('u1', null),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(novelsReloadCount, equals(before));
    });
  });

  // ============================================================
  // removeCoverMediaId —— 走 writer.updateCoverMediaIdByUrl(_, null)
  // ============================================================
  group('removeCoverMediaId', () {
    test('调 writer.updateCoverMediaIdByUrl(_, null) + invalidate', () async {
      final before = novelsReloadCount;

      await container
          .read(bookshelfMutationProvider.notifier)
          .removeCoverMediaId('u1');

      await container.read(bookshelfNovelsProvider.future);

      expect(fakeWriter.updateCoverMediaIdByUrlCalls, 1);
      expect(fakeWriter.lastCoverUpdate?.url, 'u1');
      expect(fakeWriter.lastCoverUpdate?.mediaId, isNull);
      expect(novelsReloadCount, greaterThan(before));
    });
  });

  // ============================================================
  // updateReadProgress —— Task 1 新增
  // 修"阅读完返回书架看不到进度更新" bug 的核心收口点。
  // ============================================================
  group('updateReadProgress', () {
    test('调 writer.updateLastReadChapter + invalidate', () async {
      final before = novelsReloadCount;

      await container
          .read(bookshelfMutationProvider.notifier)
          .updateReadProgress('u1', 5);

      await container.read(bookshelfNovelsProvider.future);

      expect(fakeWriter.updateLastReadChapterCalls, 1);
      expect(fakeWriter.lastProgressUpdate?.url, 'u1');
      expect(fakeWriter.lastProgressUpdate?.chapterIndex, 5);
      expect(novelsReloadCount, greaterThan(before),
          reason: 'updateReadProgress 成功后书架列表应 invalidate,'
              ' 修复"返回书架看不到进度"bug');
    });

    test('writer 抛异常 → 上抛 + 不 invalidate', () async {
      fakeWriter.progressThrowOnce = StateError('db error');

      final before = novelsReloadCount;

      await expectLater(
        container
            .read(bookshelfMutationProvider.notifier)
            .updateReadProgress('u1', 5),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(novelsReloadCount, equals(before),
          reason: '失败路径必须不 invalidate，避免半真半假 UI');
    });
  });

  // ============================================================
  // moveToBookshelf —— 走 association writer
  // ============================================================
  group('moveToBookshelf', () {
    test('调 assocWriter.moveNovelToBookshelf + invalidate', () async {
      final before = novelsReloadCount;

      await container
          .read(bookshelfMutationProvider.notifier)
          .moveToBookshelf('u1', 2, 3);

      await container.read(bookshelfNovelsProvider.future);

      expect(fakeAssocWriter.moveCalls, 1);
      expect(novelsReloadCount, greaterThan(before));
    });

    test('writer 抛异常 → 上抛 + 不 invalidate', () async {
      fakeAssocWriter.throwOnce = StateError('db error');

      final before = novelsReloadCount;

      await expectLater(
        container
            .read(bookshelfMutationProvider.notifier)
            .moveToBookshelf('u1', 2, 3),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(novelsReloadCount, equals(before));
    });
  });

  // ============================================================
  // copyToBookshelf —— 走 association writer.addNovelToBookshelf
  // （Task 4 reviewer 建议 deferred 补的 2 个 case）
  // ============================================================
  group('copyToBookshelf', () {
    test('调 assocWriter.addNovelToBookshelf + invalidate', () async {
      final before = novelsReloadCount;

      await container
          .read(bookshelfMutationProvider.notifier)
          .copyToBookshelf('u1', 7);

      await container.read(bookshelfNovelsProvider.future);

      expect(fakeAssocWriter.addCalls, 1);
      expect(fakeAssocWriter.lastAdd?.url, 'u1');
      expect(fakeAssocWriter.lastAdd?.bookshelfId, 7);
      expect(novelsReloadCount, greaterThan(before));
    });

    test('writer 抛异常 → 上抛 + 不 invalidate', () async {
      fakeAssocWriter.addThrowOnce = StateError('db error');

      final before = novelsReloadCount;

      await expectLater(
        container
            .read(bookshelfMutationProvider.notifier)
            .copyToBookshelf('u1', 7),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(novelsReloadCount, equals(before));
    });
  });

  // ============================================================
  // createNovel —— 返回 Novel，需走 _wrap 也能 invalidate
  // ============================================================
  group('createNovel', () {
    test('调 writer.createNovel + 返回 Novel + invalidate', () async {
      final before = novelsReloadCount;

      final result =
          await container.read(bookshelfMutationProvider.notifier).createNovel(
        title: '新建',
        author: '作者',
      );

      await container.read(bookshelfNovelsProvider.future);

      expect(fakeWriter.createNovelCalls, 1);
      expect(result, isA<Novel>(),
          reason: 'createNovel 应把 writer.createNovel 的结果透传给调用方');
      expect(novelsReloadCount, greaterThan(before));
    });

    test('writer 抛异常 → 上抛 + 不 invalidate', () async {
      fakeWriter.throwOnce = StateError('db error');

      final before = novelsReloadCount;

      await expectLater(
        container.read(bookshelfMutationProvider.notifier).createNovel(
              title: 'x',
              author: 'y',
            ),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(novelsReloadCount, equals(before));
    });
  });
}
