// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookshelf_mutation_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$bookshelfMutationHash() => r'24eb4e1746627f83c9e26ef6522f707f211b8188';

/// 书架写操作聚合 Notifier（无状态）。
///
/// 8 个公共方法：addNovel / removeNovel / toggleBookshelf /
/// updateTitle / updateCoverMediaId / removeCoverMediaId /
/// backfillCoverUrl / updateReadProgress / createNovel。
///
/// Copied from [BookshelfMutation].
@ProviderFor(BookshelfMutation)
final bookshelfMutationProvider =
    AutoDisposeNotifierProvider<BookshelfMutation, void>.internal(
  BookshelfMutation.new,
  name: r'bookshelfMutationProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$bookshelfMutationHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$BookshelfMutation = AutoDisposeNotifier<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
