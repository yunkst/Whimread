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
String _$bookshelfShelvesHash() => r'81eb2def171be8319e7a01ba0e062226825dd0ce';

/// 书架 Tab 列表
///
/// 全部/原创固定 + 按来源站点拆分的联网书架（见 [Bookshelf.tabShelves]）。
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
String _$bookshelfNovelsHash() => r'acf75189da61f53278348c502128995403c39310';

/// 书架小说列表
///
/// 根据当前书架异步加载小说列表（分类由 URL 派生；站点书架按 host 过滤）
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
    r'1cea465bf551de9d4de4e2863c2e85556ce25400';

/// 书架小说列表缓存统计
///
/// 刷新时从数据库查询已缓存章节数和总章节数
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
