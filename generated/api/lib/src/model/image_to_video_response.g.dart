// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'image_to_video_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ImageToVideoResponse extends ImageToVideoResponse {
  @override
  final int taskId;
  @override
  final String imgName;
  @override
  final String status;
  @override
  final String message;

  factory _$ImageToVideoResponse(
          [void Function(ImageToVideoResponseBuilder)? updates]) =>
      (ImageToVideoResponseBuilder()..update(updates))._build();

  _$ImageToVideoResponse._(
      {required this.taskId,
      required this.imgName,
      required this.status,
      required this.message})
      : super._();
  @override
  ImageToVideoResponse rebuild(
          void Function(ImageToVideoResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ImageToVideoResponseBuilder toBuilder() =>
      ImageToVideoResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ImageToVideoResponse &&
        taskId == other.taskId &&
        imgName == other.imgName &&
        status == other.status &&
        message == other.message;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, taskId.hashCode);
    _$hash = $jc(_$hash, imgName.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ImageToVideoResponse')
          ..add('taskId', taskId)
          ..add('imgName', imgName)
          ..add('status', status)
          ..add('message', message))
        .toString();
  }
}

class ImageToVideoResponseBuilder
    implements Builder<ImageToVideoResponse, ImageToVideoResponseBuilder> {
  _$ImageToVideoResponse? _$v;

  int? _taskId;
  int? get taskId => _$this._taskId;
  set taskId(int? taskId) => _$this._taskId = taskId;

  String? _imgName;
  String? get imgName => _$this._imgName;
  set imgName(String? imgName) => _$this._imgName = imgName;

  String? _status;
  String? get status => _$this._status;
  set status(String? status) => _$this._status = status;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ImageToVideoResponseBuilder() {
    ImageToVideoResponse._defaults(this);
  }

  ImageToVideoResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _taskId = $v.taskId;
      _imgName = $v.imgName;
      _status = $v.status;
      _message = $v.message;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ImageToVideoResponse other) {
    _$v = other as _$ImageToVideoResponse;
  }

  @override
  void update(void Function(ImageToVideoResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ImageToVideoResponse build() => _build();

  _$ImageToVideoResponse _build() {
    final _$result = _$v ??
        _$ImageToVideoResponse._(
          taskId: BuiltValueNullFieldError.checkNotNull(
              taskId, r'ImageToVideoResponse', 'taskId'),
          imgName: BuiltValueNullFieldError.checkNotNull(
              imgName, r'ImageToVideoResponse', 'imgName'),
          status: BuiltValueNullFieldError.checkNotNull(
              status, r'ImageToVideoResponse', 'status'),
          message: BuiltValueNullFieldError.checkNotNull(
              message, r'ImageToVideoResponse', 'message'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
