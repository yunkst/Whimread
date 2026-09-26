/// Local Dream 嵌入式引擎单元测试
///
/// 覆盖：
/// - model_pack：三类包的必需文件清单、目录缺失检查
/// - 内置目录：与 Local Dream 同款（数量/分组/SoC 芯片后缀 URL/SDXL 门控）
/// - engine_manager：启动命令行参数矩阵（sd15cpu 无 lib_dir / QNN 类型有）
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/local_dream_embedded/engine_manager.dart';
import 'package:novel_app/services/local_dream_embedded/model_pack.dart';

void main() {
  group('LocalDreamPackType', () {
    test('dbName 与引擎 --type 字面量一致', () {
      expect(LocalDreamPackType.sd15Cpu.dbName, 'sd15cpu');
      expect(LocalDreamPackType.sd15Npu.dbName, 'sd15npu');
      expect(LocalDreamPackType.sdxl.dbName, 'sdxl');
      expect(LocalDreamPackType.parse('sd15npu'), LocalDreamPackType.sd15Npu);
      expect(LocalDreamPackType.parse('unknown'), isNull);
    });

    test('必需文件清单：SD1.5 四件，SDXL 九件', () {
      expect(LocalDreamPackType.sd15Npu.requiredFiles,
          ['tokenizer.json', 'clip_v2.mnn', 'pos_emb.bin', 'token_emb.bin']);
      expect(LocalDreamPackType.sdxl.requiredFiles, hasLength(9));
      expect(LocalDreamPackType.sdxl.requiredFiles, contains('unet.bin'));
    });

    test('QNN 库需求与画布尺寸', () {
      expect(LocalDreamPackType.sd15Cpu.needsQnnLibs, isFalse);
      expect(LocalDreamPackType.sd15Npu.needsQnnLibs, isTrue);
      expect(LocalDreamPackType.sdxl.generationSize, 1024);
      expect(LocalDreamPackType.sd15Npu.generationSize, 512);
    });
  });

  group('芯片后缀（对齐 Local Dream chipsetModelSuffixes）', () {
    test('已知 SoC 映射', () {
      expect(chipsetSuffixForSoc('SM8450'), '8gen1');
      expect(chipsetSuffixForSoc('SM8550'), '8gen2');
      expect(chipsetSuffixForSoc('SM8750'), '8gen2');
      expect(chipsetSuffixForSoc('SM8850P'), '8gen2');
    });

    test('未知 SM 前缀回退 min，非骁龙为 null', () {
      expect(chipsetSuffixForSoc('SM9999'), 'min');
      expect(chipsetSuffixForSoc('MT6989'), isNull); // 联发科
      expect(chipsetSuffixForSoc(''), isNull);
    });

    test('SDXL 门控：仅 8 Gen 3+ 集合', () {
      expect(sdxlCapableSocs.contains('SM8750'), isTrue);
      expect(sdxlCapableSocs.contains('SM8650'), isTrue);
      expect(sdxlCapableSocs.contains('SM8550'), isFalse);
    });
  });

  group('内置目录（对齐 Local Dream ModelRepository）', () {
    test('总数 13：SDXL 4 + NPU 5 + CPU 5（去掉 SDXL 门控前）', () {
      expect(localDreamPackCatalog, hasLength(14));
      expect(
          localDreamPackCatalog.where((e) => e.sdxlOnly), hasLength(4));
      expect(
          localDreamPackCatalog
              .where((e) => e.type == LocalDreamPackType.sd15Npu),
          hasLength(5));
      expect(
          localDreamPackCatalog
              .where((e) => e.type == LocalDreamPackType.sd15Cpu),
          hasLength(5));
    });

    test('catalogForSoc：8gen3 显示 SDXL；低端只见 NPU+CPU；联发科只见 CPU',
        () {
      final flagship = catalogForSoc('SM8750');
      expect(flagship.where((e) => e.sdxlOnly), hasLength(4));
      expect(flagship, hasLength(14));

      final older = catalogForSoc('SM8450');
      expect(older.any((e) => e.sdxlOnly), isFalse);
      expect(older.where((e) => e.type == LocalDreamPackType.sd15Npu),
          hasLength(5));

      final mtk = catalogForSoc('MT6989');
      expect(mtk.every((e) => e.type == LocalDreamPackType.sd15Cpu), isTrue);
    });

    test('resolveZipUrl：NPU zip 按芯片后缀替换，SDXL 固定 URL', () {
      final anything = localDreamPackCatalog.firstWhere((e) => e.id == 'anythingv5');
      expect(
        anything.resolveZipUrl(
            baseUrl: LocalDreamBaseUrl.huggingface, socSuffix: '8gen1'),
        'https://huggingface.co/xororz/sd-qnn/resolve/main/'
        'AnythingV5_qnn2.28_8gen1.zip',
      );
      final illustrious =
          localDreamPackCatalog.firstWhere((e) => e.id == 'illustrious_v16');
      expect(
        illustrious.resolveZipUrl(
            baseUrl: LocalDreamBaseUrl.hfMirror, socSuffix: '8gen2'),
        'https://hf-mirror.com/xororz/sdxl-qnn/resolve/main/'
        'illustrious_v16_qnn2.28_8gen3.zip',
      );
      // 非骁龙 SoC：NPU 包不可下载
      expect(
        anything.resolveZipUrl(
            baseUrl: LocalDreamBaseUrl.huggingface, socSuffix: null),
        isNull,
      );
    });
  });

  group('LocalDreamModelPack.missingFiles', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ld_pack_test');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('齐全 → 空列表；缺文件 → 列出缺失项', () {
      for (final name in LocalDreamPackType.sd15Npu.requiredFiles) {
        File('${tempDir.path}${Platform.pathSeparator}$name')
            .writeAsStringSync('x');
      }
      expect(
        LocalDreamModelPack.missingFiles(
            tempDir.path, LocalDreamPackType.sd15Npu),
        isEmpty,
      );

      File('${tempDir.path}${Platform.pathSeparator}clip_v2.mnn')
          .deleteSync();
      expect(
        LocalDreamModelPack.missingFiles(
            tempDir.path, LocalDreamPackType.sd15Npu),
        ['clip_v2.mnn'],
      );
    });

    test('目录不存在 → 全部必需文件缺失', () {
      expect(
        LocalDreamModelPack.missingFiles(
            '${tempDir.path}${Platform.pathSeparator}nope',
            LocalDreamPackType.sdxl),
        hasLength(9),
      );
    });
  });

  group('LocalDreamEngineManager.buildEngineArgs', () {
    test('sd15cpu：无 --lib_dir', () {
      final args = LocalDreamEngineManager.buildEngineArgs(
        type: LocalDreamPackType.sd15Cpu,
        modelDir: '/models/p1',
        executablePath: '/native/libstable_diffusion_core.so',
        runtimeDir: '/runtime',
      );
      expect(args, [
        '/native/libstable_diffusion_core.so',
        '--type', 'sd15cpu',
        '--model_dir', '/models/p1',
        '--port', '8081',
      ]);
    });

    test('QNN 类型：带 --lib_dir；缺运行时目录抛异常', () {
      final args = LocalDreamEngineManager.buildEngineArgs(
        type: LocalDreamPackType.sdxl,
        modelDir: '/models/p2',
        executablePath: '/native/libstable_diffusion_core.so',
        runtimeDir: '/runtime',
      );
      expect(args.sublist(args.indexOf('--lib_dir')),
          ['--lib_dir', '/runtime']);
      expect(args[args.indexOf('--type') + 1], 'sdxl');

      expect(
        () => LocalDreamEngineManager.buildEngineArgs(
          type: LocalDreamPackType.sdxl,
          modelDir: '/models/p2',
          executablePath: '/native/x',
        ),
        throwsA(isA<LocalDreamEngineException>()),
      );
    });
  });
}
