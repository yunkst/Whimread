/// 真实 checkpoint 全量转换验证脚本（开发用）
///
/// 跑完整的 safetensors → GGUF(Q8_0) 转换链路（isolate + 进度回调），
/// 用真实 Civitai/官方 checkpoint 验证转换器产物可用。
///
/// 运行：
/// ```
/// dart run tool/convert_checkpoint.dart <input.safetensors> <output.gguf>
/// ```
library;

import 'dart:io';

import 'package:novel_app/services/conversion/model_converter.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('用法: dart run tool/convert_checkpoint.dart '
        '<input.safetensors> <output.gguf>');
    exit(2);
  }
  final input = File(args[0]);
  final output = args[1];
  if (!input.existsSync()) {
    stderr.writeln('输入文件不存在: ${input.path}');
    exit(1);
  }

  final sw = Stopwatch()..start();
  stdout.writeln('转换开始: ${input.path}');
  stdout.writeln('       → $output');

  // 先出转换计划（架构识别 + 估算）
  try {
    final plan = await planConversion(input);
    stdout.writeln('架构: ${plan.detection.arch.displayName}'
        '${plan.detection.isVPrediction ? " (v-pred)" : ""} · '
        '估算输出 ${(plan.estimatedOutputSize / 1024 / 1024 / 1024).toStringAsFixed(2)} GB');
  } on ConversionException catch (e) {
    stderr.writeln('转换计划失败: ${e.message}');
    exit(3);
  }

  try {
    final result = await runConversion(
      sourcePath: input.path,
      outputPath: output,
      onProgress: (p) {
        // \r 单行刷新进度
        stdout.write('\r[${p.percent.toString().padLeft(3)}%] '
            '张量 ${p.currentTensor}/${p.totalTensors}: '
            '${p.tensorName.length > 48 ? p.tensorName.substring(0, 48) : p.tensorName}'
            '        ');
        if (p.currentTensor == p.totalTensors) stdout.writeln();
      },
    );
    sw.stop();
    final inSize = input.lengthSync();
    final outSize = File(output).lengthSync();
    final ratio = (outSize / inSize * 100).toStringAsFixed(1);
    stdout.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    stdout.writeln('转换完成 ✓  耗时 ${sw.elapsed}');
    stdout.writeln('架构: ${result.arch.displayName} · '
        '量化 ${result.quantizedCount} / 保留 ${result.keptCount}');
    stdout.writeln('输出: $output');
    stdout.writeln('大小: ${(inSize / 1024 / 1024).toStringAsFixed(0)} MB → '
        '${(outSize / 1024 / 1024).toStringAsFixed(0)} MB ($ratio%)');
  } on ConversionException catch (e) {
    sw.stop();
    stderr.writeln('\n转换失败（耗时 ${sw.elapsed}）: ${e.message}');
    exit(4);
  }
}
