// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workflow_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WorkflowInfo extends WorkflowInfo {
  @override
  final String title;
  @override
  final String description;
  @override
  final String? path;
  @override
  final int? width;
  @override
  final int? height;
  @override
  final bool? isDefault;

  factory _$WorkflowInfo([void Function(WorkflowInfoBuilder)? updates]) =>
      (WorkflowInfoBuilder()..update(updates))._build();

  _$WorkflowInfo._(
      {required this.title,
      required this.description,
      this.path,
      this.width,
      this.height,
      this.isDefault})
      : super._();
  @override
  WorkflowInfo rebuild(void Function(WorkflowInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WorkflowInfoBuilder toBuilder() => WorkflowInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WorkflowInfo &&
        title == other.title &&
        description == other.description &&
        path == other.path &&
        width == other.width &&
        height == other.height &&
        isDefault == other.isDefault;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, width.hashCode);
    _$hash = $jc(_$hash, height.hashCode);
    _$hash = $jc(_$hash, isDefault.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WorkflowInfo')
          ..add('title', title)
          ..add('description', description)
          ..add('path', path)
          ..add('width', width)
          ..add('height', height)
          ..add('isDefault', isDefault))
        .toString();
  }
}

class WorkflowInfoBuilder
    implements Builder<WorkflowInfo, WorkflowInfoBuilder> {
  _$WorkflowInfo? _$v;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  int? _width;
  int? get width => _$this._width;
  set width(int? width) => _$this._width = width;

  int? _height;
  int? get height => _$this._height;
  set height(int? height) => _$this._height = height;

  bool? _isDefault;
  bool? get isDefault => _$this._isDefault;
  set isDefault(bool? isDefault) => _$this._isDefault = isDefault;

  WorkflowInfoBuilder() {
    WorkflowInfo._defaults(this);
  }

  WorkflowInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _title = $v.title;
      _description = $v.description;
      _path = $v.path;
      _width = $v.width;
      _height = $v.height;
      _isDefault = $v.isDefault;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WorkflowInfo other) {
    _$v = other as _$WorkflowInfo;
  }

  @override
  void update(void Function(WorkflowInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WorkflowInfo build() => _build();

  _$WorkflowInfo _build() {
    final _$result = _$v ??
        _$WorkflowInfo._(
          title: BuiltValueNullFieldError.checkNotNull(
              title, r'WorkflowInfo', 'title'),
          description: BuiltValueNullFieldError.checkNotNull(
              description, r'WorkflowInfo', 'description'),
          path: path,
          width: width,
          height: height,
          isDefault: isDefault,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
