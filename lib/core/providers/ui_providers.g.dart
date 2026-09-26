// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ui_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$homeTabIndexNotifierHash() =>
    r'ae5b68787619996beffce4a6588df8070b02985d';

/// 当前选中的底部导航 Tab
///
/// HomePage 监听此 Provider 切换 Tab；其他页面（如书架空状态引导）
/// 可通过 ref.read(homeTabIndexNotifierProvider.notifier).state = ... 切换 Tab。
///
/// Copied from [HomeTabIndexNotifier].
@ProviderFor(HomeTabIndexNotifier)
final homeTabIndexNotifierProvider =
    AutoDisposeNotifierProvider<HomeTabIndexNotifier, int>.internal(
  HomeTabIndexNotifier.new,
  name: r'homeTabIndexNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$homeTabIndexNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$HomeTabIndexNotifier = AutoDisposeNotifier<int>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
