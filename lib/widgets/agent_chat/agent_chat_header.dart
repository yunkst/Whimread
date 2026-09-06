import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/agent_scenario_provider.dart';
import '../../core/providers/agent_chat_state.dart';
import '../../core/providers/chat_session_providers.dart';
import '../../core/providers/reading_context_providers.dart';
import '../../core/providers/scenario_sessions_provider.dart';
import '../../core/providers/webview_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/novel_agent/agent_scenario.dart';
import '../../services/novel_agent/agent_scenario_factory.dart';
import 'agent_icons.dart';
import 'agent_novel_picker_dialog.dart';

class AgentChatHeader extends ConsumerWidget {
  final VoidCallback? onHistory;
  final VoidCallback? onNewSession;
  final VoidCallback? onConfig;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onClose;
  final bool isFullscreen;

  const AgentChatHeader({
    super.key,
    this.onHistory,
    this.onNewSession,
    this.onConfig,
    this.onToggleFullscreen,
    this.onClose,
    this.isFullscreen = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(currentChatStateProvider);
    final colors = context.appColors;
    final isWebview = chatState.scenarioId == ScenarioIds.webviewExtract;

    return Container(
      decoration: BoxDecoration(
        color: colors.paper,
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colors.chatButtonPrimary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                      color: colors.chatButtonPrimary.withValues(alpha: 0.20)),
                ),
                child: Icon(AgentIcons.quill,
                    size: 16, color: colors.chatButtonPrimary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  chatState.scenarioDisplayName,
                  style: AppTypography.novelTitle.copyWith(fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _ScenarioMenu(onConfig: onConfig, onHistory: onHistory),
              IconButton(
                tooltip: isFullscreen ? '退出全屏' : '全屏',
                icon: Icon(
                  isFullscreen
                      ? AgentIcons.fullscreenExit
                      : AgentIcons.fullscreen,
                  size: 19,
                ),
                color: colors.inkSoft,
                onPressed: onToggleFullscreen,
              ),
              IconButton(
                tooltip: '新建会话',
                icon: Icon(AgentIcons.plus, size: 19),
                color: colors.inkSoft,
                onPressed: onNewSession,
              ),
              IconButton(
                tooltip: '关闭',
                icon: Icon(AgentIcons.close, size: 19),
                color: colors.inkSoft,
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 6),
          _ContextLine(isWebview: isWebview, chatState: chatState),
        ],
      ),
    );
  }
}

class _ScenarioMenu extends ConsumerWidget {
  final VoidCallback? onConfig;
  final VoidCallback? onHistory;
  const _ScenarioMenu({this.onConfig, this.onHistory});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final currentId = ref.watch(currentAgentScenarioProvider);
    return PopupMenuButton<String>(
      tooltip: '场景与设置',
      icon: Icon(AgentIcons.dots, size: 19),
      color: colors.paper,
      onSelected: (value) {
        if (value == 'config') {
          onConfig?.call();
          return;
        }
        if (value == 'history') {
          onHistory?.call();
          return;
        }
        // scenarioId -> 切场景（沿用现有 agent_chat_dialog 切换逻辑）
        ref.read(currentAgentScenarioProvider.notifier).state = value;
        ref.read(currentChatSessionIdProvider.notifier).state = null;
        ref.read(scenarioSessionsProvider.notifier).get(value);
      },
      itemBuilder: (_) => [
        for (final s in AgentScenarioFactory.availableScenarios)
          PopupMenuItem(
            value: s.id,
            child: Row(children: [
              Icon(AgentIcons.quill, size: 16, color: colors.chatButtonPrimary),
              const SizedBox(width: 8),
              Expanded(child: Text(s.displayName)),
              if (s.id == currentId)
                Icon(Icons.check, size: 16, color: colors.chatButtonPrimary),
            ]),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'config', child: Text('场景配置')),
        const PopupMenuItem(value: 'history', child: Text('会话历史')),
      ],
    );
  }
}

class _ContextLine extends ConsumerWidget {
  final bool isWebview;
  final AgentChatState chatState;
  const _ContextLine({required this.isWebview, required this.chatState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    if (isWebview) {
      final url = ref.watch(webviewCurrentUrlProvider);
      return InkWell(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Icon(AgentIcons.link, size: 12, color: colors.chatButtonPrimary),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                url.isEmpty ? '当前无页面' : url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    color: colors.inkSoft,
                    fontFamily: 'JetBrainsMono'),
              ),
            ),
          ]),
        ),
      );
    }
    final novel = chatState.currentNovel;
    final readingCtx = ref.watch(readingContextProvider);
    final hasNovel = novel != null;
    final label = StringBuffer();
    if (hasNovel) {
      label.write('阅读《${novel.title}》');
      if (readingCtx.hasContext && readingCtx.chapterTitle != null) {
        label.write(' · ${readingCtx.chapterTitle}');
      }
    } else {
      label.write('尚未选择小说 · 点击选择');
    }
    return InkWell(
      // 未选小说时显示"点击选择"提示；已选小说时仍可点开换书（picker 既可选也可切换）。
      onTap: () => _showNovelPicker(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(AgentIcons.book, size: 13, color: colors.chatButtonPrimary),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label.toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  color: hasNovel ? colors.inkSoft : colors.chatHintText),
            ),
          ),
        ]),
      ),
    );
  }

  /// 弹出小说选择对话框，并把用户选中的 novelId 走 ScenarioSession.selectNovel
  /// 写入当前会话（与 select_novel 工具路径同一入口，UI 即时刷新 + 落库）。
  ///
  /// 注：picker 仅返回 novel.id，selectNovel 内部会用 getNovelById 装配 title/url。
  Future<void> _showNovelPicker(BuildContext context, WidgetRef ref) async {
    final novelId = await showDialog<int>(
      context: context,
      builder: (_) => const AgentNovelPickerDialog(),
    );
    if (novelId == null) return; // 用户取消
    await ref.read(currentSessionProvider)?.selectNovel(novelId);
  }
}
