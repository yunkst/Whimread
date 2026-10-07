/// MediaProxy 单元测试（真实内存 SQLite + 系统临时目录）
///
/// 覆盖生图参数留痕链路（v56）：upload 写入 modelName + genParams（刻意不含
/// seed）→ getItem 读回 MediaItem 字段。文件落在临时目录，不污染应用目录。
///
/// 运行：
///   flutter test test/unit/services/media/media_proxy_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common/sqlite_api.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/services/media/media_proxy.dart';
import 'package:novel_app/services/media/media_types.dart';
import '../../../helpers/test_database_setup.dart' as test_db;

/// 临时目录版 path_provider：MediaStore 固定写应用文档目录，单测下重定向到
/// 系统临时目录（tearDown 删除）。
class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

void main() {
  late Directory tempDir;
  late Database db;
  late MediaProxy proxy;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_proxy_test');
    PathProviderPlatform.instance = _TempPathProvider(tempDir.path);
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    proxy = MediaProxy(dbConn: DatabaseConnection.forTesting(db));
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('upload 写入 modelName + genParams，getItem 原样读回', () async {
    final mediaId = await proxy.upload(
      Uint8List.fromList([1, 2, 3]),
      MediaKind.image,
      prompt: '雨夜城门口的守卫',
      modelName: 'sdxl_npu',
      genParams: {
        'steps': 28,
        'cfg': 7.5,
        'negativePrompt': '模糊',
        'aspectRatio': '3:4',
      },
    );

    final item = await proxy.getItem(mediaId);
    expect(item, isNotNull);
    expect(item!.prompt, '雨夜城门口的守卫');
    expect(item.modelName, 'sdxl_npu');
    expect(item.genParams!['steps'], 28);
    expect(item.genParams!['cfg'], 7.5);
    expect(item.genParams!['negativePrompt'], '模糊');
    expect(item.genParams!['aspectRatio'], '3:4');
    expect(item.genParams!.containsKey('seed'), isFalse,
        reason: '刻意不记 seed：用户要的是「换一张」而非复现同一张');
  });

  test('用户上传（不传生图参数）→ modelName / genParams 为 null', () async {
    final mediaId =
        await proxy.upload(Uint8List.fromList([1]), MediaKind.image);
    final item = await proxy.getItem(mediaId);
    expect(item!.modelName, isNull);
    expect(item.genParams, isNull);
    expect(item.source, MediaSource.localUpload,
        reason: '缺省来源 = 用户上传');
  });

  test('生图路径显式传 source=aiGenerated → 落库为 AI 生成', () async {
    final mediaId = await proxy.upload(
      Uint8List.fromList([1]),
      MediaKind.image,
      prompt: 'p',
      modelName: 'm',
      source: MediaSource.aiGenerated,
    );
    final item = await proxy.getItem(mediaId);
    expect(item!.source, MediaSource.aiGenerated);
  });

  test('文件真实落盘（media 目录），getItem 元数据在库中', () async {
    final mediaId = await proxy.upload(
      Uint8List.fromList([7, 7, 7]),
      MediaKind.image,
      prompt: '落盘校验',
    );
    final file = File('${tempDir.path}${Platform.pathSeparator}media'
        '${Platform.pathSeparator}$mediaId.png');
    expect(file.existsSync(), isTrue);
    expect(await file.length(), 3);
  });
}
