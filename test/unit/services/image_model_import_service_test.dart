/// ImageModelImportService 单元测试
///
/// 覆盖 [ImageModelImportService.importFromPath] 的校验链路（不弹文件选择器）：
/// - 文件不存在 → ImageModelImportException
/// - 扩展名非 .gguf → ImageModelImportException
/// - 文件头 magic 错误 → ImageModelImportException
/// - 正常 gguf 文件 → 复制到 image_models 目录，返回 fileSize 与路径
/// - [deleteModelFile] 仅允许删 image_models 目录内的文件（安全护栏）
///
/// 通过 inMemory 临时目录隔离测试产物（[Directory.systemTemp.createTempSync]）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:novel_app/services/image_model_import_service.dart';
import '../../helpers/path_provider_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpRoot;
  late PathProviderPlatform original;

  setUp(() async {
    original = PathProviderPlatform.instance;
    tmpRoot = Directory.systemTemp.createTempSync('img_model_test_');
    // 拦截 getApplicationDocumentsDirectory → 临时目录
    PathProviderPlatform.instance = FakePathProviderPlatform(tmpRoot.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = original;
    if (tmpRoot.existsSync()) tmpRoot.deleteSync(recursive: true);
  });

  /// 在 tmpRoot 写一个伪造 gguf 文件（magic + 若干零字节），返回源路径
  String writeFakeGguf({String name = 'fake.gguf', List<int>? extraBytes}) {
    final file = File(p.join(tmpRoot.path, name));
    final bytes = <int>[0x47, 0x47, 0x55, 0x46, ...?extraBytes];
    file.writeAsBytesSync(bytes);
    return file.path;
  }
  /// 写一个最小合法 safetensors（单 F32 张量）
  String writeFakeSafetensors({String name = 'fake.safetensors'}) {
    final header =
        '{"w":{"dtype":"F32","shape":[4],"data_offsets":[0,16]}}';
    final buf = BytesBuilder()
      ..add((ByteData(8)..setUint64(0, header.length, Endian.little))
          .buffer
          .asUint8List())
      ..add(header.codeUnits)
      ..add(Uint8List(16));
    final file = File(p.join(tmpRoot.path, name))..writeAsBytesSync(buf.toBytes());
    return file.path;
  }

  group('importFromPath 校验', () {
    test('文件不存在 → 抛 ImageModelImportException', () async {
      expect(
        () => ImageModelImportService.instance.importFromPath(
          p.join(tmpRoot.path, 'missing.gguf'),
        ),
        throwsA(isA<ImageModelImportException>()),
      );
    });

    test('扩展名不是 .gguf → 抛 ImageModelImportException', () async {
      final src = File(p.join(tmpRoot.path, 'not_gguf.bin'))
        ..writeAsBytesSync([0x47, 0x47, 0x55, 0x46, 0, 0]);
      expect(
        () => ImageModelImportService.instance.importFromPath(src.path),
        throwsA(isA<ImageModelImportException>()),
      );
    });

    test('合法 safetensors → needsConversion=true，副本在 model_downloads',
        () async {
      final src = writeFakeSafetensors();
      final r = await ImageModelImportService.instance.importFromPath(src);
      expect(r.needsConversion, isTrue);
      expect(r.filePath, contains('model_downloads'));
      expect(r.filePath, endsWith('.safetensors'));
      expect(File(r.filePath).existsSync(), isTrue);
    });

    test('损坏 safetensors → 抛 ImageModelImportException', () async {
      final src = File(p.join(tmpRoot.path, 'broken.safetensors'))
        ..writeAsBytesSync([1, 2, 3, 4]);
      try {
        await ImageModelImportService.instance.importFromPath(src.path);
        fail('应抛异常');
      } on ImageModelImportException catch (e) {
        expect(e.message, contains('safetensors'));
      }
    });

    test('文件头 magic 不对 → 抛 ImageModelImportException', () async {
      final src = File(p.join(tmpRoot.path, 'bad.gguf'))
        ..writeAsBytesSync([0x00, 0x00, 0x00, 0x00, 0x00]);
      try {
        await ImageModelImportService.instance.importFromPath(src.path);
        fail('应抛异常');
      } on ImageModelImportException catch (e) {
        expect(e.message, contains('文件头校验失败'));
      }
    });

    test('合法 gguf → 复制到 image_models 目录并返回元数据', () async {
      final extra = List<int>.filled(1024, 0); // 1KB 文件体
      final src = writeFakeGguf(extraBytes: extra);

      final result = await ImageModelImportService.instance.importFromPath(
        src,
        originalFileName: '古风.gguf',
      );

      expect(result.originalFileName, '古风.gguf');
      expect(result.fileSize, 4 + 1024);
      expect(result.filePath, contains(p.join(tmpRoot.path, 'image_models')));
      expect(result.filePath, endsWith('.gguf'));

      // 目标文件确实存在且内容一致
      final copied = File(result.filePath);
      expect(copied.existsSync(), true);
      expect(copied.lengthSync(), 4 + 1024);
      expect(copied.readAsBytesSync().sublist(0, 4), [0x47, 0x47, 0x55, 0x46]);
    });

    test('originalFileName 原样保留（去后缀由调用方负责）', () async {
      final src = writeFakeGguf(name: '古风.gguf');
      final result = await ImageModelImportService.instance
          .importFromPath(src, originalFileName: '古风.gguf');
      expect(result.originalFileName, '古风.gguf');
    });
  });

  group('deleteModelFile 安全护栏', () {
    test('只删 image_models 目录内的文件', () async {
      // 准备：tmpRoot/foo.gguf（不在 image_models 内）+ image_models/x.gguf
      final outside = File(p.join(tmpRoot.path, 'outside.gguf'))
        ..writeAsBytesSync([0x47, 0x47, 0x55, 0x46]);
      final insideSrc = writeFakeGguf();
      final inside = await ImageModelImportService.instance
          .importFromPath(insideSrc);
      final insidePath = inside.filePath;

      await ImageModelImportService.instance.deleteModelFile(outside.path);
      expect(outside.existsSync(), true, reason: 'image_models 外文件不动');

      await ImageModelImportService.instance.deleteModelFile(insidePath);
      expect(File(insidePath).existsSync(), false, reason: 'image_models 内文件删掉');
    });

    test('空路径 / 路径指向 image_models 外 → 无操作', () async {
      // 空路径
      await ImageModelImportService.instance.deleteModelFile('');
      // 路径穿越尝试：tmpRoot 上层
      final escapePath = p.normalize(p.join(tmpRoot.parent.path, 'evil.gguf'));
      await ImageModelImportService.instance.deleteModelFile(escapePath);
      // 不抛异常即通过（护栏命中时不删除任何文件）
    });
  });
}