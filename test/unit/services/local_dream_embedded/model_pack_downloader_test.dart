/// Local Dream 模型包下载器测试（ZIP 全链路）
///
/// fake HttpServer 提供 zip，内存库 + 临时目录，覆盖：
/// - zip 下载 → 流式解压 → NPU v3 标记 → 必需文件校验置 ready
/// - zip 内 config.json 的 steps/cfg/negativePrompt 合并到模型行
/// - 空 URL / 404 → failed 引导
/// - cancelAndDelete 清理
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/image_model_providers.dart';
import 'package:novel_app/core/providers/services/network_service_providers.dart';
import 'package:novel_app/models/image_model.dart';
import 'package:novel_app/services/api_service_wrapper.dart';
import 'package:novel_app/services/local_dream_embedded/model_pack.dart';
import 'package:novel_app/services/local_dream_embedded/model_pack_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common/sqflite.dart';

import '../../../helpers/path_provider_fake.dart';
import '../../../helpers/test_database_setup.dart' as test_db;

void main() {
  late HttpServer server;
  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;
  late ProviderContainer container;
  late LocalDreamModelPackDownloader downloader;
  late Database db;

  /// /pack.zip 命中次数（幂等守卫测试断言"只发一个请求"用）
  var packRequests = 0;

  /// zip 内的模型文件内容（解压后落包目录）
  final packFiles = <String, List<int>>{
    'tokenizer.json': utf8.encode('{"token": true}'),
    'clip_v2.mnn': utf8.encode('MNN-BYTES'),
    'pos_emb.bin': utf8.encode('POS'),
    'token_emb.bin': utf8.encode('TOKEN'),
    // DMD2 风格的包内配置：steps/cfg/负向词
    'config.json': utf8.encode(jsonEncode({
      'prompt': 'masterpiece',
      'negativePrompt': 'lowres, from-config',
      'steps': 8,
      'cfg': 1.5,
    })),
  };

  setUp(() async {
    packRequests = 0;
    tempDir = await Directory.systemTemp.createTemp('ld_pack_dl');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);

    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    final dio = Dio();
    container = ProviderContainer(overrides: [
      databaseConnectionProvider
          .overrideWithValue(DatabaseConnection.forTesting(db)),
      apiServiceWrapperProvider
          .overrideWithValue(_UnusedApiServiceWrapper()),
    ]);
    final downloaderProvider =
        Provider<LocalDreamModelPackDownloader>((ref) =>
            LocalDreamModelPackDownloader(ref: ref, dio: dio));
    downloader = container.read(downloaderProvider);

    // 构造 zip：模拟 Local Dream 的预转换包（文件在根 + config.json）
    final zipPath = p.join(tempDir.path, 'pack.zip');
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    for (final entry in packFiles.entries) {
      final tmp = File(p.join(tempDir.path, entry.key))
        ..writeAsBytesSync(entry.value);
      encoder.addFile(tmp);
    }
    encoder.close();

    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/pack.zip') {
        packRequests++;
        final bytes = File(zipPath).readAsBytesSync();
        request.response.headers.contentType =
            ContentType('application', 'zip');
        request.response.add(bytes);
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    container.dispose();
    await db.close();
    PathProviderPlatform.instance = originalPathProvider;
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  LocalDreamPackEntry entry() =>
      localDreamPackCatalog.firstWhere((e) => e.id == 'anythingv5');

  test('zip 全链路：下载解压 v3 标记 config 合并 → ready', () async {
    final row = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/pack.zip',
    );

    await downloader.startDownload(row);

    final repo = container.read(imageModelRepositoryProvider);
    final latest = await repo.getById(row.id!);
    expect(latest!.status, ImageModelStatus.ready);
    expect(latest.errorMessage, isEmpty);

    // 文件落盘（内容一致）
    for (final e in packFiles.entries) {
      final f = File(p.join(latest.filePath, e.key));
      expect(f.existsSync(), isTrue, reason: e.key);
      expect(f.readAsBytesSync(), e.value, reason: e.key);
    }

    // NPU 类型带 v3 标记（Local Dream 版本约定）
    expect(File(p.join(latest.filePath, 'v3')).existsSync(), isTrue);

    // config.json 的 steps/cfg/负向词已合并到行
    expect(latest.defaultSteps, 8);
    expect(latest.defaultCfg, 1.5);
    expect(latest.negativePrompt, 'lowres, from-config');
  });

  test('空 URL → failed 并给出引导', () async {
    final row = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: '',
    );
    final model =
        await container.read(imageModelRepositoryProvider).getById(row.id!);
    await downloader.startDownload(model!);

    final latest =
        await container.read(imageModelRepositoryProvider).getById(row.id!);
    expect(latest!.status, ImageModelStatus.failed);
    expect(latest.errorMessage, contains('没有可用的下载地址'));
  });

  test('404 → failed', () async {
    final row = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/nope.zip',
    );
    await downloader.startDownload(row);

    final latest =
        await container.read(imageModelRepositoryProvider).getById(row.id!);
    expect(latest!.status, ImageModelStatus.failed);
    expect(latest.errorMessage, contains('404'));
  });

  test('cancelAndDelete：删除包目录与行', () async {
    final row = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/pack.zip',
    );
    final packDir = Directory(row.filePath);
    expect(packDir.existsSync(), isTrue);

    await downloader.cancelAndDelete(row);

    expect(packDir.existsSync(), isFalse);
    expect(
        await container.read(imageModelRepositoryProvider).getById(row.id!),
        isNull);
  });

  test('服务器不支持 Range（回 200 全量）→ 截断旧 .part 全量重下不损坏', () async {
    final row = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/pack.zip',
    );
    // 模拟上次中断留下的 .part：测试服务器不支持 Range（恒回 200 全量），
    // 旧行为会把完整响应追加到旧 .part 尾部产出损坏 zip；
    // 修复后应从 0 起全量重下
    File('${row.filePath}.zip.part').writeAsBytesSync([1, 2, 3, 4, 5]);

    await downloader.startDownload(row);

    final repo = container.read(imageModelRepositoryProvider);
    final latest = await repo.getById(row.id!);
    expect(latest!.status, ImageModelStatus.ready);
    // 落盘内容必须与 zip 原件一致（追加损坏时这里会失败/解压报错）
    for (final e in packFiles.entries) {
      expect(File(p.join(latest.filePath, e.key)).readAsBytesSync(), e.value,
          reason: e.key);
    }
  });

  test('startDownload 幂等：该 id 已在下载时忽略重复启动', () async {
    final row = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/pack.zip',
    );
    // 连点两次（不 await 第一次）：第一次在首个 await 前同步注册
    // CancelToken 占位，第二次应被守卫拦截，不再发第二个请求
    final first = downloader.startDownload(row);
    final second = downloader.startDownload(row);
    await Future.wait([first, second]);

    expect(packRequests, 1);
    final latest = await container
        .read(imageModelRepositoryProvider)
        .getById(row.id!);
    expect(latest!.status, ImageModelStatus.ready);
  });
}

class _UnusedApiServiceWrapper extends ApiServiceWrapper {}
