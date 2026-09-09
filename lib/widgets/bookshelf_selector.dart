import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bookshelf.dart';
import '../core/providers/bookshelf_providers.dart';

/// 书架分类切换器（顶部 Tab 栏）
///
/// 新设计：书架只有三档系统分类（全部/原创/联网），
/// 由"小说来源"派生，**用户不可调整**。本组件仅负责单步切换，
/// 不再保留"新建/删除/重命名/排序"等用户操作。
///
/// 用自定义 Row 而非 Material TabBar——状态由 Riverpod 持有，
/// TabBar 走 controller 同步较重；此处只需要"点击即切 + 下划线指示器"。
class BookshelfTabBar extends ConsumerWidget {
  const BookshelfTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentKind = ref.watch(currentBookshelfKindProvider);
    final shelves = Bookshelf.systemShelves;
    final theme = Theme.of(context);
    final dividerColor = theme.dividerColor;
    final primary = theme.colorScheme.primary;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          for (final s in shelves)
            Expanded(
              child: _BookshelfTab(
                label: s.name,
                selected: s.kind == currentKind,
                selectedColor: primary,
                unselectedColor: onSurfaceVariant,
                onTap: () {
                  if (s.kind != currentKind) {
                    ref
                        .read(currentBookshelfKindProvider.notifier)
                        .setBookshelfKind(s.kind);
                  }
                },
              ),
            ),
        ],
      ),
    );
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
        padding: const EdgeInsets.symmetric(vertical: 14),
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
