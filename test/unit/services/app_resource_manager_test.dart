/// AppResourceManager 单测：manifest 解析 / 下载校验 / 缓存命中 / 失败重试
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../helpers/path_provider_fake.dart';
import 'package:novel_app/services/app_resource_manager.dart';

void main() {
  // 注意：不使用 TestWidgetsFlutterBinding——它会劫持所有 HttpClient 请求
  // 返回 400；本测试用真实 localhost socket 验证下载链路。
  late Directory tmpDir;
  late HttpServer server;
  late String baseUrl;
  final served = <String, int>{}; // path → 请求次数

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('arm_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tmpDir.path);
  });

  tearDownAll(() async {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  setUp(() async {
    served.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.host}:${server.port}';
    server.listen((req) async {
      served[req.uri.path] = (served[req.uri.path] ?? 0) + 1;
      final bytes = utf8.encode('content-of:${req.uri.path}');
      req.response.add(bytes);
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  DynamicResourceFile spec(String name) {
    final bytes = utf8.encode('content-of:/$name');
    return DynamicResourceFile(
      name: name,
      url: '$baseUrl/$name',
      sha256: sha256.convert(bytes).toString(),
      size: bytes.length,
    );
  }

  test('fetchManifest 正确解析统一 manifest', () async {
    final body = json.encode({
      'manifest_version': 2,
      'resources': [
        {
          'id': 'ui_fonts',
          'version': 'v1',
          'files': [
            {
              'name': 'a.ttf',
              'url': '$baseUrl/a.ttf',
              'sha256': 'x',
              'size': 1,
            }
          ],
        },
      ],
    });
    final manifest = AppResourcesManifest.fromJson(
        json.decode(body) as Map<String, dynamic>);
    expect(manifest.manifestVersion, 2);
    expect(manifest.resources['ui_fonts']!.files.single.name, 'a.ttf');
  });

  test('ensureResource 下载 + 校验通过，二次调用命中缓存不再请求', () async {
    final f = spec('font_a.ttf');
    final manager = AppResourceManager(dio: Dio(), retryDelay: Duration.zero);
    final specObj = DynamicResourceSpec(id: 'ui_fonts', version: 'v1', files: [f]);

    var progressCalls = 0;
    final paths = await manager.ensureResource(specObj,
        onProgress: (r, t) => progressCalls++);
    expect(paths['font_a.ttf'], isNotNull);
    expect(File(paths['font_a.ttf']!).existsSync(), isTrue);
    expect(progressCalls, greaterThan(0));

    // 二次：sha256 命中
    final again = await manager.ensureResource(specObj);
    expect(again, paths);
    expect(served['/font_a.ttf'], 1); // 只下载过一次
  });

  test('sha256 不一致 → 删除临时文件并抛错', () async {
    final bad = DynamicResourceFile(
      name: 'bad.so',
      url: '$baseUrl/bad.so',
      sha256: '0' * 64, // 故意错误的期望值
      size: 16,
    );
    final manager = AppResourceManager(dio: Dio(), retryDelay: Duration.zero);
    await expectLater(
      manager.ensureResource(
          DynamicResourceSpec(id: 'sd_engine', version: 'v1', files: [bad])),
      throwsA(isA<StateError>()),
    );
    final dir = await manager.resourceDir('sd_engine');
    expect(dir.listSync().whereType<File>().where((f) => f.path.endsWith('.tmp')),
        isEmpty);
  });

  test('tryRestoreSdEngine 命中时回填 sdLibraryPath', () async {
    final f = spec('libsds.so');
    final manager = AppResourceManager(dio: Dio(), retryDelay: Duration.zero);
    final specObj = DynamicResourceSpec(id: 'sd_engine', version: 'v1', files: [f]);
    AppResourceManager.sdLibraryPath = null;

    expect(await manager.tryRestoreSdEngine(specObj), isFalse);

    await manager.ensureSdEngine(specObj);
    expect(AppResourceManager.sdLibraryPath, isNotNull);
    expect(AppResourceManager.sdLibraryPath!.endsWith('libsds.so'), isTrue);

    // 新实例（模拟重启）：tryRestore 直接恢复路径
    AppResourceManager.sdLibraryPath = null;
    final manager2 = AppResourceManager(dio: Dio());
    expect(await manager2.tryRestoreSdEngine(specObj), isTrue);
    expect(AppResourceManager.sdLibraryPath, isNotNull);
  });
}
