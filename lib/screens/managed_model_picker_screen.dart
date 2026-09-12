/// 托管模式 LLM 模型选择页
///
/// 数据源 [managedModelProvider]:
///   - 目录:GET /v1/models(无鉴权)
///   - 选中:SharedPreferences `managed_model_selection`
///
/// 展示规则:
///   - 列表按消耗倍率升序(baseline 最便宜 → 最贵)
///   - 每条副标题展示「消耗速度约是 Flash 的 N 倍」类相对文案
///     (不展示「1 点 = N token」类直白价格)
///
/// 非托管包(打包未注入 BACKEND_BASE_URL)直接隐藏入口。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/build_config.dart';
import '../core/providers/device_quota_provider.dart';
import '../core/providers/managed_model_provider.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../services/device/device_auth_service.dart' show StarRedeemResult;
import '../services/managed_models/managed_model_service.dart';
import '../utils/toast_utils.dart';
import '../widgets/common/library_app_bar.dart';
import '../widgets/star_quota_redeem_dialog.dart';

class ManagedModelPickerScreen extends ConsumerStatefulWidget {
  const ManagedModelPickerScreen({super.key});

  @override
  ConsumerState<ManagedModelPickerScreen> createState() =>
      _ManagedModelPickerScreenState();
}

class _ManagedModelPickerScreenState
    extends ConsumerState<ManagedModelPickerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(managedModelProvider.notifier).refresh();
      // 进页即拉一次最新余额（模型倍率与剩余额度一起看才有意义）
      ref.read(deviceQuotaProvider.notifier).refresh(force: true);
    });
  }

  Future<void> _onSelect(ManagedModel model) async {
    final state = ref.read(managedModelProvider);
    if (state.selectedModelId == model.id) return;
    await ref.read(managedModelProvider.notifier).select(model.id);
    if (!mounted) return;
    ToastUtils.showSuccess('已切换到 ${model.displayName}', context: context);
  }

  Future<void> _onRefresh() async {
    await ref.read(managedModelProvider.notifier).refresh(force: true);
    // 下拉/手动刷新同时拉新余额（额度在别处用 AI 后可能已变化）
    ref.read(deviceQuotaProvider.notifier).refresh(force: true);
    if (!mounted) return;
    final state = ref.read(managedModelProvider);
    if (state.catalog == null) {
      ToastUtils.show('目录刷新失败,使用本地缓存', context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 非托管包 → 直接提示不可用(防御性兜底,正常流程下不会进到此页)
    if (!kHasBundledBackend) {
      return Scaffold(
        appBar: const LibraryAppBar(title: 'AI 模型选择'),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '当前构建未配置托管后端,无法选择模型。',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final state = ref.watch(managedModelProvider);
    final colors = context.appColors;
    final catalog = state.catalog;

    return Scaffold(
      appBar: LibraryAppBar(
        title: 'AI 模型选择',
        actions: [
          IconButton(
            tooltip: '刷新目录',
            icon: const Icon(Icons.refresh),
            onPressed: state.loading ? null : _onRefresh,
          ),
        ],
      ),
      body: _buildBody(state, colors, catalog),
    );
  }

  Widget _buildBody(
    ManagedModelState state,
    AppColors colors,
    ManagedModelCatalog? catalog,
  ) {
    if (catalog == null) {
      if (state.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 48, color: colors.inkSoft),
              const SizedBox(height: 12),
              Text(
                '暂无可用模型',
                style: AppTypography.novelTitle.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                '后端未配置模型目录,或网络暂时不可达。\n点击右上 ↻ 重试',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colors.inkSoft),
              ),
            ],
          ),
        ),
      );
    }

    // 选中已落库但不在目录(目录更新后失效) → 自动落回默认
    final selectedInCatalog = state.selectedModelId == null
        ? null
        : catalog.byId(state.selectedModelId!);
    final selectedId = selectedInCatalog?.id ?? catalog.defaultModel?.id;

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          const _QuotaCard(),
          const SizedBox(height: 12),
          _Header(catalog: catalog, colors: colors),
          const SizedBox(height: 12),
          for (final m in catalog.models)
            _ModelTile(
              model: m,
              rateLabel: catalog.rateLabel(m),
              isSelected: m.id == selectedId,
              accent: colors.agentAccent,
              onTap: () => _onSelect(m),
            ),
          const SizedBox(height: 12),
          _Footer(catalog: catalog, colors: colors),
        ],
      ),
    );
  }
}

/// 顶部剩余额度卡片。
///
/// 数据源 [deviceQuotaProvider]（与 Agent 对话框顶部徽标同一真相源，
/// AI 使用后自动刷新）；点击强刷。余额不可知时降级为浅色提示行，
/// 不渲染警告色惊吓用户。
class _QuotaCard extends ConsumerWidget {
  const _QuotaCard();

  /// 额度耗尽且未兑换过 → 点击弹 Star 兑换对话框；成功后强刷余额。
  Future<void> _onTap(
      BuildContext context, WidgetRef ref,
      {required bool exhaustedNeedsGuide}) async {
    if (exhaustedNeedsGuide) {
      final result = await showDialog<StarRedeemResult>(
        // 卡片常驻页面顶部，弹窗生命周期内不会离场，直接用 build context
        context: context,
        builder: (_) => const StarQuotaRedeemDialog(),
      );
      if (result == null) return;
    }
    ref.read(deviceQuotaProvider.notifier).refresh(force: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final state = ref.watch(deviceQuotaProvider);
    final balance = state.info?.quotaBalance;

    final Color tint;
    final String valueLabel;
    // 一次性 Star 引导：额度耗尽且还没用过兑换机会时，点击直接弹兑换框
    // （已兑换过再引导只会撞后端 ALREADY_REDEEMED，退回强刷行为）
    final exhaustedNeedsGuide =
        balance != null && balance <= 0 && !state.hasRedeemedStar;
    if (balance != null && balance <= 0) {
      tint = colors.error;
      valueLabel = exhaustedNeedsGuide ? '额度已用完 · 点⭐补' : '额度已用完';
    } else if (balance != null && balance <= 20) {
      tint = colors.warning;
      valueLabel = '$balance 点 · 即将耗尽';
    } else if (balance != null) {
      tint = colors.chatButtonPrimary;
      valueLabel = '$balance 点';
    } else {
      tint = colors.inkSoft;
      valueLabel = '暂不可用';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onTap(context, ref,
            exhaustedNeedsGuide: exhaustedNeedsGuide),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: tint.withValues(alpha: 0.20), width: 0.6),
          ),
          child: Row(
            children: [
              Icon(Icons.savings_outlined, size: 18, color: tint),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前剩余额度',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          valueLabel,
                          style: AppTypography.novelTitle.copyWith(
                            fontSize: 16,
                            color: tint,
                          ),
                        ),
                        if (state.loading) ...[
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.refresh, size: 18, color: colors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ManagedModelCatalog catalog;
  final AppColors colors;
  const _Header({required this.catalog, required this.colors});

  @override
  Widget build(BuildContext context) {
    final baseline = catalog.baseline;
    final baseName = baseline?.shortLabel ?? '基准';
    return _InfoBanner(
      icon: Icons.bolt_outlined,
      tint: colors.agentAccent,
      title: '不同模型消耗额度的速度不同',
      subtitle:
          '以下倍率以「$baseName」为基准(最便宜的模型)。倍率越高,处理同等请求消耗的额度越多。',
    );
  }
}

class _Footer extends StatelessWidget {
  final ManagedModelCatalog catalog;
  final AppColors colors;
  const _Footer({required this.catalog, required this.colors});

  @override
  Widget build(BuildContext context) {
    final baseline = catalog.baseline;
    return _InfoBanner(
      icon: Icons.info_outline,
      tint: colors.inkSoft,
      title: null,
      subtitle: '选择会立即应用于后续所有 AI 调用。'
          '${baseline != null ? "当前基准:${baseline.displayName}。" : ""}',
    );
  }
}

/// Header/Footer 复用:同样的 tinted Container + Row(Icon + Text)。
/// 仅标题颜色和背景 alpha 不同,用 tint 颜色驱动。
class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String? title;
  final String subtitle;

  const _InfoBanner({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isHighlighted = title != null;
    return Container(
      padding: EdgeInsets.all(isHighlighted ? 14 : 12),
      decoration: BoxDecoration(
        color: isHighlighted
            ? tint.withValues(alpha: 0.06)
            : colors.divider.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(isHighlighted ? 10 : 8),
        border: isHighlighted
            ? Border.all(color: tint.withValues(alpha: 0.20), width: 0.6)
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: isHighlighted ? 18 : 14, color: tint),
          SizedBox(width: isHighlighted ? 8 : 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: AppTypography.novelTitle.copyWith(
                      fontSize: 13,
                      color: tint,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: isHighlighted ? 12 : 11,
                    color: colors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  final ManagedModel model;
  final String rateLabel;
  final bool isSelected;
  final Color accent;
  final VoidCallback onTap;

  const _ModelTile({
    required this.model,
    required this.rateLabel,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? accent.withValues(alpha: 0.08)
                  : colors.paper,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? accent.withValues(alpha: 0.55)
                    : colors.divider,
                width: isSelected ? 1.0 : 0.6,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              model.displayName,
                              style: AppTypography.novelTitle.copyWith(
                                fontSize: 14,
                                color: colors.ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (model.isBaseline) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '基准',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        rateLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.inkSoft,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (model.description != null &&
                          model.description!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          model.description!,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.inkSoft,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: isSelected ? accent : colors.inkSoft,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}