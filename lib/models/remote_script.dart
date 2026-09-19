/// 云端脚本仓库 DTO（v47 起）
///
/// 与 whimread-admin 后端 `script_repo` 表 / `/api/v1/scripts` 系列接口的
/// 契约对应：
/// - [RemoteScriptMeta]：列表 / 搜索返回的摘要（不含 JS 载荷）
/// - [RemoteScriptPayload]：单个脚本详情（含三类 JS 载荷），下载用
class RemoteScriptMeta {
  /// 云端脚本主键（uuid）
  final String remoteId;

  /// 目标站点 domain
  final String domain;

  /// 站点显示名（可能为空串）
  final String displayName;

  /// 当前版本号（同 author+domain 单调递增）
  final int version;

  /// 脚本载荷指纹（SHA-256 hex）
  final String sha256;

  /// 验证样本 URL
  final String sampleUrl;

  /// 是否包含书架脚本
  final bool hasBookshelfJs;

  /// 审核通过时间（毫秒时间戳）
  final int approvedAt;

  /// 累计下载次数
  final int downloadCount;

  /// 提交者设备脱敏标识（展示用，如 `dev-xxxx…xxxx`）
  final String authorDisplayId;

  const RemoteScriptMeta({
    required this.remoteId,
    required this.domain,
    required this.displayName,
    required this.version,
    required this.sha256,
    required this.sampleUrl,
    required this.hasBookshelfJs,
    required this.approvedAt,
    required this.downloadCount,
    required this.authorDisplayId,
  });

  factory RemoteScriptMeta.fromJson(Map<String, dynamic> json) {
    return RemoteScriptMeta(
      remoteId: json['remote_id'] as String,
      domain: json['domain'] as String,
      displayName: (json['display_name'] as String?) ?? '',
      version: (json['version'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'] as String,
      sampleUrl: (json['sample_url'] as String?) ?? '',
      hasBookshelfJs: (json['has_bookshelf_js'] as bool?) ?? false,
      approvedAt: _parseTime(json['approved_at']),
      downloadCount: (json['download_count'] as num?)?.toInt() ?? 0,
      authorDisplayId: (json['author_display_id'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'remote_id': remoteId,
        'domain': domain,
        'display_name': displayName,
        'version': version,
        'sha256': sha256,
        'sample_url': sampleUrl,
        'has_bookshelf_js': hasBookshelfJs,
        'approved_at': approvedAt,
        'download_count': downloadCount,
        'author_display_id': authorDisplayId,
      };

  /// 后端时间字段兼容 ISO 字符串 / 毫秒数两种形态
  static int _parseTime(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0;
    }
    return 0;
  }
}

/// 云端脚本完整载荷（下载 / 更新用）
class RemoteScriptPayload {
  final RemoteScriptMeta meta;
  final String chapterListJs;
  final String chapterContentJs;
  final String bookshelfJs;

  /// 是否需要 OCR 后处理（目录 / 正文各自独立，与本地语义一致）
  final bool chapterListOcr;
  final bool chapterContentOcr;

  /// 创作时的浏览器模式（0=未设置、1=桌面、2=手机）
  final int preferredMode;

  /// 验证样本 URL
  final String sampleUrl;

  /// URL 匹配模式（当前后端仅为回显字段）
  final String urlPattern;

  const RemoteScriptPayload({
    required this.meta,
    required this.chapterListJs,
    required this.chapterContentJs,
    required this.bookshelfJs,
    required this.chapterListOcr,
    required this.chapterContentOcr,
    required this.preferredMode,
    required this.sampleUrl,
    required this.urlPattern,
  });

  factory RemoteScriptPayload.fromJson(Map<String, dynamic> json) {
    return RemoteScriptPayload(
      meta: RemoteScriptMeta.fromJson(
        json['meta'] as Map<String, dynamic>,
      ),
      chapterListJs: (json['chapter_list_js'] as String?) ?? '',
      chapterContentJs: (json['chapter_content_js'] as String?) ?? '',
      bookshelfJs: (json['bookshelf_js'] as String?) ?? '',
      chapterListOcr: (json['chapter_list_ocr'] as bool?) ?? false,
      chapterContentOcr: (json['chapter_content_ocr'] as bool?) ?? false,
      preferredMode: (json['preferred_mode'] as num?)?.toInt() ?? 0,
      sampleUrl: (json['sample_url'] as String?) ?? '',
      urlPattern: (json['url_pattern'] as String?) ?? '',
    );
  }
}

/// 共享提交后服务端返回的结果
class RemoteShareResult {
  final String remoteId;
  final int version;

  /// 服务端是否复用了已有提交（同 author+domain+sha256 去重）
  final bool deduplicated;

  const RemoteShareResult({
    required this.remoteId,
    required this.version,
    required this.deduplicated,
  });

  factory RemoteShareResult.fromJson(Map<String, dynamic> json) {
    return RemoteShareResult(
      remoteId: json['remote_id'] as String,
      version: (json['version'] as num?)?.toInt() ?? 0,
      deduplicated: (json['deduplicated'] as bool?) ?? false,
    );
  }
}

/// 批量更新检查结果：某 remote_id 有比本地更新的版本
class RemoteScriptUpdate {
  final String remoteId;
  final int latestVersion;
  final String sha256;

  const RemoteScriptUpdate({
    required this.remoteId,
    required this.latestVersion,
    required this.sha256,
  });

  factory RemoteScriptUpdate.fromJson(Map<String, dynamic> json) {
    return RemoteScriptUpdate(
      remoteId: json['remote_id'] as String,
      latestVersion: (json['latest_version'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'] as String,
    );
  }
}
