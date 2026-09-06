/// GitHub Release 数据模型
///
/// 对应 GitHub API `/repos/{owner}/{repo}/releases/latest` 响应
class GithubRelease {
  final String tagName;
  final String name;
  final String? body;
  final String publishedAt;
  final bool prerelease;
  final bool draft;
  final List<GithubAsset> assets;

  GithubRelease({
    required this.tagName,
    required this.name,
    this.body,
    required this.publishedAt,
    required this.prerelease,
    required this.draft,
    required this.assets,
  });

  factory GithubRelease.fromJson(Map<String, dynamic> json) {
    return GithubRelease(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: json['body'] as String?,
      publishedAt: json['published_at'] as String? ?? '',
      prerelease: json['prerelease'] as bool? ?? false,
      draft: json['draft'] as bool? ?? false,
      assets: (json['assets'] as List<dynamic>?)
              ?.map((e) => GithubAsset.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// 通用 APK asset：取第一个 APK（兼容旧逻辑）
  ///
  /// 保留此方法以避免破坏外部调用者；新代码应使用 [apkAssetFor] 按设备架构选取。
  GithubAsset? get apkAsset {
    try {
      return assets.firstWhere(
        (a) => a.contentType == 'application/vnd.android.package-archive',
      );
    } catch (_) {
      // fallback: 按 .apk 后缀匹配
      try {
        return assets.firstWhere((a) => a.name.endsWith('.apk'));
      } catch (_) {
        return null;
      }
    }
  }

  /// 按设备架构选择最合适的 APK asset
  ///
  /// 兜底链：
  ///   1. 精确匹配当前架构的 split APK（如 `app-arm64-v8a-release.apk`）
  ///   2. 通用 fat APK（`app-release.apk`，包含所有架构）
  ///   3. 任意一个 APK（避免升级流程完全走不通）
  GithubAsset? apkAssetFor(String archSegment) {
    // 1) 优先按架构精确匹配
    if (archSegment.isNotEmpty) {
      final matched = _firstApkNameContains(archSegment);
      if (matched != null) return matched;
    }

    // 2) 兜底：通用 fat APK
    final universal = _firstApkNameContains('-release.apk') ??
        _firstApkNameContains('app-release');
    if (universal != null) return universal;

    // 3) 最后兜底：任意 .apk
    return _anyApk();
  }

  GithubAsset? _firstApkNameContains(String segment) {
    for (final a in assets) {
      if (!a.name.endsWith('.apk')) continue;
      if (a.name.contains(segment)) return a;
    }
    return null;
  }

  GithubAsset? _anyApk() {
    for (final a in assets) {
      if (a.name.endsWith('.apk')) return a;
    }
    return null;
  }

  /// 版本号（去除 'v' 前缀）
  /// "v1.7.7" → "1.7.7"
  String get versionNumber => tagName.replaceFirst(RegExp(r'^v'), '');
}

/// GitHub Release Asset 数据模型
class GithubAsset {
  final String name;
  final int size;
  final String browserDownloadUrl;
  final String contentType;

  GithubAsset({
    required this.name,
    required this.size,
    required this.browserDownloadUrl,
    required this.contentType,
  });

  factory GithubAsset.fromJson(Map<String, dynamic> json) {
    return GithubAsset(
      name: json['name'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      browserDownloadUrl: json['browser_download_url'] as String? ?? '',
      contentType: json['content_type'] as String? ?? '',
    );
  }
}
