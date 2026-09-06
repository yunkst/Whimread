import 'package:flutter/material.dart';

/// 人物卡列表的空状态视图
///
/// 当某本小说尚无任何角色时显示，提示用户可手动新建，
/// 或在阅读时由 AI 自动提取。仿 [EmptyChaptersView] 的布局风格。
class EmptyCharactersView extends StatelessWidget {
  /// 点击「新建人物卡」回调
  final VoidCallback onCreateCharacter;

  const EmptyCharactersView({
    required this.onCreateCharacter,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 64,
            color: colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有人物卡',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '阅读时 AI 会自动提取角色，也可手动新建',
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onCreateCharacter,
            icon: const Icon(Icons.person_add_alt_outlined),
            label: const Text('新建人物卡'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
