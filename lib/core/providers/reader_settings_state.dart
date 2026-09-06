import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../services/reader_settings_service.dart';

part 'reader_settings_state.g.dart';

/// ReaderSettingsState
///
/// 管理阅读器设置的状态
/// 包括字体大小、滚动速度等
class ReaderSettingsState {
  final double? fontSize;
  final double? scrollSpeed;
  final double? textBrightness;

  const ReaderSettingsState({
    this.fontSize,
    this.scrollSpeed,
    this.textBrightness,
  });

  ReaderSettingsState copyWith({
    double? fontSize,
    double? scrollSpeed,
    double? textBrightness,
  }) {
    return ReaderSettingsState(
      fontSize: fontSize ?? this.fontSize,
      scrollSpeed: scrollSpeed ?? this.scrollSpeed,
      textBrightness: textBrightness ?? this.textBrightness,
    );
  }
}

/// ReaderSettingsStateNotifier Provider
///
/// 管理阅读器设置状态，自动持久化到 SharedPreferences
@riverpod
class ReaderSettingsStateNotifier extends _$ReaderSettingsStateNotifier {
  @override
  Future<ReaderSettingsState> build() async {
    // 从服务加载初始设置
    final service = ReaderSettingsService.instance;
    final fontSize = await service.getFontSize();
    final scrollSpeed = await service.getScrollSpeed();
    final textBrightness = await service.getTextBrightness();

    return ReaderSettingsState(
      fontSize: fontSize,
      scrollSpeed: scrollSpeed,
      textBrightness: textBrightness,
    );
  }

  /// 更新字体大小
  Future<void> setFontSize(double newSize) async {
    final service = ReaderSettingsService.instance;
    await service.setFontSize(newSize);

    // 更新状态
    state = AsyncData(state.value?.copyWith(fontSize: newSize) ??
        ReaderSettingsState(fontSize: newSize));
  }

  /// 更新滚动速度
  Future<void> setScrollSpeed(double newSpeed) async {
    final service = ReaderSettingsService.instance;
    await service.setScrollSpeed(newSpeed);

    // 更新状态
    state = AsyncData(state.value?.copyWith(scrollSpeed: newSpeed) ??
        ReaderSettingsState(scrollSpeed: newSpeed));
  }

  /// 更新文字亮度
  Future<void> setTextBrightness(double newBrightness) async {
    final service = ReaderSettingsService.instance;
    await service.setTextBrightness(newBrightness);

    // 更新状态
    state = AsyncData(state.value?.copyWith(textBrightness: newBrightness) ??
        ReaderSettingsState(textBrightness: newBrightness));
  }

}
