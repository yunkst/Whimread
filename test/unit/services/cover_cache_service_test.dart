/// CoverCacheService 单元测试
///
/// 覆盖：URL 哈希路径确定性、空/无效 URL 安全返回、缓存命中读取、
/// clearAll 清空。真实网络下载不在此覆盖（单测不触网）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/media/cover_cache_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../helpers/path_provider_fake.dart';
import '../../test_bootstrap.dart';

void main() {
  initTests();

  late Directory tempDocs;

  setUp(() async {
    tempDocs = await Directory.systemTemp.createTemp('cover_cache_test');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDocs.path);
  });

  tearDown(() async {
    if (await tempDocs.exists()) {
      await tempDocs.delete(recursive: true);
    }
  });

  /// 按服务端命名规则拼出缓存文件路径（md5(url)）
  File expectedFile(String url) {
    final name = md5.convert(url.codeUnits).toString();
    return File(
      '${tempDocs.path}${Platform.pathSeparator}cover_cache'
      '${Platform.pathSeparator}$name',
    );
  }

  group('getFile', () {
    test('空 URL 返回 null', () async {
      expect(await CoverCacheService.instance.getFile(''), isNull);
      expect(await CoverCacheService.instance.getFile('   '), isNull);
    });

    test('未缓存返回 null', () async {
      expect(
        await CoverCacheService.instance.getFile('https://a.com/c.jpg'),
        isNull,
      );
    });

    test('命中返回文件（MD5 命名确定性）', () async {
      final url = 'https://a.com/c.jpg';
      final file = expectedFile(url);
      await file.create(recursive: true);
      await file.writeAsBytes(utf8.encode('fake-image'));

      final got = await CoverCacheService.instance.getFile(url);
      expect(got, isNotNull);
      expect(got!.path, file.path);

      // 空文件不视为命中
      final empty = expectedFile('https://b.com/empty.png');
      await empty.create(recursive: true);
      expect(
        await CoverCacheService.instance.getFile('https://b.com/empty.png'),
        isNull,
      );
    });
  });

  group('prefetch', () {
    test('空 URL 直接返回 null，不触网', () async {
      expect(await CoverCacheService.instance.prefetch(''), isNull);
    });

    test('非法 URL（scheme 不支持）安全返回 null', () async {
      expect(await CoverCacheService.instance.prefetch('not a url'), isNull);
    });

    test('已缓存直接命中，不再下载', () async {
      final url = 'https://a.com/cached.jpg';
      final file = expectedFile(url);
      await file.create(recursive: true);
      await file.writeAsBytes(utf8.encode('fake-image'));

      final got = await CoverCacheService.instance.prefetch(url);
      expect(got, isNotNull);
      expect(got!.path, file.path);
    });
  });

  group('clearAll', () {
    test('清空全部缓存文件', () async {
      final urls = ['https://a.com/1.jpg', 'https://a.com/2.jpg'];
      for (final url in urls) {
        final f = expectedFile(url);
        await f.create(recursive: true);
        await f.writeAsBytes(utf8.encode('x'));
      }
      await CoverCacheService.instance.clearAll();

      for (final url in urls) {
        expect(
          await CoverCacheService.instance.getFile(url),
          isNull,
          reason: '$url 应已被清空',
        );
      }
    });
  });
}
