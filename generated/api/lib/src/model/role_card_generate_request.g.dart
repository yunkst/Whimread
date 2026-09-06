// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'role_card_generate_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RoleCardGenerateRequest extends RoleCardGenerateRequest {
  @override
  final String roleId;
  @override
  final BuiltList<RoleInfo> roles;
  @override
  final String? model;

  factory _$RoleCardGenerateRequest(
          [void Function(RoleCardGenerateRequestBuilder)? updates]) =>
      (RoleCardGenerateRequestBuilder()..update(updates))._build();

  _$RoleCardGenerateRequest._(
      {required this.roleId, required this.roles, this.model})
      : super._();
  @override
  RoleCardGenerateRequest rebuild(
          void Function(RoleCardGenerateRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RoleCardGenerateRequestBuilder toBuilder() =>
      RoleCardGenerateRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RoleCardGenerateRequest &&
        roleId == other.roleId &&
        roles == other.roles &&
        model == other.model;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, roleId.hashCode);
    _$hash = $jc(_$hash, roles.hashCode);
    _$hash = $jc(_$hash, model.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RoleCardGenerateRequest')
          ..add('roleId', roleId)
          ..add('roles', roles)
          ..add('model', model))
        .toString();
  }
}

class RoleCardGenerateRequestBuilder
    implements
        Builder<RoleCardGenerateRequest, RoleCardGenerateRequestBuilder> {
  _$RoleCardGenerateRequest? _$v;

  String? _roleId;
  String? get roleId => _$this._roleId;
  set roleId(String? roleId) => _$this._roleId = roleId;

  ListBuilder<RoleInfo>? _roles;
  ListBuilder<RoleInfo> get roles => _$this._roles ??= ListBuilder<RoleInfo>();
  set roles(ListBuilder<RoleInfo>? roles) => _$this._roles = roles;

  String? _model;
  String? get model => _$this._model;
  set model(String? model) => _$this._model = model;

  RoleCardGenerateRequestBuilder() {
    RoleCardGenerateRequest._defaults(this);
  }

  RoleCardGenerateRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _roleId = $v.roleId;
      _roles = $v.roles.toBuilder();
      _model = $v.model;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RoleCardGenerateRequest other) {
    _$v = other as _$RoleCardGenerateRequest;
  }

  @override
  void update(void Function(RoleCardGenerateRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RoleCardGenerateRequest build() => _build();

  _$RoleCardGenerateRequest _build() {
    _$RoleCardGenerateRequest _$result;
    try {
      _$result = _$v ??
          _$RoleCardGenerateRequest._(
            roleId: BuiltValueNullFieldError.checkNotNull(
                roleId, r'RoleCardGenerateRequest', 'roleId'),
            roles: roles.build(),
            model: model,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'roles';
        roles.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'RoleCardGenerateRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
