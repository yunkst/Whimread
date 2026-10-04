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
import 'dart:typed_data';

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
        // 越界 Range → 416（真实 CDN 行为），content-range 携带全量大小。
        // 不越界的 Range 仍忽略（回 200 全量），维持既有测试语义。
        final range = request.headers.value('range');
        final start = range == null
            ? 0
            : int.tryParse(
                    RegExp(r'bytes=(\d+)-').firstMatch(range)?.group(1) ??
                        '0') ??
                0;
        if (range != null && start >= bytes.length) {
          request.response.statusCode = 416;
          request.response.headers
              .set('content-range', 'bytes */${bytes.length}');
          await request.response.close();
          return;
        }
        request.response.headers.contentType =
            ContentType('application', 'zip');
        // 真实 CDN 都带 Content-Length（否则下载器拿不到总量，
        // 进度只能停在 0%）；这里保持不支持 Range 的行为不变
        request.response.contentLength = bytes.length;
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
    // Windows：解压 isolate 的文件句柄释放滞后于 Isolate.run 返回，
    // 立即删临时目录偶发 errno=32（文件被占用），重试兜底
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        break;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
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

  test('createDownloadingRow 写入 catalog_id（目录条目 id），导入行为空', () async {
    final row = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/pack.zip',
    );
    expect(row.catalogId, 'anythingv5');

    final imported = await downloader.importPackDirectory(
      type: LocalDreamPackType.sd15Cpu,
      sourceDir: tempDir.path,
      displayName: '手工导入包',
    );
    expect(imported.row.catalogId, isEmpty);
  });

  test('同名未就绪行复用：再点下载 = 续传（不撞唯一名、.part 保留、换源生效）',
      () async {
    final repo = container.read(imageModelRepositoryProvider);
    // 第一次用坏地址 → failed（目录卡片此时仍显示下载图标）
    final failedRow = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/nope.zip',
    );
    await downloader.startDownload(failedRow);
    expect((await repo.getById(failedRow.id!))!.status,
        ImageModelStatus.failed);

    // 模拟上次中断留下的 .part（断点）
    final part = File('${failedRow.filePath}.zip.part');
    part.writeAsBytesSync([1, 2, 3]);

    // 再点下载（可同时已切换下载源）：必须复用旧行而不是新插同名行
    final resumed = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/pack.zip',
    );
    expect(resumed.id, failedRow.id, reason: '应复用原行，避免重复记录');
    expect(resumed.sourceUrl, contains('/pack.zip'),
        reason: 'sourceUrl 应刷成当前所选源');
    expect(part.existsSync(), isTrue, reason: '.part 断点应保留以续传');
    expect((await repo.getAll()).where((m) => m.id == failedRow.id).length, 1);

    await downloader.startDownload(resumed);
    expect((await repo.getById(failedRow.id!))!.status,
        ImageModelStatus.ready);
  });

  test('同名已就绪行：再下同名任务自动改名兜底，不抛唯一名异常', () async {
    final repo = container.read(imageModelRepositoryProvider);
    final first = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/pack.zip',
    );
    await downloader.startDownload(first);
    expect((await repo.getById(first.id!))!.status, ImageModelStatus.ready);

    // 正常 UI 在「已添加」态隐藏入口，这里兜底保证不撞 UNIQUE 崩溃
    final second = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/pack.zip',
    );
    expect(second.id, isNot(first.id));
    expect(second.name, isNot(first.name));
    expect(second.name, startsWith(first.name));
  });

  test('resumeOrphanDownloads：孤儿 downloading 行自愈续传至 ready', () async {
    final repo = container.read(imageModelRepositoryProvider);
    final row = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/pack.zip',
    );
    // 模拟切后台被冻结：行停在 downloading，但本进程无活跃任务
    expect(downloader.hasActiveDownload(row.id!), isFalse);

    final healed = await downloader.resumeOrphanDownloads();
    expect(healed, 1, reason: '孤儿行应触发自愈续传');
    expect(downloader.hasActiveDownload(row.id!), isTrue);

    // 后台续传任务跑完 → ready（反馈 #9 卡死的场景在此闭环）
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var status = (await repo.getById(row.id!))!.status;
    while (status != ImageModelStatus.ready &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      status = (await repo.getById(row.id!))!.status;
    }
    expect(status, ImageModelStatus.ready);
  });

  test('resumeOrphanDownloads：有活跃任务时不重复启动（单请求守卫）', () async {
    final row = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/pack.zip',
    );
    // 进行中的下载：startDownload 在首个 await 前同步注册 CancelToken
    final task = downloader.startDownload(row);
    expect(await downloader.resumeOrphanDownloads(), 0,
        reason: '有活跃任务的行不能被自愈重复启动');
    await task;
    expect(packRequests, 1, reason: '自愈不得发出第二个请求');

    // 任务结束后行已 ready，无 downloading 行可自愈
    expect(await downloader.resumeOrphanDownloads(), 0);
  });

  test('progressSamples：广播细粒度采样（真实字节/速度/百分比，收尾到 100）',
      () async {
    final samples = <PackDownloadSample>[];
    final sub = downloader.progressSamples.listen(samples.add);
    final row = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/pack.zip',
    );

    await downloader.startDownload(row);
    await sub.cancel();

    expect(samples, isNotEmpty, reason: '下载过程必须广播采样供 UI 细看');
    for (final s in samples) {
      expect(s.modelId, row.id);
      expect(s.bytesPerSecond, greaterThanOrEqualTo(0));
      expect(s.percent, inInclusiveRange(0, 100));
      if (s.totalBytes != null) {
        expect(s.receivedBytes, lessThanOrEqualTo(s.totalBytes!));
      }
    }
    // 字节只增不减（进度条不会倒退）
    for (var i = 1; i < samples.length; i++) {
      expect(samples[i].receivedBytes,
          greaterThanOrEqualTo(samples[i - 1].receivedBytes));
    }
    // 收尾采样：真实百分比走到 100（UI 进度条不卡在 95%）
    expect(samples.last.percent, 100);
    expect(samples.last.etaSeconds, 0);
  });

  test('断点已完整（416 且大小吻合）→ 跳过下载直接解压 → ready', () async {
    final repo = container.read(imageModelRepositoryProvider);
    final row = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/pack.zip',
    );
    // 模拟「上次已下完、进入解压前被杀」：.part 是完整 zip
    File('${row.filePath}.zip.part')
        .writeAsBytesSync(File(p.join(tempDir.path, 'pack.zip')).readAsBytesSync());

    await downloader.startDownload(row);

    final latest = await repo.getById(row.id!);
    expect(latest!.status, ImageModelStatus.ready);
    expect(packRequests, 1, reason: '断点完整时不应重下整个包');
  });

  test('断点越界（416）→ 截断 .part 全量重下 → ready 且内容正确', () async {
    final repo = container.read(imageModelRepositoryProvider);
    final row = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/pack.zip',
    );
    // .part 比远端全量还大（远端文件换小/换包）
    final part = File('${row.filePath}.zip.part');
    part.writeAsBytesSync(
        List.filled(File(p.join(tempDir.path, 'pack.zip')).lengthSync() + 100, 9));

    await downloader.startDownload(row);

    final latest = await repo.getById(row.id!);
    expect(latest!.status, ImageModelStatus.ready);
    for (final e in packFiles.entries) {
      expect(File(p.join(latest.filePath, e.key)).readAsBytesSync(), e.value,
          reason: e.key);
    }
  });

  test('完整大小但内容损坏 → failed 且 .part 被清理（不陷入 416 死循环）',
      () async {
    final repo = container.read(imageModelRepositoryProvider);
    final row = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/pack.zip',
    );
    // 大小吻合但内容是垃圾 → 416 后直接解压失败
    final part = File('${row.filePath}.zip.part');
    part.writeAsBytesSync(
        List.filled(File(p.join(tempDir.path, 'pack.zip')).lengthSync(), 7));

    await downloader.startDownload(row);

    final latest = await repo.getById(row.id!);
    expect(latest!.status, ImageModelStatus.failed);
    expect(latest.errorMessage, contains('损坏'));
    expect(part.existsSync(), isFalse,
        reason: '坏 .part 必须清理，否则下次续传 416→解压失败无限循环');
  });

  test('大条目流式解压：24MB 条目正确落盘（GB 级权重不整块进内存）', () async {
    // 用户实测事故：SDXL NPU 包进度到 95% 后 failed(Out of Memory)——
    // archive 3.6.1 的 writeContent 对 DEFLATE 条目整块解压进内存。
    // 修复后走 decompress(output) 流式路径；本例用 24MB 条目验证
    // 多块流式解压的内容正确性（GB 级条目的内存行为由代码路径保证）。
    final repo = container.read(imageModelRepositoryProvider);
    final bigBytes = Uint8List(24 * 1024 * 1024);
    for (var i = 0; i < bigBytes.length; i++) {
      bigBytes[i] = i % 251; // 可压缩内容 → 编解码都快
    }
    final bigZipPath = p.join(tempDir.path, 'big.zip');
    final bigEncoder = ZipFileEncoder();
    bigEncoder.create(bigZipPath);
    // 复用 setUp 写好的必需文件（名字必须与 requiredFiles 一致）
    for (final entry in packFiles.entries) {
      bigEncoder.addFile(File(p.join(tempDir.path, entry.key)));
    }
    final bigTmp = File(p.join(tempDir.path, 'unet.mnn'))
      ..writeAsBytesSync(bigBytes);
    bigEncoder.addFile(bigTmp);
    bigEncoder.close();
    final bigPack = File(bigZipPath).readAsBytesSync();

    final bigServer = await HttpServer.bind('127.0.0.1', 0);
    bigServer.listen((request) async {
      request.response.contentLength = bigPack.length;
      request.response.add(bigPack);
      await request.response.close();
    });
    addTearDown(() => bigServer.close(force: true));

    final row = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${bigServer.port}/big.zip',
    );
    await downloader.startDownload(row);

    final latest = await repo.getById(row.id!);
    expect(latest!.status, ImageModelStatus.ready,
        reason: latest.errorMessage);
    final out = File(p.join(latest.filePath, 'unet.mnn'));
    expect(out.existsSync(), isTrue);
    expect(out.lengthSync(), bigBytes.length);
    expect(out.readAsBytesSync(), bigBytes);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('macOS 资源叉条目被跳过：__MACOSX/._x.mnn 不覆盖真文件', () async {
    // 对齐 Local Dream unzipFile 的过滤规则：跳过 . 开头与 __MACOSX/ 条目，
    // 否则扁平化后的 '._x.mnn'（几 KB 空壳）会覆盖真正的 x.mnn
    final repo = container.read(imageModelRepositoryProvider);
    final macZipPath = p.join(tempDir.path, 'mac.zip');
    final macEncoder = ZipFileEncoder();
    macEncoder.create(macZipPath);
    for (final entry in packFiles.entries) {
      macEncoder.addFile(File(p.join(tempDir.path, entry.key)));
    }
    // 真正的权重文件
    final real = File(p.join(tempDir.path, 'unet.mnn'))
      ..writeAsBytesSync(utf8.encode('REAL-UNET-WEIGHTS'));
    macEncoder.addFile(real);
    // macOS 资源叉：解压后 basename = ._unet.mnn
    final fork = File(p.join(tempDir.path, '._unet.mnn'))
      ..writeAsBytesSync(utf8.encode('MACOSX-RESOURCE-FORK'));
    macEncoder.addFile(fork);
    macEncoder.close();
    final macPack = File(macZipPath).readAsBytesSync();

    final macServer = await HttpServer.bind('127.0.0.1', 0);
    macServer.listen((request) async {
      request.response.contentLength = macPack.length;
      request.response.add(macPack);
      await request.response.close();
    });
    addTearDown(() => macServer.close(force: true));

    final row = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${macServer.port}/mac.zip',
    );
    await downloader.startDownload(row);

    final latest = await repo.getById(row.id!);
    expect(latest!.status, ImageModelStatus.ready, reason: latest.errorMessage);
    expect(File(p.join(latest.filePath, 'unet.mnn')).readAsStringSync(),
        'REAL-UNET-WEIGHTS');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('recoverInterruptedDownloads：downloading 行归位 paused', () async {
    final row = await downloader.createDownloadingRow(
      entry: entry(),
      zipUrl: 'http://127.0.0.1:${server.port}/pack.zip',
    );

    // 模拟杀进程遗留：行处于 downloading（无进行中任务）
    final recovered = await downloader.recoverInterruptedDownloads();
    expect(recovered, isTrue);

    final latest = await container
        .read(imageModelRepositoryProvider)
        .getById(row.id!);
    expect(latest!.status, ImageModelStatus.paused);

    // 再跑一次：无 stuck 行时不触发写库
    final again = await downloader.recoverInterruptedDownloads();
    expect(again, isFalse);
  });
}

class _UnusedApiServiceWrapper extends ApiServiceWrapper {}
