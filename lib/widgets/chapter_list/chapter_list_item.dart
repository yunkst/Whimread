import 'package:flutter/material.dart';
import '../../models/chapter.dart';
import 'chapter_title.dart';
import 'chapter_badge.dart';

/// 章节列表项组件（正常模式）
/// 显示章节标题、缓存状态、番外徽标、插入和删除操作按钮
class ChapterListItem extends StatelessWidget {
  final Chapter chapter;
  final bool isLastRead;
  final bool isUserChapter;
  final bool isCached; // 改为直接接收状态
  final bool isRead; // 是否已读

  /// 该章挂载的番外数量（0 = 不显示徽标）
  final int sideStoryCount;

  /// 点击番外徽标 → 打开本章番外列表（不进入阅读）
  final VoidCallback? onSideStoryTap;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onInsert;
  final VoidCallback? onDelete;

  const ChapterListItem({
    required this.chapter,
    required this.isLastRead,
    required this.isUserChapter,
    required this.isCached,
    this.isRead = false,
    this.sideStoryCount = 0,
    this.onSideStoryTap,
    required this.onTap,
    required this.onLongPress,
    required this.onInsert,
    this.onDelete,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: isUserChapter
            ? colorScheme.primary.withValues(alpha: 0.05)
            : null,
        border: Border(
          left: BorderSide(
            color: isUserChapter
                ? colorScheme.primary.withValues(alpha: 0.3)
                : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: ChapterTitle(
                title: chapter.title,
                isLastRead: isLastRead,
                isUserChapter: isUserChapter,
                isRead: isRead,
              ),
            ),
            // 本章番外徽标（有番外才显示；点击进本章番外列表，不影响
            // 章节行其余区域的进阅读行为）
            if (sideStoryCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: InkWell(
                  onTap: onSideStoryTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_stories,
                            size: 11, color: colorScheme.primary),
                        const SizedBox(width: 3),
                        Text(
                          '番外 $sideStoryCount',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (isUserChapter) const ChapterBadge(),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (chapter.isUserInserted && onDelete != null)
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: colorScheme.error,
                ),
                onPressed: onDelete,
                tooltip: '删除此章节',
              ),
            IconButton(
              icon: Icon(
                Icons.add_circle_outline,
                color: colorScheme.primary,
              ),
              onPressed: onInsert,
              tooltip: '在此章节后插入新章节',
            ),
            // 直接显示缓存状态，不再使用 FutureBuilder
            if (isCached)
              Icon(
                Icons.download_done,
                color: colorScheme.primary,
              ),
          ],
        ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}
