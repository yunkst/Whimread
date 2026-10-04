// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_service_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$llmConfigServiceHash() => r'0c3a3e6b43fe97db8dec09a97d5f304ea84055aa';

/// LlmConfigService Provider
///
/// 提供全局 LLM Provider 构建服务实例（所有 AI 调用路径的统一入口）。
///
/// **功能**:
/// - 构建托管后端 LlmProvider（设备 JWT 鉴权 + 用户选择的模型）
/// - 一次性擦除自配 LLM 模式的遗留数据
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
