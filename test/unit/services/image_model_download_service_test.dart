/// ImageModelDownloadService 单元测试
///
/// 测试内起本地 HttpServer 充当模型文件源，验证：
/// - 流式下载完整落地（.part → 重命名 → ready / 转换分流）
/// - Range 断点续传（服务端支持 206）
/// - gguf 直接入库；safetensors 走转换链路（微型模型）
/// - 失败 → failed + error_message
/// - 启动对账、cleanupFiles
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/image_model_providers.dart'
    show imageModelRepositoryProvider;
import 'package:novel_app/models/image_model.dart';
import 'package:novel_app/repositories/image_model_repository.dart';
import 'package:novel_app/services/image_model_download_service.dart';
import '../../helpers/test_database_setup.dart' as test_db;
import '../../helpers/path_provider_fake.dart';
import '../../helpers/safetensors_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ImageModelRepository repo;
  late ImageModelDownloadService service;
  late HttpServer server;
  late Directory tmpDocs;
  late PathProviderPlatform originalProvider;

  /// 服务端行为开关
  var servedBytes = Uint8List(0);
  final rangeSeen = <int>[];
  var failWith500 = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // TestWidgetsFlutterBinding 会全局注入 fake HttpClient（所有请求 400），
    // 用空 HttpOverrides 覆盖回去，让 Dio 能连本地测试服务器
    HttpOverrides.global = _RealHttpOverrides();
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    repo = ImageModelRepository(dbConnection: DatabaseConnection.forTesting(db));
    service = ImageModelDownloadService(repo: repo);

    originalProvider = PathProviderPlatform.instance;
    tmpDocs = Directory.systemTemp.createTempSync('dl_service_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tmpDocs.path);

    servedBytes = Uint8List(0);
    rangeSeen.clear();
    failWith500 = false;

    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      if (failWith500) {
        req.response.statusCode = 500;
        await req.response.close();
        return;
      }
      final range = req.headers.value('range');
      var start = 0;
      if (range != null) {
        rangeSeen
            .add(int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!));
      }
      if (range != null) {
        start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        req.response.statusCode = 206;
        req.response.headers.set('content-range',
            'bytes $start-${servedBytes.length - 1}/${servedBytes.length}');
      } else {
        req.response.statusCode = 200;
      }
      req.response.contentLength = servedBytes.length - start;
      req.response.add(servedBytes.sublist(start));
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    service.dispose();
    PathProviderPlatform.instance = originalProvider;
    if (tmpDocs.existsSync()) tmpDocs.deleteSync(recursive: true);
    await db.close();
  });

  Uri serverUrl(String name) =>
      Uri.parse('http://127.0.0.1:${server.port}/$name');

  Future<ImageModel> insertDownloadingModel(String url, String filename) async {
    final now = DateTime.now();
    final id = await repo.save(ImageModel(
      name: filename,
      status: ImageModelStatus.downloading,
      sourceUrl: url,
      createdAt: now,
      updatedAt: now,
    ));
    return (await repo.getById(id))!;
  }

  group('gguf 下载', () {
    test('完整下载 → 移入 image_models → ready + filePath/fileSize', () async {
      servedBytes = Uint8List.fromList(
          [0x47, 0x47, 0x55, 0x46, ...List<int>.filled(1000, 0xAB)]);
      final model = await insertDownloadingModel(
          serverUrl('m.gguf').toString(), 'test.gguf');

      await service.startDownload(model);

      final done = await repo.getById(model.id!);
      expect(done!.status, ImageModelStatus.ready);
      expect(done.progress, 100);
      expect(done.filePath, contains('image_models'));
      expect(done.filePath, endsWith('.gguf'));
      expect(done.fileSize, servedBytes.length);
      // 源 .part 已不存在（rename 走了）
      expect(
          File('${tmpDocs.path}/model_downloads/${model.id}.part').existsSync(),
          isFalse);
    });

    test('服务端 500 → failed + error_message', () async {
      failWith500 = true;
      final model = await insertDownloadingModel(
          serverUrl('x.gguf').toString(), 'x.gguf');

      await service.startDownload(model);

      final failed = await repo.getById(model.id!);
      expect(failed!.status, ImageModelStatus.failed);
      expect(failed.errorMessage, isNotEmpty);
    });
  });

  group('safetensors 下载 → 转换链路', () {
    test('微型 SD1.5 safetensors → converting → ready（转换产物 gguf）',
        () async {
      final tensors = <String, (String, List<int>, Uint8List)>{
        'model.diffusion_model.input_blocks.0.0.weight':
            ('F32', [128], seqF32(32 * 4)), // ne[0]=128 ✓ 量化
        'model.diffusion_model.input_blocks.0.0.bias':
            ('F32', [32], seqF32(32)), // .bias 排除
        'cond_stage_model.transformer.text_model.encoder.layers.0.mlp.fc1.weight':
            ('F32', [64], seqF32(64)),
        'first_stage_model.encoder.conv_in.weight':
            ('F32', [128], seqF32(128)),
      };
      servedBytes = writeSyntheticSafetensors(tensors,
              dir: tmpDocs, name: 'tiny')
          .readAsBytesSync();

      final model = await insertDownloadingModel(
          serverUrl('tiny.safetensors').toString(), 'tiny.safetensors');

      await service.startDownload(model);

      // 转换在后台队列异步执行 → 轮询等终态
      final done = await _waitForTerminal(repo, model.id!);
      expect(done.status, ImageModelStatus.ready, reason: '微型模型转换应成功');
      expect(done.filePath, endsWith('.gguf'));
      // 源 safetensors 已自动删除
      expect(
          File('${tmpDocs.path}/model_downloads/${model.id}_source.safetensors')
              .existsSync(),
          isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Range 续传', () {
    test('预置 .part → resume 从 .part 大小续传（服务端收到 Range）', () async {
      final big = Uint8List(3 * 1024 * 1024 + 4096);
      for (var i = 0; i < big.length; i++) {
        big[i] = i % 256;
      }
      servedBytes = big;

      // 预置 .part（模拟已下 3MB）→ startDownload 应带 Range: bytes=3145728-
      final dlDir = Directory('${tmpDocs.path}/model_downloads')
        ..createSync(recursive: true);
      final now = DateTime.now();
      final id = await repo.save(ImageModel(
        name: 'resume.gguf',
        status: ImageModelStatus.downloading,
        sourceUrl: serverUrl('resume.gguf').toString(),
        createdAt: now,
        updatedAt: now,
      ));
      File('${dlDir.path}/$id.part')
          .writeAsBytesSync(big.sublist(0, 3 * 1024 * 1024));

      final model = (await repo.getById(id))!;
      await service.startDownload(model);

      final done = await repo.getById(id);
      expect(done!.status, ImageModelStatus.ready);
      expect(rangeSeen, [3 * 1024 * 1024],
          reason: '应携带 Range 从 .part 大小续传');
      expect(done.fileSize, big.length);
      // 文件内容拼接正确：末尾 4 字节 == big 末尾
      final content = await File(done.filePath).readAsBytes();
      expect(content.length, big.length);
      expect(content.sublist(content.length - 4),
          big.sublist(big.length - 4));
    });
  });

  group('启动对账', () {
    test('downloading → paused；converting → failed（可重试语义）', () async {
      final now = DateTime.now();
      await repo.save(ImageModel(
          name: 'a',
          status: ImageModelStatus.downloading,
          sourceUrl: 'http://x',
          createdAt: now,
          updatedAt: now));
      await repo.save(ImageModel(
          name: 'b',
          status: ImageModelStatus.converting,
          createdAt: now,
          updatedAt: now));

      await service.recoverOnStartup();

      final all = await repo.getAll();
      final byName = {for (final m in all) m.name: m};
      expect(byName['a']!.status, ImageModelStatus.paused);
      expect(byName['b']!.status, ImageModelStatus.failed);
    });
  });

  group('cleanupFiles', () {
    test('删除 .part / 源 / 转换产物', () async {
      final dlDir = Directory('${tmpDocs.path}/model_downloads')
        ..createSync(recursive: true);
      File('${dlDir.path}/1.part').writeAsBytesSync([1]);
      File('${dlDir.path}/1_source.safetensors').writeAsBytesSync([1]);
      File('${dlDir.path}/1_converted.gguf').writeAsBytesSync([1]);

      await service.cleanupFiles(1);

      expect(File('${dlDir.path}/1.part').existsSync(), isFalse);
      expect(File('${dlDir.path}/1_source.safetensors').existsSync(), isFalse);
      expect(File('${dlDir.path}/1_converted.gguf').existsSync(), isFalse);
    });
  });
}

// ---------- helpers ----------

/// 恢复真实 HttpClient（绕开 flutter_test 的 400 拦截），仅用于连本地测试服务器
class _RealHttpOverrides extends HttpOverrides {}

/// 轮询直到模型进入终态（ready/failed）或超时
Future<ImageModel> _waitForTerminal(ImageModelRepository repo, int modelId,
    {Duration timeout = const Duration(seconds: 60)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final m = await repo.getById(modelId);
    if (m != null &&
        (m.status == ImageModelStatus.ready ||
            m.status == ImageModelStatus.failed)) {
      return m;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('模型 $modelId 未在限时内进入终态');
}
