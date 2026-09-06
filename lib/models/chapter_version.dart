import 'package:flutter/material.dart';

/// 章节历史版本模型
///
/// 用于存储章节内容的历史版本快照，
/// 与 chapter_cache 主表配合：主表始终存最新内容，版本表存历史内容。
class ChapterVersion {
  final int? id;
  final String chapterUrl;
  final String content;
  final String source; // 'edit' | 'ai_rewrite' | 'manual_snapshot' | 'restore'
  final int createdAt; // millisecondsSinceEpoch
  final int contentLength; // 冗余字段，列表展示用，避免读大字段

  ChapterVersion({
    this.id,
    required this.chapterUrl,
    required this.content,
    required this.source,
    required this.createdAt,
    required this.contentLength,
  });

  /// 版本来源的中文标签
  String get sourceLabel {
    switch (source) {
      case 'edit':
        return '用户编辑';
      case 'ai_rewrite':
        return 'AI改写';
      case 'manual_snapshot':
        return '手动快照';
      case 'restore':
        return '还原操作';
      default:
        return '未知';
    }
  }

  /// 版本来源对应的图标
  IconData get sourceIcon {
    switch (source) {
      case 'edit':
        return Icons.edit;
      case 'ai_rewrite':
        return Icons.auto_fix_high;
      case 'manual_snapshot':
        return Icons.camera_alt;
      case 'restore':
        return Icons.restore;
      default:
        return Icons.history;
    }
  }

  /// 格式化时间字符串
  String get formattedTime {
    final dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 格式化字数
  String get formattedLength {
    return '$contentLength字';
  }

  factory ChapterVersion.fromMap(Map<String, dynamic> map) {
    return ChapterVersion(
      id: map['id'] as int?,
      chapterUrl: map['chapterUrl'] as String,
      content: map['content'] as String,
      source: map['source'] as String? ?? 'edit',
      createdAt: map['createdAt'] as int,
      contentLength: map['contentLength'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'chapterUrl': chapterUrl,
      'content': content,
      'source': source,
      'createdAt': createdAt,
      'contentLength': contentLength,
    };
  }
}
