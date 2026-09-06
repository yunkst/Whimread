/// 媒体代理器 — 统一的 mediaId → 媒体字节 解析层
///
/// 三层架构的中层。职责：
/// - `resolve(mediaId)`：查本地 MediaStore → 命中返回；miss 按 source 回源后端
///   → 拿到字节存本地 → 更新 media_items.lastAccessedAt/localBytes → 返回。
/// - `register(...)`：AI 提交任务时调用，写 media_items 元数据（含 source），
///   使后续 resolve 知道去哪个端点回源。
/// - `upload(...)`：用户上传图片/视频，生成 mediaId + 存本地 + 写 media_items
///   (localOnly=1)，返回 mediaId 供展示层使用。
///
/// `mediaId` 体系：
/// - AI 生成媒体 mediaId = backend task_id（与旧 imageId 冗余设计不同，
///   本代理器直接用 task_id 作统一句柄，不再额外生成 imageId）
/// - 用户上传媒体 mediaId = app 本地生成 id（local_ 前缀），标记 localOnly
///
/// 依赖：MediaStore（文件层）、DatabaseConnection（media_items 表）、
/// ApiServiceWrapper（回源）。
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/database/database_connection.dart';
import '../../core/providers/database_providers.dart';
import '../../core/providers/services/network_service_providers.dart';
import '../api_service_wrapper.dart';
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
  final ApiServiceWrapper _api;

  /// 进程内自增计数器，避免同毫秒上传产生 id 碰撞。
  int _idCounter = 0;

  MediaProxy({
    required DatabaseConnection dbConn,
    required ApiServiceWrapper api,
  })  : _dbConn = dbConn,
        _api = api;

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

  /// 写入/覆盖 media_items 元数据（AI 提交任务时调用）。
  Future<void> register({
    required String mediaId,
    required MediaKind kind,
    required MediaSource source,
    String? prompt,
    String? modelName,
  }) async {
    final db = await _dbConn.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'media_items',
      {
        'mediaId': mediaId,
        'kind': kind.dbName,
        'source': source.dbName,
        if (prompt != null) 'prompt': prompt,
        if (modelName != null) 'modelName': modelName,
        'createdAt': now,
        'lastAccessedAt': now,
        'localBytes': 0,
        'localOnly': source == MediaSource.localUpload ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
  /// - miss + source=localUpload → miss（不可回源，调用方展示占位）
  /// - miss + source=text2img → 回源 fetchText2ImgImage
  ///   - 200 → 存本地 + 更新元数据 → loaded
  ///   - 202 → pending（调用方轮询）
  ///   - 404 → failed
  ///   - 其他 → 透传 code（调用方按 failed 处理，可重试）
  /// - miss + source=imageToVideo → 回源 fetchImageToVideoVideo（同上）
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

    // 2. miss — 用户上传不可回源
    if (item.source == MediaSource.localUpload) {
      return MediaResult(status: MediaStatus.miss, kind: item.kind);
    }

    // 3. miss — 按 source 回源
    final (bytes, code) = await _fetch(item.source, mediaId);
    if (code == 200 && bytes != null && bytes.isNotEmpty) {
      final saved = await _store.saveBytes(mediaId, item.kind, bytes);
      final size = await saved.length();
      final db = await _dbConn.database;
      await db.update(
        'media_items',
        {
          'lastAccessedAt': DateTime.now().millisecondsSinceEpoch,
          'localBytes': size,
        },
        where: 'mediaId = ?',
        whereArgs: [mediaId],
      );
      return MediaResult(
        status: MediaStatus.loaded,
        kind: item.kind,
        localPathHint: saved.path,
      );
    }
    if (code == 202) {
      return MediaResult(status: MediaStatus.pending, kind: item.kind, code: 202);
    }
    if (code == 404) {
      return MediaResult(status: MediaStatus.failed, kind: item.kind, code: 404);
    }
    return MediaResult(
      status: MediaStatus.failed,
      kind: item.kind,
      code: code,
    );
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

  /// 清空所有可回源媒体（source≠localUpload）：删文件 + 删元数据，
  /// 保留用户上传（localOnly=1）。返回删除数量。
  Future<int> clearRemotable() async {
    final db = await _dbConn.database;
    final rows = await db.query(
      'media_items',
      where: 'localOnly = ?',
      whereArgs: [0],
    );
    for (final row in rows) {
      final item = MediaItem.fromMap(row);
      await _store.delete(item.mediaId, item.kind);
    }
    final count = rows.length;
    await db.delete('media_items',
        where: 'localOnly = ?', whereArgs: [0]);
    return count;
  }

  /// 拉取媒体字节（按 source 路由）。
  Future<(Uint8List?, int)> _fetch(MediaSource source, String mediaId) async {
    switch (source) {
      case MediaSource.text2img:
        return await _api.fetchText2ImgImage(mediaId);
      case MediaSource.imageToVideo:
        return await _api.fetchImageToVideoVideo(mediaId);
      case MediaSource.localUpload:
        return (null, 0); // 不可达：resolve 已在前面拦截
    }
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
/// 依赖 databaseConnectionProvider（keepAlive 全局单例）+ apiServiceWrapperProvider。
final mediaProxyProvider = Provider<MediaProxy>((ref) {
  final dbConn = ref.watch(databaseConnectionProvider);
  final api = ref.watch(apiServiceWrapperProvider);
  return MediaProxy(dbConn: dbConn, api: api);
});
