library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/models/agent_chat_message.dart';
import 'package:novel_app/services/media/media_proxy.dart';
import 'package:novel_app/services/media/media_types.dart';
import 'package:novel_app/widgets/agent_chat/agent_message_bubble.dart';
import 'package:novel_app/widgets/media/media_view.dart';

/// 假 MediaProxy：resolve 返回 loaded 状态，指向临时 PNG。
///
/// 真实 MediaView 在 _load 内调用 proxy.resolve。若返回 pending/failed/miss，
/// MediaView 会启动 10s 轮询 Timer，触发 widget test 的 "Timer is still
/// pending" 错误。这里直接返回 loaded + 1x1 PNG 字节，MediaView 进入已加载态，
/// 不启动 polling，也能被 find.byType(MediaView) 匹配。
class _FakeMediaProxy implements MediaProxy {
  _FakeMediaProxy(this._pngPath);

  final String _pngPath;

  @override
  Future<MediaResult> resolve(String mediaId) async => MediaResult(
        status: MediaStatus.loaded,
        kind: MediaKind.image,
        localPathHint: _pngPath,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('FakeMediaProxy 不支持: ${invocation.memberName}');
  }
}

/// 最小 1x1 透明 PNG（89 字节），足以让 Image.file 成功 decode。
final Uint8List _kOnePixelPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, // IDAT
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, // IEND
  0x42, 0x60, 0x82,
]);

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('agent_bubble_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets('user 气泡含 ImageSegment → 出现 MediaView', (tester) async {
    final imgPath = '${tempDir.path}/local_test1.png';
    File(imgPath).writeAsBytesSync(_kOnePixelPng);

    final msg = AgentChatMessage(
      role: AgentChatRole.user,
      segments: const [
        ImageSegment(mediaId: 'local_test1'),
        TextSegment('看看这张'),
      ],
    );

    // MediaView 是 ConsumerStatefulWidget，内部 _load 异步 + VisibilityDetector
    // 在 widget test fake_async 下会调度 500ms 一次性 timer，触发 "Timer is
    // still pending" 不变量错误。用 runAsync 跑在真实 async zone，绕开
    // fake_async 的 timer 校验。
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaProxyProvider.overrideWithValue(_FakeMediaProxy(imgPath)),
          ],
          child: MaterialApp(
            home: Scaffold(body: AgentMessageBubble(message: msg)),
          ),
        ),
      );
      // 让 MediaView._load 异步完成
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    // 在 fake_async 下 pump 一次刷新 widget 树
    await tester.pump();

    expect(find.byType(MediaView), findsOneWidget);
    expect(find.text('看看这张'), findsOneWidget);
  });

  testWidgets('user 气泡纯文本（回归）→ 无 MediaView', (tester) async {
    final imgPath = '${tempDir.path}/local_test1.png';
    File(imgPath).writeAsBytesSync(_kOnePixelPng);

    final msg = AgentChatMessage(
      role: AgentChatRole.user,
      segments: const [TextSegment('你好')],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaProxyProvider.overrideWithValue(_FakeMediaProxy(imgPath)),
        ],
        child: MaterialApp(
          home: Scaffold(body: AgentMessageBubble(message: msg)),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MediaView), findsNothing);
    expect(find.text('你好'), findsOneWidget);
  });
}
