/// 测试共享：LLM 相关的假实现集合。
///
/// `NoopLlmHttpClient` —— 三个以上测试文件曾经各自定义相同实现（全 throw
/// [UnimplementedError]），用于在已 override 流式方法的 fake provider 里
/// 满足 [LlmProvider] 构造对 [LlmHttpClient] 的非空约束。统一收口于此。
library;

import 'package:novel_app/services/dsl_engine/llm_provider.dart';

/// 占位 HTTP 客户端：fake LLM Provider 已 override 流式/工具方法，
/// 永远不会走到真实 HTTP，这里仅为满足 [LlmProvider] 构造的非空约束。
class NoopLlmHttpClient implements LlmHttpClient {
  @override
  Future<String> postJson(
          String url, Map<String, String> headers, String body) =>
      throw UnimplementedError();

  @override
  Stream<String> postJsonStream(
          String url, Map<String, String> headers, String body) =>
      throw UnimplementedError();
}
