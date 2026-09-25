/// Local Dream 设备协议客户端
///
/// 对接 Local Dream 安卓端"宿主模式"（设备互联）暴露的 HTTP API：
/// - 控制端口 [LocalDreamPorts.control]：/info /status /models /select
/// - 生成端口 [LocalDreamPorts.generation]：/generate（SSE 流式，图片 base64）
///
/// 协议参考 local-dream 仓库 `RemoteProtocol.kt`（端口为协议常量）与
/// `main.cpp`（SSE 事件格式）。两端均无鉴权，端口仅由 host 推导。
///
/// HTTP 用 dart:io HttpClient 直连而非 Dio：本项目 Dio 实例挂了设备鉴权
/// 拦截器与后端超时语义，直连局域网设备不应经过它们（流式 SSE 同理，
/// 与 llm_provider_client.dart 的选择一致）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../logger_service.dart';

/// Local Dream 协议固定端口
class LocalDreamPorts {
  /// 控制端口（RemoteHostServer：/info /status /models /select）
  static const int control = 8808;

  /// 生成端口（原生后端 --listen_all：/generate /health）
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

  const LocalDreamGenerateRequest({
    required this.prompt,
    this.negativePrompt = '',
    required this.width,
    required this.height,
    required this.steps,
    required this.cfg,
    this.seed,
  });

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        if (negativePrompt.isNotEmpty) 'negative_prompt': negativePrompt,
        'width': width,
        'height': height,
        'steps': steps,
        'cfg': cfg,
        if (seed != null) 'seed': seed,
        // 与 MediaStore 的 image 扩展名（png）对齐，结果 bytes 免二次编码
        'output_format': 'png',
      };
}

/// GET /info：设备身份
class LocalDreamInfo {
  final String app;
  final int protocol;
  final String version;
  final String device;

  const LocalDreamInfo({
    required this.app,
    required this.protocol,
    required this.version,
    required this.device,
  });

  factory LocalDreamInfo.fromJson(Map<String, dynamic> json) => LocalDreamInfo(
        app: (json['app'] as String?) ?? '',
        protocol: (json['protocol'] as num?)?.toInt() ?? 0,
        version: (json['version'] as String?) ?? '',
        device: (json['device'] as String?) ?? '',
      );
}

/// GET /status：后端状态（idle/starting/running/error）
class LocalDreamStatus {
  final String state;
  final String? servingModelId;
  final String? message;

  const LocalDreamStatus({
    required this.state,
    this.servingModelId,
    this.message,
  });

  factory LocalDreamStatus.fromJson(Map<String, dynamic> json) =>
      LocalDreamStatus(
        state: (json['state'] as String?) ?? 'idle',
        servingModelId: json['serving_model_id'] as String?,
        message: json['message'] as String?,
      );
}

/// GET /models：设备上已安装的一个模型
class LocalDreamCatalogModel {
  final String id;
  final String name;
  final String description;
  final bool isSdxl;
  final int generationSize;
  final int defaultSteps;
  final double defaultCfg;
  final String defaultNegativePrompt;

  const LocalDreamCatalogModel({
    required this.id,
    required this.name,
    required this.description,
    required this.isSdxl,
    required this.generationSize,
    required this.defaultSteps,
    required this.defaultCfg,
    required this.defaultNegativePrompt,
  });

  factory LocalDreamCatalogModel.fromJson(Map<String, dynamic> json) {
    final defaults = (json['defaults'] as Map<String, dynamic>?) ?? const {};
    return LocalDreamCatalogModel(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      isSdxl: (json['is_sdxl'] as bool?) ?? false,
      generationSize: (json['generation_size'] as num?)?.toInt() ?? 512,
      defaultSteps: (defaults['steps'] as num?)?.toInt() ?? 20,
      defaultCfg: (defaults['cfg'] as num?)?.toDouble() ?? 7.0,
      defaultNegativePrompt: (defaults['negative_prompt'] as String?) ?? '',
    );
  }
}

/// /generate SSE 流事件
sealed class LocalDreamGenerateEvent {
  const LocalDreamGenerateEvent();
}

/// 采样步进（step 从 1 计）
class LocalDreamProgressEvent extends LocalDreamGenerateEvent {
  final int step;
  final int totalSteps;

  const LocalDreamProgressEvent({required this.step, required this.totalSteps});
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

/// 与 Local Dream 设备通信失败的异常（连接不上、协议不符、设备报错等）
class LocalDreamException implements Exception {
  final String message;
  const LocalDreamException(this.message);

  @override
  String toString() => message;
}

class LocalDreamClient {
  /// 设备地址（已规范化，不含 scheme 与端口）
  final String host;

  final int controlPort;
  final int generationPort;

  /// 单次 TCP 连接超时
  static const Duration connectTimeout = Duration(seconds: 10);

  /// SSE 帧间空闲超时（采样一步可能 10s+，整图 1 分钟+，放宽到 2 分钟）
  static const Duration idleTimeout = Duration(seconds: 120);

  /// /select 后等待后端进入 running 的上限
  static const Duration selectSettleTimeout = Duration(seconds: 90);

  /// 轮询 /status 的间隔（测试注入短间隔加速）
  Duration selectPollInterval = const Duration(seconds: 1);

  HttpClient? _httpClient;

  LocalDreamClient({
    required this.host,
    this.controlPort = LocalDreamPorts.control,
    this.generationPort = LocalDreamPorts.generation,
  });

  /// 规范化用户输入的设备地址：去 scheme/路径/端口/空白。
  /// 端口是协议常量，用户多填（如 `192.168.31.76:8808`）也一并剥掉。
  /// 注：按首个 ':' 截断端口，不支持 IPv6 字面量（局域网直连场景为 IPv4）。
  static String normalizeHost(String raw) {
    var host = raw.trim();
    final scheme = host.indexOf('://');
    if (scheme >= 0) host = host.substring(scheme + 3);
    final slash = host.indexOf('/');
    if (slash >= 0) host = host.substring(0, slash);
    final colon = host.indexOf(':');
    if (colon >= 0) host = host.substring(0, colon);
    return host.trim();
  }

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

  Uri _controlUri(String path) =>
      Uri.parse('http://$host:$controlPort$path');

  Uri _generationUri(String path) =>
      Uri.parse('http://$host:$generationPort$path');

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final body = await _requestJson(() async {
      final request = await _http().getUrl(uri);
      return request.close();
    }, uri);
    return body;
  }

  Future<Map<String, dynamic>> _postJson(Uri uri, Map<String, dynamic> json) {
    return _requestJson(() async {
      final request = await _http().postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(json));
      return request.close();
    }, uri);
  }

  Future<Map<String, dynamic>> _requestJson(
    Future<HttpClientResponse> Function() open,
    Uri uri,
  ) async {
    HttpClientResponse response;
    try {
      response = await open().timeout(connectTimeout);
    } on TimeoutException {
      throw LocalDreamException('连接设备 $host 超时，请确认在同一网络、'
          '宿主模式已开启且手机屏幕未锁定');
    } on SocketException catch (e) {
      throw LocalDreamException('无法连接设备 $host（${e.message}），'
          '请确认在同一网络、宿主模式已开启且手机屏幕未锁定');
    } on HttpException catch (e) {
      throw LocalDreamException('连接设备 $host 失败（${e.message}）');
    }
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw LocalDreamException('设备 $host 返回 HTTP ${response.statusCode}');
    }
    final text = await response.transform(utf8.decoder).join();
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } on FormatException {
      throw LocalDreamException('设备 $host 返回了非 JSON 响应');
    }
  }

  /// 设备身份（校验 app == localdream）
  Future<LocalDreamInfo> info() async {
    final json = await _getJson(_controlUri('/info'));
    return LocalDreamInfo.fromJson(json);
  }

  /// 后端状态
  Future<LocalDreamStatus> status() async {
    final json = await _getJson(_controlUri('/status'));
    return LocalDreamStatus.fromJson(json);
  }

  /// 设备上已安装的模型目录
  Future<List<LocalDreamCatalogModel>> models() async {
    final json = await _getJson(_controlUri('/models'));
    final list = (json['models'] as List<dynamic>?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(LocalDreamCatalogModel.fromJson)
        .toList();
  }

  /// 远程激活模型并等待后端进入 running。
  /// 设备已在跑其他模型时会被切换；已在跑目标模型时跳过重复 select。
  Future<void> select(
    String modelId, {
    int width = 512,
    int height = 512,
  }) async {
    final current = await status();
    if (current.state == 'running' && current.servingModelId == modelId) {
      return;
    }
    LoggerService.instance.i('远程激活 Local Dream 模型: $modelId @ $host',
        category: LogCategory.ai, tags: ['image_gen', 'local_dream']);
    await _postJson(
        _controlUri('/select'), {'model_id': modelId, 'width': width, 'height': height});

    final deadline = DateTime.now().add(selectSettleTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(selectPollInterval);
      final current = await status();
      if (current.state == 'running' && current.servingModelId == modelId) {
        return;
      }
      if (current.state == 'error') {
        throw LocalDreamException(
            '设备激活模型 $modelId 失败：${current.message ?? '未知错误'}');
      }
    }
    throw LocalDreamException('等待设备加载模型 $modelId 超时');
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
                '设备 $host 生成响应中断（超过 ${idleTimeout.inSeconds}s 无数据）'));
            return;
          }
          sink.addError(
              LocalDreamException('与设备 $host 通信失败：$error'));
        },
      ),
    );
  }

  Stream<LocalDreamGenerateEvent> _generateSse(
      LocalDreamGenerateRequest request) async* {
    HttpClientResponse response;
    try {
      final httpRequest = await _http()
          .postUrl(_generationUri('/generate'))
          .timeout(connectTimeout);
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.write(jsonEncode(request.toJson()));
      response = await httpRequest.close().timeout(connectTimeout);
    } on TimeoutException {
      throw LocalDreamException('连接设备 $host 超时，请确认在同一网络、'
          '宿主模式已开启且手机屏幕未锁定');
    } on SocketException catch (e) {
      throw LocalDreamException('无法连接设备 $host（${e.message}），'
          '请确认设备模型已在手机端启动（宿主模式）且屏幕未锁定');
    }

    if (response.statusCode != 200) {
      await response.drain<void>();
      throw LocalDreamException(
          '设备生成接口返回 HTTP ${response.statusCode}，请确认模型已激活');
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
          e.message.isEmpty ? '设备连接中断' : e.message);
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
        return LocalDreamProgressEvent(
          step: (json['step'] as num?)?.toInt() ?? 0,
          totalSteps: (json['total_steps'] as num?)?.toInt() ?? 0,
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
