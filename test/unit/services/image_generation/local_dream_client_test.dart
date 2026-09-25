/// LocalDreamClient 单元测试
///
/// 用进程内 HttpServer 伪造 Local Dream 的控制端口（/info /status /models
/// /select）与生成端口（/generate SSE），覆盖：
/// - host 规范化（剥 scheme/路径/端口）
/// - info / models / status JSON 解析
/// - select：idle → select → 轮询至 running；已在跑目标模型时跳过
/// - generate SSE：跨 chunk 帧解析、progress/complete/error 三类事件
/// - 连接失败映射为 LocalDreamException
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/image_generation/local_dream_client.dart';

void main() {
  group('normalizeHost', () {
    test('纯 IP 原样保留', () {
      expect(LocalDreamClient.normalizeHost('192.168.31.76'),
          '192.168.31.76');
    });

    test('剥 scheme / 端口 / 路径 / 空白', () {
      expect(LocalDreamClient.normalizeHost('http://192.168.31.76'),
          '192.168.31.76');
      expect(LocalDreamClient.normalizeHost('https://192.168.31.76:8808/'),
          '192.168.31.76');
      expect(LocalDreamClient.normalizeHost('  http://192.168.31.76/path '),
          '192.168.31.76');
      expect(LocalDreamClient.normalizeHost('192.168.31.76:8081'),
          '192.168.31.76');
    });

    test('空输入', () {
      expect(LocalDreamClient.normalizeHost(''), '');
      expect(LocalDreamClient.normalizeHost('   '), '');
    });
  });

  group('协议交互（fake HttpServer）', () {
    late HttpServer controlServer;
    late HttpServer generationServer;

    /// /status 响应队列：非空时逐个弹出，空了重复最后一个
    final statusQueue = <Map<String, dynamic>>[];
    final selectBodies = <Map<String, dynamic>>[];
    final generateBodies = <Map<String, dynamic>>[];

    /// /select 请求的传输元数据（transfer-encoding / content-length），
    /// 用于固化「禁止 chunked」契约
    final requestMetadata = <Map<String, String?>>[];

    setUp(() async {
      statusQueue.clear();
      selectBodies.clear();
      generateBodies.clear();
      requestMetadata.clear();

      controlServer = await HttpServer.bind('127.0.0.1', 0);
      controlServer.listen((request) async {
        final path = request.uri.path;
        if (path == '/info') {
          await _writeJson(request, {
            'app': 'localdream',
            'protocol': 1,
            'version': '2.8.1',
            'device': 'V2454DA',
          });
        } else if (path == '/status') {
          await _writeJson(
              request,
              statusQueue.isNotEmpty
                  ? statusQueue.removeAt(0)
                  : {
                      'serving_model_id': 'illustrious_v16',
                      'state': 'running',
                    });
        } else if (path == '/models') {
          await _writeJson(request, {
            'models': [
              {
                'id': 'illustrious_v16',
                'name': 'Illustrious v16',
                'description': 'WAI Illustrious SDXL v16',
                'is_sdxl': true,
                'generation_size': 1024,
                'defaults': {
                  'steps': 20,
                  'cfg': 7,
                  'negative_prompt': 'lowres',
                },
              },
            ],
          });
        } else if (path == '/select') {
          requestMetadata.add({
            'transferEncoding': request.headers.value('transfer-encoding'),
            'contentLength': request.headers.value('content-length'),
          });
          // 模拟真机行为（反馈 #6 根因）：设备端解析不了 chunked body，
          // 拿不到 model_id 时回 404 "model not found"。客户端必须显式
          // 设置 contentLength 走 Content-Length，禁止 chunked 传输。
          final transferEncoding = request.headers.value('transfer-encoding');
          if (transferEncoding != null &&
              transferEncoding.toLowerCase() == 'chunked') {
            await _writeJson(request, {'error': 'model not found'},
                status: 404);
            return;
          }
          final body = await utf8.decoder.bind(request).join();
          selectBodies
              .add(jsonDecode(body) as Map<String, dynamic>);
          await _writeJson(request, {'ok': true});
        } else {
          await _writeJson(request, {'error': 'not found'},
              status: 404);
        }
      });

      generationServer = await HttpServer.bind('127.0.0.1', 0);
      generationServer.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        generateBodies.add(jsonDecode(body) as Map<String, dynamic>);
        final response = request.response
          ..headers.contentType =
              ContentType('text', 'event-stream', charset: 'utf-8');
        // 故意把 SSE 文本按任意字节边界切片，验证跨 chunk 帧解析
        final sse = _testSse();
        for (final piece in _splitUtf8Randomly(sse)) {
          response.add(piece);
          await response.flush();
        }
        await response.close();
      });
    });

    tearDown(() async {
      await controlServer.close(force: true);
      await generationServer.close(force: true);
    });

    LocalDreamClient client() => LocalDreamClient(
          host: '127.0.0.1',
          controlPort: controlServer.port,
          generationPort: generationServer.port,
        )..selectPollInterval = const Duration(milliseconds: 5);

    test('info 解析设备身份', () async {
      final info = await client().info();
      expect(info.app, 'localdream');
      expect(info.version, '2.8.1');
      expect(info.device, 'V2454DA');
    });

    test('models 解析目录与默认参数', () async {
      final models = await client().models();
      expect(models, hasLength(1));
      expect(models.single.id, 'illustrious_v16');
      expect(models.single.isSdxl, isTrue);
      expect(models.single.generationSize, 1024);
      expect(models.single.defaultSteps, 20);
      expect(models.single.defaultCfg, 7.0);
      expect(models.single.defaultNegativePrompt, 'lowres');
    });

    test('select：idle 时激活并轮询至 running', () async {
      statusQueue.addAll([
        {'serving_model_id': null, 'state': 'idle'},
        {'serving_model_id': 'illustrious_v16', 'state': 'starting'},
        {'serving_model_id': 'illustrious_v16', 'state': 'running'},
      ]);
      await client().select('illustrious_v16', width: 1024, height: 1024);
      expect(selectBodies, hasLength(1));
      expect(selectBodies.single['model_id'], 'illustrious_v16');
      expect(selectBodies.single['width'], 1024);
      // 反馈 #6 契约：POST 必须带 Content-Length，禁止 chunked
      // （设备端解析不了 chunked body，会回 404 "model not found"）
      expect(requestMetadata, isNotEmpty);
      expect(requestMetadata.last['transferEncoding'], isNull);
      expect(int.parse(requestMetadata.last['contentLength']!),
          greaterThan(0));
    });

    test('select：已在跑目标模型时跳过重复激活', () async {
      await client().select('illustrious_v16');
      expect(selectBodies, isEmpty);
    });

    test('select：设备报 error 状态时抛异常', () async {
      statusQueue.addAll([
        {'serving_model_id': null, 'state': 'idle'},
        {
          'serving_model_id': 'illustrious_v16',
          'state': 'error',
          'message': 'model load failed',
        },
      ]);
      await expectLater(
        client().select('illustrious_v16'),
        throwsA(isA<LocalDreamException>().having(
            (e) => e.message, 'message', contains('model load failed'))),
      );
    });

    test('generate：跨 chunk 解析 progress 与 complete', () async {
      final events = await client()
          .generate(const LocalDreamGenerateRequest(
        prompt: 'cat',
        negativePrompt: 'lowres',
        width: 8,
        height: 8,
        steps: 2,
        cfg: 7,
        seed: 42,
      ))
          .toList();

      final progress = events.whereType<LocalDreamProgressEvent>().toList();
      final complete = events.whereType<LocalDreamCompleteEvent>().toList();
      expect(progress.map((e) => e.step), [1, 2]);
      expect(progress.every((e) => e.totalSteps == 2), isTrue);
      expect(complete, hasLength(1));
      expect(complete.single.bytes, Uint8List.fromList([1, 2, 3, 4]));
      expect(complete.single.format, 'png');
      expect(complete.single.seed, 42);
      expect(complete.single.width, 8);
      expect(complete.single.height, 8);
      // 请求体：png 输出 + 参数透传
      expect(generateBodies.single['output_format'], 'png');
      expect(generateBodies.single['seed'], 42);
      expect(generateBodies.single['negative_prompt'], 'lowres');
    });

    test('generate：error 事件映射为 LocalDreamErrorEvent', () async {
      // 覆写生成端口响应为错误流
      await generationServer.close(force: true);
      final errorServer = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => errorServer.close(force: true));
      errorServer.listen((request) async {
        await utf8.decoder.bind(request).join();
        final response = request.response;
        response.add(utf8.encode('event: progress\n'
            'data: {"type":"progress","step":1,"total_steps":2}\n\n'
            'event: error\n'
            'data: {"type":"error","message":"boom"}\n\n'));
        await response.close();
      });

      final events = await LocalDreamClient(
        host: '127.0.0.1',
        controlPort: controlServer.port,
        generationPort: errorServer.port,
      )
          .generate(const LocalDreamGenerateRequest(
              prompt: 'cat', width: 8, height: 8, steps: 2, cfg: 7))
          .toList();

      expect(events.whereType<LocalDreamProgressEvent>(), hasLength(1));
      expect(events.whereType<LocalDreamErrorEvent>().single.message, 'boom');
    });

    test('generate：连接失败时抛 LocalDreamException', () async {
      // 绑定后立即关闭拿一个确定空闲的端口。注意：本机若有代理工具劫持
      // 回环连接，会表现为 HTTP 502；正常环境表现为连接拒绝。两种网络
      // 失败都必须收敛为带可读文案的 LocalDreamException。
      final socket = await ServerSocket.bind('127.0.0.1', 0);
      final closedPort = socket.port;
      await socket.close();

      final closedClient = LocalDreamClient(
        host: '127.0.0.1',
        controlPort: closedPort,
        generationPort: closedPort,
      );
      await expectLater(
        closedClient.generate(const LocalDreamGenerateRequest(
            prompt: 'cat', width: 8, height: 8, steps: 2, cfg: 7)).drain(),
        throwsA(isA<LocalDreamException>().having(
            (e) => e.message, 'message', isNotEmpty)),
      );
    });
  });

  group('isLocalDreamDevice 本机探测', () {
    test('/info 返回 localdream 时判定为 true', () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) async {
        await _writeJson(request, {
          'app': 'localdream',
          'protocol': 1,
          'version': '2.8.1',
          'device': 'V2454DA',
        });
      });
      addTearDown(server.close);

      expect(
        await LocalDreamClient.isLocalDreamDevice(
          '127.0.0.1',
          timeout: const Duration(seconds: 2),
          controlPort: server.port,
        ),
        isTrue,
      );
    });

    test('端口无人监听（连接拒绝）判定为 false 而非抛异常', () async {
      // 绑定后立刻释放，拿到一个大概率空闲的端口号
      final server = await HttpServer.bind('127.0.0.1', 0);
      final deadPort = server.port;
      await server.close();

      expect(
        await LocalDreamClient.isLocalDreamDevice(
          '127.0.0.1',
          timeout: const Duration(seconds: 2),
          controlPort: deadPort,
        ),
        isFalse,
      );
    });

    test('占用端口的服务不是 localdream 时判定为 false', () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) async {
        await _writeJson(request, {'app': 'other_app'});
      });
      addTearDown(server.close);

      expect(
        await LocalDreamClient.isLocalDreamDevice(
          '127.0.0.1',
          timeout: const Duration(seconds: 2),
          controlPort: server.port,
        ),
        isFalse,
      );
    });
  });
}

/// 测试用 SSE 流：2 个 progress + 1 个 complete（图片 bytes=[1,2,3,4]）
String _testSse() {
  final b64 = base64Encode([1, 2, 3, 4]);
  return 'event: progress\n'
      'data: {"type":"progress","step":1,"total_steps":2}\n\n'
      'event: progress\n'
      'data: {"type":"progress","step":2,"total_steps":2}\n\n'
      'event: complete\n'
      'data: {"type":"complete","image":"$b64","format":"png",'
      '"seed":42,"width":8,"height":8,"channels":3,'
      '"generation_time_ms":100}\n\n';
}

/// 把 UTF-8 文本按不定长字节切片（含把多字节字符切开的情况）
List<Uint8List> _splitUtf8Randomly(String text) {
  final bytes = utf8.encode(text);
  final pieces = <Uint8List>[];
  var i = 0;
  var step = 3;
  while (i < bytes.length) {
    final end = (i + step).clamp(i + 1, bytes.length);
    pieces.add(Uint8List.fromList(bytes.sublist(i, end)));
    i = end;
    step = step == 3 ? 7 : 3;
  }
  return pieces;
}

Future<void> _writeJson(HttpRequest request, Map<String, dynamic> json,
    {int status = 200}) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(json));
  await request.response.close();
}
