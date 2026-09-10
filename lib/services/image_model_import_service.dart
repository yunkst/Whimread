/// 生图模型文件导入服务
///
/// 职责：把用户通过系统文件选择器选中的 .gguf 模型文件校验后复制到应用
/// 私有目录，返回 (路径, 字节数) 供 image_models 表落库。
///
/// 设计要点：
/// - 大文件（SD1.5 量化 gguf 约 1-2GB）：withData=false 只拿路径，用
///   dart:io File.copy 原生复制，绝不把字节读进内存。
/// - 校验两道关卡：扩展名 .gguf + 文件头 magic（前 4 字节 "GGUF"）。
/// - 复制目标名用时间戳，避免用户文件名里的非法字符/重名问题；
///   删除时 [deleteModelFile] 只允许删 image_models 目录内的文件。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'conversion/gguf_writer.dart' show kGgufMagic;
import 'conversion/safetensors_reader.dart';

/// 导入失败（UI 直接把 message 展示给用户）
class ImageModelImportException implements Exception {
  final String message;
  const ImageModelImportException(this.message);

  @override
  String toString() => message;
}

/// 导入结果
class ImageModelImportResult {
  /// 应用私有目录内的模型文件绝对路径
  final String filePath;

  /// 文件字节数
  final int fileSize;

  /// 用户原始文件名（仅用于预填名字/展示）
  final String originalFileName;

  /// true = safetensors 源文件，需要经端上转换（Q8_0）产出 gguf 后才可用；
  /// 调用方应建 status=converting 的模型行并调下载服务的转换入口
  final bool needsConversion;

  const ImageModelImportResult({
    required this.filePath,
    required this.fileSize,
    required this.originalFileName,
    this.needsConversion = false,
  });
}

class ImageModelImportService {
  ImageModelImportService._();

  static final ImageModelImportService instance = ImageModelImportService._();

  /// 模型文件存放目录名（位于应用文档目录下）
  static const String _dirName = 'image_models';

  /// 弹系统文件选择器 → 校验 → 复制到应用私有目录。
  ///
  /// 用户取消返回 null；校验失败抛 [ImageModelImportException]。
  /// 支持 .gguf（直接可用）与 .safetensors（needsConversion=true）。
  Future<ImageModelImportResult?> pickAndImport() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      // 绝不 withData：模型文件 1-12GB，只取路径
      withData: false,
    );
    final pickedFile = picked?.files.single;
    final sourcePath = pickedFile?.path;
    if (pickedFile == null || sourcePath == null || sourcePath.isEmpty) {
      return null;
    }

    return importFromPath(sourcePath, originalFileName: pickedFile.name);
  }

  /// 从已有路径导入（跳过文件选择器，便于测试与浏览器下载入口复用）。
  Future<ImageModelImportResult> importFromPath(
    String sourcePath, {
    String? originalFileName,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const ImageModelImportException('所选文件不存在，请重新选择。');
    }

    final fileName = originalFileName ?? p.basename(sourcePath);
    final lower = fileName.toLowerCase();
    final isGguf = lower.endsWith('.gguf');
    final isSafetensors = lower.endsWith('.safetensors');
    if (!isGguf && !isSafetensors) {
      throw const ImageModelImportException(
          '仅支持 .gguf 或 .safetensors 格式的模型文件。');
    }

    if (isGguf) {
      // 文件头 magic 校验：读前 4 字节，拒绝改扩展名的假 gguf
      final raf = await source.open(mode: FileMode.read);
      try {
        final header = await raf.read(4);
        var matchesMagic = header.length == 4;
        for (var i = 0; matchesMagic && i < 4; i++) {
          if (header[i] != kGgufMagic[i]) matchesMagic = false;
        }
        if (!matchesMagic) {
          throw const ImageModelImportException(
              '文件头校验失败：不是有效的 GGUF 模型文件（可能仅改了扩展名）。');
        }
      } finally {
        await raf.close();
      }
    } else {
      // safetensors：解析 header 校验（只读头部几 MB，12GB 文件也很快）
      try {
        await parseSafetensors(source);
      } on FormatException catch (e) {
        throw ImageModelImportException('不是有效的 safetensors 文件：${e.message}');
      }
    }

    final size = await source.length();

    // 复制到应用私有目录（时间戳命名，杜绝非法字符与重名）。
    // safetensors 放 model_downloads（转换中间产物目录），gguf 放 image_models。
    final Directory destDir;
    if (isSafetensors) {
      final docs = await getApplicationDocumentsDirectory();
      destDir = Directory(p.join(docs.path, 'model_downloads'));
    } else {
      destDir = await _ensureModelDir();
    }
    if (!await destDir.exists()) await destDir.create(recursive: true);

    final destExt = isSafetensors ? 'safetensors' : 'gguf';
    final destPath = p.join(destDir.path,
        'model_${DateTime.now().millisecondsSinceEpoch}.$destExt');
    await source.copy(destPath);
    final copiedSize = await File(destPath).length();

    return ImageModelImportResult(
      filePath: destPath,
      fileSize: copiedSize > 0 ? copiedSize : size,
      originalFileName: fileName,
      needsConversion: isSafetensors,
    );
  }

  /// 删除应用私有目录内的模型文件。
  ///
  /// 安全护栏：只删 image_models 目录内的文件，避免外部路径误删。
  Future<void> deleteModelFile(String filePath) async {
    if (filePath.isEmpty) return;
    final dir = await _ensureModelDir();
    final canonicalFile = File(p.normalize(filePath));
    if (!p.isWithin(dir.path, canonicalFile.path)) return;
    if (await canonicalFile.exists()) {
      await canonicalFile.delete();
    }
  }

  Future<Directory> _ensureModelDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _dirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 已落盘的模型文件路径（image_models 目录下，时间戳命名）。
  ///
  /// 下载/转换链路和手动导入共用同款命名规范，避免转换产物落到不同目录
  /// 或重名覆盖。
  static Future<String> finalizedModelPath(String ext) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _dirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return p.join(dir.path,
        'model_${DateTime.now().millisecondsSinceEpoch}.$ext');
  }
}
