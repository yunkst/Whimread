/// 新游戏扉页（GameIntroView）— 从未开始的文字游戏的进入画面
///
/// 标题区（图标 + 游戏名）与内容卡（开场情境 / 世界观）放在可滚动区：
/// 开场文本是 agent 写的整段情境，可能远超一屏，必须可滚动——
/// 内容不足一屏时整组垂直居中，超一屏时自然撑开滚动。
/// 「开始游戏」固定在滚动区之外，长文翻页时始终可见可点。
library;

import 'package:flutter/material.dart';

class GameIntroView extends StatelessWidget {
  final String title;
  final String opening;
  final String worldview;
  final VoidCallback onStart;

  const GameIntroView({
    super.key,
    required this.title,
    required this.opening,
    required this.worldview,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, viewport) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                // 最小高度 = 视口去掉自身 padding：短内容仍垂直居中，
                // 长内容溢出该约束后由 SingleChildScrollView 接管滚动
                constraints:
                    BoxConstraints(minHeight: viewport.maxHeight - 56),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const Spacer(),
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.5),
                        ),
                        child: Icon(
                          Icons.auto_stories_rounded,
                          size: 28,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        title,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                      const Spacer(),
                      if (opening.isNotEmpty || worldview.isNotEmpty)
                        _contentCard(context)
                      else
                        Text(
                          '你的故事等待开场',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('开始游戏'),
            ),
          ),
        ),
      ],
    );
  }

  /// 开场卡：开场情境为主体（正文级排版），世界观为补充分区
  Widget _contentCard(BuildContext context) {
    final theme = Theme.of(context);
    Widget label(IconData icon, String text) => Row(
          children: [
            Icon(icon, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 5),
            Text(text,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary)),
          ],
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (opening.isNotEmpty) ...[
            label(Icons.auto_awesome, '开场情境'),
            const SizedBox(height: 8),
            Text(
              opening,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.8),
            ),
          ],
          if (worldview.isNotEmpty) ...[
            if (opening.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(
                height: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 14),
            ],
            label(Icons.public, '世界观'),
            const SizedBox(height: 6),
            Text(
              worldview,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
