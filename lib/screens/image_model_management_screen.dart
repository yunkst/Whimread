/// 生图模型管理页
///
/// 职责：
/// - 列出 image_models 表全部模型（名字 / 后端类型 / 标签 / 大小 / 状态）
/// - 导入 .gguf 模型文件 → 编辑对话框填名字与特点 → 落库
/// - 编辑 / 删除 / 启停 / 设为默认
///
/// 架构：本 Screen watch [imageModelLifecycleProvider]（含下载事件自动刷新），CRUD 后
/// ref.invalidate 刷新（与 characterListProvider 同款刷新约定）。
library;

import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/interfaces/repositories/i_image_model_repository.dart';
import '../../core/providers/image_model_download_providers.dart';
import '../../core/providers/image_model_providers.dart';
import '../../models/image_model.dart';
import '../../services/image_model_import_service.dart';
import '../../services/local_dream_embedded/model_pack.dart';
import '../../services/logger_service.dart';
import '../../utils/format_utils.dart';
import '../../utils/toast_utils.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/empty_states/empty_state_view.dart';
import 'image_model/dialogs/image_model_edit_dialog.dart';
import 'image_model/dialogs/local_dream_model_dialog.dart';
import 'image_model/local_dream_pack_download_screen.dart';

class ImageModelManagementScreen extends ConsumerWidget {
  const ImageModelManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 生命周期视图：下载/转换事件自动刷新（进度条实时走动）
    final modelsAsync = ref.watch(imageModelLifecycleProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('生图模型管理'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Beta',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _showPackMenu(context, ref),
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Local Dream 模型包（下载/导入）',
          ),
          IconButton(
            onPressed: () => _addRemoteModel(context, ref),
            icon: const Icon(Icons.phonelink_setup_outlined),
            tooltip: '添加 Local Dream 设备模型',
          ),
          IconButton(
            onPressed: () => _addModel(context, ref),
            icon: const Icon(Icons.add),
            tooltip: '导入本地模型文件',
          ),
        ],
      ),
      body: modelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (models) {
          if (models.isEmpty) {
            return EmptyStateView(
              icon: Icons.image_outlined,
              title: '还没有生图模型',
              subtitle: '导入 .gguf / .safetensors 模型文件，\n'
                  '或在内置浏览器下载模型自动导入；\n'
                  'Agent 会根据模型特点自动选型出图。',
              actionText: '导入第一个模型',
              onAction: () => _addModel(context, ref),
            );
          }
          // 下载/转换中的排前面（用户正在等的任务），其余按 sort_order
          final sorted = List<ImageModel>.of(models)
            ..sort((a, b) {
              final aActive = a.status.isActive ? 0 : 1;
              final bActive = b.status.isActive ? 0 : 1;
              if (aActive != bActive) return aActive - bActive;
              return a.sortOrder.compareTo(b.sortOrder);
            });
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _ModelCard(
                model: sorted[i],
                existingNames: _nameSet(sorted, sorted[i])),
          );
        },
      ),
    );
  }

  static Set<String> _nameSet(List<ImageModel> all, ImageModel exclude) =>
      {for (final m in all) if (m.id != exclude.id) m.name};

  /// Local Dream 模型包入口：下载（内置目录/manifest）或从目录导入
  Future<void> _showPackMenu(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: const Text('下载模型包'),
              subtitle: const Text('从内置目录或自定义 manifest 下载'),
              onTap: () => Navigator.pop(sheetContext, 'download'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('从目录导入模型包'),
              subtitle: const Text('已在本机有 Local Dream 模型文件时使用'),
              onTap: () => Navigator.pop(sheetContext, 'import'),
            ),
          ],
        ),
      ),
    );
    if (action == 'download' && context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const LocalDreamPackDownloadScreen(),
        ),
      );
    } else if (action == 'import' && context.mounted) {
      await _importPack(context, ref);
    }
  }

  /// 导入 Local Dream 模型包目录（选类型 → SAF 选目录 → 拷贝校验落库）
  Future<void> _importPack(BuildContext context, WidgetRef ref) async {
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
      ref.invalidate(imageModelLifecycleProvider);
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

  /// 添加 Local Dream 设备模型：填设备地址 → 拉取设备模型列表选择 → 落库
  Future<void> _addRemoteModel(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(imageModelRepositoryProvider);
    final models = await repo.getAll();
    if (!context.mounted) return;

    final model = await showDialog<ImageModel>(
      context: context,
      builder: (_) => LocalDreamModelDialog(
        existingNames: {for (final m in models) m.name},
      ),
    );
    if (model == null) return; // 用户取消

    final sortOrder = await repo.getNextSortOrder();
    await _saveNewModel(context, ref, model.copyWith(sortOrder: sortOrder));
  }

  /// 落库 + 刷新 + 提示（本地导入与设备添加共用）
  Future<void> _saveNewModel(
      BuildContext context, WidgetRef ref, ImageModel model) async {
    final repo = ref.read(imageModelRepositoryProvider);
    try {
      await repo.save(model);
      ref.invalidate(imageModelLifecycleProvider);
      if (context.mounted) {
        ToastUtils.showSuccess('已添加模型「${model.name}」', context: context);
      }
    } on ImageModelNameConflictException {
      if (context.mounted) {
        ToastUtils.showError('模型名称「${model.name}」已存在', context: context);
      }
    } catch (e) {
      LoggerService.instance.e('保存生图模型失败: $e',
          category: LogCategory.database, tags: ['image_model', 'save']);
      if (context.mounted) ToastUtils.showError('保存失败：$e', context: context);
    }
  }

  Future<void> _addModel(BuildContext context, WidgetRef ref) async {
    // 导入流程：选文件 → 复制 →
    //   .gguf       → 编辑对话框填元数据 → ready 落库
    //   .safetensors → 建 converting 行 → 端上转换 → ready
    ImageModelImportResult? imported;
    try {
      imported = await ImageModelImportService.instance.pickAndImport();
    } on ImageModelImportException catch (e) {
      if (context.mounted) ToastUtils.showError(e.message, context: context);
      return;
    } catch (e) {
      LoggerService.instance.e('导入模型文件失败: $e',
          category: LogCategory.ai, tags: ['image_model', 'import']);
      if (context.mounted) {
        ToastUtils.showError('导入失败：$e', context: context);
      }
      return;
    }
    if (imported == null) return; // 用户取消
    if (!context.mounted) return;

    final repo = ref.read(imageModelRepositoryProvider);

    // ===== safetensors：不弹编辑框（转换完成后再编辑），直接入队转换 =====
    if (imported.needsConversion) {
      final now = DateTime.now();
      final row = ImageModel(
        name: _stripGguf(imported.originalFileName),
        status: ImageModelStatus.converting,
        filePath: imported.filePath,
        fileSize: imported.fileSize,
        createdAt: now,
        updatedAt: now,
      );
      try {
        final id = await repo.save(row.copyWith(sortOrder: await repo.getNextSortOrder()));
        final saved = await repo.getById(id);
        if (saved != null) {
          await ref
              .read(imageModelDownloadServiceProvider)
              .startConversionForImportedFile(saved, imported.filePath);
        }
        ref.invalidate(imageModelLifecycleProvider);
        if (context.mounted) {
          ToastUtils.showInfo(
              '已导入「${row.name}」，正在转换（Q8_0 量化，需数分钟）',
              context: context);
        }
      } catch (e) {
        LoggerService.instance.e('safetensors 导入失败: $e',
            category: LogCategory.ai, tags: ['image_model', 'import']);
        if (context.mounted) ToastUtils.showError('导入失败：$e', context: context);
      }
      return;
    }

    // ===== gguf：原有编辑对话框流程 =====
    final models = await repo.getAll();
    if (!context.mounted) return;

    final model = await showDialog<ImageModel>(
      context: context,
      builder: (_) => ImageModelEditDialog(
        presetFilePath: imported!.filePath,
        presetFileSize: imported.fileSize,
        presetName: _stripGguf(imported.originalFileName),
        existingNames: {for (final m in models) m.name},
      ),
    );
    if (model == null) {
      // 用户放弃编辑 → 删掉已复制的文件，避免垃圾堆积
      await ImageModelImportService.instance.deleteModelFile(imported.filePath);
      return;
    }

    final sortOrder = await repo.getNextSortOrder();
    await _saveNewModel(context, ref, model.copyWith(sortOrder: sortOrder));
  }

  static String _stripGguf(String fileName) {
    final base = fileName.replaceAll(
        RegExp(r'\.(safetensors|gguf)$', caseSensitive: false), '');
    return base.isEmpty ? '未命名模型' : base;
  }
}

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
                  onSelected: (action) =>
                      _onMenu(context, ref, action),
                  itemBuilder: (_) => _menuItems(),
                ),
              ],
            ),
            // 生命周期区：进度条 / 错误信息 / 状态操作按钮
            if (model.status == ImageModelStatus.downloading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: model.progress / 100.0),
              const SizedBox(height: 4),
              Text('下载中 ${model.progress}%',
                  style: Theme.of(context).textTheme.bodySmall),
            ] else if (model.status == ImageModelStatus.paused) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: model.progress / 100.0),
              const SizedBox(height: 4),
              Text('已暂停（${model.progress}%）',
                  style: Theme.of(context).textTheme.bodySmall),
            ] else if (model.status == ImageModelStatus.converting) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text('转换中（Q8_0 量化，数分钟）',
                  style: Theme.of(context).textTheme.bodySmall),
            ] else if (model.status == ImageModelStatus.failed) ...[
              const SizedBox(height: 10),
              Text(
                model.errorMessage.isEmpty ? '下载/转换失败' : model.errorMessage,
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
            if (isReady)
              Text(
                switch (model.backendType) {
                  ImageModelBackendType.localDreamEmbedded =>
                    'Local Dream 本机引擎 · ${_packTypeLabel(model)} · '
                        '${_packFileCount(model)} 个文件',
                  ImageModelBackendType.localDream =>
                    'Local Dream 设备 · ${model.remoteHost} · ${model.remoteModelId}',
                  _ =>
                    '${FormatUtils.formatFileSize(model.fileSize)} · ${_fileName(model.filePath)}',
                },
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
              )
            else if (model.sourcePageUrl.isNotEmpty)
              Text(
                '来源：${Uri.tryParse(model.sourcePageUrl)?.host ?? model.sourcePageUrl}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
      case ImageModelStatus.converting:
        return '转换中';
      case ImageModelStatus.failed:
        return '失败';
      case ImageModelStatus.ready:
        return '';
    }
  }

  Color _statusColor(ImageModelStatus s, ColorScheme scheme) {
    switch (s) {
      case ImageModelStatus.downloading:
      case ImageModelStatus.converting:
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
      case ImageModelStatus.converting:
        return const [
          PopupMenuItem(value: 'delete', child: Text('删除')),
        ];
      case ImageModelStatus.failed:
        // 目录导入的包（无下载源）重试只会再次失败，应重新导入而非重试
        final importedPack =
            model.backendType == ImageModelBackendType.localDreamEmbedded &&
                model.sourceUrl.isEmpty;
        return [
          if (!importedPack)
            const PopupMenuItem(value: 'retry', child: Text('重试')),
          const PopupMenuItem(value: 'delete', child: Text('删除')),
        ];
      case ImageModelStatus.ready:
        return [
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

  static String _fileName(String path) {
    if (path.isEmpty) return '';
    final idx = path.replaceAll('\\', '/').lastIndexOf('/');
    return idx >= 0 ? path.substring(idx + 1) : path;
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
    final repo = ref.read(imageModelRepositoryProvider);
    final downloadService = ref.read(imageModelDownloadServiceProvider);
    final packDownloader = ref.read(localDreamPackDownloaderProvider);
    final isEmbedded =
        model.backendType == ImageModelBackendType.localDreamEmbedded;
    switch (action) {
      // ===== 生命周期动作 =====
      case 'pause':
        if (isEmbedded) {
          packDownloader.pause(model.id!);
        } else {
          await downloadService.pause(model.id!);
        }
        ref.invalidate(imageModelLifecycleProvider);
        break;
      case 'resume':
        if (isEmbedded) {
          await packDownloader.startDownload(model);
        } else {
          await downloadService.resume(model);
        }
        ref.invalidate(imageModelLifecycleProvider);
        break;
      case 'retry':
        // failed 行按来源分流：模型包 → 重跑包下载；有源文件的转换失败 →
        // 重试转换；否则重试单文件下载
        if (isEmbedded) {
          await packDownloader.startDownload(model);
        } else if (model.sourceUrl.isNotEmpty) {
          await downloadService.resume(model);
        } else {
          await downloadService.retryConversion(model);
        }
        ref.invalidate(imageModelLifecycleProvider);
        break;
      case 'delete':
        if (!context.mounted) return;
        final confirmed = await ConfirmDialog.show(
          context,
          title: '确认删除',
          message: model.status.isReady
              ? '将删除模型「${model.name}」及其模型文件，此操作不可恢复。'
              : '将取消「${model.name}」的下载/转换并删除相关文件。',
          confirmText: '删除',
          isDangerous: true,
        );
        if (confirmed != true) return;
        if (isEmbedded) {
          // 包下载器统一清理：取消任务 + 删包目录 + 删行
          await packDownloader.cancelAndDelete(model);
        } else {
          // 清理下载/转换临时文件 + 最终模型文件，再删记录
          await downloadService.cleanupFiles(model.id!);
          await ImageModelImportService.instance.deleteModelFile(model.filePath);
          await repo.delete(model.id!);
        }
        ref.invalidate(imageModelLifecycleProvider);
        if (context.mounted) {
          ToastUtils.showSuccess('已删除「${model.name}」', context: context);
        }
        break;
      // ===== ready 模型的常规动作 =====
      case 'edit':
        if (!context.mounted) return;
        // 远程设备模型走设备对话框（无本地文件字段）
        final isRemote =
            model.backendType == ImageModelBackendType.localDream;
        final updated = await showDialog<ImageModel>(
          context: context,
          builder: (_) => isRemote
              ? LocalDreamModelDialog(
                  model: model,
                  existingNames: existingNames,
                )
              : ImageModelEditDialog(
                  model: model,
                  existingNames: existingNames,
                ),
        );
        if (updated == null) return;
        try {
          await repo.save(updated);
          ref.invalidate(imageModelLifecycleProvider);
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
        await repo.setDefault(model.id!);
        ref.invalidate(imageModelLifecycleProvider);
        break;
      case 'toggle':
        await repo.save(model.copyWith(isEnabled: !model.isEnabled));
        ref.invalidate(imageModelLifecycleProvider);
        break;
    }
  }
}