// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'novel_with_chapters.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NovelWithChapters extends NovelWithChapters {
  @override
  final Novel novel;
  @override
  final BuiltList<Chapter> chapters;

  factory _$NovelWithChapters(
          [void Function(NovelWithChaptersBuilder)? updates]) =>
      (NovelWithChaptersBuilder()..update(updates))._build();

  _$NovelWithChapters._({required this.novel, required this.chapters})
      : super._();
  @override
  NovelWithChapters rebuild(void Function(NovelWithChaptersBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  NovelWithChaptersBuilder toBuilder() =>
      NovelWithChaptersBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NovelWithChapters &&
        novel == other.novel &&
        chapters == other.chapters;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, novel.hashCode);
    _$hash = $jc(_$hash, chapters.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NovelWithChapters')
          ..add('novel', novel)
          ..add('chapters', chapters))
        .toString();
  }
}

class NovelWithChaptersBuilder
    implements Builder<NovelWithChapters, NovelWithChaptersBuilder> {
  _$NovelWithChapters? _$v;

  NovelBuilder? _novel;
  NovelBuilder get novel => _$this._novel ??= NovelBuilder();
  set novel(NovelBuilder? novel) => _$this._novel = novel;

  ListBuilder<Chapter>? _chapters;
  ListBuilder<Chapter> get chapters =>
      _$this._chapters ??= ListBuilder<Chapter>();
  set chapters(ListBuilder<Chapter>? chapters) => _$this._chapters = chapters;

  NovelWithChaptersBuilder() {
    NovelWithChapters._defaults(this);
  }

  NovelWithChaptersBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _novel = $v.novel.toBuilder();
      _chapters = $v.chapters.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NovelWithChapters other) {
    _$v = other as _$NovelWithChapters;
  }

  @override
  void update(void Function(NovelWithChaptersBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NovelWithChapters build() => _build();

  _$NovelWithChapters _build() {
    _$NovelWithChapters _$result;
    try {
      _$result = _$v ??
          _$NovelWithChapters._(
            novel: novel.build(),
            chapters: chapters.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'novel';
        novel.build();
        _$failedField = 'chapters';
        chapters.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'NovelWithChapters', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
