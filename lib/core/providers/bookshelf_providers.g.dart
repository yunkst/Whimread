// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookshelf_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$bookshelfNovelsHash() => r'a396a77f5a51312a193460a0a4f965239970fd31';

/// 书架小说列表
///
/// 根据当前书架分类异步加载小说列表（分类由 URL 前缀派生）
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
String _$currentBookshelfKindHash() =>
    r'b7f2093e35e972bab9144637e6fbd2fa7a984342';

/// 当前选中的书架分类
///
/// 三档系统分类（全部/原创/联网），由"小说来源"派生，用户不可调整。
/// 支持持久化保存用户选择，重启 app 后恢复上次打开的书架：
/// - 新键 `current_bookshelf_kind` 存 [BookshelfKind.name]
/// - 旧键 `current_bookshelf_id`（int）存在时经 [Bookshelf.fromLegacyId] 兜底映射
///
/// Copied from [CurrentBookshelfKind].
@ProviderFor(CurrentBookshelfKind)
final currentBookshelfKindProvider =
    AutoDisposeNotifierProvider<CurrentBookshelfKind, BookshelfKind>.internal(
  CurrentBookshelfKind.new,
  name: r'currentBookshelfKindProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$currentBookshelfKindHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$CurrentBookshelfKind = AutoDisposeNotifier<BookshelfKind>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
