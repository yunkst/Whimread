// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chapter_mutation_signal_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$chapterMutationSignalHash() =>
    r'5f8a169aac7f3f1f84ae0bb52e4cb60d30eb7a7c';

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

abstract class _$ChapterMutationSignal
    extends BuildlessAutoDisposeNotifier<int> {
  late final String novelUrl;

  int build(
    String novelUrl,
  );
}

/// 章节数据变更信号（按 novelUrl 分桶的 tick 计数器）。
///
/// 写操作聚合 Notifier [ChapterMutationNotifier] 在每次写库成功后 `bump()`，
/// 触发对应小说的 `chapterListProvider` 软刷新。失败不 bump（避免半真半假 UI）。
///
/// Copied from [ChapterMutationSignal].
@ProviderFor(ChapterMutationSignal)
const chapterMutationSignalProvider = ChapterMutationSignalFamily();

/// 章节数据变更信号（按 novelUrl 分桶的 tick 计数器）。
///
/// 写操作聚合 Notifier [ChapterMutationNotifier] 在每次写库成功后 `bump()`，
/// 触发对应小说的 `chapterListProvider` 软刷新。失败不 bump（避免半真半假 UI）。
///
/// Copied from [ChapterMutationSignal].
class ChapterMutationSignalFamily extends Family<int> {
  /// 章节数据变更信号（按 novelUrl 分桶的 tick 计数器）。
  ///
  /// 写操作聚合 Notifier [ChapterMutationNotifier] 在每次写库成功后 `bump()`，
  /// 触发对应小说的 `chapterListProvider` 软刷新。失败不 bump（避免半真半假 UI）。
  ///
  /// Copied from [ChapterMutationSignal].
  const ChapterMutationSignalFamily();

  /// 章节数据变更信号（按 novelUrl 分桶的 tick 计数器）。
  ///
  /// 写操作聚合 Notifier [ChapterMutationNotifier] 在每次写库成功后 `bump()`，
  /// 触发对应小说的 `chapterListProvider` 软刷新。失败不 bump（避免半真半假 UI）。
  ///
  /// Copied from [ChapterMutationSignal].
  ChapterMutationSignalProvider call(
    String novelUrl,
  ) {
    return ChapterMutationSignalProvider(
      novelUrl,
    );
  }

  @override
  ChapterMutationSignalProvider getProviderOverride(
    covariant ChapterMutationSignalProvider provider,
  ) {
    return call(
      provider.novelUrl,
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
  String? get name => r'chapterMutationSignalProvider';
}

/// 章节数据变更信号（按 novelUrl 分桶的 tick 计数器）。
///
/// 写操作聚合 Notifier [ChapterMutationNotifier] 在每次写库成功后 `bump()`，
/// 触发对应小说的 `chapterListProvider` 软刷新。失败不 bump（避免半真半假 UI）。
///
/// Copied from [ChapterMutationSignal].
class ChapterMutationSignalProvider
    extends AutoDisposeNotifierProviderImpl<ChapterMutationSignal, int> {
  /// 章节数据变更信号（按 novelUrl 分桶的 tick 计数器）。
  ///
  /// 写操作聚合 Notifier [ChapterMutationNotifier] 在每次写库成功后 `bump()`，
  /// 触发对应小说的 `chapterListProvider` 软刷新。失败不 bump（避免半真半假 UI）。
  ///
  /// Copied from [ChapterMutationSignal].
  ChapterMutationSignalProvider(
    String novelUrl,
  ) : this._internal(
          () => ChapterMutationSignal()..novelUrl = novelUrl,
          from: chapterMutationSignalProvider,
          name: r'chapterMutationSignalProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$chapterMutationSignalHash,
          dependencies: ChapterMutationSignalFamily._dependencies,
          allTransitiveDependencies:
              ChapterMutationSignalFamily._allTransitiveDependencies,
          novelUrl: novelUrl,
        );

  ChapterMutationSignalProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.novelUrl,
  }) : super.internal();

  final String novelUrl;

  @override
  int runNotifierBuild(
    covariant ChapterMutationSignal notifier,
  ) {
    return notifier.build(
      novelUrl,
    );
  }

  @override
  Override overrideWith(ChapterMutationSignal Function() create) {
    return ProviderOverride(
      origin: this,
      override: ChapterMutationSignalProvider._internal(
        () => create()..novelUrl = novelUrl,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        novelUrl: novelUrl,
      ),
    );
  }

  @override
  AutoDisposeNotifierProviderElement<ChapterMutationSignal, int>
      createElement() {
    return _ChapterMutationSignalProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ChapterMutationSignalProvider && other.novelUrl == novelUrl;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, novelUrl.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ChapterMutationSignalRef on AutoDisposeNotifierProviderRef<int> {
  /// The parameter `novelUrl` of this provider.
  String get novelUrl;
}

class _ChapterMutationSignalProviderElement
    extends AutoDisposeNotifierProviderElement<ChapterMutationSignal, int>
    with ChapterMutationSignalRef {
  _ChapterMutationSignalProviderElement(super.provider);

  @override
  String get novelUrl => (origin as ChapterMutationSignalProvider).novelUrl;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
