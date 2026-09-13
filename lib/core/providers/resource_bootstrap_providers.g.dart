// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'resource_bootstrap_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$appResourceManagerHash() =>
    r'3e5cd377733b50f984aed6df5de011c627d461af';

/// See also [appResourceManager].
@ProviderFor(appResourceManager)
final appResourceManagerProvider =
    AutoDisposeProvider<AppResourceManager>.internal(
  appResourceManager,
  name: r'appResourceManagerProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$appResourceManagerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AppResourceManagerRef = AutoDisposeProviderRef<AppResourceManager>;
String _$resourceBootstrapNotifierHash() =>
    r'0066b375f28ee43a457a624ba804e6248774cef0';

/// 启动资源引导编排器（Notifier 驱动 ResourceBootstrapScreen）
///
/// Copied from [ResourceBootstrapNotifier].
@ProviderFor(ResourceBootstrapNotifier)
final resourceBootstrapNotifierProvider = AutoDisposeNotifierProvider<
    ResourceBootstrapNotifier, ResourceBootstrapState>.internal(
  ResourceBootstrapNotifier.new,
  name: r'resourceBootstrapNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$resourceBootstrapNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ResourceBootstrapNotifier
    = AutoDisposeNotifier<ResourceBootstrapState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
