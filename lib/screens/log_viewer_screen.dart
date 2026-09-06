import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/logger_service.dart';
import '../core/providers/service_providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/log_level_colors.dart';
import '../utils/toast_utils.dart';
import '../widgets/common/common_widgets.dart';
import '../widgets/common/library_app_bar.dart';

/// "全部级别" / "全部分类" 菜单项的 sentinel。
///
/// 之所以需要它：Flutter 的 PopupMenuItem 对 value:null 故意跳过点击
/// （"If itemBuilder returns an item with a null value, the item will not be
/// selectable."），点 null 不会触发 onSelected。我们用 const Object() 作为
/// 不可点击之外的另一个稳定值，绕过这条限制，onSelected 里再用 identical
/// 判别还原成"不过滤"。
const Object _kNoFilterSentinel = Object();

/// 把菜单回调里的 sentinel 解码回 nullable 过滤值（sentinel → null）。
T? _decodeNoFilter<T>(Object? value) =>
    identical(value, _kNoFilterSentinel) ? null : value as T?;

/// 日志查看页面
///
/// 提供应用日志的查看、过滤、搜索、导出和清空功能。
/// 日志按时间倒序显示（最新日志在最上方），支持按级别、分类过滤和关键词搜索。
class LogViewerScreen extends ConsumerStatefulWidget {
  const LogViewerScreen({super.key});

  @override
  ConsumerState<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends ConsumerState<LogViewerScreen> {
  /// 当前选择的日志级别过滤器
  LogLevel? _selectedLevel;

  /// 当前选择的日志分类过滤器
  LogCategory? _selectedCategory;

  /// 搜索关键词
  String _searchQuery = '';

  /// 当前显示的日志列表
  late List<LogEntry> _displayedLogs;

  /// 是否正在导出
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    // 监听日志变化
    LoggerService.logChangeNotifier.addListener(_onLogChanged);
  }

  @override
  void dispose() {
    // 移除监听器
    LoggerService.logChangeNotifier.removeListener(_onLogChanged);
    super.dispose();
  }

  /// 日志变化回调
  void _onLogChanged() {
    // 当日志发生变化时重新加载
    if (mounted) {
      setState(() {
        _loadLogs();
      });
    }
  }

  /// 从LoggerService加载日志
  void _loadLogs() {
    final loggerService = ref.read(loggerServiceProvider);
    List<LogEntry> logs;

    if (_searchQuery.isNotEmpty) {
      // 搜索模式
      logs = loggerService.searchLogs(
        _searchQuery,
        category: _selectedCategory,
      );
      if (_selectedLevel != null) {
        logs = logs.where((log) => log.level == _selectedLevel).toList();
      }
    } else if (_selectedLevel != null && _selectedCategory != null) {
      // 同时按级别和分类过滤
      logs = loggerService
          .getLogsByCategory(_selectedCategory!)
          .where((log) => log.level == _selectedLevel)
          .toList();
    } else if (_selectedLevel != null) {
      logs = loggerService.getLogsByLevel(_selectedLevel);
    } else if (_selectedCategory != null) {
      logs = loggerService.getLogsByCategory(_selectedCategory!);
    } else {
      logs = loggerService.getLogs();
    }

    _displayedLogs = logs;
  }

  /// 判断是否有活跃的过滤器
  bool get _hasActiveFilter =>
      _selectedLevel != null ||
      _selectedCategory != null ||
      _searchQuery.isNotEmpty;

  /// 清除所有过滤器
  void _clearFilters() {
    setState(() {
      _selectedLevel = null;
      _selectedCategory = null;
      _searchQuery = '';
      _loadLogs();
    });
  }

  /// 复制所有日志到剪贴板
  ///
  /// 将当前过滤后的所有日志格式化为纯文本后复制到剪贴板。
  void _copyAllLogs() async {
    if (_displayedLogs.isEmpty) {
      ToastUtils.show('暂无日志可复制');
      return;
    }

    final text = _displayedLogs.map((log) {
      final stackTrace = log.stackTrace != null ? '\n${log.stackTrace}' : '';
      return '[${LoggerService.formatTimestamp(log.timestamp)}] [${log.level.label}] [${log.category.label}] ${log.message}$stackTrace';
    }).join('\n\n---\n\n');

    await Clipboard.setData(ClipboardData(text: text));

    if (mounted) {
      ToastUtils.showSuccess('已复制 ${_displayedLogs.length} 条日志到剪贴板');
    }
  }

  /// 导出日志到文件
  ///
  /// 调用 LoggerService.exportToFile 将所有日志导出为文本文件。
  Future<void> _exportLogs() async {
    setState(() {
      _isExporting = true;
    });

    try {
      final file = await ref.read(loggerServiceProvider).exportToFile();
      if (mounted) {
        ToastUtils.showSuccess('日志已导出到: ${file.path}');
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('导出失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  /// 清空所有日志
  ///
  /// 显示确认对话框，用户确认后清空所有日志。
  Future<void> _clearLogs() async {
    if (_displayedLogs.isEmpty) {
      ToastUtils.show('日志已为空');
      return;
    }

    final confirmed = await ConfirmDialog.show(
      context,
      title: '确认清空',
      message: '确定要清空所有日志吗？此操作不可撤销。',
      confirmText: '清空',
      icon: Icons.delete_outline,
      confirmColor: context.appColors.error,
    );

    if (confirmed == true && mounted) {
      await ref.read(loggerServiceProvider).clearLogs();
      setState(() {
        _loadLogs();
      });
      ToastUtils.showSuccess('日志已清空');
    }
  }

  /// 获取日志级别的颜色
  Color _getLevelColor(LogLevel level) =>
      LogLevelColors.levelColor(level, context.appColors);

  /// 获取日志分类的颜色
  Color _getCategoryColor(LogCategory category) =>
      LogLevelColors.categoryColor(category);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LibraryAppBar(
        title: '应用日志',
        actions: [
          // 搜索按钮
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showSearchDialog,
            tooltip: '搜索日志',
          ),
          // 分类过滤按钮
          PopupMenuButton<Object?>(
            icon: const Icon(Icons.category_outlined),
            tooltip: '按分类过滤',
            onSelected: (value) {
              setState(() {
                _selectedCategory = _decodeNoFilter<LogCategory>(value);
                _loadLogs();
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem<Object?>(
                value: _kNoFilterSentinel,
                child: Text('全部分类'),
              ),
              const PopupMenuDivider(),
              ...LogCategory.values.map(
                (category) => PopupMenuItem<Object?>(
                  value: category,
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _getCategoryColor(category),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(category.label),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // 级别过滤按钮
          PopupMenuButton<Object?>(
            icon: const Icon(Icons.filter_list),
            tooltip: '按级别过滤',
            onSelected: (value) {
              setState(() {
                _selectedLevel = _decodeNoFilter<LogLevel>(value);
                _loadLogs();
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem<Object?>(
                value: _kNoFilterSentinel,
                child: Text('全部级别'),
              ),
              const PopupMenuDivider(),
              ...LogLevel.values.map(
                (level) => PopupMenuItem<Object?>(
                  value: level,
                  child: Row(
                    children: [
                      Icon(level.icon, size: 18, color: _getLevelColor(level)),
                      const SizedBox(width: 8),
                      Text(level.label),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // 导出按钮
          IconButton(
            icon: _isExporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download),
            onPressed: _isExporting ? null : _exportLogs,
            tooltip: '导出日志文件',
          ),
          // 复制按钮
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyAllLogs,
            tooltip: '复制全部日志',
          ),
          // 上报按钮
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined),
            onPressed: () async {
              final reporter = ref.read(logReporterServiceProvider);
              await reporter.flush();
              if (mounted) {
                ToastUtils.showSuccess('日志已上报');
              }
            },
            tooltip: '上报日志',
          ),
          // 清空按钮
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearLogs,
            tooltip: '清空日志',
          ),
        ],
      ),
      body: _displayedLogs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bug_report_outlined,
                    size: 64,
                    color: context.appColors.inkSoft.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _hasActiveFilter ? '没有匹配的日志' : '暂无日志',
                    style: AppTypography.bodyProse.copyWith(
                      fontSize: 16,
                      color: context.appColors.inkSoft,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // 过滤状态提示
                if (_hasActiveFilter)
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (_selectedLevel != null)
                                Chip(
                                  label: Text(
                                    '级别: ${_selectedLevel!.label}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  avatar: Icon(_selectedLevel!.icon,
                                      size: 14,
                                      color: _getLevelColor(_selectedLevel!)),
                                  onDeleted: () {
                                    setState(() {
                                      _selectedLevel = null;
                                      _loadLogs();
                                    });
                                  },
                                  visualDensity: VisualDensity.compact,
                                ),
                              if (_selectedCategory != null)
                                Chip(
                                  label: Text(
                                    '分类: ${_selectedCategory!.label}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  avatar: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color:
                                          _getCategoryColor(_selectedCategory!),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  onDeleted: () {
                                    setState(() {
                                      _selectedCategory = null;
                                      _loadLogs();
                                    });
                                  },
                                  visualDensity: VisualDensity.compact,
                                ),
                              if (_searchQuery.isNotEmpty)
                                Chip(
                                  label: Text(
                                    '搜索: $_searchQuery',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  avatar: const Icon(Icons.search, size: 14),
                                  onDeleted: () {
                                    setState(() {
                                      _searchQuery = '';
                                      _loadLogs();
                                    });
                                  },
                                  visualDensity: VisualDensity.compact,
                                ),
                              TextButton(
                                onPressed: _clearFilters,
                                child: const Text('清除全部'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_displayedLogs.length} 条',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                // 日志列表
                Expanded(
                  child: ListView.builder(
                    itemCount: _displayedLogs.length,
                    reverse: true,
                    itemBuilder: (context, index) {
                      final log =
                          _displayedLogs[_displayedLogs.length - 1 - index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            log.level.icon,
                            size: 18,
                            color: _getLevelColor(log.level),
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 消息内容
                              Text(
                                log.message,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              // 分类标签
                              Wrap(
                                spacing: 4,
                                children: [
                                  Chip(
                                    label: Text(
                                      log.category.label,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    backgroundColor:
                                        _getCategoryColor(log.category)
                                            .withValues(alpha: 0.2),
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  ...log.tags.map((tag) => Chip(
                                        label: Text(
                                          tag,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.1),
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      )),
                                ],
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                LoggerService.formatTimestamp(log.timestamp),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall!
                                    .copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                              ),
                              if (log.stackTrace != null &&
                                  log.stackTrace!.isNotEmpty)
                                InkWell(
                                  onTap: () {
                                    _showStackTraceDialog(log);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '查看堆栈信息',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall!
                                          .copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          onTap: () => _showLogDetailDialog(log),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  /// 显示搜索对话框
  void _showSearchDialog() {
    final controller = TextEditingController(text: _searchQuery);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('搜索日志'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入关键词搜索日志内容和标签...',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
          ),
          onSubmitted: (_) => _applySearch(controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (_searchQuery.isNotEmpty) {
                setState(() {
                  _searchQuery = '';
                  _loadLogs();
                });
              }
            },
            child: const Text('清除'),
          ),
          FilledButton(
            onPressed: () => _applySearch(controller.text),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
  }

  /// 应用搜索
  void _applySearch(String query) {
    Navigator.pop(context);
    setState(() {
      _searchQuery = query.trim();
      _loadLogs();
    });
  }

  /// 显示堆栈信息对话框
  void _showStackTraceDialog(LogEntry log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(log.level.icon, color: _getLevelColor(log.level)),
            const SizedBox(width: 8),
            const Text('堆栈信息'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              log.stackTrace ?? '无堆栈信息',
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    fontFamily: 'monospace',
                  ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: log.stackTrace ?? ''));
              Navigator.pop(context);
              ToastUtils.showSuccess('已复制堆栈信息');
            },
            child: const Text('复制'),
          ),
        ],
      ),
    );
  }

  /// 单条日志的纯文本格式（用于复制全部信息）
  String _formatLogForCopy(LogEntry log) => LoggerService.formatLogForCopy(log);

  /// 复制单条日志全部信息到剪贴板
  Future<void> _copyLogEntry(LogEntry log) async {
    final text = _formatLogForCopy(log);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ToastUtils.showSuccess('已复制日志全部信息到剪贴板');
    }
  }

  /// 显示日志详情对话框
  ///
  /// 展示单条日志的全部字段（时间/级别/分类/标签/消息/堆栈），
  /// 并提供"复制全部信息"按钮。展示内容与 [_formatLogForCopy] 一致，
  /// 确保"所见即所复制"。
  void _showLogDetailDialog(LogEntry log) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(log.level.icon, color: _getLevelColor(log.level)),
            const SizedBox(width: 8),
            const Text('日志详情'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              _formatLogForCopy(log),
              style: Theme.of(ctx)
                  .textTheme
                  .bodySmall!
                  .copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制全部信息'),
            onPressed: () async {
              await _copyLogEntry(log);
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }
}
