import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bookshelf.dart';
import '../core/providers/bookshelf_providers.dart';

/// 书架分类切换器（顶部 Tab 栏）
///
/// 新设计：书架由"小说来源"派生，**用户不可调整**——全部/原创固定，
/// 联网按来源网站（URL host）拆分，每个有藏书的站点一个 Tab。
/// 本组件仅负责单步切换，不保留"新建/删除/重命名/排序"等用户操作。
///
/// 用自定义 Row 而非 Material TabBar——状态由 Riverpod 持有，
/// TabBar 走 controller 同步较重；此处只需要"点击即切 + 下划线指示器"。
/// Tab 总宽未超视口时按自然宽度比例分配 flex 铺满（每个 Tab 分到的宽度
/// ≥ 自身自然宽度，避免长站点名被压缩折行）；超出时横向滚动。
/// Tab 文字兜底设了 maxLines:1 + ellipsis，任何情况下都不会变两行。
class BookshelfTabBar extends ConsumerWidget {
  const BookshelfTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentBookshelfProvider);
    final shelvesAsync = ref.watch(bookshelfShelvesProvider);
    // 加载中/失败时先展示固定基础书架，站点 Tab 就绪后无缝补齐
    final shelves =
        shelvesAsync.valueOrNull ?? Bookshelf.systemShelves.sublist(0, 2);
    final theme = Theme.of(context);
    final dividerColor = theme.dividerColor;
    final primary = theme.colorScheme.primary;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;

    final tabs = [
      for (final s in shelves)
        _BookshelfTab(
          label: s.name,
          selected: s == current,
          selectedColor: primary,
          unselectedColor: onSurfaceVariant,
          onTap: () {
            if (s != current) {
              ref.read(currentBookshelfProvider.notifier).setBookshelf(s);
            }
          },
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: dividerColor, width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 用 TextPainter 按真实样式量宽（含系统字体缩放），
          // 替代字符数估算，保证"是否超宽"与"flex 分配"都贴合实际渲染
          final tabWidths = [
            for (final t in tabs)
              _measureTabTextWidth(
                    context,
                    label: t.label,
                    selected: t.selected,
                  ) +
                  _tabHorizontalPadding,
          ];
          final totalWidth =
              tabWidths.fold<double>(0, (w, x) => w + x);
          if (totalWidth <= constraints.maxWidth) {
            // 未超宽：按自然宽度比例分配 flex 铺满。总 flex ≈ 总自然宽度 ≤
            // 视口宽，故每个 Tab 分到的宽度 ≥ 自身自然宽度，长标签不折行
            return Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(flex: tabWidths[i].round(), child: tabs[i]),
              ],
            );
          }
          // 超宽：横向滚动
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: tabs),
          );
        },
      ),
    );
  }

  /// Tab 水平 padding（_BookshelfTab 的 EdgeInsets.symmetric(horizontal: 16)）
  static const double _tabHorizontalPadding = 32;

  /// 量取 Tab 标签文字的真实渲染宽度（fontSize/字重与 [_BookshelfTab] 一致）
  static double _measureTabTextWidth(
    BuildContext context, {
    required String label,
    required bool selected,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(); // 默认 maxWidth 无穷，单行量出自然宽度
    return painter.width;
  }
}

class _BookshelfTab extends StatelessWidget {
  const _BookshelfTab({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? selectedColor : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? selectedColor : unselectedColor,
            ),
          ),
        ),
      ),
    );
  }
}
