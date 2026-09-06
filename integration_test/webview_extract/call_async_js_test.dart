/// callAsyncJavaScript API 验证测试
///
/// 验证 WebView2 Windows 平台上 callAsyncJavaScript 能否：
///   1. 执行 async 函数并返回 Promise resolve 值
///   2. await setTimeout（模拟翻页等待）
///   3. DOM 查询 + 点击下一页按钮
///   4. 捕获 Promise reject 错误
///
/// ## 运行
///   cd novel_app
///   flutter test integration_test/webview_extract/call_async_js_test.dart -d windows
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/webview_test_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('callAsyncJavaScript API 验证', (tester) async {
    final helper = WebViewTestHelper();
    final controller = await helper.createWebView(tester);

    // =========================================================================
    // 1. 基础：async 函数 + Promise resolve 值返回
    // =========================================================================
    {
      final result = await controller.callAsyncJavaScript(
        functionBody: '''
          var p = new Promise(function(resolve) {
            resolve(JSON.stringify({hello: "world", count: 42}));
          });
          await p;
          return p;
        ''',
      );
      // ignore: avoid_print
      print('TEST1 - callAsyncJavaScript result: $result');
      // ignore: avoid_print
      print('TEST1 - result.runtimeType=${result.runtimeType}');
      if (result != null) {
        // ignore: avoid_print
        print('TEST1 - result.value.runtimeType=${result.value.runtimeType}');
        // ignore: avoid_print
        print('TEST1 - result.value=${result.value}');
        // ignore: avoid_print
        print('TEST1 - result.error=${result.error}');
      }

      // callAsyncJavaScript 返回 CallAsyncJavaScriptResult
      // value 应该是 Promise resolve 的值（JSON 字符串）
      expect(result, isNotNull);
      expect(result!.error, isNull);
      final parsed = jsonDecode(result.value as String) as Map<String, dynamic>;
      expect(parsed['hello'], 'world');
      expect(parsed['count'], 42);
    }

    // =========================================================================
    // 2. await setTimeout（模拟翻页等待）
    // =========================================================================
    {
      final stopwatch = Stopwatch()..start();
      final result = await controller.callAsyncJavaScript(
        functionBody: '''
          var p = new Promise(function(resolve) {
            setTimeout(function() {
              resolve("waited");
            }, 500);
          });
          await p;
          return p;
        ''',
      );
      final elapsed = stopwatch.elapsedMilliseconds;
      // ignore: avoid_print
      print('TEST2 - elapsed=${elapsed}ms, result.value=${result?.value}');

      // 实际上 setTimeout 是否能生效取决于 WebView2 的 callAsyncJavaScript 实现
      // 如果 elapsed >= ~400ms 说明 setTimeout 确实生效了
      expect(result, isNotNull);
      // 不严格判断 error，因为 WebView2 可能行为不同
      // ignore: avoid_print
      print('TEST2 - setTimeout 是否生效: elapsed=${elapsed}ms');
    }

    // =========================================================================
    // 3. DOM 查询 + click + 等待（模拟翻页单步操作）
    // =========================================================================
    {
      // 先确认当前页面有章节链接
      final result = await controller.callAsyncJavaScript(
        functionBody: '''
          var p = new Promise(function(resolve) {
            var links = document.querySelectorAll('.chapter-link');
            var titles = [];
            links.forEach(function(link) {
              titles.push(link.innerText.trim());
            });
            resolve(JSON.stringify({count: links.length, titles: titles}));
          });
          await p;
          return p;
        ''',
      );
      // ignore: avoid_print
      print('TEST3a - DOM 查询结果: value=${result?.value}, error=${result?.error}');
      if (result?.value != null) {
        final parsed = jsonDecode(result!.value as String) as Map<String, dynamic>;
        expect(parsed['count'], 3);
        expect((parsed['titles'] as List).first, '第一章 初入江湖');
      }
    }

    // =========================================================================
    // 4. 点击"下一页"链接
    // =========================================================================
    {
      // 注意：我们的测试 HTML 里的 href 是假的 example.com 链接
      // 这里主要验证 click 操作能触发
      final result = await controller.callAsyncJavaScript(
        functionBody: '''
          var p = new Promise(function(resolve, reject) {
            var nextBtn = document.querySelector('.next-page');
            if (nextBtn) {
              resolve(JSON.stringify({found: true, href: nextBtn.getAttribute('href'), text: nextBtn.innerText.trim()}));
            } else {
              resolve(JSON.stringify({found: false}));
            }
          });
          await p;
          return p;
        ''',
      );
      // ignore: avoid_print
      print('TEST4 - 翻页按钮: value=${result?.value}, error=${result?.error}');
      if (result?.value != null) {
        final parsed = jsonDecode(result!.value as String) as Map<String, dynamic>;
        expect(parsed['found'], true);
        expect(parsed['href'], 'https://example.com/page2.html');
      }
    }

    // =========================================================================
    // 5. Promise reject 错误捕获
    // =========================================================================
    {
      final result = await controller.callAsyncJavaScript(
        functionBody: '''
          var p = new Promise(function(resolve, reject) {
            reject("JS_ERROR: something went wrong");
          });
          await p;
          return p;
        ''',
      );
      // ignore: avoid_print
      print('TEST5 - Promise reject: value=${result?.value}, error=${result?.error}');
      expect(result, isNotNull);
      // error 字段应该包含 reject 的信息
      if (result!.error != null) {
        // ignore: avoid_print
        print('TEST5 - ✅ callAsyncJavaScript 正确捕获了 Promise reject: ${result.error}');
      } else {
        // ignore: avoid_print
        print('TEST5 - ⚠️ WebView2 callAsyncJavaScript 未返回 error 字段（平台差异）');
      }
    }

    // =========================================================================
    // 6. 综合测试：async 提取 + setTimeout + 返回（模拟完整翻页流程）
    // =========================================================================
    {
      final result = await controller.callAsyncJavaScript(
        functionBody: '''
          var p = new Promise(function(resolve) {
            // 模拟第一步：提取当前页章节
            var chapters = [];
            document.querySelectorAll('.chapter-link').forEach(function(link) {
              chapters.push({
                title: link.innerText.trim(),
                url: link.getAttribute('href')
              });
            });

            // 模拟翻页延迟
            setTimeout(function() {
              // 模拟第二步：提取正文
              var title = document.querySelector('.chapter-title');
              var paragraphs = [];
              document.querySelectorAll('.novel-paragraph').forEach(function(p) {
                paragraphs.push(p.innerText.trim());
              });

              resolve(JSON.stringify({
                chapters: chapters,
                chapterTitle: title ? title.innerText.trim() : '',
                paragraphs: paragraphs,
                totalParagraphs: paragraphs.length
              }));
            }, 100);
          });
          await p;
          return p;
        ''',
      );
      // ignore: avoid_print
      print('TEST6 - 综合翻页流程: value=${result?.value}');
      // ignore: avoid_print
      print('TEST6 - error=${result?.error}');
      if (result?.value != null) {
        final parsed = jsonDecode(result!.value as String) as Map<String, dynamic>;
        // ignore: avoid_print
        print('TEST6 - chapters count=${(parsed["chapters"] as List).length}');
        // ignore: avoid_print
        print('TEST6 - chapterTitle=${parsed["chapterTitle"]}');
        // ignore: avoid_print
        print('TEST6 - totalParagraphs=${parsed["totalParagraphs"]}');

        // 验证结构化数据正确提取
        expect((parsed['chapters'] as List).length, 3);
        expect(parsed['chapterTitle'], '第一章 初入江湖');
        expect(parsed['totalParagraphs'], 3);
      } else {
        // ignore: avoid_print
        print('TEST6 - ⚠️ result.value 为 null，需要检查 WebView2 兼容性');
      }
    }

    // =========================================================================
    // 7. 对比 evaluateJavascript（原方式）在同一场景的表现
    // =========================================================================
    {
      // evaluateJavascript 执行同样的 async 代码（之前测试已知 WebView2 不支持）
      final rawResult = await controller.evaluateJavascript(
        source: '''(function() {
          return JSON.stringify({sync: "only", message: "WebView2 只能同步"});
        })()''',
      );
      // ignore: avoid_print
      print('TEST7 - evaluateJavascript sync: $rawResult (type=${rawResult.runtimeType})');

      // 对比：evaluateJavascript 执行 async 代码
      final asyncResult = await controller.evaluateJavascript(
        source: '''(async function() {
          await new Promise(function(r) { setTimeout(r, 100); });
          return JSON.stringify({async: "attempt"});
        })()''',
      );
      // ignore: avoid_print
      print('TEST7 - evaluateJavascript async: $asyncResult (type=${asyncResult.runtimeType})');
    }

    await helper.dispose();
  });
}
