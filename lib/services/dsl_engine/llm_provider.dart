/// LLM Provider barrel — 保持向后兼容。
///
/// 原 llm_provider.dart 已拆分为四个子文件：
/// - llm_provider_config.dart — 配置与消息模型
/// - llm_provider_sse.dart  — SSE 流式解析器
/// - llm_provider_core.dart  — API 门面（LlmProvider + LlmHttpClient）
/// - llm_provider_client.dart — dart:io HTTP 传输实现
///
/// 本 barrel 透明导出所有 public 符号，25 个调用方 0 改动。
library;

export 'llm_provider_config.dart';
export 'llm_provider_sse.dart';
export 'llm_provider_core.dart';
export 'llm_provider_client.dart';