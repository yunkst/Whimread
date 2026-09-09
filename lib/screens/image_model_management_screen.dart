/// 生图模型管理页
///
/// 职责：
/// - 列出 image_models 表全部模型（名字 / 后端类型 / 标签 / 大小 / 状态）
/// - 导入 .gguf 模型文件 → 编辑对话框填名字与特点 → 落库
/// - 编辑 / 删除 / 启停 / 设为默认
///
/// 架构：本 Screen 直接 watch [imageModelListProvider]，CRUD 后
/// ref.invalidate 刷新（与 characterListProvider 同款刷新约定）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/interfaces/repositories/i_image_model_repository.dart';
import '../../core/providers/image_model_providers.dart';
import '../../models/image_model.dart';
import '../../services/image_model_import_service.dart';
import '../../services/logger_service.dart';
import '../../utils/format_utils.dart';
import '../../utils/toast_utils.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/empty_states/empty_state_view.dart';
import 'image_model/dialogs/image_model_edit_dialog.dart';

class ImageModelManagementScreen extends ConsumerWidget {
  const ImageModelManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelsAsync = ref.watch(imageModelListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('生图模型管理'),
        actions: [
          IconButton(
            onPressed: () => _addModel(context, ref),
            icon: const Icon(Icons.add),
            tooltip: '导入模型',
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
              subtitle: '导入 .gguf 格式的本地 SD 模型，\n'
                  'Agent 会根据模型特点自动选型出图。',
              actionText: '导入第一个模型',
              onAction: () => _addModel(context, ref),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: models.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) =>
                _ModelCard(model: models[i], existingNames: _nameSet(models, models[i])),
          );
        },
      ),
    );
  }

  static Set<String> _nameSet(List<ImageModel> all, ImageModel exclude) =>
      {for (final m in all) if (m.id != exclude.id) m.name};

  Future<void> _addModel(BuildContext context, WidgetRef ref) async {
    // 导入流程：选文件 → 复制 → 编辑对话框填元数据
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

    try {
      final sortOrder = await repo.getNextSortOrder();
      await repo.save(model.copyWith(sortOrder: sortOrder));
      ref.invalidate(imageModelListProvider);
      if (context.mounted) ToastUtils.showSuccess('已添加模型「${model.name}」', context: context);
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

  static String _stripGguf(String fileName) {
    final base = fileName.endsWith('.gguf') || fileName.endsWith('.GGUF')
        ? fileName.substring(0, fileName.length - 5)
        : fileName;
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
                      if (model.isDefault) ...[
                        const SizedBox(width: 6),
                        _chip(context, '默认', colorScheme.primary),
                      ],
                      const SizedBox(width: 6),
                      _chip(context, model.backendType.displayName,
                          colorScheme.secondary),
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
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('编辑')),
                    if (!model.isDefault)
                      const PopupMenuItem(value: 'default', child: Text('设为默认')),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(model.isEnabled ? '停用' : '启用'),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
            if (model.description.isNotEmpty) ...[
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
            if (model.tags.isNotEmpty) ...[
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
            Text(
              '${FormatUtils.formatFileSize(model.fileSize)} · ${_fileName(model.filePath)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fileName(String path) {
    if (path.isEmpty) return '';
    final idx = path.replaceAll('\\', '/').lastIndexOf('/');
    return idx >= 0 ? path.substring(idx + 1) : path;
  }

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
    switch (action) {
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
          await repo.save(updated);
          ref.invalidate(imageModelListProvider);
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
        ref.invalidate(imageModelListProvider);
        break;
      case 'toggle':
        await repo.save(model.copyWith(isEnabled: !model.isEnabled));
        ref.invalidate(imageModelListProvider);
        break;
      case 'delete':
if (!context.mounted) return;
        final confirmed = await ConfirmDialog.show(
          context,
          title: '确认删除',
          message: '将删除模型「${model.name}」及其模型文件，'
              '此操作不可恢复。',
          confirmText: '删除',
          isDangerous: true,
        );
        if (confirmed != true) return;
        // 先删文件再删记录
        await ImageModelImportService.instance.deleteModelFile(model.filePath);
        await repo.delete(model.id!);
        ref.invalidate(imageModelListProvider);
        if (context.mounted) {
          ToastUtils.showSuccess('已删除「${model.name}」', context: context);
        }
        break;
    }
  }
}