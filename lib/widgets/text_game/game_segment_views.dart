/// 文字游戏游玩页 — 游戏段渲染组件
///
/// 全新独立组件（不 import widgets/agent_chat/）：旁白（阅读器风格段落）、
/// 台词（角色名 + 对白排版）、场景插图（MediaView/占位/错误）、选项按钮、
/// 玩家输入、打字机流式内容。视觉走 Theme.colorScheme，跟随应用主题。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../screens/text_game/game_transcript_projector.dart';
import '../character/avatar_media.dart';
import '../media/media_view.dart';

/// 旁白段（阅读器风格：适中行高、无头像无标签）
class GameNarrationView extends StatelessWidget {
  final String text;
  const GameNarrationView({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(
        text,
        style: theme.textTheme.bodyLarge?.copyWith(
          height: 1.7,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// 台词段（小圆头像 + 彩色角色名标签 + 对白文本）
class GameDialogueView extends StatelessWidget {
  final String character;
  final String text;

  /// 角色头像 mediaId（null = 无头像，只渲染彩色名标签）
  final String? avatarMediaId;

  const GameDialogueView({
    super.key,
    required this.character,
    required this.text,
    this.avatarMediaId,
  });

  Color _nameColor(BuildContext context) {
    // 角色名按 hash 稳定取色（从预置调色板），同一角色恒同色
    const palette = [
      Color(0xFF7E57C2),
      Color(0xFF29B6F6),
      Color(0xFF26A69A),
      Color(0xFFEF6C00),
      Color(0xFFEC407A),
      Color(0xFF8D6E63),
      Color(0xFF5C6BC0),
      Color(0xFF66BB6A),
    ];
    return palette[character.hashCode.abs() % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameColor = _nameColor(context);
    final hasAvatar = avatarMediaId != null && avatarMediaId!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (hasAvatar)
                Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(right: 6),
                  child: AvatarMedia(
                    mediaId: avatarMediaId,
                    name: character,
                    genderColor: nameColor,
                    fontSize: 12,
                    borderRadius: 12,
                  ),
                ),
              Text(
                character,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: nameColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.6,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// 玩家输入段（右对齐气泡）
class GamePlayerInputView extends StatelessWidget {
  final String text;
  const GamePlayerInputView({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// 场景插图段
///
/// 渲染直接读消息链里的 tool result（生图同步完成，结果即最终态）；
/// 未完成 → 占位转圈；失败 → 错误文案。
class GameSceneImageView extends ConsumerWidget {
  final GameSceneImage segment;

  const GameSceneImageView({super.key, required this.segment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget child;
    if (!segment.toolCompleted) {
      child = _statusBox(context, null, '插图生成中…', spinner: true);
    } else {
      final mediaIds = parseSceneImageMediaIds(segment.toolResultJson);
      if (mediaIds.isNotEmpty) {
        child = _mediaList(context, mediaIds);
      } else {
        final error = parseSceneImageError(segment.toolResultJson);
        child = _statusBox(
          context,
          Icons.history_toggle_off,
          error ?? '本次运行未完成生成，图片不可用',
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: child,
    );
  }

  Widget _mediaList(BuildContext context, List<String> mediaIds) {
    if (mediaIds.isEmpty) {
      return _statusBox(context, Icons.image_not_supported_outlined, '图片不可用');
    }
    // MediaView 非全屏分支内部 Stack(fit: expand)，必须 bounded 约束
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: MediaView(
          mediaId: mediaIds.first,
          onTap: () => _openFullscreen(context, mediaIds.first),
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context, String mediaId) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(child: MediaView(mediaId: mediaId, fullscreen: true)),
      ),
    ));
  }

  Widget _statusBox(
    BuildContext context,
    IconData? icon,
    String message, {
    bool spinner = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (spinner)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (icon != null)
            Icon(icon, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

/// 选项段（按钮组；历史选项置灰，已选标记 ✓）
class GameChoicesView extends StatelessWidget {
  final GameChoices choices;

  /// 点选回调（null = 不可点，纯展示）
  final void Function(GameChoice choice)? onSelected;

  /// 回溯回调（仅带锚点的历史选项组由游玩页提供：回到此节点重新选择）
  final VoidCallback? onRollback;

  const GameChoicesView({
    super.key,
    required this.choices,
    this.onSelected,
    this.onRollback,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in choices.choices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed:
                    onSelected == null || !choices.active ? null : () => onSelected!(c),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (choices.chosenLabel == c.label) ...[
                          Icon(Icons.check_circle,
                              size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            c.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (c.hint != null && c.hint!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          c.hint!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (onRollback != null)
            TextButton.icon(
              onPressed: onRollback,
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                visualDensity: VisualDensity.compact,
                foregroundColor: theme.colorScheme.outline,
              ),
              icon: const Icon(Icons.history, size: 16),
              label: Text(
                '回溯到这一步',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
        ],
      ),
    );
  }
}

/// 打字机流式内容（运行中：旁白/台词按已到达文本渲染，淡入）
class GameStreamingPartsView extends StatelessWidget {
  final List<GameStreamingPart> parts;

  /// 角色名/别名 → 头像 mediaId（台词流式段与定稿段一致带头像）
  final Map<String, String> avatarByName;

  const GameStreamingPartsView({
    super.key,
    required this.parts,
    this.avatarByName = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in parts)
          p.name == 'speak'
              ? GameDialogueView(
                  character: p.character ?? '',
                  text: p.text,
                  avatarMediaId: avatarByName[p.character],
                )
              : GameNarrationView(text: p.text),
      ],
    );
  }
}
