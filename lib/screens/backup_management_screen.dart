import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/service_providers.dart';
import '../utils/format_utils.dart';
import '../utils/toast_utils.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../widgets/backup_confirm_dialog.dart';
import '../widgets/backup_progress_dialog.dart';
import '../widgets/restore_confirm_dialog.dart';
import '../widgets/restore_progress_dialog.dart';

/// 备份管理页面
///
/// 提供完整的备份管理功能：
/// - 查看上次备份时间和服务器备份数量
/// - 立即备份（上传到服务器）
/// - 查看服务器备份列表
/// - 恢复指定备份
/// - 删除指定备份
class BackupManagementScreen extends ConsumerStatefulWidget {
  const BackupManagementScreen({super.key});

  @override
  ConsumerState<BackupManagementScreen> createState() =>
      _BackupManagementScreenState();
}

class _BackupManagementScreenState
    extends ConsumerState<BackupManagementScreen> {
  List<Map<String, dynamic>>? _backupList;
  bool _isLoading = false;
  String? _lastBackupTime;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final backupService = ref.read(backupServiceProvider);
    _lastBackupTime = await backupService.getLastBackupTimeText();
    await _loadBackupList();
  }

  /// 加载服务器备份列表
  Future<void> _loadBackupList() async {
    setState(() => _isLoading = true);
    try {
      final backupService = ref.read(backupServiceProvider);
      final apiService = ref.read(apiServiceWrapperProvider);
      final list = await backupService.getBackupList(apiWrapper: apiService);
      if (mounted) {
        setState(() {
          _backupList = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _backupList ??= [];
        ToastUtils.showError('获取备份列表失败: $e');
      }
    }
  }

  /// 立即备份
  Future<void> _handleBackupNow() async {
    try {
      final backupService = ref.read(backupServiceProvider);
      final apiService = ref.read(apiServiceWrapperProvider);

      // 获取数据库文件（用于估算备份包大小）
      final dbFile = await backupService.getDatabaseFile();
      final fileSize = await dbFile.length();
      final fileName = dbFile.path.split('/').last;
      final fileSizeText = FormatUtils.formatFileSize(fileSize);

      // 显示确认对话框（含 Token 排除选项）
      if (!mounted) return;
      final confirmResult = await BackupConfirmDialog.show(
        context: context,
        fileName: fileName,
        fileSize: fileSizeText,
      );

      if (!confirmResult.confirmed) return;

      // 显示进度对话框并执行上传
      if (!mounted) return;
      await BackupProgressDialog.show(
        context: context,
        uploadTask: () => backupService.uploadBackup(
          apiWrapper: apiService,
          excludeToken: confirmResult.excludeToken,
        ),
      );

      // 刷新状态
      _lastBackupTime = await backupService.getLastBackupTimeText();
      await _loadBackupList();
      if (mounted) {
        setState(() {});
        ToastUtils.show(confirmResult.excludeToken ? '备份成功（不含 API Token）' : '备份成功');
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.show('备份失败: $e');
      }
    }
  }

  /// 删除备份
  Future<void> _handleDelete(int index) async {
    final backup = _backupList![index];
    final backupId = backup['backup_id'] as String;
    final fileName = backup['filename'] as String? ?? backupId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除服务器上的备份 "$fileName" 吗？\n此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: context.appColors.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final backupService = ref.read(backupServiceProvider);
      final apiService = ref.read(apiServiceWrapperProvider);
      await backupService.deleteBackupOnServer(
        apiWrapper: apiService,
        backupId: backupId,
      );
      await _loadBackupList();
      if (mounted) {
        ToastUtils.show('备份已删除');
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('删除失败: $e');
      }
    }
  }

  /// 恢复备份
  Future<void> _handleRestore(int index) async {
    final backup = _backupList![index];
    final backupId = backup['backup_id'] as String;
    final fileName = backup['filename'] as String? ?? '未知';
    final fileSize = backup['file_size'] as int? ?? 0;
    final uploadedAt = backup['uploaded_at'] as String? ?? '未知';

    // 显示恢复确认对话框
    if (!mounted) return;
    final confirmed = await RestoreConfirmDialog.show(
      context: context,
      fileName: fileName,
      fileSize: fileSize,
      uploadedAt: uploadedAt,
    );

    if (!confirmed) return;

    // 显示恢复进度对话框并执行
    if (!mounted) return;
    final success = await RestoreProgressDialog.show(
      context: context,
      restoreTask: (updateState) async {
        final backupService = ref.read(backupServiceProvider);
        final apiService = ref.read(apiServiceWrapperProvider);

        updateState(RestoreState.downloading);
        await backupService.restoreBackup(
          apiWrapper: apiService,
          backupId: backupId,
        );

        updateState(RestoreState.restoring);
      },
    );

    if (success && mounted) {
      // 更新备份时间显示
      final backupService = ref.read(backupServiceProvider);
      _lastBackupTime = await backupService.getLastBackupTimeText();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '备份管理',
          style: AppTypography.chapterTitle.copyWith(fontSize: 18),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadBackupList,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 状态卡片 ──
            _buildStatusCard(),
            const SizedBox(height: 16),

            // ── 立即备份按钮 ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _handleBackupNow,
                icon: const Icon(Icons.backup_rounded),
                label: const Text('立即备份'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),

            // ── 标题行 ──
            Row(
              children: [
                const Icon(Icons.cloud_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  '服务器备份列表',
                  style: AppTypography.novelTitle.copyWith(
                    fontSize: 15,
                    color: context.appColors.ink,
                  ),
                ),
                const Spacer(),
                if (_backupList != null)
                  Text(
                    '${_backupList!.length} 条',
                    style: AppTypography.metaItalic.copyWith(
                      color: context.appColors.inkSoft,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // ── 备份列表 ──
            if (_isLoading && _backupList == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_backupList == null)
              const SizedBox()
            else if (_backupList!.isEmpty)
              _buildEmptyState()
            else
              ..._backupList!.asMap().entries.map(
                    (entry) => _buildBackupListItem(entry.key, entry.value),
                  ),
          ],
        ),
      ),
    );
  }

  /// 状态卡片
  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline,
                    size: 20, color: context.appColors.info),
                const SizedBox(width: 8),
                Text(
                  '备份状态',
                  style: AppTypography.novelTitle.copyWith(
                    fontSize: 15,
                    color: context.appColors.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatusRow(
              '上次备份',
              _lastBackupTime ?? '加载中...',
            ),
            const SizedBox(height: 8),
            _buildStatusRow(
              '服务器备份',
              _backupList != null ? '${_backupList!.length} 条' : '加载中...',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: AppTypography.metaItalic.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Text(': '),
        Expanded(
          child: Text(
            value,
            style: AppTypography.bodyProse.copyWith(
              fontSize: 14,
              color: context.appColors.ink,
            ),
          ),
        ),
      ],
    );
  }

  /// 空状态
  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined,
              size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            '暂无服务器备份',
            style: AppTypography.bodyProse.copyWith(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '点击上方"立即备份"按钮创建第一个备份',
            style: AppTypography.metaItalic.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 备份列表项
  Widget _buildBackupListItem(int index, Map<String, dynamic> backup) {
    final fileName = backup['filename'] as String? ?? '未知文件';
    final fileSize = backup['file_size'] as int? ?? 0;
    final uploadedAt = backup['uploaded_at'] as String? ?? '未知时间';

    // 格式化上传时间
    String timeText = uploadedAt;
    try {
      final dateTime = DateTime.parse(uploadedAt);
      timeText = FormatUtils.formatDateTime(dateTime);
    } catch (_) {}

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 文件图标
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.appColors.infoContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.storage,
                  size: 24, color: context.appColors.onInfoContainer),
            ),
            const SizedBox(width: 12),

            // 文件信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: AppTypography.novelTitle.copyWith(
                      fontSize: 14,
                      color: context.appColors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$timeText  ·  ${FormatUtils.formatFileSize(fileSize)}',
                    style: AppTypography.metaItalic.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // 操作按钮
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'restore':
                    _handleRestore(index);
                    break;
                  case 'delete':
                    _handleDelete(index);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'restore',
                  child: Row(
                    children: [
                      Icon(Icons.restore, size: 20),
                      SizedBox(width: 8),
                      Text('恢复'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline,
                          size: 20, color: context.appColors.error),
                      const SizedBox(width: 8),
                      Text('删除', style: TextStyle(color: context.appColors.error)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
