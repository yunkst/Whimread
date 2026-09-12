import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'prompt_tag_management_screen.dart';
import 'agent_memory_management_screen.dart';
import 'image_model_management_screen.dart';
import 'feedback_submit_screen.dart';
import 'log_viewer_screen.dart';
import 'managed_model_picker_screen.dart';
import '../widgets/common/library_app_bar.dart';
import 'preload_queue_debug_screen.dart';
import '../services/app_update_service.dart';
import '../services/device/device_auth_service.dart';
import '../services/logger_service.dart';
import '../widgets/app_update_dialog.dart';
import '../widgets/star_quota_redeem_dialog.dart';
import '../utils/toast_utils.dart';
import '../core/providers/theme_provider.dart';
import '../core/providers/device_quota_provider.dart';
import '../core/providers/managed_model_provider.dart';
import '../core/constants/build_config.dart';
import '../core/database/database_connection.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../screens/onboarding/onboarding_screen.dart';
import 'media_cache_screen.dart';
import '../widgets/diagnostics/attestation_chain_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  PackageInfo? _packageInfo;
  bool _isCheckingUpdate = false;
  bool _isPreviewChannel = false;
  bool _isRepairing = false;

  // 7-tap 关于应用 触发 attestation 证书链诊断面板(供用户遇到安全相关问题时
  // 把诊断文本发给开发者;不显眼以免打扰普通用户)。
  // 窗口 3s 内连续点击才累计,超时重置。
  int _versionTapCount = 0;
  DateTime? _firstTapTime;

  void _handleVersionTap() {
    final now = DateTime.now();
    if (_firstTapTime == null ||
        now.difference(_firstTapTime!) > const Duration(seconds: 3)) {
      _firstTapTime = now;
      _versionTapCount = 1;
      return;
    }
    _versionTapCount++;
    if (_versionTapCount >= 7) {
      _versionTapCount = 0;
      _firstTapTime = null;
      AttestationChainSheet.show(context);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _loadPreviewChannel();
    // 「点 Star 补充 AI 额度」副标题的余额查询统一走 deviceQuotaProvider
    // （与 Agent Chat 顶部 QuotaBadge 同一数据源 + 60s 缓存）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(deviceQuotaProvider.notifier).refresh();
    });
  }

  /// 打开 Star 兑换对话框；成功后强制刷新共享额度状态 + toast 反馈。
  Future<void> _openStarRedeemDialog() async {
    final result = await showDialog<StarRedeemResult>(
      context: context,
      builder: (_) => const StarQuotaRedeemDialog(),
    );
    if (result == null || !mounted) return;
    ToastUtils.showSuccess(
      '${result.message}，当前余额 ${result.quotaBalance} 点',
      context: context,
    );
    // 兑换改变了服务端余额，绕过 60s 缓存强制拉新
    ref.read(deviceQuotaProvider.notifier).refresh(force: true);
  }

  /// 「点 Star 补充 AI 额度」副标题：余额已知时展示具体数字；
  /// 已完成过 Star 兑换（一次性权益）后不再说「可补充」；未配置托管后端 /
  /// 未注册 / 查询失败时回退通用文案。
  String _quotaSubtitle(DeviceQuotaState state) {
    final info = state.info;
    if (info == null) return 'Star 项目可免费补充一次 AI 托管额度';
    if (state.hasRedeemedStar) return '当前余额 ${info.quotaBalance} 点';
    return '当前余额 ${info.quotaBalance} 点 · Star 可补充一次';
  }

  /// 「AI 模型选择」副标题：当前选中模型名 + 倍率文案。
  /// 目录未拉取时回退通用提示,引导用户打开选择页手动触发。
  String _managedModelSubtitle(ManagedModelState state) {
    final catalog = state.catalog;
    final selected = state.selectedModelId;
    if (catalog == null) {
      return state.loading ? '加载目录中…' : '点击选择 AI 模型';
    }
    final id = selected ?? catalog.defaultModel?.id;
    if (id == null) return '点击选择 AI 模型';
    final model = catalog.byId(id);
    if (model == null) return '点击选择 AI 模型';
    return '${model.displayName} · ${catalog.rateLabel(model)}';
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
            subtitle: '智能助手 · 主题偏好',
            children: [
              ListTile(
                leading: Icon(Icons.label_outline, color: appColors.agentAccent),
                title: const Text('写作技巧管理'),
                subtitle: const Text('管理 AI 写作的技巧分类和 Prompt 文本'),
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
                leading: Icon(Icons.image_outlined, color: appColors.agentAccent),
                title: const Text('生图模型管理'),
                subtitle: const Text('导入本地 SD 模型供 Agent 出图'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ImageModelManagementScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.psychology_outlined, color: appColors.agentAccent),
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
              if (kHasBundledBackend)
                ListTile(
                  leading: Icon(Icons.tune, color: appColors.agentAccent),
                  title: const Text('AI 模型选择'),
                  subtitle: Text(_managedModelSubtitle(
                      ref.watch(managedModelProvider))),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const ManagedModelPickerScreen(),
                      ),
                    ).then((_) {
                      if (mounted) {
                        ref.read(managedModelProvider.notifier).refresh();
                      }
                    });
                  },
                ),
              ListTile(
                leading: Icon(Icons.star_outline, color: appColors.agentAccent),
                title: const Text('点 Star 补充 AI 额度'),
                subtitle: Text(_quotaSubtitle(
                    ref.watch(deviceQuotaProvider))),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: _openStarRedeemDialog,
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
                // 7-tap 打开 attestation 诊断面板,供用户遇到安全相关问题时把
                // 诊断文本发给开发者用(不显眼入口)
                onTap: _handleVersionTap,
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
                    if (!mounted) return;
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
                  if (!mounted) return;
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
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _openFeedback,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 打开问题反馈表单页,提交到后端(不再跳 GitHub issues)。
  void _openFeedback() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const FeedbackSubmitScreen(),
      ),
    );
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

/// 设置页分组卡片（书馆美学风格）
///
/// 顶部 section header（图标 + 衬线大字 + 可选副标题），
/// 下方承载一组业务 ListTile，圆角 12，elevation 0。
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.accentColor,
    required this.children,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final Color accentColor;
  final List<Widget> children;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
