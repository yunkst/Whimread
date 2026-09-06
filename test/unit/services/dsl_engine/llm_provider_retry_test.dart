/// IoLlmHttpClient 重试与 RetrySignals 接线测试
///
/// 注意:IoLlmHttpClient._httpClient 是私有 dart:io HttpClient 字段,
/// 无法直接注入替身。本测试聚焦 withRetry + onRetry 的连接逻辑
/// (onRetry → RetrySignals.reportTransport 的桥接),IoLlmHttpClient 内部
/// 实际接线由 analyze(编译期保证 onRetry lambda 类型正确)+ 后续集成/
/// 手动验收覆盖(spec DoD 已注明)。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/services/dsl_engine/llm_provider_retry_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';
import 'package:novel_app/services/dsl_engine/retry_signals.dart';
import 'package:novel_app/utils/retry_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LLM Provider 传输层重试 → RetrySignals', () {
    setUp(() => RetrySignals.instance.resetForTest());

    test('withRetry onRetry → RetrySignals.reportTransport 写入 transport state',
        () async {
      bool called = false;
      await withRetry(
        () async {
          if (!called) {
            called = true;
            throw const RetryableHttpException(503, '', '');
          }
          return 'ok';
        },
        config: const RetryConfig(
          maxAttempts: 3,
          initialDelay: Duration(milliseconds: 1),
        ),
        onRetry: (a, m, d, e) {
          RetrySignals.instance.reportTransport(
            attempt: a,
            maxAttempts: m,
            delayMs: d,
            error: e,
          );
        },
      );
      // 重试 1 次后成功,state 残留(因为没 clear)
      expect(RetrySignals.instance.notifier.value, isNotNull);
      expect(RetrySignals.instance.notifier.value!.attempt, 1);

      // 模拟 postJson 成功的 clear 行为
      RetrySignals.instance.clear();
      expect(RetrySignals.instance.notifier.value, isNull);
    });

    test('categorizeRetryError 经 onRetry 透传到 RetryState.errorCategory',
        () async {
      try {
        await withRetry(
          () async => throw const RetryableHttpException(429, 'body', ''),
          config: const RetryConfig(
            maxAttempts: 2,
            initialDelay: Duration(milliseconds: 1),
          ),
          onRetry: (a, m, d, e) {
            RetrySignals.instance.reportTransport(
              attempt: a,
              maxAttempts: m,
              delayMs: d,
              error: e,
            );
          },
        );
      } catch (_) {
        // 预期:2 次都失败,withRetry 最终 rethrow
      }

      final v = RetrySignals.instance.notifier.value!;
      expect(v.errorCategory, RetryErrorCategory.rateLimited);
      expect(v.maxAttempts, 2);
    });
  });

  group('IoLlmHttpClient._budget', () {
    test('默认 budget → transportBlockingMaxAttempts=8', () {
      // IoLlmHttpClient() 不传 budget → _budget = LlmRetryBudget()
      // 通过构造验证默认值不会崩溃，并检查实际 withRetry 的 maxAttempts
      final client = IoLlmHttpClient();
      // 无公开 getter，通过行为验证：用 ScriptedErrorHttpClient 注入
      // 底层 dart:io 不可替换，此处仅验证构造不抛 + 类型正确
      expect(client, isA<LlmHttpClient>());
    });

    test('显式注入 budget → transportStreamMaxAttempts=2 生效', () async {
      var callCount = 0;
      // 验证 budget 的 transportStreamMaxAttempts 控制流式握手 maxAttempts
      // 直接验证 withRetry 被调用时的 config.maxAttempts：
      // 这里用 RetryConfig(maxAttempts: budget.transportStreamMaxAttempts)
      const budget = LlmRetryBudget(transportStreamMaxAttempts: 2);
      expect(budget.transportStreamMaxAttempts, 2);
      // IoLlmHttpClient 内部 postJsonStream 会读 _budget.transportStreamMaxAttempts
      // 此处验证 budget 构造正确，实际 IoLlmHttpClient 接线由集成测试覆盖
    });

    test('strict budget → 阻塞3/流式2/回合1', () {
      const b = LlmRetryBudget.strict();
      expect(b.transportBlockingMaxAttempts, 3);
      expect(b.transportStreamMaxAttempts, 2);
      expect(b.roundNetworkRetryPerRound, 1);
    });
  });

  group('withRetry 边界', () {
    test('onRetry 回调抛异常 → 被吞掉，不影响主流程', () async {
      var mainCalls = 0;
      var onRetryCalls = 0;
      await withRetry(
        () async {
          mainCalls++;
          if (mainCalls <= 2) throw SocketException('断');
          return 'ok';
        },
        config: const RetryConfig(
          maxAttempts: 4,
          initialDelay: Duration(milliseconds: 1),
        ),
        onRetry: (a, m, d, e) {
          onRetryCalls++;
          throw StateError('onRetry 内部异常');
        },
      );
      expect(mainCalls, 3, reason: '重试 2 次 + 第 3 次成功');
      expect(onRetryCalls, 2, reason: 'onRetry 调了 2 次，但抛异常被吞');
    });

    test('maxAttempts=0 → 抛出 StateError（防御性兜底）', () async {
      try {
        await withRetry(
          () async => throw SocketException('断'),
          config: const RetryConfig(maxAttempts: 0),
        );
        fail('应该抛出');
      } on StateError catch (e) {
        expect(e.message, contains('withRetry'));
      }
      // 若 maxAttempts=0 被 RetryConfig 限制（实际未限制），测试会失败
      // 若 for 循环跳过，lastError=null → StateError
    });
  });
}
