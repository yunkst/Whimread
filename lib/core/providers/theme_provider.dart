/// Riverpod Theme Provider
///
/// 管理应用主题状态，支持亮色/暗色/跟随系统三种模式
/// 使用 @riverpod 注解自动生成代码
library;

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../services/logger_service.dart';
import '../../services/preferences_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

part 'theme_provider.g.dart';

/// 应用主题模式枚举
enum AppThemeMode {
  light, // 亮色模式
  dark, // 暗色模式
  system, // 跟随系统
}

/// 主题状态类
///
/// 包含当前主题模式和相关配置
class ThemeState {
  final AppThemeMode themeMode;
  final Color seedColor;

  const ThemeState({
    required this.themeMode,
    // 书馆美学种子色：琥珀（暗夜书馆 / 晨读书馆 共用基调）
    this.seedColor = const Color(0xFFB8843A),
  });

  /// 获取Flutter的ThemeMode（用于MaterialApp）
  ThemeMode get flutterThemeMode {
    switch (themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  /// 生成亮色主题数据 · 晨读书馆
  ThemeData getLightTheme() {
    final base = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    return ThemeData(
      colorScheme: base.copyWith(
        surface: AppColors.light.paper,
        onSurface: AppColors.light.ink,
      ),
      scaffoldBackgroundColor: AppColors.light.paper,
      useMaterial3: true,
      // 全局默认字体：无衬线 + 中文 fallback 链（项目内嵌 NotoSansSC）
      fontFamily: AppTypography.sans,
      fontFamilyFallback: AppTypography.sansFallback,
      extensions: const <ThemeExtension<dynamic>>[AppColors.light],
    );
  }

  /// 生成暗色主题数据 · 暗夜书馆
  ThemeData getDarkTheme() {
    final base = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    return ThemeData(
      colorScheme: base.copyWith(
        surface: AppColors.dark.paper,
        onSurface: AppColors.dark.ink,
      ),
      scaffoldBackgroundColor: AppColors.dark.paper,
      useMaterial3: true,
      fontFamily: AppTypography.sans,
      fontFamilyFallback: AppTypography.sansFallback,
      extensions: const <ThemeExtension<dynamic>>[AppColors.dark],
    );
  }

  /// 复制并修改状态
  ThemeState copyWith({AppThemeMode? themeMode, Color? seedColor}) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      seedColor: seedColor ?? this.seedColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeState &&
          runtimeType == other.runtimeType &&
          themeMode == other.themeMode &&
          seedColor == other.seedColor;

  @override
  int get hashCode => themeMode.hashCode ^ seedColor.hashCode;
}

/// ThemeNotifier
///
/// 管理主题状态，支持主题切换和持久化
@riverpod
class ThemeNotifier extends _$ThemeNotifier {
  static const String _themeModeKey = 'theme_mode';

  /// 初始化主题状态
  ///
  /// 从 SharedPreferences 加载保存的主题设置
  @override
  Future<ThemeState> build() async {
    // 保持状态，不被自动销毁
    ref.keepAlive();

    // 获取 PreferencesService
    final prefs = PreferencesService.instance;

    try {
      LoggerService.instance.d(
        '开始加载主题设置',
        category: LogCategory.ui,
        tags: ['provider', 'theme', 'load'],
      );
      final themeModeString = await prefs.getString(_themeModeKey);

      AppThemeMode themeMode;
      if (themeModeString.isNotEmpty) {
        themeMode = AppThemeMode.values.firstWhere(
          (mode) => mode.toString() == themeModeString,
          orElse: () => AppThemeMode.system,
        );
      } else {
        // 默认跟随系统：日间浅色「晨读书馆」纸感，夜间「暗夜书馆」
        themeMode = AppThemeMode.system;
      }

      LoggerService.instance.i(
        '主题设置加载成功: $themeMode',
        category: LogCategory.ui,
        tags: ['provider', 'theme', 'load'],
      );
      return ThemeState(themeMode: themeMode);
    } catch (e, st) {
      LoggerService.instance.e(
        '加载主题设置失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ui,
        tags: ['provider', 'theme', 'load'],
      );
      // 发生错误时使用默认主题
      return const ThemeState(themeMode: AppThemeMode.system);
    }
  }

  /// 设置主题模式
  Future<void> setThemeMode(AppThemeMode mode) async {
    // 如果主题没有变化，不做任何操作
    final current = await future;
    if (current.themeMode == mode) return;

    LoggerService.instance.d(
      '设置主题模式: $mode',
      category: LogCategory.ui,
      tags: ['provider', 'theme', 'set'],
    );

    try {
      final prefs = PreferencesService.instance;

      // 保存到 SharedPreferences
      await prefs.setString(_themeModeKey, mode.toString());

      // 更新状态
      state = AsyncData(current.copyWith(themeMode: mode));
      LoggerService.instance.i(
        '主题模式切换成功: $mode',
        category: LogCategory.ui,
        tags: ['provider', 'theme', 'set'],
      );
    } catch (e, st) {
      LoggerService.instance.e(
        '保存主题模式失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ui,
        tags: ['provider', 'theme', 'set'],
      );
      // 保存失败时抛出错误
      throw Exception('保存主题模式失败: $e');
    }
  }

}
