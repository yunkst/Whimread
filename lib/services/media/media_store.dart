/// 媒体本地存储 — 纯文件存取层
///
/// 单例。文件存放在 `<application_documents>/media/<mediaId>.<ext>`，
/// ext 由 kind 决定（image→png，video→mp4）。
///
/// 职责边界：
/// - 只做文件读写/枚举/删除，**不碰数据库元数据**（元数据由 MediaProxy 经
///   media_items 表管理），**不碰网络**（回源由 MediaProxy 负责）。
/// - mediaId 来自 backend task_id（AI 生成）或 app 本地生成 id（用户上传），
///   均不含路径分隔符，按文件名拼接规避路径穿越。
///
/// 替代旧 AgentImageCacheService（仅服务 agent 文生图、按 imageId 命名、
/// 固定 png 扩展名）。旧服务在所有调用点迁移到 MediaStore 后删除。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../logger_service.dart';
import 'media_types.dart';

class MediaStore {
  static final MediaStore instance = MediaStore._();

  MediaStore._();

  /// 缓存根目录名（位于应用文档目录下）
  static const String _dirName = 'media';

  /// 缓存根目录惰性解析
  Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 拼出 `<mediaId>.<ext>` 完整路径。
  Future<File> _pathFor(String mediaId, MediaKind kind) async {
    final root = await _rootDir();
    final safeName = '$mediaId.${kind.ext}';
    return File('${root.path}${Platform.pathSeparator}$safeName');
  }

  /// 读取本地文件。命中返回 File，未命中返回 null。
  Future<File?> getFile(String mediaId, MediaKind kind) async {
    try {
      final file = await _pathFor(mediaId, kind);
      if (await file.exists() && (await file.length()) > 0) {
        return file;
      }
      return null;
    } catch (e) {
      LoggerService.instance.d(
        'MediaStore.getFile 失败: mediaId=$mediaId, $e',
        category: LogCategory.cache,
        tags: ['media_store', 'read_failed'],
      );
      return null;
    }
  }

  /// 读取字节。命中返回 bytes，未命中返回 null。
  Future<Uint8List?> getBytes(String mediaId, MediaKind kind) async {
    final file = await getFile(mediaId, kind);
    if (file == null) return null;
    return await file.readAsBytes();
  }

  /// 写入字节，返回保存后的 File。幂等：重复写覆盖。
  Future<File> saveBytes(
      String mediaId, MediaKind kind, Uint8List bytes) async {
    final file = await _pathFor(mediaId, kind);
    await file.writeAsBytes(bytes, flush: true);
    LoggerService.instance.d(
      'MediaStore.saveBytes: mediaId=$mediaId kind=$kind (${bytes.length} bytes)',
      category: LogCategory.cache,
      tags: ['media_store', 'write'],
    );
    return file;
  }

  /// 删除本地文件。不存在视为成功。
  Future<void> delete(String mediaId, MediaKind kind) async {
    try {
      final file = await _pathFor(mediaId, kind);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      LoggerService.instance.d(
        'MediaStore.delete 失败: mediaId=$mediaId, $e',
        category: LogCategory.cache,
        tags: ['media_store', 'delete_failed'],
      );
    }
  }

  /// 枚举本地所有媒体文件（缓存管理页用）。
  Future<List<MediaFileEntry>> listAll() async {
    final root = await _rootDir();
    if (!await root.exists()) return const [];
    final entries = <MediaFileEntry>[];
    await for (final entity in root.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      if (dot <= 0) continue;
      final mediaId = name.substring(0, dot);
      final ext = name.substring(dot + 1).toLowerCase();
      final kind = MediaKind.fromExt(ext);
      final size = await entity.length();
      entries.add(MediaFileEntry(
        mediaId: mediaId,
        kind: kind,
        file: entity,
        sizeBytes: size,
      ));
    }
    return entries;
  }

  /// 本地媒体总占用字节
  Future<int> usedSpace() async {
    final entries = await listAll();
    return entries.fold<int>(0, (s, e) => s + e.sizeBytes);
  }
}
