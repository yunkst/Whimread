import 'package:flutter/material.dart';

/// 阅读器正文分段——无限滚动拼接的最小渲染单元。
///
/// 一段 = 一个已拼接进阅读视图的章节：
/// - [paragraphs] 为展示用段落（改写揭示的旧文本占位已由上层替换）
/// - 标注 / 待揭示均以「章内段落序号」为 key，随段落归属章节，
///   不受扁平化后的条目位移影响
class ReaderChapterSegment {
  final String chapterUrl;
  final String chapterTitle;
  final List<String> paragraphs;

  /// 已有标注的章内段落序号集合（显示标注图标）
  final Set<int> annotatedIndexes;

  /// 待揭示段落（章内段落序号 → 改写后的新文本）
  final Map<int, String> pendingReveals;

  const ReaderChapterSegment({
    required this.chapterUrl,
    required this.chapterTitle,
    required this.paragraphs,
    this.annotatedIndexes = const {},
    this.pendingReveals = const {},
  });

  /// 按显示层一致规则拆分正文（按 '\n' 拆 + 过滤空行）
  static List<String> splitParagraphs(String content) =>
      content.split('\n').where((p) => p.trim().isNotEmpty).toList();
}

/// 章节分隔线：分割线 + 居中章节名，渲染在每章起点（含首章）。
///
/// 携带章节起点 GlobalKey（由阅读页传入），供起点偏移采样与重定位。
/// 高度计入所在章节块——顶部拼接的测高列必须包含同构分隔线。
class ReaderChapterDivider extends StatelessWidget {
  final String title;

  const ReaderChapterDivider({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分段 → 扁平条目的布局换算。
///
/// 条目序列 = Σ(章节分隔线 + 该章段落) + 尾部占位。
/// 章节分隔线为每章首条目，携带章节级 GlobalKey，供阅读页做
/// 「起点偏移采样」「当前章检测」与「刷新/切章后重定位」。
class ReaderFlatLayout {
  final List<ReaderChapterSegment> segments;

  const ReaderFlatLayout(this.segments);

  /// 扁平条目总数（含每章分隔线与末尾 1 项占位）
  int get itemCount =>
      segments.fold(0, (n, s) => n + 1 + s.paragraphs.length) + 1;

  /// 条目为章节分隔线时返回章节 URL，否则返回 null
  String? markerChapterUrlAt(int index) {
    var cursor = 0;
    for (final s in segments) {
      if (index == cursor) return s.chapterUrl;
      cursor += 1 + s.paragraphs.length;
    }
    return null;
  }

  /// 条目为段落时返回（章节 URL, 章内段落序号, 段落文本），否则 null
  (String, int, String)? paragraphAt(int index) {
    var cursor = 0;
    for (final s in segments) {
      final inSegmentIndex = index - cursor - 1; // 跳过章节分隔线
      if (inSegmentIndex >= 0 && inSegmentIndex < s.paragraphs.length) {
        return (s.chapterUrl, inSegmentIndex, s.paragraphs[inSegmentIndex]);
      }
      cursor += 1 + s.paragraphs.length;
    }
    return null;
  }
}
