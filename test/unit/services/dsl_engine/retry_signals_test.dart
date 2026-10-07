/// RetrySignals + categorizeRetryError 单元测试
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/services/dsl_engine/retry_signals_test.dart
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/dsl_engine/retry_signals.dart';
import 'package:novel_app/utils/retry_helper.dart';

void main() {
  setUp(() => RetrySignals.instance.resetForTest());

  group('RetrySignals', () {
    test('reportTransport → notifier.value 写入 transport state', () async {
      final notified = <RetryState?>[];
      RetrySignals.instance.notifier.addListener(() {
        notified.add(RetrySignals.instance.notifier.value);
      });

      RetrySignals.instance.reportTransport(
        attempt: 3,
        maxAttempts: 8,
        delayMs: 2000,
        error: const RetryableHttpException(429, '', ''),
      );

      final state = RetrySignals.instance.notifier.value!;
      expect(state.level, RetryLevel.transport);
      expect(state.attempt, 3);
      expect(state.maxAttempts, 8);
      expect(state.delayMs, 2000);
      expect(state.errorCategory, RetryErrorCategory.rateLimited);
      expect(state.httpStatusCode, 429);
      expect(notified, hasLength(1));
      expect(notified.last, state);
    });

    test('reportRound → notifier.value 写入 round state', () {
      RetrySignals.instance.reportRound(
        attempt: 1,
        maxAttempts: 2,
        delayMs: 1000,
        error: const SocketException('断'),
      );

      final state = RetrySignals.instance.notifier.value!;
      expect(state.level, RetryLevel.round);
      expect(state.attempt, 1);
      expect(state.maxAttempts, 2);
      expect(state.errorCategory, RetryErrorCategory.networkDisconnected);
    });

    test('clear → notifier.value == null', () {
      RetrySignals.instance.reportTransport(
        attempt: 1,
        maxAttempts: 8,
        delayMs: 100,
        error: const SocketException('x'),
      );
      expect(RetrySignals.instance.notifier.value, isNotNull);

      RetrySignals.instance.clear();
      expect(RetrySignals.instance.notifier.value, isNull);
    });

    test('连续 report,后值覆盖前值', () {
      RetrySignals.instance.reportTransport(
        attempt: 1,
        maxAttempts: 8,
        delayMs: 100,
        error: const SocketException('x'),
      );
      RetrySignals.instance.reportRound(
        attempt: 1,
        maxAttempts: 2,
        delayMs: 1000,
        error: const RetryableHttpException(503, '', ''),
      );
      final v = RetrySignals.instance.notifier.value!;
      expect(v.level, RetryLevel.round,
          reason: '后写的 report 覆盖前一个 transport state');
    });
  });

  group('categorizeRetryError', () {
    test('429 → rateLimited', () {
      expect(
        categorizeRetryError(const RetryableHttpException(429, '', '')),
        RetryErrorCategory.rateLimited,
      );
    });
    test('408 → requestTimeout', () {
      expect(
        categorizeRetryError(const RetryableHttpException(408, '', '')),
        RetryErrorCategory.requestTimeout,
      );
    });
    test('4xx 其他 → requestError', () {
      expect(
        categorizeRetryError(const RetryableHttpException(400, '', '')),
        RetryErrorCategory.requestError,
      );
      expect(
        categorizeRetryError(const RetryableHttpException(401, '', '')),
        RetryErrorCategory.requestError,
      );
    });
    test('5xx → serverError', () {
      expect(
        categorizeRetryError(const RetryableHttpException(500, '', '')),
        RetryErrorCategory.serverError,
      );
      expect(
        categorizeRetryError(const RetryableHttpException(503, '', '')),
        RetryErrorCategory.serverError,
      );
    });
    test('SocketException/HandshakeException → networkDisconnected', () {
      expect(
        categorizeRetryError(const SocketException('x')),
        RetryErrorCategory.networkDisconnected,
      );
      expect(
        categorizeRetryError(const HandshakeException()),
        RetryErrorCategory.networkDisconnected,
      );
    });
    test('TimeoutException → responseTimeout', () {
      expect(
        categorizeRetryError(
          TimeoutException('x', const Duration(milliseconds: 1)),
        ),
        RetryErrorCategory.responseTimeout,
      );
    });
    test('其它 → retrying', () {
      expect(categorizeRetryError(StateError('x')), RetryErrorCategory.retrying);
    });

    test('RetryErrorCategory.label 文案映射', () {
      expect(RetryErrorCategory.rateLimited.label, '限流');
      expect(RetryErrorCategory.requestTimeout.label, '请求超时');
      expect(RetryErrorCategory.serverError.label, '服务端错误');
      expect(RetryErrorCategory.networkDisconnected.label, '网络断开');
    });
  });

  group('llmErrorUserMessage', () {
    test('RetryableHttpException 429 → 限流文案', () {
      const e = RetryableHttpException(429, '', '');
      expect(llmErrorUserMessage(e), 'AI 请求过于频繁，请稍等片刻再试');
    });

    test('RetryableHttpException 5xx → 服务端错误文案(带状态码)', () {
      const e = RetryableHttpException(502, '', '');
      expect(llmErrorUserMessage(e), contains('502'));
      expect(llmErrorUserMessage(e), contains('AI 服务暂时不可用'));
    });

    test('RetryableHttpException 400 → 请求失败文案(带状态码,无裸 url)', () {
      const e = RetryableHttpException(400, '', 'https://secret.example.com');
      final msg = llmErrorUserMessage(e);
      expect(msg, contains('400'));
      expect(msg, isNot(contains('secret.example.com')), reason: '不得泄漏 url');
      expect(msg, isNot(contains('RetryableHttpException')),
          reason: '不得裸 toString');
    });

    test('网络类异常 → 不可用文案', () {
      expect(
        llmErrorUserMessage(const SocketException('x')),
        contains('AI 服务暂时不可用'),
      );
      expect(
        llmErrorUserMessage(TimeoutException('x', const Duration(seconds: 1))),
        contains('AI 服务暂时不可用'),
      );
    });

    test('QuotaExhaustedException → 保留原中文文案', () {
      const e = QuotaExhaustedException('{}', '');
      expect(llmErrorUserMessage(e), contains('免费额度已用完'));
    });

    test('未知异常 → 原样透传(保留诊断信息)', () {
      expect(llmErrorUserMessage(StateError('boom')), contains('boom'));
    });
  });
}
