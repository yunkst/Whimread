// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ui_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$toastNotifierHash() => r'5e6227980861a53aa28452e8fd607ec12e9e99fd';

/// Toast状态管理器
///
/// **职责**:
/// - 管理Toast消息状态
/// - 提供显示各类Toast的接口
/// - 自动触发状态更新通知UI层
///
/// **架构原则**:
/// - Notifier只管理状态，不直接显示Toast
/// - UI层通过ref.listen监听状态变化并显示
/// - 显示后立即清除状态，避免重复显示
///
/// Copied from [ToastNotifier].
@ProviderFor(ToastNotifier)
final toastNotifierProvider =
    AutoDisposeNotifierProvider<ToastNotifier, ToastState>.internal(
  ToastNotifier.new,
  name: r'toastNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$toastNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ToastNotifier = AutoDisposeNotifier<ToastState>;
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
