/// WebView 提取场景的 JS 错误解析
///
/// 从 `WebViewExtractScenario` 抽出的独立职责：把 WebView / Dart 层抛出的
/// JS 异常文本解析为结构化诊断（错误码 + 消息 + 修复建议），
/// 供 execute_js / save_script 的错误出口复用。
///
/// 纯函数、无状态，不依赖 WebView 或 Riverpod。
library;

/// JS 异常的结构化诊断结果
typedef WebViewExtractJsErrorDiagnosis = ({
  String code,
  String message,
  String suggestion,
});

/// JS 错误解析器（纯静态）
abstract final class WebViewExtractJsDiagnostics {
  /// 解析 WebView 抛出的 JS 异常，按错误类型给出针对性修复建议
  static WebViewExtractJsErrorDiagnosis parseJsError(
    String raw,
    String script,
  ) {
    final lowerRaw = raw.toLowerCase();

    // 语法错误
    if (lowerRaw.contains('syntaxerror')) {
      return (
        code: 'JS_SYNTAX_ERROR',
        message: '脚本有语法错误',
        suggestion:
            '检查括号/引号是否配对，async IIFE 格式是否正确: (async function(){...})()',
      );
    }

    // 引用错误（未定义变量 / 第三方库）
    if (lowerRaw.contains('referenceerror')) {
      // 提取出错的变量名
      final match = RegExp(r"(\w+)\s+is\s+not\s+defined").firstMatch(raw);
      final varName = match?.group(1);
      final isLibHint = varName != null &&
          (varName == r'$' ||
              varName == 'jQuery' ||
              varName == '_' ||
              varName == 'Vue' ||
              varName == 'React');
      return (
        code: 'JS_REFERENCE_ERROR',
        message: varName != null
            ? '引用了未定义的变量: $varName'
            : '引用了未定义的变量',
        suggestion: isLibHint
            ? '目标网站没有加载 $varName 等第三方库，请改用原生 DOM API (document.querySelector, innerText, etc.)'
            : '检查变量名拼写是否正确，注意 IIFE 内是独立作用域，外部 const/let 无法直接访问',
      );
    }

    // 类型错误
    if (lowerRaw.contains('typeerror')) {
      // 提取"Cannot read properties of XXX (reading 'yyy')"
      final nullMatch =
          RegExp(r"Cannot read propert(?:y|ies) of (null|undefined)").firstMatch(raw);
      final isNullAccess = nullMatch != null;
      return (
        code: 'JS_TYPE_ERROR',
        message: isNullAccess
            ? '访问了 null/undefined 对象的属性'
            : '类型错误',
        suggestion: isNullAccess
            ? 'querySelector 可能返回 null。访问前加判断: const el = document.querySelector("..."); if (el) { ... }'
            : '检查对象/数组的访问方式是否正确，必要时加 typeof 或 instanceof 判断',
      );
    }

    // Dart 侧类型转换错误：evaluateJavascript 返回了 Map 而非 String
    // 典型错误: "type '_Map<String, dynamic>' is not a subtype of type 'FutureOr<String>'"
    if (raw.contains('_Map<String, dynamic>') ||
        raw.contains('FutureOr<String>')) {
      return (
        code: 'JS_TYPE_ERROR',
        message: '脚本返回了 JSON 对象而非字符串',
        suggestion:
            '脚本必须返回字符串（用 JSON.stringify 包装返回值）。例如: return JSON.stringify({title: ..., content: ...})',
      );
    }

    // 超时（被外层 catch 捕获前）
    if (lowerRaw.contains('timeout')) {
      return (
        code: 'JS_TIMEOUT',
        message: '脚本执行超时',
        suggestion:
            '在长循环中加 await new Promise(r => setTimeout(r, 100)) 让出主线程，避免阻塞 WebView',
      );
    }

    return (
      code: 'JS_RUNTIME_ERROR',
      message: '脚本执行失败: $raw',
      suggestion:
          '根据错误信息修正后重试。如果连续失败 3 次，建议换一种思路（如换选择器、简化提取逻辑）',
    );
  }
}
