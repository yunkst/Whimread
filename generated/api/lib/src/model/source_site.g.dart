// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'source_site.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SourceSite extends SourceSite {
  @override
  final String id;
  @override
  final String name;
  @override
  final String baseUrl;
  @override
  final String description;
  @override
  final bool enabled;
  @override
  final bool searchEnabled;
  @override
  final String? searchReason;
  @override
  final String? searchHint;

  factory _$SourceSite([void Function(SourceSiteBuilder)? updates]) =>
      (SourceSiteBuilder()..update(updates))._build();

  _$SourceSite._(
      {required this.id,
      required this.name,
      required this.baseUrl,
      required this.description,
      required this.enabled,
      required this.searchEnabled,
      this.searchReason,
      this.searchHint})
      : super._();
  @override
  SourceSite rebuild(void Function(SourceSiteBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SourceSiteBuilder toBuilder() => SourceSiteBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SourceSite &&
        id == other.id &&
        name == other.name &&
        baseUrl == other.baseUrl &&
        description == other.description &&
        enabled == other.enabled &&
        searchEnabled == other.searchEnabled &&
        searchReason == other.searchReason &&
        searchHint == other.searchHint;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, baseUrl.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, enabled.hashCode);
    _$hash = $jc(_$hash, searchEnabled.hashCode);
    _$hash = $jc(_$hash, searchReason.hashCode);
    _$hash = $jc(_$hash, searchHint.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SourceSite')
          ..add('id', id)
          ..add('name', name)
          ..add('baseUrl', baseUrl)
          ..add('description', description)
          ..add('enabled', enabled)
          ..add('searchEnabled', searchEnabled)
          ..add('searchReason', searchReason)
          ..add('searchHint', searchHint))
        .toString();
  }
}

class SourceSiteBuilder implements Builder<SourceSite, SourceSiteBuilder> {
  _$SourceSite? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _baseUrl;
  String? get baseUrl => _$this._baseUrl;
  set baseUrl(String? baseUrl) => _$this._baseUrl = baseUrl;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  bool? _enabled;
  bool? get enabled => _$this._enabled;
  set enabled(bool? enabled) => _$this._enabled = enabled;

  bool? _searchEnabled;
  bool? get searchEnabled => _$this._searchEnabled;
  set searchEnabled(bool? searchEnabled) =>
      _$this._searchEnabled = searchEnabled;

  String? _searchReason;
  String? get searchReason => _$this._searchReason;
  set searchReason(String? searchReason) => _$this._searchReason = searchReason;

  String? _searchHint;
  String? get searchHint => _$this._searchHint;
  set searchHint(String? searchHint) => _$this._searchHint = searchHint;

  SourceSiteBuilder() {
    SourceSite._defaults(this);
  }

  SourceSiteBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _baseUrl = $v.baseUrl;
      _description = $v.description;
      _enabled = $v.enabled;
      _searchEnabled = $v.searchEnabled;
      _searchReason = $v.searchReason;
      _searchHint = $v.searchHint;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SourceSite other) {
    _$v = other as _$SourceSite;
  }

  @override
  void update(void Function(SourceSiteBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SourceSite build() => _build();

  _$SourceSite _build() {
    final _$result = _$v ??
        _$SourceSite._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'SourceSite', 'id'),
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'SourceSite', 'name'),
          baseUrl: BuiltValueNullFieldError.checkNotNull(
              baseUrl, r'SourceSite', 'baseUrl'),
          description: BuiltValueNullFieldError.checkNotNull(
              description, r'SourceSite', 'description'),
          enabled: BuiltValueNullFieldError.checkNotNull(
              enabled, r'SourceSite', 'enabled'),
          searchEnabled: BuiltValueNullFieldError.checkNotNull(
              searchEnabled, r'SourceSite', 'searchEnabled'),
          searchReason: searchReason,
          searchHint: searchHint,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
