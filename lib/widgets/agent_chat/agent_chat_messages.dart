import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/chat_session_providers.dart';
import '../../core/providers/scenario_sessions_provider.dart';
import '../../core/providers/agent_chat_state.dart';
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

  /// 吸底跟随：在底部（或点过回底按钮）时内容变高自动追到最新；
  /// 手动上滑翻历史即解除。程序化 jumpTo/animateTo 不产生
  /// UserScrollNotification，因此不会误关跟随。
  bool _followBottom = true;

  /// 回底迭代进行中标记（按钮连点 / 流式更新与按钮同时触发时防重入）。
  bool _scrollingToBottom = false;

  /// 判定"在底部"的容差（像素）
  static const double _bottomSlack = 40;

  /// 判定 maxScrollExtent 已收敛的容差（像素）
  static const double _extentSettledSlack = 24;

  /// 追底迭代上限：每轮至少前进一个 cacheExtent，
  /// 防止流式内容持续增长时死循环。
  static const int _maxCatchUpRounds = 30;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateAtBottom);
    // 打开长会话时直接落到最新消息（与 _isAtBottom 初始 true 的语义一致）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _goToBottom(animated: false);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _updateAtBottom() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - _bottomSlack;
    if (atBottom != _isAtBottom) setState(() => _isAtBottom = atBottom);
  }

  /// 用户手势滚动：翻回历史解除吸底，手动滑到最新消息则恢复跟随。
  ///
  /// 注意 ScrollDirection 描述的是"内容移动方向"而非 offset 方向：
  /// forward = 内容下滑、露出更早的消息（常规列表上手指下拉，即往上翻）；
  /// reverse = 内容上移、露出更晚的消息（朝最新消息方向滚）。
  bool _onUserScroll(UserScrollNotification notification) {
    if (notification.direction == ScrollDirection.forward) {
      _followBottom = false;
    } else if (notification.direction == ScrollDirection.reverse) {
      _followBottom = notification.metrics.pixels >=
          notification.metrics.maxScrollExtent - _bottomSlack;
    }
    return false;
  }

  /// 滚到真实底部。
  ///
  /// ListView.builder 懒加载下 maxScrollExtent 由已 build item 的平均高度
  /// 外推估算，长上下文里尚未 build 的消息往往比均值高，一次 animateTo 只能
  /// 到估算出的"假底部"；滚过去后新 item 才 build、maxScrollExtent 随之
  /// 变大，因此循环追赶直到 maxScrollExtent 不再增长。
  Future<void> _goToBottom({required bool animated}) async {
    if (_scrollingToBottom) return;
    _scrollingToBottom = true;
    try {
      for (var round = 0; round < _maxCatchUpRounds; round++) {
        if (!mounted || !_scrollController.hasClients || !_followBottom) {
          return;
        }
        final target = _scrollController.position.maxScrollExtent;
        if (animated && round == 0) {
          await _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(target);
        }
        if (!mounted || !_scrollController.hasClients || !_followBottom) {
          return;
        }
        // jumpTo 只同步改 pixels，maxScrollExtent 要等下一帧 layout 才更新；
        // 必须先等一帧再比较，否则第一轮就会误判"已收敛"
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_scrollController.hasClients || !_followBottom) {
          return;
        }
        final grew = _scrollController.position.maxScrollExtent - target;
        if (grew.abs() < _extentSettledSlack) return; // 已到真实底部
      }
    } finally {
      _scrollingToBottom = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(currentChatStateProvider);
    final colors = context.appColors;
    final isEmpty =
        chatState.messages.isEmpty && chatState.streamingSegments.isEmpty;

    // 吸底跟随：跟随状态下内容变高（新消息 / 流式增长 / 历史加载完成）时
    // 追到最新；用户上滑翻历史时（_followBottom == false）不打扰阅读位置。
    ref.listen<AgentChatState>(currentChatStateProvider, (prev, next) {
      if (!_followBottom) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_followBottom || !_scrollController.hasClients) {
          return;
        }
        if (_scrollController.position.pixels <
            _scrollController.position.maxScrollExtent - _bottomSlack) {
          _goToBottom(animated: false);
        }
      });
    });

    // 切换会话（历史抽屉选中另一条 / 新建会话）：无条件跳到新会话最新消息
    ref.listen<int?>(currentChatSessionIdProvider, (prev, next) {
      if (prev == next) return;
      _followBottom = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goToBottom(animated: false);
      });
    });

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
      NotificationListener<UserScrollNotification>(
        onNotification: _onUserScroll,
        child: ListView.builder(
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
      ),
      if (!_isAtBottom)
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.small(
            onPressed: () {
              _followBottom = true;
              _goToBottom(animated: true);
            },
            backgroundColor: colors.agentAccent,
            foregroundColor: colors.agentOnBrand,
            child: const Icon(Icons.keyboard_arrow_down),
          ),
        ),
    ]);
  }
}
