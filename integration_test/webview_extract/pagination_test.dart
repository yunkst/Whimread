/// WebView 翻页集成测试
///
/// 测试两种翻页场景：
///   1. 目录翻页：章节列表跨多页 → 点下一页 → 提取 → 拼接
///   2. 内容翻页：章节内容跨多页 → 点下一页 → 提取 → 拼接
///
/// 翻页模拟方案：
///   用 JS 动态替换 DOM 模拟翻页效果，点击"下一页"时切换到"第 2 页"的内容。
///   这样不需要真实网络导航，全部在 InAppWebViewInitialData 内完成。
///
/// ## 运行
///   cd novel_app
///   flutter test integration_test/webview_extract/pagination_test.dart -d windows
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:novel_app/services/novel_agent/scenarios/webview_extract_scenario.dart';
import 'package:novel_app/services/logger_service.dart';

// ===========================================================================
// 多页模拟 HTML（翻页测试专用）
//
// 页面结构：
//   - 第 1 页：3 个章节 + "下一页"按钮
//   - 第 2 页：2 个章节 + "尾页"标记（无下一页）
//   通过 JS 切换 #page1 和 #page2 的 display 模拟翻页
// ===========================================================================
const String multiPageHtml = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <title>星辰变 - 章节列表</title>
</head>
<body>
  <!-- 初始状态：只有第 1 页的章节链接和第 1 页的翻页按钮 -->
  <div id="app">
    <h1 class="novel-title">星辰变</h1>
    <div id="chapter-container">
      <ul>
        <li><a class="chapter-link" href="https://example.com/ch1.html">第一章 初入江湖</a></li>
        <li><a class="chapter-link" href="https://example.com/ch2.html">第二章 拜师学艺</a></li>
        <li><a class="chapter-link" href="https://example.com/ch3.html">第三章 下山历练</a></li>
      </ul>
    </div>
    <div class="pagination">
      <a class="next-page" href="#" onclick="switchToPage2(); return false;">下一页</a>
    </div>
  </div>

  <!-- 内容翻页区域，初始隐藏 -->
  <div id="content-area" style="display: none;">
    <h2 class="chapter-title">第一章 初入江湖</h2>
    <div id="content-container">
      <p class="novel-paragraph">少年背着一把生锈的铁剑，站在了青云山下。</p>
      <p class="novel-paragraph">山风吹起他的衣角，也吹起了他心中的忐忑。</p>
      <p class="novel-paragraph">"这里就是修仙界的第一关吗？"他喃喃自语。</p>
    </div>
    <div class="pagination">
      <a class="next-content-page" href="#" onclick="switchContentToPage2(); return false;">下一页</a>
    </div>
  </div>

  <script>
    // 目录翻页：清空旧章节，灌入第 2 页章节
    function switchToPage2() {
      var container = document.getElementById('chapter-container');
      container.innerHTML = '<ul>' +
        '<li><a class="chapter-link" href="https://example.com/ch4.html">第四章 初遇魔教</a></li>' +
        '<li><a class="chapter-link" href="https://example.com/ch5.html">第五章 生死之战</a></li>' +
        '</ul>';
      var pagination = document.querySelector('#app .pagination');
      pagination.innerHTML = '<span class="last-page">已经是最后一页</span>';
    }
    // 内容翻页：清空旧段落，灌入第 2 页段落
    function switchContentToPage2() {
      var container = document.getElementById('content-container');
      container.innerHTML = '' +
        '<p class="novel-paragraph">守山弟子打量了他一番，嘴角露出一丝不屑。</p>' +
        '<p class="novel-paragraph">"又来了一个不知天高地厚的小子。"</p>' +
        '<p class="novel-paragraph">少年没有理会嘲笑，只是紧紧握住了剑柄。</p>';
      var pagination = document.querySelector('#content-area .pagination');
      pagination.innerHTML = '<span class="last-content-page">看完啦~</span>';
    }
  </script>
</body>
</html>
''';

/// 多页 WebView 测试辅助类
class MultiPageTestHelper {
  InAppWebViewController? _controller;
  Completer<InAppWebViewController>? _controllerCompleter;
  Completer<void>? _pageLoadCompleter;

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
              data: multiPageHtml,
              mimeType: 'text/html',
              encoding: 'utf-8',
              baseUrl: WebUri('https://example.com/novel/chapter_list.html'),
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

    _controller = await _controllerCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('WebView 初始化超时'),
    );

    await tester.pump();
    await _pageLoadCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('页面加载超时'),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    return _controller!;
  }

  Future<void> dispose() async {
    _controller = null;
    _controllerCompleter = null;
    _pageLoadCompleter = null;
  }
}

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
    InAppWebViewController controller, [
    String currentUrl = 'https://example.com/novel/chapter_list.html',
  ]) {
    final provider = Provider<WebViewExtractScenario>((ref) {
      return WebViewExtractScenario(ref, controller, currentUrl);
    });
    return container.read(provider);
  }

  /// 辅助：执行工具调用并解码 JSON
  Future<Map<String, dynamic>> callTool(
    WebViewExtractScenario scenario,
    String name,
    Map<String, dynamic> args,
  ) async {
    final result = await scenario.executeTool(name, args);
    return jsonDecode(result) as Map<String, dynamic>;
  }

  // ===========================================================================
  // 测试 1：目录翻页
  // ===========================================================================
  testWidgets('翻页 - 目录获取翻页（章节列表跨多页提取拼接）', (tester) async {
    final helper = MultiPageTestHelper();
    final controller = await helper.createWebView(tester);
    final scenario = createScenario(controller);

    final result = await callTool(scenario, 'execute_js', {
      'script': '''
        (async function() {
          const PAGE_URL = '{{URL}}';
          const allChapters = [];

          function extractChapters() {
            const items = [];
            document.querySelectorAll('.chapter-link').forEach(function(link) {
              items.push({
                title: link.innerText.trim(),
                url: new URL(link.getAttribute('href'), PAGE_URL).href
              });
            });
            return items;
          }

          allChapters.push(...extractChapters());

          let nextBtn = document.querySelector('.next-page');
          let pageNum = 1;

          while (nextBtn) {
            pageNum++;
            nextBtn.click();
            await new Promise(function(r) { setTimeout(r, 300); });
            allChapters.push(...extractChapters());
            nextBtn = document.querySelector('.next-page');
            if (pageNum >= 5) break;
          }

          const titleEl = document.querySelector('.novel-title');
          const title = titleEl ? titleEl.innerText.trim() : '';

          return JSON.stringify({
            title: title,
            chapters: allChapters,
            totalPages: pageNum,
            totalChapters: allChapters.length
          });
        })()
      ''',
    });

    // ignore: avoid_print
    print('PAGINATION-TEST1 (目录翻页) result: ${jsonEncode(result)}');
    expect(result['error'], isNull);
    expect(result['title'], '星辰变');
    expect(result['totalPages'], 2);
    expect(result['totalChapters'], 5);
    final chapters = result['chapters'] as List;
    expect(chapters.length, 5);
    expect((chapters[0] as Map)['title'], '第一章 初入江湖');
    expect((chapters[3] as Map)['title'], '第四章 初遇魔教');
    expect((chapters[4] as Map)['title'], '第五章 生死之战');

    await helper.dispose();
  });

  // ===========================================================================
  // 测试 2：内容翻页（章节内容跨多页拼接）
  // ===========================================================================
  testWidgets('翻页 - 内容获取翻页（章节内容跨多页提取拼接）', (tester) async {
    final helper = MultiPageTestHelper();
    final controller = await helper.createWebView(tester);
    final scenario = createScenario(controller);

    // 先切换到内容模式
    await controller.evaluateJavascript(source: '''
      document.getElementById('page1').style.display = 'none';
      document.getElementById('content-area').style.display = 'block';
    ''');

    final result = await callTool(scenario, 'execute_js', {
      'script': '''
        (async function() {
          const PAGE_URL = '{{URL}}';
          const allParagraphs = [];
          let chapterTitle = '';

          function extractParagraphs() {
            const items = [];
            document.querySelectorAll('.novel-paragraph').forEach(function(p) {
              const text = p.innerText.trim();
              if (text.length > 0 &&
                  !text.includes('本章未完') &&
                  !text.includes('一秒记住') &&
                  !text.includes('笔趣阁')) {
                items.push(text);
              }
            });
            return items;
          }

          const titleEl = document.querySelector('.chapter-title');
          if (titleEl) chapterTitle = titleEl.innerText.trim();

          allParagraphs.push(...extractParagraphs());

          let nextBtn = document.querySelector('.next-content-page');
          let pageNum = 1;

          while (nextBtn) {
            pageNum++;
            nextBtn.click();
            await new Promise(function(r) { setTimeout(r, 300); });
            allParagraphs.push(...extractParagraphs());
            nextBtn = document.querySelector('.next-content-page');
            if (pageNum >= 5) break;
          }

          return JSON.stringify({
            title: chapterTitle,
            content: allParagraphs.join('\\n\\n'),
            totalParagraphs: allParagraphs.length,
            totalPages: pageNum
          });
        })()
      ''',
    });

    // ignore: avoid_print
    print('PAGINATION-TEST2 (内容翻页) result: ${jsonEncode(result)}');
    expect(result['error'], isNull);
    expect(result['title'], '第一章 初入江湖');
    expect(result['totalPages'], 2);
    expect(result['totalParagraphs'], 6);
    final content = result['content'] as String;
    expect(content.contains('青云山'), isTrue);
    expect(content.contains('不知天高地厚'), isTrue);
    final idx1 = content.indexOf('青云山');
    final idx2 = content.indexOf('不知天高地厚');
    expect(idx1 < idx2, true);

    await helper.dispose();
  });

  // ===========================================================================
  // 测试 3：翻页终止条件——无"下一页"时正常退出循环
  // ===========================================================================
  testWidgets('翻页 - 达到最后一页时正确退出', (tester) async {
    final helper = MultiPageTestHelper();
    final controller = await helper.createWebView(tester);
    final scenario = createScenario(controller);

    final result = await callTool(scenario, 'execute_js', {
      'script': '''
        (async function() {
          const PAGE_URL = '{{URL}}';
          const allChapters = [];

          function extractChapters() {
            const items = [];
            document.querySelectorAll('.chapter-link').forEach(function(link) {
              items.push(link.innerText.trim());
            });
            return items;
          }

          allChapters.push(...extractChapters());

          let nextBtn = document.querySelector('.next-page');
          let pageNum = 1;

          while (nextBtn && pageNum < 10) {
            pageNum++;
            nextBtn.click();
            await new Promise(function(r) { setTimeout(r, 200); });
            allChapters.push(...extractChapters());
            nextBtn = document.querySelector('.next-page');
          }

          const hasLastPage = document.querySelector('.last-page') != null;

          return JSON.stringify({
            totalPages: pageNum,
            chapters: allChapters,
            hasMorePages: nextBtn != null,
            reachedLastPageMarker: hasLastPage
          });
        })()
      ''',
    });

    // ignore: avoid_print
    print('PAGINATION-TEST3 (翻页终止) result: ${jsonEncode(result)}');
    expect(result['error'], isNull);
    expect(result['totalPages'], 2);
    expect(result['hasMorePages'], false);
    expect(result['reachedLastPageMarker'], true);

    await helper.dispose();
  });

  // ===========================================================================
  // 测试 4：翻页过程中正常提取（验证第 2 页数据正确）
  // ===========================================================================
  testWidgets('翻页 - 翻页后正确提取第二页数据', (tester) async {
    final helper = MultiPageTestHelper();
    final controller = await helper.createWebView(tester);
    final scenario = createScenario(controller);

    final result = await callTool(scenario, 'execute_js', {
      'script': '''
        (async function() {
          const PAGE_URL = '{{URL}}';
          const chapters = [];

          document.querySelectorAll('.chapter-link').forEach(function(link) {
            chapters.push(link.innerText.trim());
          });

          let nextBtn = document.querySelector('.next-page');
          if (nextBtn) {
            nextBtn.click();
            await new Promise(function(r) { setTimeout(r, 200); });
          }

          document.querySelectorAll('.chapter-link').forEach(function(link) {
            chapters.push(link.innerText.trim());
          });

          return JSON.stringify({ chapters: chapters, count: chapters.length });
        })()
      ''',
    });

    // ignore: avoid_print
    print('PAGINATION-TEST4 (第二页数据) result: ${jsonEncode(result)}');
    expect(result['count'], 5);
    expect((result['chapters'] as List).last, '第五章 生死之战');

    await helper.dispose();
  });

  // ===========================================================================
  // 测试 5：空页面——没有章节链接时不应崩溃
  // ===========================================================================
  testWidgets('翻页 - 空章节列表时优雅处理', (tester) async {
    final helper = MultiPageTestHelper();
    final controller = await helper.createWebView(tester);
    final scenario = createScenario(controller);

    await controller.evaluateJavascript(source: '''
      document.querySelectorAll('.chapter-link').forEach(function(el) {
        el.remove();
      });
    ''');

    final result = await callTool(scenario, 'execute_js', {
      'script': '''
        (async function() {
          const PAGE_URL = '{{URL}}';
          const chapters = [];
          document.querySelectorAll('.chapter-link').forEach(function(link) {
            chapters.push(link.innerText.trim());
          });
          return JSON.stringify({ chapters: chapters, count: chapters.length });
        })()
      ''',
    });

    // ignore: avoid_print
    print('PAGINATION-TEST5 (空列表) result: ${jsonEncode(result)}');
    expect(result['count'], 0);
    expect(result['chapters'] as List, isEmpty);

    await helper.dispose();
  });
}
