/// SideStoryMutationNotifier —— 番外写路径的统一收口。
///
/// 所有创建/删除番外的写操作必须经此 Notifier。Notifier 内部统一执行
/// 「写库 → bump sideStorySignalProvider(anchorNovelUrl)」，驱动目录页徽标、
/// 阅读器角标与番外列表页刷新；调用方无需手记通知。
///
/// 关键约定：
/// - **不持状态**（`build()` 返回 void）—— 写聚合，不是状态机
/// - **`_wrap` 统一收口** —— 所有写方法都走它；失败不 bump（避免半真半假 UI）
/// - 章节级的写（番外里写章节/改章节）不在此收口——它们走既有
///   `ChapterMutationNotifier`（番外章节就是普通章节行）
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/novel.dart';
import '../../repositories/side_story_repository.dart';
import 'database_providers.dart';
import 'side_story_signal_provider.dart';

part 'side_story_mutation_provider.g.dart';

/// 番外写操作聚合 Notifier（无状态）
@riverpod
class SideStoryMutation extends _$SideStoryMutation {
  @override
  void build() {
    // 无状态——只做写聚合。
  }

  /// 创建番外（不入书架），返回已落库的番外 [Novel]。
  ///
  /// AI 番外场景的 create_side_story 工具与本弹层均走此方法。
  Future<Novel> createSideStory({
    required String title,
    required String anchorNovelUrl,
    required String anchorChapterUrl,
    String? description,
  }) =>
      _wrap(
        () => _repo.createSideStory(
          title: title,
          anchorNovelUrl: anchorNovelUrl,
          anchorChapterUrl: anchorChapterUrl,
          description: description,
        ),
        anchorNovelUrl,
      );

  /// 级联删除番外（含全部子番外），返回删除的番外部数。
  Future<int> deleteSideStoryTree(String sideStoryUrl,
          {required String anchorNovelUrl}) =>
      _wrap(
        () => _repo.deleteSideStoryTree(sideStoryUrl),
        anchorNovelUrl,
      );

  /// 级联删除宿主小说挂载的全部番外（主线小说从书架移除时调用）。
  Future<int> deleteSideStoriesOfNovel(String anchorNovelUrl) =>
      _wrap(
        () => _repo.deleteSideStoriesOfNovel(anchorNovelUrl),
        anchorNovelUrl,
      );

  // ===== 内部 =====

  SideStoryRepository get _repo => ref.read(sideStoryRepositoryProvider);

  /// 统一收口：写库 + bump 宿主小说的番外信号。
  ///
  /// 失败不 bump：若 [op] 抛异常，异常向上抛，bump 不执行。
  Future<T> _wrap<T>(Future<T> Function() op, String anchorNovelUrl) async {
    final result = await op();
    ref.read(sideStorySignalProvider(anchorNovelUrl).notifier).bump();
    return result;
  }
}
