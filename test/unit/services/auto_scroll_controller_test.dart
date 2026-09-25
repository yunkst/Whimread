/// HighPerformanceAutoScrollController 自动滚动回归测试
///
/// 重点回归:帧回调链被长时间中断(退后台后恢复)时,墙钟时间差不得把
/// 整段中断时长一次性补滚到章节底部——单帧推进有 0.25s 上限,恢复后
/// 从原位置附近继续。
///
/// 控制器时间源可注入:测试用固定时钟手动推进,`pump()` 只负责驱动帧
/// 回调本身。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/auto_scroll_controller.dart';

/// LoggerService 写日志后有 1s 防抖 flush Timer,测试结束前泵过它,
/// 否则触发 binding 的 timersPending 不变量断言。
Future<void> _settleFlushTimer(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(seconds: 2));
}

Future<void> _pumpScrollable(WidgetTester tester, ScrollController sc) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          controller: sc,
          child: const SizedBox(height: 10000, width: 100),
        ),
      ),
    ),
  );
  await tester.pump(); // 首帧布局,使 maxScrollExtent 可用
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('长时间无帧(模拟退后台)后恢复,单帧只推进上限时长,不跳到底', (tester) async {
    final sc = ScrollController();
    await _pumpScrollable(tester, sc);
    final maxExtent = sc.position.maxScrollExtent;
    expect(maxExtent, greaterThan(1000), reason: '前置条件:内容足够长');

    var fakeNow = DateTime(2026, 1, 1);
    final controller = HighPerformanceAutoScrollController(
      scrollController: sc,
      clock: () => fakeNow,
    );
    controller.startAutoScroll(100); // 100 px/s

    fakeNow = fakeNow.add(const Duration(milliseconds: 500));
    await tester.pump(); // 0.5s 间隔被钳制为 0.25s → 25px
    final offsetBeforeGap = sc.offset;
    expect(offsetBeforeGap, closeTo(25, 0.5));

    // 模拟退后台 10 分钟:期间引擎停帧、回调不执行,恢复后的第一帧
    // 墙钟时间差为 10 分钟。修复前:offset 被一次性顶到 maxExtent;
    // 修复后:只推进 0.25s × 100px/s = 25px。
    fakeNow = fakeNow.add(const Duration(minutes: 10));
    await tester.pump();

    expect(sc.offset, closeTo(50, 1.0),
        reason: '只推进上限时长,不得把后台时长一次性补滚');
    expect(sc.offset, lessThan(maxExtent), reason: '不得直接跳到章节底部');
    expect(controller.isScrolling, isTrue, reason: '恢复后滚动应继续');

    controller.dispose();
    await _settleFlushTimer(tester);
  });

  testWidgets('正常连续帧按速度推进并能在底部触底停止', (tester) async {
    final sc = ScrollController();
    await _pumpScrollable(tester, sc);

    var fakeNow = DateTime(2026, 1, 1);
    final controller = HighPerformanceAutoScrollController(
      scrollController: sc,
      clock: () => fakeNow,
    );
    var completed = false;
    controller.startAutoScroll(1000, onScrollComplete: () => completed = true);

    fakeNow = fakeNow.add(const Duration(milliseconds: 500));
    await tester.pump(); // 1000px/s,0.5s 被钳制为 0.25s → 250px
    expect(sc.offset, greaterThan(100), reason: '正常帧应显著推进');

    // 连续泵帧直到触底(9400px / 250px每帧 ≈ 38 帧)
    for (var i = 0; i < 60 && !completed; i++) {
      fakeNow = fakeNow.add(const Duration(milliseconds: 500));
      await tester.pump();
    }
    expect(completed, isTrue, reason: '触底后应回调 onScrollComplete 并停止');
    expect(sc.offset, sc.position.maxScrollExtent);
    expect(controller.isScrolling, isFalse);

    controller.dispose();
    await _settleFlushTimer(tester);
  });

  testWidgets('暂停期间经过长时间不产生位移,恢复后从暂停处继续', (tester) async {
    final sc = ScrollController();
    await _pumpScrollable(tester, sc);

    var fakeNow = DateTime(2026, 1, 1);
    final controller = HighPerformanceAutoScrollController(
      scrollController: sc,
      clock: () => fakeNow,
    );
    controller.startAutoScroll(100);
    fakeNow = fakeNow.add(const Duration(milliseconds: 500));
    await tester.pump();
    final pausedAt = sc.offset;
    expect(pausedAt, closeTo(25, 0.5));

    controller.pauseAutoScroll();
    fakeNow = fakeNow.add(const Duration(minutes: 10));
    await tester.pump();
    expect(sc.offset, pausedAt, reason: '暂停态不滚动,恢复点不因后台时长漂移');

    controller.resumeAutoScroll(); // 重置 _lastFrameTime,避免恢复瞬间跳跃
    fakeNow = fakeNow.add(const Duration(seconds: 1));
    await tester.pump();
    expect(sc.offset, greaterThan(pausedAt), reason: '恢复后从暂停处继续');
    expect(sc.offset, lessThan(pausedAt + 100), reason: '恢复首帧仍受上限约束');

    controller.dispose();
    await _settleFlushTimer(tester);
  });
}
