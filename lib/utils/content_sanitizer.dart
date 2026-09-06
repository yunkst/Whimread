/// 章节内容净化器 — 剥离 LLM 可能产生的 markdown 标记
///
/// 写作场景的 system prompt 要求"纯文本内容"，但 LLM 经常不遵守，
/// 可能返回 **粗体**、# 标题、> 引用 等 markdown 标记。
/// 这些标记如果原样写入数据库，用户在阅读器中会看到原始符号。
///
/// 本净化器在写入数据库前自动剥离这些标记，保留实际文本内容。
library;

class ContentSanitizer {
  ContentSanitizer._();

  /// 净化章节内容，按顺序执行所有规则
  ///
  /// 处理顺序：代码块 → 行内代码 → 标题 → 粗体/斜体 → 引用 → 分隔线 → 空行压缩
  static String sanitize(String content) {
    var result = content;
    result = _removeCodeBlocks(result);
    result = _removeInlineCode(result);
    result = _removeHeadings(result);
    result = _removeHorizontalRules(result);  // 先于粗体/斜体，避免 *** 被误匹配
    result = _removeBoldItalic(result);
    result = _removeBlockquotes(result);
    result = _cleanupEmptyLines(result);
    return result.trim();
  }

  // ── 1. 代码块围栏 ──

  /// 移除 ```lang ... ``` 围栏标记，保留代码内容
  static String _removeCodeBlocks(String c) {
    // 先移除开围栏 ```lang 或 ```
    c = c.replaceAll(RegExp(r'```[\w]*\n?'), '');
    // 再移除闭围栏 ```
    c = c.replaceAll(RegExp(r'\n?```'), '');
    return c;
  }

  // ── 2. 行内代码 ──

  /// 移除 `code` 反引号，保留代码文字
  static String _removeInlineCode(String c) =>
      c.replaceAllMapped(RegExp(r'`([^`\n]+)`'), (m) => m[1]!);

  // ── 3. 标题标记 ──

  /// 移除 # ## ### 等标题前缀，保留标题文字
  static String _removeHeadings(String c) =>
      c.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');

  // ── 4. 粗体/斜体 ──

  /// 移除 **bold** / __bold__ / *italic* / _italic_ 标记，保留文字
  static String _removeBoldItalic(String c) {
    // **bold** → bold（优先匹配，避免 * 被斜体规则误匹配）
    c = c.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m[1]!);
    // __bold__ → bold
    c = c.replaceAllMapped(RegExp(r'__(.+?)__'), (m) => m[1]!);
    // *italic* → italic
    c = c.replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m[1]!);
    // _italic_ → italic（仅匹配词边界的下划线，避免中文下划线误伤）
    c = c.replaceAllMapped(RegExp(r'(?<!\w)_(.+?)_(?!\w)'), (m) => m[1]!);
    return c;
  }

  // ── 5. 引用标记 ──

  /// 移除 > 引用前缀，保留引用文字
  static String _removeBlockquotes(String c) =>
      c.replaceAll(RegExp(r'^>\s?', multiLine: true), '');

  // ── 6. 分隔线 ──

  /// 移除 --- / *** / ___ 分隔线（含前后换行）
  static String _removeHorizontalRules(String c) {
    // 先尝试匹配独立行的分隔线（带换行）
    c = c.replaceAll(RegExp(r'\n[-*_]{3,}\s*\n'), '\n');
    c = c.replaceAll(RegExp(r'\n[-*_]{3,}\s*$'), '');
    c = c.replaceAll(RegExp(r'^[-*_]{3,}\s*\n'), '');
    return c;
  }

  // ── 7. 空行压缩 ──

  /// 压缩连续空行（最多保留 1 个空行，即最多 2 个连续换行符）
  static String _cleanupEmptyLines(String c) =>
      c.replaceAll(RegExp(r'\n{3,}'), '\n\n');
}
