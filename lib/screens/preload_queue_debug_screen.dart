import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/preload_service.dart';
import '../core/providers/service_providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../widgets/common/confirm_dialog.dart';

/// 统计卡片定义（4 张，与 PreloadService 数据层对应）
enum _StatCard {
  queue('队列长度', Icons.list_alt),
  status('处理状态', Icons.sync),
  processed('已处理', Icons.check_circle_outline),
  failed('已失败', Icons.error_outline);

  const _StatCard(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// 预加载队列调试页面
///
/// 顶部 4 张统计卡片可点击切换选中态，
/// 下方详情面板按选中卡展示对应队列信息。
/// 所有章节项均显示可读标题，不再暴露 URL。
class PreloadQueueDebugScreen extends ConsumerStatefulWidget {
  const PreloadQueueDebugScreen({super.key});

  @override
  ConsumerState<PreloadQueueDebugScreen> createState() =>
      _PreloadQueueDebugScreenState();
}

class _PreloadQueueDebugScreenState
    extends ConsumerState<PreloadQueueDebugScreen> {
  late final PreloadService _preloadService;
  Map<String, dynamic> _stats = {};
  Timer? _refreshTimer;

  /// 当前选中的统计卡片索引
  int _selectedIndex = 0;

  /// 是否正在清空队列
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _preloadService = ref.read(preloadServiceProvider);
    _refreshStats();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _refreshStats());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refreshStats() {
    if (!mounted) return;
    setState(() {
      _stats = _preloadService.getStatistics();
    });
  }

  Future<void> _clearQueue() async {
    setState(() => _isClearing = true);
    try {
      await _preloadService.clearQueue();
      _refreshStats();
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  // ─── 统计卡片值 ─────────────────────────────────────

  String _statValue(_StatCard card) {
    switch (card) {
      case _StatCard.queue:
        return '${_stats['queue_length'] ?? 0}';
      case _StatCard.status:
        final isProcessing = _stats['is_processing'] == true;
        final isPaused = _stats['is_paused'] == true;
        if (isPaused) return '已暂停';
        return isProcessing ? '处理中' : '空闲';
      case _StatCard.processed:
        return '${_stats['total_processed'] ?? 0}';
      case _StatCard.failed:
        return '${_stats['total_failed'] ?? 0}';
    }
  }

  Color _statColor(_StatCard card) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (card) {
      case _StatCard.queue:
        return colorScheme.primary;
      case _StatCard.status:
        final isProcessing = _stats['is_processing'] == true;
        return isProcessing ? Colors.orange : Colors.green;
      case _StatCard.processed:
        return Colors.green;
      case _StatCard.failed:
        final count = _stats['total_failed'] as int? ?? 0;
        return count > 0 ? Colors.red : colorScheme.outline;
    }
  }

  // ─── 详情面板构建 ───────────────────────────────────

  Widget _buildDetailPanel() {
    final card = _StatCard.values[_selectedIndex];
    switch (card) {
      case _StatCard.queue:
        return _buildQueueDetail();
      case _StatCard.status:
        return _buildStatusDetail();
      case _StatCard.processed:
        return _buildProcessedDetail();
      case _StatCard.failed:
        return _buildFailedDetail();
    }
  }

  Widget _buildQueueDetail() {
    final snapshot = _preloadService.getQueueSnapshot();
    if (snapshot.isEmpty) return _buildEmpty('队列为空');
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: snapshot.length,
      itemBuilder: (context, index) {
        final task = snapshot[index];
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              '${index + 1}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          title: Text(task.displayTitle),
          trailing: Text(
            '第${task.chapterIndex + 1}章',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      },
    );
  }

  Widget _buildStatusDetail() {
    final colorScheme = Theme.of(context).colorScheme;
    final isProcessing = _stats['is_processing'] == true;
    final isPaused = _stats['is_paused'] == true;
    final current = _preloadService.currentTask;

    final children = <Widget>[];

    // 处理状态标识
    children.add(
      Card(
        color: isPaused
            ? colorScheme.errorContainer
            : isProcessing
                ? colorScheme.tertiaryContainer
                : colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                isPaused
                    ? Icons.pause_circle
                    : isProcessing
                        ? Icons.sync
                        : Icons.check_circle,
                color: isPaused
                    ? colorScheme.error
                    : isProcessing
                        ? Colors.orange
                        : Colors.green,
              ),
              const SizedBox(width: 8),
              Text(
                isPaused
                    ? '已暂停 — 阅读器优先'
                    : isProcessing
                        ? '正在处理'
                        : '空闲 — 等待任务',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
      ),
    );

    // 当前处理中的任务
    if (current != null) {
      children.add(
        ListTile(
          dense: true,
          leading: const Icon(Icons.play_arrow, color: Colors.orange),
          title: Text(current.displayTitle),
          subtitle: const Text('正在获取内容…'),
        ),
      );
    }

    // 最后活跃小说
    final lastNovel = _stats['last_active_novel'] as String?;
    if (lastNovel != null) {
      children.add(
        ListTile(
          dense: true,
          leading: Icon(Icons.book, size: 20, color: colorScheme.primary),
          title: Text(lastNovel, overflow: TextOverflow.ellipsis),
          subtitle: const Text('最后活跃小说'),
        ),
      );
    }

    // 各小说处理进度
    final novelStates = _stats['novel_states'] as Map<String, dynamic>?;
    if (novelStates != null && novelStates.isNotEmpty) {
      children.add(const Divider(height: 16));
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            '各小说进度',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      );
      for (final entry in novelStates.entries) {
        final novelUrl = entry.key;
        final chapterNum = entry.value;
        children.add(
          ListTile(
            dense: true,
            leading:
                Icon(Icons.menu_book, size: 20, color: colorScheme.primary),
            title: Text(
              novelUrl,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '第$chapterNum章',
                style: TextStyle(fontSize: 12, color: colorScheme.onPrimaryContainer),
              ),
            ),
          ),
        );
      }
    }

    if (children.length == 1 && current == null && lastNovel == null) {
      return _buildEmpty('暂无活跃任务');
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _buildProcessedDetail() {
    final history = _preloadService.getProcessedHistory();
    if (history.isEmpty) return _buildEmpty('暂无已处理记录');
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final entry = history[index];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.check_circle, color: Colors.green, size: 20),
          title: Text(entry.displayTitle),
          subtitle: Text(_formatTime(entry.time)),
        );
      },
    );
  }

  Widget _buildFailedDetail() {
    final history = _preloadService.getFailedHistory();
    if (history.isEmpty) return _buildEmpty('暂无失败记录');
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final entry = history[index];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.error, color: Colors.red, size: 20),
          title: Text(entry.displayTitle),
          subtitle: entry.error != null
              ? Text(
                  entry.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.red.shade300, fontSize: 12),
                )
              : null,
        );
      },
    );
  }

  // ─── 通用组件 ───────────────────────────────────────

  Widget _buildEmpty(String message) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_outlined,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              message,
              style: AppTypography.bodyProse.copyWith(
                fontSize: 14,
                color: context.appColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // ─── 页面构建 ───────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cards = _StatCard.values;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '预加载队列',
          style: AppTypography.chapterTitle.copyWith(fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshStats,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshStats(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 统计卡网格（4 张：2×2）──
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.0,
              children: [
                for (var i = 0; i < cards.length; i++)
                  _buildStatCard(cards[i], i),
              ],
            ),
            const SizedBox(height: 16),

            // ── 选中卡详情面板 ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(cards[_selectedIndex].icon, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          cards[_selectedIndex].label,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    _buildDetailPanel(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── 操作按钮 ──
            FilledButton.icon(
              onPressed: _isClearing
                  ? null
                  : () async {
                      final confirmed = await ConfirmDialog.show(
                        context,
                        title: '清空队列',
                        message: '确定要清空所有预加载任务吗？',
                        isDangerous: true,
                      );
                      if (confirmed == true) {
                        await _clearQueue();
                      }
                    },
              icon: _isClearing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_forever, size: 18),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              label: const Text('清空队列'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(_StatCard card, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _statColor(card);
    final isSelected = _selectedIndex == index;

    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.18)
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: colorScheme.primary, width: 2)
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(card.icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  FittedBox(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _statValue(card),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
