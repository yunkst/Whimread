/// OCR PUA 字符渲染器（WebView 端共享实现）。
///
/// 封装 "渲染单个 PUA 码点为 base64 PNG" 的通用流程：
/// buildOcrRenderJs → extractAsyncFunctionBody → callAsyncJavaScript(30s)
/// → error/null 检查 → 返回 base64 字符串。
///
/// 供 HeadlessWebViewContentService / HeadlessWebViewChapterListService /
/// site_script_panel 共用，避免 4 处重复实现。
///
/// 注意：WebViewExtractScenario._renderPuaViaController 保留独立实现——
/// 它有 pre/post 诊断探针用于诊断 ocr_verify_timeout，核心逻辑与本文件相同
/// 但包装了大量诊断代码，不宜合并。
library;

import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/novel_agent/scenarios/webview_js_executor.dart';
import 'ocr_render_js.dart';

/// 在 [controller] 上渲染单个 PUA 码点，返回 base64 PNG 字符串（不带 data: 前缀）。
///
/// 流程：
/// 1. buildOcrRenderJs(codepoint, fontFamily) → JS 模板
/// 2. WebViewJsExecutor.extractAsyncFunctionBody → callAsyncJavaScript 函数体
/// 3. controller.callAsyncJavaScript(functionBody: ...).timeout(30s)
/// 4. result 校验 → 返回 base64 或抛异常
///
/// 抛出：
/// - [TimeoutException]：渲染超时（>30s）
/// - [Exception]：result 为空、JS 执行错误、或返回值非 String
Future<String> renderPuaViaController(
  InAppWebViewController controller,
  int codepoint,
  String fontFamily,
) async {
  final js = buildOcrRenderJs(codepoint, fontFamily);
  final functionBody = WebViewJsExecutor.extractAsyncFunctionBody(js);
  final result = await controller
      .callAsyncJavaScript(functionBody: functionBody)
      .timeout(const Duration(seconds: 30));
  if (result == null || result.error != null) {
    throw Exception('OCR 渲染失败 cp=$codepoint: ${result?.error}');
  }
  final value = result.value;
  if (value is String) return value;
  throw Exception('OCR 渲染返回非字符串: $value');
}