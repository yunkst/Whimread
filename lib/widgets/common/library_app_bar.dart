/// 书馆美学 · 通用 AppBar 组件
///
/// 抽自 [bookshelf_screen.dart] 的"卷轴品牌 mark + 衬线标题 + 斜体英文副标题"模式，
/// 让书馆主题下的页面获得统一的衬线标题观感。
///
/// 视觉规范：
/// - **简洁模式**（默认，无 subtitle / brandMark）：toolbar 高度跟随 [kToolbarHeight]，
///   仅渲染衬线主标题，适合设置页、日志页等"次级页面"。
/// - **装饰模式**（传入 subtitle 或 brandMark）：toolbar 高度提升至 72，渲染
///   "品牌方块 + 标题（+ 副标题）"的完整书馆品牌头，适合书架、主页等"门面页"。
///
/// 不设 [AppBar.backgroundColor]，跟随主题默认（与 P0-3 统一风格一致）。
///
/// 使用示例：
/// ```dart
/// // 简洁模式
/// Scaffold(appBar: LibraryAppBar(title: '设置'));
///
/// // 装饰模式
/// Scaffold(
///   appBar: LibraryAppBar(
///     title: '我的书架',
///     subtitle: 'Midnight Library',
///   ),
/// );
///
/// // 透传 actions
/// Scaffold(
///   appBar: LibraryAppBar(
///     title: '章节列表',
///     actions: [IconButton(...)],
///   ),
/// );
/// ```
library;

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 书馆主题通用 AppBar
///
/// 实现 [PreferredSizeWidget]，可直接作为 [Scaffold.appBar] 使用。
class LibraryAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LibraryAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.brandMark = '卷',
    this.brandColor,
    this.actions,
    this.centerTitle = false,
    this.automaticallyImplyLeading = true,
  });

  /// 主标题（衬线字体）
  final String title;

  /// 可选副标题（斜体小字），不传则不显示
  final String? subtitle;

  /// 品牌方块中的文字，默认 `'卷'`；传 `null` 则不显示品牌方块
  final String? brandMark;

  /// 品牌方块背景色，默认跟随 [AppColors.agentAccent]
  final Color? brandColor;

  /// 右侧操作按钮列表
  final List<Widget>? actions;

  /// 是否居中显示标题，默认左对齐
  final bool centerTitle;

  /// 是否自动显示返回按钮，默认 true
  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize => Size.fromHeight(
        (subtitle != null || brandMark != null) ? 72 : kToolbarHeight,
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final colorScheme = Theme.of(context).colorScheme;
    final showDecor = subtitle != null || brandMark != null;
    final effectiveBrandColor = brandColor ?? colors.agentAccent;

    // 简洁模式：只渲染衬线主标题，保持 AppBar 默认高度
    if (!showDecor) {
      return AppBar(
        toolbarHeight: kToolbarHeight,
        titleSpacing: 20,
        automaticallyImplyLeading: automaticallyImplyLeading,
        centerTitle: centerTitle,
        title: Text(
          title,
          style: AppTypography.shelfTitle.copyWith(
            color: colorScheme.onSurface,
          ),
        ),
        actions: actions,
      );
    }

    // 装饰模式：品牌方块 + 标题（+ 副标题）
    return AppBar(
      toolbarHeight: 72,
      titleSpacing: 20,
      automaticallyImplyLeading: automaticallyImplyLeading,
      centerTitle: centerTitle,
      title: Row(
        children: [
          if (brandMark != null) ...[
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: effectiveBrandColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                brandMark!,
                style: AppTypography.chapterTitle.copyWith(
                  fontSize: 20,
                  color: colors.agentOnBrand,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTypography.shelfTitle.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppTypography.metaItalic.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: actions,
    );
  }
}
