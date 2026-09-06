// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookshelf_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$bookshelfNovelsHash() => r'd4006a1ed2ae5573901a27423c067cddb1a3dedb';

/// 书架小说列表
///
/// 根据当前书架ID异步加载小说列表
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
String _$currentBookshelfIdHash() =>
    r'bb284e432c14f971582d32838b8eb1e617bac264';

/// 当前选中的书架ID
///
/// 默认值为 1（"全部小说"书架）
/// 支持持久化保存用户选择，重启app后恢复上次打开的书架
///
/// Copied from [CurrentBookshelfId].
@ProviderFor(CurrentBookshelfId)
final currentBookshelfIdProvider =
    AutoDisposeNotifierProvider<CurrentBookshelfId, int>.internal(
  CurrentBookshelfId.new,
  name: r'currentBookshelfIdProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$currentBookshelfIdHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$CurrentBookshelfId = AutoDisposeNotifier<int>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
