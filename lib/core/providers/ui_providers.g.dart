// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ui_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$homeTabNotifierHash() => r'99d82034395d2d050fa19201fd4c3afdc3f0c519';

/// 当前选中的底部导航 Tab
///
/// 状态是 [HomeTab] 枚举而非裸 int：Tab 的顺序/文案/图标定义在枚举里，
/// 页面栈与导航栏都由它派生，任何地方不再出现魔法索引。
/// HomePage 监听此 Provider 切换 Tab；其他页面可通过
/// `ref.read(homeTabNotifierProvider.notifier).state = ...` 切换 Tab。
///
/// Copied from [HomeTabNotifier].
@ProviderFor(HomeTabNotifier)
final homeTabNotifierProvider =
    AutoDisposeNotifierProvider<HomeTabNotifier, HomeTab>.internal(
  HomeTabNotifier.new,
  name: r'homeTabNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$homeTabNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$HomeTabNotifier = AutoDisposeNotifier<HomeTab>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
