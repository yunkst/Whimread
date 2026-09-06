/// 主 Agent 气泡里的子任务卡片
///
/// 当 [AgentMessageBubble] 渲染 [ToolCallSegment] 时，识别
/// `call.name == 'dispatch_subagent'` 后用本卡片替代普通 [AgentToolCallCard]。
///
/// 通过 (sessionId, toolCallId) 反查 [SubagentRegistry] 找到对应 [SubagentRun]，
/// 按 [SubagentRunState] 渲染状态图标 + task 标题 + progressSummary。
///
/// 实时刷新说明（方案 C）：当前 SubagentRegistry 不是 ChangeNotifier，
/// 不会主动 notify。本卡片只解决静态渲染；运行中状态变化由上游主气泡
/// 自身的 rebuild（事件回流触发的 ref 更新）顺带刷新本卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/subagent_providers.dart';
import '../../services/novel_agent/subagent_run.dart';

class SubagentToolCard extends ConsumerWidget {
  final String sessionId;
  final String toolCallId;
  final String task;

  /// 点击回调（任务 11 接入：push SubagentDetailScreen）。
  /// 仅在 run 未到 completed 终态时启用；completed 时点击无响应
  /// （避免误触重开已完成的详情页；如需回看请通过列表入口）。
  final VoidCallback? onTap;

  const SubagentToolCard({
    super.key,
    required this.sessionId,
    required this.toolCallId,
    required this.task,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(subagentRegistryProvider);
    final run = registry.getByToolCallId(sessionId, toolCallId);

    final state = run?.state;
    final summary = run?.progressSummary ?? '派发中…';
    final isClickable =
        onTap != null && state != SubagentRunState.completed;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: isClickable ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _iconForState(context, state),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '子 Agent: $task',
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                summary,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconForState(BuildContext context, SubagentRunState? state) {
    switch (state) {
      case null:
      case SubagentRunState.pending:
      case SubagentRunState.running:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: state == SubagentRunState.running
                ? Theme.of(context).colorScheme.primary
                : Colors.grey,
          ),
        );
      case SubagentRunState.completed:
        return const Icon(Icons.check_circle, size: 16, color: Colors.green);
      case SubagentRunState.failed:
        return const Icon(Icons.error, size: 16, color: Colors.red);
      case SubagentRunState.cancelled:
        return const Icon(Icons.cancel, size: 16, color: Colors.orange);
    }
  }
}
