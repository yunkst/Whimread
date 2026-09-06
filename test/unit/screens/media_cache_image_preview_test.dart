/// 媒体缓存页图片全屏预览测试
///
/// 验证从 media_cache_screen 点图片缩略图后能进入全屏预览页，且点击可退出。
/// 通过 imageBuilder 注入纯色 Container，避免 Image/PhotoView 在 widget test 中
/// 因缺少真实图像解码而挂起。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/screens/media_cache_screen.dart';

void main() {
  testWidgets('MediaImagePreviewScreen 渲染 Hero 并支持点击退出',
      (tester) async {
    final observer = _MockNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: MediaImagePreviewScreen(
          file: _dummyFile,
          heroTag: 'test_hero_tag',
          imageBuilder: (context, file) =>
              const ColoredBox(color: Color(0xFF000000), child: SizedBox.expand()),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(Hero), findsOneWidget);
    // 点击任意位置应触发 pop。MaterialApp 也有一个 ColoredBox（scaffoldBackground），
    // 故用 .at(0) 取 imageBuilder 注入的全屏 ColoredBox 进行点击。
    await tester.tap(find.byType(ColoredBox).at(0));
    await tester.pump();

    expect(observer.popped, isTrue);
  });
}

/// 测试用 File 占位：imageBuilder 注入了无需文件 IO 的 widget，
/// File 实例本身不被读取，只需满足构造函数签名。
final _dummyFile = _FakeFile();

class _FakeFile implements File {
  const _FakeFile();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockNavigatorObserver extends NavigatorObserver {
  bool popped = false;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped = true;
  }
}

