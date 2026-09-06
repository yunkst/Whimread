/// 崩溃报告弹框。
///
/// App 下次冷启动检测到 native crash dump 时弹出，展示崩溃信息（可选中复制），
/// 并引导用户前往 GitHub 提 issue。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 崩溃报告弹框。
///
/// 展示上次 native crash 的 dump 内容（[dumpContent]）+ 环境摘要，提供：
/// - 文本可选中复制（[SelectableText]）
/// - "复制全部"按钮：把完整报告（含版本/设备）写入剪贴板
/// - "前往 GitHub 提 Issue"按钮：返回 true 让调用方 [launchUrl]
/// - "关闭"按钮：返回 false
///
/// [barrierDismissible]=false + 无返回键兜底：强制用户先看到崩溃信息。
class CrashReportDialog extends StatelessWidget {
  const CrashReportDialog({
    super.key,
    required this.dumpContent,
    required this.version,
    required this.device,
  });

  /// dump 原文（C handler 写的 signal/fault_addr/backtrace 等）。
  final String dumpContent;

  /// App 版本（version+buildNumber）。
  final String version;

  /// 设备摘要（厂商 型号 Android x SDK y）。
  final String device;

  /// 拼接可复制的完整报告文本（纯文本，便于贴到任意位置）。
  String _buildCopyText() {
    return [
      'App 版本：$version',
      '设备：$device',
      '',
      '崩溃信息：',
      dumpContent,
    ].join('\n');
  }

  Future<void> _copyAll(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _buildCopyText()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制崩溃信息到剪贴板')),
    );
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
              '请将以下信息提交到 GitHub，帮助我们定位问题：',
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
                  Text('App 版本：$version',
                      style: theme.textTheme.bodySmall),
                  Text('设备：$device', style: theme.textTheme.bodySmall),
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
                      dumpContent,
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
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _copyAll(context),
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: const Text('复制全部'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('前往 GitHub'),
        ),
      ],
    );
  }
}
