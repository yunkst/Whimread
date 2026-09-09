/// OCR 模型后台下载服务
///
/// 背景(2026-09-08 决策):
///   - `inference.onnx` (21MB) + `ppocrv6_dict.txt` (75KB) 原本在 assets/,APK 多 21MB
///   - 改成启动后后台从 CloudBase Storage 拉取
///   - 模型独立版本号 (`model_version`) 跟 APK 解耦,APK 升级不重下
///   - 仅在 `model_version` 变化 / 本地无文件 / 本地 sha256 不一致时才下载
///
/// 路径:
///   - `<getApplicationSupportDirectory>/ocr_models/inference.onnx`
///   - `<getApplicationSupportDirectory>/ocr_models/ppocrv6_dict.txt`
///   - `<getApplicationSupportDirectory>/ocr_models/meta.json` 含 `modelVersion` / `modelSha256` / `dictSha256` / `downloadedAt`
///
/// 重试:失败 3 次,30 秒间隔(指数退避)。最终失败抛异常给调用方
///   (通常是 `ocrPredictorProvider`,UI 那边 catch StateError 报"模型下载中")。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'logger_service.dart';

class OcrModelManifest {
  final String modelVersion;
  final String releasedAt;
  final Map<String, OcrModelEntry> arch;     // arch → entry
  final OcrModelEntry dict;                  // 共享一个 dict

  OcrModelManifest({
    required this.modelVersion,
    required this.releasedAt,
    required this.arch,
    required this.dict,
  });

  factory OcrModelManifest.fromJson(Map<String, dynamic> j) {
    final archJson = j['arch'] as Map<String, dynamic>;
    final arch = <String, OcrModelEntry>{};
    for (final e in archJson.entries) {
      arch[e.key] = OcrModelEntry.fromJson(e.value as Map<String, dynamic>);
    }
    return OcrModelManifest(
      modelVersion: j['model_version'] as String,
      releasedAt: (j['released_at'] as String?) ?? '',
      arch: arch,
      dict: OcrModelEntry.fromJson(j['dict'] as Map<String, dynamic>),
    );
  }
}

class OcrModelEntry {
  final String url;
  final String sha256;
  final int size;

  OcrModelEntry({required this.url, required this.sha256, required this.size});

  factory OcrModelEntry.fromJson(Map<String, dynamic> j) => OcrModelEntry(
        url: j['url'] as String,
        sha256: j['sha256'] as String,
        size: (j['size'] as num).toInt(),
      );
}

class OcrModelDownloader {
  /// 公网 manifest URL(只读)
  /// bucket = 7768-whimread-dev-d0gm4oi0z3099082d-1256733196
  /// path = /ocr-models/v1/manifest.json
  /// 公开读 ACL,无需签名
  static const String manifestUrl =
      'https://7768-whimread-dev-d0gm4oi0z3099082d-1256733196.tcb.qcloud.la/'
      'ocr-models/v1/manifest.json';

  static const String _localDir = 'ocr_models';
  static const String _localModelName = 'inference.onnx';
  static const String _localDictName = 'ppocrv6_dict.txt';
  static const String _localMetaName = 'meta.json';

  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 30);

  final Dio _dio;
  final Future<String> Function() _archProvider;   // 异步 / 同步返回当前 arch 字符串

  /// 缓存:同一启动周期内只跑一次 ensureLocal
  Future<OcrModelManifest>? _pending;

  OcrModelDownloader({Dio? dio, required Future<String> Function() archProvider})
      : _dio = dio ?? _buildDefaultDio(),
        _archProvider = archProvider;

  static Dio _buildDefaultDio() {
    return Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),    // 21MB 模型需要长 receive
      sendTimeout: const Duration(seconds: 30),
    ));
  }

  // ---- 本地路径 ----
  Future<Directory> _localRoot() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_localDir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _localModelFile() async => File('${(await _localRoot()).path}/$_localModelName');
  Future<File> _localDictFile() async => File('${(await _localRoot()).path}/$_localDictName');
  Future<File> _localMetaFile() async => File('${(await _localRoot()).path}/$_localMetaName');

  /// 给 OcrPredictor.load() 用的本地文件路径
  /// (调用方在 await ensureLocal() 成功后再读)
  Future<String> localModelPath() async => (await _localModelFile()).path;
  Future<String> localDictPath() async => (await _localDictFile()).path;

  // ---- 主入口:启动期后台调度 ----
  /// 不抛异常,失败内部记日志 + 抛 StateError 让 OcrPredictor 走降级
  Future<OcrModelManifest> ensureLocal() {
    _pending ??= _doEnsure();
    return _pending!;
  }

  Future<OcrModelManifest> _doEnsure() async {
    LoggerService.instance.i(
      'OCR 模型下载: 启动检查 manifest=$manifestUrl',
      category: LogCategory.ai,
      tags: ['ocr', 'model-download', 'start'],
    );

    // 1. 拉 manifest
    OcrModelManifest manifest;
    try {
      final resp = await _dio.get<String>(
        manifestUrl,
        options: Options(responseType: ResponseType.plain),
      );
      manifest = OcrModelManifest.fromJson(
          json.decode(resp.data ?? '{}') as Map<String, dynamic>);
    } catch (e, st) {
      _err('拉 manifest 失败', e, st);
      rethrow;
    }

    final arch = await _archProvider();
    final archEntry = manifest.arch[arch];
    if (archEntry == null) {
      _err('当前架构 $arch 不在 manifest 里(manifest 提供: ${manifest.arch.keys.join(', ')})',
          null, null);
      throw StateError('OCR manifest 缺少当前架构 $arch');
    }

    // 2. 读本地 meta
    final metaFile = await _localMetaFile();
    Map<String, dynamic>? meta;
    if (await metaFile.exists()) {
      try {
        meta = json.decode(await metaFile.readAsString()) as Map<String, dynamic>;
      } catch (_) {/* 损坏忽略 */}
    }

    final modelFile = await _localModelFile();
    final dictFile = await _localDictFile();
    final modelExists = await modelFile.exists();
    final dictExists = await dictFile.exists();
    final modelLocalSha = modelExists ? await _sha256Of(modelFile) : null;
    final dictLocalSha = dictExists ? await _sha256Of(dictFile) : null;

    // 3. 决策
    final needModel = !modelExists
        || modelLocalSha != archEntry.sha256
        || meta?['modelVersion'] != manifest.modelVersion;
    final needDict = !dictExists
        || dictLocalSha != manifest.dict.sha256
        || meta?['modelVersion'] != manifest.modelVersion;

    if (!needModel && !needDict) {
      LoggerService.instance.i(
        'OCR 模型已就绪(本地 sha256 匹配, version=${manifest.modelVersion})',
        category: LogCategory.ai,
        tags: ['ocr', 'model-download', 'skip', 'hit'],
      );
      return manifest;
    }

    LoggerService.instance.i(
      'OCR 模型需要下载: needModel=$needModel needDict=$needDict version=${manifest.modelVersion}',
      category: LogCategory.ai,
      tags: ['ocr', 'model-download', 'start-download'],
    );

    // 4. 下载(各自独立重试)
    if (needModel) {
      await _downloadWithRetry(
        url: archEntry.url,
        expectSha256: archEntry.sha256,
        dest: modelFile,
        label: 'inference.onnx',
        onProgress: (rec, total) => _logProgress('inference.onnx', rec, total),
      );
    }
    if (needDict) {
      await _downloadWithRetry(
        url: manifest.dict.url,
        expectSha256: manifest.dict.sha256,
        dest: dictFile,
        label: 'ppocrv6_dict.txt',
        onProgress: (rec, total) => _logProgress('dict', rec, total),
      );
    }

    // 5. 写 meta(原子)
    final tmpMeta = File('${metaFile.path}.tmp');
    await tmpMeta.writeAsString(json.encode({
      'modelVersion': manifest.modelVersion,
      'modelSha256': archEntry.sha256,
      'dictSha256': manifest.dict.sha256,
      'downloadedAt': DateTime.now().toIso8601String(),
    }));
    await tmpMeta.rename(metaFile.path);

    LoggerService.instance.i(
      'OCR 模型下载完成 version=${manifest.modelVersion} '
      'model=${archEntry.size}B dict=${manifest.dict.size}B',
      category: LogCategory.ai,
      tags: ['ocr', 'model-download', 'done'],
    );
    return manifest;
  }

  Future<void> _downloadWithRetry({
    required String url,
    required String expectSha256,
    required File dest,
    required String label,
    void Function(int received, int total)? onProgress,
  }) async {
    Object? lastErr;
    for (var attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        await _downloadOnce(url, expectSha256, dest, onProgress);
        return;
      } catch (e) {
        lastErr = e;
        LoggerService.instance.w(
          'OCR 模型 $label 下载失败(尝试 $attempt/$_maxRetries): $e',
          category: LogCategory.ai,
          tags: ['ocr', 'model-download', 'retry', 'attempt-$attempt'],
        );
        if (attempt < _maxRetries) {
          await Future.delayed(_retryDelay);
        }
      }
    }
    throw StateError('OCR 模型 $label 下载失败(重试 $_maxRetries 次): $lastErr');
  }

  Future<void> _downloadOnce(
    String url,
    String expectSha256,
    File dest,
    void Function(int received, int total)? onProgress,
  ) async {
    final tmp = File('${dest.path}.tmp');
    if (await tmp.exists()) await tmp.delete();

    final resp = await _dio.get<ResponseBody>(
      url,
      options: Options(responseType: ResponseType.stream),
    );
    final total = int.tryParse(
            resp.headers.value(HttpHeaders.contentLengthHeader) ?? '') ??
        -1;
    var received = 0;
    final sink = tmp.openWrite();
    try {
      await for (final chunk in resp.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }

    // SHA256 校验
    final actual = await _sha256Of(tmp);
    if (actual != expectSha256) {
      await tmp.delete();
      throw StateError(
          'SHA256 不一致: 期望 $expectSha256, 实际 $actual ($url)');
    }

    // 原子替换
    if (await dest.exists()) await dest.delete();
    await tmp.rename(dest.path);
  }

  // ---- 工具 ----
  Future<String> _sha256Of(File f) async {
    final bytes = await f.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  void _logProgress(String label, int received, int total) {
    if (total > 0) {
      LoggerService.instance.d(
        'OCR 模型 $label 进度 ${(received * 100 / total).toStringAsFixed(1)}% '
        '($received / $total)',
        category: LogCategory.ai,
        tags: ['ocr', 'model-download', 'progress'],
      );
    }
  }

  void _err(String msg, Object? e, StackTrace? st) {
    LoggerService.instance.e(
      'OCR 模型: $msg${e != null ? ' err=$e' : ''}',
      stackTrace: st?.toString(),
      category: LogCategory.ai,
      tags: ['ocr', 'model-download', 'error'],
    );
  }
}
