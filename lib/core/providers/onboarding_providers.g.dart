// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'onboarding_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$onboardingNotifierHash() =>
    r'a250e185fc505b585c3c4de199cb8883b1c5b937';

/// Onboarding 状态管理器
///
/// **职责**:
/// - 从 SharedPreferences 加载引导完成状态
/// - 提供标记完成/重置接口
/// - 管理各场景独立的引导标记
///
/// **持久化键**:
/// - `onboarding_completed`: 首次启动向导
/// - `guide_bookshelf_shown`: 书架引导
/// - `guide_search_shown`: 搜索引导
/// - `guide_reader_shown`: 阅读器引导
/// - `guide_chapter_list_shown`: 章节列表引导
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
