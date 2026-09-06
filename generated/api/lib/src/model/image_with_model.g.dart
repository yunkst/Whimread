// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'image_with_model.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ImageWithModel extends ImageWithModel {
  @override
  final String url;
  @override
  final String? modelName;

  factory _$ImageWithModel([void Function(ImageWithModelBuilder)? updates]) =>
      (ImageWithModelBuilder()..update(updates))._build();

  _$ImageWithModel._({required this.url, this.modelName}) : super._();
  @override
  ImageWithModel rebuild(void Function(ImageWithModelBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ImageWithModelBuilder toBuilder() => ImageWithModelBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ImageWithModel &&
        url == other.url &&
        modelName == other.modelName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, modelName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ImageWithModel')
          ..add('url', url)
          ..add('modelName', modelName))
        .toString();
  }
}

class ImageWithModelBuilder
    implements Builder<ImageWithModel, ImageWithModelBuilder> {
  _$ImageWithModel? _$v;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  String? _modelName;
  String? get modelName => _$this._modelName;
  set modelName(String? modelName) => _$this._modelName = modelName;

  ImageWithModelBuilder() {
    ImageWithModel._defaults(this);
  }

  ImageWithModelBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _url = $v.url;
      _modelName = $v.modelName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ImageWithModel other) {
    _$v = other as _$ImageWithModel;
  }

  @override
  void update(void Function(ImageWithModelBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ImageWithModel build() => _build();

  _$ImageWithModel _build() {
    final _$result = _$v ??
        _$ImageWithModel._(
          url: BuiltValueNullFieldError.checkNotNull(
              url, r'ImageWithModel', 'url'),
          modelName: modelName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
