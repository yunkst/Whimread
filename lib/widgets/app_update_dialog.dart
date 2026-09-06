import 'package:flutter/material.dart';
import '../models/app_version.dart';
import '../services/app_update_service.dart';
import '../services/logger_service.dart';
import '../utils/toast_utils.dart';

/// APP更新对话框
///
/// 显示有新版本可用，提供下载更新选项
class AppUpdateDialog extends StatefulWidget {
  final AppVersion version;
  final AppUpdateService updateService;
  final VoidCallback? onUpdateComplete;
  final bool isNewVersion; // 是否是新版本，false表示版本相同但用户选择重新下载

  const AppUpdateDialog({
    super.key,
    required this.version,
    required this.updateService,
    this.onUpdateComplete,
    this.isNewVersion = true,
  });

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  double _downloadProgress = 0.0;
  String _statusMessage = '';
  bool _isDownloading = false;
  bool _isDownloadComplete = false;
  bool _isInstalling = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.new_releases,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            widget.isNewVersion ? '发现新版本' : '重新下载',
            style: const TextStyle(fontSize: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 版本信息
            Text(
              '版本 ${widget.version.version}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '大小: ${widget.version.fileSizeFormatted}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            // 更新日志
            if (widget.version.changelog != null &&
                widget.version.changelog!.isNotEmpty) ...[
              Text(
                '更新内容:',
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.version.changelog!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 下载进度
            if (_isDownloading || _isDownloadComplete) ...[
              if (_isDownloading) ...[
                LinearProgressIndicator(
                  value: _downloadProgress,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
                const SizedBox(height: 8),
                Text(
                  '${(_downloadProgress * 100).toStringAsFixed(0)}% - $_statusMessage',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ] else if (_isDownloadComplete) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '下载完成',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      actions: _buildActions(context),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    if (_isInstalling) {
      return [
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(),
          ),
        ),
      ];
    }

    if (_isDownloadComplete) {
      return [
        TextButton(
          onPressed: _isInstalling ? null : _installApk,
          child: const Text('立即安装'),
        ),
      ];
    }

    if (_isDownloading) {
      return [
        TextButton(
          onPressed: null,
          child: const Text('下载中...'),
        ),
      ];
    }

    return [
      TextButton(
        onPressed: () async {
          await widget.updateService.ignoreVersion(widget.version.version);
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: const Text('稍后提醒'),
      ),
      ElevatedButton(
        onPressed: _startDownload,
        child: Text(widget.isNewVersion ? '立即更新' : '重新下载'),
      ),
    ];
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _statusMessage = '准备下载...';
    });

    final success = await widget.updateService.downloadUpdate(
      version: widget.version,
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
          });
        }
      },
      onStatus: (status) {
        if (mounted) {
          setState(() {
            _statusMessage = status;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isDownloading = false;
        _isDownloadComplete = success;
        _statusMessage = success ? '下载完成' : '下载失败';
      });

      if (success) {
        _installApk();
      } else {
        LoggerService.instance.e(
          'APK下载失败: ${widget.version.version}',
          category: LogCategory.network,
          tags: ['update', 'apk', 'download', 'failed'],
        );
      }
    }
  }

  Future<void> _installApk() async {
    setState(() {
      _isInstalling = true;
    });

    final success =
        await widget.updateService.installUpdate(widget.version.version);

    if (mounted) {
      setState(() {
        _isInstalling = false;
      });

      if (success) {
        Navigator.of(context).pop();
        widget.onUpdateComplete?.call();
      } else {
        LoggerService.instance.e(
          'APK安装失败: ${widget.version.version}',
          category: LogCategory.general,
          tags: ['update', 'apk', 'install', 'failed'],
        );
        ToastUtils.showError('安装失败，请手动安装');
      }
    }
  }
}

/// 显示更新对话框的辅助函数
Future<void> showAppUpdateDialog(
  BuildContext context, {
  required AppVersion version,
  required AppUpdateService updateService,
  VoidCallback? onUpdateComplete,
  bool isNewVersion = true,
}) {
  return showDialog(
    context: context,
    builder: (context) => AppUpdateDialog(
      version: version,
      updateService: updateService,
      onUpdateComplete: onUpdateComplete,
      isNewVersion: isNewVersion,
    ),
  );
}
