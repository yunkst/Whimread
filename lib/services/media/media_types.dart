/// 媒体代理器共享类型
///
/// 跨 MediaStore / MediaProxy / widget / 缓存管理页共用，独立成文件避免循环依赖。
library;

import 'dart:io';

/// 媒体类型
///
/// `dbName`/`ext` 与 `fromDbName`/`fromExt` 集中接管 kind↔字符串映射，
/// 避免 `'video'/'image'/'png'/'mp4'` 字面量散落在 proxy/store/widget 各处。
enum MediaKind {
  image,
  video;

  /// 数据库 kind 列名
  String get dbName => this == MediaKind.video ? 'video' : 'image';

  /// 本地文件扩展名（不含点）
  String get ext => this == MediaKind.video ? 'mp4' : 'png';

  static MediaKind fromDbName(String name) =>
      name == 'video' ? MediaKind.video : MediaKind.image;

  static MediaKind fromExt(String ext) =>
      ext == 'mp4' ? MediaKind.video : MediaKind.image;
}

/// 媒体来源 — localUpload 不回源。
///
/// 历史上的 text2img/imageToVideo 回源端点已随 ComfyUI 后端下线，
/// v51 迁移把存量记录归一为 local_upload，枚举随之瘦身。
enum MediaSource {
  /// 用户上传：仅本地，不回源，不可被"清空可回源缓存"批量删除
  localUpload;

  /// 数据库 source 列名
  String get dbName => 'local_upload';

  /// 未知的存量来源（如历史 text2img/image_to_video 行）按不可回源处理
  static MediaSource fromDbName(String name) => MediaSource.localUpload;
}

/// MediaStore.listAll 返回项（缓存管理页用）
class MediaFileEntry {
  final String mediaId;
  final MediaKind kind;
  final File file;
  final int sizeBytes;

  const MediaFileEntry({
    required this.mediaId,
    required this.kind,
    required this.file,
    required this.sizeBytes,
  });
}

/// media_items 表行映射（MediaProxy / 缓存管理页共用）
class MediaItem {
  final String mediaId;
  final MediaKind kind;
  final MediaSource source;
  final String? prompt;
  final String? modelName;
  final int createdAt;
  final int lastAccessedAt;
  final int localBytes;
  final bool localOnly;

  const MediaItem({
    required this.mediaId,
    required this.kind,
    required this.source,
    required this.createdAt,
    required this.lastAccessedAt,
    this.prompt,
    this.modelName,
    this.localBytes = 0,
    this.localOnly = false,
  });

  factory MediaItem.fromMap(Map<String, dynamic> m) {
    return MediaItem(
      mediaId: m['mediaId'] as String,
      kind: MediaKind.fromDbName(m['kind'] as String),
      source: MediaSource.fromDbName(m['source'] as String),
      prompt: m['prompt'] as String?,
      modelName: m['modelName'] as String?,
      createdAt: m['createdAt'] as int,
      lastAccessedAt: m['lastAccessedAt'] as int,
      localBytes: (m['localBytes'] as int?) ?? 0,
      localOnly: (m['localOnly'] as int?) == 1,
    );
  }
}
