/// 崩溃报告弹框。
///
/// App 下次冷启动检测到 native crash dump 时弹出，展示崩溃信息（可选中复制），
/// 主按钮把崩溃报告（kind=native_crash + 附带近期日志）上传到后端。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/feedback_service.dart';

/// 崩溃报告弹框。
///
/// 展示上次 native crash 的 dump 内容（[dumpContent]）+ 环境摘要，提供：
/// - 文本可选中复制（[SelectableText]）
/// - "复制全部"按钮：把完整报告（含版本/设备）写入剪贴板（网络不可用时的兜底）
/// - "上传报告"按钮：经 [FeedbackService] 提交 kind=native_crash 到后端，
///   成功后 pop(true)；失败 inline 红字，弹框不关
/// - "关闭"按钮：pop(false)
///
/// [service] 可注入 fake 供测试（house style，同 StarQuotaRedeemDialog）。
///
/// [barrierDismissible]=false + 无返回键兜底：强制用户先看到崩溃信息。
class CrashReportDialog extends StatefulWidget {
  const CrashReportDialog({
    super.key,
    required this.dumpContent,
    required this.version,
    required this.device,
    this.service,
  });

  /// dump 原文（C handler 写的 signal/fault_addr/backtrace 等）。
  final String dumpContent;

  /// App 版本（version+buildNumber）。
  final String version;

  /// 设备摘要（厂商 型号 Android x SDK y）。
  final String device;

  /// 反馈服务（测试可注入 fake）。
  final FeedbackService? service;

  @override
  State<CrashReportDialog> createState() => _CrashReportDialogState();
}

class _CrashReportDialogState extends State<CrashReportDialog> {
  bool _submitting = false;
  String? _errorText;

  /// dump 首行作为标题素材（如 "Fatal signal 11 (SIGSEGV), code -1 ..."），
  /// 截到 80 字符以内（服务端上限 200，留余量给前缀）。
  String get _dumpHeadline {
    final firstLine =
        widget.dumpContent.split('\n').firstWhere((l) => l.trim().isNotEmpty,
            orElse: () => 'Native crash');
    final head = firstLine.trim();
    return head.length > 80 ? head.substring(0, 80) : head;
  }

  /// 拼接可复制的完整报告文本（纯文本，便于贴到任意位置）。
  String _buildCopyText() {
    return [
      'App 版本：${widget.version}',
      '设备：${widget.device}',
      '',
      '崩溃信息：',
      widget.dumpContent,
    ].join('\n');
  }

  Future<void> _copyAll(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _buildCopyText()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制崩溃信息到剪贴板')),
    );
  }

  Future<void> _upload() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      await (widget.service ?? FeedbackService.instance).submit(
        kind: FeedbackKind.nativeCrash,
        title: 'Native 崩溃：$_dumpHeadline',
        description: widget.dumpContent,
        includeLogs: true,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FeedbackSubmitException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = '上传失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: cs.error, size: 40),
      title: const Text('检测到上次异常退出'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'App 在上次使用时发生了崩溃。非常抱歉带来的不便。\n'
              '可一键上传报告（含近期日志）帮助定位，也可复制后稍后处理：',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            // 环境摘要
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('App 版本：${widget.version}',
                      style: theme.textTheme.bodySmall),
                  Text('设备：${widget.device}',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // dump 内容（可选中复制 + 限高滚动）
            Text('崩溃堆栈：', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      widget.dumpContent,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: TextStyle(color: cs.error, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _submitting ? null : () => _copyAll(context),
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: const Text('复制全部'),
        ),
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _upload,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload_outlined, size: 18),
          label: Text(_submitting ? '上传中...' : '上传报告'),
        ),
      ],
    );
  }
}