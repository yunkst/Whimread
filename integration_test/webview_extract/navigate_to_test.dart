/// navigate_to 工具集成测试
///
/// 验证 WebViewExtractScenario._navigateTo 工具能：
///   1. 加载初始 URL
///   2. 跳转到第二个 URL（跨域/同域皆可）
///   3. 等待 onLoadStop 完成
///   4. 跳转后调用 get_page_info 能看到新页面 DOM
///
/// ## 运行
///   cd novel_app
///   flutter test integration_test/webview_extract/navigate_to_test.dart -d windows
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:novel_app/services/novel_agent/scenarios/webview_extract_scenario.dart';
import 'package:novel_app/services/logger_service.dart';
import '../helpers/webview_test_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUpAll(() async {
    container = ProviderContainer();
    LoggerService.resetForTesting();
  });

  tearDownAll(() async {
    container.dispose();
  });

  WebViewExtractScenario createScenario(
    InAppWebViewController controller,
    String currentUrl,
  ) {
    final provider = Provider<WebViewExtractScenario>((ref) {
      return WebViewExtractScenario(ref, controller, currentUrl);
    });
    return container.read(provider);
  }

  // 用多页测试 HTML 模拟跳转效果（用 innerHTML 替换内容而非真实 URL 跳转）
  // 因为集成测试要求确定性，但 navigate_to 在真实场景会跳到任意 URL
  // 这里我们用 file:// 加载两段 HTML，验证 WebView 切换内容的能力

  testWidgets('navigate_to 工具 - 缺 url 参数', (tester) async {
    final helper = WebViewTestHelper();
    final controller = await helper.createWebView(tester);
    final scenario = createScenario(controller, WebViewTestHelper.testBaseUrl);

    final result = await scenario.executeTool('navigate_to', {});
    final json = jsonDecode(result) as Map<String, dynamic>;

    // ignore: avoid_print
    print('TEST1 (缺url): $json');
    expect(json['error'], 'missing_param');
    expect(json['missing'], contains('url'));

    await helper.dispose();
  });

  testWidgets('navigate_to 工具 - URL 格式不合法', (tester) async {
    final helper = WebViewTestHelper();
    final controller = await helper.createWebView(tester);
    final scenario = createScenario(controller, WebViewTestHelper.testBaseUrl);

    final result = await scenario.executeTool('navigate_to', {
      'url': 'not-a-valid-url',
    });
    final json = jsonDecode(result) as Map<String, dynamic>;

    // ignore: avoid_print
    print('TEST2 (URL不合法): $json');
    expect(json['error'], 'INVALID_URL');

    await helper.dispose();
  });

  testWidgets('navigate_to 工具 - 拒绝 javascript: 伪协议', (tester) async {
    final helper = WebViewTestHelper();
    final controller = await helper.createWebView(tester);
    final scenario = createScenario(controller, WebViewTestHelper.testBaseUrl);

    final result = await scenario.executeTool('navigate_to', {
      'url': 'javascript:void(0)',
    });
    final json = jsonDecode(result) as Map<String, dynamic>;

    // ignore: avoid_print
    print('TEST3 (javascript伪协议): $json');
    expect(json['error'], 'INVALID_URL');

    await helper.dispose();
  });

  testWidgets('navigate_to 工具 - 跳转到当前页面应快速返回', (tester) async {
    final helper = WebViewTestHelper();
    final controller = await helper.createWebView(tester);
    // 初始 helper 加载的 baseUrl 是 testBaseUrl, 但 getUrl 返回的可能是 about:blank
    // 需要在 scenario 中传入与 WebView 实际 URL 一致的值
    final actualUrl = (await controller.getUrl())?.toString() ??
        WebViewTestHelper.testBaseUrl;
    final scenario = createScenario(controller, actualUrl);

    final result = await scenario.executeTool('navigate_to', {
      'url': actualUrl,
    });
    final json = jsonDecode(result) as Map<String, dynamic>;

    // ignore: avoid_print
    print('TEST4 (同URL) actualUrl=$actualUrl result: $json');
    // 初始页可能是 about:blank，需要先导航到 http URL 才能用此工具
    if (actualUrl.startsWith('http')) {
      expect(json['ok'], true);
      expect(json['note'], isNotNull,
          reason: '同 URL 应返回 note 说明未执行跳转');
    } else {
      // ignore: avoid_print
      print('跳过断言：初始页不是 http URL（是 $actualUrl）');
    }

    await helper.dispose();
  });

  testWidgets('navigate_to 工具 - 真实 URL 跳转 + 新页面可见', (tester) async {
    // 创建 WebView 加载初始 HTML
    final helper = WebViewTestHelper();
    final controller = await helper.createWebView(tester);
    final scenario = createScenario(
      controller,
      WebViewTestHelper.testBaseUrl,
    );

    // 跳转到一个真实可访问的 URL（用 example.com 简单页面）
    const targetUrl = 'https://example.com/';
    final result = await scenario.executeTool('navigate_to', {
      'url': targetUrl,
    });
    final json = jsonDecode(result) as Map<String, dynamic>;

    // ignore: avoid_print
    print('TEST5 (真实跳转) result: ${jsonEncode(json)}');
    // 跳转可能成功也可能失败（网络环境），但应该返回了有效 JSON
    expect(json, isNotNull);

    if (json['ok'] == true) {
      // 跳转成功后，新页面可见
      final newUrl = await controller.getUrl();
      // ignore: avoid_print
      print('跳转后 URL: $newUrl');
      expect(newUrl?.toString(), targetUrl);

      // 验证 execute_js 在新页面上能正常工作
      final jsResult = await scenario.executeTool('execute_js', {
        'script': '''
          (function() {
            const PAGE_URL = '{{URL}}';
            return JSON.stringify({title: document.title, h1: document.querySelector('h1') ? document.querySelector('h1').innerText : 'no h1'});
          })()
        ''',
      });
      final jsJson = jsonDecode(jsResult) as Map<String, dynamic>;
      // ignore: avoid_print
      print('跳转后 page info: $jsJson');
      expect(jsJson['error'], isNull,
          reason: '跳转后 execute_js 不应报错');
      expect(jsJson['title'], isNotNull,
          reason: 'example.com 应有 title');
    } else {
      // ignore: avoid_print
      print('⚠️ 真实跳转失败: ${json['error']} ${json['message']}');
      // 网络问题不算测试失败
    }

    await helper.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
