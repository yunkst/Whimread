// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chapter_search_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$chaptersListHash() => r'a6007807d7ad550dd1406dfb681fa28fbb5bb727';

/// Chapters List Provider
///
/// 提供小说的章节列表
///
/// Copied from [chaptersList].
@ProviderFor(chaptersList)
final chaptersListProvider = AutoDisposeFutureProvider<List<Chapter>>.internal(
  chaptersList,
  name: r'chaptersListProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$chaptersListHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ChaptersListRef = AutoDisposeFutureProviderRef<List<Chapter>>;
String _$searchResultsHash() => r'00dcc21f4e08805756bdd135648ad24cea111908';

/// Search Results Provider
///
/// 提供章节搜索结果
///
/// Copied from [searchResults].
@ProviderFor(searchResults)
final searchResultsProvider =
    AutoDisposeFutureProvider<List<ChapterSearchResult>>.internal(
  searchResults,
  name: r'searchResultsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$searchResultsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SearchResultsRef
    = AutoDisposeFutureProviderRef<List<ChapterSearchResult>>;
String _$novelParamHash() => r'91e6ac33d7c09bfdfe8bd2df0ddba78552a327fd';

/// Novel Parameter Provider
///
/// 提供 ChapterSearchScreen 所需的 Novel 参数
///
/// Copied from [NovelParam].
@ProviderFor(NovelParam)
final novelParamProvider =
    AutoDisposeNotifierProvider<NovelParam, Novel?>.internal(
  NovelParam.new,
  name: r'novelParamProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$novelParamHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$NovelParam = AutoDisposeNotifier<Novel?>;
String _$searchQueryHash() => r'd7f9cdadacbc5a7476d73c2b264810dfc54452f7';

/// Search Query Provider
///
/// 管理搜索查询字符串
///
/// Copied from [SearchQuery].
@ProviderFor(SearchQuery)
final searchQueryProvider =
    AutoDisposeNotifierProvider<SearchQuery, String>.internal(
  SearchQuery.new,
  name: r'searchQueryProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$searchQueryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$SearchQuery = AutoDisposeNotifier<String>;
String _$searchStateHash() => r'50ddaaf60cbeef7c1bbbb1bfef1fb4c5320baa3d';

/// Search State Provider
///
/// 管理搜索状态（是否已搜索、是否正在加载）
///
/// Copied from [SearchState].
@ProviderFor(SearchState)
final searchStateProvider =
    AutoDisposeNotifierProvider<SearchState, SearchStateData>.internal(
  SearchState.new,
  name: r'searchStateProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$searchStateHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$SearchState = AutoDisposeNotifier<SearchStateData>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
