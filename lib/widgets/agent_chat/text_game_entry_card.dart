/// 文字游戏创建结果跳转入口卡片
///
/// 在 Agent 聊天窗口中，当 `create_text_game` 工具成功完成时渲染此卡片。
/// 用户点击后直接进入对应游戏的游玩页（TextGamePlayScreen 按 gameId 自行
/// 加载；游戏已被删除时游玩页有兜底提示）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../screens/text_game/text_game_play_screen.dart';

/// 解析工具结果 JSON，创建成功时返回入口数据，否则返回 null。
TextGameEntryData? parseTextGameEntry(String? toolResultJson) {
  if (toolResultJson == null) return null;
  try {
    final json = jsonDecode(toolResultJson) as Map<String, dynamic>;
    if (json['success'] != true) return null;
    final gameId = (json['gameId'] as num?)?.toInt();
    if (gameId == null) return null;
    return TextGameEntryData(
      gameId: gameId,
      gameTitle: json['gameTitle'] as String? ?? '文字游戏',
    );
  } catch (_) {
    return null;
  }
}

class TextGameEntryData {
  final int gameId;
  final String gameTitle;

  const TextGameEntryData({required this.gameId, required this.gameTitle});
}

/// 「进入文字游戏」入口卡：与章节入口卡同一视觉语言（浅色底 + 主色描边 +
/// 图标 + 双行文案 + 箭头），点击直达游玩页。
class TextGameEntryCard extends StatelessWidget {
  final TextGameEntryData data;

  const TextGameEntryCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TextGamePlayScreen(gameId: data.gameId),
          ));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.sports_esports,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '进入文字游戏',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.gameTitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 12, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
