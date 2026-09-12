/// 段落标注模型
///
/// 用户在阅读页长按某段落后写的个人标注（类段评交互）。
/// 每个章节的每个段落最多一条，重复长按 = 编辑已有标注。
/// [paragraphIndex] 为阅读页按 '\n' 拆分并过滤空行后的段落序号。
class ParagraphAnnotation {
  final int? id;
  final String novelUrl;
  final String chapterUrl;
  final int paragraphIndex;

  /// 段落前 80 字快照，编辑弹窗回显上下文用
  final String paragraphPreview;
  final String content;
  final int createdAt; // millisecondsSinceEpoch
  final int updatedAt; // millisecondsSinceEpoch

  /// 段落预览的最大长度
  static const int previewMaxLength = 80;

  ParagraphAnnotation({
    this.id,
    required this.novelUrl,
    required this.chapterUrl,
    required this.paragraphIndex,
    required this.paragraphPreview,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 从段落原文截取预览文本
  static String buildPreview(String paragraph) {
    final trimmed = paragraph.trim();
    if (trimmed.length <= previewMaxLength) return trimmed;
    return '${trimmed.substring(0, previewMaxLength)}…';
  }

  /// 格式化更新时间（如 9/12 14:30）
  String get formattedTime {
    final dt = DateTime.fromMillisecondsSinceEpoch(updatedAt);
    return '${dt.month}/${dt.day} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  ParagraphAnnotation copyWith({int? id, String? content}) {
    return ParagraphAnnotation(
      id: id ?? this.id,
      novelUrl: novelUrl,
      chapterUrl: chapterUrl,
      paragraphIndex: paragraphIndex,
      paragraphPreview: paragraphPreview,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory ParagraphAnnotation.fromMap(Map<String, dynamic> map) {
    return ParagraphAnnotation(
      id: map['id'] as int?,
      novelUrl: map['novelUrl'] as String,
      chapterUrl: map['chapterUrl'] as String,
      paragraphIndex: map['paragraphIndex'] as int,
      paragraphPreview: map['paragraphPreview'] as String? ?? '',
      content: map['content'] as String,
      createdAt: map['createdAt'] as int,
      updatedAt: map['updatedAt'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      // 不携带 id：upsert 走 UNIQUE(chapterUrl, paragraphIndex) 冲突替换，
      // 让 SQLite 重新分配行 id，避免与旧行主键纠缠
      'novelUrl': novelUrl,
      'chapterUrl': chapterUrl,
      'paragraphIndex': paragraphIndex,
      'paragraphPreview': paragraphPreview,
      'content': content,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
