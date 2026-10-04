/// AI Service Providers
///
/// 此文件定义所有AI相关服务的 Provider。
///
/// **功能**:
/// - LLM 通道（托管后端）构建
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riverpod/riverpod.dart';
import '../../../services/llm_config_service.dart';

part 'ai_service_providers.g.dart';

/// LlmConfigService Provider
///
/// 提供全局 LLM Provider 构建服务实例（所有 AI 调用路径的统一入口）。
///
/// **功能**:
/// - 构建托管后端 LlmProvider（设备 JWT 鉴权 + 用户选择的模型）
/// - 一次性擦除自配 LLM 模式的遗留数据
@Riverpod(keepAlive: true)
LlmConfigService llmConfigService(Ref ref) {
  return LlmConfigService(ref);
}
