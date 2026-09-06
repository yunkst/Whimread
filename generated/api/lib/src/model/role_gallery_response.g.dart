// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'role_gallery_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RoleGalleryResponse extends RoleGalleryResponse {
  @override
  final String roleId;
  @override
  final BuiltList<String> images;

  factory _$RoleGalleryResponse(
          [void Function(RoleGalleryResponseBuilder)? updates]) =>
      (RoleGalleryResponseBuilder()..update(updates))._build();

  _$RoleGalleryResponse._({required this.roleId, required this.images})
      : super._();
  @override
  RoleGalleryResponse rebuild(
          void Function(RoleGalleryResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RoleGalleryResponseBuilder toBuilder() =>
      RoleGalleryResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RoleGalleryResponse &&
        roleId == other.roleId &&
        images == other.images;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, roleId.hashCode);
    _$hash = $jc(_$hash, images.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RoleGalleryResponse')
          ..add('roleId', roleId)
          ..add('images', images))
        .toString();
  }
}

class RoleGalleryResponseBuilder
    implements Builder<RoleGalleryResponse, RoleGalleryResponseBuilder> {
  _$RoleGalleryResponse? _$v;

  String? _roleId;
  String? get roleId => _$this._roleId;
  set roleId(String? roleId) => _$this._roleId = roleId;

  ListBuilder<String>? _images;
  ListBuilder<String> get images => _$this._images ??= ListBuilder<String>();
  set images(ListBuilder<String>? images) => _$this._images = images;

  RoleGalleryResponseBuilder() {
    RoleGalleryResponse._defaults(this);
  }

  RoleGalleryResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _roleId = $v.roleId;
      _images = $v.images.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RoleGalleryResponse other) {
    _$v = other as _$RoleGalleryResponse;
  }

  @override
  void update(void Function(RoleGalleryResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RoleGalleryResponse build() => _build();

  _$RoleGalleryResponse _build() {
    _$RoleGalleryResponse _$result;
    try {
      _$result = _$v ??
          _$RoleGalleryResponse._(
            roleId: BuiltValueNullFieldError.checkNotNull(
                roleId, r'RoleGalleryResponse', 'roleId'),
            images: images.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'images';
        images.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'RoleGalleryResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
