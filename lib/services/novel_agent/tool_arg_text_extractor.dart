/// 工具参数流式文本提取器
///
/// 从「半截 JSON」的 arguments 累计串里抽取展示用文本字段（text / character），
/// 供文字游戏剧情工具（narrate / speak）的打字机流式渲染。
///
/// 只做显示，不做权威解析——工具正式执行时仍由 jsonDecode 解析完整参数。
/// 容错目标：
/// - 值尚未开始（args 只到 `"text":`）→ 返回空串
/// - 值流到一半（引号未闭合）→ 返回已到达部分（打字机中段）
/// - 截断的转义序列（结尾是 `\` 或半截 `\u00`）→ 丢弃不完整尾部
/// - `"text"` 出现在字符串值里不会被误当键（仅匹配键位置：前一个非空白
///   字符是 `{` 或 `,`）
library;

/// 提取结果：text 恒非空串；character 为 null 表示尚未流出或工具无此字段
class ExtractedToolArgText {
  final String text;
  final String? character;

  const ExtractedToolArgText({this.text = '', this.character});
}

class ToolArgTextExtractor {
  ToolArgTextExtractor._();

  /// 从 arguments 前缀串提取 text / character 两个字符串字段的当前可见值
  static ExtractedToolArgText extract(String argsSoFar) {
    return ExtractedToolArgText(
      text: extractStringField(argsSoFar, 'text') ?? '',
      character: extractStringField(argsSoFar, 'character'),
    );
  }

  /// 在 JSON 对象前缀串中找 `"key": "value..."` 的 value 已到达部分。
  ///
  /// 未找到键返回 null；键命中但值未开始返回空串；
  /// 值流到一半返回已到达的解码内容。多个同名键取第一个合法命中。
  static String? extractStringField(String src, String key) {
    final needle = '"$key"';
    final colon = 0x3A; // :
    final quote = 0x22; // "
    final lbrace = 0x7B; // {
    final comma = 0x2C; // ,

    var searchFrom = 0;
    while (true) {
      final keyIdx = src.indexOf(needle, searchFrom);
      if (keyIdx < 0) return null;

      // 键位置校验：前一个非空白字符必须是 { 或 ,（排除出现在字符串值里的同名文本）
      var i = keyIdx - 1;
      while (i >= 0 && _isSpace(src.codeUnitAt(i))) {
        i--;
      }
      final prev = i >= 0 ? src.codeUnitAt(i) : lbrace;
      if (prev != lbrace && prev != comma) {
        searchFrom = keyIdx + needle.length;
        continue;
      }

      // 跳过 key 后的空白与冒号
      var j = keyIdx + needle.length;
      while (j < src.length && _isSpace(src.codeUnitAt(j))) {
        j++;
      }
      if (j >= src.length || src.codeUnitAt(j) != colon) {
        searchFrom = keyIdx + needle.length;
        continue;
      }
      j++;
      while (j < src.length && _isSpace(src.codeUnitAt(j))) {
        j++;
      }
      if (j >= src.length) return '';
      if (src.codeUnitAt(j) != quote) {
        searchFrom = keyIdx + needle.length;
        continue;
      }
      // 值开始：解码到未转义的闭引号或输入末尾
      return _decodeUntilClosingQuote(src, j + 1);
    }
  }

  static bool _isSpace(int u) =>
      u == 0x20 || u == 0x09 || u == 0x0A || u == 0x0D;

  /// 从 [start] 起解码 JSON 字符串值，直到未转义的 `"` 或输入末尾。
  /// 处理标准 JSON 转义（\n \t \r \b \f \" \\ \/ \uXXXX），截断的转义丢弃。
  static String _decodeUntilClosingQuote(String src, int start) {
    final buf = StringBuffer();
    var i = start;
    while (i < src.length) {
      final u = src.codeUnitAt(i);
      if (u == 0x22) break; // 未转义闭引号：值结束
      if (u != 0x5C) {
        // 普通字符（含原生 UTF-16 代理对，按 code unit 原样写出）
        buf.writeCharCode(u);
        i++;
        continue;
      }
      // 转义序列
      if (i + 1 >= src.length) break; // 截断的反斜杠
      final e = src.codeUnitAt(i + 1);
      switch (e) {
        case 0x6E: // n
          buf.write('\n');
          i += 2;
        case 0x74: // t
          buf.write('\t');
          i += 2;
        case 0x72: // r
          buf.write('\r');
          i += 2;
        case 0x62: // b
          buf.write('\b');
          i += 2;
        case 0x66: // f
          buf.write('\f');
          i += 2;
        case 0x22: // "
          buf.write('"');
          i += 2;
        case 0x5C: // \
          buf.write('\\');
          i += 2;
        case 0x2F: // /
          buf.write('/');
          i += 2;
        case 0x75: // uXXXX
          if (i + 6 <= src.length) {
            final code = int.tryParse(src.substring(i + 2, i + 6), radix: 16);
            if (code != null) buf.writeCharCode(code);
            // 非法十六进制：跳过该序列（显示层容错）
            i += 6;
          } else {
            i = src.length; // 截断的 \u，丢弃尾部
          }
        default:
          buf.writeCharCode(e);
          i += 2;
      }
    }
    return buf.toString();
  }
}
