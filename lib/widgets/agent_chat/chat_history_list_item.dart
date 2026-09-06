import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/core/providers/chat_session_providers.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/core/theme/app_colors.dart';
import 'package:novel_app/models/chat_session.dart';
import 'package:novel_app/utils/format_utils.dart';

/// 会话历史列表中的一行
///
/// - 点击：切换为当前 session（运行中时由父级禁用）
/// - 右上 PopupMenu：重命名 / 删除
class ChatHistoryListItem extends ConsumerWidget {
  final ChatSession session;
  final String scenarioId;
  final bool isRunning;
  final bool isCurrent;

  const ChatHistoryListItem({
    super.key,
    required this.session,
    required this.scenarioId,
    required this.isRunning,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentId = ref.watch(currentChatSessionIdProvider);
    final selected = isCurrent || currentId == session.id;

    return ListTile(
      selected: selected,
      leading: Icon(
        selected ? Icons.chat_bubble : Icons.chat_bubble_outline,
        size: 22,
        color: selected ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
      title: Text(
        session.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Row(
        children: [
          Text(
            FormatUtils.formatDateTimeShort(session.updatedAt),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          if (isRunning) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '进行中',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (action) async {
          switch (action) {
            case 'rename':
              await _showRenameDialog(context, ref);
              break;
            case 'delete':
              final confirmed = await _confirmDelete(context);
              if (confirmed) {
                await ref.read(chatSessionRepositoryProvider).deleteSession(session.id!);
                ref.invalidate(chatSessionsByScenarioProvider(scenarioId));
              }
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'rename', child: Text('重命名')),
          const PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
      // isRunning 仅用于"进行中"徽章展示（下方 if 子句）；切会话不再禁用——
      // ScenarioSession.adoptSession 内部 cancel 老 agent 兜底避免数据污染。
      onTap: () async {
        // 切换当前 session
        ref.read(currentChatSessionIdProvider.notifier).state = session.id;
        // 通知 ScenarioSession 重新 hydrate（内部 cancel + reload）
        await ref
            .read(scenarioSessionsProvider.notifier)
            .switchSession(scenarioId, session.id);
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  Future<void> _showRenameDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: session.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入新标题',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && result != session.title) {
      await ref.read(chatSessionRepositoryProvider).renameSession(session.id!, result);
      ref.invalidate(chatSessionsByScenarioProvider(scenarioId));
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定删除「${session.displayTitle}」？该会话全部消息将被清除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: context.appColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
