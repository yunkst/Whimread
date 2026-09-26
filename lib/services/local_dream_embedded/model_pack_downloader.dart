/// Local Dream 模型包下载器
///
/// 模型包是 Local Dream 预转换的 ZIP（托管在 HuggingFace，目录清单见
/// `model_pack.dart` 的内置 catalog）。流程对齐 Local Dream
/// ModelDownloadService：zip 下载（.part + Range 续传）→ 流式解压到包
/// 目录 → NPU 类型打 `v3` 标记 → 读包内 config.json 合并默认提示词/参数
/// → 校验必需文件 → 置 ready。
///
/// 状态机复用 image_models 行（downloading → paused/failed/ready +
/// progress 列），管理页卡片零改动渲染进度。
///
/// 与 [ImageModelDownloadService]（单文件 gguf/safetensors）并存的
/// 独立服务：包下载逻辑差异大（zip 解压、无转换阶段）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory;

import '../../core/providers/image_model_providers.dart'
    show imageModelRepositoryProvider;
import '../../models/image_model.dart';
import '../../services/logger_service.dart';
import 'model_pack.dart';

class LocalDreamModelPackDownloader {
  final Ref _ref;
  final Dio _dio;

  /// 每个进行中的包一个 CancelToken（key = image_models.id）
  final Map<int, CancelToken> _cancelTokens = {};

  /// 事件流：管理页 lifecycle provider 监听刷新（对齐
  /// ImageModelDownloadService.onChanged 约定）
  final _onChanged = StreamController<void>.broadcast();
  Stream<void> get onChanged => _onChanged.stream;

  LocalDreamModelPackDownloader({required Ref ref, Dio? dio})
      : _ref = ref,
        _dio = dio ?? Dio();

  void dispose() {
    _onChanged.close();
  }

  /// 模型包根目录（<应用文档目录>/local_dream_models/）
  static Future<String> modelsRootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'local_dream_models'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// 为一个目录条目创建占位 image_models 行（status=downloading）。
  /// [zipUrl] 为解析后的完整下载地址（含芯片后缀 / 镜像源）。
  Future<ImageModel> createDownloadingRow({
    required LocalDreamPackEntry entry,
    required String zipUrl,
  }) async {
    final root = await modelsRootDir();
    // 包目录用 Local Dream 的模型 id（重名冲突时加时间戳后缀）
    final now = DateTime.now();
    var packId = entry.id;
    if (Directory(p.join(root, packId)).existsSync()) {
      packId = '${entry.id}_${now.millisecondsSinceEpoch}';
    }
    final packDir = p.join(root, packId);
    Directory(packDir).createSync(recursive: true);
    final repo = _ref.read(imageModelRepositoryProvider);
    final row = ImageModel(
      // NPU/CPU 变体同名（Local Dream 同款），加类型后缀保证本表 name 唯一
      name: '${entry.name}（${entry.type.label}）',
      description: '${entry.description} · 约 ${entry.approximateSize}',
      backendType: ImageModelBackendType.localDreamEmbedded,
      filePath: packDir,
      remoteModelId: entry.type.dbName,
      negativePrompt: entry.defaultNegativePrompt,
      isEnabled: true,
      status: ImageModelStatus.downloading,
      sourceUrl: zipUrl,
      createdAt: now,
      updatedAt: now,
    );
    final id = await repo.save(row);
    _onChanged.add(null);
    return (await repo.getById(id))!;
  }

  /// 开始/续传一个模型包的下载（zip → 解压 → 校验 → ready）。
  /// 幂等：该 id 已有进行中的下载时直接忽略（管理页连点 retry/resume
  /// 不会产生两个写同一 .part 的循环）。
  Future<void> startDownload(ImageModel model) async {
    if (_cancelTokens.containsKey(model.id)) {
      LoggerService.instance.w('模型包已在下载中，忽略重复启动: ${model.name}',
          category: LogCategory.ai,
          tags: ['local_dream_pack', 'download', 'duplicate']);
      return;
    }
    final repo = _ref.read(imageModelRepositoryProvider);
    final type = LocalDreamPackType.parse(model.remoteModelId);
    if (type == null) {
      await _fail(model.id!, '未知的模型包类型: ${model.remoteModelId}');
      return;
    }
    if (model.sourceUrl.isEmpty) {
      await _fail(model.id!, '没有可用的下载地址');
      return;
    }

    // 先注册 CancelToken 再进入首个 await：占位必须发生在任何挂起点之前，
    // 否则连点两次会在 updateStatus 处双双通过上面的守卫
    final cancelToken = CancelToken();
    _cancelTokens[model.id!] = cancelToken;

    try {
      await repo.updateStatus(model.id!, ImageModelStatus.downloading);
      final zipPath = await _downloadZip(
        model: model,
        cancelToken: cancelToken,
      );
      if (cancelToken.isCancelled) return;

      // 流式解压到包目录
      await _extractZip(zipPath, model.filePath);

      // NPU 包打 v3 标记（Local Dream 的版本约定）
      if (type.needsQnnLibs) {
        File(p.join(model.filePath, 'v3')).writeAsStringSync('');
      }

      // 包内 config.json 覆盖默认参数（DMD2 蒸馏模型在此提供 steps/cfg）
      await _applyPackConfig(model);

      final missing = LocalDreamModelPack.missingFiles(model.filePath, type);
      if (missing.isNotEmpty) {
        await _fail(model.id!, '解压完成但缺少文件：${missing.join('、')}');
        return;
      }
      await repo.updateStatus(model.id!, ImageModelStatus.ready);
      LoggerService.instance.i('模型包下载完成: ${model.name}',
          category: LogCategory.ai,
          tags: ['local_dream_pack', 'download', 'done']);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return; // 暂停/取消属预期
      await _fail(model.id!, '下载失败：${e.message ?? e.type.name}');
    } on ArchiveException catch (e) {
      await _fail(model.id!, '压缩包损坏或无法解压：$e');
    } catch (e) {
      await _fail(model.id!, '下载失败：$e');
    } finally {
      // 只移除属于自己的 token（防误删后继下载任务的占位）
      if (identical(_cancelTokens[model.id], cancelToken)) {
        _cancelTokens.remove(model.id);
      }
      _onChanged.add(null);
    }
  }

  /// 暂停（保留 .part，续传从已下载字节继续）
  void pause(int modelId) {
    _cancelTokens[modelId]?.cancel('pause');
    _ref
        .read(imageModelRepositoryProvider)
        .updateStatus(modelId, ImageModelStatus.paused);
    _onChanged.add(null);
  }

  /// 取消并删除包目录、zip 残留与占位行
  Future<void> cancelAndDelete(ImageModel model) async {
    _cancelTokens[model.id]?.cancel('delete');
    if (model.filePath.startsWith(await modelsRootDir())) {
      final dir = Directory(model.filePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    // .part 在包目录外（<dir>.zip.part），单独清理避免 GB 级孤儿文件
    final zipPart = File('${model.filePath}.zip.part');
    if (zipPart.existsSync()) zipPart.deleteSync();
    if (model.id != null) {
      await _ref.read(imageModelRepositoryProvider).delete(model.id!);
    }
    _onChanged.add(null);
  }

  /// 从本地目录导入：把源目录内的包文件拷入包目录（GB 级文件用
  /// File.copy 流式拷贝），返回拷到的必需文件数（供 UI 提示缺多少）。
  /// 完成后调用方负责按缺失数置 ready/failed 并刷新列表。
  Future<int> importFromDirectory({
    required ImageModel model,
    required String sourceDir,
  }) async {
    final type = LocalDreamPackType.parse(model.remoteModelId);
    if (type == null) return 0;
    final source = Directory(sourceDir);
    if (!source.existsSync()) return 0;

    var copiedRequired = 0;
    for (final entity in source.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!type.requiredFiles.contains(name) &&
          !['.mnn', '.bin', '.json', '.patch']
              .any(p.extension(name).toLowerCase().endsWith)) {
        continue;
      }
      final target = File(p.join(model.filePath, name));
      if (target.existsSync()) target.deleteSync();
      await entity.copy(target.path);
      if (type.requiredFiles.contains(name)) copiedRequired++;
    }
    LoggerService.instance.i(
        '模型包导入完成: ${model.name}, 必需文件 $copiedRequired/${type.requiredFiles.length}',
        category: LogCategory.ai,
        tags: ['local_dream_pack', 'import', 'done']);
    return copiedRequired;
  }

  /// 从本地目录导入模型包：创建占位行 → 拷贝必需文件 → NPU 打 v3 标记 →
  /// 合并包内 config.json → 按缺失情况置 ready/failed。
  /// UI 只负责选目录与展示结果。返回最终行与拷到的必需文件数。
  Future<({ImageModel row, int copied})> importPackDirectory({
    required LocalDreamPackType type,
    required String sourceDir,
    required String displayName,
  }) async {
    final entry = LocalDreamPackEntry(
      id: displayName,
      name: displayName,
      type: type,
      description: '从目录导入',
      zipUri: '',
      approximateSize: '本地',
      defaultPrompt: '',
      defaultNegativePrompt: '',
    );
    final row = await createDownloadingRow(entry: entry, zipUrl: '');
    final copied = await importFromDirectory(model: row, sourceDir: sourceDir);

    final repo = _ref.read(imageModelRepositoryProvider);
    if (copied < type.requiredFiles.length) {
      await _fail(row.id!,
          '源目录缺少 ${type.requiredFiles.length - copied} 个必需文件');
    } else {
      if (type.needsQnnLibs) {
        File(p.join(row.filePath, 'v3')).writeAsStringSync('');
      }
      await _applyPackConfig(row);
      final missing = LocalDreamModelPack.missingFiles(row.filePath, type);
      if (missing.isEmpty) {
        await repo.updateStatus(row.id!, ImageModelStatus.ready);
      } else {
        await _fail(row.id!, '解压/拷贝后仍缺少文件：${missing.join('、')}');
      }
    }
    _onChanged.add(null);
    return (row: (await repo.getById(row.id!))!, copied: copied);
  }

  // ===== 内部实现 =====

  /// zip 下载（.part + Range 续传），字节级进度聚合到行 progress。
  /// 返回落盘的 zip 路径。
  Future<String> _downloadZip({
    required ImageModel model,
    required CancelToken cancelToken,
  }) async {
    final partPath = '${model.filePath}.zip.part';
    final part = File(partPath);
    var startFrom = 0;
    if (part.existsSync()) startFrom = part.lengthSync();

    final response = await _dio.get<ResponseBody>(
      model.sourceUrl,
      options: Options(
        responseType: ResponseType.stream,
        headers: startFrom > 0 ? {'range': 'bytes=$startFrom-'} : null,
        validateStatus: (s) => s != null && s < 500,
      ),
      cancelToken: cancelToken,
    );
    if (response.statusCode == 404) {
      throw Exception('下载地址 404：${model.sourceUrl}');
    }
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('下载地址返回 HTTP ${response.statusCode}');
    }

    // 断点续传损坏防护：请求了 Range 但服务器不支持（忽略头回 200 全量）
    // 时，不能把完整响应追加到旧 .part 尾部（产出损坏 zip）——
    // 按 0 起全量重下（截断 .part）
    if (response.statusCode == 200 && startFrom > 0) {
      LoggerService.instance.w(
          '下载源不支持断点续传（HTTP 200），回退全量重下: ${model.name}',
          category: LogCategory.ai,
          tags: ['local_dream_pack', 'download', 'resume_fallback']);
      startFrom = 0;
    }

    // 总字节数（Range 响应从 Content-Range 尾部取全量大小）
    var totalBytes = startFrom;
    final contentRange = response.headers.value('content-range');
    if (contentRange != null) {
      final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
      if (match != null) totalBytes = int.parse(match.group(1)!);
    } else {
      // ResponseBody.contentLength 非 null 语义（未知时为 -1）
      final declared = response.data!.contentLength;
      totalBytes = startFrom + (declared > 0 ? declared : 0);
    }

    // startFrom > 0：Range 续传追加到旧 .part 尾部；
    // startFrom == 0（首次下载或 200 回退重下）：FileMode.write 截断重建
    final sink = part.openWrite(
        mode: startFrom > 0 ? FileMode.append : FileMode.write);
    var received = startFrom;
    var lastUpdate = DateTime.now();
    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        // 节流写库（≥1s 或 ≥5MB，对齐单文件下载服务）
        if (totalBytes > 0 &&
            (DateTime.now().difference(lastUpdate).inMilliseconds >= 1000 ||
                received - startFrom >= 5 * 1024 * 1024)) {
          lastUpdate = DateTime.now();
          final pct = (received * 95 ~/ totalBytes).clamp(0, 95);
          await _ref
              .read(imageModelRepositoryProvider)
              .updateProgress(model.id!, pct);
          _onChanged.add(null);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    _onChanged.add(null);
    return partPath;
  }

  /// 流式解压 zip 到包目录。GB 级 zip 的目录解析与逐条目拷贝放后台
  /// isolate，避免冻结 UI；archive 经 InputFileStream 按需读取，不把
  /// 整包载入内存。只取各条目的文件名，防 zip-slip。
  Future<void> _extractZip(String zipPath, String packDir) async {
    await Isolate.run(() {
      final input = InputFileStream(zipPath);
      try {
        final archive = ZipDecoder().decodeBuffer(input);
        for (final file in archive.files) {
          if (!file.isFile) continue;
          final name = p.basename(file.name.replaceAll('\\', '/'));
          if (name.isEmpty || name == '.' || name == '..') continue;
          final output = OutputFileStream(p.join(packDir, name));
          try {
            file.writeContent(output);
          } finally {
            output.closeSync();
          }
        }
      } finally {
        input.closeSync();
      }
    });
    // 解压完成，删掉 zip 残留
    final zipPart = File(zipPath);
    if (zipPart.existsSync()) zipPart.deleteSync();
  }

  /// 读包内 config.json 合并默认值（prompt/negativePrompt/steps/cfg/
  /// scheduler；DMD2 蒸馏模型在此提供步数/CFG）。缺失/损坏不阻断就绪
  /// （有目录条目级默认值兜底）。
  Future<void> _applyPackConfig(ImageModel model) async {
    final configFile = File(p.join(model.filePath, 'config.json'));
    if (!configFile.existsSync()) return;
    try {
      final config =
          jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
      final negative = (config['negativePrompt'] ??
              config['negative_prompt']) as String?;
      final steps = config['steps'];
      final cfg = config['cfg'];
      if ((negative == null || negative.isEmpty) &&
          steps is! num &&
          cfg is! num) {
        return;
      }
      final repo = _ref.read(imageModelRepositoryProvider);
      final current = await repo.getById(model.id!);
      if (current == null) return;
      await repo.save(current.copyWith(
        negativePrompt:
            (negative != null && negative.isNotEmpty) ? negative : null,
        defaultSteps: steps is num ? steps.toInt() : null,
        defaultCfg: cfg is num ? cfg.toDouble() : null,
      ));
      LoggerService.instance.i('已合并模型包 config.json 默认参数: ${model.name}',
          category: LogCategory.ai,
          tags: ['local_dream_pack', 'config']);
    } catch (e) {
      LoggerService.instance.w('模型包 config.json 解析失败（忽略）: $e',
          category: LogCategory.ai,
          tags: ['local_dream_pack', 'config']);
    }
  }

  Future<void> _fail(int id, String message) async {
    await _ref
        .read(imageModelRepositoryProvider)
        .updateStatus(id, ImageModelStatus.failed, errorMessage: message);
    LoggerService.instance.e('模型包下载失败: $message',
        category: LogCategory.ai,
        tags: ['local_dream_pack', 'download', 'error']);
    _onChanged.add(null);
  }
}
