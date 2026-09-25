import 'dart:convert';

/// 章内阅读位置锚点——比"上次阅读章节"细一级的恢复依据。
///
/// 用户读到某章中途退出后，重开同一章时按锚点跳回原位置。
/// 存储在 `bookshelf.lastReadAnchor`（TEXT，JSON 序列化，随 v49 迁移新增）。
///
/// 为什么存"段落序号 + 段内比例"而不是像素偏移：
/// 正文是无限滚动拼接视图，当前章上方可能拼着前序章节，且字号/窗口
/// 尺寸变化都会让像素偏移漂移；段落序号是语义位置，改字号后最多
/// 偏一两个段落，恢复时由阅读器按当前布局重新换算精确偏移。
class ReadingAnchor {
  /// 锚点所属章节 URL（重开章节与它不一致时不做恢复）
  final String chapterUrl;

  /// 章内段落序号（0 起，与显示层段落拆分一致：按 '\n' 拆 + 过滤空行）
  final int paragraphIndex;

  /// 段内滚动比例（0.0-1.0）：视口顶越过该段落顶部的比例
  final double paragraphRatio;

  const ReadingAnchor({
    required this.chapterUrl,
    required this.paragraphIndex,
    required this.paragraphRatio,
  });

  /// 序列化为入库字符串（JSON）。
  ///
  /// ratio 舍入到 3 位小数，降低高频写入的存储抖动。
  String encode() {
    final r = (paragraphRatio.isFinite
            ? paragraphRatio.clamp(0.0, 1.0)
            : 0.0)
        .toStringAsFixed(3);
    return jsonEncode({'u': chapterUrl, 'p': paragraphIndex, 'r': r});
  }

  /// 从入库字符串反序列化；格式非法/字段缺失时返回 null（宽容降级为不恢复）。
  static ReadingAnchor? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final url = map['u'];
      final p = map['p'];
      final r = double.tryParse('${map['r']}');
      if (url is! String || url.isEmpty) return null;
      if (p is! int || p < 0) return null;
      if (r == null) return null;
      return ReadingAnchor(
        chapterUrl: url,
        paragraphIndex: p,
        paragraphRatio: r.isFinite ? r.clamp(0.0, 1.0) : 0.0,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadingAnchor &&
          other.chapterUrl == chapterUrl &&
          other.paragraphIndex == paragraphIndex &&
          other.paragraphRatio == paragraphRatio;

  @override
  int get hashCode =>
      Object.hash(chapterUrl, paragraphIndex, paragraphRatio);

  @override
  String toString() =>
      'ReadingAnchor($chapterUrl, p=$paragraphIndex, r=$paragraphRatio)';
}
