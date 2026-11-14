/// 番外数据变更信号 Provider（family by anchorNovelUrl）。
///
/// 与 `chapterMutationSignalProvider` 同构：番外列表/徽标的数据源
/// （`SideStoryRepository` 查询）按宿主小说 URL 分桶，而番外列表页持有的
/// Novel 实例不适合做 provider 参数（对象身份问题），故用
/// **family by String anchorNovelUrl 的 int tick** 作信号。
///
/// `SideStoryMutationNotifier` 每次创建/删除番外成功后 bump 对应宿主的
/// tick；徽标 provider 与番外列表页 `ref.listen` 该信号刷新。
/// 失败不 bump（避免半真半假 UI）。
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'side_story_signal_provider.g.dart';

/// 番外数据变更信号（按宿主小说 URL 分桶的 tick 计数器）
@riverpod
class SideStorySignal extends _$SideStorySignal {
  @override
  int build(String anchorNovelUrl) => 0;

  /// tick +1，触发监听本宿主的徽标/列表刷新
  void bump() => state++;
}
