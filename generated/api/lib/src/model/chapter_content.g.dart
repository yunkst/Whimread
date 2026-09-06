// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chapter_content.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ChapterContent extends ChapterContent {
  @override
  final String title;
  @override
  final String content;
  @override
  final bool? fromCache;

  factory _$ChapterContent([void Function(ChapterContentBuilder)? updates]) =>
      (ChapterContentBuilder()..update(updates))._build();

  _$ChapterContent._(
      {required this.title, required this.content, this.fromCache})
      : super._();
  @override
  ChapterContent rebuild(void Function(ChapterContentBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ChapterContentBuilder toBuilder() => ChapterContentBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ChapterContent &&
        title == other.title &&
        content == other.content &&
        fromCache == other.fromCache;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, content.hashCode);
    _$hash = $jc(_$hash, fromCache.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ChapterContent')
          ..add('title', title)
          ..add('content', content)
          ..add('fromCache', fromCache))
        .toString();
  }
}

class ChapterContentBuilder
    implements Builder<ChapterContent, ChapterContentBuilder> {
  _$ChapterContent? _$v;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _content;
  String? get content => _$this._content;
  set content(String? content) => _$this._content = content;

  bool? _fromCache;
  bool? get fromCache => _$this._fromCache;
  set fromCache(bool? fromCache) => _$this._fromCache = fromCache;

  ChapterContentBuilder() {
    ChapterContent._defaults(this);
  }

  ChapterContentBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _title = $v.title;
      _content = $v.content;
      _fromCache = $v.fromCache;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ChapterContent other) {
    _$v = other as _$ChapterContent;
  }

  @override
  void update(void Function(ChapterContentBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ChapterContent build() => _build();

  _$ChapterContent _build() {
    final _$result = _$v ??
        _$ChapterContent._(
          title: BuiltValueNullFieldError.checkNotNull(
              title, r'ChapterContent', 'title'),
          content: BuiltValueNullFieldError.checkNotNull(
              content, r'ChapterContent', 'content'),
          fromCache: fromCache,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
