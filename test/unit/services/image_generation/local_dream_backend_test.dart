/// LocalDreamBackend 单元测试
///
/// 用进程内 HttpServer 伪造设备两端口（通过 clientFactory 注入端口），
/// MediaProxy 用内存 SQLite + 临时目录（FakePathProviderPlatform），覆盖：
/// - validate：设备可达且模型已装 → null；未装 → 错误文案；不可达 → 可读错误
/// - submit：idle → 自动 select → 逐张生成 → MediaProxy 落库
/// - count>1：seed 递增、请求体参数（png 输出/负向词/模型默认参数）正确
/// - 设备 error 事件 → 抛 LocalDreamException
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/models/image_model.dart';
import 'package:novel_app/services/api_service_wrapper.dart';
import 'package:novel_app/services/image_generation/image_generation_backend.dart';
import 'package:novel_app/services/image_generation/local_dream_backend.dart';
import 'package:novel_app/services/image_generation/local_dream_client.dart';
import 'package:novel_app/services/media/media_proxy.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../helpers/path_provider_fake.dart';
import '../../../helpers/test_database_setup.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late HttpServer controlServer;
  late HttpServer generationServer;
  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;

  final statusQueue = <Map<String, dynamic>>[];
  final selectBodies = <Map<String, dynamic>>[];
  final generateBodies = <Map<String, dynamic>>[];

  /// 生成端口 SSE 响应（默认 complete；测试可替换为 error 流）
  String generationSse =
      'event: progress\ndata: {"type":"progress","step":1,"total_steps":2}\n\n'
      'event: complete\ndata: {"type":"complete","image":"${base64Encode([9, 8, 7])}",'
      '"format":"png","seed":1,"width":8,"height":8,'
      '"generation_time_ms":50}\n\n';

  setUp(() async {
    statusQueue.clear();
    selectBodies.clear();
    generateBodies.clear();
    generationSse =
        'event: progress\ndata: {"type":"progress","step":1,"total_steps":2}\n\n'
        'event: complete\ndata: {"type":"complete","image":"${base64Encode([9, 8, 7])}",'
        '"format":"png","seed":1,"width":8,"height":8,'
        '"generation_time_ms":50}\n\n';

    tempDir = await Directory.systemTemp.createTemp('local_dream_backend');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);

    controlServer = await HttpServer.bind('127.0.0.1', 0);
    controlServer.listen((request) async {
      final path = request.uri.path;
      if (path == '/info') {
        await _writeJson(request, {'app': 'localdream', 'version': '2.8.1'});
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
            {'id': 'illustrious_v16', 'name': 'Illustrious v16'},
            {'id': 'other_model', 'name': 'Other'},
          ],
        });
      } else if (path == '/select') {
        final body = await utf8.decoder.bind(request).join();
        selectBodies.add(jsonDecode(body) as Map<String, dynamic>);
        await _writeJson(request, {'ok': true});
      } else {
        await _writeJson(request, {'error': 'not found'}, status: 404);
      }
    });

    generationServer = await HttpServer.bind('127.0.0.1', 0);
    generationServer.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      generateBodies.add(jsonDecode(body) as Map<String, dynamic>);
      final response = request.response;
      response.add(utf8.encode(generationSse));
      await response.close();
    });
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPathProvider;
    await controlServer.close(force: true);
    await generationServer.close(force: true);
    await tempDir.delete(recursive: true);
  });

  LocalDreamBackend backend(DatabaseConnection dbConn) => LocalDreamBackend(
        mediaProxy:
            MediaProxy(dbConn: dbConn, api: ApiServiceWrapper()),
        clientFactory: (host) => LocalDreamClient(
          host: LocalDreamClient.normalizeHost(host),
          controlPort: controlServer.port,
          generationPort: generationServer.port,
        )..selectPollInterval = const Duration(milliseconds: 5),
      );

  ImageModel model() => ImageModel(
        name: '手机 SDXL',
        backendType: ImageModelBackendType.localDream,
        remoteHost: '127.0.0.1',
        remoteModelId: 'illustrious_v16',
        defaultWidth: 8,
        defaultHeight: 8,
        defaultSteps: 2,
        defaultCfg: 7.0,
        negativePrompt: 'lowres',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  test('id / supports：local_dream 路由正确', () async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    addTearDown(db.close);
    final b = backend(DatabaseConnection.forTesting(db));
    expect(b.id, 'local_dream');
    expect(b.supports(ImageModelBackendType.localDream), isTrue);
    expect(b.supports(ImageModelBackendType.localSd), isFalse);
  });

  test('validate：设备可达且模型已装 → null', () async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    addTearDown(db.close);
    final result = await backend(DatabaseConnection.forTesting(db))
        .validate(model());
    expect(result, isNull);
  });

  test('validate：设备未装该模型 → 错误文案', () async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    addTearDown(db.close);
    final result = await backend(DatabaseConnection.forTesting(db))
        .validate(model().copyWith(remoteModelId: 'missing_model'));
    expect(result, contains('missing_model'));
    expect(result, contains('未安装'));
  });

  test('validate：设备不可达 → 可读错误', () async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    addTearDown(db.close);
    // 绑定后立即关闭拿一个确定空闲的端口
    final socket = await ServerSocket.bind('127.0.0.1', 0);
    final closedPort = socket.port;
    await socket.close();
    final b = LocalDreamBackend(
      mediaProxy: MediaProxy(
          dbConn: DatabaseConnection.forTesting(db),
          api: ApiServiceWrapper()),
      // 强制指向空闲端口：本机有代理工具劫持回环连接时表现为 HTTP 502，
      // 正常环境表现为连接拒绝，两种失败都必须映射为非 null 的可读文案
      clientFactory: (host) => LocalDreamClient(
        host: LocalDreamClient.normalizeHost(host),
        controlPort: closedPort,
        generationPort: closedPort,
      ),
    );
    final result = await b.validate(model());
    expect(result, isNotNull);
    expect(result, contains('127.0.0.1'));
  });

  test('validate：未配置 host / model id → 提示配置', () async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    addTearDown(db.close);
    final result = await backend(DatabaseConnection.forTesting(db))
        .validate(model().copyWith(remoteHost: '', remoteModelId: ''));
    expect(result, contains('未配置'));
  });

  test('submit：idle → 自动 select → count 张全部落库，seed 递增', () async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    addTearDown(db.close);
    final dbConn = DatabaseConnection.forTesting(db);
    statusQueue.addAll([
      {'serving_model_id': null, 'state': 'idle'},
      {'serving_model_id': 'illustrious_v16', 'state': 'starting'},
      {'serving_model_id': 'illustrious_v16', 'state': 'running'},
    ]);

    final steps = <int>[];
    final result = await backend(dbConn).submit(
      ImageGenerationRequest(
        model: model(),
        prompt: 'cat',
        count: 2,
        seed: 100,
      ),
      onProgress: (step, total) => steps.add(step),
    );

    // 自动激活了模型，且带上了出图尺寸
    expect(selectBodies, hasLength(1));
    expect(selectBodies.single['model_id'], 'illustrious_v16');
    expect(selectBodies.single['width'], 8);
    expect(selectBodies.single['height'], 8);

    // 两次生成请求：seed 递增、负向词取模型预设、png 输出
    expect(generateBodies, hasLength(2));
    expect(generateBodies[0]['seed'], 100);
    expect(generateBodies[1]['seed'], 101);
    expect(generateBodies[0]['negative_prompt'], 'lowres');
    expect(generateBodies[0]['steps'], 2);
    expect(generateBodies[0]['cfg'], 7.0);
    expect(generateBodies[0]['output_format'], 'png');

    // 进度事件透传：count=2，每张图各吐一次 step=1
    expect(steps, [1, 1]);

    // 结果经 MediaProxy 登记：media_items 有 2 行，本地文件可读
    expect(result.mediaIds, hasLength(2));
    expect(result.modelName, '手机 SDXL');
    final mediaRows = await db.query('media_items');
    expect(mediaRows, hasLength(2));
    for (final mediaId in result.mediaIds) {
      final bytes =
          await File('${tempDir.path}/media/$mediaId.png').readAsBytes();
      expect(bytes, Uint8List.fromList([9, 8, 7]));
    }
  });

  test('submit：未配置 host / model id → 直接报错不打设备', () async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    addTearDown(db.close);
    await expectLater(
      backend(DatabaseConnection.forTesting(db)).submit(
        ImageGenerationRequest(
          model: model().copyWith(remoteHost: '', remoteModelId: ''),
          prompt: 'cat',
        ),
      ),
      throwsA(isA<LocalDreamException>().having(
          (e) => e.message, 'message', contains('未配置'))),
    );
    // 设备未被触碰
    expect(selectBodies, isEmpty);
    expect(generateBodies, isEmpty);
  });

  test('submit：step>total 的进度帧归一化，total=0 的帧丢弃', () async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    addTearDown(db.close);
    // 复刻真实设备行为：step 超过 total、total=0 的帧
    generationSse = 'event: progress\n'
        'data: {"type":"progress","step":1,"total_steps":2}\n\n'
        'event: progress\n'
        'data: {"type":"progress","step":10,"total_steps":2}\n\n'
        'event: progress\n'
        'data: {"type":"progress","step":1,"total_steps":0}\n\n'
        'event: complete\n'
        'data: {"type":"complete","image":"${base64Encode([9, 8, 7])}",'
        '"format":"png","seed":1,"width":8,"height":8,'
        '"generation_time_ms":50}\n\n';

    final steps = <int>[];
    await backend(DatabaseConnection.forTesting(db)).submit(
      ImageGenerationRequest(model: model(), prompt: 'cat'),
      onProgress: (step, total) => steps.add(step),
    );
    // 10 被钳到 2；total=0 的帧不透传（避免上层 0/0 或越界比值）
    expect(steps, [1, 2]);
  });

  test('submit：设备 error 事件 → 抛 LocalDreamException', () async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    addTearDown(db.close);
    generationSse = 'event: error\ndata: {"type":"error","message":"OOM"}\n\n';

    await expectLater(
      backend(DatabaseConnection.forTesting(db)).submit(
        ImageGenerationRequest(model: model(), prompt: 'cat'),
      ),
      throwsA(isA<LocalDreamException>().having(
          (e) => e.message, 'message', contains('OOM'))),
    );
  });
}

Future<void> _writeJson(HttpRequest request, Map<String, dynamic> json,
    {int status = 200}) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(json));
  await request.response.close();
}
