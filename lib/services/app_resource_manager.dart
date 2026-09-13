/// 统一动态资源管理器（启动资源引导）
///
/// 背景（2026-09-13 APK 瘦身决策）：
///   - arm64 APK 135MB 中，UI 字体 ~38MB + libsds.so ~57MB 占 70%
///   - 连同 OCR 模型（~21MB，此前已动态化）统一纳入启动校验 + 下载
///   - manifest 沿用 OcrModelDownloader 验证过的模式：
///     CloudBase 公开读 bucket + json manifest + sha256 校验 + 原子替换
///
/// 资源清单（`app-resources/v1/manifest.json`，各资源独立版本化）：
///   - ui_fonts  : Noto Serif/Sans SC 四个 ttf，下载后用 FontLoader 运行时注册
///   - sd_engine : libsds.so（arm64-v8a），下载后由 SdLibrary 按绝对路径 dlopen
///   - ocr_model : 不走本 manifest，由 OcrModelDownloader 独立下载（已有链路），
///     由 bootstrap 编排层统一调度与展示进度
///
/// 降级语义（所有失败都不阻塞进 App）：
///   - 字体缺失 → fontFamilyFallback 系统字体
///   - OCR 模型缺失 → OcrRestoreService 现有"模型下载中/失败"提示
///   - libsds.so 缺失 → LocalSdCppBackend.isEngineBinaryAvailable() = false，
///     生图走 engine_not_ready
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:path_provider/path_provider.dart';

import 'logger_service.dart';

// ============================================================
// manifest 模型
// ============================================================

/// manifest 中单个资源条目（一组文件 + 版本号）
class DynamicResourceSpec {
  final String id;
  final String version;
  final List<DynamicResourceFile> files;

  DynamicResourceSpec({
    required this.id,
    required this.version,
    required this.files,
  });

  factory DynamicResourceSpec.fromJson(Map<String, dynamic> j) =>
      DynamicResourceSpec(
        id: j['id'] as String,
        version: j['version'] as String? ?? '',
        files: (j['files'] as List<dynamic>)
            .map((e) => DynamicResourceFile.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class DynamicResourceFile {
  final String name;
  final String url;
  final String sha256;
  final int size;

  DynamicResourceFile({
    required this.name,
    required this.url,
    required this.sha256,
    required this.size,
  });

  factory DynamicResourceFile.fromJson(Map<String, dynamic> j) =>
      DynamicResourceFile(
        name: j['name'] as String,
        url: j['url'] as String,
        sha256: j['sha256'] as String,
        size: (j['size'] as num).toInt(),
      );
}

class AppResourcesManifest {
  final int manifestVersion;
  final Map<String, DynamicResourceSpec> resources; // id → spec

  AppResourcesManifest({required this.manifestVersion, required this.resources});

  factory AppResourcesManifest.fromJson(Map<String, dynamic> j) {
    final list = j['resources'] as List<dynamic>? ?? const [];
    final map = <String, DynamicResourceSpec>{};
    for (final e in list) {
      final spec = DynamicResourceSpec.fromJson(e as Map<String, dynamic>);
      map[spec.id] = spec;
    }
    return AppResourcesManifest(
      manifestVersion: (j['manifest_version'] as num?)?.toInt() ?? 1,
      resources: map,
    );
  }
}

// ============================================================
// 引导状态（UI 订阅）
// ============================================================

enum ResourceItemStatus { pending, checking, downloading, ready, failed }

class ResourceItemState {
  final String id;
  final ResourceItemStatus status;
  final int received;
  final int total;
  final String? error;

  const ResourceItemState({
    required this.id,
    this.status = ResourceItemStatus.pending,
    this.received = 0,
    this.total = 0,
    this.error,
  });

  double? get progress =>
      total <= 0 ? null : (received / total).clamp(0.0, 1.0);

  ResourceItemState copyWith({
    ResourceItemStatus? status,
    int? received,
    int? total,
    String? error,
  }) =>
      ResourceItemState(
        id: id,
        status: status ?? this.status,
        received: received ?? this.received,
        total: total ?? this.total,
        error: error ?? this.error,
      );
}

/// bootstrap 整体状态。itemIds 顺序即 UI 展示顺序。
class ResourceBootstrapState {
  final List<String> itemIds;
  final Map<String, ResourceItemState> items;
  final bool checking;   // 正在校验本地（尚未开始下载）
  final bool completed;  // 全部就绪（或无需下载）

  const ResourceBootstrapState({
    required this.itemIds,
    required this.items,
    this.checking = false,
    this.completed = false,
  });

  /// 总进度（已就绪资源按 100% 计入）。total 未知时返回 null。
  double? get overallProgress {
    var received = 0, total = 0, unknown = false;
    for (final id in itemIds) {
      final s = items[id];
      if (s == null) continue;
      if (s.status == ResourceItemStatus.ready) {
        total += 1;
        received += 1;
        continue;
      }
      if (s.total > 0) {
        total += s.total;
        received += s.received.clamp(0, s.total);
      } else {
        unknown = true;
      }
    }
    if (total == 0) return unknown ? null : 1.0;
    return received / total;
  }

  bool get hasFailure =>
      items.values.any((s) => s.status == ResourceItemStatus.failed);

  ResourceBootstrapState copyWith({
    Map<String, ResourceItemState>? items,
    bool? checking,
    bool? completed,
  }) =>
      ResourceBootstrapState(
        itemIds: itemIds,
        items: items ?? this.items,
        checking: checking ?? this.checking,
        completed: completed ?? this.completed,
      );
}

// ============================================================
// 管理器
// ============================================================

/// 统一资源 id 约定
abstract final class ResourceIds {
  static const String uiFonts = 'ui_fonts';
  static const String sdEngine = 'sd_engine';
  static const String ocrModel = 'ocr_model';
}

class AppResourceManager {
  /// 公网统一 manifest URL（只读，bucket 同 OCR 模型）
  static const String manifestUrl =
      'https://7768-whimread-dev-d0gm4oi0z3099082d-1256733196.tcb.qcloud.la/'
      'app-resources/v1/manifest.json';

  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 5);

  final Dio _dio;
  final Duration retryDelay;

  AppResourceManager({Dio? dio, Duration? retryDelay})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(minutes: 30),
            )),
        retryDelay = retryDelay ?? _retryDelay;

  // ---- SdLibrary 动态路径 ----
  /// libsds.so 下载完成后的绝对路径。由 [ensureSdEngine] 成功后写入，
  /// SdLibrary.open() 优先按此路径 dlopen（为空回退随包 so，兼容未瘦身构建）。
  static String? sdLibraryPath;

  // ---- manifest ----
  Future<AppResourcesManifest> fetchManifest() async {
    final resp = await _dio.get<String>(
      manifestUrl,
      options: Options(responseType: ResponseType.plain),
    );
    return AppResourcesManifest.fromJson(
        json.decode(resp.data ?? '{}') as Map<String, dynamic>);
  }

  // ---- 本地目录：<appSupport>/dynamic_resources/<id>/ ----
  Future<Directory> resourceDir(String id) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/dynamic_resources/$id');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _metaFile(String id) async =>
      File('${(await resourceDir(id)).path}/meta.json');

  /// 资源本地就绪且 sha256 匹配时返回本地文件路径表；否则返回 null。
  /// 就绪判定：所有文件存在 + sha256 匹配 spec（meta 版本号仅作日志参考，
  /// sha256 是唯一事实来源——模型/字体文件被用户清理后能自动重下）。
  Future<Map<String, String>?> localReadyFiles(DynamicResourceSpec spec) async {
    final dir = await resourceDir(spec.id);
    final paths = <String, String>{};
    for (final f in spec.files) {
      final file = File('${dir.path}/${f.name}');
      if (!await file.exists()) return null;
      if (await _sha256Of(file) != f.sha256) return null;
      paths[f.name] = file.path;
    }
    return paths;
  }

  /// 校验并按需下载一个资源。返回本地文件路径表。
  /// [onProgress] 以该资源全部文件的总字节为口径回报。
  Future<Map<String, String>> ensureResource(
    DynamicResourceSpec spec, {
    void Function(int received, int total)? onProgress,
  }) async {
    final ready = await localReadyFiles(spec);
    if (ready != null) {
      LoggerService.instance.i(
        '动态资源 ${spec.id} 已就绪(sha256 命中) version=${spec.version}',
        category: LogCategory.general,
        tags: ['resource', spec.id, 'hit'],
      );
      onProgress?.call(1, 1);
      return ready;
    }

    final dir = await resourceDir(spec.id);
    final totalBytes = spec.files.fold<int>(0, (a, f) => a + f.size);
    var doneBytes = 0;
    final paths = <String, String>{};

    for (final f in spec.files) {
      final dest = File('${dir.path}/${f.name}');
      await _downloadWithRetry(
        url: f.url,
        expectSha256: f.sha256,
        dest: dest,
        label: '${spec.id}/${f.name}',
        onProgress: (rec, _) => onProgress?.call(doneBytes + rec, totalBytes),
      );
      doneBytes += f.size;
      paths[f.name] = dest.path;
    }

    // meta（仅记录用途，校验以 sha256 为准）
    final meta = await _metaFile(spec.id);
    final tmp = File('${meta.path}.tmp');
    await tmp.writeAsString(json.encode({
      'version': spec.version,
      'downloadedAt': DateTime.now().toIso8601String(),
    }));
    await tmp.rename(meta.path);

    return paths;
  }

  /// 下载 + sha256 校验 + 原子替换（带重试）。
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
          '动态资源 $label 下载失败(尝试 $attempt/$_maxRetries): $e',
          category: LogCategory.general,
          tags: ['resource', 'download', 'retry'],
        );
        if (attempt < _maxRetries) await Future.delayed(retryDelay);
      }
    }
    throw StateError('动态资源 $label 下载失败(重试 $_maxRetries 次): $lastErr');
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

    final actual = await _sha256Of(tmp);
    if (actual != expectSha256) {
      await tmp.delete();
      throw StateError('SHA256 不一致: 期望 $expectSha256, 实际 $actual ($url)');
    }

    if (await dest.exists()) await dest.delete();
    await tmp.rename(dest.path);
  }

  // ---- sd_engine 专用 ----

  /// 确保 libsds.so 本地就绪并记录动态加载路径。
  /// 成功后 [sdLibraryPath] 非空，SdLibrary.open() 按绝对路径打开。
  Future<void> ensureSdEngine(DynamicResourceSpec spec,
      {void Function(int received, int total)? onProgress}) async {
    final paths = await ensureResource(spec, onProgress: onProgress);
    final so = paths.values
        .where((p) => p.endsWith('.so'))
        .toList(growable: false);
    if (so.isEmpty) {
      throw StateError('sd_engine 资源里没有 .so 文件');
    }
    sdLibraryPath = so.first;
    LoggerService.instance.i(
      'libsds.so 动态加载路径已注册: ${so.first}',
      category: LogCategory.general,
      tags: ['resource', ResourceIds.sdEngine, 'ready'],
    );
  }

  /// sd_engine 资源是否已下载就绪（不触发下载）。
  /// 用于启动时把缓存路径直接挂回 [sdLibraryPath]。
  Future<bool> tryRestoreSdEngine(DynamicResourceSpec spec) async {
    final paths = await localReadyFiles(spec);
    if (paths == null) return false;
    final so = paths.values
        .where((p) => p.endsWith('.so'))
        .toList(growable: false);
    if (so.isEmpty) return false;
    sdLibraryPath = so.first;
    return true;
  }

  // ---- ui_fonts 专用 ----

  /// 用 FontLoader 把下载的 ttf 注册进引擎（family 名与原打包字体一致，
  /// 主题/样式零改动）。必须在 UI 首帧后调用也安全——引擎热注册后自动重绘。
  ///
  /// 已注册过的 family 幂等跳过（FontLoader 重复 load 会抛重复注册）。
  Future<void> registerFonts(Map<String, String> nameToPath) async {
    // family → [(bytes, bold?)]，与 pubspec 原声明一致：
    // NotoSerifSC / NotoSansSC 各含 Regular + Bold(700)
    const families = <String, List<String>>{
      'NotoSerifSC': ['NotoSerifSC-Regular.ttf', 'NotoSerifSC-Bold.ttf'],
      'NotoSansSC': ['NotoSansSC-Regular.ttf', 'NotoSansSC-Bold.ttf'],
    };
    for (final entry in families.entries) {
      if (_registeredFamilies.contains(entry.key)) continue;
      final loader = FontLoader(entry.key);
      var added = 0;
      for (final fileName in entry.value) {
        final path = nameToPath[fileName];
        if (path == null) continue;
        final bytes = await File(path).readAsBytes();
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
        added++;
      }
      if (added == 0) continue;
      await loader.load();
      _registeredFamilies.add(entry.key);
      LoggerService.instance.i(
        '动态字体已注册 family=${entry.key} files=$added',
        category: LogCategory.general,
        tags: ['resource', ResourceIds.uiFonts, 'font-registered'],
      );
    }
  }

  static final Set<String> _registeredFamilies = {};

  // ---- 工具 ----
  Future<String> _sha256Of(File f) async {
    final bytes = await f.readAsBytes();
    return sha256.convert(bytes).toString();
  }
}
