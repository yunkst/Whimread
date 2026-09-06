import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_app/models/novel.dart';
import 'package:novel_app/widgets/novel/novel_cover.dart';

/// NovelCover 分支选择测试。
///
/// AI 封面命中（coverMediaId 非空）→ 渲染 MediaView（ConsumerStatefulWidget，
/// 依赖 mediaProxyProvider + IO），端到端渲染脆弱，仅验证"命中即出现 MediaView
/// 而非程序化 CustomPaint"这一分支选择（参照 avatar_media_test 约定）。
/// 未命中 → 走 _ProgrammaticCoverPainter（CustomPaint）。
void main() {
  setUp(() {
    // 屏蔽 SharedPreferences channel 缺失引发的 noise + 未取消 timer。
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets('coverMediaId 为空 → 程序化封面（含 CustomPaint）', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: NovelCover(
              novel: Novel(title: '测试', author: '作者', url: 'custom://x'),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('coverMediaId 非空 → 命中 MediaView（不再走程序化文字）',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              height: 160,
              child: NovelCover(
                novel: Novel(
                  title: '测试',
                  author: '作者',
                  url: 'custom://x',
                  coverMediaId: 'media-fake',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // MediaView 是异步 resolve，让异步 _load() 走完（resolve 失败走 miss 路径，
    // _evaluateTimer 启动轮询 Timer）。
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    // 命中分支不应渲染程序化封面的标题文字 CustomPainter（_ProgrammaticCoverPainter）
    final coverMediaPainters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((c) => c.painter?.runtimeType.toString() == '_ProgrammaticCoverPainter');
    expect(coverMediaPainters, isEmpty,
        reason: 'coverMediaId 命中时不应渲染 _ProgrammaticCoverPainter');

    // 卸载 widget tree 触发 MediaView.dispose() 取消轮询 Timer，避免
    // "Timer is still pending after widget tree disposed" 报错。
    await tester.pumpWidget(const SizedBox.shrink());
    // 推完 LoggerService._schedulePersist 的 1s timer + VisibilityDetector 的
    // 0.5s timer，避免 binding._verifyInvariants 报 "Timer still pending"。
    await tester.pump(const Duration(seconds: 2));
  });
}