/// QuotaExhaustedException（HTTP 402 余额耗尽）重试豁免单测
///
/// 覆盖三条判定链，保证 402 在传输层与回合层都不进重试预算：
/// 1. RetryConfig.defaultShouldRetry → false
/// 2. isTransientNetworkError → false（回合层 AgentLoop 用它判重试）
/// 3. withRetry → 抛出时立即 rethrow，fn 只执行 1 次
/// 4. toString 为友好中文文案（agent_loop 直接 emit(e.toString())）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/utils/retry_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('defaultShouldRetry 判定', () {
    test('QuotaExhaustedException → false（不重试）', () {
      expect(
        RetryConfig.defaultShouldRetry(
            const QuotaExhaustedException('body', 'https://x/v1')),
        isFalse,
      );
    });

    test('对照：RetryableHttpException 仍重试', () {
      expect(
        RetryConfig.defaultShouldRetry(
            const RetryableHttpException(402, '', '')),
        isTrue,
        reason: '402 走 QuotaExhaustedException 才豁免；'
            '其他来源的 RetryableHttpException(402) 不受影响',
      );
      expect(
        RetryConfig.defaultShouldRetry(
            const RetryableHttpException(429, '', '')),
        isTrue,
      );
    });
  });

  group('isTransientNetworkError 判定（回合层）', () {
    test('QuotaExhaustedException → false', () {
      expect(
        isTransientNetworkError(
            const QuotaExhaustedException('body', 'https://x/v1')),
        isFalse,
      );
    });

    test('对照：RetryableHttpException → true', () {
      expect(
        isTransientNetworkError(const RetryableHttpException(503, '', '')),
        isTrue,
      );
    });
  });

  group('withRetry 不重试', () {
    test('fn 抛 QuotaExhaustedException → 只执行 1 次并原样 rethrow', () async {
      var calls = 0;
      await expectLater(
        withRetry(
          () async {
            calls++;
            throw const QuotaExhaustedException(
                '{"error":{"code":"insufficient_quota"}}', 'https://x/v1');
          },
          config: const RetryConfig(maxAttempts: 8, initialDelay: Duration(milliseconds: 1)),
          label: 'quota_test',
        ),
        throwsA(isA<QuotaExhaustedException>()),
      );
      expect(calls, 1, reason: '余额耗尽不应消耗重试预算（旧实现会重试 8 次）');
    });
  });

  group('toString 文案契约', () {
    test('为友好中文（AgentErrorEvent 直接渲染 e.toString()）', () {
      const e = QuotaExhaustedException('raw', 'https://x/v1');
      expect(e.toString(), contains('免费额度已用完'));
      expect(e.toString(), isNot(contains('QuotaExhausted')),
          reason: '用户可见文案不应暴露类名');
    });
  });
}
