// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'onboarding_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$onboardingNotifierHash() =>
    r'7667dfc04cf14aa1426e058de727b0c2a1477bf1';

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
///
/// Copied from [OnboardingNotifier].
@ProviderFor(OnboardingNotifier)
final onboardingNotifierProvider = AutoDisposeAsyncNotifierProvider<
    OnboardingNotifier, OnboardingState>.internal(
  OnboardingNotifier.new,
  name: r'onboardingNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$onboardingNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$OnboardingNotifier = AutoDisposeAsyncNotifier<OnboardingState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
