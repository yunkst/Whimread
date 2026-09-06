import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/scenario_sessions_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/agent_chat_message.dart';
import '../empty_states/empty_state_view.dart';
import 'agent_icons.dart';
import 'agent_message_bubble.dart';
import 'compaction_marker_card.dart';

class AgentChatMessages extends ConsumerStatefulWidget {
  final void Function(AgentChatMessage)? onRollback;

  const AgentChatMessages({super.key, this.onRollback});

  @override
  ConsumerState<AgentChatMessages> createState() => _AgentChatMessagesState();
}

class _AgentChatMessagesState extends ConsumerState<AgentChatMessages> {
  final _scrollController = ScrollController();
  bool _isAtBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final atBottom = _scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 40;
      if (atBottom != _isAtBottom) setState(() => _isAtBottom = atBottom);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(currentChatStateProvider);
    final colors = context.appColors;
    final isEmpty =
        chatState.messages.isEmpty && chatState.streamingSegments.isEmpty;

    if (isEmpty) {
      return EmptyStateView(
        icon: AgentIcons.quill,
        title: '开始今天的写作',
        subtitle: '告诉我你想写什么，或从下方提示开始一段新的章节。',
        iconWidget: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: colors.chatButtonPrimary.withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(
                color: colors.chatButtonPrimary.withValues(alpha: 0.20)),
          ),
          child: Icon(AgentIcons.quill,
              size: 30, color: colors.chatButtonPrimary),
        ),
        titleStyle: AppTypography.novelTitle.copyWith(fontSize: 17),
      );
    }

    return Stack(children: [
      ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: chatState.messages.length + (chatState.isLoading ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == chatState.messages.length) {
            // 流式尾气泡
            return AgentMessageBubble(
              message: AgentChatMessage(role: AgentChatRole.assistant),
              streamingSegments: chatState.streamingSegments,
            );
          }
          final m = chatState.messages[i];
          if (m.role == AgentChatRole.marker) {
            // marker 走 CompactionMarkerCard，需 CompactionMarkerSegment
            final seg = m.segments.isNotEmpty ? m.segments.first : null;
            if (seg is CompactionMarkerSegment) {
              return CompactionMarkerCard(segment: seg);
            }
            return const SizedBox.shrink();
          }
          return AgentMessageBubble(
            message: m,
            showTimestamp: true,
            onRollback: m.role == AgentChatRole.user
                ? () => widget.onRollback?.call(m)
                : null,
          );
        },
      ),
      if (!_isAtBottom)
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.small(
            onPressed: () => _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            ),
            backgroundColor: colors.agentAccent,
            foregroundColor: colors.agentOnBrand,
            child: const Icon(Icons.keyboard_arrow_down),
          ),
        ),
    ]);
  }
}
