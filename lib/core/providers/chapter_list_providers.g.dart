// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chapter_list_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$preloadProgressHash() => r'dbf149df8f45977d02fa916bbe473dd817cfbd40';

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

/// 预加载进度监听 Provider
///
/// 监听 PreloadService 的进度更新
///
/// Copied from [preloadProgress].
@ProviderFor(preloadProgress)
const preloadProgressProvider = PreloadProgressFamily();

/// 预加载进度监听 Provider
///
/// 监听 PreloadService 的进度更新
///
/// Copied from [preloadProgress].
class PreloadProgressFamily extends Family<AsyncValue<PreloadProgressUpdate>> {
  /// 预加载进度监听 Provider
  ///
  /// 监听 PreloadService 的进度更新
  ///
  /// Copied from [preloadProgress].
  const PreloadProgressFamily();

  /// 预加载进度监听 Provider
  ///
  /// 监听 PreloadService 的进度更新
  ///
  /// Copied from [preloadProgress].
  PreloadProgressProvider call(
    Novel novel,
  ) {
    return PreloadProgressProvider(
      novel,
    );
  }

  @override
  PreloadProgressProvider getProviderOverride(
    covariant PreloadProgressProvider provider,
  ) {
    return call(
      provider.novel,
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
  String? get name => r'preloadProgressProvider';
}

/// 预加载进度监听 Provider
///
/// 监听 PreloadService 的进度更新
///
/// Copied from [preloadProgress].
class PreloadProgressProvider
    extends AutoDisposeStreamProvider<PreloadProgressUpdate> {
  /// 预加载进度监听 Provider
  ///
  /// 监听 PreloadService 的进度更新
  ///
  /// Copied from [preloadProgress].
  PreloadProgressProvider(
    Novel novel,
  ) : this._internal(
          (ref) => preloadProgress(
            ref as PreloadProgressRef,
            novel,
          ),
          from: preloadProgressProvider,
          name: r'preloadProgressProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$preloadProgressHash,
          dependencies: PreloadProgressFamily._dependencies,
          allTransitiveDependencies:
              PreloadProgressFamily._allTransitiveDependencies,
          novel: novel,
        );

  PreloadProgressProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.novel,
  }) : super.internal();

  final Novel novel;

  @override
  Override overrideWith(
    Stream<PreloadProgressUpdate> Function(PreloadProgressRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PreloadProgressProvider._internal(
        (ref) => create(ref as PreloadProgressRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        novel: novel,
      ),
    );
  }

  @override
  AutoDisposeStreamProviderElement<PreloadProgressUpdate> createElement() {
    return _PreloadProgressProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PreloadProgressProvider && other.novel == novel;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, novel.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin PreloadProgressRef
    on AutoDisposeStreamProviderRef<PreloadProgressUpdate> {
  /// The parameter `novel` of this provider.
  Novel get novel;
}

class _PreloadProgressProviderElement
    extends AutoDisposeStreamProviderElement<PreloadProgressUpdate>
    with PreloadProgressRef {
  _PreloadProgressProviderElement(super.provider);

  @override
  Novel get novel => (origin as PreloadProgressProvider).novel;
}

String _$chapterListHash() => r'73d4721d04e1a92be804028e78269d9df98afc83';

abstract class _$ChapterList
    extends BuildlessAutoDisposeNotifier<ChapterListState> {
  late final Novel novel;

  ChapterListState build(
    Novel novel,
  );
}

/// ChapterListStateNotifier
///
/// 管理 ChapterListScreen 的状态
///
/// Copied from [ChapterList].
@ProviderFor(ChapterList)
const chapterListProvider = ChapterListFamily();

/// ChapterListStateNotifier
///
/// 管理 ChapterListScreen 的状态
///
/// Copied from [ChapterList].
class ChapterListFamily extends Family<ChapterListState> {
  /// ChapterListStateNotifier
  ///
  /// 管理 ChapterListScreen 的状态
  ///
  /// Copied from [ChapterList].
  const ChapterListFamily();

  /// ChapterListStateNotifier
  ///
  /// 管理 ChapterListScreen 的状态
  ///
  /// Copied from [ChapterList].
  ChapterListProvider call(
    Novel novel,
  ) {
    return ChapterListProvider(
      novel,
    );
  }

  @override
  ChapterListProvider getProviderOverride(
    covariant ChapterListProvider provider,
  ) {
    return call(
      provider.novel,
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
  String? get name => r'chapterListProvider';
}

/// ChapterListStateNotifier
///
/// 管理 ChapterListScreen 的状态
///
/// Copied from [ChapterList].
class ChapterListProvider
    extends AutoDisposeNotifierProviderImpl<ChapterList, ChapterListState> {
  /// ChapterListStateNotifier
  ///
  /// 管理 ChapterListScreen 的状态
  ///
  /// Copied from [ChapterList].
  ChapterListProvider(
    Novel novel,
  ) : this._internal(
          () => ChapterList()..novel = novel,
          from: chapterListProvider,
          name: r'chapterListProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$chapterListHash,
          dependencies: ChapterListFamily._dependencies,
          allTransitiveDependencies:
              ChapterListFamily._allTransitiveDependencies,
          novel: novel,
        );

  ChapterListProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.novel,
  }) : super.internal();

  final Novel novel;

  @override
  ChapterListState runNotifierBuild(
    covariant ChapterList notifier,
  ) {
    return notifier.build(
      novel,
    );
  }

  @override
  Override overrideWith(ChapterList Function() create) {
    return ProviderOverride(
      origin: this,
      override: ChapterListProvider._internal(
        () => create()..novel = novel,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        novel: novel,
      ),
    );
  }

  @override
  AutoDisposeNotifierProviderElement<ChapterList, ChapterListState>
      createElement() {
    return _ChapterListProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ChapterListProvider && other.novel == novel;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, novel.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ChapterListRef on AutoDisposeNotifierProviderRef<ChapterListState> {
  /// The parameter `novel` of this provider.
  Novel get novel;
}

class _ChapterListProviderElement
    extends AutoDisposeNotifierProviderElement<ChapterList, ChapterListState>
    with ChapterListRef {
  _ChapterListProviderElement(super.provider);

  @override
  Novel get novel => (origin as ChapterListProvider).novel;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
