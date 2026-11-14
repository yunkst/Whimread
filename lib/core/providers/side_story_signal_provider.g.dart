// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'side_story_signal_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sideStorySignalHash() => r'0da0f6f6a99cf63b821ade698f58b05233787767';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

abstract class _$SideStorySignal extends BuildlessAutoDisposeNotifier<int> {
  late final String anchorNovelUrl;

  int build(
    String anchorNovelUrl,
  );
}

/// 番外数据变更信号（按宿主小说 URL 分桶的 tick 计数器）
///
/// Copied from [SideStorySignal].
@ProviderFor(SideStorySignal)
const sideStorySignalProvider = SideStorySignalFamily();

/// 番外数据变更信号（按宿主小说 URL 分桶的 tick 计数器）
///
/// Copied from [SideStorySignal].
class SideStorySignalFamily extends Family<int> {
  /// 番外数据变更信号（按宿主小说 URL 分桶的 tick 计数器）
  ///
  /// Copied from [SideStorySignal].
  const SideStorySignalFamily();

  /// 番外数据变更信号（按宿主小说 URL 分桶的 tick 计数器）
  ///
  /// Copied from [SideStorySignal].
  SideStorySignalProvider call(
    String anchorNovelUrl,
  ) {
    return SideStorySignalProvider(
      anchorNovelUrl,
    );
  }

  @override
  SideStorySignalProvider getProviderOverride(
    covariant SideStorySignalProvider provider,
  ) {
    return call(
      provider.anchorNovelUrl,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'sideStorySignalProvider';
}

/// 番外数据变更信号（按宿主小说 URL 分桶的 tick 计数器）
///
/// Copied from [SideStorySignal].
class SideStorySignalProvider
    extends AutoDisposeNotifierProviderImpl<SideStorySignal, int> {
  /// 番外数据变更信号（按宿主小说 URL 分桶的 tick 计数器）
  ///
  /// Copied from [SideStorySignal].
  SideStorySignalProvider(
    String anchorNovelUrl,
  ) : this._internal(
          () => SideStorySignal()..anchorNovelUrl = anchorNovelUrl,
          from: sideStorySignalProvider,
          name: r'sideStorySignalProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$sideStorySignalHash,
          dependencies: SideStorySignalFamily._dependencies,
          allTransitiveDependencies:
              SideStorySignalFamily._allTransitiveDependencies,
          anchorNovelUrl: anchorNovelUrl,
        );

  SideStorySignalProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.anchorNovelUrl,
  }) : super.internal();

  final String anchorNovelUrl;

  @override
  int runNotifierBuild(
    covariant SideStorySignal notifier,
  ) {
    return notifier.build(
      anchorNovelUrl,
    );
  }

  @override
  Override overrideWith(SideStorySignal Function() create) {
    return ProviderOverride(
      origin: this,
      override: SideStorySignalProvider._internal(
        () => create()..anchorNovelUrl = anchorNovelUrl,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        anchorNovelUrl: anchorNovelUrl,
      ),
    );
  }

  @override
  AutoDisposeNotifierProviderElement<SideStorySignal, int> createElement() {
    return _SideStorySignalProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SideStorySignalProvider &&
        other.anchorNovelUrl == anchorNovelUrl;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, anchorNovelUrl.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin SideStorySignalRef on AutoDisposeNotifierProviderRef<int> {
  /// The parameter `anchorNovelUrl` of this provider.
  String get anchorNovelUrl;
}

class _SideStorySignalProviderElement
    extends AutoDisposeNotifierProviderElement<SideStorySignal, int>
    with SideStorySignalRef {
  _SideStorySignalProviderElement(super.provider);

  @override
  String get anchorNovelUrl =>
      (origin as SideStorySignalProvider).anchorNovelUrl;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
