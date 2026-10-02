/// 文字游戏管理页（底部第 2 个 Tab）
///
/// 已创建游戏的列表：继续游玩 / 查看设定 / 删除；空态引导去写作助手
/// 对话创建（新建按钮带预填草稿打开聊天）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_providers.dart'
    show textGameRepositoryProvider;
import '../../core/providers/scenario_sessions_provider.dart';
import '../../core/providers/text_game_providers.dart';
import '../../models/text_game.dart';
import '../../services/novel_agent/agent_scenario.dart';
import '../../utils/format_utils.dart';
import '../../widgets/agent_chat/agent_chat_launcher_entry.dart';
import '../../widgets/agent_chat/agent_scenario_config_dialog.dart';
import '../../widgets/empty_states/empty_state_view.dart';
import '../../widgets/text_game/game_settings_sheet.dart';
import 'text_game_play_screen.dart';

class TextGameHomeScreen extends ConsumerWidget {
  const TextGameHomeScreen({super.key});

  void _openCreation(BuildContext context) {
    AgentChatLauncherEntry.open(
      context,
      scenarioId: ScenarioIds.writing,
      initialDraft: '我想创建一个文字游戏。我们先把设定聊清楚：'
          '题材、世界观、玩家角色、登场角色、叙事风格和规则。',
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    TextGame game,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除游戏'),
        content: Text('删除「${game.title}」？\n剧情记录将一并删除，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // 若被删游戏正在推进剧情，先中断该回合（避免向已删除会话继续写消息）
    final session = ref
        .read(scenarioSessionsProvider.notifier)
        .getIfExists(ScenarioIds.textGame);
    if (session != null && session.sessionId == game.chatSessionId) {
      await session.cancel();
      if (!context.mounted) return;
    }
    await ref.read(textGameRepositoryProvider).delete(game.id!);
    if (!context.mounted) return;
    ref.invalidate(textGamesProvider);
  }

  void _showSettings(BuildContext context, WidgetRef ref, TextGame game) {
    showGameSettingsSheet(context, ref, game);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(textGamesProvider);
    // 进行中徽标：text_game 场景会话的 isLoading（响应式）
    final gameChatState =
        ref.watch(scenarioSessionsProvider)[ScenarioIds.textGame];
    final running = gameChatState?.isLoading ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('文字游戏'),
        actions: [
          IconButton(
            tooltip: 'AI 模型配置',
            icon: const Icon(Icons.tune),
            onPressed: () => showDialog(
              context: context,
              builder: (_) =>
                  const AgentScenarioConfigDialog(scenarioId: ScenarioIds.textGame),
            ),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('加载失败：${state.error}'),
                      TextButton(
                        onPressed: () =>
                            ref.read(textGamesProvider.notifier).refresh(),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : state.games.isEmpty
                  ? EmptyStateView(
                      icon: Icons.casino_outlined,
                      title: '还没有文字游戏',
                      subtitle: '和写作助手聊聊你的点子——它可以基于书架上的小说\n'
                          '或你的自定义设定，帮你把游戏创建出来',
                      actionText: '去创建一个游戏',
                      onAction: () => _openCreation(context),
                    )
                  : RefreshIndicator(
                      onRefresh: () =>
                          ref.read(textGamesProvider.notifier).refresh(),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        itemCount: state.games.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final game = state.games[index];
                          return _GameCard(
                            game: game,
                            running: running,
                            onOpen: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) =>
                                    TextGamePlayScreen(gameId: game.id!),
                              ));
                            },
                            onSettings: () => _showSettings(context, ref, game),
                            onDelete: () => _confirmDelete(context, ref, game),
                          );
                        },
                      ),
                    ),
      floatingActionButton: state.games.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openCreation(context),
              icon: const Icon(Icons.add),
              label: const Text('新建游戏'),
            ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final TextGame game;
  final bool running;
  final VoidCallback onOpen;
  final VoidCallback onSettings;
  final VoidCallback onDelete;

  const _GameCard({
    required this.game,
    required this.running,
    required this.onOpen,
    required this.onSettings,
    required this.onDelete,
  });

  String get _sourceLabel => '改编自《${game.sourceNovelTitle ?? '未知小说'}》';

  String get _statusLabel {
    switch (game.status) {
      case TextGameStatus.active:
        return '进行中';
      case TextGameStatus.finished:
        return '已完结';
      case TextGameStatus.abandoned:
        return '已搁置';
    }
  }

  String get _lastPlayedLabel {
    final t = game.lastPlayedAt;
    if (t == null) return '尚未开始';
    return '上次游玩 ${FormatUtils.formatDateTimeShort(t)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            game.title,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (running) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '剧情推进中',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_sourceLabel · $_statusLabel',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _lastPlayedLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (value) {
                  if (value == 'settings') onSettings();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'settings', child: Text('查看设定')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
