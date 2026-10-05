/// 回归测试：MediaView 在 ListView item 的 Column 中触发
/// `BoxConstraints forces an infinite height` 异常 → UI 白屏+卡死
///
/// 背景（2026-07-08）：
/// Agent 一次会话中多次调用 create_images 工具（每次 1 张），结果在 chat
/// 对话框滚到图片区域时整片空屏、无法向下滚动。根因：
/// MediaView 非全屏图片分支（media_view.dart:316-336）用了
/// `Stack(fit: StackFit.expand)` 包裹无 width/height 的 Image.file，
/// 当 N 个 MediaView 嵌在 ListView item 的 Column 中时，父约束纵轴
/// unbounded，StackFit.expand 触发
/// `BoxConstraints forces an infinite height` 异常，RenderBox 未布局，
/// 级联导致 ListView item 高度塌缩、RenderViewport.maxScrollExtent 异常、
/// 滚动手势失灵。
///
/// 修复（media_gallery_card.dart 的 _GallerySlot）：
/// 在 MediaView 外层包 `AspectRatio(aspectRatio: 1)`，给内部
/// Stack(StackFit.expand) 一个 bounded 父约束，从根上消除 unbounded。
///
/// 本测试用两套策略：
/// 1) 纯布局等价实验（不依赖 MediaView 异步路径）—— 验证根因 + 修复模式有效
/// 2) MediaGalleryCard 结构断言 —— 验证 _GallerySlot 确实在 MediaView 外层
///    包了 AspectRatio，不依赖异步状态、不受 widget test 噪音影响
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/theme/app_colors.dart';
import 'package:novel_app/services/media/media_proxy.dart';
import 'package:novel_app/services/media/media_types.dart';
import 'package:novel_app/widgets/agent_chat/media_gallery_card.dart';
import 'package:novel_app/widgets/media/media_view.dart';

/// MediaView 的媒体解析桩：直接返回 miss，切断 MediaStore 文件 IO 与数据库，
/// 让回归 #3 只关心 widget 树结构（AspectRatio 包裹），不受异步加载状态影响。
/// 传入的 DatabaseConnection 是惰性单例且 `database` getter 从不被触达
/// （resolve 已覆写），因此测试内没有任何真实 I/O——testWidgets 的 FakeAsync
/// 区无法驱动 sqflite_ffi 的真实 I/O，用真实 DB 会导致超时挂起。
class _MissMediaProxy extends MediaProxy {
  _MissMediaProxy() : super(dbConn: DatabaseConnection());

  @override
  Future<MediaResult> resolve(String mediaId) async =>
      const MediaResult(status: MediaStatus.miss);
}

/// 等价的"裸 Image.file"在 Stack(StackFit.expand) 里的布局行为
Widget _simulateUnboundedImageInStack() {
  return Container(
    color: Colors.grey.shade300,
    alignment: Alignment.center,
    child: const Text('image'),
  );
}

/// 模拟 media_view.dart:316-336 的 _ImageContent 形态：Stack(fit: StackFit.expand)
/// + 无 width/height 的 image 占位 + Positioned 角标。这是触发 bug 的核心 widget 树。
Widget _buildBuggyImageSlot() {
  return GestureDetector(
    onTap: () {},
    child: Stack(
      fit: StackFit.expand,
      children: [
        _simulateUnboundedImageInStack(),
        const Positioned(
          right: 6,
          bottom: 6,
          child: Icon(Icons.fullscreen, size: 14, color: Colors.white),
        ),
      ],
    ),
  );
}

void main() {
  /// 回归 #1（纯布局）：Stack(StackFit.expand) 在 ListView item 的 Column 中
  /// 纵轴父约束 unbounded → 触发 `BoxConstraints forces an infinite height`。
  ///
  /// 不依赖 MediaView 异步/timer 路径，CI 100% 稳定。
  ///
  /// 注意：[WidgetTester.binding.setSurfaceSize] 修改的是 binding 级全局表面
  /// 尺寸，跨测试持久。setSurfaceSize 必须在 test body 内调用（依赖 inTest
  /// 断言），且每个测试末尾必须用 addTearDown 把 surface 恢复为默认（null），
  /// 否则 400×800 的小屏会污染后续依赖默认 800×600 surface 的 widget 测试
  /// （如 contextual_agent_launcher_test 的全屏 dialog）。
  /// 注意：本测试组需要小屏 surface（400×800）来稳定触发 unbounded 约束。
  /// 用 [WidgetTester.view.physicalSize]（现代 API）而非 binding.setSurfaceSize：
  /// 前者随 WidgetTester 生命周期自动重置，不污染后续测试；后者修改 binding
  /// 全局状态，需要手动恢复 addTearDown（曾因 inTest 断言在 setUp/tearDown
  /// 不可用，导致跨测试污染 contextual_agent_launcher_test 等依赖默认 surface
  /// 的 widget 测试）。
  void useSmallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
  }

  testWidgets('回归 #1: 裸 Stack(StackFit.expand) 在 ListView+Column → 抛 RenderBox 异常',
      (tester) async {
    useSmallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: 3,
            itemBuilder: (context, index) {
              if (index == 1) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(4, (i) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: SizedBox(
                          width: 200,
                          child: _buildBuggyImageSlot(),
                        ),
                      );
                    }),
                  ),
                );
              }
              return const SizedBox(height: 60, child: ColoredBox(color: Colors.blue));
            },
          ),
        ),
      ),
    );
    await tester.pump();

    // 关键断言：未修复的 Stack(StackFit.expand) 路径必抛异常
    final ex = tester.takeException();
    expect(ex, isNotNull,
        reason: '裸 Stack(StackFit.expand) 在 unbounded 父约束下必抛 '
            'BoxConstraints forces an infinite height，证明 _GallerySlot '
            '的 AspectRatio 修复是真正必要的');
    // 多异常会被 flutter_test 包成 "Multiple exceptions (N)"，原始细节
    // 不可直接 toString 比对，所以这里只断言"有异常发生"——bug 复现的关键
    // 是"无 AspectRatio 时必崩"，具体异常文字不强制。
  });

  /// 回归 #2（修复模式）：Stack(StackFit.expand) 外层包 AspectRatio → 父约束
  /// bounded → 不再抛异常。
  ///
  /// 验证修复模式(给 _GallerySlot 提供 bounded 父约束)有效。
  testWidgets('回归 #2: AspectRatio 包裹 → Stack(StackFit.expand) 不再抛异常',
      (tester) async {
    useSmallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: 3,
            itemBuilder: (context, index) {
              if (index == 1) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(4, (i) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        // 关键：与 _GallerySlot 修复等价
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: SizedBox(
                            width: 200,
                            child: _buildBuggyImageSlot(),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }
              return const SizedBox(height: 60, child: ColoredBox(color: Colors.blue));
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'AspectRatio 给 Stack(StackFit.expand) 提供 bounded 父约束后，'
            '4 个 stack 堆叠都不应触发 RenderBox 异常');
  });

  /// 回归 #3（结构断言）：MediaGalleryCard 单图分支的 widget 树必须让
  /// MediaView 处于 AspectRatio 之内 —— 防止后续维护者误删修复。
  ///
  /// 这是唯一锁定 `media_gallery_card.dart::_GallerySlot` 修复的回归防线
  /// （#1/#2 只在测试本地复现布局机制，改生产代码时它们照样绿）。
  /// 原先因「MediaView 异步/timer 噪音」被 skip，实际原因不成立：
  /// - MediaView 的 periodic 轮询由 `_shouldPoll` 决定，单图分支
  ///   （fullscreen=false、未出屏）下恒为 false，initState 不建 timer；
  /// - 轮询逻辑用 `mediaProxyProvider` 覆写为 miss 桩，彻底断开文件 IO
  ///   与数据库，保证 widget 树同步可断言；
  /// - 断言后主动 pumpWidget 卸载 → MediaView.dispose 取消任何潜在 timer，
  ///   teardown 干净无 "Timer is still pending"。
  testWidgets('回归 #3: MediaGalleryCard 单图分支中 MediaView 被 AspectRatio 包裹',
      (tester) async {
    final proxy = _MissMediaProxy();
    final card = MediaGalleryCard(
      data: MediaGalleryData(items: [
        MediaGalleryItem(mediaId: 'm0', kind: MediaKind.image, prompt: 'p0'),
      ]),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaProxyProvider.overrideWithValue(proxy)],
        child: MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFB8843A),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            extensions: <ThemeExtension<dynamic>>[AppColors.dark],
          ),
          home: Scaffold(
            body: SizedBox(width: 200, height: 200, child: card),
          ),
        ),
      ),
    );
    await tester.pump();

    // 核心断言：MediaView 必须在 AspectRatio 之内（祖先关系），而不只是
    // 「树里存在某个 AspectRatio」——后者可能被卡片其它角落的 AspectRatio
    // 误满足，删掉 _GallerySlot 的包裹后仍会通过。
    expect(find.byType(MediaView), findsOneWidget);
    expect(
      find.ancestor(of: find.byType(MediaView), matching: find.byType(AspectRatio)),
      findsAtLeastNWidgets(1),
      reason: '修复后 MediaGalleryCard 单图分支必须在 MediaView 外层包 AspectRatio '
          '（或等效 bounded 父约束），给内部 Stack(StackFit.expand) bounded 高度。'
          '如本断言失败，说明有人误删了 _GallerySlot 的 AspectRatio 包裹，'
          '会立刻在 ListView+Column 场景触发白屏+卡死 bug。',
    );

    // 主动卸载 → MediaView.dispose；再推进 600ms 把延迟回调在
    // paint 期排的 500ms 一次性 timer（FakeAsync 区跟踪）无害跑完，
    // teardown 不会报 "A Timer is still pending"
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });
}
