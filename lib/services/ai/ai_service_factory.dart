/// AI Service 工厂
///
/// 统一 LlmProvider 的构造方式，供 NovelAgentService 共用。
library;

import '../dsl_engine/llm_provider.dart';

class AiServiceFactory {
  AiServiceFactory._();

  /// 从 LlmConfig（llm_provider 层）构建 LlmProvider
  ///
  /// 统一 LlmProvider 的构造方式，供 NovelAgentService 共用。
  static LlmProvider buildLlmProvider(LlmConfig llmConfig) {
    return LlmProvider(llmConfig, httpClient: IoLlmHttpClient());
  }
}
