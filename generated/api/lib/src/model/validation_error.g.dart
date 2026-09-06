// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'validation_error.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ValidationError extends ValidationError {
  @override
  final BuiltList<ValidationErrorLocInner> loc;
  @override
  final String msg;
  @override
  final String type;
  @override
  final JsonObject? input;
  @override
  final JsonObject? ctx;

  factory _$ValidationError([void Function(ValidationErrorBuilder)? updates]) =>
      (ValidationErrorBuilder()..update(updates))._build();

  _$ValidationError._(
      {required this.loc,
      required this.msg,
      required this.type,
      this.input,
      this.ctx})
      : super._();
  @override
  ValidationError rebuild(void Function(ValidationErrorBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ValidationErrorBuilder toBuilder() => ValidationErrorBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ValidationError &&
        loc == other.loc &&
        msg == other.msg &&
        type == other.type &&
        input == other.input &&
        ctx == other.ctx;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, loc.hashCode);
    _$hash = $jc(_$hash, msg.hashCode);
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, input.hashCode);
    _$hash = $jc(_$hash, ctx.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ValidationError')
          ..add('loc', loc)
          ..add('msg', msg)
          ..add('type', type)
          ..add('input', input)
          ..add('ctx', ctx))
        .toString();
  }
}

class ValidationErrorBuilder
    implements Builder<ValidationError, ValidationErrorBuilder> {
  _$ValidationError? _$v;

  ListBuilder<ValidationErrorLocInner>? _loc;
  ListBuilder<ValidationErrorLocInner> get loc =>
      _$this._loc ??= ListBuilder<ValidationErrorLocInner>();
  set loc(ListBuilder<ValidationErrorLocInner>? loc) => _$this._loc = loc;

  String? _msg;
  String? get msg => _$this._msg;
  set msg(String? msg) => _$this._msg = msg;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  JsonObject? _input;
  JsonObject? get input => _$this._input;
  set input(JsonObject? input) => _$this._input = input;

  JsonObject? _ctx;
  JsonObject? get ctx => _$this._ctx;
  set ctx(JsonObject? ctx) => _$this._ctx = ctx;

  ValidationErrorBuilder() {
    ValidationError._defaults(this);
  }

  ValidationErrorBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _loc = $v.loc.toBuilder();
      _msg = $v.msg;
      _type = $v.type;
      _input = $v.input;
      _ctx = $v.ctx;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ValidationError other) {
    _$v = other as _$ValidationError;
  }

  @override
  void update(void Function(ValidationErrorBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ValidationError build() => _build();

  _$ValidationError _build() {
    _$ValidationError _$result;
    try {
      _$result = _$v ??
          _$ValidationError._(
            loc: loc.build(),
            msg: BuiltValueNullFieldError.checkNotNull(
                msg, r'ValidationError', 'msg'),
            type: BuiltValueNullFieldError.checkNotNull(
                type, r'ValidationError', 'type'),
            input: input,
            ctx: ctx,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'loc';
        loc.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ValidationError', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
