// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scene_regenerate_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SceneRegenerateRequest extends SceneRegenerateRequest {
  @override
  final String taskId;
  @override
  final int count;
  @override
  final String? model;

  factory _$SceneRegenerateRequest(
          [void Function(SceneRegenerateRequestBuilder)? updates]) =>
      (SceneRegenerateRequestBuilder()..update(updates))._build();

  _$SceneRegenerateRequest._(
      {required this.taskId, required this.count, this.model})
      : super._();
  @override
  SceneRegenerateRequest rebuild(
          void Function(SceneRegenerateRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SceneRegenerateRequestBuilder toBuilder() =>
      SceneRegenerateRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SceneRegenerateRequest &&
        taskId == other.taskId &&
        count == other.count &&
        model == other.model;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, taskId.hashCode);
    _$hash = $jc(_$hash, count.hashCode);
    _$hash = $jc(_$hash, model.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SceneRegenerateRequest')
          ..add('taskId', taskId)
          ..add('count', count)
          ..add('model', model))
        .toString();
  }
}

class SceneRegenerateRequestBuilder
    implements Builder<SceneRegenerateRequest, SceneRegenerateRequestBuilder> {
  _$SceneRegenerateRequest? _$v;

  String? _taskId;
  String? get taskId => _$this._taskId;
  set taskId(String? taskId) => _$this._taskId = taskId;

  int? _count;
  int? get count => _$this._count;
  set count(int? count) => _$this._count = count;

  String? _model;
  String? get model => _$this._model;
  set model(String? model) => _$this._model = model;

  SceneRegenerateRequestBuilder() {
    SceneRegenerateRequest._defaults(this);
  }

  SceneRegenerateRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _taskId = $v.taskId;
      _count = $v.count;
      _model = $v.model;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SceneRegenerateRequest other) {
    _$v = other as _$SceneRegenerateRequest;
  }

  @override
  void update(void Function(SceneRegenerateRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SceneRegenerateRequest build() => _build();

  _$SceneRegenerateRequest _build() {
    final _$result = _$v ??
        _$SceneRegenerateRequest._(
          taskId: BuiltValueNullFieldError.checkNotNull(
              taskId, r'SceneRegenerateRequest', 'taskId'),
          count: BuiltValueNullFieldError.checkNotNull(
              count, r'SceneRegenerateRequest', 'count'),
          model: model,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
