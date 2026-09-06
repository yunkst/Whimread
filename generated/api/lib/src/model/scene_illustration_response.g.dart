// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scene_illustration_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SceneIllustrationResponse extends SceneIllustrationResponse {
  @override
  final String taskId;
  @override
  final String status;
  @override
  final String message;

  factory _$SceneIllustrationResponse(
          [void Function(SceneIllustrationResponseBuilder)? updates]) =>
      (SceneIllustrationResponseBuilder()..update(updates))._build();

  _$SceneIllustrationResponse._(
      {required this.taskId, required this.status, required this.message})
      : super._();
  @override
  SceneIllustrationResponse rebuild(
          void Function(SceneIllustrationResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SceneIllustrationResponseBuilder toBuilder() =>
      SceneIllustrationResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SceneIllustrationResponse &&
        taskId == other.taskId &&
        status == other.status &&
        message == other.message;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, taskId.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SceneIllustrationResponse')
          ..add('taskId', taskId)
          ..add('status', status)
          ..add('message', message))
        .toString();
  }
}

class SceneIllustrationResponseBuilder
    implements
        Builder<SceneIllustrationResponse, SceneIllustrationResponseBuilder> {
  _$SceneIllustrationResponse? _$v;

  String? _taskId;
  String? get taskId => _$this._taskId;
  set taskId(String? taskId) => _$this._taskId = taskId;

  String? _status;
  String? get status => _$this._status;
  set status(String? status) => _$this._status = status;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  SceneIllustrationResponseBuilder() {
    SceneIllustrationResponse._defaults(this);
  }

  SceneIllustrationResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _taskId = $v.taskId;
      _status = $v.status;
      _message = $v.message;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SceneIllustrationResponse other) {
    _$v = other as _$SceneIllustrationResponse;
  }

  @override
  void update(void Function(SceneIllustrationResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SceneIllustrationResponse build() => _build();

  _$SceneIllustrationResponse _build() {
    final _$result = _$v ??
        _$SceneIllustrationResponse._(
          taskId: BuiltValueNullFieldError.checkNotNull(
              taskId, r'SceneIllustrationResponse', 'taskId'),
          status: BuiltValueNullFieldError.checkNotNull(
              status, r'SceneIllustrationResponse', 'status'),
          message: BuiltValueNullFieldError.checkNotNull(
              message, r'SceneIllustrationResponse', 'message'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
