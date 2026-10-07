/// 媒体代理器共享类型
///
/// 跨 MediaStore / MediaProxy / widget / 缓存管理页共用，独立成文件避免循环依赖。
library;

import 'dart:convert';
import 'dart:io';

/// 媒体类型（仅图片）
///
/// 视频（云端图生视频时代）已下线：解析历史 `'video'`/`'mp4'` 行时统一
/// 归为 image——那些文件已无法被任何端侧功能生成，缓存管理页仍可删除。
enum MediaKind {
  image;

  /// 数据库 kind 列名
  String get dbName => 'image';

  /// 本地文件扩展名（不含点）
  String get ext => 'png';

  static MediaKind fromDbName(String name) => MediaKind.image;

  static MediaKind fromExt(String ext) => MediaKind.image;
}

/// 媒体来源（均不回源——云端端点已下线）。
///
/// v51 曾把存量记录归一为 local_upload（当时无法区分），v57 起恢复双值：
/// AI 生成图靠 genParams 列回填归一（见该迁移）。
enum MediaSource {
  /// 用户上传：仅本地，不回源，不可被"清空缓存"批量删除
  localUpload,

  /// 端侧引擎（Local Dream）生成
  aiGenerated;

  /// 数据库 source 列名
  String get dbName => switch (this) {
        MediaSource.localUpload => 'local_upload',
        MediaSource.aiGenerated => 'ai_generated',
      };

  static MediaSource fromDbName(String name) => switch (name) {
        'ai_generated' => MediaSource.aiGenerated,
        _ => MediaSource.localUpload, // 未知/存量一律按用户上传（不可回源）
      };
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

  /// 生图时的生效参数留痕（`{steps, cfg, negativePrompt, aspectRatio}`，
  /// 刻意不含 seed）。null = 用户上传 / 旧数据（读取方回退当前模型预设推导）。
  final Map<String, dynamic>? genParams;

  const MediaItem({
    required this.mediaId,
    required this.kind,
    required this.source,
    required this.createdAt,
    required this.lastAccessedAt,
    this.prompt,
    this.modelName,
    this.genParams,
    this.localBytes = 0,
    this.localOnly = false,
  });

  factory MediaItem.fromMap(Map<String, dynamic> m) {
    final genParamsRaw = m['genParams'] as String?;
    return MediaItem(
      mediaId: m['mediaId'] as String,
      kind: MediaKind.fromDbName(m['kind'] as String),
      source: MediaSource.fromDbName(m['source'] as String),
      prompt: m['prompt'] as String?,
      modelName: m['modelName'] as String?,
      genParams: genParamsRaw == null
          ? null
          : (jsonDecode(genParamsRaw) as Map<String, dynamic>),
      createdAt: m['createdAt'] as int,
      lastAccessedAt: m['lastAccessedAt'] as int,
      localBytes: (m['localBytes'] as int?) ?? 0,
      localOnly: (m['localOnly'] as int?) == 1,
    );
  }
}
