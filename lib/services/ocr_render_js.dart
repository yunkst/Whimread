/// 系统内置 OCR-JS：在已加载反爬字体的 WebView 页面上，
/// 用 canvas 渲染单个 PUA 码点 -> toDataURL -> 返回 base64 PNG（不带前缀）。
///
/// **关键**：canvas 不自动继承 @font-face，必须显式 `ctx.font = '80px <反爬字体族名>'`。
/// spike 验证：`80px sans-serif` 时四个不同 PUA 渲染出完全相同占位框（失败）；
/// `80px <反爬字体族名>` 时渲染出四个不同字形（成功）。
///
/// **重要**：`{{FONT_FAMILY}}` 注入的值来自 `getComputedStyle().fontFamily`，
/// 可能含双引号和逗号（如 `DNMrHsV173Pd4pgy, "PingFang SC", sans-serif`），
/// 直接拼到 JS 字符串字面量 `"{{FONT_FAMILY}}"` 会导致**语法错误**——
/// 内层双引号提前结束字符串。而 Android 的 callAsyncJavaScript 在语法错误时
/// 整个外层 async wrapper 解析失败，`.then`/`.catch` 都不执行，callHandler
/// 永不触发 → Dart 侧 Future 永不 complete → 卡到 30s timeout
/// （表现为 ocr_verify_timeout）。
///
/// 因此 [buildOcrRenderJs] 把 fontFamily 编码为**十六进制字符码序列**注入，
/// JS 侧用 String.fromCodePoint 还原。十六进制只含 `[0-9a-f,]`，绝对安全，
/// 不依赖 JS 字符串字面量的引号转义。
///
/// `{{CODEPOINT}}` 由 [buildOcrRenderJs] 替换为十六进制字面量（如 `0xE3E9`），直接内联。
/// 本 JS **不走 `WebViewJsExecutor.validateScript`**（该函数强制 {{URL}} 会误杀），
/// 调用方直接 `callAsyncJavaScript(functionBody: js)`。
library;

const String ocrRenderJsTemplate = r'''
(async function() {
  await document.fonts.ready;
  const cp = {{CODEPOINT}};
  const fontFamily = String.fromCodePoint(...[{{FONT_FAMILY_CODES}}]);
  const canvas = document.createElement('canvas');
  canvas.width = 120; canvas.height = 120;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#FFFFFF'; ctx.fillRect(0, 0, 120, 120);
  ctx.fillStyle = '#000000';
  ctx.font = '80px ' + fontFamily;
  ctx.textBaseline = 'middle'; ctx.textAlign = 'center';
  ctx.fillText(String.fromCodePoint(cp), 60, 60);
  return canvas.toDataURL('image/png').split(',')[1];
})()
''';

/// 把 [codepoint] 和 [fontFamily] 注入模板，返回可执行的 async IIFE JS。
///
/// **注意**：[fontFamily] 来自 `getComputedStyle().fontFamily`，可能含双引号/
/// 逗号等特殊字符。本方法把每个字符编码为十六进制 Unicode 码点，JS 侧用
/// `String.fromCodePoint(...)` 还原，从根本上避开 JS 字符串字面量转义问题。
///
/// 调用方用 `controller.callAsyncJavaScript(functionBody: buildOcrRenderJs(...))`。
String buildOcrRenderJs(int codepoint, String fontFamily) {
  // 把 fontFamily 每个字符转成十进制码点，逗号分隔，注入 JS 数组字面量
  final codes = fontFamily.codeUnits.map((u) => u.toString()).join(',');
  return ocrRenderJsTemplate
      .replaceAll('{{CODEPOINT}}', '0x${codepoint.toRadixString(16).toUpperCase()}')
      .replaceAll('{{FONT_FAMILY_CODES}}', codes);
}
