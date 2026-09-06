// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$databaseConnectionHash() =>
    r'c922b4150f1a08804551e45890e9408beaeffbe6';

/// 数据库连接Provider
///
/// 提供全局单例 DatabaseConnection 实例
/// 使用 keepAlive: true 确保数据库连接不会因为没有监听者而被销毁
///
/// Copied from [databaseConnection].
@ProviderFor(databaseConnection)
final databaseConnectionProvider = Provider<DatabaseConnection>.internal(
  databaseConnection,
  name: r'databaseConnectionProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$databaseConnectionHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DatabaseConnectionRef = ProviderRef<DatabaseConnection>;
String _$novelRepositoryHash() => r'db78c68a09195a23080e8da3fa820491d1b1227d';

/// NovelRepository Provider
///
/// 使用IDatabaseConnection接口注入，支持测试和依赖替换
///
/// Copied from [novelRepository].
@ProviderFor(novelRepository)
final novelRepositoryProvider = AutoDisposeProvider<INovelRepository>.internal(
  novelRepository,
  name: r'novelRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$novelRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NovelRepositoryRef = AutoDisposeProviderRef<INovelRepository>;
String _$bookshelfWriterHash() => r'd835af567ddd692990eb138d82b46aa9b27841ae';

/// 书架写操作 Provider（仅 [BookshelfMutationNotifier] 用）。
///
/// 通过 cast 拿到 [NovelRepository] 的 IBookshelfWriter 能力。
/// 普通调用方应使用 [bookshelfMutationProvider] 走收口路径。
///
/// Copied from [bookshelfWriter].
@ProviderFor(bookshelfWriter)
final bookshelfWriterProvider = AutoDisposeProvider<IBookshelfWriter>.internal(
  bookshelfWriter,
  name: r'bookshelfWriterProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$bookshelfWriterHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BookshelfWriterRef = AutoDisposeProviderRef<IBookshelfWriter>;
String _$chapterRepositoryHash() => r'8c82f427c1be5f67323bf3e5b5e79a1bf3860b8d';

/// ChapterRepository Provider
///
/// 使用IDatabaseConnection接口注入，支持测试和依赖替换
/// 依赖 ChapterVersionRepository 实现自动版本保存
///
/// Copied from [chapterRepository].
@ProviderFor(chapterRepository)
final chapterRepositoryProvider =
    AutoDisposeProvider<IChapterRepository>.internal(
  chapterRepository,
  name: r'chapterRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$chapterRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ChapterRepositoryRef = AutoDisposeProviderRef<IChapterRepository>;
String _$chapterWriterHash() => r'ee446e537a0a387f3e4ce2812f6a59bdd581ee9c';

/// 章节写操作 Provider（仅 [ChapterMutationNotifier] 用）。
///
/// 通过 cast 拿到 [ChapterRepository] 的 [IChapterWriter] 能力（含 12 个原写方法
/// + 2 个事务方法 `createCustomChapterWithShift` / `deleteChapterAndReindex`）。
/// 普通调用方应使用 `chapterMutationProvider` 走收口路径——通过
/// `IChapterRepository` 类型拿不到写能力，编译期阻止绕过 Notifier 直接写库
/// （正是「agent 写完章节列表不刷新」bug 的根因）。
///
/// Copied from [chapterWriter].
@ProviderFor(chapterWriter)
final chapterWriterProvider = AutoDisposeProvider<IChapterWriter>.internal(
  chapterWriter,
  name: r'chapterWriterProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$chapterWriterHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ChapterWriterRef = AutoDisposeProviderRef<IChapterWriter>;
String _$chapterVersionRepositoryHash() =>
    r'0f200a89492b11e16cebb073e68273bf82039277';

/// ChapterVersionRepository Provider
///
/// 章节历史版本的持久化操作
///
/// Copied from [chapterVersionRepository].
@ProviderFor(chapterVersionRepository)
final chapterVersionRepositoryProvider =
    AutoDisposeProvider<IChapterVersionRepository>.internal(
  chapterVersionRepository,
  name: r'chapterVersionRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$chapterVersionRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ChapterVersionRepositoryRef
    = AutoDisposeProviderRef<IChapterVersionRepository>;
String _$characterRepositoryHash() =>
    r'88d938991a24b892168a768899b6196a7546688f';

/// CharacterRepository Provider
///
/// 使用IDatabaseConnection接口注入，支持测试和依赖替换
///
/// Copied from [characterRepository].
@ProviderFor(characterRepository)
final characterRepositoryProvider =
    AutoDisposeProvider<ICharacterRepository>.internal(
  characterRepository,
  name: r'characterRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$characterRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CharacterRepositoryRef = AutoDisposeProviderRef<ICharacterRepository>;
String _$characterRelationRepositoryHash() =>
    r'b74e9e2a4ae22543b30a1190bf11748c662c8370';

/// CharacterRelationRepository Provider
///
/// 使用IDatabaseConnection接口注入，支持测试和依赖替换
///
/// Copied from [characterRelationRepository].
@ProviderFor(characterRelationRepository)
final characterRelationRepositoryProvider =
    AutoDisposeProvider<ICharacterRelationRepository>.internal(
  characterRelationRepository,
  name: r'characterRelationRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$characterRelationRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CharacterRelationRepositoryRef
    = AutoDisposeProviderRef<ICharacterRelationRepository>;
String _$outlineRepositoryHash() => r'2729584c4249fb2abd7fc024f86002df82fa90a5';

/// OutlineRepository Provider
///
/// 使用IDatabaseConnection接口注入，支持测试和依赖替换
///
/// Copied from [outlineRepository].
@ProviderFor(outlineRepository)
final outlineRepositoryProvider =
    AutoDisposeProvider<IOutlineRepository>.internal(
  outlineRepository,
  name: r'outlineRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$outlineRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef OutlineRepositoryRef = AutoDisposeProviderRef<IOutlineRepository>;
String _$promptTagCategoryRepositoryHash() =>
    r'cbc4e912675859cba31c3ec93dc79163a8597b48';

/// PromptTagCategoryRepository Provider
///
/// Copied from [promptTagCategoryRepository].
@ProviderFor(promptTagCategoryRepository)
final promptTagCategoryRepositoryProvider =
    AutoDisposeProvider<IPromptTagCategoryRepository>.internal(
  promptTagCategoryRepository,
  name: r'promptTagCategoryRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$promptTagCategoryRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PromptTagCategoryRepositoryRef
    = AutoDisposeProviderRef<IPromptTagCategoryRepository>;
String _$promptTagRepositoryHash() =>
    r'b0ce6dabefb5203954d02130bfb6a73bcf47e687';

/// PromptTagRepository Provider
///
/// Copied from [promptTagRepository].
@ProviderFor(promptTagRepository)
final promptTagRepositoryProvider =
    AutoDisposeProvider<IPromptTagRepository>.internal(
  promptTagRepository,
  name: r'promptTagRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$promptTagRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PromptTagRepositoryRef = AutoDisposeProviderRef<IPromptTagRepository>;
String _$bookshelfRepositoryHash() =>
    r'9f12c5aa18a12c4d48303b9f926256e73f2b1d7b';

/// BookshelfRepository Provider
///
/// 使用IDatabaseConnection接口注入，支持测试和依赖替换
///
/// Copied from [bookshelfRepository].
@ProviderFor(bookshelfRepository)
final bookshelfRepositoryProvider =
    AutoDisposeProvider<IBookshelfRepository>.internal(
  bookshelfRepository,
  name: r'bookshelfRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$bookshelfRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BookshelfRepositoryRef = AutoDisposeProviderRef<IBookshelfRepository>;
String _$bookshelfAssociationWriterHash() =>
    r'09345db27ed53474c8e208719c8ef82a530bd5dc';

/// 书架关联表写操作 Provider（仅 [BookshelfMutationNotifier] 用）。
///
/// Copied from [bookshelfAssociationWriter].
@ProviderFor(bookshelfAssociationWriter)
final bookshelfAssociationWriterProvider =
    AutoDisposeProvider<IBookshelfAssociationWriter>.internal(
  bookshelfAssociationWriter,
  name: r'bookshelfAssociationWriterProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$bookshelfAssociationWriterHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BookshelfAssociationWriterRef
    = AutoDisposeProviderRef<IBookshelfAssociationWriter>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
