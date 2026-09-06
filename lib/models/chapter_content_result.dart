/// 章节内容获取结果
///
/// 包含内容文本和来源标识，用于智能速率控制。
class ChapterContentResult {
  final String content;
  final String? fontFamily; // v37 新增：反爬字体族名（OCR 模式下由脚本返回）
  final bool fromCache;

  const ChapterContentResult({
    required this.content,
    this.fontFamily,
    this.fromCache = false,
  });
}