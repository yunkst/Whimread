/// Local Dream 嵌入式引擎协议客户端
///
/// 对接本机引擎子进程（libstable_diffusion_core.so，监听 localhost:8081）
/// 暴露的 HTTP API：
/// - [LocalDreamPorts.generation]：/generate（SSE 流式，图片 base64）、/health
///
/// 协议参考 Local Dream `main.cpp`（端口为协议常量、SSE 事件格式）。
/// 无鉴权，端口固定。
///
/// HTTP 用 dart:io HttpClient 直连而非 Dio：本项目 Dio 实例挂了设备鉴权
/// 拦截器与后端超时语义，直连本机子进程不应经过它们（流式 SSE 同理，
/// 与 llm_provider_client.dart 的选择一致）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';

import '../logger_service.dart';

/// Local Dream 协议固定端口
class LocalDreamPorts {
  /// 生成端口（原生后端 --listen：/generate /health）
  static const int generation = 8081;
}

/// 生成请求参数（/generate 的 JSON body）
class LocalDreamGenerateRequest {
  final String prompt;
  final String negativePrompt;
  final int width;
  final int height;
  final int steps;
  final double cfg;
  final int? seed;

  /// 调度器（dpm/euler/euler_a/lcm/dpm_sde…，引擎默认 dpm）
  final String? scheduler;

  /// 画面比例预设（"1:1"/"3:4"/"4:3"/"16:9"…，仅 SDXL/Anima 生效）。
  /// 引擎在固定 1024 画布上按比例合成重绘后裁切；SD1.5 恒为原生 512。
  final String? aspectRatio;

  /// 逐步预览（开启后 progress 事件带 previewFormat 格式的中间图）
  final bool showDiffusionProcess;
  final String? previewFormat;

  const LocalDreamGenerateRequest({
    required this.prompt,
    this.negativePrompt = '',
    required this.width,
    required this.height,
    required this.steps,
    required this.cfg,
    this.seed,
    this.scheduler,
    this.aspectRatio,
    this.showDiffusionProcess = false,
    this.previewFormat,
  });

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        if (negativePrompt.isNotEmpty) 'negative_prompt': negativePrompt,
        'width': width,
        'height': height,
        'steps': steps,
        'cfg': cfg,
        if (seed != null) 'seed': seed,
        if (scheduler != null && scheduler!.isNotEmpty) 'scheduler': scheduler,
        if (aspectRatio != null && aspectRatio!.isNotEmpty)
          'aspect_ratio': aspectRatio,
        // 与 MediaStore 的 image 扩展名（png）对齐，结果 bytes 免二次编码
        'output_format': 'png',
        if (showDiffusionProcess) ...{
          'show_diffusion_process': true,
          // 预览图走 jpeg（体积小，逐帧传输）
          'preview_format': previewFormat ?? 'jpeg',
        },
      };
}

/// /generate SSE 流事件
sealed class LocalDreamGenerateEvent {
  const LocalDreamGenerateEvent();
}

/// 采样步进（step 从 1 计；开启逐步预览时携带中间图 base64）
class LocalDreamProgressEvent extends LocalDreamGenerateEvent {
  final int step;
  final int totalSteps;

  /// 中间预览图 bytes（showDiffusionProcess 时存在）
  final Uint8List? previewBytes;
  final String? previewFormat;

  const LocalDreamProgressEvent({
    required this.step,
    required this.totalSteps,
    this.previewBytes,
    this.previewFormat,
  });
}

/// 生成完成（图片 bytes 已按 format 解码）
class LocalDreamCompleteEvent extends LocalDreamGenerateEvent {
  final Uint8List bytes;
  final String format;
  final int seed;
  final int width;
  final int height;
  final int generationTimeMs;

  const LocalDreamCompleteEvent({
    required this.bytes,
    required this.format,
    required this.seed,
    required this.width,
    required this.height,
    required this.generationTimeMs,
  });
}

/// 设备侧生成失败
class LocalDreamErrorEvent extends LocalDreamGenerateEvent {
  final String message;

  const LocalDreamErrorEvent({required this.message});
}

/// 与本机引擎通信失败的异常（连接不上、协议不符、引擎报错等）
class LocalDreamException implements Exception {
  final String message;
  const LocalDreamException(this.message);

  @override
  String toString() => message;
}

class LocalDreamClient {
  /// 引擎监听地址（嵌入式引擎固定 127.0.0.1）
  final String host;

  final int generationPort;

  /// 默认单次 TCP 连接超时
  static const Duration defaultConnectTimeout = Duration(seconds: 10);

  /// 单次 TCP 连接超时
  final Duration connectTimeout;

  /// SSE 帧间空闲超时（采样一步可能 10s+，整图 1 分钟+，放宽到 2 分钟）
  static const Duration idleTimeout = Duration(seconds: 120);

  HttpClient? _httpClient;

  LocalDreamClient({
    required this.host,
    this.generationPort = LocalDreamPorts.generation,
    this.connectTimeout = defaultConnectTimeout,
  });

  HttpClient _http() {
    final client = _httpClient ??= HttpClient()
      ..connectionTimeout = connectTimeout;
    return client;
  }

  /// 释放底层连接池；调用后本实例不可再用
  void close() {
    _httpClient?.close();
    _httpClient = null;
  }

  Uri _generationUri(String path) =>
      Uri.parse('http://$host:$generationPort$path');

  /// 把底层连接异常统一映射为可读的 [LocalDreamException]。
  LocalDreamException _connectionError(Object e) {
    if (e is TimeoutException) {
      return LocalDreamException('连接本机引擎 $host 超时');
    }
    if (e is SocketException) {
      return LocalDreamException('无法连接本机引擎 $host（${e.message}）');
    }
    if (e is HttpException) {
      return LocalDreamException('连接本机引擎 $host 失败（${e.message}）');
    }
    return LocalDreamException('连接本机引擎 $host 失败：$e');
  }

  /// 响应体尽力排空（带读取超时）。
  ///
  /// 半死进程（TCP 已建连但不再发数据）的响应体可能永远读不完，
  /// 不加超时会让 [health] 轮询 / 非 200 分支永久挂起，
  /// 引擎管理器的启动 deadline 检查随之失效。
  Future<void> _drainQuietly(HttpClientResponse response) async {
    try {
      await response.drain<void>().timeout(idleTimeout);
    } on TimeoutException {
      // 放弃接收即可：连接随后被丢弃
    }
  }

  /// 生成端口健康检查（GET /health 返回 200 即就绪；
  /// 嵌入式引擎 manager 启动后轮询此方法等待模型加载完成）
  Future<bool> health() async {
    try {
      final request = await _http()
          .getUrl(_generationUri('/health'))
          .timeout(connectTimeout);
      final response = await request.close().timeout(connectTimeout);
      await _drainQuietly(response);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 提交生成并消费整个 SSE 流，返回 complete 事件。
  ///
  /// progress 钳制后透传给 [onProgress]（真实引擎会出现重复帧与
  /// step > total 的帧，归一化保证上层 step/total 恒在 0..1）；
  /// error 事件转为异常抛出。
  Future<LocalDreamCompleteEvent> generateAndWait(
    LocalDreamGenerateRequest request, {
    void Function(int step, int total)? onProgress,
  }) async {
    LocalDreamCompleteEvent? complete;
    await for (final event in generate(request)) {
      switch (event) {
        case LocalDreamProgressEvent(:final step, :final totalSteps):
          if (totalSteps > 0) {
            onProgress?.call(min(step, totalSteps), totalSteps);
          }
        case LocalDreamCompleteEvent():
          complete = event;
        case LocalDreamErrorEvent(:final message):
          throw LocalDreamException('引擎生成失败：$message');
      }
    }
    if (complete == null) {
      throw const LocalDreamException('引擎连接中断，未返回完整图片');
    }
    return complete;
  }

  /// 提交生成，流式返回 progress/complete/error 事件。
  ///
  /// SSE 帧格式（Local Dream main.cpp）：
  /// ```text
  /// event: progress
  /// data: {"type":"progress","step":1,"total_steps":20}
  /// ```
  Stream<LocalDreamGenerateEvent> generate(LocalDreamGenerateRequest request) {
    return _generateSse(request).transform(
      StreamTransformer<LocalDreamGenerateEvent,
          LocalDreamGenerateEvent>.fromHandlers(
        handleError: (error, stackTrace, sink) {
          if (error is LocalDreamException) {
            sink.addError(error);
            return;
          }
          if (error is TimeoutException) {
            sink.addError(LocalDreamException(
                '引擎 $host 生成响应中断（超过 ${idleTimeout.inSeconds}s 无数据）'));
            return;
          }
          sink.addError(
              LocalDreamException('与引擎 $host 通信失败：$error'));
        },
      ),
    );
  }

  Stream<LocalDreamGenerateEvent> _generateSse(
      LocalDreamGenerateRequest request) async* {
    HttpClientResponse response;
    try {
      // contentLength 显式设置走 Content-Length 而非 chunked 传输
      final body = utf8.encode(jsonEncode(request.toJson()));
      final httpRequest = await _http()
          .postUrl(_generationUri('/generate'))
          .timeout(connectTimeout);
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.contentLength = body.length;
      httpRequest.add(body);
      response = await httpRequest.close().timeout(connectTimeout);
    } catch (e) {
      throw _connectionError(e);
    }

    if (response.statusCode != 200) {
      await response.drain<void>();
      throw LocalDreamException(
          '引擎生成接口返回 HTTP ${response.statusCode}');
    }

    final parser = _SseParser();
    try {
      // utf8.decoder 增量解码：多字节字符被 TCP 分包切开时自动跨 chunk 续接
      await for (final text in response
          .transform(utf8.decoder)
          .timeout(idleTimeout)) {
        for (final event in parser.feed(text)) {
          yield event;
        }
      }
    } on StateError catch (e) {
      // _SseParser 在流意外结束时抛 StateError，转成可读文案
      throw LocalDreamException(
          e.message.isEmpty ? '引擎连接中断' : e.message);
    }

    for (final event in parser.flush()) {
      yield event;
    }
  }
}

/// Local Dream SSE 帧解析器（`event:` + `data:` 成对出现，空行分隔帧）
class _SseParser {
  String _buffer = '';
  String _eventName = '';
  String _data = '';

  /// 喂入一段文本，返回由此凑齐的完整事件
  List<LocalDreamGenerateEvent> feed(String text) {
    _buffer += text;
    final events = <LocalDreamGenerateEvent>[];
    int newline;
    while ((newline = _buffer.indexOf('\n')) >= 0) {
      final line = _buffer.substring(0, newline);
      _buffer = _buffer.substring(newline + 1);
      final event = _consumeLine(line.trim());
      if (event != null) events.add(event);
    }
    return events;
  }

  /// 流结束时调用；理论上 Local Dream 每帧都以空行收尾，这里兜底
  List<LocalDreamGenerateEvent> flush() {
    final event = _consumeLine(_buffer.trim(), forceDispatch: true);
    _buffer = '';
    return event == null ? const [] : [event];
  }

  /// 处理一行；空行表示一帧结束，凑齐 event+data 则解析分发
  LocalDreamGenerateEvent? _consumeLine(String line,
      {bool forceDispatch = false}) {
    if (line.isEmpty) {
      final event = _build();
      _eventName = '';
      _data = '';
      return event;
    }
    if (line.startsWith('event:')) {
      _eventName = line.substring(6).trim();
      return null;
    }
    if (line.startsWith('data:')) {
      _data = line.substring(5).trim();
      if (forceDispatch) return _build();
      return null;
    }
    // 忽略注释（: keep-alive 等）与未知行
    return null;
  }

  LocalDreamGenerateEvent? _build() {
    if (_eventName.isEmpty || _data.isEmpty) return null;
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(_data) as Map<String, dynamic>;
    } on FormatException {
      LoggerService.instance.w('Local Dream SSE data 解析失败: $_data',
          category: LogCategory.ai, tags: ['image_gen', 'local_dream']);
      return null;
    }
    switch (_eventName) {
      case 'progress':
        final preview = json['image'] as String?;
        return LocalDreamProgressEvent(
          step: (json['step'] as num?)?.toInt() ?? 0,
          totalSteps: (json['total_steps'] as num?)?.toInt() ?? 0,
          previewBytes:
              (preview != null && preview.isNotEmpty) ? base64Decode(preview) : null,
          previewFormat: json['format'] as String?,
        );
      case 'complete':
        final image = json['image'] as String?;
        if (image == null || image.isEmpty) {
          return const LocalDreamErrorEvent(message: '设备未返回图片数据');
        }
        try {
          return LocalDreamCompleteEvent(
            bytes: base64Decode(image),
            format: (json['format'] as String?) ?? 'png',
            seed: (json['seed'] as num?)?.toInt() ?? 0,
            width: (json['width'] as num?)?.toInt() ?? 0,
            height: (json['height'] as num?)?.toInt() ?? 0,
            generationTimeMs: (json['generation_time_ms'] as num?)?.toInt() ?? 0,
          );
        } on FormatException {
          return const LocalDreamErrorEvent(message: '设备返回的图片数据解码失败');
        }
      case 'error':
        return LocalDreamErrorEvent(
            message: (json['message'] as String?) ?? '设备生成失败');
      default:
        return null;
    }
  }
}
