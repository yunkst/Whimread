/// WebViewAddNovelFab 三分支编排单测
///
/// 验证：无脚本场景下点击 FAB -> 调用 ContextualAgentLauncher.launch
/// （autoSend + noScript 草稿）。
///
/// 不覆盖（需要真实 InAppWebViewController 执行 JS）：
///   - 有脚本成功路径（保留原 :150-269 逻辑）
///   - 有脚本失败/超时降级
library;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:novel_app/core/providers/agent_launcher_providers.dart';
import 'package:novel_app/core/providers/webview_add_novel_providers.dart';
import 'package:novel_app/core/providers/webview_providers.dart';
import 'package:novel_app/services/agent_launcher/agent_launch_request.dart';
import 'package:novel_app/services/agent_launcher/contextual_agent_launcher.dart';
import 'package:novel_app/widgets/webview_add_novel_button.dart';

/// mockito 直接 implement 抽象/具体类即可（ContextualAgentLauncher 是普通类）。
@GenerateNiceMocks([MockSpec<ContextualAgentLauncher>()])
import 'webview_add_novel_fab_orchestration_test.mocks.dart';

/// 占位 PlatformInAppWebViewController：测试用 noScript 分支不会真正调用 JS，
/// 只需让 webviewControllerProvider 非 null，通过 controller==null 守卫。
class _FakePlatformController extends PlatformInAppWebViewController {
  _FakePlatformController()
      : super.implementation(
            const PlatformInAppWebViewControllerCreationParams(id: 'fake'));
}

void main() {
  late MockContextualAgentLauncher launcher;
  late ProviderContainer container;

  setUp(() {
    launcher = MockContextualAgentLauncher();
    container = ProviderContainer(
      overrides: [
        contextualAgentLauncherProvider.overrideWithValue(launcher),
        // 无脚本：site_scripts 表查不到该 domain -> 返回 null
        webviewCurrentSiteScriptProvider.overrideWith((ref) async => null),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<void> pumpFab(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: const WebViewAddNovelFab(),
          ),
        ),
      ),
    );
  }

  testWidgets('无脚本时点击 FAB -> 触发 launcher.launch(autoSend, noScript)',
      (tester) async {
    // 设置无脚本 + http 页面
    container.read(webviewCurrentUrlProvider.notifier).state =
        'https://a.com/book/123';

    // controller 非 null 才能通过 _handleAddNovel 的 controller==null 校验；
    // noScript 分支在调用 controller 任何方法前就 return，所以 fake controller 即可。
    container.read(webviewControllerProvider.notifier).setController(
          InAppWebViewController.fromPlatform(
            platform: _FakePlatformController(),
          ),
        );

    await pumpFab(tester);
    await tester.pump();

    // FAB 应可见（webviewHasAddNovelButtonProvider 仅依赖 domain 非 null）
    expect(find.byTooltip('添加小说'), findsOneWidget);

    await tester.tap(find.byTooltip('添加小说'));
    await tester.pumpAndSettle();

    // launch(BuildContext, AgentLaunchRequest) 是两个位置参数，无 named param。
    // 原 brief 示例里的 `context: anyNamed('context')` 是 mockito 误用，已修正。
    final captured = verify(
      launcher.launch(any, captureThat(isA<AgentLaunchRequest>())),
    ).captured;

    expect(captured, hasLength(1));
    final request = captured.single as AgentLaunchRequest;
    // noScript 分支必然 autoSend + 草稿非空 + scenarioId=webview_extract
    expect(request.mode, LaunchMode.autoSend);
    expect(request.draftMessage, isNotEmpty);
    expect(request.context['failureReason'], 'noScript');
  });
}
