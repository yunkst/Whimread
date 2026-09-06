// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'role_image_delete_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RoleImageDeleteRequest extends RoleImageDeleteRequest {
  @override
  final String roleId;
  @override
  final String imgUrl;

  factory _$RoleImageDeleteRequest(
          [void Function(RoleImageDeleteRequestBuilder)? updates]) =>
      (RoleImageDeleteRequestBuilder()..update(updates))._build();

  _$RoleImageDeleteRequest._({required this.roleId, required this.imgUrl})
      : super._();
  @override
  RoleImageDeleteRequest rebuild(
          void Function(RoleImageDeleteRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RoleImageDeleteRequestBuilder toBuilder() =>
      RoleImageDeleteRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RoleImageDeleteRequest &&
        roleId == other.roleId &&
        imgUrl == other.imgUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, roleId.hashCode);
    _$hash = $jc(_$hash, imgUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RoleImageDeleteRequest')
          ..add('roleId', roleId)
          ..add('imgUrl', imgUrl))
        .toString();
  }
}

class RoleImageDeleteRequestBuilder
    implements Builder<RoleImageDeleteRequest, RoleImageDeleteRequestBuilder> {
  _$RoleImageDeleteRequest? _$v;

  String? _roleId;
  String? get roleId => _$this._roleId;
  set roleId(String? roleId) => _$this._roleId = roleId;

  String? _imgUrl;
  String? get imgUrl => _$this._imgUrl;
  set imgUrl(String? imgUrl) => _$this._imgUrl = imgUrl;

  RoleImageDeleteRequestBuilder() {
    RoleImageDeleteRequest._defaults(this);
  }

  RoleImageDeleteRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _roleId = $v.roleId;
      _imgUrl = $v.imgUrl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RoleImageDeleteRequest other) {
    _$v = other as _$RoleImageDeleteRequest;
  }

  @override
  void update(void Function(RoleImageDeleteRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RoleImageDeleteRequest build() => _build();

  _$RoleImageDeleteRequest _build() {
    final _$result = _$v ??
        _$RoleImageDeleteRequest._(
          roleId: BuiltValueNullFieldError.checkNotNull(
              roleId, r'RoleImageDeleteRequest', 'roleId'),
          imgUrl: BuiltValueNullFieldError.checkNotNull(
              imgUrl, r'RoleImageDeleteRequest', 'imgUrl'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
