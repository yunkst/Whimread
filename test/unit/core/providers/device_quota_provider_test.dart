/// DeviceQuotaNotifier 单元测试
///
/// 覆盖 AI 使用驱动的额度自动刷新链路：
/// - onAiUsage 尾沿防抖：连续 N 次使用事件合流为 1 次查询
/// - 防抖触发后强刷（绕过 60s TTL）
/// - 拉取失败保留旧余额、推进 TTL
/// - dispose 取消未触发的防抖 timer
///
/// fetchQuota 经构造注入（默认 DeviceAuthService 单例不可在单测中
/// 发真实请求），Timer 用 fakeAsync 推进。
///
/// 运行:
///   flutter test test/unit/core/providers/device_quota_provider_test.dart
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/core/providers/device_quota_provider.dart';
import 'package:novel_app/services/device/device_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DeviceQuotaInfo infoOf(int balance) => DeviceQuotaInfo(
        deviceId: 'dev-1',
        quotaBalance: balance,
        status: 'active',
        attestationVerified: true,
      );

  group('DeviceQuotaNotifier.onAiUsage 防抖', () {
    test('连续多次使用事件合流为 1 次查询，且为强刷', () {
      fakeAsync((async) {
        var fetchCount = 0;
        final notifier = DeviceQuotaNotifier(fetchQuota: () async {
          fetchCount++;
          return infoOf(100);
        });

        // agent 一轮对话的 5 次 LLM 调用，每次都发使用事件
        notifier.onAiUsage();
        async.elapse(const Duration(milliseconds: 500));
        notifier.onAiUsage();
        async.elapse(const Duration(milliseconds: 500));
        notifier.onAiUsage();
        notifier.onAiUsage();
        notifier.onAiUsage();
        expect(fetchCount, 0, reason: '防抖窗口内不应触发查询');

        async.elapse(quotaUsageDebounce);
        expect(fetchCount, 1, reason: '窗口静默后尾沿触发一次');
        expect(notifier.state.info?.quotaBalance, 100);

        notifier.dispose();
      });
    });

    test('两轮使用事件（间隔超过窗口）各触发一次查询', () {
      fakeAsync((async) {
        var fetchCount = 0;
        final notifier = DeviceQuotaNotifier(fetchQuota: () async {
          fetchCount++;
          return infoOf(fetchCount);
        });

        notifier.onAiUsage();
        async.elapse(quotaUsageDebounce);
        expect(fetchCount, 1);

        notifier.onAiUsage();
        async.elapse(quotaUsageDebounce);
        expect(fetchCount, 2);
        expect(notifier.state.info?.quotaBalance, 2);

        notifier.dispose();
      });
    });

    test('dispose 取消未触发的防抖 timer', () {
      fakeAsync((async) {
        var fetchCount = 0;
        final notifier = DeviceQuotaNotifier(fetchQuota: () async {
          fetchCount++;
          return infoOf(1);
        });

        notifier.onAiUsage();
        notifier.dispose();
        async.elapse(quotaUsageDebounce * 2);
        expect(fetchCount, 0);
      });
    });
  });

  group('DeviceQuotaNotifier.refresh', () {
    test('强刷绕过 TTL 更新余额', () async {
      var balance = 50;
      final notifier = DeviceQuotaNotifier(fetchQuota: () async {
        return infoOf(balance);
      });

      await notifier.refresh(force: true);
      expect(notifier.state.info?.quotaBalance, 50);

      balance = 30; // 模拟 AI 使用后服务端扣减
      // 非 force：60s TTL 内跳过（fetchedAt 刚推进）
      await notifier.refresh();
      expect(notifier.state.info?.quotaBalance, 50);

      // force：立即拉到新值
      await notifier.refresh(force: true);
      expect(notifier.state.info?.quotaBalance, 30);

      notifier.dispose();
    });

    test('拉取失败（null）保留旧余额并推进 TTL', () async {
      var fail = false;
      final notifier = DeviceQuotaNotifier(fetchQuota: () async {
        if (fail) return null;
        return infoOf(88);
      });

      await notifier.refresh(force: true);
      expect(notifier.state.info?.quotaBalance, 88);

      fail = true;
      await notifier.refresh(force: true);
      expect(notifier.state.info?.quotaBalance, 88, reason: '失败应保留旧值');

      notifier.dispose();
    });
  });

  group('DeviceQuotaNotifier.hasRedeemedStar（Star 一次性兑换标记）', () {
    test('refresh 后加载本地已兑换标记（额度耗尽引导的条件）', () async {
      final notifier = DeviceQuotaNotifier(
        fetchQuota: () async => infoOf(0),
        hasRedeemedStar: () async => true,
      );

      expect(notifier.state.hasRedeemedStar, isFalse);
      await notifier.refresh(force: true);
      await Future<void>.delayed(Duration.zero); // 标记异步补写
      expect(notifier.state.hasRedeemedStar, isTrue,
          reason: '已兑换过 → UI 不再引导去 Star');

      notifier.dispose();
    });

    test('未兑换过保持 false（宁可多引导，不漏引导）', () async {
      final notifier = DeviceQuotaNotifier(
        fetchQuota: () async => infoOf(0),
        hasRedeemedStar: () async => false,
      );

      await notifier.refresh(force: true);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.hasRedeemedStar, isFalse);

      notifier.dispose();
    });
  });
}
