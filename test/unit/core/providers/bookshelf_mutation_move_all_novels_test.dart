/// BookshelfMutationNotifier `moveToBookshelf` from=1 透传专项单测（Task 2）。
///
/// Task 1 已在 Repository 层把 `from=1`（"全部小说"系统书架）降级为
/// `addNovelToBookshelf(toId)`（不删 nonexistent association 行）。
/// 本测试只验证 Notifier 层在 `from=1` 调用下行为正确：
///
/// - Notifier 透传 `(url, 1, 2)` 给 `IBookshelfAssociationWriter.moveNovelToBookshelf`
///   （Repository 内部如何降级由 Task 1 测试覆盖，Notifier 不关心）
/// - 写库成功后 `bookshelfNovelsProvider` 被 invalidate（订阅者重发）
///
/// Notifier 代码本身未修改；本测试只是钉死 from=1 这一调用路径的契约。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/core/providers/bookshelf_mutation_move_all_novels_test.dart
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

/// 与 `bookshelf_mutation_provider_test.dart` 同款 fake（精简版，只覆盖本测试用到的方法）。
/// 不用 noSuchMethod 是因为 IBookshelfWriter / IBookshelfAssociationWriter 是
/// Repository 文件内部 abstract interface，Mockito generator 索引不到，手写最直接。
class _FakeBookshelfWriter implements IBookshelfWriter {
  @override
  Future<int> addToBookshelf(Novel novel) async => 1;

  @override
  Future<int> removeFromBookshelf(String novelUrl) async => 1;

  @override
  Future<int> updateTitle(String novelUrl, String newTitle) async => 1;

  @override
  Future<int> updateCoverMediaIdByUrl(String novelUrl, String? mediaId) async =>
      1;

  @override
  Future<int> updateLastReadChapter(String novelUrl, int chapterIndex) async =>
      1;

  @override
  Future<Novel> createNovel({
    required String title,
    required String author,
    String? description,
    String? coverUrl,
    String? backgroundSetting,
  }) async =>
      Novel(title: title, author: author, url: 'created_url');
}

class _FakeAssocWriter implements IBookshelfAssociationWriter {
  int moveCalls = 0;
  ({String url, int fromId, int toId})? lastMove;

  @override
  Future<void> addNovelToBookshelf(String novelUrl, int bookshelfId) async {}

  @override
  Future<bool> removeNovelFromBookshelf(
      String novelUrl, int bookshelfId) async => true;

  @override
  Future<void> moveNovelToBookshelf(
      String novelUrl, int fromBookshelfId, int toBookshelfId) async {
    moveCalls++;
    lastMove = (
      url: novelUrl,
      fromId: fromBookshelfId,
      toId: toBookshelfId,
    );
  }
}

@GenerateMocks([INovelRepository])
void main() {
  late _FakeAssocWriter fakeAssocWriter;
  late MockINovelRepository mockNovelRepo;
  late ProviderContainer container;

  // 跟踪 bookshelfNovelsProvider 被重新求值的次数（invalidate 验证）。
  int novelsReloadCount = 0;

  setUp(() {
    fakeAssocWriter = _FakeAssocWriter();
    mockNovelRepo = MockINovelRepository();

    when(mockNovelRepo.isInBookshelf(any)).thenAnswer((_) async => false);

    container = ProviderContainer(
      overrides: [
        bookshelfWriterProvider.overrideWithValue(_FakeBookshelfWriter()),
        bookshelfAssociationWriterProvider.overrideWithValue(fakeAssocWriter),
        novelRepositoryProvider.overrideWithValue(mockNovelRepo),
        // 旁路真正的 DB 加载：用计数器 Provider 替换。
        // 必须 `container.listen` 保持订阅活着，否则 AutoDispose FutureProvider
        // 在 await read(future) 完成后立即释放，invalidate 触发的 lazy rebuild 不会执行。
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

  test('moveToBookshelf from=1 to=2 透传 + invalidate bookshelfNovelsProvider',
      () async {
    const url = 'https://example.com/novel/1';
    final before = novelsReloadCount;

    await container
        .read(bookshelfMutationProvider.notifier)
        .moveToBookshelf(url, 1, 2);

    // 强制等待 invalidate 触发的 rebuild 落地
    await container.read(bookshelfNovelsProvider.future);

    // (a) 透传给 association writer（from=1 不在 Notifier 层短路）
    expect(fakeAssocWriter.moveCalls, 1,
        reason: 'Notifier 应透传到 IBookshelfAssociationWriter.moveNovelToBookshelf');
    expect(fakeAssocWriter.lastMove?.url, url);
    expect(fakeAssocWriter.lastMove?.fromId, 1,
        reason: 'from=1（全部小说系统书架）应原样透传，'
            'Repository 内部的降级逻辑不在 Notifier 关心范围');
    expect(fakeAssocWriter.lastMove?.toId, 2);

    // (b) invalidate 信号触发了 bookshelfNovelsProvider 重发
    expect(novelsReloadCount, greaterThan(before),
        reason: 'moveToBookshelf 成功后 bookshelfNovelsProvider 应被 invalidate');
  });
}
