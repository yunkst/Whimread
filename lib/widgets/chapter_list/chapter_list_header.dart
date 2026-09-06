import 'package:flutter/material.dart';
import '../../models/novel.dart';

/// 章节列表头部组件
/// 显示小说基本信息（标题、作者、章节数量、缓存统计）
class ChapterListHeader extends StatelessWidget {
  final Novel novel;
  final int chapterCount;
  final int cachedCount;

  const ChapterListHeader({
    required this.novel,
    required this.chapterCount,
    this.cachedCount = 0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            novel.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text('作者: ${novel.author}'),
          const SizedBox(height: 4),
          Text(_buildChapterCountText()),
        ],
      ),
    );
  }

  /// 构建章节数量文本
  ///
  /// 根据缓存状态显示不同格式：
  /// - 无缓存: "共 50 章"
  /// - 有缓存: "共 50 章 (已缓存 12 章)"
  String _buildChapterCountText() {
    if (cachedCount > 0) {
      return '共 $chapterCount 章 (已缓存 $cachedCount 章)';
    }
    return '共 $chapterCount 章';
  }
}
