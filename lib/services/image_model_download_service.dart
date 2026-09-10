/// 生图模型下载服务
///
/// 从内置浏览器拦截的 URL 下载模型文件到应用私有目录，完成后按扩展名分流：
/// - `.gguf` → 移入 image_models 目录，模型置 ready
/// - `.safetensors` → 置 converting → 端上转换（Q8_0）→ 产出 gguf 置 ready
///   （转换成功后自动删除 safetensors 源文件释放空间）
///
/// 技术要点（沿用旧 ModelDownloadService 验证过的模式，2026-07 因后端移除删除）：
/// - Dio ResponseType.stream + Range 断点续传（续传偏移 = `.part` 文件当前大小）
/// - CancelToken 暂停/恢复
/// - 节流落库：≥1s 或 ≥5MB 才写一次 DB，避免 GB 级文件写爆 SQLite
/// - 任务即 image_models 行（status/progress 列），无独立任务表
///
/// 进程边界：in-process 下载（前台运行）；App 被杀后由 [recoverOnStartup]
/// 对账（downloading→paused 可续传，converting→failed 可重试转换）。
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/interfaces/repositories/i_image_model_repository.dart';
import '../models/image_model.dart';
import 'conversion/model_converter.dart';
import 'image_model_import_service.dart';
import 'logger_service.dart';

class ImageModelDownloadService {
  final IImageModelRepository _repo;
  final Dio _dio;

  /// modelId → CancelToken
  final Map<int, CancelToken> _cancelTokens = {};

  /// modelId → 内存中的字节数缓存（percent 计算用；重启后从 .part 大小重建）
  final Map<int, _DownloadState> _states = {};

  /// 转换串行队列（端侧 CPU 密集，避免并发转换互相拖慢）
  Future<void> _conversionChain = Future.value();

  /// 状态变更事件（UI 订阅刷新卡片）
  final StreamController<ImageModel> _changed =
      StreamController<ImageModel>.broadcast();
  Stream<ImageModel> get onChanged => _changed.stream;

  ImageModelDownloadService({
    required IImageModelRepository repo,
    Dio? dio,
  })  : _repo = repo,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(minutes: 60),
            ));

  // ============================================================
  // 下载入口
  // ============================================================

  /// 为已存在的模型行（status=downloading）启动下载。
  ///
  /// [cookieHeader]/[userAgent] 从浏览器拦截点转发（保住 Civitai 等站登录态），
  /// 必须按原始请求头字符串传入（例 `"a=b; c=d"`），不要外层包 `Cookie:` 键
  /// （避免双重 Cookie 前缀 bug）。
  Future<void> startDownload(
    ImageModel model, {
    String? cookieHeader,
    String? userAgent,
  }) async {
    if (_cancelTokens.containsKey(model.id)) return; // 已在下载
    final token = CancelToken();
    _cancelTokens[model.id!] = token;
    _states[model.id!] = _DownloadState();

    try {
      final dir = await _downloadDir();
      final partPath = p.join(dir.path, '${model.id}.part');
      final partFile = File(partPath);
      final startByte = await partFile.exists() ? await partFile.length() : 0;

      final headers = <String, dynamic>{
        if (userAgent != null) 'User-Agent': userAgent,
        if (cookieHeader != null && cookieHeader.isNotEmpty)
          'Cookie': cookieHeader,
        if (startByte > 0) 'Range': 'bytes=$startByte-',
      };

      final response = await _dio.get<ResponseBody>(
        model.sourceUrl,
        options: Options(
          responseType: ResponseType.stream,
          headers: headers,
          followRedirects: true,
          validateStatus: (s) => s != null && s < 400,
        ),
        cancelToken: token,
      );

      // 解析总大小（Range 响应从 Content-Range 取完整值）
      var totalSize = _states[model.id]!.totalSize;
      final contentRange = response.headers.value('content-range');
      final contentLength = response.headers.value('content-length');
      if (contentRange != null) {
        final m = RegExp(r'/(\d+)$').firstMatch(contentRange);
        if (m != null) totalSize = int.parse(m.group(1)!);
      } else if (contentLength != null) {
        totalSize = int.tryParse(contentLength) ?? totalSize;
      }
      _states[model.id]!.totalSize = totalSize;

      final sink = partFile.openWrite(mode: FileMode.append);
      var received = startByte;
      var lastFlush = DateTime.now();
      var lastFlushBytes = received;
      final completer = Completer<void>();

      response.data!.stream.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastFlush).inMilliseconds >= 1000 ||
              received - lastFlushBytes >= 5 * 1024 * 1024) {
            lastFlush = now;
            lastFlushBytes = received;
            _reportProgress(model.id!, received, totalSize);
          }
        },
        onError: (Object e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          sink.flush().then((_) => sink.close()).then((_) {
            if (!completer.isCompleted) completer.complete();
          });
        },
        cancelOnError: true,
      );
      await completer.future;

      _cancelTokens.remove(model.id);
      await _onDownloadComplete(model, partPath);
    } on DioException catch (e) {
      _cancelTokens.remove(model.id);
      if (e.type == DioExceptionType.cancel) {
        // 暂停/取消：状态由调用方已设置
        return;
      }
      await _repo.updateStatus(model.id!,
          ImageModelStatus.failed,
          errorMessage: e.message ?? '网络错误');
      _emitById(model.id!);
    } catch (e) {
      _cancelTokens.remove(model.id);
      await _repo.updateStatus(model.id!, ImageModelStatus.failed,
          errorMessage: e.toString());
      _emitById(model.id!);
    }
  }

  /// 下载完成分流：gguf 直接入库；safetensors 进转换
  Future<void> _onDownloadComplete(
      ImageModel model, String partPath) async {
    final ext = _extensionOf(model.sourceUrl, fallback: model.filePath);
    final id = model.id!;

    if (ext == 'gguf') {
      final dest = await ImageModelImportService.finalizedModelPath('gguf');
      await File(partPath).rename(dest);
      final size = await File(dest).length();
      await _repo.updateStatus(id, ImageModelStatus.ready,
          progress: 100, filePath: dest, fileSize: size);
      _emitById(id);
      LoggerService.instance.i('模型下载完成(gguf): id=$id, $dest',
          category: LogCategory.ai,
          tags: ['image_model', 'download', 'done']);
      return;
    }

    // safetensors → 转换
    final safetensorsPath = p.join(
        (await _downloadDir()).path, '${id}_source.safetensors');
    await File(partPath).rename(safetensorsPath);
    await _repo.updateStatus(id, ImageModelStatus.converting, progress: 0);
    _emitById(id);

    _conversionChain = _conversionChain.then((_) =>
        _convertAndFinalize(id, safetensorsPath));
  }

  /// 串行执行的转换步骤
  Future<void> _convertAndFinalize(int id, String safetensorsPath) async {
    try {
      await _repo.updateStatus(id, ImageModelStatus.converting, progress: 0);

      // 转换产物临时放 model_downloads，成功后移入 image_models
      final tmpOut = p.join(
          (await _downloadDir()).path, '${id}_converted.gguf');

      final result = await runConversion(
        sourcePath: safetensorsPath,
        outputPath: tmpOut,
        onProgress: (progress) {
          // 转换进度占 0-100；下载已占满的进度条重置语义由 UI 处理
          _repo.updateProgress(id, progress.percent);
          _emitById(id);
        },
      );

      final dest = await ImageModelImportService.finalizedModelPath('gguf');
      await File(tmpOut).rename(dest);
      final size = await File(dest).length();

      // 源 safetensors 自动删除（GB 级，转换成功即无保留价值）
      final src = File(safetensorsPath);
      if (await src.exists()) await src.delete();

      await _repo.updateStatus(id, ImageModelStatus.ready,
          progress: 100,
          filePath: dest,
          fileSize: size,
          defaultWidth: result.arch.defaultSize,
          defaultHeight: result.arch.defaultSize);
      LoggerService.instance.i(
          '模型转换完成: id=$id, arch=${result.arch.displayName}, '
          'quantized=${result.quantizedCount}, kept=${result.keptCount}',
          category: LogCategory.ai,
          tags: ['image_model', 'convert', 'done']);
      _emitById(id);
    } on ConversionException catch (e) {
      await _repo.updateStatus(id, ImageModelStatus.failed,
          errorMessage: e.message);
      _emitById(id);
    } catch (e) {
      await _repo.updateStatus(id, ImageModelStatus.failed,
          errorMessage: '转换失败: $e');
      LoggerService.instance.e('模型转换失败: id=$id, $e',
          category: LogCategory.ai,
          tags: ['image_model', 'convert', 'error']);
      _emitById(id);
    }
  }

  // ============================================================
  // 控制
  // ============================================================

  /// 暂停（下载阶段有效；转换不可暂停）
  Future<void> pause(int modelId) async {
    final token = _cancelTokens[modelId];
    token?.cancel('pause');
    final model = await _repo.getById(modelId);
    if (model != null && model.status == ImageModelStatus.downloading) {
      await _repo.updateStatus(modelId, ImageModelStatus.paused);
      _emitById(modelId);
    }
  }

  /// 继续（paused/failed → downloading，Range 从 .part 续传）
  Future<void> resume(ImageModel model,
      {String? cookieHeader, String? userAgent}) async {
    if (model.status != ImageModelStatus.paused &&
        model.status != ImageModelStatus.failed) {
      return;
    }
    final refreshed = model.copyWith(
      status: ImageModelStatus.downloading,
      errorMessage: '',
    );
    await _repo.updateStatus(refreshed.id!, refreshed.status);
    _emitById(refreshed.id!);
    unawaited(startDownload(refreshed,
        cookieHeader: cookieHeader, userAgent: userAgent));
  }

  /// 重试失败的转换（源 safetensors 仍在时）
  Future<void> retryConversion(ImageModel model) async {
    final dir = await _downloadDir();
    final src = File(p.join(dir.path, '${model.id}_source.safetensors'));
    if (!await src.exists()) {
      await _repo.updateStatus(model.id!, ImageModelStatus.failed,
          errorMessage: '源文件已不存在，请重新下载');
      _emitById(model.id!);
      return;
    }
    _conversionChain = _conversionChain
        .then((_) => _convertAndFinalize(model.id!, src.path));
  }

  /// 文件导入的 safetensors 转换入口（[ImageModelImportService] 产出
  /// needsConversion=true 时由管理页调用）。
  ///
  /// [importedSourcePath] 应位于 model_downloads 目录（导入服务的副本）；
  /// 模型行应已建好。统一重命名为 `<id>_source.safetensors`，使
  /// [retryConversion] 的路径约定对下载/导入两条链路一致。
  /// 转换成功后行置 ready、源副本自动删除。
  Future<void> startConversionForImportedFile(
      ImageModel model, String importedSourcePath) async {
    final dir = await _downloadDir();
    final canonical = p.join(dir.path, '${model.id}_source.safetensors');
    final src = File(importedSourcePath);
    if (p.normalize(importedSourcePath) != p.normalize(canonical)) {
      if (await src.exists()) await src.delete();
      await File(importedSourcePath).rename(canonical);
    }
    _conversionChain =
        _conversionChain.then((_) => _convertAndFinalize(model.id!, canonical));
  }

  /// 取消并清理（删除 .part / 源文件；行删除由调用方处理）
  Future<void> cleanupFiles(int modelId) async {
    _cancelTokens[modelId]?.cancel('delete');
    _cancelTokens.remove(modelId);
    _states.remove(modelId);
    final dir = await _downloadDir();
    for (final name in ['$modelId.part', '${modelId}_source.safetensors',
        '${modelId}_converted.gguf']) {
      final f = File(p.join(dir.path, name));
      if (await f.exists()) await f.delete();
    }
  }

  /// 启动对账：下载中被杀 → paused；转换中被杀 → failed（可重试）
  Future<void> recoverOnStartup() async {
    final downloading = await _repo.getByStatus(ImageModelStatus.downloading);
    for (final m in downloading) {
      await _repo.updateStatus(m.id!, ImageModelStatus.paused);
    }
    final converting = await _repo.getByStatus(ImageModelStatus.converting);
    for (final m in converting) {
      await _repo.updateStatus(m.id!, ImageModelStatus.failed,
          errorMessage: '进程中断，转换未完成，可重试');
    }
  }

  // ============================================================
  // 工具
  // ============================================================

  void _reportProgress(int modelId, int received, int totalSize) {
    final state = _states[modelId];
    if (state != null) state.received = received;
    if (totalSize > 0) {
      final percent = (received * 100 ~/ totalSize).clamp(0, 100);
      unawaited(_repo.updateProgress(modelId, percent).then((_) {
        _emitById(modelId);
      }));
    }
  }

  void _emitById(int modelId) {
    unawaited(_repo.getById(modelId).then((m) {
      if (m != null) _changed.add(m);
    }));
  }

  String _extensionOf(String url, {String fallback = ''}) {
    final path = Uri.tryParse(url)?.path ?? '';
    if (path.toLowerCase().endsWith('.safetensors')) return 'safetensors';
    if (path.toLowerCase().endsWith('.gguf')) return 'gguf';
    if (fallback.toLowerCase().endsWith('.safetensors')) return 'safetensors';
    return 'gguf';
  }

  Future<Directory> _downloadDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'model_downloads'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  void dispose() {
    _changed.close();
  }
}

/// 下载会话内存状态（跨重启不持久；totalSize 从响应头重建）
class _DownloadState {
  int totalSize = 0;
  int received = 0;
}
