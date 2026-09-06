/// 章节数据变更信号 Provider（family by novelUrl）。
///
/// 与 [BookshelfMutationNotifier] 用 `ref.invalidate(bookshelfNovelsProvider)`
/// 不同——章节列表 `chapterListProvider` 是 **family by Novel**，而 `Novel` 未实现
/// `==`/`hashCode`（默认对象身份），从 novelUrl 重构的 Novel 与 UI 持有实例不等，
/// `invalidate(chapterListProvider(novelFromUrl))` 命中不到 UI 实例；全 family
/// invalidate 又会重置 currentPage/退出重排模式（UX 跳页）。
///
/// 故改用 **family by String novelUrl 的 int tick** 作信号：[ChapterMutationNotifier]
/// 写库成功后 `bump()` 对应 novelUrl 的 tick，[ChapterList.build] 内
/// `ref.listen(chapterMutationSignalProvider(novel.url), ...)` 触发 **softReload**
/// （重读 chapters 替换 state，保留分页/loading/重排状态）。
///
/// signal arg 用 String novelUrl，与 UI Novel 实例解耦，规避对象身份坑；只触发
/// 对应 novelUrl 的 listen，其他 family 实例零成本。
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chapter_mutation_signal_provider.g.dart';

/// 章节数据变更信号（按 novelUrl 分桶的 tick 计数器）。
///
/// 写操作聚合 Notifier [ChapterMutationNotifier] 在每次写库成功后 `bump()`，
/// 触发对应小说的 `chapterListProvider` 软刷新。失败不 bump（避免半真半假 UI）。
@riverpod
class ChapterMutationSignal extends _$ChapterMutationSignal {
  @override
  int build(String novelUrl) => 0;

  /// tick +1，触发监听本信号的 ChapterList 软刷新。
  void bump() => state++;
}
