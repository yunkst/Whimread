// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enhanced_scene_illustration_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnhancedSceneIllustrationRequest
    extends EnhancedSceneIllustrationRequest {
  @override
  final String chaptersContent;
  @override
  final String taskId;
  @override
  final BuiltList<RoleInfo> roles;
  @override
  final int num_;
  @override
  final String? modelName;

  factory _$EnhancedSceneIllustrationRequest(
          [void Function(EnhancedSceneIllustrationRequestBuilder)? updates]) =>
      (EnhancedSceneIllustrationRequestBuilder()..update(updates))._build();

  _$EnhancedSceneIllustrationRequest._(
      {required this.chaptersContent,
      required this.taskId,
      required this.roles,
      required this.num_,
      this.modelName})
      : super._();
  @override
  EnhancedSceneIllustrationRequest rebuild(
          void Function(EnhancedSceneIllustrationRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EnhancedSceneIllustrationRequestBuilder toBuilder() =>
      EnhancedSceneIllustrationRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnhancedSceneIllustrationRequest &&
        chaptersContent == other.chaptersContent &&
        taskId == other.taskId &&
        roles == other.roles &&
        num_ == other.num_ &&
        modelName == other.modelName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, chaptersContent.hashCode);
    _$hash = $jc(_$hash, taskId.hashCode);
    _$hash = $jc(_$hash, roles.hashCode);
    _$hash = $jc(_$hash, num_.hashCode);
    _$hash = $jc(_$hash, modelName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnhancedSceneIllustrationRequest')
          ..add('chaptersContent', chaptersContent)
          ..add('taskId', taskId)
          ..add('roles', roles)
          ..add('num_', num_)
          ..add('modelName', modelName))
        .toString();
  }
}

class EnhancedSceneIllustrationRequestBuilder
    implements
        Builder<EnhancedSceneIllustrationRequest,
            EnhancedSceneIllustrationRequestBuilder> {
  _$EnhancedSceneIllustrationRequest? _$v;

  String? _chaptersContent;
  String? get chaptersContent => _$this._chaptersContent;
  set chaptersContent(String? chaptersContent) =>
      _$this._chaptersContent = chaptersContent;

  String? _taskId;
  String? get taskId => _$this._taskId;
  set taskId(String? taskId) => _$this._taskId = taskId;

  ListBuilder<RoleInfo>? _roles;
  ListBuilder<RoleInfo> get roles => _$this._roles ??= ListBuilder<RoleInfo>();
  set roles(ListBuilder<RoleInfo>? roles) => _$this._roles = roles;

  int? _num_;
  int? get num_ => _$this._num_;
  set num_(int? num_) => _$this._num_ = num_;

  String? _modelName;
  String? get modelName => _$this._modelName;
  set modelName(String? modelName) => _$this._modelName = modelName;

  EnhancedSceneIllustrationRequestBuilder() {
    EnhancedSceneIllustrationRequest._defaults(this);
  }

  EnhancedSceneIllustrationRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _chaptersContent = $v.chaptersContent;
      _taskId = $v.taskId;
      _roles = $v.roles.toBuilder();
      _num_ = $v.num_;
      _modelName = $v.modelName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnhancedSceneIllustrationRequest other) {
    _$v = other as _$EnhancedSceneIllustrationRequest;
  }

  @override
  void update(void Function(EnhancedSceneIllustrationRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnhancedSceneIllustrationRequest build() => _build();

  _$EnhancedSceneIllustrationRequest _build() {
    _$EnhancedSceneIllustrationRequest _$result;
    try {
      _$result = _$v ??
          _$EnhancedSceneIllustrationRequest._(
            chaptersContent: BuiltValueNullFieldError.checkNotNull(
                chaptersContent,
                r'EnhancedSceneIllustrationRequest',
                'chaptersContent'),
            taskId: BuiltValueNullFieldError.checkNotNull(
                taskId, r'EnhancedSceneIllustrationRequest', 'taskId'),
            roles: roles.build(),
            num_: BuiltValueNullFieldError.checkNotNull(
                num_, r'EnhancedSceneIllustrationRequest', 'num_'),
            modelName: modelName,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'roles';
        roles.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'EnhancedSceneIllustrationRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
