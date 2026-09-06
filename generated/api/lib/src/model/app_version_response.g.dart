// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_version_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AppVersionResponse extends AppVersionResponse {
  @override
  final String version;
  @override
  final int versionCode;
  @override
  final String downloadUrl;
  @override
  final int fileSize;
  @override
  final String? changelog;
  @override
  final bool? forceUpdate;
  @override
  final String createdAt;

  factory _$AppVersionResponse(
          [void Function(AppVersionResponseBuilder)? updates]) =>
      (AppVersionResponseBuilder()..update(updates))._build();

  _$AppVersionResponse._(
      {required this.version,
      required this.versionCode,
      required this.downloadUrl,
      required this.fileSize,
      this.changelog,
      this.forceUpdate,
      required this.createdAt})
      : super._();
  @override
  AppVersionResponse rebuild(
          void Function(AppVersionResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AppVersionResponseBuilder toBuilder() =>
      AppVersionResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AppVersionResponse &&
        version == other.version &&
        versionCode == other.versionCode &&
        downloadUrl == other.downloadUrl &&
        fileSize == other.fileSize &&
        changelog == other.changelog &&
        forceUpdate == other.forceUpdate &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jc(_$hash, versionCode.hashCode);
    _$hash = $jc(_$hash, downloadUrl.hashCode);
    _$hash = $jc(_$hash, fileSize.hashCode);
    _$hash = $jc(_$hash, changelog.hashCode);
    _$hash = $jc(_$hash, forceUpdate.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AppVersionResponse')
          ..add('version', version)
          ..add('versionCode', versionCode)
          ..add('downloadUrl', downloadUrl)
          ..add('fileSize', fileSize)
          ..add('changelog', changelog)
          ..add('forceUpdate', forceUpdate)
          ..add('createdAt', createdAt))
        .toString();
  }
}

class AppVersionResponseBuilder
    implements Builder<AppVersionResponse, AppVersionResponseBuilder> {
  _$AppVersionResponse? _$v;

  String? _version;
  String? get version => _$this._version;
  set version(String? version) => _$this._version = version;

  int? _versionCode;
  int? get versionCode => _$this._versionCode;
  set versionCode(int? versionCode) => _$this._versionCode = versionCode;

  String? _downloadUrl;
  String? get downloadUrl => _$this._downloadUrl;
  set downloadUrl(String? downloadUrl) => _$this._downloadUrl = downloadUrl;

  int? _fileSize;
  int? get fileSize => _$this._fileSize;
  set fileSize(int? fileSize) => _$this._fileSize = fileSize;

  String? _changelog;
  String? get changelog => _$this._changelog;
  set changelog(String? changelog) => _$this._changelog = changelog;

  bool? _forceUpdate;
  bool? get forceUpdate => _$this._forceUpdate;
  set forceUpdate(bool? forceUpdate) => _$this._forceUpdate = forceUpdate;

  String? _createdAt;
  String? get createdAt => _$this._createdAt;
  set createdAt(String? createdAt) => _$this._createdAt = createdAt;

  AppVersionResponseBuilder() {
    AppVersionResponse._defaults(this);
  }

  AppVersionResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _version = $v.version;
      _versionCode = $v.versionCode;
      _downloadUrl = $v.downloadUrl;
      _fileSize = $v.fileSize;
      _changelog = $v.changelog;
      _forceUpdate = $v.forceUpdate;
      _createdAt = $v.createdAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AppVersionResponse other) {
    _$v = other as _$AppVersionResponse;
  }

  @override
  void update(void Function(AppVersionResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AppVersionResponse build() => _build();

  _$AppVersionResponse _build() {
    final _$result = _$v ??
        _$AppVersionResponse._(
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'AppVersionResponse', 'version'),
          versionCode: BuiltValueNullFieldError.checkNotNull(
              versionCode, r'AppVersionResponse', 'versionCode'),
          downloadUrl: BuiltValueNullFieldError.checkNotNull(
              downloadUrl, r'AppVersionResponse', 'downloadUrl'),
          fileSize: BuiltValueNullFieldError.checkNotNull(
              fileSize, r'AppVersionResponse', 'fileSize'),
          changelog: changelog,
          forceUpdate: forceUpdate,
          createdAt: BuiltValueNullFieldError.checkNotNull(
              createdAt, r'AppVersionResponse', 'createdAt'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
