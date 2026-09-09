/// IoLlmHttpClient HTTP 错误映射契约单测（402 → QuotaExhaustedException）
///
/// `throwForHttpFailure` 是传输层「状态码 → 异常」的单一真理源
/// （`_handleHttpFailure` 阻塞/流式握手两条路径都经由它抛出）。
///
/// 不用本地 HttpServer 做端到端：dart:io 响应对象不可构造，且 Windows 下
/// flutter test 进程的入站监听会被防火墙静默吞连接（连接挂到
/// connectionTimeout 15s × 重试 8 次 ≫ 30s 测试超时），故把映射契约抽出
/// 直测；「withRetry 不重试 QuotaExhaustedException」的集成行为由
/// `test/unit/utils/retry_helper_quota_test.dart` 覆盖。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/dsl_engine/llm_provider_client.dart';
import 'package:novel_app/utils/retry_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('throwForHttpFailure 状态码 → 异常映射契约', () {
    test('402 → QuotaExhaustedException（携带 body 与 url）', () {
      expect(
        () => IoLlmHttpClient.throwForHttpFailure(
          statusCode: 402,
          responseBody:
              '{"error":{"code":"insufficient_quota","message":"免费额度已用完"}}',
          url: 'https://backend.example.com/v1/chat/completions',
        ),
        throwsA(isA<QuotaExhaustedException>()
            .having((e) => e.body, 'body', contains('insufficient_quota'))
            .having((e) => e.url, 'url', contains('chat/completions'))
            .having((e) => e.toString(), 'toString', contains('免费额度已用完'))),
      );
    });

    test('503 → 仍为 RetryableHttpException（保持瞬态重试语义）', () {
      expect(
        () => IoLlmHttpClient.throwForHttpFailure(
          statusCode: 503, responseBody: 'upstream down', url: 'https://x/v1',
        ),
        throwsA(isA<RetryableHttpException>()
            .having((e) => e.statusCode, 'statusCode', 503)),
      );
    });

    test('429 → RetryableHttpException 且携带 retryAfterMs', () {
      expect(
        () => IoLlmHttpClient.throwForHttpFailure(
          statusCode: 429,
          responseBody: '',
          url: 'https://x/v1',
          retryAfterMs: 120000,
        ),
        throwsA(isA<RetryableHttpException>()
            .having((e) => e.retryAfterMs, 'retryAfterMs', 120000)),
      );
    });

    test('403/401 等其他 4xx → RetryableHttpException（不受 402 豁免影响）', () {
      for (final code in [400, 401, 403, 404, 408, 422]) {
        expect(
          () => IoLlmHttpClient.throwForHttpFailure(
            statusCode: code, responseBody: '', url: 'https://x/v1',
          ),
          throwsA(isA<RetryableHttpException>()
              .having((e) => e.statusCode, 'statusCode', code)),
          reason: 'HTTP $code 应保持可重试',
        );
      }
    });
  });
}
