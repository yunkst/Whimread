/// LocalDreamClient 单元测试
///
/// 用进程内 HttpServer 伪造嵌入式引擎的生成端口（/generate SSE），覆盖：
/// - generate SSE：跨 chunk 帧解析、progress/complete/error 三类事件
/// - generateAndWait：progress 钳制透传、error 事件转异常
/// - 连接失败映射为 LocalDreamException
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/image_generation/local_dream_client.dart';

void main() {
  group('协议交互（fake HttpServer）', () {
    late HttpServer generationServer;
    final generateBodies = <Map<String, dynamic>>[];

    setUp(() async {
      generateBodies.clear();

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
      await generationServer.close(force: true);
    });

    LocalDreamClient client() => LocalDreamClient(
          host: '127.0.0.1',
          generationPort: generationServer.port,
        );

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

    test('generateAndWait：progress 钳制透传并返回 complete', () async {
      final steps = <int>[];
      final complete = await client().generateAndWait(
        const LocalDreamGenerateRequest(
            prompt: 'cat', width: 8, height: 8, steps: 2, cfg: 7, seed: 42),
        onProgress: (step, total) => steps.add(step),
      );
      expect(steps, [1, 2]);
      expect(complete.seed, 42);
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
        generationPort: errorServer.port,
      )
          .generate(const LocalDreamGenerateRequest(
              prompt: 'cat', width: 8, height: 8, steps: 2, cfg: 7))
          .toList();

      expect(events.whereType<LocalDreamProgressEvent>(), hasLength(1));
      expect(events.whereType<LocalDreamErrorEvent>().single.message, 'boom');
    });

    test('generateAndWait：error 事件转为异常抛出', () async {
      await generationServer.close(force: true);
      final errorServer = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => errorServer.close(force: true));
      errorServer.listen((request) async {
        await utf8.decoder.bind(request).join();
        final response = request.response;
        response.add(utf8.encode('event: error\n'
            'data: {"type":"error","message":"boom"}\n\n'));
        await response.close();
      });

      await expectLater(
        LocalDreamClient(
          host: '127.0.0.1',
          generationPort: errorServer.port,
        ).generateAndWait(const LocalDreamGenerateRequest(
            prompt: 'cat', width: 8, height: 8, steps: 2, cfg: 7)),
        throwsA(isA<LocalDreamException>().having(
            (e) => e.message, 'message', contains('boom'))),
      );
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
