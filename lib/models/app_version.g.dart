// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_version.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppVersion _$AppVersionFromJson(Map<String, dynamic> json) => AppVersion(
      version: json['version'] as String,
      downloadUrl: json['downloadUrl'] as String,
      fileSize: (json['fileSize'] as num).toInt(),
      changelog: json['changelog'] as String?,
      createdAt: json['createdAt'] as String,
      sha256: json['sha256'] as String?,
    );

Map<String, dynamic> _$AppVersionToJson(AppVersion instance) =>
    <String, dynamic>{
      'version': instance.version,
      'downloadUrl': instance.downloadUrl,
      'fileSize': instance.fileSize,
      'changelog': instance.changelog,
      'createdAt': instance.createdAt,
      'sha256': instance.sha256,
    };
