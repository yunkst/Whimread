/// WebView 集成测试辅助工具
///
/// 封装 InAppWebView 的创建、控制器捕获、页面加载等待等样板代码。
/// 使用 InAppWebViewInitialData 加载确定性 HTML，无需网络依赖。
///
/// ## 前提条件
///   - Windows 10/11，Edge WebView2 Runtime 已安装（Win11 预装）
///   - Flutter SDK 3.x
///
/// ## 使用示例
/// ```dart
/// testWidgets('测试标题', (tester) async {
///   final helper = WebViewTestHelper();
///   final controller = await helper.createWebView(tester);
///   // ... 执行测试 ...
///   await helper.dispose();
/// });
/// ```
///
/// ## 运行
///   cd novel_app
///   flutter test integration_test/xxx_test.dart -d windows
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// WebView 集成测试辅助类
///
/// 在 testWidgets 中创建真实的 InAppWebView，
/// 通过 Completer 模式捕获控制器并等待页面加载完成。
class WebViewTestHelper {
  InAppWebViewController? _controller;
  Completer<InAppWebViewController>? _controllerCompleter;
  Completer<void>? _pageLoadCompleter;

  /// 测试页面的基础 URL（用于 InAppWebViewInitialData 的 baseUrl）
  static const String testBaseUrl = 'https://example.com/novel/';

  /// 确定性测试 HTML
  ///
  /// 模拟典型小说站点的章节列表页面 DOM 结构：
  /// - 小说标题
  /// - 章节链接列表（模拟 chapter_list 页面）
  /// - 正文段落（模拟 chapter_content 页面）
  /// - 分页链接
  /// - 广告元素（应被脚本过滤）
  static const String testHtml = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <title>测试小说 - 章节列表</title>
</head>
<body>
  <div id="app">
    <h1 class="novel-title">星辰变</h1>
    <div class="chapter-list">
      <ul id="chapter-ul">
        <li><a class="chapter-link" href="https://example.com/ch1.html">第一章 初入江湖</a></li>
        <li><a class="chapter-link" href="https://example.com/ch2.html">第二章 拜师学艺</a></li>
        <li><a class="chapter-link" href="https://example.com/ch3.html">第三章 下山历练</a></li>
      </ul>
    </div>
    <div class="content-area">
      <h2 class="chapter-title">第一章 初入江湖</h2>
      <p class="novel-paragraph">这是一个测试段落，用于验证DOM查询功能。</p>
      <p class="novel-paragraph">第二个测试段落，包含一些<span class="highlight">高亮</span>文本。</p>
      <div class="ad-banner">广告内容，应该被跳过</div>
      <p class="novel-paragraph">第三个测试段落。</p>
    </div>
    <div class="pagination">
      <a class="next-page" href="https://example.com/page2.html">下一页</a>
    </div>
  </div>
  <div id="debug-info" style="display:none;">debug data</div>
</body>
</html>
''';

  /// 创建 InAppWebView 并等待初始化完成
  ///
  /// 1. pumpWidget 挂载 InAppWebView 组件
  /// 2. 等待 onWebViewCreated 回调（捕获控制器）
  /// 3. 等待 onLoadStop 回调（页面加载完成）
  ///
  /// 超时 15 秒（WebView2 首次初始化需要 2-5 秒）。
  Future<InAppWebViewController> createWebView(WidgetTester tester) async {
    _controllerCompleter = Completer<InAppWebViewController>();
    _pageLoadCompleter = Completer<void>();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 800,
          height: 600,
          child: InAppWebView(
            key: GlobalKey(),
            initialData: InAppWebViewInitialData(
              data: testHtml,
              mimeType: 'text/html',
              encoding: 'utf-8',
              baseUrl: WebUri(testBaseUrl),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
              if (!_controllerCompleter!.isCompleted) {
                _controllerCompleter!.complete(controller);
              }
            },
            onLoadStop: (controller, url) {
              if (!_pageLoadCompleter!.isCompleted) {
                _pageLoadCompleter!.complete();
              }
            },
          ),
        ),
      ),
    );

    // 等待 WebView 控制器就绪
    _controller = await _controllerCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw TimeoutException(
          'WebView 控制器初始化超时（15秒），请确认 Edge WebView2 已安装',
        );
      },
    );

    // 等待页面加载完成
    await tester.pump();
    await _pageLoadCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw TimeoutException('WebView 页面加载超时（15秒）');
      },
    );

    // 额外 pump 确保渲染完成
    await tester.pumpAndSettle(const Duration(seconds: 2));

    return _controller!;
  }

  /// 获取当前控制器（必须先调用 createWebView）
  InAppWebViewController get controller {
    if (_controller == null) {
      throw StateError('WebView 尚未创建，请先调用 createWebView()');
    }
    return _controller!;
  }

  /// 清理 WebView 资源
  Future<void> dispose() async {
    _controller = null;
    _controllerCompleter = null;
    _pageLoadCompleter = null;
  }
}
