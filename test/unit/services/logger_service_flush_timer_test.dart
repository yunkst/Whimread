/// LoggerService 延迟持久化 timer 清理回归测试
///
/// LoggerService._schedulePersist 在距上次持久化 <1s 时会安排一个 1s 后的
/// 兜底 timer（_pendingFlushTimer）。若不保存引用、不在 resetForTesting 取消，
/// 这个 pending timer 会跨测试残留，在 widget test 的 _verifyInvariants 处
/// 报 "Timer is still pending" —— 这曾导致 contextual_agent_launcher_test
/// 在 CI 上必现失败（本地因时序差异恰好不触发）。
///
/// 本测试验证 resetForTesting 能取消该 timer：修复前会因 timersPending 失败，
/// 修复后通过。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novel_app/services/logger_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LoggerService.resetForTesting();
  });

  testWidgets('resetForTesting 取消未 fire 的延迟持久化 timer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    // 连续两次记日志（<1s 间隔）触发 _schedulePersist 的 else 分支，
    // 安排一个 1s 后的 _pendingFlushTimer。
    final log = LoggerService.instance;
    log.i('first');
    log.i('second');

    // resetForTesting 必须取消该 timer，否则 testWidgets 结束时
    // _verifyInvariants 会因 timersPending 失败。
    LoggerService.resetForTesting();

    // 故意只 pump 一帧（不推进到 1s）：若 timer 未取消，此处结束后会暴露。
    await tester.pump();
  });
}
