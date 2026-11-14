/// 番外读数据 providers
///
/// 数据源是 `SideStoryRepository` 的查询（非 Notifier 状态），通过 watch
/// `sideStorySignalProvider(novelUrl)` 获得刷新时机：番外创建/删除后信号
/// bump，本文件的 family provider 自动重查。
library;

import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/side_story_summary.dart';
import 'database_providers.dart';
import 'side_story_signal_provider.dart';

part 'side_story_providers.g.dart';

/// 各章节挂载的番外数量（目录页章节徽标 / 阅读器顶栏角标的数据源）
///
/// 返回 `Map<anchorChapterUrl, count>`；只含有锚点章的番外。
@riverpod
Future<Map<String, int>> sideStoryCounts(Ref ref, String novelUrl) {
  // watch signal：创建/删除番外后 bump → 本 provider 重查
  ref.watch(sideStorySignalProvider(novelUrl));
  return ref
      .watch(sideStoryRepositoryProvider)
      .getSideStoryCountsByChapter(novelUrl);
}

/// 番外列表汇总（番外列表页数据源）
///
/// [anchorChapterUrl] 传入时只返回挂载在该章的番外（章级视图）；
/// 不传返回宿主小说的全部番外（小说级视图，含子番外）。
@riverpod
Future<List<SideStorySummary>> sideStorySummaries(
  Ref ref,
  String anchorNovelUrl, {
  String? anchorChapterUrl,
}) {
  ref.watch(sideStorySignalProvider(anchorNovelUrl));
  return ref
      .watch(sideStoryRepositoryProvider)
      .getSideStories(
        anchorNovelUrl: anchorNovelUrl,
        anchorChapterUrl: anchorChapterUrl,
      );
}
