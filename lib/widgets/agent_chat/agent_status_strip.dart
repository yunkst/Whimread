import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/agent_chat_state.dart';
import '../../core/providers/device_quota_provider.dart';
import '../../core/providers/scenario_sessions_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../services/device/device_auth_service.dart';
import '../../services/dsl_engine/retry_signals.dart';
import '../../widgets/star_quota_redeem_dialog.dart';
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

  /// 是否挂了「Star 补额度」类动作（测试/断言辅助：以动作标签是否存在为准）
  bool get hasAction => actionLabel != null && onAction != null;
}

/// 优先级：error > retry > supplement。isLoading 普通态返回 null（靠消息流流式光标）。
///
/// [onQuotaAction]：额度耗尽错误（`chatState.quotaExhausted`）时挂到
/// [AgentStatus.onAction] 的回调——UI 层弹「点 Star 补充免费额度」对话框。
/// 纯函数本身不依赖 BuildContext，便于单测。
///
/// [hasRedeemedStar]：本机是否已完成过 Star 兑换（一次性权益）。已兑换过
/// 的用户额度再耗尽时不再挂 Star 动作（后端必回 ALREADY_REDEEMED，引导是
/// 死胡同），错误文案保持原样引导去设置页查看；未兑换过则改写文案明确
/// 指向 Star 补充。
AgentStatus? selectStatus(
  AgentChatState chatState,
  RetryState? retry, {
  VoidCallback? onQuotaAction,
  bool hasRedeemedStar = false,
}) {
  if (chatState.error != null && !chatState.isLoading) {
    final isQuota = chatState.quotaExhausted;
    final canGuideStar = isQuota && !hasRedeemedStar;
    return AgentStatus(
      AgentStatusKind.error,
      canGuideStar ? '免费额度已用完 · 去 GitHub 点 ⭐ 可免费补充一次' : chatState.error!,
      actionLabel: canGuideStar ? '去 Star 补额度' : null,
      onAction: canGuideStar ? onQuotaAction : null,
    );
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

  /// 额度耗尽时弹出 Star 兑换对话框。闭包里拿 context（widget 已 mounted），
  /// 用 mount 守卫防止 widget 在异步对话框生命周期内被卸载。
  ///
  /// 兑换成功（result 非 null）→ 强刷共享额度状态（绕过 60s 缓存，与设置页
  /// 入口行为一致）；余额与已兑换标记一并更新，错误条上的 Star 动作随即消失。
  Future<void> _openStarRedeemDialog() async {
    if (!mounted) return;
    final result = await showDialog<StarRedeemResult>(
      context: context,
      builder: (_) => const StarQuotaRedeemDialog(),
    );
    if (result == null || !mounted) return;
    await ref.read(deviceQuotaProvider.notifier).refresh(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(currentChatStateProvider);
    final retry = RetrySignals.instance.notifier.value;
    final status = selectStatus(
      chatState,
      retry,
      onQuotaAction: _openStarRedeemDialog,
      // 已兑换标记与余额同源（quota 刷新时一并加载）；未拉到前按
      // false 处理——宁可多引导一次，也不漏引导
      hasRedeemedStar: ref.watch(deviceQuotaProvider).hasRedeemedStar,
    );

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
          // 额度耗尽专属动作按钮（与「停止」互斥：error 态不该有停止按钮）
          if (isError &&
              status.actionLabel != null &&
              status.onAction != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: status.onAction,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.chatButtonPrimary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, size: 11, color: Colors.white),
                    const SizedBox(width: 3),
                    Text(status.actionLabel!,
                        style: const TextStyle(
                            fontSize: 10.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
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
