/// BookshelfMutationNotifier —— 书架写路径的统一收口。
///
/// 所有改 `bookshelf` 表（或 `novel_bookshelves` 关联表）的写操作必须经此 Notifier。
/// Notifier 内部统一执行"写库 → invalidate(bookshelfNovelsProvider)"，
/// 调用方再也无需手记"写完 invalidate"，从根本上消除浏览器添加小说后书架不刷新
/// 这一类架构缺陷。
///
/// 设计意图见 `docs/superpowers/specs/2026-07-28-bookshelf-mutation-notifier-design.md`。
///
/// 关键约定：
/// - **不持状态**（`build()` 返回 void）——这是写操作聚合，不是状态机
/// - **`_wrap` 统一收口**——所有写方法都走它；失败不 invalidate（避免半真半假 UI）
/// - **`toggleBookshelf` 双分支也走 `_wrap`**——避免任何路径绕开 invalidate
/// - **`removeCoverMediaId` 是 `updateCoverMediaIdByUrl(_, null)` 的 convenience**
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/novel.dart';
import '../../repositories/bookshelf_repository.dart';
import '../../repositories/novel_repository.dart';
import 'bookshelf_providers.dart';
import 'database_providers.dart';

part 'bookshelf_mutation_provider.g.dart';

/// 书架写操作聚合 Notifier（无状态）。
///
/// 10 个公共方法：addNovel / removeNovel / toggleBookshelf /
/// updateTitle / updateCoverMediaId / removeCoverMediaId /
/// updateReadProgress / moveToBookshelf / copyToBookshelf / createNovel。
@riverpod
class BookshelfMutation extends _$BookshelfMutation {
  @override
  void build() {
    // 无状态——只做写聚合。build() 仅返回 void，避免引入额外生命周期。
  }

  /// 把小说加入书架。
  ///
  /// 透传 [IBookshelfWriter.addToBookshelf] 返回的插入行 id，
  /// Agent 工具（如 create_novel）需要这个 id 作为响应字段。
  Future<int> addNovel(Novel novel) =>
      _wrap(() => _writer.addToBookshelf(novel));

  /// 把小说从书架移除。
  Future<void> removeNovel(String novelUrl) =>
      _wrap(() => _writer.removeFromBookshelf(novelUrl));

  /// 切换小说的书架归属（在则移除 / 不在则加入）。
  ///
  /// 内部先查 `isInBookshelf`，再走 add/remove 分支，
  /// **两分支都经 [_wrap]**，因此 invalidate 一定触发。
  Future<void> toggleBookshelf(Novel novel) async {
    final writer = _writer;
    if (await _isInBookshelf(novel.url)) {
      await _wrap(() => writer.removeFromBookshelf(novel.url));
    } else {
      await _wrap(() => writer.addToBookshelf(novel));
    }
  }

  /// 更新小说标题。
  Future<void> updateTitle(String novelUrl, String newTitle) =>
      _wrap(() => _writer.updateTitle(novelUrl, newTitle));

  /// 更新小说封面媒体 ID（图/视频）。
  Future<void> updateCoverMediaId(String novelUrl, String? mediaId) =>
      _wrap(() => _writer.updateCoverMediaIdByUrl(novelUrl, mediaId));

  /// 清空小说封面媒体 ID（回到程序化占位）。
  Future<void> removeCoverMediaId(String novelUrl) =>
      _wrap(() => _writer.updateCoverMediaIdByUrl(novelUrl, null));

  /// 更新阅读进度（最近阅读章节索引）。
  ///
  /// 内部走 `_writer.updateLastReadChapter`，与其他写方法一样经 [_wrap]：
  /// 成功 → invalidate `bookshelfNovelsProvider`，书架页"最近阅读"立即刷新；
  /// 失败 → 异常上抛，**不** invalidate（避免半真半假 UI）。
  ///
  /// 这是修复"阅读完返回书架看不到进度更新"bug 的核心收口点：之前
  /// [ReaderContentController] 直接调 `INovelRepository.updateLastReadChapter`
  /// 绕过 Notifier，写库成功但书架列表 Provider 无从得知，导致 UI 不刷新。
  Future<void> updateReadProgress(String novelUrl, int chapterIndex) =>
      _wrap(() => _writer.updateLastReadChapter(novelUrl, chapterIndex));

  /// 把小说从一个书架分类移动到另一个。
  Future<void> moveToBookshelf(
    String novelUrl,
    int fromBookshelfId,
    int toBookshelfId,
  ) =>
      _wrap(() => _associationWriter.moveNovelToBookshelf(
            novelUrl,
            fromBookshelfId,
            toBookshelfId,
          ));

  /// 把小说复制到指定书架分类（不影响原书架归属）。
  ///
  /// 与 [moveToBookshelf] 的差别：复制只向 `novel_bookshelves` 关联表追加一行，
  /// 不删除原书架的关联。复制成功后 invalidate `bookshelfNovelsProvider`——
  /// 若用户当前停留在目标书架，列表会立即显示这本小说；若停留在原书架，
  /// 小说仍在原列表（复制不影响原书架行），invalidate 只是无副作用的重新查询。
  Future<void> copyToBookshelf(String novelUrl, int toBookshelfId) =>
      _wrap(() => _associationWriter.addNovelToBookshelf(novelUrl, toBookshelfId));

  /// 创建新小说（不依赖浏览器 URL，由 Agent 工具或独立入口调用）。
  ///
  /// 透传 [IBookshelfWriter.createNovel] 的返回值（已落库的 Novel）。
  Future<Novel> createNovel({
    required String title,
    required String author,
    String? description,
    String? coverUrl,
    String? backgroundSetting,
  }) =>
      _wrap<Novel>(() => _writer.createNovel(
            title: title,
            author: author,
            description: description,
            coverUrl: coverUrl,
            backgroundSetting: backgroundSetting,
          ));

  // ===== 内部 =====

  IBookshelfWriter get _writer => ref.read(bookshelfWriterProvider);

  IBookshelfAssociationWriter get _associationWriter =>
      ref.read(bookshelfAssociationWriterProvider);

  Future<bool> _isInBookshelf(String novelUrl) async {
    return ref.read(novelRepositoryProvider).isInBookshelf(novelUrl);
  }

  /// 统一收口：写库 + invalidate(bookshelfNovelsProvider)。
  ///
  /// **失败不 invalidate**：若 [op] 抛异常，异常向上抛，`ref.invalidate`
  /// 不执行——避免 UI 显示"写了但没刷干净"的半真半假状态。
  Future<T> _wrap<T>(Future<T> Function() op) async {
    final result = await op();
    ref.invalidate(bookshelfNovelsProvider);
    return result;
  }
}
