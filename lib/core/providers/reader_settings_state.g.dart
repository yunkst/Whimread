// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reader_settings_state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$readerSettingsStateNotifierHash() =>
    r'f2fff0a20cc43ec234fae22500b5273f29586671';

/// ReaderSettingsStateNotifier Provider
///
/// 管理阅读器设置状态，自动持久化到 SharedPreferences
///
/// Copied from [ReaderSettingsStateNotifier].
@ProviderFor(ReaderSettingsStateNotifier)
final readerSettingsStateNotifierProvider = AutoDisposeAsyncNotifierProvider<
    ReaderSettingsStateNotifier, ReaderSettingsState>.internal(
  ReaderSettingsStateNotifier.new,
  name: r'readerSettingsStateNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$readerSettingsStateNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ReaderSettingsStateNotifier
    = AutoDisposeAsyncNotifier<ReaderSettingsState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
