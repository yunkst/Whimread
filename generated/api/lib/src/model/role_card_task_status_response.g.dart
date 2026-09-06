// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'role_card_task_status_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RoleCardTaskStatusResponse extends RoleCardTaskStatusResponse {
  @override
  final int taskId;
  @override
  final String roleId;
  @override
  final String status;
  @override
  final int totalPrompts;
  @override
  final int generatedImages;
  @override
  final String? resultMessage;
  @override
  final String? errorMessage;
  @override
  final String createdAt;
  @override
  final String? startedAt;
  @override
  final String? completedAt;
  @override
  final num progressPercentage;

  factory _$RoleCardTaskStatusResponse(
          [void Function(RoleCardTaskStatusResponseBuilder)? updates]) =>
      (RoleCardTaskStatusResponseBuilder()..update(updates))._build();

  _$RoleCardTaskStatusResponse._(
      {required this.taskId,
      required this.roleId,
      required this.status,
      required this.totalPrompts,
      required this.generatedImages,
      this.resultMessage,
      this.errorMessage,
      required this.createdAt,
      this.startedAt,
      this.completedAt,
      required this.progressPercentage})
      : super._();
  @override
  RoleCardTaskStatusResponse rebuild(
          void Function(RoleCardTaskStatusResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RoleCardTaskStatusResponseBuilder toBuilder() =>
      RoleCardTaskStatusResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RoleCardTaskStatusResponse &&
        taskId == other.taskId &&
        roleId == other.roleId &&
        status == other.status &&
        totalPrompts == other.totalPrompts &&
        generatedImages == other.generatedImages &&
        resultMessage == other.resultMessage &&
        errorMessage == other.errorMessage &&
        createdAt == other.createdAt &&
        startedAt == other.startedAt &&
        completedAt == other.completedAt &&
        progressPercentage == other.progressPercentage;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, taskId.hashCode);
    _$hash = $jc(_$hash, roleId.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, totalPrompts.hashCode);
    _$hash = $jc(_$hash, generatedImages.hashCode);
    _$hash = $jc(_$hash, resultMessage.hashCode);
    _$hash = $jc(_$hash, errorMessage.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, startedAt.hashCode);
    _$hash = $jc(_$hash, completedAt.hashCode);
    _$hash = $jc(_$hash, progressPercentage.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RoleCardTaskStatusResponse')
          ..add('taskId', taskId)
          ..add('roleId', roleId)
          ..add('status', status)
          ..add('totalPrompts', totalPrompts)
          ..add('generatedImages', generatedImages)
          ..add('resultMessage', resultMessage)
          ..add('errorMessage', errorMessage)
          ..add('createdAt', createdAt)
          ..add('startedAt', startedAt)
          ..add('completedAt', completedAt)
          ..add('progressPercentage', progressPercentage))
        .toString();
  }
}

class RoleCardTaskStatusResponseBuilder
    implements
        Builder<RoleCardTaskStatusResponse, RoleCardTaskStatusResponseBuilder> {
  _$RoleCardTaskStatusResponse? _$v;

  int? _taskId;
  int? get taskId => _$this._taskId;
  set taskId(int? taskId) => _$this._taskId = taskId;

  String? _roleId;
  String? get roleId => _$this._roleId;
  set roleId(String? roleId) => _$this._roleId = roleId;

  String? _status;
  String? get status => _$this._status;
  set status(String? status) => _$this._status = status;

  int? _totalPrompts;
  int? get totalPrompts => _$this._totalPrompts;
  set totalPrompts(int? totalPrompts) => _$this._totalPrompts = totalPrompts;

  int? _generatedImages;
  int? get generatedImages => _$this._generatedImages;
  set generatedImages(int? generatedImages) =>
      _$this._generatedImages = generatedImages;

  String? _resultMessage;
  String? get resultMessage => _$this._resultMessage;
  set resultMessage(String? resultMessage) =>
      _$this._resultMessage = resultMessage;

  String? _errorMessage;
  String? get errorMessage => _$this._errorMessage;
  set errorMessage(String? errorMessage) => _$this._errorMessage = errorMessage;

  String? _createdAt;
  String? get createdAt => _$this._createdAt;
  set createdAt(String? createdAt) => _$this._createdAt = createdAt;

  String? _startedAt;
  String? get startedAt => _$this._startedAt;
  set startedAt(String? startedAt) => _$this._startedAt = startedAt;

  String? _completedAt;
  String? get completedAt => _$this._completedAt;
  set completedAt(String? completedAt) => _$this._completedAt = completedAt;

  num? _progressPercentage;
  num? get progressPercentage => _$this._progressPercentage;
  set progressPercentage(num? progressPercentage) =>
      _$this._progressPercentage = progressPercentage;

  RoleCardTaskStatusResponseBuilder() {
    RoleCardTaskStatusResponse._defaults(this);
  }

  RoleCardTaskStatusResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _taskId = $v.taskId;
      _roleId = $v.roleId;
      _status = $v.status;
      _totalPrompts = $v.totalPrompts;
      _generatedImages = $v.generatedImages;
      _resultMessage = $v.resultMessage;
      _errorMessage = $v.errorMessage;
      _createdAt = $v.createdAt;
      _startedAt = $v.startedAt;
      _completedAt = $v.completedAt;
      _progressPercentage = $v.progressPercentage;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RoleCardTaskStatusResponse other) {
    _$v = other as _$RoleCardTaskStatusResponse;
  }

  @override
  void update(void Function(RoleCardTaskStatusResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RoleCardTaskStatusResponse build() => _build();

  _$RoleCardTaskStatusResponse _build() {
    final _$result = _$v ??
        _$RoleCardTaskStatusResponse._(
          taskId: BuiltValueNullFieldError.checkNotNull(
              taskId, r'RoleCardTaskStatusResponse', 'taskId'),
          roleId: BuiltValueNullFieldError.checkNotNull(
              roleId, r'RoleCardTaskStatusResponse', 'roleId'),
          status: BuiltValueNullFieldError.checkNotNull(
              status, r'RoleCardTaskStatusResponse', 'status'),
          totalPrompts: BuiltValueNullFieldError.checkNotNull(
              totalPrompts, r'RoleCardTaskStatusResponse', 'totalPrompts'),
          generatedImages: BuiltValueNullFieldError.checkNotNull(
              generatedImages,
              r'RoleCardTaskStatusResponse',
              'generatedImages'),
          resultMessage: resultMessage,
          errorMessage: errorMessage,
          createdAt: BuiltValueNullFieldError.checkNotNull(
              createdAt, r'RoleCardTaskStatusResponse', 'createdAt'),
          startedAt: startedAt,
          completedAt: completedAt,
          progressPercentage: BuiltValueNullFieldError.checkNotNull(
              progressPercentage,
              r'RoleCardTaskStatusResponse',
              'progressPercentage'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
