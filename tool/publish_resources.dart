// 生成动态资源 manifest（app-resources/v1/manifest.json）
//
// 用法：
//   dart run tool/publish_resources.dart \
//     --sd-so <libsds.so 路径> \
//     [--fonts-dir assets/fonts] \
//     [--base-url <对象存储公开前缀>] \
//     [--out tool/app_resources/dist]
//
// 产物：
//   <out>/manifest.json        —— 上传到 bucket 的 app-resources/v1/manifest.json
//   <out>/ 上会列出需要一并上传的文件清单（字体 + libsds.so）
//
// 上传（二选一）：
//   1. 云开发控制台 → 静态托管/云存储，把 dist 下文件传到对应路径，
//      bucket 与 OCR 模型一致（公开读）：
//      7768-whimread-dev-d0gm4oi0z3099082d-1256733196（tcb.qcloud.la）
//   2. tcb CLI: tcb storage upload <本地文件> <云端路径>
//
// 注意：
//   - libsds.so 从 gradle 构建产物收集：
//     android/app/build/intermediates/cxx/*/obj/arm64-v8a/libsds.so
//     （packagingOptions 已把它排除出 APK，但 CMake 产物仍在 intermediates）
//   - 每次更新资源后必须重新上传 manifest.json，否则客户端拿旧 sha256 校验失败
//   - manifest_version 递增会让「跳过」标记失效，用户会再看到一次引导页

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> args) async {
  String? sdSoPath;
  var fontsDir = 'assets/fonts';
  var baseUrl =
      'https://7768-whimread-dev-d0gm4oi0z3099082d-1256733196.tcb.qcloud.la';
  var outDir = 'tool/app_resources/dist';

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--sd-so':
        sdSoPath = args[++i];
      case '--fonts-dir':
        fontsDir = args[++i];
      case '--base-url':
        baseUrl = args[++i].replaceAll(RegExp(r'/+$'), '');
      case '--out':
        outDir = args[++i];
    }
  }
  if (sdSoPath == null) {
    stderr.writeln('缺少 --sd-so <libsds.so 路径>');
    exit(2);
  }

  final soFile = File(sdSoPath);
  if (!await soFile.exists()) {
    stderr.writeln('libsds.so 不存在: $sdSoPath');
    exit(2);
  }

  const fontFiles = [
    'NotoSerifSC-Regular.ttf',
    'NotoSerifSC-Bold.ttf',
    'NotoSansSC-Regular.ttf',
    'NotoSansSC-Bold.ttf',
  ];

  Future<Map<String, dynamic>> fileEntry(
      String cloudPrefix, File f, String name) async {
    final bytes = await f.readAsBytes();
    return {
      'name': name,
      'url': '$cloudPrefix/$name',
      'sha256': sha256.convert(bytes).toString(),
      'size': bytes.length,
    };
  }

  // 1. ui_fonts
  final fonts = <Map<String, dynamic>>[];
  for (final name in fontFiles) {
    final f = File('$fontsDir/$name');
    if (!await f.exists()) {
      stderr.writeln('字体缺失: ${f.path}');
      exit(2);
    }
    fonts.add(await fileEntry('$baseUrl/app-resources/v1/ui_fonts', f, name));
  }

  // 2. sd_engine
  final sd = await fileEntry(
      '$baseUrl/app-resources/v1/sd_engine', soFile, 'libsds.so');

  final manifest = {
    'manifest_version': 1,
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'resources': [
      {
        'id': 'ui_fonts',
        'version': DateTime.now().toUtc().toIso8601String(),
        'files': fonts,
      },
      {
        'id': 'sd_engine',
        'version': DateTime.now().toUtc().toIso8601String(),
        'files': [sd],
      },
    ],
  };

  final out = Directory(outDir);
  if (!await out.exists()) await out.create(recursive: true);
  final manifestFile = File('${out.path}/manifest.json');
  await manifestFile.writeAsString(const JsonEncoder.withIndent('  ')
      .convert(manifest));

  // 待上传文件对照表（云端路径 → 本地路径）
  final buffer = StringBuffer()
    ..writeln('# 需上传到 bucket 的文件（云端路径 → 本地路径）')
    ..writeln('app-resources/v1/manifest.json → ${manifestFile.path}');
  for (final f in fonts) {
    buffer.writeln(
        'app-resources/v1/ui_fonts/${f['name']} → $fontsDir/${f['name']}');
  }
  buffer.writeln('app-resources/v1/sd_engine/libsds.so → $sdSoPath');
  await File('${out.path}/UPLOAD_LIST.txt').writeAsString(buffer.toString());

  stdout.writeln('manifest 已生成: ${manifestFile.path}');
  stdout.writeln('上传清单: ${out.path}/UPLOAD_LIST.txt');
  stdout.writeln(
      '上传后客户端从 $baseUrl/app-resources/v1/manifest.json 拉取');
}
