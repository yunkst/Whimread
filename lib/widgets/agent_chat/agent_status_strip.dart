import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/agent_chat_state.dart';
import '../../core/providers/scenario_sessions_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../services/dsl_engine/retry_signals.dart';
import 'agent_icons.dart';

/// 状态条种类
enum AgentStatusKind { error, retry, supplement, running }

/// 单条状态（同一时刻最多 1 条）
@immutable
class AgentStatus {
  final AgentStatusKind kind;
  final String message;
  final String? detail;
  final int? countdownSeconds;
  final VoidCallback? onAction;
  final String? actionLabel;

  const AgentStatus(
    this.kind,
    this.message, {
    this.detail,
    this.countdownSeconds,
    this.onAction,
    this.actionLabel,
  });
}

/// 优先级：error > retry > supplement。isLoading 普通态返回 null（靠消息流流式光标）。
AgentStatus? selectStatus(AgentChatState chatState, RetryState? retry) {
  if (chatState.error != null && !chatState.isLoading) {
    return AgentStatus(AgentStatusKind.error, chatState.error!);
  }
  if (retry != null) {
    final levelLabel = retry.level == RetryLevel.transport ? '传输层' : '回合层';
    final cat = retry.errorCategory.label;
    final http =
        retry.httpStatusCode != null ? ' · HTTP ${retry.httpStatusCode}' : '';
    return AgentStatus(
      AgentStatusKind.retry,
      '网络重试',
      detail: '$levelLabel · ${retry.attempt}/${retry.maxAttempts} · $cat$http',
      countdownSeconds: (retry.delayMs / 1000).ceil(),
    );
  }
  if (chatState.isLoading && chatState.supplementaryCount > 0) {
    return AgentStatus(
      AgentStatusKind.supplement,
      '已补充 ${chatState.supplementaryCount} 条消息',
      detail: '将在下一轮处理',
    );
  }
  // running 兜底：纯运行态（非重试 / 无补充）——消息流顶部渲染
  // 「正在生成…」+ 停止按钮入口（按钮回调由 AgentStatusStrip.onStop 注入）。
  if (chatState.isLoading) {
    return const AgentStatus(AgentStatusKind.running, '正在生成…');
  }
  return null;
}

/// 统一状态条：error/retry/supplement/running 4 选 1，消息流顶部。
/// 自包含 retry 倒计时（订阅 RetrySignals + Timer.periodic）。
/// running/supplement/retry 三种运行态右侧带「停止」按钮（[onStop] 注入），
/// error（非运行态）不带。
/// 取代原 RetryBanner + _buildErrorBar + _buildStopBar + _buildSupplementBar。
class AgentStatusStrip extends ConsumerStatefulWidget {
  /// 停止当前生成。运行态（retry/supplement/running）时渲染停止按钮；
  /// null 时不渲染（向后兼容，如纯函数单测）。
  final VoidCallback? onStop;

  const AgentStatusStrip({super.key, this.onStop});
  @override
  ConsumerState<AgentStatusStrip> createState() => _AgentStatusStripState();
}

class _AgentStatusStripState extends ConsumerState<AgentStatusStrip> {
  Timer? _timer;
  int _countdown = 0;
  int _lastAttempt = -1;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    _countdown = seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(currentChatStateProvider);
    final retry = RetrySignals.instance.notifier.value;
    final status = selectStatus(chatState, retry);

    if (status?.kind == AgentStatusKind.retry) {
      final attempt = retry!.attempt;
      if (attempt != _lastAttempt) {
        _lastAttempt = attempt;
        _startCountdown(status!.countdownSeconds ?? 0);
      }
    } else {
      _timer?.cancel();
      _countdown = 0;
      _lastAttempt = -1;
    }

    if (status == null) return const SizedBox.shrink();

    final colors = context.appColors;
    final isError = status.kind == AgentStatusKind.error;
    final accent = isError ? colors.error : colors.chatButtonPrimary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: accent.withValues(alpha: isError ? 0.08 : 0.14),
        // 左侧 accent 条用 border 实现（borderRadius 与 uniform color 才合法）
        border: Border(
          left: BorderSide(width: 3, color: accent),
        ),
      ),
      child: Row(
        children: [
          if (status.kind == AgentStatusKind.retry ||
              status.kind == AgentStatusKind.running)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            )
          else
            Icon(isError ? Icons.error_outline : Icons.edit_note,
                size: 16, color: accent),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(status.message,
                    style: TextStyle(fontSize: 11.5, color: colors.ink)),
                if (status.detail != null) ...[
                  const SizedBox(height: 1),
                  Text(status.detail!,
                      style: TextStyle(
                          fontSize: 10.5,
                          color: colors.chatHintText,
                          fontFamily: 'JetBrainsMono')),
                ],
              ],
            ),
          ),
          if (status.kind == AgentStatusKind.retry && _countdown > 0)
            Text('${_countdown}s',
                style: TextStyle(
                    fontSize: 11,
                    color: accent,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'JetBrainsMono')),
          if (widget.onStop != null &&
              status.kind != AgentStatusKind.error) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: '停止生成',
              child: GestureDetector(
                onTap: widget.onStop,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AgentIcons.stop, size: 11, color: colors.error),
                      const SizedBox(width: 3),
                      Text('停止',
                          style: TextStyle(
                              fontSize: 10.5,
                              color: colors.error,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
