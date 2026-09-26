/// LocalDreamEmbeddedBackend 测试
///
/// fake 引擎管理器（记录 ensureStarted 调用）+ fake 生成端口 HttpServer
/// + 真实 MediaProxy（内存库 + 临时目录），覆盖：
/// - validate：引擎未打包 / 未配置类型 / 包文件缺失 / 齐全通过
/// - submit：ensureStarted 带上正确类型与目录、SSE 完成事件落库为 mediaId
/// - 生成 error 事件 → LocalDreamException
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
import 'package:novel_app/services/image_generation/local_dream_client.dart';
import 'package:novel_app/services/image_generation/local_dream_embedded_backend.dart';
import 'package:novel_app/services/local_dream_embedded/engine_manager.dart';
import 'package:novel_app/services/local_dream_embedded/model_pack.dart';
import 'package:novel_app/services/media/media_proxy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../helpers/path_provider_fake.dart';
import '../../../helpers/test_database_setup.dart';

/// 记录调用的假引擎管理器（不 spawn 真进程）
class _FakeEngineManager implements LocalDreamEngineManager {
  bool binaryAvailable = true;
  final List<({LocalDreamPackType type, String modelDir})> started = [];

  @override
  Future<bool> isBinaryAvailable() async => binaryAvailable;

  @override
  Future<void> ensureStarted({
    required LocalDreamPackType type,
    required String modelDir,
  }) async {
    started.add((type: type, modelDir: modelDir));
  }

  @override
  Future<void> stop() async {}

  @override
  LocalDreamEngineStatus get status => const LocalDreamEngineStatus.stopped();

  @override
  Future<bool> isQnnAssetsAvailable() async => true;

  @override
  Future<String?> nativeLibDir() async => '/unused';
}

void main() {
  late HttpServer generationServer;
  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;
  late Database db;
  String generationSse =
      'event: complete\ndata: {"type":"complete","image":"${base64Encode([5, 6, 7])}",'
      '"format":"png","seed":7,"width":8,"height":8,'
      '"generation_time_ms":40}\n\n';

  /// /generate 请求体记录（断言画布/aspect_ratio 用）
  final generateBodies = <Map<String, dynamic>>[];

  setUp(() async {
    generateBodies.clear();
    tempDir = await Directory.systemTemp.createTemp('ld_embedded');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);

    db = await TestDatabaseSetup.createInMemoryDatabase();
    generationSse =
        'event: complete\ndata: {"type":"complete","image":"${base64Encode([5, 6, 7])}",'
        '"format":"png","seed":7,"width":8,"height":8,'
        '"generation_time_ms":40}\n\n';

    generationServer = await HttpServer.bind('127.0.0.1', 0);
    generationServer.listen((request) async {
      final path = request.uri.path;
      if (path == '/health') {
        request.response.statusCode = 200;
        await request.response.close();
        return;
      }
      if (path == '/generate') {
        final body = await utf8.decoder.bind(request).join();
        generateBodies.add(jsonDecode(body) as Map<String, dynamic>);
        final response = request.response;
        response.add(utf8.encode(generationSse));
        await response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPathProvider;
    await generationServer.close(force: true);
    await db.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// 建 sdxl 模型包目录（9 个必需文件全写占位内容）
  Directory createPack() {
    final pack = Directory(p.join(tempDir.path, 'pack_sdxl'))
      ..createSync(recursive: true);
    for (final name in LocalDreamPackType.sdxl.requiredFiles) {
      File(p.join(pack.path, name)).writeAsStringSync('placeholder');
    }
    return pack;
  }

  ImageModel model(Directory pack) => ImageModel(
        name: '本机 SDXL',
        backendType: ImageModelBackendType.localDreamEmbedded,
        filePath: pack.path,
        remoteModelId: LocalDreamPackType.sdxl.dbName,
        defaultWidth: 8,
        defaultHeight: 8,
        defaultSteps: 2,
        defaultCfg: 7.0,
        negativePrompt: 'lowres',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  LocalDreamEmbeddedBackend backend({_FakeEngineManager? manager}) {
    final dbConn = DatabaseConnection.forTesting(db);
    return LocalDreamEmbeddedBackend(
      mediaProxy: MediaProxy(dbConn: dbConn),
      engineManager: manager ?? _FakeEngineManager(),
      clientFactory: () => LocalDreamClient(
        host: '127.0.0.1',
        generationPort: generationServer.port,
      ),
    );
  }

  test('id / supports：local_dream_embedded 路由正确', () {
    final b = backend();
    expect(b.id, 'local_dream_embedded');
    expect(b.supports(ImageModelBackendType.localDreamEmbedded), isTrue);
    expect(b.supports(ImageModelBackendType.localSd), isFalse);
  });

  test('validate：引擎未打包 → 放置引导文案', () async {
    final manager = _FakeEngineManager()..binaryAvailable = false;
    final result = await backend(manager: manager).validate(model(createPack()));
    expect(result, contains('引擎未打包'));
  });

  test('validate：未配置包类型 → 提示编辑', () async {
    final pack = createPack();
    final result = await backend()
        .validate(model(pack).copyWith(remoteModelId: ''));
    expect(result, contains('未配置模型包类型'));
  });

  test('validate：包文件缺失 → 列出缺失文件', () async {
    final pack = createPack();
    File(p.join(pack.path, 'unet.bin')).deleteSync();
    final result = await backend().validate(model(pack));
    expect(result, contains('unet.bin'));
  });

  test('validate：目录不存在 → 提示重新导入', () async {
    final pack = createPack();
    pack.deleteSync(recursive: true);
    final result = await backend().validate(model(pack));
    expect(result, contains('模型包目录不存在'));
  });

  test('submit：ensureStarted + SSE 出图落库为 mediaId', () async {
    final pack = createPack();
    final manager = _FakeEngineManager();
    final result = await backend(manager: manager).submit(
      ImageGenerationRequest(
        model: model(pack),
        prompt: 'a cat',
        negativePrompt: 'lowres',
        count: 1,
        seed: 11,
        // 模型条目的 8×8 像素应被忽略：SDXL 恒用 1024 原生画布
        width: 8,
        height: 8,
        aspectRatio: '16:9',
      ),
      onProgress: (step, total) {},
    );

    expect(manager.started, hasLength(1));
    expect(manager.started.single.type, LocalDreamPackType.sdxl);
    expect(manager.started.single.modelDir, pack.path);

    // 画布 = 包类型原生尺寸（1024），模型条目像素被忽略；比例透传
    expect(generateBodies, hasLength(1));
    expect(generateBodies.single['width'], 1024);
    expect(generateBodies.single['height'], 1024);
    expect(generateBodies.single['aspect_ratio'], '16:9');

    expect(result.mediaIds, hasLength(1));
    final bytes =
        await File('${tempDir.path}/media/${result.mediaIds.single}.png')
            .readAsBytes();
    expect(bytes, Uint8List.fromList([5, 6, 7]));
  });

  test('submit：SD1.5 恒用原生 512 画布且不带 aspect_ratio', () async {
    final pack = Directory(p.join(tempDir.path, 'pack_sd15'))
      ..createSync(recursive: true);
    for (final name in LocalDreamPackType.sd15Npu.requiredFiles) {
      File(p.join(pack.path, name)).writeAsStringSync('placeholder');
    }
    await backend().submit(
      ImageGenerationRequest(
        model: model(pack).copyWith(remoteModelId: 'sd15npu'),
        prompt: 'cat',
        aspectRatio: '16:9', // SD1.5 应被忽略
      ),
    );
    expect(generateBodies.single['width'], 512);
    expect(generateBodies.single['height'], 512);
    expect(generateBodies.single.containsKey('aspect_ratio'), isFalse);
  });

  test('submit：设备 error 事件 → 抛 LocalDreamException', () async {
    final pack = createPack();
    generationSse = 'event: error\ndata: {"type":"error","message":"OOM"}\n\n';

    await expectLater(
      backend().submit(
        ImageGenerationRequest(model: model(pack), prompt: 'cat'),
      ),
      throwsA(isA<LocalDreamException>().having(
          (e) => e.message, 'message', contains('OOM'))),
    );
  });
}
