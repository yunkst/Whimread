// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'role_regenerate_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RoleRegenerateRequest extends RoleRegenerateRequest {
  @override
  final String imgUrl;
  @override
  final int count;
  @override
  final String? model;

  factory _$RoleRegenerateRequest(
          [void Function(RoleRegenerateRequestBuilder)? updates]) =>
      (RoleRegenerateRequestBuilder()..update(updates))._build();

  _$RoleRegenerateRequest._(
      {required this.imgUrl, required this.count, this.model})
      : super._();
  @override
  RoleRegenerateRequest rebuild(
          void Function(RoleRegenerateRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RoleRegenerateRequestBuilder toBuilder() =>
      RoleRegenerateRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RoleRegenerateRequest &&
        imgUrl == other.imgUrl &&
        count == other.count &&
        model == other.model;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, imgUrl.hashCode);
    _$hash = $jc(_$hash, count.hashCode);
    _$hash = $jc(_$hash, model.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RoleRegenerateRequest')
          ..add('imgUrl', imgUrl)
          ..add('count', count)
          ..add('model', model))
        .toString();
  }
}

class RoleRegenerateRequestBuilder
    implements Builder<RoleRegenerateRequest, RoleRegenerateRequestBuilder> {
  _$RoleRegenerateRequest? _$v;

  String? _imgUrl;
  String? get imgUrl => _$this._imgUrl;
  set imgUrl(String? imgUrl) => _$this._imgUrl = imgUrl;

  int? _count;
  int? get count => _$this._count;
  set count(int? count) => _$this._count = count;

  String? _model;
  String? get model => _$this._model;
  set model(String? model) => _$this._model = model;

  RoleRegenerateRequestBuilder() {
    RoleRegenerateRequest._defaults(this);
  }

  RoleRegenerateRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _imgUrl = $v.imgUrl;
      _count = $v.count;
      _model = $v.model;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RoleRegenerateRequest other) {
    _$v = other as _$RoleRegenerateRequest;
  }

  @override
  void update(void Function(RoleRegenerateRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RoleRegenerateRequest build() => _build();

  _$RoleRegenerateRequest _build() {
    final _$result = _$v ??
        _$RoleRegenerateRequest._(
          imgUrl: BuiltValueNullFieldError.checkNotNull(
              imgUrl, r'RoleRegenerateRequest', 'imgUrl'),
          count: BuiltValueNullFieldError.checkNotNull(
              count, r'RoleRegenerateRequest', 'count'),
          model: model,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
