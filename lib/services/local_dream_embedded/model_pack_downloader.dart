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
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory;

import '../../core/providers/image_model_providers.dart'
    show imageModelRepositoryProvider;
import '../../models/image_model.dart';
import '../../services/logger_service.dart';
import 'model_pack.dart';

/// 一次细粒度下载进度采样（仅内存广播，不落库）
@immutable
class PackDownloadSample {
  final int modelId;

  /// 已落盘字节数（含续传前 .part 的既有长度）
  final int receivedBytes;

  /// 全量字节数；服务端未给 Content-Length 时为 null
  final int? totalBytes;

  /// 采样窗口内的瞬时速度（B/s）
  final double bytesPerSecond;

  /// 0-100 真实百分比（总量未知时为 0）
  final int percent;

  final DateTime at;

  const PackDownloadSample({
    required this.modelId,
    required this.receivedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
    required this.percent,
    required this.at,
  });

  /// 剩余秒数（总量已知且在移动时）
  double? get etaSeconds {
    final total = totalBytes;
    if (total == null || bytesPerSecond <= 0) return null;
    final remain = total - receivedBytes;
    if (remain <= 0) return 0;
    return remain / bytesPerSecond;
  }
}

class LocalDreamModelPackDownloader {
  /// zip 压缩方法号（archive 未导出 ZipCompressionType）：8=DEFLATE，0=STORE
  static const int _zipMethodDeflate = 8;

  final Ref _ref;
  final Dio _dio;

  /// 每个进行中的包一个 CancelToken（key = image_models.id）
  final Map<int, CancelToken> _cancelTokens = {};

  /// 事件流：管理页 lifecycle provider 监听刷新
  final _onChanged = StreamController<void>.broadcast();
  Stream<void> get onChanged => _onChanged.stream;

  /// 细粒度进度采样流（≈2Hz，仅内存态不落库）：UI 展示真实字节/速度/剩余。
  /// progress 列是 1% 粒度的整数，GB 级包看着像卡死，用它兜细看。
  final _progressSamples = StreamController<PackDownloadSample>.broadcast();
  Stream<PackDownloadSample> get progressSamples => _progressSamples.stream;

  LocalDreamModelPackDownloader({required Ref ref, Dio? dio})
      : _ref = ref,
        _dio = dio ??
            Dio(BaseOptions(
              // 反馈 #9：切后台后 socket 被系统静默掐断（vivo 冻结/杀进程、
              // 网络切换），零超时的 await for 会永远等下去——进度条卡死、
              // 状态停在 downloading、不报错。超时把静默死亡变成可续传的
              // failed。receiveTimeout 是「两次数据事件之间」的间隔超时，
              // 大文件慢速下载也不会误伤。
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 60),
            ));

  @visibleForTesting
  bool hasActiveDownload(int modelId) => _cancelTokens.containsKey(modelId);

  void dispose() {
    _onChanged.close();
    _progressSamples.close();
  }

  /// 启动对账：进程被杀遗留的 downloading 行归位为 paused
  /// （.part 已保留，用户点"继续下载"即从断点续传）。
  /// App 启动时调用一次；进行中的下载不存在于此时点（单实例假设）。
  /// 返回是否发现并归位了 stuck 行。
  Future<bool> recoverInterruptedDownloads() async {
    final repo = _ref.read(imageModelRepositoryProvider);
    final stuck = await repo.getByStatus(ImageModelStatus.downloading);
    if (stuck.isEmpty) return false;
    for (final row in stuck) {
      await repo.updateStatus(row.id!, ImageModelStatus.paused);
    }
    LoggerService.instance.i(
        '模型包下载对账：${stuck.length} 行 downloading → paused',
        category: LogCategory.ai,
        tags: ['local_dream_pack', 'recover']);
    _onChanged.add(null);
    return true;
  }

  /// 自愈：库里 downloading 但本进程**没有**进行中任务的孤儿行，直接续传。
  ///
  /// 覆盖启动对账管不到的场景——同进程内下载任务死掉但行状态没机会归位
  /// （典型：切后台被系统冻结，恢复前台后任务已被超时终结）。app 回前台
  /// 时调用（HomePage 生命周期 resumed）；有活跃任务的行跳过（幂等守卫
  /// 兜底，不会双写同一 .part）。返回自愈的行数。
  Future<int> resumeOrphanDownloads() async {
    final repo = _ref.read(imageModelRepositoryProvider);
    final downloading = await repo.getByStatus(ImageModelStatus.downloading);
    var healed = 0;
    for (final row in downloading) {
      final id = row.id;
      if (id == null || _cancelTokens.containsKey(id)) continue;
      healed++;
      LoggerService.instance.w(
        '孤儿下载自愈：续传 "${row.name}" (id=$id)',
        category: LogCategory.ai,
        tags: ['local_dream_pack', 'orphan-heal'],
      );
      unawaited(startDownload(row));
    }
    if (healed > 0) _onChanged.add(null);
    return healed;
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
  /// [catalogId] 落库的目录条目 id（目录导入传空——它不对应 catalog 条目）。
  ///
  /// 同名的未就绪行（paused/failed/downloading）会被**复用**而不是新插：
  /// 目录卡片对这类条目仍显示下载图标，若新插同名行会撞
  /// image_models.name 唯一索引（历史报错「生图模型名重复」→
  /// 「创建下载任务失败」），还会丢掉旧 .part 断点、留下重复记录。
  /// 复用时把 sourceUrl 刷成当前所选源——切换下载源后重下由此生效
  /// （hf-mirror 与官方内容一致，跨源断点续传安全）。
  Future<ImageModel> createDownloadingRow({
    required LocalDreamPackEntry entry,
    required String zipUrl,
    String? catalogId,
  }) async {
    final root = await modelsRootDir();
    final repo = _ref.read(imageModelRepositoryProvider);
    final displayName = '${entry.name}（${entry.type.label}）';
    final now = DateTime.now();

    if (zipUrl.isNotEmpty) {
      final existing = await repo.getByName(displayName);
      if (existing != null && !existing.status.isReady) {
        // 包目录缺失时补建（用户手动清文件后的续传仍可用）
        final packDir = Directory(existing.filePath);
        if (!packDir.existsSync()) packDir.createSync(recursive: true);
        await repo.save(existing.copyWith(
          sourceUrl: zipUrl,
          catalogId: catalogId ?? entry.id,
          status: ImageModelStatus.downloading,
          updatedAt: now,
        ));
        _onChanged.add(null);
        return (await repo.getById(existing.id!))!;
      }
    }

    // 同名行已就绪（正常会被目录卡「已添加」态拦住，兜底防 UNIQUE 崩）
    var name = displayName;
    if (await repo.getByName(name) != null) {
      name = '$displayName ${now.millisecondsSinceEpoch}';
    }

    // 包目录用 Local Dream 的模型 id（重名冲突时加时间戳后缀）
    var packId = entry.id;
    if (Directory(p.join(root, packId)).existsSync()) {
      packId = '${entry.id}_${now.millisecondsSinceEpoch}';
    }
    final packDir = p.join(root, packId);
    Directory(packDir).createSync(recursive: true);
    final row = ImageModel(
      // NPU/CPU 变体同名（Local Dream 同款），加类型后缀保证本表 name 唯一
      name: name,
      description: '${entry.description} · 约 ${entry.approximateSize}',
      backendType: ImageModelBackendType.localDreamEmbedded,
      filePath: packDir,
      remoteModelId: entry.type.dbName,
      catalogId: catalogId ?? entry.id,
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

    // zip 落盘路径；解压失败时要删掉坏 .part（catch 块可见，故提声明）
    String? zipPath;
    try {
      await repo.updateStatus(model.id!, ImageModelStatus.downloading);
      zipPath = await _downloadZip(
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
      // 坏包不留给下次：完整大小的损坏 .part 会在续传时命中 416（大小吻合
      // → 跳过下载直接解压）再解压失败，形成死循环。删掉强制全量重下。
      if (zipPath != null) {
        final partFile = File(zipPath);
        if (partFile.existsSync()) partFile.deleteSync();
      }
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
    final row = await createDownloadingRow(
        entry: entry, zipUrl: '', catalogId: '');
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

    // 416 降级：请求 bytes=N- 且 N ≥ 远端全量时服务器回 416。两种来源——
    // ① .part 已是完整文件（上次下完、解压前被杀）：跳过下载直接解压；
    // ② 远端文件变小/换包了：截断 .part 全量重下（大小未知时保守同此）。
    Response<ResponseBody> response;
    while (true) {
      response = await _dio.get<ResponseBody>(
        model.sourceUrl,
        options: Options(
          responseType: ResponseType.stream,
          headers: startFrom > 0 ? {'range': 'bytes=$startFrom-'} : null,
          validateStatus: (s) => s != null && s < 500,
        ),
        cancelToken: cancelToken,
      );
      if (response.statusCode != 416) break;

      // 416 响应体必须排干，否则连接挂着不回收
      await response.data?.stream.drain<void>().catchError((Object _) {});

      final remoteTotal = int.tryParse(RegExp(r'bytes \*/(\d+)')
              .firstMatch(response.headers.value('content-range') ?? '')
              ?.group(1) ??
          '');
      if (remoteTotal != null && startFrom == remoteTotal) {
        LoggerService.instance.i(
          '断点已是完整 zip（416 + 大小吻合），跳过下载直接解压: ${model.name}',
          category: LogCategory.ai,
          tags: ['local_dream_pack', 'download', 'resume_complete'],
        );
        return partPath;
      }
      LoggerService.instance.w(
        '断点越界（HTTP 416），截断 .part 全量重下: '
        'part=$startFrom, remote=$remoteTotal, ${model.name}',
        category: LogCategory.ai,
        tags: ['local_dream_pack', 'download', 'resume_invalid'],
      );
      startFrom = 0;
    }

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
    var lastSampleAt = lastUpdate;
    var lastSampleBytes = received;
    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        // 细粒度采样（≈2Hz，仅内存广播）：UI 展示真实字节/速度/剩余时间。
        // 4GB 包的 1% = 40MB，DB 里 1 秒/5MB 节流的整数百分比看着像卡死
        final sampleMs = now.difference(lastSampleAt).inMilliseconds;
        if (sampleMs >= 500) {
          final speed = (received - lastSampleBytes) / (sampleMs / 1000);
          lastSampleAt = now;
          lastSampleBytes = received;
          _emitSample(model.id!, received, totalBytes, speed);
        }
        // 节流写库（≥1s 或 ≥5MB）：progress 列只服务冷启动恢复/对账展示
        if (totalBytes > 0 &&
            (now.difference(lastUpdate).inMilliseconds >= 1000 ||
                received - startFrom >= 5 * 1024 * 1024)) {
          lastUpdate = now;
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
    // 收尾必发一帧：不足 500ms 采样窗的尾包也要让 UI 走到 100%
    final tailMs =
        DateTime.now().difference(lastSampleAt).inMilliseconds.clamp(1, 1000);
    _emitSample(model.id!, received, totalBytes,
        (received - lastSampleBytes) / (tailMs / 1000));
    _onChanged.add(null);
    return partPath;
  }

  void _emitSample(int modelId, int received, int totalBytes, double speed) {
    if (_progressSamples.isClosed) return;
    _progressSamples.add(PackDownloadSample(
      modelId: modelId,
      receivedBytes: received,
      totalBytes: totalBytes > 0 ? totalBytes : null,
      bytesPerSecond: speed > 0 ? speed : 0,
      percent:
          totalBytes > 0 ? (received * 100 ~/ totalBytes).clamp(0, 100) : 0,
      at: DateTime.now(),
    ));
  }

  /// 流式解压 zip 到包目录。GB 级 zip 的目录解析与逐条目拷贝放后台
  /// isolate，避免冻结 UI；只取各条目的文件名，防 zip-slip。
  ///
  /// 不能用 `file.writeContent(output)`：zip 条目的 content 是 FileContent
  /// （ZipFile），它会先 `ZipFile.content` → `inflateBuffer(raw.toUint8List())`
  /// 整块解压进内存（raw 拷贝 + 解压结果两份 GB 级驻留）再写出——SDXL NPU
  /// 包的 unet 权重是 GB 级，手机直接 Out of Memory（用户实测：进度 95% 后
  /// failed(Out of Memory)，重试即 416）。
  /// 也不能用 `file.decompress(output)`：zip 条目的 `_content` 非空（存着
  /// ZipFile 本身），其 `if (_content == null)` 守卫直接短路产出空文件。
  /// 正确路径：拿 `rawContent`（压缩数据切片流）按 compressionMethod 自己
  /// 流式处理。
  Future<void> _extractZip(String zipPath, String packDir) async {
    await Isolate.run(() {
      final input = InputFileStream(zipPath);
      try {
      final archive = ZipDecoder().decodeBuffer(input);
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final name = p.basename(file.name.replaceAll('\\', '/'));
        if (name.isEmpty || name == '.' || name == '..') continue;
        // 跳过隐藏文件与 macOS 资源叉（对齐 Local Dream unzipFile）：
        // 包若由 macOS 打包会带 __MACOSX/xxx/._foo.mnn，扁平化后 basename
        // 是 '._foo.mnn'——不跳过会覆盖真正的 foo.mnn（几 KB 的空壳）
        if (name.startsWith('.') || file.name.startsWith('__MACOSX/')) {
          continue;
        }
        final raw = file.rawContent;
        if (raw == null) continue;
        final target = p.join(packDir, name);
        final output = OutputFileStream(target);
        try {
          if (file.compressionType == _zipMethodDeflate) {
            Inflate.stream(raw, output);
          } else {
            // STORE 及其它未压缩方法：原样拷贝
            output.writeInputStream(raw);
          }
        } finally {
          output.closeSync();
        }
        // 落盘长度校验：zip 条目被截断时 central directory 仍给得出文件名，
        // 缺文件检查查不出来，会把坏包置 ready（Local Dream 靠 JDK
        // ZipInputStream 的 CRC 校验兜底，这里用大小校验覆盖截断场景）。
        final written = File(target).lengthSync();
        if (written != file.size) {
          throw ArchiveException('解压长度不符：$name（$written != ${file.size}）');
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
