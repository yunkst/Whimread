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

  /// 安全地把 `{{URL}}` 占位符替换为 URL 字符串。
  ///
  /// 旧实现 `script.replaceAll('{{URL}}', url)` 存在两个风险：
  /// 1. URL 含 `'` / 反斜杠 / `}` 会破坏 JS 字符串字面量，导致脚本语法错误或
  ///    被 `extractAsyncFunctionBody` 误截断（按括号深度找 `}` 收尾）；
  /// 2. URL 含 `'); console.log(1); //` 之类可在 IIFE 内插入可执行语句。
  ///
  /// 这里用 [jsonEncode] 编码 URL，输出是合法 JS 字符串字面量（JSON 字符串
  /// 与 JS 字符串字面量完全等价），再用 [replaceAll] 替换 — 拼接出来的脚本
  /// 仍是合法 JS，URL 内容只会被当作字面量解释，不会逃逸。
  static String replaceUrlPlaceholder(String script, String url) {
    return script.replaceAll('{{URL}}', jsonEncode(url));
  }

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
  /// 静态清单可被字符串拼接等手段绕过，这里在执行环境内再拦一层。
  /// 覆盖范围（任一通道都被拦截 → 抛出 `WHIMREAD_SANDBOX:` 错误）：
  /// - fetch / XMLHttpRequest：仅允许与 PAGE_URL 同源的请求
  /// - navigator.sendBeacon：直接禁用
  /// - location.href 写入 / assign / replace：拦截跨域跳转
  /// - HTMLFormElement.submit：拦截表单跨域 POST
  /// - HTMLImageElement.src setter：拦截通过图片 GET 外发数据
  ///
  /// **默认拒绝策略**：守卫自身抛错（非 sandbox 错误）也按 deny 处理，
  /// 避免静默放行绕过（曾出现过 URL 解析异常被吞掉导致跨域请求通过）。
  /// PAGE_URL 由脚本自身声明（校验规则 1 强制），守卫在**调用时**才读取，
  /// 因此前导代码可以放在声明之前。
  static String buildSandboxPreamble() {
    return r'''
/* ==== Whimread 沙箱守卫（自动注入，请勿修改/删除） ==== */
(() => {
  const __wrSameOrigin = (u) => {
    if (typeof PAGE_URL === 'undefined' || !PAGE_URL) return true;
    let origin, target;
    try { origin = new URL(PAGE_URL).origin; } catch (_) { return true; }
    try { target = new URL(String(u), PAGE_URL).origin; } catch (_) { return false; }
    return target === origin;
  };
  const __wrDeny = (why) => {
    throw new Error('WHIMREAD_SANDBOX: ' + why);
  };
  const __wrGuard = (u, why) => {
    if (!__wrSameOrigin(u)) __wrDeny(why + ': ' + u);
  };
  try {
    // 1) fetch / XHR
    if (typeof window !== 'undefined' && typeof window.fetch === 'function') {
      const __wrFetch = window.fetch.bind(window);
      window.fetch = (input, init) => {
        const u = typeof input === 'string' ? input
          : (input && typeof input === 'object' && input.url) ? input.url : '';
        __wrGuard(u, 'fetch 跨域请求被禁止');
        return __wrFetch(input, init);
      };
    }
    if (typeof XMLHttpRequest !== 'undefined') {
      const __wrOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (m, u) {
        __wrGuard(u, 'XHR 跨域请求被禁止');
        return __wrOpen.apply(this, arguments);
      };
    }
    // 2) sendBeacon：直接禁用，不区分同异源
    if (typeof navigator !== 'undefined' && navigator.sendBeacon) {
      try {
        Object.defineProperty(navigator, 'sendBeacon', {
          configurable: false,
          value: () => { __wrDeny('sendBeacon 被禁止'); },
        });
      } catch (_) {
        navigator.sendBeacon = () => { __wrDeny('sendBeacon 被禁止'); };
      }
    }
    // 3) location 导航：拦截跨域跳转与赋值
    if (typeof window !== 'undefined' && window.location) {
      try {
        const locProto = Object.getPrototypeOf(window.location);
        if (locProto && !Object.getOwnPropertyDescriptor(locProto, '__wrPatched')) {
          const wrap = (fn) => function (url) {
            if (typeof url === 'string') __wrGuard(url, 'location 跨域跳转被禁止');
            return fn.apply(this, arguments);
          };
          try { locProto.assign = wrap(locProto.assign); } catch (_) {}
          try { locProto.replace = wrap(locProto.replace); } catch (_) {}
          Object.defineProperty(locProto, '__wrPatched', { value: true });
        }
      } catch (_) {}
    }
    // 4) HTMLFormElement.submit：拦截表单 POST 外发
    if (typeof HTMLFormElement !== 'undefined' && HTMLFormElement.prototype) {
      const __wrFormSubmit = HTMLFormElement.prototype.submit;
      HTMLFormElement.prototype.submit = function () {
        try { __wrGuard(this.action || window.location.href, 'form.submit 跨域被禁止'); }
        catch (e) { throw e; }
        return __wrFormSubmit.apply(this, arguments);
      };
    }
    // 5) HTMLImageElement.src setter：拦截图片 GET 外发
    if (typeof HTMLImageElement !== 'undefined') {
      const proto = HTMLImageElement.prototype;
      const desc = Object.getOwnPropertyDescriptor(proto, 'src');
      if (desc && desc.set && !desc.set.__wrPatched) {
        const origSet = desc.set;
        const guardedSet = function (v) {
          if (typeof v === 'string') {
            try { __wrGuard(v, 'Image.src 跨域被禁止'); }
            catch (e) { throw e; }
          }
          return origSet.call(this, v);
        };
        guardedSet.__wrPatched = true;
        Object.defineProperty(proto, 'src', {
          get: desc.get, set: guardedSet,
          configurable: desc.configurable, enumerable: desc.enumerable,
        });
      }
    }
  } catch (e) {
    // 守卫自身初始化失败：拒绝执行以避免安全降级
    throw new Error('WHIMREAD_SANDBOX: 守卫初始化失败 ' + (e && e.message || e));
  }
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
  ///   3. 非包裹的函数体 → 原样保留（兼容）
  ///
  /// 返回的函数体首部注入同源守卫前导（[buildSandboxPreamble]）。
  /// 所有路径（含回退）都必须注入：守卫是运行时唯一的网络出口拦截，
  /// 漏注入等于沙箱旁路。
  static String extractAsyncFunctionBody(String script) {
    final trimmed = script.trim();

    // 匹配 (async function() { ... })() 或 (async function(){...})()
    // 也匹配 (function() { ... })() 同步 IIFE
    final iifePattern = RegExp(
      r'^\(\s*(?:async\s+)?function\s*\([^)]*\)\s*\{',
    );
    final match = iifePattern.firstMatch(trimmed);
    if (match == null) return buildSandboxPreamble() + trimmed;

    // 找到第一个 { 的位置
    final firstBrace = trimmed.indexOf('{', match.start);
    if (firstBrace == -1) return buildSandboxPreamble() + trimmed;

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

    if (lastBrace == -1) return buildSandboxPreamble() + trimmed;

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
