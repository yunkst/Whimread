// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scene_regenerate_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SceneRegenerateResponse extends SceneRegenerateResponse {
  @override
  final String taskId;
  @override
  final int totalPrompts;
  @override
  final String message;

  factory _$SceneRegenerateResponse(
          [void Function(SceneRegenerateResponseBuilder)? updates]) =>
      (SceneRegenerateResponseBuilder()..update(updates))._build();

  _$SceneRegenerateResponse._(
      {required this.taskId, required this.totalPrompts, required this.message})
      : super._();
  @override
  SceneRegenerateResponse rebuild(
          void Function(SceneRegenerateResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SceneRegenerateResponseBuilder toBuilder() =>
      SceneRegenerateResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SceneRegenerateResponse &&
        taskId == other.taskId &&
        totalPrompts == other.totalPrompts &&
        message == other.message;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, taskId.hashCode);
    _$hash = $jc(_$hash, totalPrompts.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SceneRegenerateResponse')
          ..add('taskId', taskId)
          ..add('totalPrompts', totalPrompts)
          ..add('message', message))
        .toString();
  }
}

class SceneRegenerateResponseBuilder
    implements
        Builder<SceneRegenerateResponse, SceneRegenerateResponseBuilder> {
  _$SceneRegenerateResponse? _$v;

  String? _taskId;
  String? get taskId => _$this._taskId;
  set taskId(String? taskId) => _$this._taskId = taskId;

  int? _totalPrompts;
  int? get totalPrompts => _$this._totalPrompts;
  set totalPrompts(int? totalPrompts) => _$this._totalPrompts = totalPrompts;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  SceneRegenerateResponseBuilder() {
    SceneRegenerateResponse._defaults(this);
  }

  SceneRegenerateResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _taskId = $v.taskId;
      _totalPrompts = $v.totalPrompts;
      _message = $v.message;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SceneRegenerateResponse other) {
    _$v = other as _$SceneRegenerateResponse;
  }

  @override
  void update(void Function(SceneRegenerateResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SceneRegenerateResponse build() => _build();

  _$SceneRegenerateResponse _build() {
    final _$result = _$v ??
        _$SceneRegenerateResponse._(
          taskId: BuiltValueNullFieldError.checkNotNull(
              taskId, r'SceneRegenerateResponse', 'taskId'),
          totalPrompts: BuiltValueNullFieldError.checkNotNull(
              totalPrompts, r'SceneRegenerateResponse', 'totalPrompts'),
          message: BuiltValueNullFieldError.checkNotNull(
              message, r'SceneRegenerateResponse', 'message'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
