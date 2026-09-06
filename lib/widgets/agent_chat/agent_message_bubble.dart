import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/core/providers/chat_session_providers.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/models/agent_chat_message.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'chapter_rewrite_entry_card.dart';
import 'media_gallery_card.dart';
import 'subagent_tool_card.dart';
import '../../screens/subagent_detail_screen.dart';
import '../media/media_view.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Agent 聊天消息气泡
class AgentMessageBubble extends ConsumerWidget {
  final AgentChatMessage message;
  /// 流式 segments（当前回合进行中时非空，历史消息为 null）
  final List<AgentChatSegment>? streamingSegments;
  final bool showTimestamp;

  /// 回滚回调（仅 user 消息使用）：点击按钮后回滚至此消息,
  /// 由 [AgentChatDialog] 实现确认弹框 + 输入框回填。
  /// 传 null 表示不渲染回滚按钮。
  final VoidCallback? onRollback;

  const AgentMessageBubble({
    super.key,
    required this.message,
    this.streamingSegments,
    this.showTimestamp = true,
    this.onRollback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.role == AgentChatRole.user;

    // 流式气泡用 streamingSegments，历史气泡用 message.segments
    final effectiveSegments = streamingSegments ?? message.segments;
    final isStreaming = streamingSegments != null;

    return Padding(
      // 气泡占满对话框内容区宽度，仅留对称小边距，避免横向空间浪费。
      // user / assistant 的区分由背景色（_getBubbleColor）和时间戳 Row 对齐承担。
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _getBubbleColor(context),
              border: Border.all(
                color: isUser
                    ? context.appColors.chatButtonPrimary
                        .withValues(alpha: 0.20)
                    : context.appColors.divider,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isUser ? 16 : 4),
                topRight: Radius.circular(isUser ? 4 : 16),
                bottomLeft: const Radius.circular(16),
                bottomRight: const Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: context.appColors.avatarShadow
                      .withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: isUser
                ? _buildContent(context)
                : _buildAssistantContent(context, ref, effectiveSegments, isStreaming),
          ),
          if (showTimestamp) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                Text(
                  _formatTime(message.timestamp),
                  style: AppTypography.metaItalic.copyWith(
                    fontSize: 11,
                    color: context.appColors.inkSoft.withValues(alpha: 0.7),
                  ),
                ),
                if (isUser && onRollback != null) ...[
                  const SizedBox(width: 6),
                  _buildRollbackButton(context),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _getBubbleColor(BuildContext context) {
    final c = context.appColors;
    if (message.role == AgentChatRole.user) {
      // 琥珀 wash（用户气泡），不再误用冷蓝 agentAccent
      return c.chatButtonPrimary.withValues(alpha: 0.10);
    }
    // assistant 气泡用纸感底色
    return c.paper;
  }

  /// 回滚按钮（小图标 + tooltip）,仅 user 消息 + onRollback != null 时渲染
  Widget _buildRollbackButton(BuildContext context) {
    final muted = context.appColors.inkSoft.withValues(alpha: 0.7);
    return Tooltip(
      message: '回滚至此',
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onRollback,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            Icons.undo,
            size: 14,
            color: muted,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final segments = message.segments;
    // 无 ImageSegment 时走原文本路径（性能 + 不破坏现有样式）
    final hasImage = segments.any((s) => s is ImageSegment);
    if (!hasImage) {
      return Text(
        message.content,
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: context.appColors.ink,
              height: 1.5,
            ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final seg in segments)
          if (seg is ImageSegment)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 200,
                  maxHeight: 200,
                ),
                child: MediaView(
                  mediaId: seg.mediaId,
                  onTap: () => _showImageFullScreen(context, seg.mediaId),
                ),
              ),
            )
          else if (seg is TextSegment)
            Text(
              seg.content,
              style: AppTypography.bodyProse.copyWith(
                fontSize: 13,
                height: 1.65,
                color: context.appColors.ink,
              ),
            ),
      ],
    );
  }

  /// 图片全屏查看（点击缩略图触发）
  void _showImageFullScreen(BuildContext context, String mediaId) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(child: MediaView(mediaId: mediaId)),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 按 segments 顺序交替渲染文本片段和工具调用卡片
  Widget _buildAssistantContent(
    BuildContext context,
    WidgetRef ref,
    List<AgentChatSegment> segments,
    bool isStreaming,
  ) {
    if (segments.isEmpty) return const SizedBox.shrink();

    final lastIndex = segments.length - 1;
    final sessionId = ref.watch(currentChatSessionIdProvider)?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: segments.asMap().entries.map((entry) {
        final idx = entry.key;
        final segment = entry.value;
        final isLast = idx == lastIndex;

        return switch (segment) {
          TextSegment s => _buildTextSegment(context, s, isStreaming && isLast),
          ToolCallSegment s => Padding(
              padding: EdgeInsets.only(
                // 与上一个元素之间留间距
                top: idx > 0 ? 8 : 0,
                bottom: isLast ? 0 : 4,
              ),
              // dispatch_subagent 走 SubagentToolCard（任务 10），点击跳转详情页（任务 11）。
              // 其他工具走 AgentToolCallCard：onRetry 由 dialog 注入，UI 端只判 running 决定是否显示按钮。
              child: s.call.name == 'dispatch_subagent'
                  ? SubagentToolCard(
                      sessionId: sessionId,
                      toolCallId: s.call.id,
                      task: (s.call.arguments['task'] as String?) ?? '',
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => SubagentDetailScreen(
                            sessionId: sessionId,
                            toolCallId: s.call.id,
                          ),
                        ));
                      },
                    )
                  : AgentToolCallCard(
                      call: s.call,
                      onRetry: () => ref
                          .read(currentSessionProvider)
                          ?.retryToolCall(s.call.id),
                    ),
            ),
          ImageSegment s => ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
              child: MediaView(
                mediaId: s.mediaId,
                onTap: () => _showImageFullScreen(context, s.mediaId),
              ),
            ),
          // CompactionMarkerSegment 在 assistant 流式气泡中不渲染（由独立 CompactionMarkerCard 负责，Task 7）
          CompactionMarkerSegment _ => const SizedBox.shrink(),
        };
      }).toList(),
    );
  }

  Widget _buildTextSegment(
    BuildContext context,
    TextSegment segment,
    bool isStreaming,
  ) {
    final text = segment.content;

    if (isStreaming) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: MarkdownBody(
              data: text,
              styleSheet: _markdownStyle(context),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      );
    }

    if (text.isEmpty) return const SizedBox.shrink();

    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: _markdownStyle(context),
    );
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    return MarkdownStyleSheet(
      p: theme.textTheme.bodyMedium!.copyWith(
        color: colors.ink,
        height: 1.5,
      ),
      h1: AppTypography.chapterTitle.copyWith(
        fontSize: 20,
        color: colors.ink,
      ),
      h2: AppTypography.chapterTitle.copyWith(
        fontSize: 18,
        color: colors.ink,
      ),
      h3: AppTypography.novelTitle.copyWith(
        fontSize: 16,
        color: colors.ink,
      ),
      code: theme.textTheme.bodyMedium?.copyWith(
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        color: theme.colorScheme.primary,
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary,
            width: 3,
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// 可展开的工具调用卡片
///
/// 每个卡片独立管理自己的展开/折叠状态。
/// 使用 StatefulWidget 确保流式更新时不丢失展开状态。
class AgentToolCallCard extends StatefulWidget {
  final AgentToolCall call;
  final VoidCallback? onRetry;

  const AgentToolCallCard({
    super.key,
    required this.call,
    this.onRetry,
  });

  @override
  State<AgentToolCallCard> createState() => _AgentToolCallCardState();
}

class _AgentToolCallCardState extends State<AgentToolCallCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final call = widget.call;

    final statusIcon = switch (call.status) {
      AgentToolStatus.running => Icons.sync,
      AgentToolStatus.completed => Icons.check_circle,
      AgentToolStatus.error => Icons.error,
      AgentToolStatus.rejected => Icons.cancel,
    };
    final statusColor = switch (call.status) {
      AgentToolStatus.running => theme.colorScheme.primary,
      AgentToolStatus.completed => theme.colorScheme.tertiary,
      AgentToolStatus.error => theme.colorScheme.error,
      AgentToolStatus.rejected => theme.colorScheme.outline,
    };

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏（可点击展开/折叠）
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 第一行：状态图标 + 工具名 + 展开箭头
                  Row(
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _runningLabel(call),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: context.appColors.inkSoft.withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                  // 第二行：实时生成字数。独立占行避免挤掉第一行的工具名/展开箭头。
                  // 与第一行文字左侧对齐：图标 14 + 间距 6 = 20
                  Builder(builder: (_) {
                    final progressLine = _progressLine(call);
                    if (progressLine == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 2, 8, 0),
                      child: Text(
                        progressLine,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: statusColor.withValues(alpha: 0.75),
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          // 展开内容
          if (_expanded) _buildExpandedBody(context, call),
          // update_chapter_content / create_chapter 成功时，渲染跳转阅读器入口
          if ((call.name == 'update_chapter_content' || call.name == 'create_chapter') &&
              call.status == AgentToolStatus.completed &&
              _rewriteEntry != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: ChapterRewriteEntryCard(
                data: _rewriteEntry!,
                titleText: call.name == 'create_chapter'
                    ? '查看新创建的章节'
                    : '查看重写后的章节',
              ),
            ),
          // create_images / create_image_to_video 成功时，渲染媒体画廊
          if ((call.name == 'create_images' ||
                  call.name == 'create_image_to_video') &&
              call.status == AgentToolStatus.completed &&
              _mediaGallery != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: MediaGalleryCard(data: _mediaGallery!),
            ),
        ],
      ),
    );
  }

  /// 解析工具结果中的重写成功信息（缓存，避免每次 build 重复解析）
  ChapterRewriteEntryData? get _rewriteEntry =>
      parseRewriteEntry(widget.call.result);

  /// 解析工具结果中的媒体画廊数据（图片或视频，缓存）
  MediaGalleryData? get _mediaGallery =>
      parseMediaGallery(widget.call.result);

  /// 标题栏第一行文案：始终返回工具名（保持单行简洁，进度单独占第二行）。
  String _runningLabel(AgentToolCall call) {
    if (call.status != AgentToolStatus.running) return call.name;
    return call.name;
  }

  /// 标题栏第二行：仅内部走 LLM 流式 + running 阶段展示，避免横向被进度挤掉。
  /// 返回 null 时不渲染第二行，保持非流式工具的原视觉。
  String? _progressLine(AgentToolCall call) {
    if (call.status != AgentToolStatus.running) return null;
    final progress = call.progressChars;
    if (progress == null || progress <= 0) return null;
    return '已生成 $progress 字...';
  }

  Widget _buildExpandedBody(BuildContext context, AgentToolCall call) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 6),
          _buildSection(
            context,
            '参数',
            _formatJson(call.arguments),
          ),
          if (call.result != null) ...[
            const SizedBox(height: 6),
            _buildSection(
              context,
              call.status == AgentToolStatus.error ? '错误' : '结果',
              _formatJsonString(call.result!),
            ),
          ],
          // 重试按钮：仅对已结束工具（completed / error / rejected）显示
          if (call.status != AgentToolStatus.running && widget.onRetry != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: _buildRetryButton(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRetryButton(BuildContext context) {
    final retry = widget.onRetry;
    return Tooltip(
      message: '重试此工具',
      child: TextButton.icon(
        onPressed: retry,
        icon: const Icon(Icons.refresh, size: 14),
        label: const Text('重试', style: TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String label, String content) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.metaItalic.copyWith(
            fontFamily: AppTypography.sans,
            fontStyle: FontStyle.normal,
            fontWeight: FontWeight.w600,
            color: context.appColors.inkSoft,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(4),
          ),
          constraints: const BoxConstraints(maxHeight: 240),
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }

  String _formatJson(Map<String, dynamic> args) {
    try {
      return const JsonEncoder.withIndent('  ').convert(args);
    } catch (_) {
      return args.toString();
    }
  }

  String _formatJsonString(String s) {
    try {
      final decoded = jsonDecode(s);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return s;
    }
  }
}