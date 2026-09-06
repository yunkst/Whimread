/// ChapterMutationNotifier —— 章节写路径的统一收口。
///
/// 所有改 `novel_chapters` 表或 `chapter_cache` 表的写操作必须经此 Notifier。
/// Notifier 内部统一执行「写库 → bump chapterMutationSignalProvider(novelUrl)」，
/// 调用方再也无需手记「写完通知章节列表」——`ChapterList.build` 自动 listen 该
/// signal 触发 softReload（重读 chapters 替换 state，保留分页/loading/重排状态）。
///
/// 根治「agent 创建/修改章节内容后章节列表不立即刷新，必须重新进入目录页面」
/// 这一类架构缺陷（CLAUDE.md 已知 TODO「章节列表 Notifier 待重构」的根治点）。
///
/// 设计意图见 `docs/superpowers/plans/2026-07-29-chapter-mutation-notifier.md`。
///
/// 关键约定：
/// - **不持状态**（`build()` 返回 void）—— 写聚合，不是状态机
/// - **`_wrap` 统一收口** —— 所有写方法都走它；失败不 bump（避免半真半假 UI）
/// - **写能力通过 `chapterWriterProvider` 拿** —— 普通调用方持有
///   `IChapterRepository` 接口，编译期阻止绕过 Notifier 直接写库
/// - **`createCustomChapterWithShift` / `deleteChapterAndReindex` 是事务方法**
///   —— 把原本调用方多次独立 DB 调用合并为单 `db.transaction`（修原子性 bug）
///
/// 7 个公共方法：updateChapterContent / deleteCachedChapters / createChapter /
/// deleteChapter / cacheNovelChapters / updateChaptersOrder / markChapterAsRead。
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/chapter.dart';
import '../../repositories/chapter_repository.dart';
import 'chapter_mutation_signal_provider.dart';
import 'database_providers.dart';

part 'chapter_mutation_provider.g.dart';

/// 章节写操作聚合 Notifier（无状态）。
@riverpod
class ChapterMutation extends _$ChapterMutation {
  @override
  void build() {
    // 无状态 —— 只做写聚合。build() 仅返回 void，避免引入额外生命周期。
  }

  /// 更新章节内容（整章替换）。
  ///
  /// [source] 决定版本来源标注：`'edit'`（用户编辑）| `'ai_edit'`（AI 局部替换）|
  /// `'ai_rewrite'`（AI 全文重写）| `'restore'`（还原历史版本）。
  /// 透传 [IChapterWriter.updateChapterContent] 返回的受影响行数。
  Future<int> updateChapterContent(
    String chapterUrl,
    String content, {
    required String novelUrl,
    String source = 'edit',
  }) =>
      _wrap(
        () => _writer.updateChapterContent(chapterUrl, content, source: source),
        novelUrl,
      );

  /// 缓存单个章节正文到 `chapter_cache` 表（阅读页下载章节后首次缓存）。
  ///
  /// 调用方：`ReaderContentController` 拿到章节正文后调用。写后章节列表 UI
  /// 的「已缓存」标记通过 signal bump → softReload 实时刷新。
  /// 透传 [IChapterWriter.cacheChapter] 返回的新插入行 ID。
  Future<int> cacheChapter(
    String novelUrl,
    Chapter chapter,
    String content,
  ) =>
      _wrap(() => _writer.cacheChapter(novelUrl, chapter, content), novelUrl);

  /// 清除整本小说的章节内容缓存（仅清 `chapter_cache` 表，`novel_chapters`
  /// 元数据保留）。
  ///
  /// 透传 [IChapterWriter.deleteCachedChapters] 返回的删除行数。
  Future<int> deleteCachedChapters(String novelUrl) =>
      _wrap(() => _writer.deleteCachedChapters(novelUrl), novelUrl);

  /// 在指定位置创建新章节（单事务：shift 后续索引 + insert 两表）。
  ///
  /// [insertIndex] 为 null 时追加到末尾（内部 MAX+1，无需 shift）；
  /// 非 null 时单事务内先 shift `chapterIndex >= insertIndex` 的行 +1，
  /// 再 insert 新章节到两表。修原「shift 成功 + insert 失败留空洞」原子性 bug。
  Future<int> createChapter({
    required String novelUrl,
    required String title,
    required String content,
    int? insertIndex,
  }) =>
      _wrap(
        () => _writer.createCustomChapterWithShift(
          novelUrl,
          title,
          content,
          insertIndex,
        ),
        novelUrl,
      );

  /// 删除章节并把剩余章节 chapterIndex 连续化（单事务）。
  ///
  /// 单事务内 delete 两表 + 重排剩余章节 chapterIndex 为 0..N-1。
  /// 修原 executor「delete + getCachedNovelChapters + cacheNovelChapters(remaining)」
  /// 三步非原子的缺陷。
  Future<void> deleteChapter(String novelUrl, String chapterUrl) =>
      _wrap(
        () => _writer.deleteChapterAndReindex(novelUrl, chapterUrl),
        novelUrl,
      );

  /// 批量缓存章节列表（headless WebView 拉取后 / 首次添加小说）。
  ///
  /// 用于 `chapter_loader.refreshFromBackend` 和 `webview_add_novel_button` 的
  /// 章节列表持久化场景。
  Future<void> cacheNovelChapters(
    String novelUrl,
    List<Chapter> chapters,
  ) =>
      _wrap(() => _writer.cacheNovelChapters(novelUrl, chapters), novelUrl);

  /// 更新章节顺序（拖拽重排保存）。
  ///
  /// 调用方先在 UI 层完成内存重排（`ChapterReorderController.onReorder`），再调用
  /// 本方法持久化。单事务批量 update 两表 chapterIndex 为 0..N-1。
  Future<void> updateChaptersOrder(
    String novelUrl,
    List<Chapter> chapters,
  ) =>
      _wrap(() => _writer.updateChaptersOrder(novelUrl, chapters), novelUrl);

  /// 标记章节为已读（写 `novel_chapters.read_at`）。
  ///
  /// 调用方：阅读页翻页时 `reader_screen._loadChapterContent`。
  /// 写后章节列表 UI 的「已读」高亮通过 signal bump → softReload 实时刷新。
  Future<void> markChapterAsRead(String novelUrl, String chapterUrl) =>
      _wrap(() => _writer.markChapterAsRead(novelUrl, chapterUrl), novelUrl);

  // ===== 内部 =====

  IChapterWriter get _writer => ref.read(chapterWriterProvider);

  /// 统一收口：写库 + bump signal。
  ///
  /// **失败不 bump**：若 [op] 抛异常，异常向上抛，`bump` 不执行——
  /// 避免 UI 显示「写了但没刷干净」的半真半假状态。
  /// 与 `BookshelfMutationNotifier._wrap` 同语义。
  Future<T> _wrap<T>(Future<T> Function() op, String novelUrl) async {
    final result = await op();
    ref.read(chapterMutationSignalProvider(novelUrl).notifier).bump();
    return result;
  }
}
