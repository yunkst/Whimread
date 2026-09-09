/// 设备额度徽标（AI 剩余点数）
///
/// 展示规则（数据源 [deviceQuotaProvider]，60s 缓存）：
/// - 非托管包 / 余额不可知（未注册、查询失败且无旧值）→ 不渲染任何内容
/// - 余额 > 20 → 主色「AI 剩余 N 点」
/// - 20 ≥ 余额 > 0 → 警告色，提示即将耗尽
/// - 余额 = 0 → 错误色「额度已用完」
/// 点击强制刷新（绕过缓存）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/build_config.dart';
import '../../core/providers/device_quota_provider.dart';
import '../../core/theme/app_colors.dart';
import 'agent_icons.dart';

class QuotaBadge extends ConsumerStatefulWidget {
  const QuotaBadge({super.key});

  @override
  ConsumerState<QuotaBadge> createState() => _QuotaBadgeState();
}

class _QuotaBadgeState extends ConsumerState<QuotaBadge> {
  @override
  void initState() {
    super.initState();
    // build 后再触发，避免 initState 中修改 provider 状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(deviceQuotaProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 非托管包：客户端 LLM 走用户自配，无额度概念，直接隐藏
    if (!kHasBundledBackend) return const SizedBox.shrink();

    final state = ref.watch(deviceQuotaProvider);
    final info = state.info;
    // 余额不可知（未注册/查询失败且无旧值）：隐藏不打扰
    if (info == null && !state.loading) return const SizedBox.shrink();

    final colors = context.appColors;
    final balance = info?.quotaBalance;
    final Color color;
    final String label;
    if (state.loading && info == null) {
      color = colors.inkSoft;
      label = 'AI 额度 …';
    } else if (balance != null && balance <= 0) {
      color = colors.error;
      label = '额度已用完';
    } else if (balance != null && balance <= 20) {
      color = colors.warning;
      label = 'AI 剩余 $balance 点';
    } else {
      color = colors.chatButtonPrimary;
      label = balance == null ? 'AI 额度 …' : 'AI 剩余 $balance 点';
    }

    return InkWell(
      onTap: () => ref.read(deviceQuotaProvider.notifier).refresh(force: true),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AgentIcons.quill, size: 12, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: balance != null && balance <= 20
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
            if (state.loading) ...[
              const SizedBox(width: 5),
              SizedBox(
                width: 9,
                height: 9,
                child: CircularProgressIndicator(
                    strokeWidth: 1.4, color: colors.inkSoft),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
