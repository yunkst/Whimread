import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/native_crash_reporter.dart' show kGitHubRepo;
import 'ai_settings_screen.dart';
import 'prompt_tag_management_screen.dart';
import 'agent_memory_management_screen.dart';
import 'backend_settings_screen.dart';
import 'log_report_settings_screen.dart';
import 'log_viewer_screen.dart';
import 'llm_log_viewer_screen.dart';
import '../widgets/common/library_app_bar.dart';
import 'preload_queue_debug_screen.dart';
import '../services/app_update_service.dart';
import '../services/logger_service.dart';
import '../widgets/app_update_dialog.dart';
import '../utils/toast_utils.dart';
import '../core/providers/theme_provider.dart';
import '../core/providers/service_providers.dart';
import '../core/database/database_connection.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../screens/onboarding/onboarding_screen.dart';
import 'backup_management_screen.dart';
import 'media_cache_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  PackageInfo? _packageInfo;
  bool _isCheckingUpdate = false;
  bool _isPreviewChannel = false;
  String? _lastBackupTime;
  bool _isRepairing = false;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _loadLastBackupTime();
    _loadPreviewChannel();
  }

  Future<void> _loadPreviewChannel() async {
    final enabled = await AppUpdateService.isPreviewChannelEnabled();
    if (mounted) {
      setState(() {
        _isPreviewChannel = enabled;
      });
    }
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _packageInfo = info;
      });
    }
  }

  /// 加载上次备份时间
  Future<void> _loadLastBackupTime() async {
    final backupService = ref.read(backupServiceProvider);
    final timeText = await backupService.getLastBackupTimeText();
    if (mounted) {
      setState(() {
        _lastBackupTime = timeText;
      });
    }
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _isCheckingUpdate = true;
    });

    try {
      final updateService = AppUpdateService();
      final previewEnabled =
          await AppUpdateService.isPreviewChannelEnabled();

      final latestVersion = await updateService.checkForUpdate(
        forceCheck: true,
        includePrerelease: previewEnabled,
      );

      if (!mounted) return;

      setState(() {
        _isCheckingUpdate = false;
      });

      if (latestVersion != null) {
        // 比较当前版本和最新版本
        final currentInfo = await PackageInfo.fromPlatform();
        final isNewVersion = updateService.hasNewVersion(
          currentInfo.version,
          latestVersion.version,
        );

        // 显示更新对话框
        if (mounted) {
          await showAppUpdateDialog(
            context,
            version: latestVersion,
            updateService: updateService,
            isNewVersion: isNewVersion,
          );
        }
      } else {
        // 显示已是最新版本
        if (mounted) {
          ToastUtils.show('当前已是最新版本');
        }
      }
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '检查更新失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.network,
        tags: ['update', 'check', 'failed'],
      );
      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
        });
        if (mounted) {
          ToastUtils.showError('检查更新失败: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听主题提供者
    final themeAsync = ref.watch(themeNotifierProvider);
    final appColors = context.appColors;

    return Scaffold(
      appBar: LibraryAppBar(title: '设置'),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── AI 组 ─────────────────────────────────────────────
          _SettingsSection(
            icon: Icons.auto_awesome_outlined,
            title: 'AI',
            accentColor: appColors.agentAccent,
            subtitle: '智能助手 · 模型配置 · 主题偏好',
            children: [
              ListTile(
                leading: Icon(Icons.smart_toy, color: appColors.agentAccent),
                title: const Text('AI 配置'),
                subtitle: const Text('配置全局默认 LLM 和 AI 设定'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AiSettingsScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.label_outline, color: appColors.agentAccent),
                title: const Text('提示词标签管理'),
                subtitle: const Text('管理 AI 写作的标签分类和 Prompt 文本'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PromptTagManagementScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.psychology_outlined, color: appColors.agentAccent),
                title: const Text('Agent 记忆管理'),
                subtitle: const Text('查看和管理 Agent 各场景的经验记忆'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const AgentMemoryManagementScreen(),
                    ),
                  );
                },
              ),
              themeAsync.when(
                data: (themeState) {
                  return ListTile(
                    leading:
                        Icon(Icons.palette_outlined, color: appColors.agentAccent),
                    title: const Text('主题模式'),
                    subtitle: Text(_getThemeModeText(themeState.themeMode)),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () => _showThemeModeDialog(themeState),
                  );
                },
                loading: () => ListTile(
                  leading:
                      Icon(Icons.palette_outlined, color: appColors.agentAccent),
                  title: const Text('主题模式'),
                  subtitle: const Text('加载中...'),
                ),
                error: (_, __) => ListTile(
                  leading:
                      Icon(Icons.palette_outlined, color: appColors.agentAccent),
                  title: const Text('主题模式'),
                  subtitle: const Text('加载失败'),
                ),
              ),
            ],
          ),

          // ── 数据组 ────────────────────────────────────────────
          _SettingsSection(
            icon: Icons.storage_outlined,
            title: '数据',
            accentColor: appColors.success,
            subtitle: '数据库 · 应用日志',
            children: [
              ListTile(
                leading: _isRepairing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.build_outlined, color: appColors.success),
                title: const Text('修复数据库'),
                subtitle: const Text('补全缺失的表和列（不影响现有数据）'),
                trailing:
                    _isRepairing ? null : const Icon(Icons.arrow_forward_ios),
                onTap: _isRepairing ? null : _handleRepairDatabase,
              ),
              ListTile(
                leading: Icon(Icons.bug_report_outlined, color: appColors.success),
                title: const Text('应用日志'),
                subtitle: const Text('查看、复制或清空应用日志'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LogViewerScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.smart_toy_outlined, color: appColors.success),
                title: const Text('LLM 调用日志'),
                subtitle: const Text('查看前端 LLM 请求/响应记录'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LlmLogViewerScreen(),
                    ),
                  );
                },
              ),
            ],
          ),

          // ── 诊断组 ────────────────────────────────────────────
          _SettingsSection(
            icon: Icons.health_and_safety_outlined,
            title: '诊断',
            accentColor: appColors.warning,
            subtitle: '队列监控 · 媒体缓存',
            children: [
              ListTile(
                leading: Icon(Icons.downloading, color: appColors.warning),
                title: const Text('预加载队列'),
                subtitle: const Text('查看和管理预加载任务'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PreloadQueueDebugScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library_outlined,
                    color: appColors.warning),
                title: const Text('媒体缓存'),
                subtitle: const Text('管理 AI 生成图/视频与上传图片缓存'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MediaCacheScreen(),
                    ),
                  );
                },
              ),
            ],
          ),

          // ── 新手组 ────────────────────────────────────────────
          _SettingsSection(
            icon: Icons.menu_book_outlined,
            title: '新手',
            accentColor: appColors.info,
            subtitle: '快速入门',
            children: [
              ListTile(
                leading: Icon(Icons.help_outline, color: appColors.info),
                title: const Text('新手引导'),
                subtitle: const Text('重新查看首次启动引导'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const OnboardingScreen(isReviewMode: true),
                      fullscreenDialog: true,
                    ),
                  );
                },
              ),
            ],
          ),

          // ── 关于组 ────────────────────────────────────────────
          _SettingsSection(
            icon: Icons.info_outline,
            title: '关于',
            accentColor: appColors.neutral,
            subtitle: '应用信息 · 版本更新',
            children: [
              ListTile(
                leading: Icon(Icons.info_outline, color: appColors.neutral),
                title: const Text('关于应用'),
                subtitle: Text(
                  _packageInfo != null
                      ? '版本 ${_packageInfo!.version} (${_packageInfo!.buildNumber})'
                      : '加载中...',
                ),
              ),
              ListTile(
                leading: _isCheckingUpdate
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.system_update_alt, color: appColors.neutral),
                title: const Text('检查更新'),
                subtitle: Text(
                  _isPreviewChannel ? '当前通道：预览版' : '查看是否有新版本可用',
                ),
                trailing:
                    _isCheckingUpdate ? null : const Icon(Icons.arrow_forward_ios),
                onTap: _isCheckingUpdate ? null : _checkForUpdate,
              ),
              SwitchListTile(
                secondary: Icon(Icons.bug_report_outlined, color: appColors.neutral),
                title: const Text('获取预览版'),
                subtitle: const Text('开启后可收到最新的预览版本'),
                value: _isPreviewChannel,
                onChanged: (value) async {
                  // 关闭预览版通道不需要确认，直接关闭
                  if (!value) {
                    await AppUpdateService.setPreviewChannelEnabled(false);
                    setState(() {
                      _isPreviewChannel = false;
                    });
                    return;
                  }

                  // 开启预览版通道需要确认
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('⚠️ 开启预览版通道'),
                      content: const Text(
                        '预览版极不稳定，可能存在崩溃、数据丢失等问题，强烈不建议开启。\n\n'
                        '仅建议开发者和测试人员在专用设备上使用。\n\n'
                        '确定要继续开启吗？',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('确认开启', style: TextStyle(color: Colors.orange)),
                        ),
                      ],
                    ),
                  );

                  if (confirmed != true) return;

                  await AppUpdateService.setPreviewChannelEnabled(true);
                  setState(() {
                    _isPreviewChannel = true;
                  });
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.feedback_outlined, color: appColors.neutral),
                title: const Text('问题反馈'),
                subtitle: const Text('报告 Bug 或提出功能建议'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: _openFeedback,
              ),
            ],
          ),

          // ── 支持项目组 ────────────────────────────────────────
          _SettingsSection(
            icon: Icons.star_outline,
            title: '支持项目',
            accentColor: appColors.warning,
            subtitle: '去 GitHub 点 Star',
            children: [
              ListTile(
                leading: Icon(Icons.star_outline, color: appColors.warning),
                title: const Text('支持项目 · 去 GitHub 点 Star'),
                subtitle: const Text('「随心阅读」是开源免费项目，欢迎点 Star 支持'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () async {
                  try {
                    await launchUrl(Uri.parse(kGitHubRepo),
                        mode: LaunchMode.externalApplication);
                  } catch (_) {
                    // 异常吞掉（无浏览器等）
                  }
                },
              ),
            ],
          ),

          // ── 进阶服务组（默认折叠）─────────────────────────────
          _SettingsSection(
            icon: Icons.cloud_outlined,
            title: '进阶服务',
            accentColor: appColors.neutral,
            subtitle: '后端部署 · 数据备份 · 远程日志',
            badgeLabel: '进阶',
            initiallyExpanded: false,
            children: [
              ListTile(
                leading: Icon(Icons.settings_ethernet, color: appColors.neutral),
                title: const Text('后端服务配置'),
                subtitle: const Text('本地部署后端后可解锁云备份、AI 出图'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BackendSettingsScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.backup_rounded, color: appColors.neutral),
                title: const Text('数据备份'),
                subtitle: Text(_lastBackupTime != null
                    ? '上次备份: $_lastBackupTime'
                    : '上传/下载小说数据库到自建后端'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BackupManagementScreen(),
                    ),
                  ).then((_) => _loadLastBackupTime());
                },
              ),
              ListTile(
                leading: Icon(Icons.cloud_upload_outlined, color: appColors.neutral),
                title: const Text('日志上报'),
                subtitle: const Text('诊断用，向自建后端匿名上报日志'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LogReportSettingsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 打开 GitHub issues/new 页,GitHub 会显示 3 个 Issue Forms 模板选择器
  /// (Bug 报告 / 功能建议 / 提问),由用户自行选择。
  ///
  /// 异常吞掉(无浏览器等),与「支持项目 → 去 GitHub 点 Star」入口范式一致。
  Future<void> _openFeedback() async {
    try {
      await launchUrl(
        Uri.parse('$kGitHubRepo/issues/new'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // 静默
    }
  }

  /// 获取主题模式显示文本
  String _getThemeModeText(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return '亮色模式';
      case AppThemeMode.dark:
        return '暗色模式';
      case AppThemeMode.system:
        return '跟随系统';
    }
  }

  /// 显示主题模式选择对话框
  void _showThemeModeDialog(ThemeState themeState) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('选择主题模式'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return RadioGroup<AppThemeMode>(
                groupValue: themeState.themeMode,
                onChanged: (AppThemeMode? value) {
                  if (value != null) {
                    ref
                        .read(themeNotifierProvider.notifier)
                        .setThemeMode(value);
                    Navigator.pop(context);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<AppThemeMode>(
                      title: const Text('亮色模式'),
                      subtitle: const Text('使用浅色主题'),
                      value: AppThemeMode.light,
                    ),
                    RadioListTile<AppThemeMode>(
                      title: const Text('暗色模式'),
                      subtitle: const Text('使用深色主题'),
                      value: AppThemeMode.dark,
                    ),
                    RadioListTile<AppThemeMode>(
                      title: const Text('跟随系统'),
                      subtitle: const Text('跟随系统设置自动切换'),
                      value: AppThemeMode.system,
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  /// 处理数据库修复
  Future<void> _handleRepairDatabase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修复数据库'),
        content: const Text(
            '将重新执行所有数据库迁移，补全缺失的表和列。\n此操作不会删除现有数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认修复'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isRepairing = true;
    });

    try {
      final connection = DatabaseConnection();
      await connection.repairDatabase();

      if (mounted) {
        setState(() {
          _isRepairing = false;
        });
        ToastUtils.show('数据库修复完成');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRepairing = false;
        });
        ToastUtils.showError('数据库修复失败: $e');
      }
    }
  }
}

/// 设置页分组标题旁的次级色小徽章，参考 onboarding "可选" 徽章样式
class _AdvancedBadge extends StatelessWidget {
  const _AdvancedBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.outline.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 设置页分组卡片（书馆美学风格）
///
/// 顶部 section header（图标 + 衬线大字 + 可选副标题），
/// 下方承载一组业务 ListTile，圆角 12，elevation 0。
///
/// 当 [initiallyExpanded] 非 null 时，启用折叠：用 ExpansionTile 承载，
/// 默认折叠（false）或默认展开（true），标题右侧可挂 [badgeLabel] 小徽章。
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.accentColor,
    required this.children,
    this.subtitle,
    this.initiallyExpanded,
    this.badgeLabel,
  });

  final IconData icon;
  final String title;
  final Color accentColor;
  final List<Widget> children;
  final String? subtitle;

  /// 非 null 时启用折叠；true=默认展开，false=默认折叠。null=不折叠（向后兼容既有 6 个分组）
  final bool? initiallyExpanded;

  /// 非 null 时在标题右侧显示一个小徽章（次级色），用于标记「进阶」分组
  final String? badgeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (initiallyExpanded != null) {
      // 折叠分组：用 ExpansionTile 直接作为容器（children 内放 ListTile + Divider 列表）
      // 方案 B：不包 Card，避免与 ExpansionTile 自带形状产生双边框
      final List<Widget> body = [];
      for (var i = 0; i < children.length; i++) {
        body.add(children[i]);
        if (i != children.length - 1) {
          body.add(Divider(
            height: 0,
            thickness: 0.4,
            indent: 16,
            endIndent: 16,
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ));
        }
      }

      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.6,
          ),
          color: colorScheme.surface,
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded!,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          backgroundColor: Colors.transparent,
          collapsedBackgroundColor: Colors.transparent,
          iconColor: accentColor,
          collapsedIconColor: accentColor,
          title: Row(
            children: [
              Icon(icon, size: 16, color: accentColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTypography.shelfTitle.copyWith(
                  fontSize: 14,
                  color: colorScheme.onSurface,
                ),
              ),
              if (badgeLabel != null) ...[
                const SizedBox(width: 6),
                _AdvancedBadge(label: badgeLabel!),
              ],
              if (subtitle != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ],
          ),
          children: body,
        ),
      );
    }

    // 非折叠：原 Card 渲染（既有 6 个分组行为完全不变）
    final List<Widget> body = [];
    for (var i = 0; i < children.length; i++) {
      body.add(children[i]);
      if (i != children.length - 1) {
        body.add(Divider(
          height: 0,
          thickness: 0.4,
          indent: 16,
          endIndent: 16,
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ));
      }
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 0.6,
        ),
      ),
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.08),
              border: Border(
                bottom: BorderSide(
                  color: accentColor.withValues(alpha: 0.25),
                  width: 0.6,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: accentColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: AppTypography.shelfTitle.copyWith(
                    fontSize: 14,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (badgeLabel != null) ...[
                  const SizedBox(width: 6),
                  _AdvancedBadge(label: badgeLabel!),
                ],
                if (subtitle != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...body,
        ],
      ),
    );
  }
}
