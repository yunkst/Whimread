/// 章节内容净化器 — 剥离 LLM 可能产生的 markdown 标记 + 拦截 JSON 污染正文
///
/// 写作场景的 system prompt 要求"纯文本内容"，但 LLM 经常不遵守，
/// 可能返回 **粗体**、# 标题、> 引用 等 markdown 标记。
/// 这些标记如果原样写入数据库，用户在阅读器中会看到原始符号。
///
/// [sanitize] 在写入数据库前自动剥离这些标记，保留实际文本内容。
/// [detectJsonContamination] 拦截更恶劣的形态：模型把 JSON / 工具调用结构
/// 混进正文（反馈 #16 实测故障），sanitize 剥不掉 JSON 文本本身，
/// 必须在写入前整段拒收、交回模型重写。
library;

import 'dart:convert';

class ContentSanitizer {
  ContentSanitizer._();

  // ═══ JSON 污染检测 ═══

  /// 检测疑似 JSON 污染的正文。
  ///
  /// 背景（反馈 #16「llm替换文字，出现错乱」实测样本）：模型生成工具入参
  /// 时 JSON 结构错乱——newString 值提前收尾后，把后续键值对整个吞进自己的
  /// 字符串值（`正文……", "oldString": "……", "position": 79}`），吞完的整体
  /// 恰好仍是合法 JSON 而被正常解析执行。程序机械行为无误，但垃圾入参
  /// 畅通落库，正文从此带着结构尾巴。
  ///
  /// 返回检测形态标识（供引导错误说明），null = 干净：
  /// - `whole_string_json`  — 整体是合法 JSON 对象/数组
  /// - `fenced_json`        — ``` 围栏内是合法 JSON 对象/数组
  /// - `tool_call_echo`     — 独立行工具调用回声（含 ≥2 个已知工具参数键）
  /// - `embedded_key_value` — 值内部嵌有 `", "工具参数键":` 键值结构（#16 形态）
  ///
  /// ⚠️ 检测对象必须是**模型本次产出的增量**（newString / content），
  /// 不要对替换后的全文检测——正文里已存在的历史污染会把「清理编辑」
  /// 也拦死，导致垃圾永远修不掉。
  static String? detectJsonContamination(String content) {
    // 规则①：整体即 JSON。正常正文永远不会整体是合法 JSON，零误伤。
    final trimmed = content.trim();
    if (trimmed.length >= 2 &&
        (trimmed.startsWith('{') || trimmed.startsWith('['))) {
      if (_tryDecodeJsonCollection(trimmed)) return 'whole_string_json';
    }

    // 规则②：围栏 JSON。只拦「围栏内确实解析为 JSON 对象/数组」的形态；
    // ```text 等围栏里的散文、剧情需要的代码描写不拦（sanitize 只剥围栏
    // 符号，JSON 文本会留下——所以必须在 sanitize 前检测）。
    for (final m in RegExp(
      r'```[^\n]*\n(.*?)```',
      dotAll: true,
    ).allMatches(content)) {
      final inner = m.group(1)?.trim() ?? '';
      if (inner.startsWith('{') || inner.startsWith('[')) {
        if (_tryDecodeJsonCollection(inner)) return 'fenced_json';
      }
    }

    // 规则③：独立行工具调用回声。行首尾成对的 {...} 且含 ≥2 个已知工具
    // 参数键——模型把工具调用回声成文本的形态。键名集合收窄到工具参数，
    // 正文里偶现的 `{"a":1,"b":2}`（程序员题材）不触发。
    const knownKeys = {
      'position', 'oldString', 'newString', 'title', 'content', 'replaceAll',
      'rewriteInstruction', 'summary', 'keyEvents', 'characterChanges',
    };
    for (final line in content.split('\n')) {
      final t = line.trim();
      if (t.length >= 2 && t.startsWith('{') && t.endsWith('}')) {
        final keys = _tryDecodeJsonObjectKeys(t);
        if (keys != null &&
            keys.where(knownKeys.contains).length >= 2) {
          return 'tool_call_echo';
        }
      }
    }

    // 规则④：值内部嵌有工具参数键值对（#16 实际形态）。`", "oldString":`
    // 这种「引号-逗号-引号-已知键名-冒号」序列在正常正文中不可能出现
    // （正文对话用中文引号「“”」，ASCII 双引号后紧跟 JSON 键语法的概率
    // 趋近于零），键名限定为已知工具参数键进一步压低误伤。
    final embeddedEcho = RegExp(
      r'"\s*,\s*"(oldString|newString|position|title|content|replaceAll)"\s*:',
    );
    if (embeddedEcho.hasMatch(content)) return 'embedded_key_value';

    return null;
  }

  /// 尝试把 [s] 解析为 JSON 对象/数组，成功返回 true。
  static bool _tryDecodeJsonCollection(String s) {
    try {
      final v = jsonDecode(s);
      return v is Map || v is List;
    } catch (_) {
      return false;
    }
  }

  /// 尝试把 [s] 解析为 JSON 对象并返回键集合，失败/非对象返回 null。
  static Set<String>? _tryDecodeJsonObjectKeys(String s) {
    try {
      final v = jsonDecode(s);
      if (v is Map) return v.keys.map((k) => k.toString()).toSet();
      return null;
    } catch (_) {
      return null;
    }
  }

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
