import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../services/llm_logger/llm_call_record.dart';
import '../services/llm_logger/llm_logger.dart';
import '../utils/format_utils.dart';
import '../utils/toast_utils.dart';
import '../widgets/common/common_widgets.dart';
import 'llm_log_detail_screen.dart';

/// LLM 调用日志列表页
///
/// 展示前端所有 LLM 请求/响应记录（DSL Engine + AI Agent）。
/// 数据来自 [LlmLogger]，按时间倒序显示（最新在最上方）。
/// 通过监听 [LlmLogger.changeNotifier] 实时刷新。
class LlmLogViewerScreen extends ConsumerStatefulWidget {
  const LlmLogViewerScreen({super.key});

  @override
  ConsumerState<LlmLogViewerScreen> createState() =>
      _LlmLogViewerScreenState();
}

class _LlmLogViewerScreenState extends ConsumerState<LlmLogViewerScreen> {
  /// 当前显示的记录列表
  List<LlmCallRecord> _records = [];

  /// 日志文件总占用字节
  int _totalSize = 0;

  /// 是否正在加载
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    LlmLogger.changeNotifier.addListener(_onChanged);
  }

  @override
  void dispose() {
    LlmLogger.changeNotifier.removeListener(_onChanged);
    super.dispose();
  }

  /// 日志变化回调
  void _onChanged() {
    if (mounted) {
      _loadLogs();
    }
  }

  /// 加载最近记录与总占用
  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final list = await LlmLogger.instance.getRecent(limit: 200);
    final size = await LlmLogger.instance.getTotalSize();
    if (mounted) {
      setState(() {
        _records = list;
        _totalSize = size;
        _isLoading = false;
      });
    }
  }

  /// 清空所有 LLM 调用日志
  Future<void> _clearLogs() async {
    if (_records.isEmpty) {
      ToastUtils.show('日志已为空');
      return;
    }

    final confirmed = await ConfirmDialog.show(
      context,
      title: '确认清空',
      message: '确定要清空所有 LLM 调用日志吗？此操作不可撤销。',
      confirmText: '清空',
      icon: Icons.delete_outline,
      confirmColor: context.appColors.error,
      isDangerous: true,
    );

    if (confirmed == true && mounted) {
      await LlmLogger.instance.clear();
      await _loadLogs();
      if (mounted) {
        ToastUtils.showSuccess('日志已清空');
      }
    }
  }

  /// 复制全部记录摘要到剪贴板
  Future<void> _copyAll() async {
    if (_records.isEmpty) {
      ToastUtils.show('暂无记录可复制');
      return;
    }
    final text = _records.map(_formatRecordForCopy).join('\n\n---\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ToastUtils.showSuccess('已复制 ${_records.length} 条记录');
    }
  }

  /// 单条记录的纯文本格式（用于复制）
  String _formatRecordForCopy(LlmCallRecord r) {
    final status = r.isSuccess ? '成功' : '失败';
    return '[${FormatUtils.formatDateTime(r.timestamp.toLocal())}] '
        '[$status] [${r.model ?? '-'}] [${r.durationText}] '
        '[tokens: ${r.totalTokens ?? '-'}]\n'
        'endpoint: ${r.endpoint}\n'
        'preview: ${r.previewText}'
        '${r.errorMessage != null ? '\nerror: ${r.errorMessage}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'LLM 调用日志',
          style: AppTypography.chapterTitle.copyWith(fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.content_copy),
            tooltip: '复制全部',
            onPressed: _copyAll,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loadLogs,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清空',
            onPressed: _clearLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          // 统计信息条
          Container(
            width: double.infinity,
            color:
                theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '共 ${_records.length} 条 · 占用 ${FormatUtils.formatFileSize(_totalSize)}'
              '${_isLoading ? ' · 加载中...' : ''}',
              style: AppTypography.metaItalic.copyWith(
                color: context.appColors.inkSoft,
              ),
            ),
          ),
          // 列表
          Expanded(
            child: _records.isEmpty
                ? _buildEmpty('暂无 LLM 调用记录')
                : ListView.builder(
                    itemCount: _records.length,
                    itemBuilder: (context, index) {
                      // _records 已按时间倒序（getRecent 优先返回内存缓存，最新在前）
                      final record = _records[index];
                      return _buildRecordCard(record);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 单条记录卡片
  Widget _buildRecordCard(LlmCallRecord record) {
    final theme = Theme.of(context);
    final isSuccess = record.isSuccess;
    final statusColor =
        isSuccess ? theme.colorScheme.tertiary : theme.colorScheme.error;
    final statusIcon = isSuccess ? Icons.check_circle : Icons.error;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        dense: true,
        leading: Icon(statusIcon, color: statusColor, size: 22),
        title: Row(
          children: [
            if (record.model != null)
              Flexible(
                child: Text(
                  record.model!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (record.isStreaming)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '流式',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              record.previewText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${FormatUtils.formatDateTime(record.timestamp.toLocal())} · '
              '${record.durationText} · '
              'tokens: ${record.totalTokens ?? '-'}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LlmLogDetailScreen(recordId: record.id),
            ),
          );
        },
      ),
    );
  }

  /// 空状态占位（参照 preload_queue_debug_screen 的 _buildEmpty 模式）
  Widget _buildEmpty(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 48,
              color: context.appColors.inkSoft.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: AppTypography.bodyProse.copyWith(
                fontSize: 15,
                color: context.appColors.inkSoft,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '触发一次 AI 写作或角色对话后将显示',
              style: AppTypography.metaItalic.copyWith(
                color: context.appColors.inkSoft.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
