/// 后端更新分发响应模型
///
/// 对应托管后端 `GET /api/v1/app/releases/latest` 响应。
/// 字段语义与 [GithubRelease] 对齐，便于后端 / GitHub 两条更新源路径互换：
/// version 同为 tag 去 `v` 前缀（preview 形如 `2.0.0-preview.1`），
/// publishedAt 同为 ISO8601 字符串。
class BackendRelease {
  final String version;
  final int versionCode;
  final String channel;
  final String changelog;
  final String publishedAt;
  final List<BackendReleaseFile> files;

  BackendRelease({
    required this.version,
    required this.versionCode,
    required this.channel,
    required this.changelog,
    required this.publishedAt,
    required this.files,
  });

  factory BackendRelease.fromJson(Map<String, dynamic> json) {
    return BackendRelease(
      version: json['version'] as String? ?? '',
      versionCode: json['version_code'] as int? ?? 0,
      channel: json['channel'] as String? ?? 'stable',
      changelog: json['changelog'] as String? ?? '',
      publishedAt: json['published_at'] as String? ?? '',
      files: (json['files'] as List<dynamic>?)
              ?.map((e) =>
                  BackendReleaseFile.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// 按设备架构选择最合适的 APK 文件（兜底链与 GithubRelease.apkAssetFor 一致）
  ///
  ///   1. abi 或文件名精确匹配当前架构（如 `app-arm64-v8a-release.apk`）
  ///   2. 通用 fat APK（`app-release.apk`）
  ///   3. 任意一个 APK（避免升级流程完全走不通）
  BackendReleaseFile? apkFileFor(String archSegment) {
    if (archSegment.isNotEmpty) {
      for (final f in files) {
        if (!f.filename.endsWith('.apk')) continue;
        if (f.abi == archSegment || f.filename.contains(archSegment)) {
          return f;
        }
      }
    }
    for (final f in files) {
      if (f.filename == 'app-release.apk') return f;
    }
    for (final f in files) {
      if (f.filename.endsWith('.apk')) return f;
    }
    return null;
  }
}

/// 后端发布的单个 APK 文件
class BackendReleaseFile {
  final String abi;
  final String filename;
  final int size;
  final String sha256;
  final String url;

  BackendReleaseFile({
    required this.abi,
    required this.filename,
    required this.size,
    required this.sha256,
    required this.url,
  });

  factory BackendReleaseFile.fromJson(Map<String, dynamic> json) {
    return BackendReleaseFile(
      abi: json['abi'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      sha256: json['sha256'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }
}
