import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database_providers.dart';

/// Agent 写作场景的"当前小说"工作区
///
/// 与 [ReadingContext] 不同：
/// - ReadingContext 表示用户当前正阅读的位置（被动）
/// - CurrentNovel 表示 Agent 操作的目标小说（可被 select_novel 工具主动切换）
class CurrentNovel {
  /// 数据库主键（全局唯一）
  final int id;

  /// 小说标题
  final String title;

  /// 小说 URL（用于 Repository 查询）
  final String url;

  const CurrentNovel({
    required this.id,
    required this.title,
    required this.url,
  });
}

/// 全局当前小说 Provider
///
/// 监听 [selectNovel] 调用以更新当前工作小说。
/// 工具执行器通过 [AgentScenarioContext.currentNovelId] 读取此值。
final currentNovelProvider = StateProvider<CurrentNovel?>((ref) => null);

/// 仅查询小说，不写全局 provider
///
/// 会话恢复路径（hydrate / adoptSession）用本函数装配会话私有的
/// _currentNovel——写全局是"用户主动选书"的副作用，恢复历史会话时
/// 不应顺手覆盖其他会话/工具看到的全局值（issue #24）。
Future<CurrentNovel?> loadNovel(Ref ref, int novelId) async {
  final repo = ref.read(novelRepositoryProvider);
  final novel = await repo.getNovelById(novelId);
  if (novel == null) return null;
  return CurrentNovel(
    id: novel.id!,
    title: novel.title,
    url: novel.url,
  );
}

/// 切换当前小说（UI / 工具统一入口）
///
/// 与 [loadNovel] 的区别：本函数表达"用户/工具主动选书"意图，
/// 会同步写全局 [currentNovelProvider]。返回切换结果；找不到小说时返回 null。
Future<CurrentNovel?> selectCurrentNovel(Ref ref, int novelId) async {
  final current = await loadNovel(ref, novelId);
  if (current != null) {
    ref.read(currentNovelProvider.notifier).state = current;
  }
  return current;
}
