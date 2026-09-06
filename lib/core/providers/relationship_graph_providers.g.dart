// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'relationship_graph_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$currentChapterHash() => r'74a946ca39e2081cc32f96ec32bfa0a22beb1719';

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

/// 当前章节进度(0-based index)。
///
/// 默认取阅读进度 [NovelRepository.getLastReadChapter];关系图页面可通过
/// 手动滑块覆盖(覆盖值由 UI 层持有,不存于此 provider)。
///
/// Copied from [currentChapter].
@ProviderFor(currentChapter)
const currentChapterProvider = CurrentChapterFamily();

/// 当前章节进度(0-based index)。
///
/// 默认取阅读进度 [NovelRepository.getLastReadChapter];关系图页面可通过
/// 手动滑块覆盖(覆盖值由 UI 层持有,不存于此 provider)。
///
/// Copied from [currentChapter].
class CurrentChapterFamily extends Family<AsyncValue<int>> {
  /// 当前章节进度(0-based index)。
  ///
  /// 默认取阅读进度 [NovelRepository.getLastReadChapter];关系图页面可通过
  /// 手动滑块覆盖(覆盖值由 UI 层持有,不存于此 provider)。
  ///
  /// Copied from [currentChapter].
  const CurrentChapterFamily();

  /// 当前章节进度(0-based index)。
  ///
  /// 默认取阅读进度 [NovelRepository.getLastReadChapter];关系图页面可通过
  /// 手动滑块覆盖(覆盖值由 UI 层持有,不存于此 provider)。
  ///
  /// Copied from [currentChapter].
  CurrentChapterProvider call(
    String novelUrl,
  ) {
    return CurrentChapterProvider(
      novelUrl,
    );
  }

  @override
  CurrentChapterProvider getProviderOverride(
    covariant CurrentChapterProvider provider,
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
  String? get name => r'currentChapterProvider';
}

/// 当前章节进度(0-based index)。
///
/// 默认取阅读进度 [NovelRepository.getLastReadChapter];关系图页面可通过
/// 手动滑块覆盖(覆盖值由 UI 层持有,不存于此 provider)。
///
/// Copied from [currentChapter].
class CurrentChapterProvider extends AutoDisposeFutureProvider<int> {
  /// 当前章节进度(0-based index)。
  ///
  /// 默认取阅读进度 [NovelRepository.getLastReadChapter];关系图页面可通过
  /// 手动滑块覆盖(覆盖值由 UI 层持有,不存于此 provider)。
  ///
  /// Copied from [currentChapter].
  CurrentChapterProvider(
    String novelUrl,
  ) : this._internal(
          (ref) => currentChapter(
            ref as CurrentChapterRef,
            novelUrl,
          ),
          from: currentChapterProvider,
          name: r'currentChapterProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$currentChapterHash,
          dependencies: CurrentChapterFamily._dependencies,
          allTransitiveDependencies:
              CurrentChapterFamily._allTransitiveDependencies,
          novelUrl: novelUrl,
        );

  CurrentChapterProvider._internal(
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
    FutureOr<int> Function(CurrentChapterRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: CurrentChapterProvider._internal(
        (ref) => create(ref as CurrentChapterRef),
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
  AutoDisposeFutureProviderElement<int> createElement() {
    return _CurrentChapterProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is CurrentChapterProvider && other.novelUrl == novelUrl;
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
mixin CurrentChapterRef on AutoDisposeFutureProviderRef<int> {
  /// The parameter `novelUrl` of this provider.
  String get novelUrl;
}

class _CurrentChapterProviderElement
    extends AutoDisposeFutureProviderElement<int> with CurrentChapterRef {
  _CurrentChapterProviderElement(super.provider);

  @override
  String get novelUrl => (origin as CurrentChapterProvider).novelUrl;
}

String _$relationshipGraphHash() => r'a8dc8cee2c2c93fe9f28680bb14d2398bae8c90e';

/// 关系图快照(按小说 + 章节)。
///
/// 返回该章节下已登场人物 + 生效关系的快照。
///
/// Copied from [relationshipGraph].
@ProviderFor(relationshipGraph)
const relationshipGraphProvider = RelationshipGraphFamily();

/// 关系图快照(按小说 + 章节)。
///
/// 返回该章节下已登场人物 + 生效关系的快照。
///
/// Copied from [relationshipGraph].
class RelationshipGraphFamily
    extends Family<AsyncValue<RelationshipGraphSnapshot>> {
  /// 关系图快照(按小说 + 章节)。
  ///
  /// 返回该章节下已登场人物 + 生效关系的快照。
  ///
  /// Copied from [relationshipGraph].
  const RelationshipGraphFamily();

  /// 关系图快照(按小说 + 章节)。
  ///
  /// 返回该章节下已登场人物 + 生效关系的快照。
  ///
  /// Copied from [relationshipGraph].
  RelationshipGraphProvider call(
    String novelUrl,
    int chapter,
  ) {
    return RelationshipGraphProvider(
      novelUrl,
      chapter,
    );
  }

  @override
  RelationshipGraphProvider getProviderOverride(
    covariant RelationshipGraphProvider provider,
  ) {
    return call(
      provider.novelUrl,
      provider.chapter,
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
  String? get name => r'relationshipGraphProvider';
}

/// 关系图快照(按小说 + 章节)。
///
/// 返回该章节下已登场人物 + 生效关系的快照。
///
/// Copied from [relationshipGraph].
class RelationshipGraphProvider
    extends AutoDisposeFutureProvider<RelationshipGraphSnapshot> {
  /// 关系图快照(按小说 + 章节)。
  ///
  /// 返回该章节下已登场人物 + 生效关系的快照。
  ///
  /// Copied from [relationshipGraph].
  RelationshipGraphProvider(
    String novelUrl,
    int chapter,
  ) : this._internal(
          (ref) => relationshipGraph(
            ref as RelationshipGraphRef,
            novelUrl,
            chapter,
          ),
          from: relationshipGraphProvider,
          name: r'relationshipGraphProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$relationshipGraphHash,
          dependencies: RelationshipGraphFamily._dependencies,
          allTransitiveDependencies:
              RelationshipGraphFamily._allTransitiveDependencies,
          novelUrl: novelUrl,
          chapter: chapter,
        );

  RelationshipGraphProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.novelUrl,
    required this.chapter,
  }) : super.internal();

  final String novelUrl;
  final int chapter;

  @override
  Override overrideWith(
    FutureOr<RelationshipGraphSnapshot> Function(RelationshipGraphRef provider)
        create,
  ) {
    return ProviderOverride(
      origin: this,
      override: RelationshipGraphProvider._internal(
        (ref) => create(ref as RelationshipGraphRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        novelUrl: novelUrl,
        chapter: chapter,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<RelationshipGraphSnapshot> createElement() {
    return _RelationshipGraphProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is RelationshipGraphProvider &&
        other.novelUrl == novelUrl &&
        other.chapter == chapter;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, novelUrl.hashCode);
    hash = _SystemHash.combine(hash, chapter.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin RelationshipGraphRef
    on AutoDisposeFutureProviderRef<RelationshipGraphSnapshot> {
  /// The parameter `novelUrl` of this provider.
  String get novelUrl;

  /// The parameter `chapter` of this provider.
  int get chapter;
}

class _RelationshipGraphProviderElement
    extends AutoDisposeFutureProviderElement<RelationshipGraphSnapshot>
    with RelationshipGraphRef {
  _RelationshipGraphProviderElement(super.provider);

  @override
  String get novelUrl => (origin as RelationshipGraphProvider).novelUrl;
  @override
  int get chapter => (origin as RelationshipGraphProvider).chapter;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
