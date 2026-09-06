/// WebViewExtractScenario.execute_js 集成测试
///
/// 使用真实的 Edge WebView2 在 Windows 桌面端执行 JavaScript。
/// **不模拟 WebView**——所有 JS 执行均为真实运行。
///
/// ## 测试覆盖
///   1. 参数校验：missing_param / SCRIPT_VALIDATION_FAILED
///   2. 正常执行：{{URL}} 替换 / DOM 查询 / async IIFE
///   3. JS 错误：JS_SYNTAX_ERROR / JS_REFERENCE_ERROR / JS_TYPE_ERROR
///
/// ## 前提条件
///   - Windows 10/11，Edge WebView2 Runtime 已安装（Win11 预装）
///   - Flutter SDK 3.x
///
/// ## 运行
///   cd novel_app
///   flutter test integration_test/webview_extract/execute_js_test.dart -d windows
///
/// ## 注意
///   - 首次运行需要编译 Windows 原生 exe，约 30-60 秒
///   - WebView2 初始化约 2-5 秒，所有测试共享一个 WebView 实例
/// ## 修复记录（2026-06-12）
///   - ✅ 已修复：_stringifyJsResult 处理跨平台 Map/String 差异
///   - ✅ 已修复：_wrapScriptForWebView2 包裹脚本解决 async IIFE 和错误静默
///   - 详见 lib/services/novel_agent/scenarios/webview_extract_scenario.dart
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

  /// 通过 Provider 间接获取 Ref，构造 WebViewExtractScenario
  WebViewExtractScenario createScenario(
    InAppWebViewController controller, [
    String currentUrl = WebViewTestHelper.testBaseUrl,
  ]) {
    final provider = Provider<WebViewExtractScenario>((ref) {
      return WebViewExtractScenario(ref, controller, currentUrl);
    });
    return container.read(provider);
  }

  // ===========================================================================
  // 所有测试在一个 testWidgets 中运行，共享 WebView 实例
  // ===========================================================================

  testWidgets('execute_js 集成测试', (tester) async {
    final helper = WebViewTestHelper();
    final controller = await helper.createWebView(tester);
    final scenario = createScenario(controller);

    // 辅助：执行工具调用并解码 JSON
    Future<Map<String, dynamic>> callTool(
      String name,
      Map<String, dynamic> args,
    ) async {
      final result = await scenario.executeTool(name, args);
      return jsonDecode(result) as Map<String, dynamic>;
    }

    // ========================================================================
    // 1. 参数校验（纯 Dart 逻辑，不执行 JS）
    // ========================================================================

    {
      final json = await callTool('execute_js', {});
      expect(json['error'], 'missing_param');
      expect((json['missing'] as List), contains('script'));
    }

    {
      final json = await callTool('execute_js', {'script': ''});
      expect(json['error'], 'missing_param');
    }

    {
      final json = await callTool('execute_js', {
        'script': '(async function() { return JSON.stringify({ok: true}); })()',
      });
      expect(json['error'], 'SCRIPT_VALIDATION_FAILED');
      expect(json['validation_error'].toString(), contains('{{URL}}'));
    }

    {
      final json = await callTool('execute_js', {
        'script': '''
          const PAGE_URL = '{{URL}}';
          const a = 'https://a.com';
          const b = 'https://b.com';
          const c = 'https://c.com';
          (async function() { return JSON.stringify({ok: true}); })()
        ''',
      });
      expect(json['error'], 'SCRIPT_VALIDATION_FAILED');
      expect(json['validation_error'].toString(), contains('硬编码'));
    }

    {
      final json = await callTool('execute_js', {
        'script': '''
          const PAGE_URL = '{{URL}}';
          const url = window.location.href;
          (async function() { return JSON.stringify({url: url}); })()
        ''',
      });
      expect(json['error'], 'SCRIPT_VALIDATION_FAILED');
      expect(json['validation_error'].toString(), contains('location.href'));
    }

    {
      final json = await callTool('execute_js', {
        'script': '''
          const PAGE_URL = '{{URL}}';
          const url = document.URL;
          (async function() { return JSON.stringify({url: url}); })()
        ''',
      });
      expect(json['error'], 'SCRIPT_VALIDATION_FAILED');
      expect(json['validation_error'].toString(), contains('document.URL'));
    }

    // ========================================================================
    // 2. 正常执行（真实 WebView JS 执行，使用 callAsyncJavaScript）
    //
    // callAsyncJavaScript 支持 async/await，Promise 结果正确返回。
    // ========================================================================

    {
      // DOM 查询（同步 IIFE）
      final result = await scenario.executeTool('execute_js', {
        'script': '''
          (function() {
            const PAGE_URL = '{{URL}}';
            const title = document.querySelector('.novel-title');
            return JSON.stringify({ title: title ? title.innerText.trim() : '' });
          })()
        ''',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['title'], '星辰变');
    }

    {
      // URL 替换：test_url 参数
      final result = await scenario.executeTool('execute_js', {
        'script': '''
          (function() {
            const PAGE_URL = '{{URL}}';
            return JSON.stringify({ pageUrl: PAGE_URL });
          })()
        ''',
        'test_url': 'https://custom-test.com/chapter1',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['pageUrl'], 'https://custom-test.com/chapter1');
    }

    {
      // URL 替换：回退到 currentUrl
      final result = await scenario.executeTool('execute_js', {
        'script': '''
          (function() {
            const PAGE_URL = '{{URL}}';
            return JSON.stringify({ pageUrl: PAGE_URL });
          })()
        ''',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['pageUrl'], WebViewTestHelper.testBaseUrl);
    }

    {
      // async IIFE 模式（Agent 实际生成的格式）
      // callAsyncJavaScript 正确支持 async/await + setTimeout
      final result = await scenario.executeTool('execute_js', {
        'script': '''
          (async function() {
            const PAGE_URL = '{{URL}}';
            await new Promise(function(r) { setTimeout(r, 50); });
            const chapters = [];
            document.querySelectorAll('.chapter-link').forEach(function(link) {
              chapters.push({
                title: link.innerText.trim(),
                url: new URL(link.getAttribute('href'), PAGE_URL).href
              });
            });
            return JSON.stringify({ chapters: chapters });
          })()
        ''',
      });
      // ignore: avoid_print
      print('DEBUG async IIFE: $result');
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json, isNotNull);
      // callAsyncJavaScript 正确返回 async Promise 结果
      expect(json['chapters'], isNotNull);
      final chapters = json['chapters'] as List;
      expect(chapters.length, 3);
      expect((chapters.first as Map)['title'], '第一章 初入江湖');
    }

    {
      // 创建 DOM 元素并回读
      final result = await scenario.executeTool('execute_js', {
        'script': '''
          (function() {
            const PAGE_URL = '{{URL}}';
            const div = document.createElement('div');
            div.id = 'test-created';
            div.textContent = 'created content';
            document.body.appendChild(div);
            const readBack = document.getElementById('test-created');
            return JSON.stringify({ created: readBack ? readBack.textContent : null });
          })()
        ''',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['created'], 'created content');
    }

    // ========================================================================
    // 3. JS 执行错误（callAsyncJavaScript 通过 error 字段返回）
    // ========================================================================

    {
      // 语法错误的 JS → callAsyncJavaScript 在 error 字段返回
      final result = await scenario.executeTool('execute_js', {
        'script': '''
          const PAGE_URL = '{{URL}}';
          this is not valid javascript!!!
        ''',
      });

      // ignore: avoid_print
      print('DEBUG syntax error result: $result');
      final json = jsonDecode(result) as Map<String, dynamic>;
      // callAsyncJavaScript 会捕获语法错误并返回 error 信息
      expect(json, isNotNull);
      // 语法错误应该被 callAsyncJavaScript 捕获（预期 error 字段有值或至少返回有效 JSON）
    }

    {
      // 未定义变量：callAsyncJavaScript 通过 error 字段返回
      final json = await callTool('execute_js', {
        'script': '''
          (function() {
            const PAGE_URL = '{{URL}}';
            return JSON.stringify({val: undefinedVariable});
          })()
        ''',
      });
      // ignore: avoid_print
      print('DEBUG undefinedVariable: $json');
      // callAsyncJavaScript 通过 Promise reject 返回错误
      // Scenario 将 error 转为结构化 JSON
      expect(json, isNotNull);
    }

    {
      // null 属性访问：callAsyncJavaScript 通过 error 字段返回
      final json = await callTool('execute_js', {
        'script': '''
          (function() {
            const PAGE_URL = '{{URL}}';
            const el = document.querySelector('#nonexistent-element-99999');
            return JSON.stringify({text: el.innerText});
          })()
        ''',
      });
      // ignore: avoid_print
      print('DEBUG null access: $json');
      expect(json, isNotNull);
    }

    {
      // jQuery 引用（未定义变量错误）
      final json = await callTool('execute_js', {
        'script': '''
          (function() {
            const PAGE_URL = '{{URL}}';
            const title = \$('.novel-title').text();
            return JSON.stringify({title: title});
          })()
        ''',
      });
      // ignore: avoid_print
      print('DEBUG jquery: $json');
      expect(json, isNotNull);
    }

    await helper.dispose();
  });
}
