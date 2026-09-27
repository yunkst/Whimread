/// NovelCover 封面下载链路测试
///
/// 回归背景：novel_cover.dart 引入 CoverCacheService 时（30846112），
/// 缓存未命中分支被写成直接渲染程序化封面，Image.network 路径不可达，
/// 有 coverUrl 的书永远不会尝试下载真封面。本文件锁定修复后的链路：
/// 1. 缓存未命中 + coverUrl 非空 → 首帧渲染 NetworkImage（真实发起 HTTP）
/// 2. 下载成功 → 异步回写 CoverCacheService（getFile 命中）
/// 3. 重新挂载同 URL 封面 → 走 Image.file 本地缓存，不再发起网络请求
///
/// 网络 via HttpOverrides 假 HttpClient（记录请求并回吐 1x1 PNG），
/// 磁盘 via FakePathProviderPlatform 指向 systemTemp 临时目录。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/services/media/cover_cache_service.dart';
import 'package:novel_app/widgets/novel/novel_cover.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../helpers/path_provider_fake.dart';

/// 1x1 透明 PNG（transparent_image 同款字节），可通过 ui 编解码
final Uint8List _png1x1 = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  // NetworkImage 持有进程级 static HttpClient（首次加载时创建后不再重建），
  // 跨测试用同一份请求记录，规避 static 客户端持有旧列表的问题。
  // 各测试用不同 URL 天然隔离计数。
  final requestedUrls = <Uri>[];

  late Directory tempDocs;

  setUp(() async {
    tempDocs = await Directory.systemTemp.createTemp('novel_cover_test');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDocs.path);
    HttpOverrides.global = _RecordingHttpOverrides(requestedUrls);
  });

  tearDown(() async {
    HttpOverrides.global = null;
    if (!await tempDocs.exists()) return;
    // LoggerService 会向 documents 目录异步写日志文件，Windows 上句柄
    // 释放有延迟；重试几轮，清理失败不影响测试结论（systemTemp 自清理）。
    for (var i = 0; i < 3; i++) {
      try {
        await tempDocs.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  Widget host(Novel novel) => ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              height: 160,
              child: NovelCover(novel: novel),
            ),
          ),
        ),
      );

  /// 真实异步窗口：让 Image 流/文件 IO 在 runAsync 里完成
  Future<void> flushRealIo(tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
  }

  /// 收尾：卸载 widget 树并推掉 LoggerService 的持久化 timer
  Future<void> tearTree(tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  // ── 探针测试：分离验证两段底层链路 ──
  test('探针: 1x1 PNG 字节可被解码', () async {
    final codec =
        await ui.instantiateImageCodec(_png1x1, targetWidth: 1, targetHeight: 1);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1);
    frame.image.dispose();
  });

  test('探针: 假 HttpClient 链路上 http.get 可下载落盘', () async {
    const url = 'https://fake.test/cover-probe.png';
    // 直接走 http.get，失败时原始异常直接暴露（而非被 prefetch 吞掉）
    final resp = await http.get(Uri.parse(url));
    expect(resp.statusCode, 200);
    expect(resp.bodyBytes, _png1x1);
    expect(resp.headers['content-type'], 'image/png');

    final file = await CoverCacheService.instance.prefetch(url);
    expect(file, isNotNull,
        reason: 'prefetch 应经 HttpOverrides 假客户端下载并写缓存');
    expect(requestedUrls.map((u) => u.toString()), contains(url));
  });

  testWidgets('缓存未命中 + coverUrl 非空 → 首帧渲染 NetworkImage（发起下载）',
      (tester) async {
    const url = 'https://fake.test/cover-a.png';
    await tester.pumpWidget(host(Novel(
      title: '测试书A',
      author: '作者',
      url: 'https://fake.test/book-a/',
      coverUrl: url,
    )));
    await tester.pump();

    expect(
      find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage),
      findsOneWidget,
      reason: '缓存未命中时必须走网络加载，而不是程序化封面（回归锁）',
    );

    await flushRealIo(tester);
    expect(
      requestedUrls.map((u) => u.toString()),
      contains(url),
      reason: '应真实发起 HTTP 请求下载封面',
    );

    await tearTree(tester);
  });

  testWidgets('下载成功 → 回写缓存 → 重新挂载走 Image.file 且不再请求网络',
      (tester) async {
    const url = 'https://fake.test/cover-b.png';
    final novel = Novel(
      title: '测试书B',
      author: '作者',
      url: 'https://fake.test/book-b/',
      coverUrl: url,
    );

    // 第一挂载：网络加载 + prefetch 回写落盘
    // 注意时序：prefetch 链路里 FakeAsync 区的微任务只能靠 pump 冲刷，
    // 真实文件 IO 只能靠 runAsync 窗口推进，两者交替循环才能走完链路。
    await tester.pumpWidget(host(novel));
    File? cachedFile;
    for (var i = 0; i < 15 && cachedFile == null; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump();
      await tester.runAsync(() async {
        cachedFile = await CoverCacheService.instance.getFile(url);
      });
    }
    expect(
      cachedFile,
      isNotNull,
      reason: '封面应在网络加载成功后异步回写 CoverCacheService'
          '（requested=${requestedUrls.length}）',
    );
    final hitsAfterFirstLoad =
        requestedUrls.where((u) => u.toString() == url).length;
    expect(hitsAfterFirstLoad, 2,
        reason: '图片加载与 prefetch 下载应各请求一次（无重复下载）');

    await tearTree(tester);
  });

  testWidgets('缓存已存在 → 挂载后最终渲染 Image.file 本地文件', (tester) async {
    // 用全新 URL 预置缓存（直接经服务写入），规避 flutter 图片内存缓存
    // 在 fake-async 下的干扰；挂载后 getFile 链路落定，渲染应走本地文件。
    const url = 'https://fake.test/cover-c.png';
    final novel = Novel(
      title: '测试书C',
      author: '作者',
      url: 'https://fake.test/book-c/',
      coverUrl: url,
    );

    File? preset;
    await tester.runAsync(() async {
      preset = await CoverCacheService.instance.prefetch(url);
    });
    expect(preset, isNotNull, reason: '预置缓存应写入成功');

    await tester.pumpWidget(host(novel));
    var hasFileImage = false;
    for (var i = 0; i < 10 && !hasFileImage; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump();
      hasFileImage = tester
          .widgetList<Image>(find.byType(Image))
          .any((w) => w.image is FileImage);
    }
    expect(hasFileImage, true,
        reason: '缓存命中后最终应渲染本地文件（Image.file）');

    await tearTree(tester);
  });
}

class _RecordingHttpOverrides extends HttpOverrides {
  _RecordingHttpOverrides(this.requested);

  final List<Uri> requested;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(requested);
}

class _FakeHttpClient extends Fake implements HttpClient {
  _FakeHttpClient(this.requested);

  final List<Uri> requested;

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url);
    return _FakeHttpClientRequest();
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    requested.add(url);
    return _FakeHttpClientRequest();
  }

  // http.get 的 _withClient 用完会调 IOClient.close → HttpClient.close
  @override
  void close({bool force = false}) {}
}

class _FakeHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  // IOClient.send 会设置这三个属性，Fake 默认实现会抛错，需显式吞掉
  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = true;

  @override
  int contentLength = -1;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse();
}

class _FakeHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

  @override
  String get reasonPhrase => 'OK';

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  bool get persistentConnection => true;

  @override
  int get contentLength => _png1x1.length;

  // consolidateHttpClientResponseBytes 会无条件读取该字段决定是否解压
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  HttpHeaders get headers => _FakeHttpHeaders()
    ..add('content-type', 'image/png')
    ..add('content-length', '${_png1x1.length}');

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_png1x1).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class _FakeHttpHeaders extends Fake implements HttpHeaders {
  final Map<String, String> _values = {};

  void _set(String name, Object value) =>
      _values[name.toLowerCase()] = value.toString();

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      _set(name, value);

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _set(name, value);

  @override
  String? value(String name) => _values[name.toLowerCase()];

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach((name, value) => action(name, [value]));
  }
}
