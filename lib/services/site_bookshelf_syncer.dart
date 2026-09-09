/// 网站书架条目 → 本地书架 的合并逻辑（可单测的纯函数层）
///
/// 负责"刷新"语义：对于从网站抓回的小说条目，逐一检查本地是否已存在：
/// - 已存在 → 跳过（保留用户已有的阅读进度/封面）
/// - 不存在 → 通过 [addNovel] 回调加入本地书架
///
/// 章节不在此层加载（ChapterLoader.loadChapters 在用户首次打开小说时会自动
/// 按需加载，无需提前拉取整本章节以加快刷新）。
library;

import '../models/novel.dart';
import '../models/site_bookshelf_entry.dart';

/// 同步结果统计
class SiteBookshelfSyncResult {
  /// 本次新加入书架的小说数
  final int added;

  /// 网站侧有但本地已存在的条目数（被跳过，保留本地进度）
  final int alreadyExists;

  /// 网站侧返回的条目总数（added + alreadyExists + 解析失败被丢弃等）
  final int totalFromSite;

  const SiteBookshelfSyncResult({
    required this.added,
    required this.alreadyExists,
    required this.totalFromSite,
  });

  /// 用户可读的总结文案（中文）
  String get summary {
    final parts = <String>[];
    if (added > 0) parts.add('新增 $added 本');
    if (alreadyExists > 0) parts.add('已存在 $alreadyExists 本');
    if (parts.isEmpty) return '未发现可同步内容';
    return parts.join('，');
  }
}

/// 网站书架合并器（纯函数，所有依赖通过参数注入，便于单测）
class SiteBookshelfSyncer {
  SiteBookshelfSyncer._();

  /// 同步 [entries] 到本地书架
  ///
  /// [isInBookshelf] 判断某 URL 是否已在本地书架中。
  /// [addNovel] 把单本小说加入书架（调用方应走 BookshelfMutationNotifier
  /// 以触发 invalidate(bookshelfNovelsProvider)）。
  /// [progress]（可选）回调 (addedCount, alreadyExistsCount, current) 用于
  /// UI 显示进度；不影响同步行为。
  static Future<SiteBookshelfSyncResult> sync({
    required List<SiteBookshelfEntry> entries,
    required Future<bool> Function(String url) isInBookshelf,
    required Future<void> Function(Novel novel) addNovel,
    void Function(SiteBookshelfSyncProgress progress)? progress,
  }) async {
    var added = 0;
    var alreadyExists = 0;
    final total = entries.length;
    for (var i = 0; i < total; i++) {
      final entry = entries[i];
      try {
        if (await isInBookshelf(entry.url)) {
          alreadyExists++;
        } else {
          await addNovel(Novel(
            title: entry.title,
            author: '',
            url: entry.url,
          ));
          added++;
        }
      } catch (_) {
        // 单本失败不中断整批（典型如 addNovel 异常）
      }
      progress?.call(SiteBookshelfSyncProgress(
        added: added,
        alreadyExists: alreadyExists,
        processed: i + 1,
        total: total,
      ));
    }
    return SiteBookshelfSyncResult(
      added: added,
      alreadyExists: alreadyExists,
      totalFromSite: total,
    );
  }
}

/// 同步进度（用于 UI 反馈）
class SiteBookshelfSyncProgress {
  final int added;
  final int alreadyExists;
  final int processed;
  final int total;

  const SiteBookshelfSyncProgress({
    required this.added,
    required this.alreadyExists,
    required this.processed,
    required this.total,
  });
}