/// 封面图本地缓存服务
///
/// 单例。把书架小说的封面 URL 图下载到 `<application_documents>/cover_cache/`
/// 目录，文件名为 URL 的 MD5（无扩展名，Image.file 不依赖后缀）。
///
/// 职责边界：
/// - 只做「URL → 本地文件」的读取/下载/清理，不碰数据库（coverUrl 字段仍是
///   唯一事实来源，缓存文件可随时删除重建）。
/// - NovelCover 展示时优先读缓存；网络加载成功后异步回写，下次离线可用。
///
/// 与 MediaStore（AI 封面/用户上传，按 mediaId 管理）互不相干。
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../logger_service.dart';

class CoverCacheService {
  static final CoverCacheService instance = CoverCacheService._();

  CoverCacheService._();

  /// 缓存根目录名（位于应用文档目录下）
  static const String _dirName = 'cover_cache';

  /// 单张封面下载上限（封面图远小于此，超限视为异常响应）
  static const int _maxBytes = 10 * 1024 * 1024;

  /// 进行中的下载，按 URL 去重，避免书架网格并发重复下载同一封面
  final Map<String, Future<File?>> _inflight = {};

  Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// URL → 缓存文件路径（MD5 哈希，规避 URL 中的非法文件名字符）
  Future<File> _pathFor(String url) async {
    final root = await _rootDir();
    final name = md5.convert(url.codeUnits).toString();
    return File('${root.path}${Platform.pathSeparator}$name');
  }

  /// 读取缓存文件。命中返回 File，未命中返回 null。
  Future<File?> getFile(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    try {
      final file = await _pathFor(trimmed);
      if (await file.exists() && (await file.length()) > 0) {
        return file;
      }
      return null;
    } catch (e) {
      LoggerService.instance.d(
        'CoverCacheService.getFile 失败: $e',
        category: LogCategory.cache,
        tags: ['cover_cache', 'read_failed'],
      );
      return null;
    }
  }

  /// 确保封面已缓存：已存在直接返回；否则下载并落盘。并发调用按 URL 去重。
  ///
  /// 失败（网络异常/非图片响应/超限）返回 null，不抛异常——缓存是尽力而为，
  /// 调用方（NovelCover）在未命中时本就走网络展示或程序化回退。
  Future<File?> prefetch(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return Future.value(null);
    final existing = _inflight[trimmed];
    if (existing != null) return existing;
    final task = _download(trimmed);
    _inflight[trimmed] = task;
    return task.whenComplete(() => _inflight.remove(trimmed));
  }

  Future<File?> _download(String url) async {
    final cached = await getFile(url);
    if (cached != null) return cached;
    try {
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      final bytes = resp.bodyBytes;
      final contentType = resp.headers['content-type'] ?? '';
      final looksLikeImage = contentType.startsWith('image/') ||
          _hasImageMagic(bytes);
      if (resp.statusCode != HttpStatus.ok ||
          bytes.isEmpty ||
          bytes.length > _maxBytes ||
          !looksLikeImage) {
        LoggerService.instance.d(
          'CoverCacheService.prefetch 跳过: status=${resp.statusCode} '
          'bytes=${bytes.length} contentType=$contentType',
          category: LogCategory.cache,
          tags: ['cover_cache', 'skipped'],
        );
        return null;
      }
      final file = await _pathFor(url);
      await file.writeAsBytes(bytes, flush: true);
      LoggerService.instance.d(
        'CoverCacheService.prefetch 已缓存: ${bytes.length} bytes',
        category: LogCategory.cache,
        tags: ['cover_cache', 'write'],
      );
      return file;
    } catch (e) {
      LoggerService.instance.d(
        'CoverCacheService.prefetch 下载失败: $e',
        category: LogCategory.cache,
        tags: ['cover_cache', 'download_failed'],
      );
      return null;
    }
  }

  /// 校验常见图片格式魔数（部分站点 content-type 缺失或返回 text/html 错误页）
  static bool _hasImageMagic(List<int> b) {
    if (b.length < 4) return false;
    if (b[0] == 0xFF && b[1] == 0xD8) return true; // JPEG
    if (b[0] == 0x89 && b[1] == 0x50) return true; // PNG
    if (b[0] == 0x47 && b[1] == 0x49) return true; // GIF
    if (b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57) return true; // WEBP(RIFF)
    return false;
  }

  /// 清空全部封面缓存（缓存管理用）。单个文件删除失败不中断整体。
  Future<void> clearAll() async {
    try {
      final root = await _rootDir();
      if (!await root.exists()) return;
      await for (final entity in root.list()) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      LoggerService.instance.d(
        'CoverCacheService.clearAll 失败: $e',
        category: LogCategory.cache,
        tags: ['cover_cache', 'clear_failed'],
      );
    }
  }
}
