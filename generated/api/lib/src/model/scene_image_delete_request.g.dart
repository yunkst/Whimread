// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scene_image_delete_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SceneImageDeleteRequest extends SceneImageDeleteRequest {
  @override
  final String taskId;
  @override
  final String filename;

  factory _$SceneImageDeleteRequest(
          [void Function(SceneImageDeleteRequestBuilder)? updates]) =>
      (SceneImageDeleteRequestBuilder()..update(updates))._build();

  _$SceneImageDeleteRequest._({required this.taskId, required this.filename})
      : super._();
  @override
  SceneImageDeleteRequest rebuild(
          void Function(SceneImageDeleteRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SceneImageDeleteRequestBuilder toBuilder() =>
      SceneImageDeleteRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SceneImageDeleteRequest &&
        taskId == other.taskId &&
        filename == other.filename;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, taskId.hashCode);
    _$hash = $jc(_$hash, filename.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SceneImageDeleteRequest')
          ..add('taskId', taskId)
          ..add('filename', filename))
        .toString();
  }
}

class SceneImageDeleteRequestBuilder
    implements
        Builder<SceneImageDeleteRequest, SceneImageDeleteRequestBuilder> {
  _$SceneImageDeleteRequest? _$v;

  String? _taskId;
  String? get taskId => _$this._taskId;
  set taskId(String? taskId) => _$this._taskId = taskId;

  String? _filename;
  String? get filename => _$this._filename;
  set filename(String? filename) => _$this._filename = filename;

  SceneImageDeleteRequestBuilder() {
    SceneImageDeleteRequest._defaults(this);
  }

  SceneImageDeleteRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _taskId = $v.taskId;
      _filename = $v.filename;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SceneImageDeleteRequest other) {
    _$v = other as _$SceneImageDeleteRequest;
  }

  @override
  void update(void Function(SceneImageDeleteRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SceneImageDeleteRequest build() => _build();

  _$SceneImageDeleteRequest _build() {
    final _$result = _$v ??
        _$SceneImageDeleteRequest._(
          taskId: BuiltValueNullFieldError.checkNotNull(
              taskId, r'SceneImageDeleteRequest', 'taskId'),
          filename: BuiltValueNullFieldError.checkNotNull(
              filename, r'SceneImageDeleteRequest', 'filename'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
