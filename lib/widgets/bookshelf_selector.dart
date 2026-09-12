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
/// Tab 少于视口宽度时均分铺满，超出时横向滚动。
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
          final totalWidth =
              tabs.fold<double>(0, (w, t) => w + _estimateTabWidth(t.label));
          if (totalWidth <= constraints.maxWidth) {
            // 未超宽：均分铺满（与旧三档 Tab 的视觉一致）
            return Row(
              children: [
                for (final t in tabs) Expanded(child: t),
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

  /// 估算 Tab 自然宽度（中文按 fontSize 全宽、西文按 ~0.62 倍宽 + 水平 padding）
  static double _estimateTabWidth(String label) {
    var textWidth = 0.0;
    for (final rune in label.runes) {
      textWidth += rune > 0x2E7F ? 15.0 : 15.0 * 0.62; // fontSize 15
    }
    return textWidth + 32; // 水平 padding 16 * 2
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
