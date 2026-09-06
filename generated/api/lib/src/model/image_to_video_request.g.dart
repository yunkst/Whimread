// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'image_to_video_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ImageToVideoRequest extends ImageToVideoRequest {
  @override
  final String imgName;
  @override
  final String userInput;
  @override
  final String? modelName;

  factory _$ImageToVideoRequest(
          [void Function(ImageToVideoRequestBuilder)? updates]) =>
      (ImageToVideoRequestBuilder()..update(updates))._build();

  _$ImageToVideoRequest._(
      {required this.imgName, required this.userInput, this.modelName})
      : super._();
  @override
  ImageToVideoRequest rebuild(
          void Function(ImageToVideoRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ImageToVideoRequestBuilder toBuilder() =>
      ImageToVideoRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ImageToVideoRequest &&
        imgName == other.imgName &&
        userInput == other.userInput &&
        modelName == other.modelName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, imgName.hashCode);
    _$hash = $jc(_$hash, userInput.hashCode);
    _$hash = $jc(_$hash, modelName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ImageToVideoRequest')
          ..add('imgName', imgName)
          ..add('userInput', userInput)
          ..add('modelName', modelName))
        .toString();
  }
}

class ImageToVideoRequestBuilder
    implements Builder<ImageToVideoRequest, ImageToVideoRequestBuilder> {
  _$ImageToVideoRequest? _$v;

  String? _imgName;
  String? get imgName => _$this._imgName;
  set imgName(String? imgName) => _$this._imgName = imgName;

  String? _userInput;
  String? get userInput => _$this._userInput;
  set userInput(String? userInput) => _$this._userInput = userInput;

  String? _modelName;
  String? get modelName => _$this._modelName;
  set modelName(String? modelName) => _$this._modelName = modelName;

  ImageToVideoRequestBuilder() {
    ImageToVideoRequest._defaults(this);
  }

  ImageToVideoRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _imgName = $v.imgName;
      _userInput = $v.userInput;
      _modelName = $v.modelName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ImageToVideoRequest other) {
    _$v = other as _$ImageToVideoRequest;
  }

  @override
  void update(void Function(ImageToVideoRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ImageToVideoRequest build() => _build();

  _$ImageToVideoRequest _build() {
    final _$result = _$v ??
        _$ImageToVideoRequest._(
          imgName: BuiltValueNullFieldError.checkNotNull(
              imgName, r'ImageToVideoRequest', 'imgName'),
          userInput: BuiltValueNullFieldError.checkNotNull(
              userInput, r'ImageToVideoRequest', 'userInput'),
          modelName: modelName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
