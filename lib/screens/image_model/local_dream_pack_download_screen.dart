/// Local Dream 模型包下载页
///
/// 模型目录**与 Local Dream App 完全一致**（逐条移植自
/// ModelRepository.kt v2.8.1）：
/// - SDXL NPU（仅 8 Gen 3+ SoC 可见）：Illustrious v16 / DMD2、
///   CyberRealistic v10 / DMD2
/// - SD1.5 NPU（zip 按芯片后缀区分）：Anything V5、QteaMix、CuteYukiMix、
///   Absolute Reality、ChilloutMix
/// - SD1.5 CPU（MNN 兜底，任意设备）
///
/// 支持 HuggingFace / HF Mirror 源切换。选中即创建 image_models 行并
/// 开始 zip 下载，进度在本页和「生图模型管理」页实时可见。
library;

import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/image_model_download_providers.dart';
import '../../models/image_model.dart';
import '../../services/local_dream_embedded/model_pack.dart';
import '../../utils/toast_utils.dart';

class LocalDreamPackDownloadScreen extends ConsumerStatefulWidget {
  const LocalDreamPackDownloadScreen({super.key});

  @override
  ConsumerState<LocalDreamPackDownloadScreen> createState() =>
      _LocalDreamPackDownloadScreenState();
}

class _LocalDreamPackDownloadScreenState
    extends ConsumerState<LocalDreamPackDownloadScreen> {
  String _baseUrl = LocalDreamBaseUrl.huggingface;

  /// 原始 socModel（catalogForSoc 入参，单一来源的 SoC 可用性过滤）
  String? _soc;
  String? _socSuffix;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _detectSoc();
  }

  Future<void> _detectSoc() async {
    String? soc;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      // SOC_MODEL 仅 API 31+；低版本拿不到 → 视为无 NPU（Local Dream 同款）
      final raw = info.data['socModel'] as String? ?? '';
      soc = raw.isEmpty ? null : raw;
    } catch (_) {
      soc = null;
    }
    if (!mounted) return;
    setState(() {
      _soc = soc;
      _socSuffix = soc == null ? null : chipsetSuffixForSoc(soc);
    });
  }

  /// 已在库里且就绪的条目（按 name+类型匹配）。failed/paused 不算
  /// "已添加"：卡片要显示失败/暂停状态并提供（重新）下载入口。
  bool _alreadyAdded(List<ImageModel> rows, LocalDreamPackEntry entry) {
    final name = '${entry.name}（${entry.type.label}）';
    return rows.any((r) => r.name == name && r.status.isReady);
  }

  Future<void> _startDownload(LocalDreamPackEntry entry) async {
    if (_starting) return;
    final zipUrl =
        entry.resolveZipUrl(baseUrl: _baseUrl, socSuffix: _socSuffix);
    if (zipUrl == null) {
      ToastUtils.showError('当前设备无可用 NPU 源', context: context);
      return;
    }
    setState(() => _starting = true);
    final downloader = ref.read(localDreamPackDownloaderProvider);
    try {
      final row = await downloader.createDownloadingRow(
        entry: entry,
        zipUrl: zipUrl,
      );
      if (!mounted) return;
      ToastUtils.showInfo('开始下载「${entry.name}」，进度见下方与模型管理页',
          context: context);
      // 后台下载，本页停留可继续加别的包
      unawaited(downloader.startDownload(row));
    } catch (e) {
      if (mounted) ToastUtils.showError('创建下载任务失败：$e', context: context);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref
            .watch(imageModelLifecycleProvider)
            .valueOrNull ??
        const <ImageModel>[];
    // SoC 可用性过滤复用 catalogForSoc（与 model_pack.dart 单一来源）：
    // 不适用的设备直接不展示对应 NPU 包，而不是点了下载才报"无可用 NPU 源"
    final entries = catalogForSoc(_soc);

    final sdxlEntries =
        entries.where((e) => e.type == LocalDreamPackType.sdxl).toList();
    final npuEntries =
        entries.where((e) => e.type == LocalDreamPackType.sd15Npu).toList();
    final cpuEntries =
        entries.where((e) => e.type == LocalDreamPackType.sd15Cpu).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载 Local Dream 模型包'),
        actions: [
          _mirrorMenu(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _socSuffix == null
                ? '未检测到骁龙 NPU，仅显示 CPU 兜底模型包。'
                : 'NPU 芯片源：$_socSuffix（与 Local Dream 相同的转换包）。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
          ),
          const SizedBox(height: 12),
          if (sdxlEntries.isNotEmpty) ...[
            _sectionHeader('SDXL · NPU（骁龙 8 Gen 3+）'),
            ...sdxlEntries.map((e) => _entryCard(e, rows)),
            const SizedBox(height: 12),
          ],
          _sectionHeader('SD1.5 · NPU（骁龙）'),
          if (npuEntries.isEmpty)
            const Text('当前设备不支持 NPU 推理。')
          else
            ...npuEntries.map((e) => _entryCard(e, rows)),
          const SizedBox(height: 12),
          _sectionHeader('SD1.5 · CPU（兜底，任意设备）'),
          ...cpuEntries.map((e) => _entryCard(e, rows)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

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

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                )),
      );

  Widget _entryCard(LocalDreamPackEntry entry, List<ImageModel> rows) {
    final added = _alreadyAdded(rows, entry);
    final name = '${entry.name}（${entry.type.label}）';
    ImageModel? downloadingRow;
    ImageModel? pausedRow;
    ImageModel? failRow;
    for (final r in rows) {
      if (r.name != name) continue;
      if (r.status == ImageModelStatus.downloading) downloadingRow = r;
      if (r.status == ImageModelStatus.paused) pausedRow = r;
      if (r.status == ImageModelStatus.failed) failRow = r;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                if (added)
                  Icon(Icons.check_circle,
                      size: 18, color: Theme.of(context).colorScheme.primary)
                else
                  IconButton(
                    tooltip: '下载',
                    icon: const Icon(Icons.download_outlined),
                    onPressed: _starting ? null : () => _startDownload(entry),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${entry.type.label} · 约 ${entry.approximateSize}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
            ),
            if (downloadingRow != null) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(value: downloadingRow.progress / 100.0),
              const SizedBox(height: 2),
              Text('下载中 ${downloadingRow.progress}%',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            // failed/paused 不算已添加（_alreadyAdded 只认 ready），
            // 此处必然仍显示下载入口；failed 附带失败原因
            if (failRow != null) ...[
              const SizedBox(height: 6),
              Text('上次失败：${failRow.errorMessage}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
            if (pausedRow != null && downloadingRow == null) ...[
              const SizedBox(height: 6),
              Text('已暂停（可在模型管理页续传），也可重新下载',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      )),
            ],
          ],
        ),
      ),
    );
  }
}
