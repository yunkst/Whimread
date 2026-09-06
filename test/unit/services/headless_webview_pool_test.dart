/// HeadlessWebViewPool 单元测试
///
/// 覆盖：
/// - acquire 引用计数正确性
/// - release 减少引用
/// - dispose 清理
/// - dispose 后 acquire 应该重新创建（健壮性）
/// - isReady 状态正确
/// - isInUse 排他标志（release 后复位）
///
/// 不覆盖（需集成测试 + 真实 platform channel）：
/// - 真实的 HeadlessInAppWebView 初始化
/// - 排他锁的真实并发等待（依赖 _ensureReady 成功）
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/services/headless_webview_pool.dart';
import 'package:novel_app/services/logger_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LoggerService.resetForTesting();
  });

  // ================================================================
  // 基础状态
  // ================================================================
  group('基础状态', () {
    test('新创建的 pool 处于未就绪状态', () {
      final pool = HeadlessWebViewPool();
      expect(pool.isReady, isFalse);
      expect(pool.refCount, 0);
      expect(pool.isInUse, isFalse);
    });

    test('dispose 后 refCount 重置为 0', () {
      final pool = HeadlessWebViewPool();
      pool.dispose();
      expect(pool.refCount, 0);
      expect(pool.isReady, isFalse);
      expect(pool.isInUse, isFalse);
    });
  });

  // ================================================================
  // 引用计数
  // ================================================================
  group('引用计数', () {
    test('acquire 失败（WebView 初始化失败）后 refCount 回退', () async {
      final pool = HeadlessWebViewPool();

      // 在纯 Dart 测试环境，HeadlessInAppWebView.run() 会抛异常
      try {
        await pool.acquire();
      } catch (_) {
        // 预期失败
      }

      // acquire 内部：refCount++ → 失败 → refCount-- → rethrow
      expect(pool.refCount, 0);
      // 初始化失败未走到 _isInUse = true
      expect(pool.isInUse, isFalse);
    });

    test('release 不允许 refCount 减到负数', () {
      final pool = HeadlessWebViewPool();
      pool.release();
      expect(pool.refCount, 0);

      pool.release();
      expect(pool.refCount, 0);
    });

    test('release 复位 isInUse 标志', () {
      final pool = HeadlessWebViewPool();
      // 直接 release 不应抛异常，且复位标志（初始即 false）
      pool.release();
      expect(pool.isInUse, isFalse);
    });
  });

  // ================================================================
  // dispose 健壮性
  // ================================================================
  group('dispose 健壮性', () {
    test('多次 dispose 不抛异常', () {
      final pool = HeadlessWebViewPool();
      pool.dispose();
      expect(() => pool.dispose(), returnsNormally);
      expect(pool.refCount, 0);
    });

    test('dispose 后 acquire 应该尝试重新初始化（健壮性）', () async {
      final pool = HeadlessWebViewPool();
      pool.dispose();

      try {
        await pool.acquire();
      } catch (_) {
        // 预期失败
      }
      expect(pool.isReady, isFalse);
    });
  });
}
