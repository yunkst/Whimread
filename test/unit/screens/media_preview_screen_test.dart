/// 媒体全屏预览页（MediaPreviewScreen）测试
///
/// 覆盖收口后的统一全屏实现：单图（Hero + 点图关闭）、多图（计数标题 +
/// 横滑翻页 + 初项定位）、静态入口 open/openGallery 能把本页推上路由栈。
///
/// 媒体解析用 miss 桩直接短路（与 repro_multi_image_stack_overflow_test 同款）：
/// miss 是终态——无无限动画，pumpAndSettle 可用，弹道模拟的 timer 也能跑完，
/// 测试不依赖真实 IO，teardown 干净。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/screens/media_preview_screen.dart';
import 'package:novel_app/services/media/media_proxy.dart';

/// 解析恒返回 miss：切断 MediaStore 文件 IO 与数据库。
/// DatabaseConnection 是惰性单例且 resolve 已覆写，测试内无任何真实 I/O。
class _MissMediaProxy extends MediaProxy {
  _MissMediaProxy() : super(dbConn: DatabaseConnection());

  @override
  Future<MediaResult> resolve(String mediaId) async =>
      const MediaResult(status: MediaStatus.miss);
}

void main() {
  late MediaProxy proxy;

  setUp(() {
    proxy = _MissMediaProxy();
  });

  Widget wrap(Widget child, {List<NavigatorObserver> observers = const []}) {
    return ProviderScope(
      overrides: [mediaProxyProvider.overrideWithValue(proxy)],
      child: MaterialApp(
        navigatorObservers: observers,
        home: child,
      ),
    );
  }

  testWidgets('单图模式渲染 Hero 且点图退出', (tester) async {
    final observer = _MockNavigatorObserver();

    await tester.pumpWidget(wrap(
      const MediaPreviewScreen(
        mediaId: 'test_media_1',
        heroTag: 'test_hero_tag',
      ),
      observers: [observer],
    ));
    await tester.pump();

    // Hero 只挂初项：来源缩略图与本页同 tag 才会播转场
    expect(find.byType(Hero), findsOneWidget);
    // 单图无计数标题
    expect(find.textContaining('/'), findsNothing);

    // 点图关闭（body 级 GestureDetector）。避开正中的刷新按钮——
    // 那是 miss 占位里的独立控件，会吞掉这次点击
    await tester.tapAt(const Offset(30, 300));
    await tester.pump();
    expect(observer.popped, isTrue);
  });

  testWidgets('多图模式显示计数标题并横滑翻页，且不挂 Hero', (tester) async {
    await tester.pumpWidget(wrap(
      const MediaPreviewScreen.gallery(
        mediaIds: ['m1', 'm2', 'm3'],
      ),
    ));
    await tester.pump();

    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.byType(Hero), findsNothing);
    expect(find.byType(PageView), findsOneWidget);

    // 带速度的 fling 必然翻页（裸 drag 位移恰在吸附判定边界，会抖回上一页）
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 800);
    await tester.pumpAndSettle();

    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('open 静态入口把预览页推上路由栈', (tester) async {
    await tester.pumpWidget(wrap(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => MediaPreviewScreen.open(context, 'm_open'),
            child: const Text('打开'),
          ),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(MediaPreviewScreen), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
  });

  testWidgets('openGallery 静态入口定位到初项', (tester) async {
    await tester.pumpWidget(wrap(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => MediaPreviewScreen.openGallery(
              context,
              ['g1', 'g2', 'g3', 'g4'],
              initialIndex: 2,
            ),
            child: const Text('打开画廊'),
          ),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('打开画廊'));
    await tester.pumpAndSettle();

    expect(find.byType(MediaPreviewScreen), findsOneWidget);
    expect(find.text('3 / 4'), findsOneWidget);
  });
}

class _MockNavigatorObserver extends NavigatorObserver {
  bool popped = false;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped = true;
  }
}
