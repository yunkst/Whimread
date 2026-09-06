// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reader_edit_mode_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$readerEditModeHash() => r'9addba654b60808c1b63923a3796a9edf56ebab0';

/// 阅读器编辑模式状态管理Provider
///
/// 用于管理阅读器的编辑模式状态，支持段落编辑、改写等功能
///
/// Copied from [ReaderEditMode].
@ProviderFor(ReaderEditMode)
final readerEditModeProvider =
    AutoDisposeNotifierProvider<ReaderEditMode, bool>.internal(
  ReaderEditMode.new,
  name: r'readerEditModeProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$readerEditModeHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ReaderEditMode = AutoDisposeNotifier<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
