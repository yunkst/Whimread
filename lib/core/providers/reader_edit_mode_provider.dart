import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'reader_edit_mode_provider.g.dart';

/// 阅读器编辑模式状态管理Provider
///
/// 用于管理阅读器的编辑模式状态，支持段落编辑、改写等功能
@riverpod
class ReaderEditMode extends _$ReaderEditMode {
  @override
  bool build() => false;

  /// 切换编辑模式
  void toggle() => state = !state;

  /// 启用编辑模式
  void enable() => state = true;

  /// 禁用编辑模式
  void disable() => state = false;
}
