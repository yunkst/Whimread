import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../services/llm_logger/llm_call_record.dart';
import '../services/llm_logger/llm_logger.dart';
import '../utils/format_utils.dart';
import '../utils/toast_utils.dart';

/// LLM 调用日志详情页
///
/// 展示单条 [LlmCallRecord] 的完整信息：概要、请求体、响应体。
/// 请求体/响应体以缩进 JSON 格式化展示，支持选中复制。
class LlmLogDetailScreen extends ConsumerStatefulWidget {
  final String recordId;

  const LlmLogDetailScreen({super.key, required this.recordId});

  @override
  ConsumerState<LlmLogDetailScreen> createState() =>
      _LlmLogDetailScreenState();
}

class _LlmLogDetailScreenState extends ConsumerState<LlmLogDetailScreen> {
  LlmCallRecord? _record;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    final r = await LlmLogger.instance.getById(widget.recordId);
    if (mounted) {
      setState(() {
        _record = r;
        _isLoading = false;
      });
    }
  }

  /// 复制完整记录 JSON 到剪贴板
  Future<void> _copyRecord() async {
    final r = _record;
    if (r == null) return;
    final text = const JsonEncoder.withIndent('  ').convert(r.toJson());
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ToastUtils.showSuccess('已复制完整记录');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '调用详情',
          style: AppTypography.chapterTitle.copyWith(fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制记录',
            onPressed: _record == null ? null : _copyRecord,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _record == null
              ? _buildNotFound()
              : _buildContent(theme, _record!),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off,
              size: 48, color: context.appColors.inkSoft.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            '未找到该记录（可能已被清空）',
            style: AppTypography.bodyProse.copyWith(
              fontSize: 15,
              color: context.appColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, LlmCallRecord r) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummary(theme, r),
          const SizedBox(height: 12),
          _buildSection(
            theme,
            '请求体',
            _formatJsonString(r.requestBody),
          ),
          const SizedBox(height: 12),
          _buildSection(
            theme,
            r.isSuccess ? '响应体' : '响应体（失败）',
            r.responseBody != null
                ? _formatJsonString(r.responseBody!)
                : (r.errorMessage ?? '（无响应体）'),
          ),
          if (r.errorMessage != null && r.responseBody != null) ...[
            const SizedBox(height: 12),
            _buildSection(theme, '错误信息', r.errorMessage!),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 概要信息卡
  Widget _buildSummary(ThemeData theme, LlmCallRecord r) {
    final statusColor =
        r.isSuccess ? theme.colorScheme.tertiary : theme.colorScheme.error;
    final meta = <_MetaEntry>[
      _MetaEntry('时间', FormatUtils.formatDateTime(r.timestamp.toLocal())),
      _MetaEntry('状态', r.isSuccess ? '成功' : '失败',
          valueColor: statusColor),
      _MetaEntry('模型', r.model ?? '-'),
      _MetaEntry('Endpoint', r.endpoint.isEmpty ? '-' : r.endpoint),
      _MetaEntry('流式', r.isStreaming ? '是' : '否'),
      _MetaEntry('耗时', r.durationText),
      _MetaEntry(
          'Tokens',
          'prompt: ${r.promptTokens ?? '-'} · '
              'completion: ${r.completionTokens ?? '-'} · '
              'total: ${r.totalTokens ?? '-'}'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            for (int i = 0; i < meta.length; i++) ...[
              _buildMetaRow(theme, meta[i]),
              if (i < meta.length - 1)
                Divider(
                    height: 1,
                    color: theme.dividerColor.withValues(alpha: 0.3)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetaRow(ThemeData theme, _MetaEntry e) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              e.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              e.value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: e.valueColor ?? theme.colorScheme.onSurface,
                fontFamily: e.label == 'Endpoint' ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 内容分节（参照 agent_message_bubble 的 _buildSection 模式）
  Widget _buildSection(ThemeData theme, String label, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.metaItalic.copyWith(
            fontFamily: AppTypography.sans,
            fontStyle: FontStyle.normal,
            fontWeight: FontWeight.w600,
            color: context.appColors.inkSoft,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:
                theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
          ),
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }

  /// JSON 字符串格式化（先 decode 再缩进输出，参照 agent_message_bubble._formatJsonString）
  String _formatJsonString(String s) {
    try {
      final decoded = jsonDecode(s);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return s;
    }
  }
}

class _MetaEntry {
  final String label;
  final String value;
  final Color? valueColor;
  const _MetaEntry(this.label, this.value, {this.valueColor});
}
