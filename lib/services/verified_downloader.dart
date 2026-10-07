/// 校验型文件下载原语
///
/// 「.tmp 流式落盘 → sha256 校验 → 原子替换」这条链路在动态资源
/// （AppResourceManager）与 OCR 模型（OcrModelDownloader）两处是完全相同的
/// 算法，差异只在重试节奏与日志文案——前者由各服务的重试循环自理，
/// 本文件只收口单次下载与哈希计算。
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// 下载 [url] 到 [dest]：先写 `<dest>.tmp`，sha256 与 [expectSha256] 一致才
/// 原子替换（先删旧文件再 rename），不一致删 tmp 并抛 [StateError]。
/// [onProgress] 按累计字节回调，total 取 Content-Length（缺失为 -1）。
Future<void> downloadVerified({
  required Dio dio,
  required String url,
  required String expectSha256,
  required File dest,
  void Function(int received, int total)? onProgress,
}) async {
  final tmp = File('${dest.path}.tmp');
  if (await tmp.exists()) await tmp.delete();

  final resp = await dio.get<ResponseBody>(
    url,
    options: Options(responseType: ResponseType.stream),
  );
  final total = int.tryParse(
          resp.headers.value(HttpHeaders.contentLengthHeader) ?? '') ??
      -1;
  var received = 0;
  final sink = tmp.openWrite();
  try {
    await for (final chunk in resp.data!.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
  } finally {
    await sink.close();
  }

  final actual = await sha256OfFile(tmp);
  if (actual != expectSha256) {
    await tmp.delete();
    throw StateError('SHA256 不一致: 期望 $expectSha256, 实际 $actual ($url)');
  }

  if (await dest.exists()) await dest.delete();
  await tmp.rename(dest.path);
}

/// 文件内容的 sha256（hex 小写）。
Future<String> sha256OfFile(File f) async {
  final bytes = await f.readAsBytes();
  return sha256.convert(bytes).toString();
}
