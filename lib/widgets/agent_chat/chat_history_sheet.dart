import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/core/providers/chat_session_providers.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';

import '../common/bottom_sheet_header.dart';
import '../empty_states/empty_state_view.dart';
import 'chat_history_list_item.dart';

/// 会话历史底部抽屉
///
/// 展示当前 scenario 下所有 session，支持：
/// - 新建会话
/// - 点击切换（运行中的当前会话禁用切换）
/// - 单条重命名 / 删除
class ChatHistorySheet extends ConsumerWidget {
  final String scenarioId;

  const ChatHistorySheet({super.key, required this.scenarioId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(chatSessionsByScenarioProvider(scenarioId));
    final currentSessionId = ref.watch(currentChatSessionIdProvider);
    // 当前会话是否运行中（用于禁用列表中其它项的切换）
    final running = ref.watch(scenarioSessionsProvider.notifier).isRunning(scenarioId);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // 顶部把手 + 标题 + 新建按钮
              BottomSheetHeader(
                icon: Icons.history,
                title: '会话历史',
                trailing: IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '新建会话',
                  onPressed: () => _createNewSession(context, ref),
                ),
              ),
              // 列表
              Expanded(
                child: sessionsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('加载失败：$e',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  ),
                  data: (sessions) {
                    if (sessions.isEmpty) {
                      return _buildEmpty(context);
                    }
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: sessions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final s = sessions[i];
                        return ChatHistoryListItem(
                          session: s,
                          scenarioId: scenarioId,
                          // 当前任一 session 运行中时，禁用其它项切换
                          isRunning: running && s.id != currentSessionId,
                          isCurrent: s.id == currentSessionId,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return const EmptyStateView(
      icon: Icons.chat_bubble_outline,
      title: '还没有会话',
      subtitle: '开始你的第一次对话吧',
    );
  }

  Future<void> _createNewSession(BuildContext context, WidgetRef ref) async {
    // 复用 ScenarioSessionsNotifier.startNewSession（与对话窗口右上角按钮共用同一段逻辑）
    await ref.read(scenarioSessionsProvider.notifier).startNewSession(scenarioId);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}
