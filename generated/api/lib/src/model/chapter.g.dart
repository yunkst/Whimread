// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chapter.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Chapter extends Chapter {
  @override
  final String title;
  @override
  final String url;

  factory _$Chapter([void Function(ChapterBuilder)? updates]) =>
      (ChapterBuilder()..update(updates))._build();

  _$Chapter._({required this.title, required this.url}) : super._();
  @override
  Chapter rebuild(void Function(ChapterBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ChapterBuilder toBuilder() => ChapterBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Chapter && title == other.title && url == other.url;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Chapter')
          ..add('title', title)
          ..add('url', url))
        .toString();
  }
}

class ChapterBuilder implements Builder<Chapter, ChapterBuilder> {
  _$Chapter? _$v;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  ChapterBuilder() {
    Chapter._defaults(this);
  }

  ChapterBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _title = $v.title;
      _url = $v.url;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Chapter other) {
    _$v = other as _$Chapter;
  }

  @override
  void update(void Function(ChapterBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Chapter build() => _build();

  _$Chapter _build() {
    final _$result = _$v ??
        _$Chapter._(
          title:
              BuiltValueNullFieldError.checkNotNull(title, r'Chapter', 'title'),
          url: BuiltValueNullFieldError.checkNotNull(url, r'Chapter', 'url'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
