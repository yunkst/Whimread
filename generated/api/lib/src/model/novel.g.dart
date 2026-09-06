// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'novel.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Novel extends Novel {
  @override
  final String title;
  @override
  final String author;
  @override
  final String url;

  factory _$Novel([void Function(NovelBuilder)? updates]) =>
      (NovelBuilder()..update(updates))._build();

  _$Novel._({required this.title, required this.author, required this.url})
      : super._();
  @override
  Novel rebuild(void Function(NovelBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  NovelBuilder toBuilder() => NovelBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Novel &&
        title == other.title &&
        author == other.author &&
        url == other.url;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, author.hashCode);
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Novel')
          ..add('title', title)
          ..add('author', author)
          ..add('url', url))
        .toString();
  }
}

class NovelBuilder implements Builder<Novel, NovelBuilder> {
  _$Novel? _$v;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _author;
  String? get author => _$this._author;
  set author(String? author) => _$this._author = author;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  NovelBuilder() {
    Novel._defaults(this);
  }

  NovelBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _title = $v.title;
      _author = $v.author;
      _url = $v.url;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Novel other) {
    _$v = other as _$Novel;
  }

  @override
  void update(void Function(NovelBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Novel build() => _build();

  _$Novel _build() {
    final _$result = _$v ??
        _$Novel._(
          title:
              BuiltValueNullFieldError.checkNotNull(title, r'Novel', 'title'),
          author:
              BuiltValueNullFieldError.checkNotNull(author, r'Novel', 'author'),
          url: BuiltValueNullFieldError.checkNotNull(url, r'Novel', 'url'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
