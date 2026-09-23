// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookshelf_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$bookshelfSiteDomainsHash() =>
    r'c7600fdf87857f9378f7e2377c6ef0eec492ad32';

/// 有藏书的联网来源站点 host 列表
///
/// 供 [bookshelfShelvesProvider] 生成按站点拆分的联网 Tab；
/// 依赖 [onlineNovelsProvider] 使增删小说后 Tab 列表同步刷新。
///
/// Copied from [bookshelfSiteDomains].
@ProviderFor(bookshelfSiteDomains)
final bookshelfSiteDomainsProvider =
    AutoDisposeFutureProvider<List<String>>.internal(
  bookshelfSiteDomains,
  name: r'bookshelfSiteDomainsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$bookshelfSiteDomainsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BookshelfSiteDomainsRef = AutoDisposeFutureProviderRef<List<String>>;
String _$siteDisplayNamesHash() => r'69e0eed8e84e73484594a07e4604ad277ac187dc';

/// 站点显示名映射（`domain -> display_name`）
///
/// 取自 `site_scripts.display_name`（提取 Agent 在 save_script 时从页面
/// 推断登记，如 `www.qidian.com -> 起点中文网`）。与 [onlineNovelsProvider]
/// 同生命周期：提取会话导入小说后随 Tab 列表一起刷新。
///
/// Copied from [siteDisplayNames].
@ProviderFor(siteDisplayNames)
final siteDisplayNamesProvider =
    AutoDisposeFutureProvider<Map<String, String>>.internal(
  siteDisplayNames,
  name: r'siteDisplayNamesProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$siteDisplayNamesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SiteDisplayNamesRef = AutoDisposeFutureProviderRef<Map<String, String>>;
String _$bookshelfShelvesHash() => r'39777011034152a834917155d3aba7da7f74ff96';

/// 书架 Tab 列表
///
/// 全部/原创固定 + 按来源站点拆分的联网书架（见 [Bookshelf.tabShelves]）。
/// 站点 Tab 名优先用 [siteDisplayNamesProvider] 登记的站点名，回退 host。
///
/// Copied from [bookshelfShelves].
@ProviderFor(bookshelfShelves)
final bookshelfShelvesProvider =
    AutoDisposeFutureProvider<List<Bookshelf>>.internal(
  bookshelfShelves,
  name: r'bookshelfShelvesProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$bookshelfShelvesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BookshelfShelvesRef = AutoDisposeFutureProviderRef<List<Bookshelf>>;
String _$onlineNovelsHash() => r'2ca2cf6ac4bd1c076c85c0a98ac122de0b8ba805';

/// 联网小说列表（全部站点聚合）
///
/// 站点 Tab 列表的数据源；增删小说后经 invalidate 刷新。
///
/// Copied from [onlineNovels].
@ProviderFor(onlineNovels)
final onlineNovelsProvider = AutoDisposeFutureProvider<List<Novel>>.internal(
  onlineNovels,
  name: r'onlineNovelsProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$onlineNovelsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef OnlineNovelsRef = AutoDisposeFutureProviderRef<List<Novel>>;
String _$shelfNovelsHash() => r'5bcc58515daa1c73fa8b40d95bcec2534c55804c';

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

/// 指定书架的小说列表（family · keepAlive）
///
/// 卡片式滑动切换需要相邻书架的数据即时可用，故按 [Bookshelf] 分桶缓存并
/// keepAlive（避免离开书架页后再回来被 autoDispose 清掉），保证跟手滑动时
/// 下一张"卡片"已经渲染完成。
///
/// 写路径经 [BookshelfMutationNotifier] invalidate 整个 family 刷新。
///
/// Copied from [shelfNovels].
@ProviderFor(shelfNovels)
const shelfNovelsProvider = ShelfNovelsFamily();

/// 指定书架的小说列表（family · keepAlive）
///
/// 卡片式滑动切换需要相邻书架的数据即时可用，故按 [Bookshelf] 分桶缓存并
/// keepAlive（避免离开书架页后再回来被 autoDispose 清掉），保证跟手滑动时
/// 下一张"卡片"已经渲染完成。
///
/// 写路径经 [BookshelfMutationNotifier] invalidate 整个 family 刷新。
///
/// Copied from [shelfNovels].
class ShelfNovelsFamily extends Family<AsyncValue<List<Novel>>> {
  /// 指定书架的小说列表（family · keepAlive）
  ///
  /// 卡片式滑动切换需要相邻书架的数据即时可用，故按 [Bookshelf] 分桶缓存并
  /// keepAlive（避免离开书架页后再回来被 autoDispose 清掉），保证跟手滑动时
  /// 下一张"卡片"已经渲染完成。
  ///
  /// 写路径经 [BookshelfMutationNotifier] invalidate 整个 family 刷新。
  ///
  /// Copied from [shelfNovels].
  const ShelfNovelsFamily();

  /// 指定书架的小说列表（family · keepAlive）
  ///
  /// 卡片式滑动切换需要相邻书架的数据即时可用，故按 [Bookshelf] 分桶缓存并
  /// keepAlive（避免离开书架页后再回来被 autoDispose 清掉），保证跟手滑动时
  /// 下一张"卡片"已经渲染完成。
  ///
  /// 写路径经 [BookshelfMutationNotifier] invalidate 整个 family 刷新。
  ///
  /// Copied from [shelfNovels].
  ShelfNovelsProvider call(
    Bookshelf shelf,
  ) {
    return ShelfNovelsProvider(
      shelf,
    );
  }

  @override
  ShelfNovelsProvider getProviderOverride(
    covariant ShelfNovelsProvider provider,
  ) {
    return call(
      provider.shelf,
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
  String? get name => r'shelfNovelsProvider';
}

/// 指定书架的小说列表（family · keepAlive）
///
/// 卡片式滑动切换需要相邻书架的数据即时可用，故按 [Bookshelf] 分桶缓存并
/// keepAlive（避免离开书架页后再回来被 autoDispose 清掉），保证跟手滑动时
/// 下一张"卡片"已经渲染完成。
///
/// 写路径经 [BookshelfMutationNotifier] invalidate 整个 family 刷新。
///
/// Copied from [shelfNovels].
class ShelfNovelsProvider extends FutureProvider<List<Novel>> {
  /// 指定书架的小说列表（family · keepAlive）
  ///
  /// 卡片式滑动切换需要相邻书架的数据即时可用，故按 [Bookshelf] 分桶缓存并
  /// keepAlive（避免离开书架页后再回来被 autoDispose 清掉），保证跟手滑动时
  /// 下一张"卡片"已经渲染完成。
  ///
  /// 写路径经 [BookshelfMutationNotifier] invalidate 整个 family 刷新。
  ///
  /// Copied from [shelfNovels].
  ShelfNovelsProvider(
    Bookshelf shelf,
  ) : this._internal(
          (ref) => shelfNovels(
            ref as ShelfNovelsRef,
            shelf,
          ),
          from: shelfNovelsProvider,
          name: r'shelfNovelsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$shelfNovelsHash,
          dependencies: ShelfNovelsFamily._dependencies,
          allTransitiveDependencies:
              ShelfNovelsFamily._allTransitiveDependencies,
          shelf: shelf,
        );

  ShelfNovelsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.shelf,
  }) : super.internal();

  final Bookshelf shelf;

  @override
  Override overrideWith(
    FutureOr<List<Novel>> Function(ShelfNovelsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ShelfNovelsProvider._internal(
        (ref) => create(ref as ShelfNovelsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        shelf: shelf,
      ),
    );
  }

  @override
  FutureProviderElement<List<Novel>> createElement() {
    return _ShelfNovelsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ShelfNovelsProvider && other.shelf == shelf;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, shelf.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ShelfNovelsRef on FutureProviderRef<List<Novel>> {
  /// The parameter `shelf` of this provider.
  Bookshelf get shelf;
}

class _ShelfNovelsProviderElement extends FutureProviderElement<List<Novel>>
    with ShelfNovelsRef {
  _ShelfNovelsProviderElement(super.provider);

  @override
  Bookshelf get shelf => (origin as ShelfNovelsProvider).shelf;
}

String _$shelfCacheStatsHash() => r'e1aa5a7dd78c76b34fff4a2ab34d86cfbdb009aa';

/// 指定书架的缓存统计（family · keepAlive）
///
/// 缓存统计依赖同书架的小说列表；同 [shelfNovelsProvider] 一起 keepAlive，
/// 保证滑动切换时元信息条 / 章节进度条数据不抖。
///
/// Copied from [shelfCacheStats].
@ProviderFor(shelfCacheStats)
const shelfCacheStatsProvider = ShelfCacheStatsFamily();

/// 指定书架的缓存统计（family · keepAlive）
///
/// 缓存统计依赖同书架的小说列表；同 [shelfNovelsProvider] 一起 keepAlive，
/// 保证滑动切换时元信息条 / 章节进度条数据不抖。
///
/// Copied from [shelfCacheStats].
class ShelfCacheStatsFamily
    extends Family<AsyncValue<Map<String, CacheStats>>> {
  /// 指定书架的缓存统计（family · keepAlive）
  ///
  /// 缓存统计依赖同书架的小说列表；同 [shelfNovelsProvider] 一起 keepAlive，
  /// 保证滑动切换时元信息条 / 章节进度条数据不抖。
  ///
  /// Copied from [shelfCacheStats].
  const ShelfCacheStatsFamily();

  /// 指定书架的缓存统计（family · keepAlive）
  ///
  /// 缓存统计依赖同书架的小说列表；同 [shelfNovelsProvider] 一起 keepAlive，
  /// 保证滑动切换时元信息条 / 章节进度条数据不抖。
  ///
  /// Copied from [shelfCacheStats].
  ShelfCacheStatsProvider call(
    Bookshelf shelf,
  ) {
    return ShelfCacheStatsProvider(
      shelf,
    );
  }

  @override
  ShelfCacheStatsProvider getProviderOverride(
    covariant ShelfCacheStatsProvider provider,
  ) {
    return call(
      provider.shelf,
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
  String? get name => r'shelfCacheStatsProvider';
}

/// 指定书架的缓存统计（family · keepAlive）
///
/// 缓存统计依赖同书架的小说列表；同 [shelfNovelsProvider] 一起 keepAlive，
/// 保证滑动切换时元信息条 / 章节进度条数据不抖。
///
/// Copied from [shelfCacheStats].
class ShelfCacheStatsProvider extends FutureProvider<Map<String, CacheStats>> {
  /// 指定书架的缓存统计（family · keepAlive）
  ///
  /// 缓存统计依赖同书架的小说列表；同 [shelfNovelsProvider] 一起 keepAlive，
  /// 保证滑动切换时元信息条 / 章节进度条数据不抖。
  ///
  /// Copied from [shelfCacheStats].
  ShelfCacheStatsProvider(
    Bookshelf shelf,
  ) : this._internal(
          (ref) => shelfCacheStats(
            ref as ShelfCacheStatsRef,
            shelf,
          ),
          from: shelfCacheStatsProvider,
          name: r'shelfCacheStatsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$shelfCacheStatsHash,
          dependencies: ShelfCacheStatsFamily._dependencies,
          allTransitiveDependencies:
              ShelfCacheStatsFamily._allTransitiveDependencies,
          shelf: shelf,
        );

  ShelfCacheStatsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.shelf,
  }) : super.internal();

  final Bookshelf shelf;

  @override
  Override overrideWith(
    FutureOr<Map<String, CacheStats>> Function(ShelfCacheStatsRef provider)
        create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ShelfCacheStatsProvider._internal(
        (ref) => create(ref as ShelfCacheStatsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        shelf: shelf,
      ),
    );
  }

  @override
  FutureProviderElement<Map<String, CacheStats>> createElement() {
    return _ShelfCacheStatsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ShelfCacheStatsProvider && other.shelf == shelf;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, shelf.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ShelfCacheStatsRef on FutureProviderRef<Map<String, CacheStats>> {
  /// The parameter `shelf` of this provider.
  Bookshelf get shelf;
}

class _ShelfCacheStatsProviderElement
    extends FutureProviderElement<Map<String, CacheStats>>
    with ShelfCacheStatsRef {
  _ShelfCacheStatsProviderElement(super.provider);

  @override
  Bookshelf get shelf => (origin as ShelfCacheStatsProvider).shelf;
}

String _$bookshelfNovelsHash() => r'a409b032650c087d6e5ebca4d9c3b45a83aba7f0';

/// 书架小说列表（当前书架的快捷视图 · 兼容层）
///
/// 委托到 [shelfNovelsProvider(currentBookshelf)]。保留此 provider 以维持
/// 旧 API / 既有注释契约；写路径 invalidate 仅作触发信号，真正数据刷新
/// 由 family 的 invalidate 完成（见 [BookshelfMutationNotifier._wrap]）。
///
/// Copied from [bookshelfNovels].
@ProviderFor(bookshelfNovels)
final bookshelfNovelsProvider = AutoDisposeFutureProvider<List<Novel>>.internal(
  bookshelfNovels,
  name: r'bookshelfNovelsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$bookshelfNovelsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BookshelfNovelsRef = AutoDisposeFutureProviderRef<List<Novel>>;
String _$bookshelfCacheStatsHash() =>
    r'70f473de725a38cca5d28728c333ac2cd1c80650';

/// 书架小说列表缓存统计（当前书架的快捷视图 · 兼容层）
///
/// 委托到 [shelfCacheStatsProvider(currentBookshelf)]。
///
/// Copied from [bookshelfCacheStats].
@ProviderFor(bookshelfCacheStats)
final bookshelfCacheStatsProvider =
    AutoDisposeFutureProvider<Map<String, CacheStats>>.internal(
  bookshelfCacheStats,
  name: r'bookshelfCacheStatsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$bookshelfCacheStatsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BookshelfCacheStatsRef
    = AutoDisposeFutureProviderRef<Map<String, CacheStats>>;
String _$currentBookshelfHash() => r'4304bf70eec03c7f3f0bd0856c06bbcfb7d2677b';

/// 当前选中的书架
///
/// 书架由"小说来源"派生，用户不可调整：全部/原创固定 +
/// 联网按来源网站（URL host）拆分。支持持久化保存用户选择，
/// 重启 app 后恢复上次打开的书架：
/// - 新键 `current_bookshelf_kind` 存 [Bookshelf.toPersistedValue]
///   （`all` / `original` / `online:<host>`）
/// - 旧键 `current_bookshelf_id`（int）存在时经 [Bookshelf.fromLegacyId] 兜底映射
///
/// Copied from [CurrentBookshelf].
@ProviderFor(CurrentBookshelf)
final currentBookshelfProvider =
    AutoDisposeNotifierProvider<CurrentBookshelf, Bookshelf>.internal(
  CurrentBookshelf.new,
  name: r'currentBookshelfProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$currentBookshelfHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$CurrentBookshelf = AutoDisposeNotifier<Bookshelf>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
