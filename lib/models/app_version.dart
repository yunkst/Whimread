import 'package:json_annotation/json_annotation.dart';

part 'app_version.g.dart';

/// APP版本信息模型
///
/// 用于在 App 内展示版本更新信息
@JsonSerializable()
class AppVersion {
  final String version;
  final String downloadUrl;
  final int fileSize;
  final String? changelog;
  final String createdAt;

  AppVersion({
    required this.version,
    required this.downloadUrl,
    required this.fileSize,
    this.changelog,
    required this.createdAt,
  });

  /// 从JSON创建
  factory AppVersion.fromJson(Map<String, dynamic> json) =>
      _$AppVersionFromJson(json);

  /// 转换为JSON
  Map<String, dynamic> toJson() => _$AppVersionToJson(this);

  /// 格式化文件大小显示
  String get fileSizeFormatted {
    if (fileSize < 1024) {
      return '$fileSize B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  /// 解析创建时间
  DateTime? get createdAtDateTime {
    try {
      return DateTime.parse(createdAt);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() {
    return 'AppVersion(version: $version, '
        'downloadUrl: $downloadUrl, fileSize: $fileSize, '
        'changelog: $changelog, '
        'createdAt: $createdAt)';
  }
}
