/// 游戏设定查看 sheet（游玩页与管理页共用）
///
/// 只读展示：世界观（缺省回退小说背景设定）/ 开场情境 / 参战角色卡
/// （含近况 currentState，来自共享的 characters 表）/ 玩家角色卡 / 规则。
/// 每个角色行可进「角色卡版本历史」；底部「编辑设定」进入手动编辑页
/// （游玩中编辑下一轮即生效）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_providers.dart'
    show characterRepositoryProvider, novelRepositoryProvider;
import '../../models/character.dart';
import '../../models/novel.dart';
import '../../models/text_game.dart';
import '../../screens/character_revision_history_screen.dart';
import '../../screens/text_game/text_game_settings_edit_screen.dart';

/// 弹出游戏设定查看 sheet（先异步加载共享角色卡）
Future<void> showGameSettingsSheet(
  BuildContext context,
  WidgetRef ref,
  TextGame game,
) async {
  final s = game.settings;

  // 先同步取齐仓库：await 之后再走 WidgetRef 读，若调用方页面在加载期间
  // 退出会抛 "ref after dispose"（sheet 尚未弹出，页面此时可交互）
  final novelRepo = ref.read(novelRepositoryProvider);
  final charRepo = ref.read(characterRepositoryProvider);

  // 加载绑定小说与参战角色卡（小说被删时优雅降级为纯设定展示）
  Novel? novel;
  var cards = <Character>[];
  Character? playerCard;
  if (game.sourceNovelId != null) {
    novel = await novelRepo.getNovelById(game.sourceNovelId!);
    if (novel != null) {
      final all = await charRepo.getCharacters(novel.url);
      final byId = {for (final c in all) c.id: c};
      cards = [
        for (final id in s.characterIds)
          if (byId[id] != null) byId[id]!,
      ];
      playerCard =
          s.playerCharacterId == null ? null : byId[s.playerCharacterId];
    }
  }
  if (!context.mounted) return;

  final theme = Theme.of(context);
  Widget section(String title, String? body) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 4),
            Text(
              (body == null || body.isEmpty) ? '（未设定）' : body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
        ),
      );

  // 一行角色卡：档案 + 近况 + 版本历史入口
  Widget cardRow(BuildContext context, Character c,
      {bool isPlayer = false, String? extra}) {
    final theme = Theme.of(context);
    final profile = <String>[
      if (c.occupation?.isNotEmpty == true) c.occupation!,
      if (c.personality?.isNotEmpty == true) c.personality!,
      if (c.backgroundStory?.isNotEmpty == true) c.backgroundStory!,
      if (extra != null) extra,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c.name}${isPlayer ? '（玩家）' : ''}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (profile.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(profile.join('；'),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(height: 1.5)),
                  ),
                if (c.speechStyle?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('说话风格：${c.speechStyle}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.5, color: theme.colorScheme.outline)),
                  ),
                if (c.currentState?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('近况：${c.currentState}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.5, color: theme.colorScheme.outline)),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: '${c.name} 的版本历史',
            icon: const Icon(Icons.history, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              if (c.id == null) return;
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    CharacterRevisionHistoryScreen(characterId: c.id!),
              ));
            },
          ),
        ],
      ),
    );
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('游戏设定 · ${game.title}', style: theme.textTheme.titleLarge),
            if (novel != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('绑定小说：${novel.title}（共享角色卡）',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ),
            const SizedBox(height: 14),
            section(
                '世界观背景',
                s.worldview.isNotEmpty
                    ? s.worldview
                    : novel?.backgroundSetting),
            section('开场情境', s.opening),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('参战角色',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 4),
                  if (cards.isEmpty)
                    Text('（参战名单为空）',
                        style: theme.textTheme.bodyMedium),
                  ...cards.map((c) => cardRow(sheetContext, c)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('玩家角色',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 4),
                  if (playerCard == null)
                    Text('（未设置）', style: theme.textTheme.bodyMedium)
                  else
                    cardRow(sheetContext, playerCard, isPlayer: true),
                ],
              ),
            ),
            section('规则', [
              if (s.rules.narrativeStyle.isNotEmpty)
                '叙事风格：${s.rules.narrativeStyle}',
              if (s.rules.contentBoundary.isNotEmpty)
                '内容边界：${s.rules.contentBoundary}',
              '每回合 ${s.rules.choicesCount} 个选项',
              '插图：${s.rules.imagePolicy == GameImagePolicy.auto ? "关键场景自动" : "手动生成"}',
            ].join('\n')),
            section(
              '世界与剧情线',
              s.worldNotes.isEmpty ? null : s.worldNotes.map((n) => '· $n').join('\n'),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(sheetContext).push(MaterialPageRoute(
                    builder: (_) => TextGameSettingsEditScreen(gameId: game.id!),
                  ));
                  // 编辑页返回后关闭 sheet——内容可能已变更，避免展示旧值
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑设定'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
