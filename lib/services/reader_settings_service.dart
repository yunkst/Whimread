import 'preferences_service.dart';

/// 阅读器设置服务
///
/// 负责管理阅读器的用户偏好设置持久化
class ReaderSettingsService {
  // ========== 单例模式 ==========
  static ReaderSettingsService? _instance;
  static ReaderSettingsService get instance {
    _instance ??= ReaderSettingsService._();
    return _instance!;
  }

  ReaderSettingsService._();

  // ========== SharedPreferences 键常量 ==========
  static const String _keyFontSize = 'reader_font_size';
  static const String _keyScrollSpeed = 'reader_scroll_speed';
  static const String _keyTextBrightness = 'reader_text_brightness';

  // ========== 默认值常量 ==========
  static const double _defaultFontSize = 18.0;
  static const double _defaultScrollSpeed = 1.0;
  static const double _defaultTextBrightness = 1.0;

  // ========== Preferences 服务实例 ==========
  static final PreferencesService _prefs = PreferencesService();

  // ========== 公开方法 ==========

  /// 获取字体大小
  Future<double> getFontSize() async {
    return await _prefs.getDouble(_keyFontSize, defaultValue: _defaultFontSize);
  }

  /// 设置字体大小
  Future<void> setFontSize(double fontSize) async {
    await _prefs.setDouble(_keyFontSize, fontSize);
  }

  /// 获取滚动速度
  Future<double> getScrollSpeed() async {
    return await _prefs.getDouble(_keyScrollSpeed,
        defaultValue: _defaultScrollSpeed);
  }

  /// 设置滚动速度
  Future<void> setScrollSpeed(double scrollSpeed) async {
    await _prefs.setDouble(_keyScrollSpeed, scrollSpeed);
  }

  /// 获取文字亮度
  ///
  /// 范围 0.0(最暗) ~ 1.0(最亮,默认)
  Future<double> getTextBrightness() async {
    return await _prefs.getDouble(_keyTextBrightness,
        defaultValue: _defaultTextBrightness);
  }

  /// 设置文字亮度
  Future<void> setTextBrightness(double brightness) async {
    await _prefs.setDouble(_keyTextBrightness, brightness);
  }

  /// 重置所有设置为默认值
  Future<void> resetToDefaults() async {
    await setFontSize(_defaultFontSize);
    await setScrollSpeed(_defaultScrollSpeed);
    await setTextBrightness(_defaultTextBrightness);
  }
}
