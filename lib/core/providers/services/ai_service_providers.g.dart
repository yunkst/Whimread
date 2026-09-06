// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_service_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$llmConfigServiceHash() => r'0c3a3e6b43fe97db8dec09a97d5f304ea84055aa';

/// LlmConfigService Provider
///
/// 提供全局 LLM 配置服务实例，用于统一管理 LLM 配置序列。
///
/// **功能**:
/// - 获取/设置激活配置（全局 + 场景级）
/// - CRUD 配置
/// - 旧配置迁移
/// - 构建 LlmProvider 配置
///
/// **依赖**:
/// - [llmConfigRepositoryProvider] - LLM 配置数据访问
///
/// Copied from [llmConfigService].
@ProviderFor(llmConfigService)
final llmConfigServiceProvider = Provider<LlmConfigService>.internal(
  llmConfigService,
  name: r'llmConfigServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$llmConfigServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef LlmConfigServiceRef = ProviderRef<LlmConfigService>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
