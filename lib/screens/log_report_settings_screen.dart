import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/log_reporter_service.dart';
import '../services/logger_service.dart';
import '../core/providers/service_providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/log_level_colors.dart';
import '../utils/toast_utils.dart';

/// 日志上报设置页面
class LogReportSettingsScreen extends ConsumerStatefulWidget {
  const LogReportSettingsScreen({super.key});

  @override
  ConsumerState<LogReportSettingsScreen> createState() =>
      _LogReportSettingsScreenState();
}

class _LogReportSettingsScreenState
    extends ConsumerState<LogReportSettingsScreen> {
  @override
  void initState() {
    super.initState();
    LogReporterService.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    LogReporterService.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  String get _levelName {
    final idx = LogReporterService.instance.minLevelIndex;
    if (idx < 0 || idx >= LogLevel.values.length) return '未知';
    return LogLevel.values[idx].label;
  }

  @override
  Widget build(BuildContext context) {
    final reporter = LogReporterService.instance;
    final appColors = context.appColors;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '日志上报',
          style: AppTypography.chapterTitle.copyWith(fontSize: 18),
        ),
      ),
      body: ListView(
        children: [
          // 总开关
          SwitchListTile(
            title: const Text('启用日志上报'),
            subtitle: Text(
              reporter.enabled
                  ? '日志将在满足条件时自动上报到后端'
                  : '日志不上报，仅保留在本地',
            ),
            value: reporter.enabled,
            onChanged: (value) {
              ref.read(logReporterServiceProvider).setEnabled(value);
            },
            secondary: Icon(
              reporter.enabled ? Icons.cloud_upload : Icons.cloud_off,
              color: reporter.enabled
                  ? appColors.agentAccent
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Divider(),

          // 最低上报级别
          ListTile(
            leading: const Icon(Icons.filter_list),
            title: const Text('最低上报级别'),
            subtitle: const Text('低于此级别的日志不会上报'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _levelName,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 16),
              ],
            ),
            onTap: reporter.enabled ? _showLevelPicker : null,
          ),
          const Divider(),

          // 当前状态
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('缓冲区状态'),
            subtitle: Text('${reporter.bufferSize} 条待上报日志'),
          ),
          if (reporter.lastUploadTime != null)
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('上次上报时间'),
              subtitle: Text(
                LoggerService.formatTimestamp(reporter.lastUploadTime!),
              ),
            ),
          if (reporter.isUploading)
            const ListTile(
              leading: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('正在上报中...'),
            ),
          const Divider(),

          // 立即上报按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: FilledButton.icon(
              onPressed: reporter.enabled && !reporter.isUploading
                  ? () async {
                      final reporter = ref.read(logReporterServiceProvider);
                      await reporter.flush();
                      if (mounted) {
                        if (reporter.bufferSize == 0) {
                          ToastUtils.showSuccess('日志已全部上报');
                        } else {
                          ToastUtils.showWarning('部分日志上报失败，将在下次重试');
                        }
                      }
                    }
                  : null,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('立即上报'),
            ),
          ),
          const SizedBox(height: 8),

          // 说明文字
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '日志上报在以下条件满足任一即自动触发：\n'
              '• 缓冲区累积达到 20 条\n'
              '• 距上次上报超过 30 秒\n'
              '• 应用进入后台',
              style: AppTypography.metaItalic.copyWith(
                color: context.appColors.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLevelPicker() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择最低上报级别'),
        children: LogLevel.values.map((level) {
          return SimpleDialogOption(
            onPressed: () {
              ref.read(logReporterServiceProvider).setMinLevel(level);
              Navigator.pop(ctx);
            },
            child: Row(
              children: [
                Icon(level.icon, size: 18, color: _levelColor(level)),
                const SizedBox(width: 12),
                Text(
                  level.label,
                  style: TextStyle(
                    fontWeight: LogReporterService.instance.minLevelIndex == level.index
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: LogReporterService.instance.minLevelIndex == level.index
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                if (LogReporterService.instance.minLevelIndex == level.index)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.check,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _levelColor(LogLevel level) =>
      LogLevelColors.levelColor(level, context.appColors);
}