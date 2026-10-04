/// 生图模型管理页
///
/// 一页完成生图模型的全部管理：
/// - 「可下载模型包」：内置目录（与 Local Dream App 同款转换包）按设备
///   SoC 过滤展示，点下载即建行并开始（进度/失败/续传都在卡片上）
/// - 「我的模型」：image_models 表全部模型（含目录导入），就绪模型可
///   编辑 / 设为默认 / 启停 / 删除 / **测试生图**（门面同步链路）
/// - AppBar：HF / HF Mirror 源切换、从目录导入模型包
///
/// 架构：watch [imageModelLifecycleProvider]（下载事件自动刷新），CRUD 经
/// [imageModelAdminServiceProvider] 门面（改库 → 刷新的约定只此一份）。
library;

import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/interfaces/repositories/i_image_model_repository.dart';
import '../../core/providers/device_soc_provider.dart';
import '../../core/providers/image_model_download_providers.dart';
import '../../models/image_model.dart';
import '../../services/image_generation/image_generation_providers.dart';
import '../../services/local_dream_embedded/model_pack.dart';
import '../../services/local_dream_embedded/model_pack_downloader.dart';
import '../../services/logger_service.dart';
import '../../utils/format_utils.dart';
import '../../utils/toast_utils.dart';
import '../../widgets/common/common_widgets.dart';
import 'image_model/dialogs/image_gen_test_sheet.dart';
import 'image_model/dialogs/image_model_edit_dialog.dart';

class ImageModelManagementScreen extends ConsumerStatefulWidget {
  const ImageModelManagementScreen({super.key});

  @override
  ConsumerState<ImageModelManagementScreen> createState() =>
      _ImageModelManagementScreenState();
}

class _ImageModelManagementScreenState
    extends ConsumerState<ImageModelManagementScreen> {
  /// 下载源（HuggingFace / HF Mirror；本页内存态，重进恢复默认）。
  /// 默认国内镜像——主要用户群在国内，直连 HuggingFace 常年超时
  /// （hf-mirror.com 为其完整反代，模型包内容一致）。
  String _baseUrl = LocalDreamBaseUrl.defaultUrl;
  bool _startingDownload = false;

  @override
  Widget build(BuildContext context) {
    final modelsAsync = ref.watch(imageModelLifecycleProvider);
    final soc = ref.watch(deviceSocProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('生图模型管理'),
            const SizedBox(width: 8),
            const BetaTag(),
          ],
        ),
        actions: [
          _mirrorMenu(),
          IconButton(
            onPressed: () => _importPack(context),
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: '从目录导入模型包',
          ),
        ],
      ),
      body: modelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (models) {
          // 下载/进行中任务排前面，其余按 sort_order
          final sorted = List<ImageModel>.of(models)
            ..sort((a, b) {
              final aActive = a.status.isActive ? 0 : 1;
              final bActive = b.status.isActive ? 0 : 1;
              if (aActive != bActive) return aActive - bActive;
              return a.sortOrder.compareTo(b.sortOrder);
            });
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              _readinessBanner(),
              _sectionHeader('可下载模型包'),
              _socHint(soc?.npuSuffix),
              const SizedBox(height: 6),
              ...catalogForSoc(soc?.socModel).map(
                (e) => _CatalogEntryCard(
                  entry: e,
                  match: _matchRow(models, e),
                  onDownload: () => _startDownload(e, soc?.npuSuffix),
                  starting: _startingDownload,
                ),
              ),
              const SizedBox(height: 16),
              _sectionHeader('我的模型'),
              if (sorted.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    '还没有模型。从上方目录下载一个，下载完成后即可测试生图，'
                    'Agent 也会根据模型特点自动选型出图。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                ),
              ...sorted.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ModelCard(
                        model: m, existingNames: _nameSet(sorted, m)),
                  )),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  static Set<String> _nameSet(List<ImageModel> all, ImageModel exclude) =>
      {for (final m in all) if (m.id != exclude.id) m.name};

  // ===== 可下载目录 =====

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                )),
      );

  Widget _socHint(String? socSuffix) => Text(
        socSuffix == null
            ? '未检测到骁龙 NPU，仅显示 CPU 兜底模型包。'
            : 'NPU 芯片源：$socSuffix（与 Local Dream 相同的转换包）。',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
      );

  /// 引擎/运行库自检提示条：只在缺东西时出现（都就绪则零噪音）
  Widget _readinessBanner() {
    final readiness = ref.watch(localDreamReadinessProvider).valueOrNull;
    if (readiness == null) return const SizedBox.shrink();
    final hints = <String>[];
    if (!readiness.binary) {
      hints.add('引擎二进制未打包（需按 docs/local_dream_engine.md 放置产物重新构建，'
          '下载模型包仍可提前进行）');
    }
    if (!readiness.qnn) {
      hints.add('QNN 运行库未就绪（NPU 模型包需联网重启应用完成启动引导下载，'
          'CPU 包不受影响）');
    }
    if (hints.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 0,
        color: Theme.of(context)
            .colorScheme
            .errorContainer
            .withValues(alpha: 0.35),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            hints.join('\n'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
          ),
        ),
      ),
    );
  }

  /// 下载源切换菜单（HuggingFace / HF Mirror）
  Widget _mirrorMenu() {
    return PopupMenuButton<String>(
      tooltip: '下载源',
      icon: const Icon(Icons.dns_outlined),
      onSelected: (url) => setState(() => _baseUrl = url),
      itemBuilder: (_) => LocalDreamBaseUrl.choices
          .map((c) => PopupMenuItem(
                value: c.$1,
                child: Row(
                  children: [
                    if (_baseUrl == c.$1)
                      const Icon(Icons.check, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 6),
                    Text(c.$2),
                  ],
                ),
              ))
          .toList(),
    );
  }

  /// 找目录条目对应的行（按 catalog_id 匹配；目录导入的包 catalogId 为空，
  /// 不会与目录条目混淆）
  ({ImageModel? downloading, ImageModel? paused, ImageModel? failed, ImageModel? ready})
      _matchRow(List<ImageModel> rows, LocalDreamPackEntry entry) {
    ImageModel? downloading;
    ImageModel? paused;
    ImageModel? failed;
    ImageModel? ready;
    for (final r in rows) {
      if (r.catalogId != entry.id) continue;
      switch (r.status) {
        case ImageModelStatus.downloading:
          downloading = r;
        case ImageModelStatus.paused:
          paused = r;
        case ImageModelStatus.failed:
          failed = r;
        case ImageModelStatus.ready:
          ready = r;
      }
    }
    return (downloading: downloading, paused: paused, failed: failed, ready: ready);
  }

  Future<void> _startDownload(
      LocalDreamPackEntry entry, String? socSuffix) async {
    if (_startingDownload) return;
    final zipUrl =
        entry.resolveZipUrl(baseUrl: _baseUrl, socSuffix: socSuffix);
    if (zipUrl == null) {
      // 目录里能看到 NPU 包却下不了，说明「探测说无 NPU」与用户认知冲突，
      // 与反馈 #8 同款矛盾点。warning 级随反馈上传，便于核对探测结果。
      LoggerService.instance.w(
        'NPU 模型包下载被拦截：pack=${entry.id}，socSuffix=$socSuffix',
        category: LogCategory.ai,
        tags: const ['image', 'npu', 'download-block'],
      );
      ToastUtils.showError('当前设备无可用 NPU 源', context: context);
      return;
    }
    setState(() => _startingDownload = true);
    final downloader = ref.read(localDreamPackDownloaderProvider);
    try {
      final row = await downloader.createDownloadingRow(
        entry: entry,
        zipUrl: zipUrl,
      );
      if (!mounted) return;
      ToastUtils.showInfo('开始下载「${entry.name}」', context: context);
      unawaited(downloader.startDownload(row));
    } catch (e) {
      if (mounted) ToastUtils.showError('创建下载任务失败：$e', context: context);
    } finally {
      if (mounted) setState(() => _startingDownload = false);
    }
  }

  /// 导入 Local Dream 模型包目录（选类型 → SAF 选目录 → 拷贝校验落库）
  Future<void> _importPack(BuildContext context) async {
    // 1. 选包类型（sd15cpu 与 sd15npu 文件相同，无法从内容推断）
    final type = await showModalBottomSheet<LocalDreamPackType>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('选择模型包类型',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            ...LocalDreamPackType.values.map(
              (t) => ListTile(
                title: Text(t.label),
                subtitle: Text(
                    '必需文件 ${t.requiredFiles.length} 个'
                    '${t == LocalDreamPackType.sdxl ? ' · 需骁龙 8 Gen 3+' : t == LocalDreamPackType.sd15Npu ? ' · 需骁龙 NPU (V68+)' : ' · CPU 兜底'}'),
                onTap: () => Navigator.pop(sheetContext, t),
              ),
            ),
          ],
        ),
      ),
    );
    if (type == null || !context.mounted) return;

    // 2. 选目录
    final sourceDirPath = await FilePicker.getDirectoryPath(
      dialogTitle: '选择 Local Dream 模型包目录（将复制文件）',
    );
    if (sourceDirPath == null || !context.mounted) return;

    // 3. 拷贝必需文件到包目录（建行/拷贝/v3/config 合并/置状态都在服务层）
    final downloader = ref.read(localDreamPackDownloaderProvider);
    try {
      final dirName = sourceDirPath
          .split(Platform.pathSeparator)
          .where((s) => s.isNotEmpty)
          .last;
      final result = await downloader.importPackDirectory(
        type: type,
        sourceDir: sourceDirPath,
        displayName: dirName,
      );
      ref.read(imageModelAdminServiceProvider).refresh();
      if (!context.mounted) return;
      if (result.row.status == ImageModelStatus.ready) {
        ToastUtils.showSuccess('已导入「${result.row.name}」', context: context);
      } else {
        ToastUtils.showError('导入失败：${result.row.errorMessage}', context: context);
      }
    } catch (e) {
      LoggerService.instance.e('导入模型包失败: $e',
          category: LogCategory.ai, tags: ['local_dream_pack', 'import']);
      if (context.mounted) ToastUtils.showError('导入失败：$e', context: context);
    }
  }
}

/// 内置目录条目卡片：下载入口 / 下载进度 / 失败原因 / 已添加标记
class _CatalogEntryCard extends StatelessWidget {
  final LocalDreamPackEntry entry;
  final ({ImageModel? downloading, ImageModel? paused, ImageModel? failed, ImageModel? ready})
      match;
  final VoidCallback onDownload;
  final bool starting;

  const _CatalogEntryCard({
    required this.entry,
    required this.match,
    required this.onDownload,
    required this.starting,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final added = match.ready != null;
    final downloadingRow = match.downloading;
    final pausedRow = match.paused;
    final failRow = match.failed;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${entry.name} · ${entry.description}',
                      style: theme.textTheme.titleSmall),
                ),
                if (added)
                  Icon(Icons.check_circle,
                      size: 18, color: theme.colorScheme.primary)
                else
                  IconButton(
                    tooltip: '下载',
                    icon: const Icon(Icons.download_outlined),
                    onPressed: starting ? null : onDownload,
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${entry.type.label} · 约 ${entry.approximateSize}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (downloadingRow != null) ...[
              const SizedBox(height: 6),
              _LiveDownloadProgress(
                  modelId: downloadingRow.id!,
                  dbPercent: downloadingRow.progress),
            ],
            // failed/paused 不算已添加，此处仍显示下载入口；failed 附失败原因
            if (failRow != null) ...[
              const SizedBox(height: 6),
              Text('上次失败：${failRow.errorMessage}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
            if (pausedRow != null && downloadingRow == null) ...[
              const SizedBox(height: 6),
              Text('已暂停（点下载图标继续，从断点续传）',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      )),
            ],
          ],
        ),
      ),
    );
  }
}

/// 我的模型卡片
class _ModelCard extends ConsumerWidget {
  final ImageModel model;
  final Set<String> existingNames;

  const _ModelCard({required this.model, required this.existingNames});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isReady = model.status.isReady;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          model.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (model.status != ImageModelStatus.ready) ...[
                        const SizedBox(width: 6),
                        _chip(context, _statusLabel(model.status),
                            _statusColor(model.status, colorScheme)),
                      ],
                      if (model.isDefault) ...[
                        const SizedBox(width: 6),
                        _chip(context, '默认', colorScheme.primary),
                      ],
                      if (!model.isEnabled) ...[
                        const SizedBox(width: 6),
                        _chip(context, '已停用', colorScheme.outline),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (action) => _onMenu(context, ref, action),
                  itemBuilder: (_) => _menuItems(),
                ),
              ],
            ),
            // 生命周期区：进度条 / 错误信息 / 状态操作按钮
            if (model.status == ImageModelStatus.downloading) ...[
              const SizedBox(height: 10),
              _LiveDownloadProgress(
                  modelId: model.id!, dbPercent: model.progress),
            ] else if (model.status == ImageModelStatus.paused) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: model.progress / 100.0),
              const SizedBox(height: 4),
              Text('已暂停（${model.progress}%）',
                  style: Theme.of(context).textTheme.bodySmall),
            ] else if (model.status == ImageModelStatus.failed) ...[
              const SizedBox(height: 10),
              Text(
                model.errorMessage.isEmpty ? '下载失败' : model.errorMessage,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.error,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (isReady && model.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                model.description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (isReady && model.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: model.tags
                    .map((t) => _chip(context, t, colorScheme.tertiary))
                    .toList(),
              ),
            ],
            const SizedBox(height: 8),
            if (isReady) ...[
              Text(
                'Local Dream 本机引擎 · ${_packTypeLabel(model)} · '
                '${_packFileCount(model)} 个文件',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
              ),
              const SizedBox(height: 10),
              // 测试生图：直出（下载完成后即可验证引擎链路）
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: model.isEnabled
                      ? () => ImageGenTestSheet.show(context, model)
                      : null,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('测试生图'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLabel(ImageModelStatus s) {
    switch (s) {
      case ImageModelStatus.downloading:
        return '下载中';
      case ImageModelStatus.paused:
        return '已暂停';
      case ImageModelStatus.failed:
        return '失败';
      case ImageModelStatus.ready:
        return '';
    }
  }

  Color _statusColor(ImageModelStatus s, ColorScheme scheme) {
    switch (s) {
      case ImageModelStatus.downloading:
        return scheme.tertiary;
      case ImageModelStatus.paused:
        return scheme.outline;
      case ImageModelStatus.failed:
        return scheme.error;
      case ImageModelStatus.ready:
        return scheme.primary;
    }
  }

  List<PopupMenuItem<String>> _menuItems() {
    switch (model.status) {
      case ImageModelStatus.downloading:
        return const [
          PopupMenuItem(value: 'pause', child: Text('暂停')),
          PopupMenuItem(value: 'delete', child: Text('取消并删除')),
        ];
      case ImageModelStatus.paused:
        return const [
          PopupMenuItem(value: 'resume', child: Text('继续下载')),
          PopupMenuItem(value: 'delete', child: Text('取消并删除')),
        ];
      case ImageModelStatus.failed:
        // 目录导入的包（无下载源）重试只会再次失败，应重新导入而非重试
        final importedPack = model.sourceUrl.isEmpty;
        return [
          if (!importedPack)
            const PopupMenuItem(value: 'retry', child: Text('重试')),
          const PopupMenuItem(value: 'delete', child: Text('删除')),
        ];
      case ImageModelStatus.ready:
        return [
          const PopupMenuItem(value: 'test', child: Text('测试生图')),
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
          if (!model.isDefault)
            const PopupMenuItem(value: 'default', child: Text('设为默认')),
          PopupMenuItem(
            value: 'toggle',
            child: Text(model.isEnabled ? '停用' : '启用'),
          ),
          const PopupMenuItem(value: 'delete', child: Text('删除')),
        ];
    }
  }

  static String _packTypeLabel(ImageModel model) {
    final type = LocalDreamPackType.parse(model.remoteModelId);
    return type?.label ?? (model.remoteModelId.isEmpty ? '未知类型' : model.remoteModelId);
  }

  static int _packFileCount(ImageModel model) =>
      LocalDreamPackType.parse(model.remoteModelId)?.requiredFiles.length ?? 0;

  Widget _chip(BuildContext context, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: color.withValues(alpha: 0.12),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      );

  Future<void> _onMenu(
      BuildContext context, WidgetRef ref, String action) async {
    final admin = ref.read(imageModelAdminServiceProvider);
    switch (action) {
      // ===== 生命周期动作 =====
      case 'pause':
        admin.pause(model.id!);
        break;
      case 'resume':
      case 'retry':
        await admin.resume(model);
        break;
      case 'delete':
        if (!context.mounted) return;
        final confirmed = await ConfirmDialog.show(
          context,
          title: '确认删除',
          message: model.status.isReady
              ? '将删除模型「${model.name}」及其模型文件，此操作不可恢复。'
              : '将取消「${model.name}」的下载并删除相关文件。',
          confirmText: '删除',
          isDangerous: true,
        );
        if (confirmed != true) return;
        await admin.delete(model);
        if (context.mounted) {
          ToastUtils.showSuccess('已删除「${model.name}」', context: context);
        }
        break;
      // ===== ready 模型的常规动作 =====
      case 'test':
        if (!context.mounted) return;
        await ImageGenTestSheet.show(context, model);
        break;
      case 'edit':
        if (!context.mounted) return;
        final updated = await showDialog<ImageModel>(
          context: context,
          builder: (_) => ImageModelEditDialog(
            model: model,
            existingNames: existingNames,
          ),
        );
        if (updated == null) return;
        try {
          await admin.save(updated);
          if (context.mounted) {
            ToastUtils.showSuccess('已保存「${updated.name}」', context: context);
          }
        } on ImageModelNameConflictException {
          if (context.mounted) {
            ToastUtils.showError('模型名称「${updated.name}」已存在', context: context);
          }
        }
        break;
      case 'default':
        await admin.setDefault(model.id!);
        break;
      case 'toggle':
        await admin.save(model.copyWith(isEnabled: !model.isEnabled));
        break;
    }
  }
}

/// 下载进度行（细粒度实时）：百分比 + 已下/总量 + 速度 + 剩余时间
///
/// 库里的 progress 是 1% 粒度的整数（4GB 包的 1% = 40MB，慢速下载时
/// 几十秒不动，看着像卡死）。这里订阅下载器的 ≈2Hz 内存采样流，展示真实
/// 字节与速度——用户在动还是真卡住一眼可见。流还没产出时回退 DB 百分比。
class _LiveDownloadProgress extends ConsumerStatefulWidget {
  final int modelId;

  /// 冷启动/流未就绪时的回退百分比
  final int dbPercent;

  const _LiveDownloadProgress({
    required this.modelId,
    required this.dbPercent,
  });

  @override
  ConsumerState<_LiveDownloadProgress> createState() =>
      _LiveDownloadProgressState();
}

class _LiveDownloadProgressState
    extends ConsumerState<_LiveDownloadProgress> {
  StreamSubscription<PackDownloadSample>? _sub;
  PackDownloadSample? _sample;

  @override
  void initState() {
    super.initState();
    _sub = ref
        .read(localDreamPackDownloaderProvider)
        .progressSamples
        .listen((s) {
      if (s.modelId != widget.modelId || !mounted) return;
      setState(() => _sample = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  static String _eta(double seconds) {
    if (seconds < 60) return '${seconds.ceil()} 秒';
    if (seconds < 3600) {
      final m = seconds ~/ 60;
      final s = (seconds % 60).round();
      return '$m 分 $s 秒';
    }
    return '约 ${(seconds / 3600).ceil()} 小时';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _sample;
    final percent = s?.percent ?? widget.dbPercent;
    final ratio = s?.totalBytes != null && s!.totalBytes! > 0
        ? (s.receivedBytes / s.totalBytes!).clamp(0.0, 1.0)
        : widget.dbPercent / 100.0;

    final parts = <String>['下载中 $percent%'];
    if (s != null) {
      parts.add(s.totalBytes != null
          ? '${FormatUtils.formatFileSize(s.receivedBytes)} / '
              '${FormatUtils.formatFileSize(s.totalBytes!)}'
          : FormatUtils.formatFileSize(s.receivedBytes));
      if (s.bytesPerSecond > 0) {
        parts.add('${FormatUtils.formatFileSize(s.bytesPerSecond.round())}/s');
        final eta = s.etaSeconds;
        if (eta != null) parts.add('剩余 ${_eta(eta)}');
      } else {
        parts.add('等待数据…');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: ratio),
        const SizedBox(height: 4),
        Text(
          parts.join(' · '),
          style: theme.textTheme.bodySmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
