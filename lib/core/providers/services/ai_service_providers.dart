/// AI Service Providers
///
/// 此文件定义所有AI相关服务的 Provider。
///
/// **功能**:
/// - LLM 配置管理
///
/// **依赖**:
/// - database_providers.dart - 数据库服务
/// - network_service_providers.dart - 网络服务
///
/// **相关 Providers**:
/// - [database_service_providers.dart] - 数据库相关 Providers
/// - [network_service_providers.dart] - 网络相关 Providers
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riverpod/riverpod.dart';
import '../../../services/llm_config_service.dart';
import '../database_providers.dart';

part 'ai_service_providers.g.dart';

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
@Riverpod(keepAlive: true)
LlmConfigService llmConfigService(Ref ref) {
  return LlmConfigService(ref);
}
