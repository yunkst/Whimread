/// safetensors header 检查脚本（开发用）
///
/// 只读 header（不载入数据），输出架构识别结果 + 张量统计。
/// 用真实 Civitai checkpoint 验证 [detectArch]。
///
/// 运行：
/// ```
/// dart run tool/inspect_safetensors.dart <file-or-dir> [...]
/// ```
///
/// 目录会递归枚举 .safetensors 文件（跳过 ._____temp 等）。
library;

import 'dart:io';

import 'package:novel_app/services/conversion/arch_detector.dart';
import 'package:novel_app/services/conversion/safetensors_reader.dart';
import 'package:novel_app/services/conversion/model_converter.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法: dart run tool/inspect_safetensors.dart <file-or-dir>');
    exit(2);
  }

  final files = <File>[];
  for (final arg in args) {
    final entity = FileSystemEntity.typeSync(arg);
    if (entity == FileSystemEntityType.directory) {
      files.addAll(Directory(arg)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.safetensors')));
    } else if (entity == FileSystemEntityType.file) {
      files.add(File(arg));
    }
  }

  if (files.isEmpty) {
    stderr.writeln('未找到 .safetensors 文件');
    exit(1);
  }

  for (final f in files) {
    stdout.writeln('━━━ ${f.path.split(Platform.pathSeparator).last} '
        '(${(f.lengthSync() / 1024 / 1024 / 1024).toStringAsFixed(2)} GB)');
    try {
      final st = await parseSafetensors(f);
      final detection = detectArch(st.tensors.map((t) => t.name));

      // 转换计划（量化/保留统计 + 估算输出大小）
      String planInfo;
      if (detection.isSupported) {
        try {
          final plan = await planConversion(f);
          planInfo = '可转换 · 估算输出 '
              '${(plan.estimatedOutputSize / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
        } on ConversionException catch (e) {
          planInfo = '不可转换: ${e.message}';
        }
      } else {
        planInfo = '不支持';
      }

      stdout.writeln('  架构: ${detection.arch.displayName}'
          '${detection.isVPrediction ? " (v-pred)" : ""} · $planInfo');
      stdout.writeln('  张量数: ${st.tensors.length}');
      if (st.metadata.isNotEmpty) {
        stdout.writeln('  metadata: ${st.metadata.keys.take(5).join(", ")}');
      }

      // 架构特征张量名采样（前缀分布）
      final prefixes = <String, int>{};
      for (final t in st.tensors) {
        final parts = t.name.split('.');
        final prefix = parts.take(2).join('.');
        prefixes[prefix] = (prefixes[prefix] ?? 0) + 1;
      }
      final top = prefixes.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in top.take(6)) {
        stdout.writeln('    ${e.key}: ${e.value}');
      }
    } on FormatException catch (e) {
      stdout.writeln('  解析失败: ${e.message}');
    }
    stdout.writeln();
  }
}
