/// 启动资源引导页。
///
/// 首次安装 / 资源版本更新时展示：校验本地缓存 → 缺失资源逐项下载
/// （字体 / OCR 模型 / 文生图引擎）。本页是纯 UI——进入/退出的时机由
/// main.dart 的 `_ResourceGate` 根据 `resourceBootstrapNotifierProvider`
/// 状态决定（避免反向 import main.dart 的 HomePage）。
/// - 「跳过」：notifier.skip() 落跳过标记 + 转后台静默补下载，gate 随即
///   放行进 App；对应功能按现有降级路径处理（系统字体 / OCR 提示
///   下载中 / 生图 engine_not_ready）。同一 manifest 版本内不再弹页。
/// - 失败项可「重试」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/resource_bootstrap_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/app_resource_manager.dart';

/// 资源条目展示名
String _displayName(String id) => switch (id) {
      ResourceIds.uiFonts => '阅读字体（Noto 宋体/黑体）',
      ResourceIds.ocrModel => 'OCR 识别模型（反爬字体还原）',
      ResourceIds.sdEngine => '本地文生图引擎',
      _ => id,
    };

class ResourceBootstrapScreen extends ConsumerWidget {
  const ResourceBootstrapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(resourceBootstrapNotifierProvider);

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '准备阅读资源',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontFamily: AppTypography.serif,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '首次使用需要下载以下资源，之后不再重复下载',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.7),
                      ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView(
                    children: [
                      for (final id in state.itemIds)
                        _ResourceTile(state: state.items[id]),
                    ],
                  ),
                ),
                if (state.hasFailure)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '部分资源下载失败，可重试或先跳过（对应功能将暂不可用）',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.appColors.error,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => ref
                            .read(resourceBootstrapNotifierProvider.notifier)
                            .skip(),
                        child: const Text('跳过'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: state.hasFailure
                            ? () => ref
                                .read(resourceBootstrapNotifierProvider
                                    .notifier)
                                .retryFailed()
                            : null,
                        child: const Text('重试失败项'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResourceTile extends StatelessWidget {
  final ResourceItemState? state;

  const _ResourceTile({this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final theme = Theme.of(context);
    String trailing;
    Widget leading;
    switch (s?.status ?? ResourceItemStatus.pending) {
      case ResourceItemStatus.ready:
        trailing = '已完成';
        leading = Icon(Icons.check_circle,
            color: theme.colorScheme.primary, size: 22);
      case ResourceItemStatus.downloading:
        final p = s!.progress;
        trailing = p == null
            ? '下载中…'
            : '下载中 ${(p * 100).toStringAsFixed(0)}%'
                '（${_fmt(s.received)} / ${_fmt(s.total)}）';
        leading = const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        );
      case ResourceItemStatus.failed:
        trailing = '下载失败';
        leading = Icon(Icons.error_outline,
            color: context.appColors.error, size: 22);
      case ResourceItemStatus.checking:
        trailing = '校验中…';
        leading = const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        );
      case ResourceItemStatus.pending:
        trailing = '等待中';
        leading = Icon(Icons.schedule,
            color:
                theme.colorScheme.onSurface.withValues(alpha: 0.4), size: 22);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Text(_displayName(s?.id ?? ''),
                    style: theme.textTheme.bodyLarge),
              ),
              Text(trailing,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  )),
            ],
          ),
          if (s?.status == ResourceItemStatus.downloading &&
              (s!.progress != null))
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 8),
              child: LinearProgressIndicator(
                value: s.progress,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }

  String _fmt(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '$bytes B';
  }
}
