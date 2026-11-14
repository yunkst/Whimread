// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'side_story_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sideStoryCountsHash() => r'3fea20605a87d49891f7b6032c07ff4ceb8bf6eb';

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

/// 各章节挂载的番外数量（目录页章节徽标 / 阅读器顶栏角标的数据源）
///
/// 返回 `Map<anchorChapterUrl, count>`；只含有锚点章的番外。
///
/// Copied from [sideStoryCounts].
@ProviderFor(sideStoryCounts)
const sideStoryCountsProvider = SideStoryCountsFamily();

/// 各章节挂载的番外数量（目录页章节徽标 / 阅读器顶栏角标的数据源）
///
/// 返回 `Map<anchorChapterUrl, count>`；只含有锚点章的番外。
///
/// Copied from [sideStoryCounts].
class SideStoryCountsFamily extends Family<AsyncValue<Map<String, int>>> {
  /// 各章节挂载的番外数量（目录页章节徽标 / 阅读器顶栏角标的数据源）
  ///
  /// 返回 `Map<anchorChapterUrl, count>`；只含有锚点章的番外。
  ///
  /// Copied from [sideStoryCounts].
  const SideStoryCountsFamily();

  /// 各章节挂载的番外数量（目录页章节徽标 / 阅读器顶栏角标的数据源）
  ///
  /// 返回 `Map<anchorChapterUrl, count>`；只含有锚点章的番外。
  ///
  /// Copied from [sideStoryCounts].
  SideStoryCountsProvider call(
    String novelUrl,
  ) {
    return SideStoryCountsProvider(
      novelUrl,
    );
  }

  @override
  SideStoryCountsProvider getProviderOverride(
    covariant SideStoryCountsProvider provider,
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
  String? get name => r'sideStoryCountsProvider';
}

/// 各章节挂载的番外数量（目录页章节徽标 / 阅读器顶栏角标的数据源）
///
/// 返回 `Map<anchorChapterUrl, count>`；只含有锚点章的番外。
///
/// Copied from [sideStoryCounts].
class SideStoryCountsProvider
    extends AutoDisposeFutureProvider<Map<String, int>> {
  /// 各章节挂载的番外数量（目录页章节徽标 / 阅读器顶栏角标的数据源）
  ///
  /// 返回 `Map<anchorChapterUrl, count>`；只含有锚点章的番外。
  ///
  /// Copied from [sideStoryCounts].
  SideStoryCountsProvider(
    String novelUrl,
  ) : this._internal(
          (ref) => sideStoryCounts(
            ref as SideStoryCountsRef,
            novelUrl,
          ),
          from: sideStoryCountsProvider,
          name: r'sideStoryCountsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$sideStoryCountsHash,
          dependencies: SideStoryCountsFamily._dependencies,
          allTransitiveDependencies:
              SideStoryCountsFamily._allTransitiveDependencies,
          novelUrl: novelUrl,
        );

  SideStoryCountsProvider._internal(
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
  Override overrideWith(
    FutureOr<Map<String, int>> Function(SideStoryCountsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: SideStoryCountsProvider._internal(
        (ref) => create(ref as SideStoryCountsRef),
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
  AutoDisposeFutureProviderElement<Map<String, int>> createElement() {
    return _SideStoryCountsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SideStoryCountsProvider && other.novelUrl == novelUrl;
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
mixin SideStoryCountsRef on AutoDisposeFutureProviderRef<Map<String, int>> {
  /// The parameter `novelUrl` of this provider.
  String get novelUrl;
}

class _SideStoryCountsProviderElement
    extends AutoDisposeFutureProviderElement<Map<String, int>>
    with SideStoryCountsRef {
  _SideStoryCountsProviderElement(super.provider);

  @override
  String get novelUrl => (origin as SideStoryCountsProvider).novelUrl;
}

String _$sideStorySummariesHash() =>
    r'5f99a10b2d4c2b430ea03c456ca763c8dc3d03ac';

/// 番外列表汇总（番外列表页数据源）
///
/// [anchorChapterUrl] 传入时只返回挂载在该章的番外（章级视图）；
/// 不传返回宿主小说的全部番外（小说级视图，含子番外）。
///
/// Copied from [sideStorySummaries].
@ProviderFor(sideStorySummaries)
const sideStorySummariesProvider = SideStorySummariesFamily();

/// 番外列表汇总（番外列表页数据源）
///
/// [anchorChapterUrl] 传入时只返回挂载在该章的番外（章级视图）；
/// 不传返回宿主小说的全部番外（小说级视图，含子番外）。
///
/// Copied from [sideStorySummaries].
class SideStorySummariesFamily
    extends Family<AsyncValue<List<SideStorySummary>>> {
  /// 番外列表汇总（番外列表页数据源）
  ///
  /// [anchorChapterUrl] 传入时只返回挂载在该章的番外（章级视图）；
  /// 不传返回宿主小说的全部番外（小说级视图，含子番外）。
  ///
  /// Copied from [sideStorySummaries].
  const SideStorySummariesFamily();

  /// 番外列表汇总（番外列表页数据源）
  ///
  /// [anchorChapterUrl] 传入时只返回挂载在该章的番外（章级视图）；
  /// 不传返回宿主小说的全部番外（小说级视图，含子番外）。
  ///
  /// Copied from [sideStorySummaries].
  SideStorySummariesProvider call(
    String anchorNovelUrl, {
    String? anchorChapterUrl,
  }) {
    return SideStorySummariesProvider(
      anchorNovelUrl,
      anchorChapterUrl: anchorChapterUrl,
    );
  }

  @override
  SideStorySummariesProvider getProviderOverride(
    covariant SideStorySummariesProvider provider,
  ) {
    return call(
      provider.anchorNovelUrl,
      anchorChapterUrl: provider.anchorChapterUrl,
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
  String? get name => r'sideStorySummariesProvider';
}

/// 番外列表汇总（番外列表页数据源）
///
/// [anchorChapterUrl] 传入时只返回挂载在该章的番外（章级视图）；
/// 不传返回宿主小说的全部番外（小说级视图，含子番外）。
///
/// Copied from [sideStorySummaries].
class SideStorySummariesProvider
    extends AutoDisposeFutureProvider<List<SideStorySummary>> {
  /// 番外列表汇总（番外列表页数据源）
  ///
  /// [anchorChapterUrl] 传入时只返回挂载在该章的番外（章级视图）；
  /// 不传返回宿主小说的全部番外（小说级视图，含子番外）。
  ///
  /// Copied from [sideStorySummaries].
  SideStorySummariesProvider(
    String anchorNovelUrl, {
    String? anchorChapterUrl,
  }) : this._internal(
          (ref) => sideStorySummaries(
            ref as SideStorySummariesRef,
            anchorNovelUrl,
            anchorChapterUrl: anchorChapterUrl,
          ),
          from: sideStorySummariesProvider,
          name: r'sideStorySummariesProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$sideStorySummariesHash,
          dependencies: SideStorySummariesFamily._dependencies,
          allTransitiveDependencies:
              SideStorySummariesFamily._allTransitiveDependencies,
          anchorNovelUrl: anchorNovelUrl,
          anchorChapterUrl: anchorChapterUrl,
        );

  SideStorySummariesProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.anchorNovelUrl,
    required this.anchorChapterUrl,
  }) : super.internal();

  final String anchorNovelUrl;
  final String? anchorChapterUrl;

  @override
  Override overrideWith(
    FutureOr<List<SideStorySummary>> Function(SideStorySummariesRef provider)
        create,
  ) {
    return ProviderOverride(
      origin: this,
      override: SideStorySummariesProvider._internal(
        (ref) => create(ref as SideStorySummariesRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        anchorNovelUrl: anchorNovelUrl,
        anchorChapterUrl: anchorChapterUrl,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<SideStorySummary>> createElement() {
    return _SideStorySummariesProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SideStorySummariesProvider &&
        other.anchorNovelUrl == anchorNovelUrl &&
        other.anchorChapterUrl == anchorChapterUrl;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, anchorNovelUrl.hashCode);
    hash = _SystemHash.combine(hash, anchorChapterUrl.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin SideStorySummariesRef
    on AutoDisposeFutureProviderRef<List<SideStorySummary>> {
  /// The parameter `anchorNovelUrl` of this provider.
  String get anchorNovelUrl;

  /// The parameter `anchorChapterUrl` of this provider.
  String? get anchorChapterUrl;
}

class _SideStorySummariesProviderElement
    extends AutoDisposeFutureProviderElement<List<SideStorySummary>>
    with SideStorySummariesRef {
  _SideStorySummariesProviderElement(super.provider);

  @override
  String get anchorNovelUrl =>
      (origin as SideStorySummariesProvider).anchorNovelUrl;
  @override
  String? get anchorChapterUrl =>
      (origin as SideStorySummariesProvider).anchorChapterUrl;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
