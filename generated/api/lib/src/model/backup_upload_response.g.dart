// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_upload_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BackupUploadResponse extends BackupUploadResponse {
  @override
  final String filename;
  @override
  final String storedPath;
  @override
  final int fileSize;
  @override
  final String uploadedAt;
  @override
  final String storedName;

  factory _$BackupUploadResponse(
          [void Function(BackupUploadResponseBuilder)? updates]) =>
      (BackupUploadResponseBuilder()..update(updates))._build();

  _$BackupUploadResponse._(
      {required this.filename,
      required this.storedPath,
      required this.fileSize,
      required this.uploadedAt,
      required this.storedName})
      : super._();
  @override
  BackupUploadResponse rebuild(
          void Function(BackupUploadResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BackupUploadResponseBuilder toBuilder() =>
      BackupUploadResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BackupUploadResponse &&
        filename == other.filename &&
        storedPath == other.storedPath &&
        fileSize == other.fileSize &&
        uploadedAt == other.uploadedAt &&
        storedName == other.storedName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, filename.hashCode);
    _$hash = $jc(_$hash, storedPath.hashCode);
    _$hash = $jc(_$hash, fileSize.hashCode);
    _$hash = $jc(_$hash, uploadedAt.hashCode);
    _$hash = $jc(_$hash, storedName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BackupUploadResponse')
          ..add('filename', filename)
          ..add('storedPath', storedPath)
          ..add('fileSize', fileSize)
          ..add('uploadedAt', uploadedAt)
          ..add('storedName', storedName))
        .toString();
  }
}

class BackupUploadResponseBuilder
    implements Builder<BackupUploadResponse, BackupUploadResponseBuilder> {
  _$BackupUploadResponse? _$v;

  String? _filename;
  String? get filename => _$this._filename;
  set filename(String? filename) => _$this._filename = filename;

  String? _storedPath;
  String? get storedPath => _$this._storedPath;
  set storedPath(String? storedPath) => _$this._storedPath = storedPath;

  int? _fileSize;
  int? get fileSize => _$this._fileSize;
  set fileSize(int? fileSize) => _$this._fileSize = fileSize;

  String? _uploadedAt;
  String? get uploadedAt => _$this._uploadedAt;
  set uploadedAt(String? uploadedAt) => _$this._uploadedAt = uploadedAt;

  String? _storedName;
  String? get storedName => _$this._storedName;
  set storedName(String? storedName) => _$this._storedName = storedName;

  BackupUploadResponseBuilder() {
    BackupUploadResponse._defaults(this);
  }

  BackupUploadResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _filename = $v.filename;
      _storedPath = $v.storedPath;
      _fileSize = $v.fileSize;
      _uploadedAt = $v.uploadedAt;
      _storedName = $v.storedName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BackupUploadResponse other) {
    _$v = other as _$BackupUploadResponse;
  }

  @override
  void update(void Function(BackupUploadResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BackupUploadResponse build() => _build();

  _$BackupUploadResponse _build() {
    final _$result = _$v ??
        _$BackupUploadResponse._(
          filename: BuiltValueNullFieldError.checkNotNull(
              filename, r'BackupUploadResponse', 'filename'),
          storedPath: BuiltValueNullFieldError.checkNotNull(
              storedPath, r'BackupUploadResponse', 'storedPath'),
          fileSize: BuiltValueNullFieldError.checkNotNull(
              fileSize, r'BackupUploadResponse', 'fileSize'),
          uploadedAt: BuiltValueNullFieldError.checkNotNull(
              uploadedAt, r'BackupUploadResponse', 'uploadedAt'),
          storedName: BuiltValueNullFieldError.checkNotNull(
              storedName, r'BackupUploadResponse', 'storedName'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
