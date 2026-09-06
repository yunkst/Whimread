/// RetryHelper 单元测试
///
/// 验证 [withRetry] 的重试次数、瞬态错误判定、指数退避 + 抖动、
/// 非 transient 错误立即抛出。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/utils/retry_helper_test.dart
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/utils/retry_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('withRetry', () {
    test('首次成功 → 只调用一次 fn，不退避', () async {
      var calls = 0;
      final result = await withRetry(
        () async {
          calls++;
          return 'ok';
        },
        label: 'test',
      );
      expect(result, 'ok');
      expect(calls, 1);
    });

    test('前 2 次 SocketException，第 3 次成功 → 总 3 次 attempt', () async {
      var calls = 0;
      final result = await withRetry(
        () async {
          calls++;
          if (calls < 3) throw const SocketException('boom');
          return 'recovered';
        },
        config: const RetryConfig(
          maxAttempts: 3,
          initialDelay: Duration(milliseconds: 1),
        ),
        label: 'test',
      );
      expect(result, 'recovered');
      expect(calls, 3);
    });

    test('所有 attempt 失败 → 抛最后一次异常', () async {
      var calls = 0;
      await expectLater(
        () => withRetry(
          () async {
            calls++;
            throw const SocketException('always');
          },
          config: const RetryConfig(
            maxAttempts: 3,
            initialDelay: Duration(milliseconds: 1),
          ),
          label: 'test',
        ),
        throwsA(isA<SocketException>()),
      );
      expect(calls, 3);
    });

    test('shouldRetry 返回 false → 立即 rethrow（即使 attempts 未用尽）', () async {
      var calls = 0;
      await expectLater(
        () => withRetry(
          () async {
            calls++;
            throw const FormatException('永远不该重试');
          },
          config: RetryConfig(
            maxAttempts: 5,
            initialDelay: const Duration(milliseconds: 1),
            shouldRetry: (e) => e is! FormatException,
          ),
          label: 'test',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(calls, 1);
    });

    test('默认 shouldRetry 判定：FormatException 不重试', () async {
      var calls = 0;
      await expectLater(
        () => withRetry(
          () async {
            calls++;
            throw const FormatException('x');
          },
          config: const RetryConfig(
            maxAttempts: 3,
            initialDelay: Duration(milliseconds: 1),
          ),
          label: 'test',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(calls, 1, reason: 'FormatException 默认不重试');
    });

    test('TimeoutException 默认判定为可重试', () async {
      var calls = 0;
      await withRetry(
        () async {
          calls++;
          if (calls < 2) {
            throw TimeoutException('timeout', const Duration(seconds: 1));
          }
          return 'ok';
        },
        config: const RetryConfig(
          maxAttempts: 3,
          initialDelay: Duration(milliseconds: 1),
        ),
        label: 'test',
      );
      expect(calls, 2);
    });

    test('RetryableHttpException（含 4xx/5xx）默认判定为可重试', () async {
      // 5xx
      var calls = 0;
      await withRetry(
        () async {
          calls++;
          if (calls < 2) throw const RetryableHttpException(503, '', '');
          return 'ok';
        },
        config: const RetryConfig(
          maxAttempts: 3,
          initialDelay: Duration(milliseconds: 1),
        ),
        label: 'test',
      );
      expect(calls, 2);

      // 4xx 也走重试（自 2026-07-17 起统一策略）
      calls = 0;
      await withRetry(
        () async {
          calls++;
          if (calls < 2) throw const RetryableHttpException(400, '', '');
          return 'ok';
        },
        config: const RetryConfig(
          maxAttempts: 3,
          initialDelay: Duration(milliseconds: 1),
        ),
        label: 'test',
      );
      expect(calls, 2, reason: '4xx 错误也走重试');

      // 401 鉴权错误同样重试
      calls = 0;
      await withRetry(
        () async {
          calls++;
          if (calls < 2) throw const RetryableHttpException(401, '', '');
          return 'ok';
        },
        config: const RetryConfig(
          maxAttempts: 3,
          initialDelay: Duration(milliseconds: 1),
        ),
        label: 'test',
      );
      expect(calls, 2, reason: '401 也走重试');
    });

    test('退避时间随 attempt 递增且有上限', () async {
      // initialDelay=100ms, multiplier=2.0, maxDelay=300ms
      // 第 1 次重试前 base=100, 第 2 次 base=200, 第 3 次 base=300 (capped)
      // jitter 0 → delayMs 精确
      final sw = Stopwatch()..start();
      var calls = 0;
      try {
        await withRetry(
          () async {
            calls++;
            throw const SocketException('always');
          },
          config: const RetryConfig(
            maxAttempts: 4,
            initialDelay: Duration(milliseconds: 100),
            maxDelay: Duration(milliseconds: 300),
            jitterFactor: 0, // 关闭抖动以便精确断言
          ),
          label: 'backoff_test',
        );
      } catch (_) {}
      sw.stop();
      // 3 次重试退避：100 + 200 + 300 = 600ms（±少量调度抖动）
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(550));
      expect(sw.elapsedMilliseconds, lessThan(2000));
      expect(calls, 4);
    });

    test('jitter 在 ±25% 区间内（initialDelay=100ms 采样）', () async {
      // 1 次重试 ≈ 100ms ± 25ms → [75, 125]
      final durations = <int>[];
      for (var i = 0; i < 20; i++) {
        final sw = Stopwatch()..start();
        try {
          await withRetry(
            () async => throw const SocketException('x'),
            config: const RetryConfig(
              maxAttempts: 2,
              initialDelay: Duration(milliseconds: 100),
              jitterFactor: 0.25,
            ),
            label: 'jitter_test',
          );
        } catch (_) {}
        sw.stop();
        durations.add(sw.elapsedMilliseconds);
      }
      // 至少有一个落在 75~125 区间（多数应满足；CI 抖动可能个别越界）
      final inRange = durations.where((d) => d >= 70 && d <= 200).length;
      expect(inRange, greaterThan(durations.length * 0.8),
          reason: '80% 以上的样本应落在退避 ±25% 区间');
    });

    group('withRetry.onRetry 回调', () {
      test('首次成功 → onRetry 调用 0 次', () async {
        final calls = <List<int>>[]; // [attempt, maxAttempts]
        final result = await withRetry(
          () async => 'ok',
          config: const RetryConfig(
            maxAttempts: 3,
            initialDelay: Duration(milliseconds: 1),
          ),
          onRetry: (a, m, d, e) => calls.add([a, m]),
        );
        expect(result, 'ok');
        expect(calls, isEmpty);
      });

      test('第 1 次失败,第 2 次成功 → onRetry 调用 1 次,attempt=1', () async {
        final calls = <List<int>>[];
        var invocations = 0;
        final result = await withRetry(
          () async {
            invocations++;
            if (invocations < 2) throw const SocketException('boom');
            return 'ok';
          },
          config: const RetryConfig(
            maxAttempts: 3,
            initialDelay: Duration(milliseconds: 1),
          ),
          onRetry: (a, m, d, e) {
            calls.add([a, m, d]);
          },
        );
        expect(result, 'ok');
        expect(invocations, 2);
        expect(calls, hasLength(1));
        expect(calls.first[0], 1, reason: '失败 → 重试 1 次 → attempt=1');
        expect(calls.first[1], 3, reason: 'maxAttempts 透传');
        expect(calls.first[2], greaterThan(0), reason: 'delayMs > 0');
      });

      test('全失败 maxAttempts=3 → onRetry 调用 2 次 (maxAttempts-1)', () async {
        final calls = <int>[];
        await expectLater(
          () => withRetry(
            () async => throw const SocketException('always'),
            config: const RetryConfig(
              maxAttempts: 3,
              initialDelay: Duration(milliseconds: 1),
            ),
            onRetry: (a, m, d, e) => calls.add(a),
          ),
          throwsA(isA<SocketException>()),
        );
        expect(calls, [1, 2], reason: '全失败 → 重试 2 次 → attempt 1,2');
      });

      test('onRetry=null 默认行为不变(向后兼容)', () async {
        var invocations = 0;
        final result = await withRetry(
          () async {
            invocations++;
            if (invocations < 2) throw const SocketException('boom');
            return 'ok';
          },
          config: const RetryConfig(
            maxAttempts: 3,
            initialDelay: Duration(milliseconds: 1),
          ),
        );
        expect(result, 'ok');
        expect(invocations, 2, reason: '默认值 null → 不调用 onRetry,行为不变');
      });
    });
  });

  group('RetryConfig.defaultShouldRetry', () {
    test('SocketException / HandshakeException → true', () {
      expect(RetryConfig.defaultShouldRetry(const SocketException('x')), true);
      expect(
        RetryConfig.defaultShouldRetry(const HandshakeException()),
        true,
      );
    });

    test('TimeoutException → true', () {
      expect(
        RetryConfig.defaultShouldRetry(
          TimeoutException('x', const Duration(seconds: 1)),
        ),
        true,
      );
    });

    test('RetryableHttpException（含 4xx）→ true', () {
      expect(
        RetryConfig.defaultShouldRetry(
            const RetryableHttpException(500, '', '')),
        true,
      );
      expect(
        RetryConfig.defaultShouldRetry(
            const RetryableHttpException(400, '', '')),
        true,
        reason: '4xx 也统一可重试',
      );
      expect(
        RetryConfig.defaultShouldRetry(
            const RetryableHttpException(401, '', '')),
        true,
      );
    });

    test('FormatException / StateError → false（非 HTTP 逻辑错误）', () {
      expect(RetryConfig.defaultShouldRetry(const FormatException('x')), false);
      expect(RetryConfig.defaultShouldRetry(StateError('x')), false);
    });
  });

  group('RetryableHttpException.retryAfterMs', () {
    test('带 retryAfterMs 字段构造 → 字段可读', () {
      const e = RetryableHttpException(429, '', '', retryAfterMs: 5000);
      expect(e.statusCode, 429);
      expect(e.retryAfterMs, 5000);
    });

    test('旧式三参 const 构造仍合法（retryAfterMs 默认 null）', () {
      const e = RetryableHttpException(503, '', '');
      expect(e.retryAfterMs, isNull);
    });

    test('toString 包含 retryAfterMs（仅在非 null 时）', () {
      const a = RetryableHttpException(429, '', '');
      const b = RetryableHttpException(429, '', '', retryAfterMs: 1000);
      expect(a.toString(), isNot(contains('retryAfter')));
      expect(b.toString(), contains('retryAfter=1000ms'));
    });
  });

  group('withRetry + Retry-After 优先', () {
    test('Retry-After > 0 时按服务端值等待，不走指数退避', () async {
      var calls = 0;
      final sw = Stopwatch()..start();
      await withRetry(
        () async {
          calls++;
          if (calls < 2) {
            throw const RetryableHttpException(429, '', '', retryAfterMs: 200);
          }
          return 'ok';
        },
        config: const RetryConfig(
          maxAttempts: 3,
          initialDelay: Duration(seconds: 10), // 大值确认没走指数退避
        ),
        label: 'retry_after_test',
      );
      sw.stop();
      expect(calls, 2);
      // 指数退避会等 ~10s；Retry-After=200ms → 应远小于此
      expect(sw.elapsedMilliseconds, lessThan(2000),
          reason: 'Retry-After=200ms 应立即等待后重试，不走指数退避');
    });

    test('Retry-After > maxDelay → clamp 到 maxDelay', () async {
      var calls = 0;
      final sw = Stopwatch()..start();
      try {
        await withRetry(
          () async {
            calls++;
            throw const RetryableHttpException(
              503, '', '',
              retryAfterMs: 999999, // 远超 maxDelay
            );
          },
          config: const RetryConfig(
            maxAttempts: 2,
            initialDelay: Duration(seconds: 1),
            maxDelay: Duration(milliseconds: 100),
          ),
          label: 'retry_after_clamp_test',
        );
      } catch (_) {}
      sw.stop();
      // maxDelay=100ms → 应小于 500ms（去除调度抖动）
      expect(sw.elapsedMilliseconds, lessThan(500),
          reason: 'Retry-After=999999 应被 clamp 到 maxDelay=100ms');
      expect(calls, 2);
    });

    test('Retry-After == 0 → 回退指数退避（防雷鸣群）', () async {
      final sw = Stopwatch()..start();
      try {
        await withRetry(
          () async {
            throw const RetryableHttpException(429, '', '', retryAfterMs: 0);
          },
          config: const RetryConfig(
            maxAttempts: 2,
            initialDelay: Duration(milliseconds: 100),
            maxDelay: Duration(milliseconds: 100),
          ),
          label: 'retry_after_zero_test',
        );
      } catch (_) {}
      sw.stop();
      // retryAfterMs=0 → 回退指数退避（initialDelay=100ms + jitter）→ 应大于 50ms
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(50),
          reason: 'retryAfterMs=0 应回退指数退避而非立即重试');
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });

  group('parseRetryAfterMs', () {
    test('整数秒：Retry-After: 120 → 120000ms', () {
      expect(parseRetryAfterMs('120'), 120000);
    });

    test('整数秒含空格：先 trim 再解析', () {
      expect(parseRetryAfterMs('  120  '), 120000);
    });

    test('HTTP-date（未来时间）→ 正值', () {
      final future = DateTime.now().toUtc().add(const Duration(hours: 1));
      final header = future.toUtc().toIso8601String();
      // dart:io HttpDate 接受 RFC 1123 格式（IMF-fixdate）
      final rfc1123 = HttpDate.format(future.toUtc());
      final ms = parseRetryAfterMs(rfc1123);
      expect(ms, isNotNull);
      expect(ms, greaterThan(0));
      // 与 1h 误差应在 ±2s（测试运行耗时）
      expect(ms!, lessThanOrEqualTo(3600000 + 2000));
      // ISO8601 不被支持（HttpDate.parse 会抛）→ 返回 null
      expect(parseRetryAfterMs(header), isNull);
    });

    test('非法字符串 → null（不抛异常）', () {
      expect(parseRetryAfterMs('garbage'), isNull);
    });

    test('null / 空字符串 → null', () {
      expect(parseRetryAfterMs(null), isNull);
      expect(parseRetryAfterMs(''), isNull);
    });
  });

  group('RetryConfig 默认值', () {
    test('maxAttempts == 8', () {
      expect(const RetryConfig().maxAttempts, 8);
    });

    test('maxDelay == 60s', () {
      expect(const RetryConfig().maxDelay, const Duration(seconds: 60));
    });

    test('initialDelay == 500ms', () {
      expect(
          const RetryConfig().initialDelay, const Duration(milliseconds: 500));
    });

    test('multiplier == 2.0 / jitterFactor == 0.25（保留）', () {
      const cfg = RetryConfig();
      expect(cfg.multiplier, 2.0);
      expect(cfg.jitterFactor, 0.25);
    });

    test('8 次全失败 → 抛最后一次异常，总 attempt=8', () async {
      var calls = 0;
      await expectLater(
        () => withRetry(
          () async {
            calls++;
            throw const SocketException('always');
          },
          config: const RetryConfig(
            maxAttempts: 8,
            initialDelay: Duration(milliseconds: 1),
            maxDelay: Duration(milliseconds: 10),
          ),
          label: 'max_attempts_test',
        ),
        throwsA(isA<SocketException>()),
      );
      expect(calls, 8, reason: 'maxAttempts=8 应执行 8 次');
    });
  });

  group('isRetryableStatus', () {
    test('5xx → true', () {
      expect(isRetryableStatus(500), true);
      expect(isRetryableStatus(502), true);
      expect(isRetryableStatus(503), true);
      expect(isRetryableStatus(599), true);
    });

    test('429 → true（关键：限流现在重试）', () {
      expect(isRetryableStatus(429), true);
    });

    test('408 → true（Request Timeout）', () {
      expect(isRetryableStatus(408), true);
    });

    test('所有 4xx + 5xx → true（含 400/401/403/404/422）', () {
      expect(isRetryableStatus(400), true, reason: '4xx 统一重试（用户策略：宁可多等也尽量自愈）');
      expect(isRetryableStatus(401), true);
      expect(isRetryableStatus(403), true);
      expect(isRetryableStatus(404), true);
      expect(isRetryableStatus(422), true);
    });

    test('2xx / 3xx → false', () {
      expect(isRetryableStatus(200), false);
      expect(isRetryableStatus(301), false);
    });
  });

  group('LlmRetryBudget', () {
    test('默认值', () {
      const b = LlmRetryBudget();
      expect(b.transportBlockingMaxAttempts, 8);
      expect(b.transportStreamMaxAttempts, 3);
      expect(b.roundNetworkRetryPerRound, 2);
    });

    test('自定义值', () {
      const b = LlmRetryBudget(
        transportBlockingMaxAttempts: 5,
        transportStreamMaxAttempts: 2,
        roundNetworkRetryPerRound: 1,
      );
      expect(b.transportBlockingMaxAttempts, 5);
      expect(b.transportStreamMaxAttempts, 2);
      expect(b.roundNetworkRetryPerRound, 1);
    });

    test('strict() 工厂 — 严格模式值', () {
      const b = LlmRetryBudget.strict();
      expect(b.transportBlockingMaxAttempts, 3);
      expect(b.transportStreamMaxAttempts, 2);
      expect(b.roundNetworkRetryPerRound, 1);
    });
  });

  group('RetryPolicy', () {
    test('默认值', () {
      const p = RetryPolicy();
      expect(p.maxDelay, const Duration(seconds: 60));
      expect(p.initialDelay, const Duration(milliseconds: 500));
      expect(p.multiplier, 2.0);
      expect(p.jitterFactor, 0.25);
    });

    test('computeDelayMs retryAfterMs 优先', () {
      const p = RetryPolicy();
      final ms = p.computeDelayMs(attempt: 1, retryAfterMs: 30000);
      expect(ms, 30000, reason: '服务端 Retry-After=30s 直接采用');
    });

    test('computeDelayMs retryAfterMs > maxDelay → clamp', () {
      const p = RetryPolicy(maxDelay: Duration(seconds: 60));
      final ms = p.computeDelayMs(attempt: 1, retryAfterMs: 120000);
      expect(ms, 60000, reason: 'Retry-After=120s 应 clamp 到 maxDelay=60s');
    });

    test('computeDelayMs retryAfterMs=0 → 回退指数退避', () {
      const p = RetryPolicy();
      final ms = p.computeDelayMs(attempt: 1, retryAfterMs: 0);
      // 指数退避：500ms * 2^0 = 500ms ± jitter
      expect(ms, greaterThanOrEqualTo(375));
      expect(ms, lessThanOrEqualTo(625));
    });

    test('computeDelayMs retryAfterMs=null → 指数退避', () {
      const p = RetryPolicy();
      final ms = p.computeDelayMs(attempt: 1);
      expect(ms, greaterThanOrEqualTo(375));
      expect(ms, lessThanOrEqualTo(625),
          reason: 'attempt=1 → 500ms ± 25% jitter');
    });

    test('computeDelayMs jitter=0 确定性退避', () {
      const p = RetryPolicy(jitterFactor: 0);
      expect(p.computeDelayMs(attempt: 1), 500);
      expect(p.computeDelayMs(attempt: 2), 1000);
      expect(p.computeDelayMs(attempt: 3), 2000);
    });

    test('computeDelayMs 可注入 Random 做确定性测试', () {
      // jitterFactor=0 即确定性，无需自定义 Random
      const p = RetryPolicy(jitterFactor: 0);
      expect(p.computeDelayMs(attempt: 1), 500);
      expect(p.computeDelayMs(attempt: 2), 1000);
    });
  });
}
