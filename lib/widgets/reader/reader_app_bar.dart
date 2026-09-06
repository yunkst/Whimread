import 'package:flutter/material.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_colors.dart';
import '../../models/novel.dart';
import '../../models/chapter.dart';

/// ReaderAppBar - 阅读器顶部应用栏
///
/// 职责：
/// - 显示章节标题和编辑模式状态
/// - 提供编辑模式切换
/// - 更多功能菜单
///
/// 依赖：
/// - Novel (novel 模型)
/// - Chapter (chapter 模型)
class ReaderAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Novel novel;
  final Chapter currentChapter;
  final List<Chapter> chapters;
  final bool isEditMode;
  final VoidCallback onToggleEditMode;
  final VoidCallback onSaveAndExitEditMode;
  final Function(String) onMenuAction;

  const ReaderAppBar({
    super.key,
    required this.novel,
    required this.currentChapter,
    required this.chapters,
    required this.isEditMode,
    required this.onToggleEditMode,
    required this.onSaveAndExitEditMode,
    required this.onMenuAction,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Row(
        children: [
          Expanded(
            child: Text(
              currentChapter.title,
              style: AppTypography.chapterTitle.copyWith(fontSize: 18),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          // 编辑模式状态指示器
          if (isEditMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.edit, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '编辑模式',
                    // 徽章文字保持小号无衬线以提升对比可读性
                    // （背景为 colorScheme.secondary，白字保证对比度）
                    style: AppTypography.metaItalic.copyWith(
                      fontSize: 12,
                      fontFamily: AppTypography.sans,
                      fontStyle: FontStyle.normal,
                      color: context.appColors.onSemantic,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        // 编辑模式切换按钮
        if (!isEditMode)
          IconButton(
            onPressed: onToggleEditMode,
            tooltip: '进入编辑模式',
            icon: const Icon(Icons.edit_outlined),
          ),
        // 编辑完成按钮
        if (isEditMode)
          IconButton(
            onPressed: onSaveAndExitEditMode,
            tooltip: '完成编辑并保存',
            icon: const Icon(Icons.check),
          ),
        // 更多功能菜单
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: '更多功能',
          onSelected: onMenuAction,
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'refresh',
              child: Row(
                children: [
                  Icon(Icons.refresh, size: 18),
                  SizedBox(width: 12),
                  Text('刷新章节'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'version_history',
              child: Row(
                children: [
                  Icon(Icons.history, size: 18),
                  SizedBox(width: 12),
                  Text('版本历史'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'create_snapshot',
              child: Row(
                children: [
                  Icon(Icons.camera_alt_outlined, size: 18),
                  SizedBox(width: 12),
                  Text('创建快照'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'reader_settings',
              child: Row(
                children: [
                  Icon(Icons.tune, size: 18),
                  SizedBox(width: 12),
                  Text('阅读设置'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}