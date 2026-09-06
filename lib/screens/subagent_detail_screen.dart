import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/subagent_providers.dart';
import '../models/agent_chat_message.dart';
import '../services/novel_agent/agent_event.dart' show AgentToolStatus;
import '../services/novel_agent/subagent_run.dart';

/// 子 Agent 详情页（只读 Agent Chat 视图 + 停止按钮）
///
/// 接收 (sessionId, toolCallId)，从 [SubagentRegistry] 反查 [SubagentRun]。
/// 渲染 `run.chatState.messages` 为 ListView。
///
/// 返回键仅 pop 页面，不取消子 Agent；取消需通过 AppBar 的停止按钮显式触发
/// （调 `run.token?.cancel(reason: '用户主动停止')`）。
/// 任务 23：停止按钮点击后 await `run.done`，按钮置 loading 状态
/// 防止用户在子 Agent 真正退出前重复点击或误以为无效。
///
/// 返回键仅 pop 页面，不取消子 Agent；取消需通过 AppBar 的停止按钮显式触发
///（调 `run.token?.cancel(reason: '用户主动停止')`）。
class SubagentDetailScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String toolCallId;

  const SubagentDetailScreen({
    super.key,
    required this.sessionId,
    required this.toolCallId,
  });

  @override
  ConsumerState<SubagentDetailScreen> createState() =>
      _SubagentDetailScreenState();
}

class _SubagentDetailScreenState extends ConsumerState<SubagentDetailScreen> {
  /// 停止按钮是否正在等待子 Agent 真正退出
  bool _stopping = false;

  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(subagentRegistryProvider);
    final run = registry.getByToolCallId(widget.sessionId, widget.toolCallId);

    if (run == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('子 Agent 详情')),
        body: const Center(child: Text('子 Agent 不存在或已清理')),
      );
    }

    final showStop = !_stopping &&
        (run.state == SubagentRunState.running ||
            run.state == SubagentRunState.pending);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '子 Agent · ${run.task}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_stopping)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (showStop)
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: '停止',
              onPressed: _onStop,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(run: run),
          const Divider(height: 1),
          Expanded(child: _MessageList(run: run)),
        ],
      ),
    );
  }

  /// 停止子 Agent：cancel 令牌 + 等待 run.done 后恢复按钮。
  Future<void> _onStop() async {
    final registry = ref.read(subagentRegistryProvider);
    final run =
        registry.getByToolCallId(widget.sessionId, widget.toolCallId);
    if (run == null) return;
    setState(() => _stopping = true);
    try {
      run.token?.cancel(reason: '用户主动停止');
      await run.done.timeout(const Duration(seconds: 15));
    } catch (_) {
      // 超时不影响 UI 恢复
    }
    if (mounted) setState(() => _stopping = false);
  }
}

/// 顶部信息：任务标题、allowedTools chips、状态标签
class _Header extends StatelessWidget {
  final SubagentRun run;
  const _Header({required this.run});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.task_alt, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '任务：${run.task}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: run.allowedTools.map((t) {
              return Chip(
                label: Text(t, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Chip(
            label: Text(run.state.name, style: const TextStyle(fontSize: 12)),
            backgroundColor: _stateColor(run.state).withValues(alpha: 0.2),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Color _stateColor(SubagentRunState s) {
    switch (s) {
      case SubagentRunState.running:
      case SubagentRunState.pending:
        return Colors.blue;
      case SubagentRunState.completed:
        return Colors.green;
      case SubagentRunState.failed:
        return Colors.red;
      case SubagentRunState.cancelled:
        return Colors.orange;
    }
  }
}

/// 消息列表：遍历 run.chatState.messages，每条走 [_MessageBubble]
class _MessageList extends StatelessWidget {
  final SubagentRun run;
  const _MessageList({required this.run});

  @override
  Widget build(BuildContext context) {
    final messages = run.chatState.messages;
    return ListView.builder(
      itemCount: messages.length,
      itemBuilder: (context, idx) {
        return _MessageBubble(message: messages[idx]);
      },
    );
  }
}

/// 单条消息气泡（简化版，不复用 agent_chat_dialog 的重型组件）
class _MessageBubble extends StatelessWidget {
  final AgentChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.role.name,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 2),
          for (final seg in message.segments) _buildSegment(context, seg),
        ],
      ),
    );
  }

  Widget _buildSegment(BuildContext context, AgentChatSegment seg) {
    final theme = Theme.of(context);
    return switch (seg) {
      TextSegment s => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(s.content, style: theme.textTheme.bodyMedium),
        ),
      ToolCallSegment s => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '🔧 ${s.call.name} (${_toolStatusName(s.call.status)})',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ImageSegment s => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            '[图片: ${s.mediaId}]',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ),
      CompactionMarkerSegment s => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            '[上下文压缩: 删 ${s.droppedMessageCount} 条, 保留 ${s.keptMessageCount} 条]',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ),
    };
  }

  String _toolStatusName(AgentToolStatus status) {
    switch (status) {
      case AgentToolStatus.running:
        return 'running';
      case AgentToolStatus.completed:
        return 'completed';
      case AgentToolStatus.error:
        return 'error';
      case AgentToolStatus.rejected:
        return 'rejected';
    }
  }
}
