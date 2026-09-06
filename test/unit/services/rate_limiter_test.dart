import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/rate_limiter.dart';

/// RateLimiter 单元测试
///
/// 测试速率限制器的核心功能：
/// - acquire 首次请求立即返回
/// - acquire 连续请求需要等待
/// - reset 后下一次请求立即返回
void main() {
  group('RateLimiter - 速率限制器测试', () {
    late RateLimiter rateLimiter;

    setUp(() {
      rateLimiter = RateLimiter(interval: Duration(milliseconds: 100));
    });

    test('首次 acquire 应该立即返回', () async {
      final sw = Stopwatch()..start();
      await rateLimiter.acquire();
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    test('连续 acquire 应该等待指定间隔', () async {
      await rateLimiter.acquire();

      final sw = Stopwatch()..start();
      await rateLimiter.acquire();
      sw.stop();

      // 应该等待约100ms（允许±50ms误差）
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(80));
    });

    test('reset 后下一次 acquire 应该立即返回', () async {
      await rateLimiter.acquire();
      rateLimiter.reset();

      final sw = Stopwatch()..start();
      await rateLimiter.acquire();
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    // 注：canRequestImmediately / timeUntilNextRequest 已从 RateLimiter 移除，
    // 对应的 getter 测试随之移除。核心行为（acquire 等待 + reset 重置）由其余用例覆盖。
  });

  group('RateLimiter - 智能速率控制场景测试', () {
    test('模拟缓存命中场景：连续 reset 后快速获取', () async {
      final rateLimiter = RateLimiter(interval: Duration(seconds: 30));

      // 模拟缓存章节连续获取
      final sw = Stopwatch()..start();

      for (int i = 0; i < 3; i++) {
        // 获取章节（模拟）
        await rateLimiter.acquire();
        // 缓存命中 → reset
        rateLimiter.reset();
      }

      sw.stop();
      // 3次缓存命中应该极快（< 100ms），因为每次都 reset 了
      expect(sw.elapsedMilliseconds, lessThan(200));
    });

    test('模拟爬虫抓取场景：每次都要等待间隔', () async {
      final rateLimiter = RateLimiter(interval: Duration(milliseconds: 100));

      final sw = Stopwatch()..start();

      // 第一次立即
      await rateLimiter.acquire();
      // 第二次需要等100ms
      await rateLimiter.acquire();

      sw.stop();
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(80));
    });

    test('模拟混合场景：缓存+爬虫交替', () async {
      final rateLimiter = RateLimiter(interval: Duration(milliseconds: 100));

      final sw = Stopwatch()..start();

      // 缓存命中 → reset
      await rateLimiter.acquire();
      rateLimiter.reset();

      // 缓存命中 → reset
      await rateLimiter.acquire();
      rateLimiter.reset();

      // 爬虫抓取 → 不 reset
      await rateLimiter.acquire();

      // 下一次需要等待
      await rateLimiter.acquire();

      sw.stop();
      // 2次缓存（无等待）+ 1次爬虫 + 1次等待（100ms）
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(80));
    });
  });
}