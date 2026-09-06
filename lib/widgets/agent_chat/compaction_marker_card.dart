import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/agent_chat_message.dart';
import 'agent_icons.dart';

/// 上下文压缩标记卡片（M3 可展开分隔条）
///
/// 折叠态：居中的 `🗂 上下文已压缩 · 丢弃 N 条 ▾` 提示行（整行可点击）。
/// 展开态：4 格统计 + 压缩率 [LinearProgressIndicator] + 不可回溯文案。
/// 颜色约束：`AppColors` 无 `surface` 字段，背景一律用
/// `Theme.of(context).colorScheme.surface`，边框/次级用
/// `context.appColors.inkSoft`，正文用 `context.appColors.ink`。
class CompactionMarkerCard extends StatefulWidget {
  final CompactionMarkerSegment segment;

  const CompactionMarkerCard({super.key, required this.segment});

  @override
  State<CompactionMarkerCard> createState() => _CompactionMarkerCardState();
}

class _CompactionMarkerCardState extends State<CompactionMarkerCard> {
  bool _expanded = false;

  /// 格式化字符数：>=1000 显示成 `420K`，否则原值。
  /// 整千不带小数（`5000` → `5K`），非整千保留 1 位（`420000` → `420K`、
  /// `1500` → `1.5K`）。
  String _fmt(int n) {
    if (n >= 1000) {
      final k = n / 1000;
      final fixed = k == k.roundToDouble() ? 0 : 1;
      return '${k.toStringAsFixed(fixed)}K';
    }
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.segment;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(
                  color:
                      context.appColors.inkSoft.withValues(alpha: 0.3),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AgentIcons.layers,
                      size: 13, color: context.appColors.chatButtonPrimary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '上下文已压缩 · 丢弃 ${s.droppedMessageCount} 条'
                      '${_expanded ? '' : '  ▾'}',
                      style: TextStyle(color: context.appColors.ink),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child:
                _expanded ? _buildExpanded(context, s) : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildExpanded(BuildContext context, CompactionMarkerSegment s) {
    final ratio = s.compressionRatio;
    final ratioPct = (ratio * 100).round();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.appColors.inkSoft.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _stat('释放字符', _fmt(s.removedChars)),
              _stat(
                '压缩前 → 后',
                '${_fmt(s.originalChars)} → ${_fmt(s.compactedChars)}',
              ),
              _stat('丢弃消息', '${s.droppedMessageCount} 条'),
              _stat(
                '保留消息',
                '${s.keptMessageCount} 条'
                '${s.rewrittenCount > 0 ? " (其中 ${s.rewrittenCount} 条 tool result 被改写)" : ""}',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$ratioPct% 被释放',
                style: TextStyle(color: context.appColors.ink),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor:
                        context.appColors.inkSoft.withValues(alpha: 0.2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            s.rewrittenCount > 0
                ? '被压缩/改写的内容不可回溯（预剪枝 1-liner 仅保留结构化摘要）'
                : '被压缩内容不可回溯（当前是简单截断，未生成摘要）',
            style: TextStyle(
              fontSize: 11,
              color: context.appColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: context.appColors.inkSoft),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: context.appColors.ink,
          ),
        ),
      ],
    );
  }
}
