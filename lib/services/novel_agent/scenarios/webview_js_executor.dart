/// WebView JS 脚本执行工具
///
/// 把 `WebViewExtractScenario` 中的核心纯函数抽出来，
/// 供场景内（ReAct 循环）和场景外（FAB「添加小说」按钮）共用。
///
/// ## 用法
///
/// ```dart
/// // 1. 校验
/// final error = WebViewJsExecutor.validateScript(script);
/// if (error != null) throw 'SCRIPT_VALIDATION_FAILED: $error';
///
/// // 2. 替换 {{URL}} 占位符
/// final resolved = script.replaceAll('{{URL}}', currentUrl);
///
/// // 3. 提取 IIFE 函数体
/// final functionBody = WebViewJsExecutor.extractAsyncFunctionBody(resolved);
///
/// // 4. 执行
/// final result = await controller.callAsyncJavaScript(
///   functionBody: functionBody,
/// ).timeout(Duration(seconds: 120));
///
/// // 5. 解析返回值
/// final jsonStr = WebViewJsExecutor.stringifyJsResult(result?.value);
/// final data = jsonDecode(jsonStr);
/// ```
library;

import 'dart:convert';

class WebViewJsExecutor {
  const WebViewJsExecutor._();

  /// 校验脚本是否符合 `{{URL}}` 占位符规范
  ///
  /// 返回 `null` 表示通过；返回字符串表示具体的校验错误。
  static String? validateScript(String script) {
    // 1. 必须包含 {{URL}} 占位符
    if (!script.contains('{{URL}}')) {
      return '脚本缺少 {{URL}} 占位符。'
          "请在脚本开头声明: const PAGE_URL = '{{URL}}'; "
          '并在脚本中使用 PAGE_URL 代替硬编码 URL';
    }

    // 2. 禁止硬编码过多完整 URL
    final hardcodedUrlPattern = RegExp(r'https?://[^\s<>]+');
    final hardcodedUrls = hardcodedUrlPattern
        .allMatches(script)
        .where((m) => !m.group(0)!.contains('{{'))
        .map((m) => m.group(0)!)
        .toList();
    if (hardcodedUrls.length > 2) {
      return '脚本中包含 ${hardcodedUrls.length} 个硬编码 URL（最多允许 2 个），'
          '请使用 PAGE_URL 变量代替。'
          '检测到的 URL: ${hardcodedUrls.take(3).join(", ")}';
    }

    // 3. 禁止使用 window.location.href / document.URL / location.href
    if (script.contains('window.location.href') ||
        script.contains('document.URL') ||
        script.contains('location.href')) {
      return '脚本中禁止使用 window.location.href/document.URL/location.href，'
          '请统一使用 PAGE_URL 变量（从 {{URL}} 占位符获取）';
    }

    // 4. 禁止数据外发通道（2026-09 审查 P1：脚本运行在目标站 origin，
    //    能拿到用户在该站的登录态；凭 Cookie/存储/beacon 外发即窃取会话）。
    //    提取任务只需读 DOM，任何跨域外发/凭据访问都没有正当用途。
    for (final entry in _exfiltrationPatterns.entries) {
      for (final token in entry.value) {
        if (script.contains(token)) {
          return '脚本中禁止使用 ${entry.key}（检测到 "$token"）。'
              '提取脚本只允许读取页面 DOM 并 return 结果，'
              '不允许访问 Cookie/存储或向任何地址发送数据。';
        }
      }
    }

    return null;
  }

  /// 数据外发通道静态拒绝清单：类别 → token 列表。
  /// 子串匹配与规则 3 同强度；运行期另有同源守卫兜底（见
  /// [buildSandboxPreamble]），两层独立生效。
  static const Map<String, List<String>> _exfiltrationPatterns = {
    'Cookie 访问': ['document.cookie', "document['cookie']", 'document[ "cookie" ]'],
    '本地存储': [
      'localStorage',
      'sessionStorage',
      'indexedDB',
      'caches.open',
    ],
    '数据外发': [
      'sendBeacon',
      'new WebSocket',
      'WebSocket(',
      'new EventSource',
      'EventSource(',
      'import(',
    ],
    '页面跳转': ['window.open'],
  };

  /// 运行时同源守卫前导代码（叠加在脚本函数体最前面执行）。
  ///
  /// 静态清单可被字符串拼接等手段绕过，这里在执行环境内再拦一层：
  /// - fetch / XMLHttpRequest：仅允许与 PAGE_URL 同源的请求
  ///   （提取站自身接口可用，第三方域一律抛错）
  /// - sendBeacon：直接禁用
  /// PAGE_URL 由脚本自身声明（校验规则 1 强制），守卫在**调用时**才读取，
  /// 因此前导代码可以放在声明之前。
  static String buildSandboxPreamble() {
    return '''
/* ==== Whimread 沙箱守卫（自动注入，请勿修改/删除） ==== */
(() => {
  const __wrGuard = (u) => {
    try {
      if (typeof PAGE_URL === 'undefined') return;
      const target = new URL(String(u), PAGE_URL);
      const origin = new URL(PAGE_URL).origin;
      if (target.origin !== origin) {
        throw new Error('WHIMREAD_SANDBOX: 跨域请求被禁止: ' + target.origin);
      }
    } catch (e) {
      if (String(e && e.message || '').startsWith('WHIMREAD_SANDBOX')) throw e;
    }
  };
  try {
    if (typeof window !== 'undefined' && typeof window.fetch === 'function') {
      const __wrFetch = window.fetch.bind(window);
      window.fetch = async (input, init) => {
        const u = typeof input === 'string' ? input
          : (input && typeof input === 'object' && input.url) ? input.url : '';
        __wrGuard(u);
        return __wrFetch(input, init);
      };
    }
    if (typeof XMLHttpRequest !== 'undefined') {
      const __wrOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (m, u) {
        __wrGuard(u);
        return __wrOpen.apply(this, arguments);
      };
    }
    if (typeof navigator !== 'undefined' && navigator.sendBeacon) {
      navigator.sendBeacon = () => {
        throw new Error('WHIMREAD_SANDBOX: sendBeacon 被禁止');
      };
    }
  } catch (e) { /* 守卫自身失败不阻断提取 */ }
})();
/* ==== 沙箱守卫结束 ==== */
''';
  }

  /// 将 Agent 生成的 IIFE 脚本转换为 callAsyncJavaScript 函数体
  ///
  /// callAsyncJavaScript(functionBody: body) 会包裹为:
  ///   async function(...){ `body` }
  ///
  /// Agent 生成的脚本有两种格式：
  ///   1. async IIFE: `(async function() { ... })()` → 提取内部函数体
  ///   2. 同步 IIFE: `(function() { ... })()` → 提取内部函数体
  ///   3. 非包裹的函数体 → 原样返回（兼容）
  ///
  /// 返回的函数体首部注入同源守卫前导（[buildSandboxPreamble]）。
  static String extractAsyncFunctionBody(String script) {
    final trimmed = script.trim();

    // 匹配 (async function() { ... })() 或 (async function(){...})()
    // 也匹配 (function() { ... })() 同步 IIFE
    final iifePattern = RegExp(
      r'^\(\s*(?:async\s+)?function\s*\([^)]*\)\s*\{',
    );
    final match = iifePattern.firstMatch(trimmed);
    if (match == null) return script;

    // 找到第一个 { 的位置
    final firstBrace = trimmed.indexOf('{', match.start);
    if (firstBrace == -1) return script;

    // 找到匹配的最后一个 }（去掉末尾的 )()
    var depth = 0;
    var lastBrace = -1;
    for (var i = firstBrace; i < trimmed.length; i++) {
      if (trimmed[i] == '{') {
        depth++;
      } else if (trimmed[i] == '}') {
        depth--;
        if (depth == 0) {
          lastBrace = i;
          break;
        }
      }
    }

    if (lastBrace == -1) return script;

    // 提取 { } 之间的内容（去掉外层花括号），首部注入同源守卫前导
    final body = trimmed.substring(firstBrace + 1, lastBrace).trim();
    return buildSandboxPreamble() + body;
  }

  /// 将 callAsyncJavaScript 返回值统一转为 JSON 字符串
  ///
  /// - JS 返回 JSON.stringify(...) → value 是 String
  /// - JS 返回普通对象 → value 可能是 Map/List
  /// - JS 返回 null → value 是 null
  static String stringifyJsResult(dynamic result) {
    if (result == null) return jsonEncode({'result': null});
    if (result is String) return result;
    return jsonEncode(result);
  }
}
