/// Onboarding 新手引导 Provider
///
/// 管理新手引导状态，支持首次启动向导和场景化提示。
/// 使用 SharedPreferences 持久化引导完成标记。
///
/// 使用示例：
/// ```dart
/// // 检查是否需要显示引导（main.dart 的 _AppRoot 即此用法）
/// final state = await ref.watch(onboardingNotifierProvider.future);
/// if (!state.onboardingCompleted) { /* 显示引导页面 */ }
///
/// // 标记引导完成
/// ref.read(onboardingNotifierProvider.notifier).completeOnboarding();
///
/// ```
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/logger_service.dart';
import '../../services/preferences_service.dart';

part 'onboarding_providers.g.dart';

/// Onboarding 引导状态数据类
///
/// 目前只跟踪「首次启动向导是否已完成」一个标记。
class OnboardingState {
  /// 首次启动向导是否已完成
  final bool onboardingCompleted;

  const OnboardingState({this.onboardingCompleted = false});

  /// 初始状态（未完成任何引导）
  static const initial = OnboardingState();

  OnboardingState copyWith({bool? onboardingCompleted}) {
    return OnboardingState(
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OnboardingState &&
          runtimeType == other.runtimeType &&
          onboardingCompleted == other.onboardingCompleted;

  @override
  int get hashCode => onboardingCompleted.hashCode;
}

/// Onboarding 状态管理器
///
/// **职责**:
/// - 从 SharedPreferences 加载引导完成状态
/// - 提供标记完成/重置接口
/// - 管理各场景独立的引导标记
///
/// **持久化键**:
/// - `onboarding_completed`: 首次启动向导
///
/// 历史注记：书架/搜索/阅读器/章节列表四个 per-场景引导标记从未被任何
/// 界面写入或读取，已随死代码清理移除。
@riverpod
class OnboardingNotifier extends _$OnboardingNotifier {
  static const String _onboardingCompletedKey = 'onboarding_completed';

  @override
  Future<OnboardingState> build() async {
    ref.keepAlive();

    try {
      final prefs = PreferencesService.instance;

      final onboardingCompleted =
          await prefs.getBool(_onboardingCompletedKey);

      LoggerService.instance.i(
        'Onboarding 状态加载完成: completed=$onboardingCompleted',
        category: LogCategory.general,
        tags: ['onboarding', 'load'],
      );

      return OnboardingState(onboardingCompleted: onboardingCompleted);
    } catch (e, st) {
      LoggerService.instance.e(
        '加载 Onboarding 状态失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.general,
        tags: ['onboarding', 'load', 'error'],
      );
      return OnboardingState.initial;
    }
  }

  /// 标记首次启动向导已完成
  Future<void> completeOnboarding() async {
    try {
      final prefs = PreferencesService.instance;
      await prefs.setBool(_onboardingCompletedKey, true);

      final current = await future;
      state = AsyncData(current.copyWith(onboardingCompleted: true));

      LoggerService.instance.i(
        '新手引导已完成',
        category: LogCategory.general,
        tags: ['onboarding', 'complete'],
      );
    } catch (e, st) {
      LoggerService.instance.e(
        '保存引导完成状态失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.general,
        tags: ['onboarding', 'save', 'error'],
      );
    }
  }

}
