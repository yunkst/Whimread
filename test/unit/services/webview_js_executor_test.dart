/// WebViewJsExecutor 单元测试
///
/// 测试三个纯静态方法：
///   - validateScript：校验 {{URL}} 占位符、硬编码 URL、禁止 API
///   - extractAsyncFunctionBody：IIFE → 函数体提取
///   - stringifyJsResult：callAsyncJavaScript 返回值统一化
///
/// 运行：
///   flutter test test/unit/services/webview_js_executor_test.dart
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/scenarios/webview_js_executor.dart';

void main() {
  // ===================================================================
  // validateScript
  // ===================================================================
  group('WebViewJsExecutor.validateScript', () {
    test('合法脚本（含 {{URL}}）→ 返回 null', () {
      const script = """
        (async function() {
          const PAGE_URL = '{{URL}}';
          return JSON.stringify({title: 'test'});
        })()
      """;
      expect(WebViewJsExecutor.validateScript(script), isNull);
    });

    test('缺少 {{URL}} 占位符 → 返回错误描述', () {
      const script = """
        (async function() {
          return JSON.stringify({title: 'test'});
        })()
      """;
      final error = WebViewJsExecutor.validateScript(script);
      expect(error, isNotNull);
      expect(error, contains('{{URL}}'));
    });

    test('空脚本 → 返回错误', () {
      final error = WebViewJsExecutor.validateScript('');
      expect(error, isNotNull);
    });

    test('包含 window.location.href → 返回错误', () {
      const script = """
        (async function() {
          const PAGE_URL = '{{URL}}';
          const url = window.location.href;
          return JSON.stringify({url: url});
        })()
      """;
      final error = WebViewJsExecutor.validateScript(script);
      expect(error, isNotNull);
      expect(error, contains('window.location.href'));
    });

    test('包含 document.URL → 返回错误', () {
      const script = """
        (async function() {
          const PAGE_URL = '{{URL}}';
          const url = document.URL;
          return JSON.stringify({});
        })()
      """;
      final error = WebViewJsExecutor.validateScript(script);
      expect(error, isNotNull);
      expect(error, contains('document.URL'));
    });

    test('包含 location.href → 返回错误', () {
      const script = """
        (async function() {
          const PAGE_URL = '{{URL}}';
          const url = location.href;
          return JSON.stringify({});
        })()
      """;
      final error = WebViewJsExecutor.validateScript(script);
      expect(error, isNotNull);
      expect(error, contains('location.href'));
    });

    test('硬编码 URL ≤ 2 个 → 通过', () {
      // 2 个硬编码 URL（如广告过滤域名）是允许的
      const script = """
        (async function() {
          const PAGE_URL = '{{URL}}';
          const adDomains = ['https://ads.example.com', 'https://tracker.example.com'];
          return JSON.stringify({title: 'ok'});
        })()
      """;
      expect(WebViewJsExecutor.validateScript(script), isNull);
    });

    test('硬编码 URL > 2 个 → 返回错误', () {
      const script = """
        (async function() {
          const PAGE_URL = '{{URL}}';
          const urls = [
            'https://a.com/ch1',
            'https://a.com/ch2',
            'https://a.com/ch3'
          ];
          return JSON.stringify({});
        })()
      """;
      final error = WebViewJsExecutor.validateScript(script);
      expect(error, isNotNull);
      expect(error, contains('硬编码 URL'));
    });

    test('含 {{URL}} 的 URL 不计入硬编码数量', () {
      // {{URL}} 中包含 https:// 前缀，但应被排除
      const script = """
        (async function() {
          const PAGE_URL = '{{URL}}';
          const base = 'https://ads.example.com';
          return JSON.stringify({title: 'ok'});
        })()
      """;
      expect(WebViewJsExecutor.validateScript(script), isNull);
    });
  });

  // ===================================================================
  // extractAsyncFunctionBody
  // ===================================================================
  group('WebViewJsExecutor.extractAsyncFunctionBody', () {
    test('async IIFE → 提取函数体', () {
      const script = "(async function() {\n  return 42;\n})()";
      final body = WebViewJsExecutor.extractAsyncFunctionBody(script);
      expect(body, endsWith('return 42;'));
    });

    test('sync IIFE → 提取函数体', () {
      const script = "(function() {\n  return 'hello';\n})()";
      final body = WebViewJsExecutor.extractAsyncFunctionBody(script);
      expect(body, endsWith("return 'hello';"));
    });

    test('带参数的 async IIFE → 提取函数体', () {
      const script = "(async function(x, y) {\n  return x + y;\n})()";
      final body = WebViewJsExecutor.extractAsyncFunctionBody(script);
      expect(body, endsWith('return x + y;'));
    });

    test('非 IIFE 格式 → 原样返回', () {
      const script = "const x = 42; return x;";
      final body = WebViewJsExecutor.extractAsyncFunctionBody(script);
      expect(body, equals(script));
    });

    test('嵌套花括号 → 正确匹配最外层', () {
      const script = """
(async function() {
  if (true) {
    for (let i = 0; i < 10; i++) {
      console.log(i);
    }
  }
  return 'done';
})()
""";
      final body = WebViewJsExecutor.extractAsyncFunctionBody(script).trim();
      // 前导守卫之后才是脚本体;守卫自身的 IIFE 结尾含 })()，先剥离再断言
      final codeOnly = body
          .substring(body.indexOf('/* ==== 沙箱守卫结束 ==== */'))
          .trim();
      expect(codeOnly, contains('if (true)'));
      expect(codeOnly, contains('for (let i'));
      expect(codeOnly, contains("return 'done';"));
      // 不应包含外层的 })()
      expect(codeOnly, isNot(contains('})()')));
    });

    test('Agent 实际生成的脚本格式 → 正确提取', () {
      const script = """
(async function() {
  const PAGE_URL = '{{URL}}';
  const chapters = [];
  document.querySelectorAll('.chapter-link').forEach(function(link) {
    chapters.push({
      title: link.innerText.trim(),
      url: new URL(link.getAttribute('href'), PAGE_URL).href
    });
  });
  const titleEl = document.querySelector('.novel-title');
  const title = titleEl ? titleEl.innerText.trim() : '';
  return JSON.stringify({ title: title, chapters: chapters });
})()
""";
      final body = WebViewJsExecutor.extractAsyncFunctionBody(script);
      expect(body, contains("const PAGE_URL = '{{URL}}';"));
      expect(body, contains('querySelectorAll'));
      expect(body, contains('return JSON.stringify'));
      final codeOnly = body
          .substring(body.indexOf('/* ==== 沙箱守卫结束 ==== */'))
          .trim();
      expect(codeOnly, isNot(contains('(async function')));
      expect(codeOnly, isNot(contains('})()')));
    });

    test('前后有空白字符 → 正确处理', () {
      const script = '  \n (async function() {\n  return 1;\n })()  \n ';
      final body = WebViewJsExecutor.extractAsyncFunctionBody(script);
      expect(body, endsWith('return 1;'));
    });

    test('空函数体 → 返回沙箱前导', () {
      const script = '(async function() {})()';
      final body = WebViewJsExecutor.extractAsyncFunctionBody(script);
      expect(body, isNotEmpty);
    });
  });

  // ===================================================================
  // 沙箱守卫（2026-09 审查 P1：数据外发/凭据访问防线）
  // ===================================================================
  group('WebViewJsExecutor 沙箱', () {
    test('validateScript: document.cookie → 拒绝', () {
      const script = """
        (async function() {
          const PAGE_URL = '{{URL}}';
          const c = document.cookie;
          return JSON.stringify({c: c});
        })()
      """;
      final error = WebViewJsExecutor.validateScript(script);
      expect(error, isNotNull);
      expect(error, contains('禁止'));
    });

    test('validateScript: localStorage / sessionStorage / indexedDB → 拒绝', () {
      for (final token in ['localStorage', 'sessionStorage', 'indexedDB']) {
        final script = """
        (async function() {
          const PAGE_URL = '{{URL}}';
          return JSON.stringify({v: window.$token.length});
        })()
      """;
        expect(WebViewJsExecutor.validateScript(script), isNotNull,
            reason: '$token 应被拒绝');
      }
    });

    test('validateScript: sendBeacon / WebSocket / EventSource → 拒绝', () {
      for (final token in ['navigator.sendBeacon', 'new WebSocket(', 'new EventSource(']) {
        final script = """
        (async function() {
          const PAGE_URL = '{{URL}}';
          $token;
          return JSON.stringify({});
        })()
      """;
        expect(WebViewJsExecutor.validateScript(script), isNotNull,
            reason: '$token 应被拒绝');
      }
    });

    test('extractAsyncFunctionBody: 注入同源守卫前导', () {
      const script = "(async function() {\n  const PAGE_URL = '{{URL}}';\n  return 1;\n})()";
      final body = WebViewJsExecutor.extractAsyncFunctionBody(script);
      expect(body, contains('WHIMREAD_SANDBOX'));
      expect(body.indexOf('WHIMREAD_SANDBOX'),
          lessThan(body.indexOf("const PAGE_URL")),
          reason: '守卫前导必须在脚本体之前');
    });

    test('守卫前导独立可执行（不依赖 PAGE_URL 声明即可定义）', () {
      final preamble = WebViewJsExecutor.buildSandboxPreamble();
      expect(preamble, contains('__wrGuard'));
      expect(preamble, contains('sendBeacon'));
      expect(preamble, contains('XMLHttpRequest'));
      expect(preamble, contains('fetch'));
    });
  });

  // ===================================================================
  // stringifyJsResult
  // ===================================================================
  group('WebViewJsExecutor.stringifyJsResult', () {
    test('null → {"result":null}', () {
      final result = WebViewJsExecutor.stringifyJsResult(null);
      expect(result, equals('{"result":null}'));
      // 验证是合法 JSON
      final parsed = jsonDecode(result);
      expect(parsed['result'], isNull);
    });

    test('String → 原样返回', () {
      const jsReturn = '{"title":"星辰变","chapters":[{"title":"第一章"}]}';
      final result = WebViewJsExecutor.stringifyJsResult(jsReturn);
      expect(result, equals(jsReturn));
      // 验证是合法 JSON
      final parsed = jsonDecode(result) as Map<String, dynamic>;
      expect(parsed['title'], '星辰变');
    });

    test('Map → jsonEncode', () {
      final mapReturn = {
        'title': '测试小说',
        'chapters': [
          {'title': '第一章', 'url': 'https://example.com/ch1'},
        ],
      };
      final result = WebViewJsExecutor.stringifyJsResult(mapReturn);
      final parsed = jsonDecode(result) as Map<String, dynamic>;
      expect(parsed['title'], '测试小说');
      expect((parsed['chapters'] as List).length, 1);
    });

    test('List → jsonEncode', () {
      final listReturn = [
        {'title': '第一章'},
        {'title': '第二章'},
      ];
      final result = WebViewJsExecutor.stringifyJsResult(listReturn);
      final parsed = jsonDecode(result) as List;
      expect(parsed.length, 2);
    });

    test('int → jsonEncode', () {
      final result = WebViewJsExecutor.stringifyJsResult(42);
      expect(result, equals('42'));
    });

    test('bool → jsonEncode', () {
      final result = WebViewJsExecutor.stringifyJsResult(true);
      expect(result, equals('true'));
    });
  });
}
