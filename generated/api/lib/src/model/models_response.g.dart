// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModelsResponse extends ModelsResponse {
  @override
  final BuiltList<WorkflowInfo>? text2img;
  @override
  final BuiltList<WorkflowInfo>? img2video;

  factory _$ModelsResponse([void Function(ModelsResponseBuilder)? updates]) =>
      (ModelsResponseBuilder()..update(updates))._build();

  _$ModelsResponse._({this.text2img, this.img2video}) : super._();
  @override
  ModelsResponse rebuild(void Function(ModelsResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModelsResponseBuilder toBuilder() => ModelsResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModelsResponse &&
        text2img == other.text2img &&
        img2video == other.img2video;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, text2img.hashCode);
    _$hash = $jc(_$hash, img2video.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModelsResponse')
          ..add('text2img', text2img)
          ..add('img2video', img2video))
        .toString();
  }
}

class ModelsResponseBuilder
    implements Builder<ModelsResponse, ModelsResponseBuilder> {
  _$ModelsResponse? _$v;

  ListBuilder<WorkflowInfo>? _text2img;
  ListBuilder<WorkflowInfo> get text2img =>
      _$this._text2img ??= ListBuilder<WorkflowInfo>();
  set text2img(ListBuilder<WorkflowInfo>? text2img) =>
      _$this._text2img = text2img;

  ListBuilder<WorkflowInfo>? _img2video;
  ListBuilder<WorkflowInfo> get img2video =>
      _$this._img2video ??= ListBuilder<WorkflowInfo>();
  set img2video(ListBuilder<WorkflowInfo>? img2video) =>
      _$this._img2video = img2video;

  ModelsResponseBuilder() {
    ModelsResponse._defaults(this);
  }

  ModelsResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _text2img = $v.text2img?.toBuilder();
      _img2video = $v.img2video?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModelsResponse other) {
    _$v = other as _$ModelsResponse;
  }

  @override
  void update(void Function(ModelsResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModelsResponse build() => _build();

  _$ModelsResponse _build() {
    _$ModelsResponse _$result;
    try {
      _$result = _$v ??
          _$ModelsResponse._(
            text2img: _text2img?.build(),
            img2video: _img2video?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'text2img';
        _text2img?.build();
        _$failedField = 'img2video';
        _img2video?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ModelsResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
