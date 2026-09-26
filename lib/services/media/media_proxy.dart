/// 媒体代理器 — 统一的 mediaId → 媒体字节 解析层
///
/// 三层架构的中层。职责：
/// - `resolve(mediaId)`：查本地 MediaStore → 命中返回；miss 返回 miss
///   （历史回源端点已随 ComfyUI 托管下线移除，所有来源均不可回源）。
/// - `upload(...)`：用户上传图片/视频，生成 mediaId + 存本地 + 写 media_items
///   (localOnly=1)，返回 mediaId 供展示层使用。
///
/// `mediaId` 体系：
/// - 用户上传媒体 mediaId = app 本地生成 id（local_ 前缀），标记 localOnly
///
/// 依赖：MediaStore（文件层）、DatabaseConnection（media_items 表）。
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/database/database_connection.dart';
import '../../core/providers/database_providers.dart';
import '../logger_service.dart';
import 'media_store.dart';
import 'media_types.dart';

/// resolve 结果状态
enum MediaStatus { loaded, pending, failed, miss }

class MediaResult {
  final MediaStatus status;
  final int code; // HTTP 状态码（loaded/miss 时为 0）
  final MediaKind? kind;

  /// 命中时附带的本地文件路径（供 UI 直接 Image.file，避免再查一次 MediaStore）。
  final String? localPathHint;

  const MediaResult({
    required this.status,
    this.code = 0,
    this.kind,
    this.localPathHint,
  });

  bool get isLoaded => status == MediaStatus.loaded;
}

class MediaProxy {
  final MediaStore _store = MediaStore.instance;
  final DatabaseConnection _dbConn;

  /// 进程内自增计数器，避免同毫秒上传产生 id 碰撞。
  int _idCounter = 0;

  MediaProxy({required DatabaseConnection dbConn}) : _dbConn = dbConn;

  /// 读取 media_items 元数据。不存在返回 null。
  Future<MediaItem?> getItem(String mediaId) async {
    final db = await _dbConn.database;
    final rows = await db.query(
      'media_items',
      where: 'mediaId = ?',
      whereArgs: [mediaId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MediaItem.fromMap(rows.first);
  }

  /// 用户上传：生成 mediaId，存本地，写 media_items(localOnly=1)。
  /// 返回 mediaId。
  Future<String> upload(
    Uint8List bytes,
    MediaKind kind, {
    String? prompt,
  }) async {
    final mediaId = _generateLocalId();
    final file = await _store.saveBytes(mediaId, kind, bytes);
    final size = await file.length();
    final db = await _dbConn.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'media_items',
      {
        'mediaId': mediaId,
        'kind': kind.dbName,
        'source': MediaSource.localUpload.dbName,
        if (prompt != null) 'prompt': prompt,
        'createdAt': now,
        'lastAccessedAt': now,
        'localBytes': size,
        'localOnly': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return mediaId;
  }

  /// 解析 mediaId → 本地文件。
  ///
  /// 状态机：
  /// - 本地命中 → loaded
  /// - miss → miss（历史回源端点已下线，调用方展示占位）
  Future<MediaResult> resolve(String mediaId) async {
    final item = await getItem(mediaId);
    if (item == null) {
      // 元数据缺失（极少数情况，如未 register 就 resolve）→ miss
      return const MediaResult(status: MediaStatus.miss);
    }

    // 1. 本地命中
    final localFile = await _store.getFile(mediaId, item.kind);
    if (localFile != null) {
      await _touchAccess(mediaId);
      return MediaResult(
        status: MediaStatus.loaded,
        kind: item.kind,
        localPathHint: localFile.path,
      );
    }

    // 2. miss — 回源路径已随 ComfyUI 托管下线移除
    //    （v51 迁移把存量 text2img/image_to_video 记录归一为 local_upload）
    return MediaResult(status: MediaStatus.miss, kind: item.kind);
  }

  /// 删除单个媒体（缓存管理页用）。删文件 + 删元数据。
  Future<void> delete(String mediaId) async {
    final item = await getItem(mediaId);
    if (item != null) {
      await _store.delete(mediaId, item.kind);
    }
    final db = await _dbConn.database;
    await db.delete('media_items',
        where: 'mediaId = ?', whereArgs: [mediaId]);
  }

  /// 枚举所有媒体元数据（缓存管理页用），按最近访问降序。
  Future<List<MediaItem>> listAll() async {
    final db = await _dbConn.database;
    final rows = await db.query('media_items', orderBy: 'lastAccessedAt DESC');
    return rows.map(MediaItem.fromMap).toList();
  }

  Future<void> _touchAccess(String mediaId) async {
    try {
      final db = await _dbConn.database;
      await db.update(
        'media_items',
        {'lastAccessedAt': DateTime.now().millisecondsSinceEpoch},
        where: 'mediaId = ?',
        whereArgs: [mediaId],
      );
    } catch (e) {
      LoggerService.instance.d(
        'MediaProxy.touchAccess 失败: $mediaId, $e',
        category: LogCategory.cache,
        tags: ['media_proxy', 'touch_failed'],
      );
    }
  }

  /// 生成用户上传媒体的本机 id（与 backend task_id 隔离命名空间）。
  /// 前缀 local_ 便于人工辨识，后接时间戳+进程内自增计数器，
  /// 规避旧版 ts.remainder(9973) 伪随机在同毫秒内多次调用产生的碰撞。
  String _generateLocalId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'local_${ts}_${++_idCounter}';
  }
}

/// MediaProxy Provider（手写，避免 codegen）。
/// 依赖 databaseConnectionProvider（keepAlive 全局单例）。
final mediaProxyProvider = Provider<MediaProxy>((ref) {
  final dbConn = ref.watch(databaseConnectionProvider);
  return MediaProxy(dbConn: dbConn);
});
