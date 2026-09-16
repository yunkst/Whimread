/// 网站书架条目（bookshelf_js 提取的单本小说）
///
/// [url] 为该站小说目录页路径，供应用跳转后复用 chapter_list_js 链路。
/// [coverUrl] 为可选封面槽位（脚本返回的 `cover_url`，与 chapter_list_js
/// 契约同形）：站点书架页通常带封面图，脚本一并提取后同步即可直接补封面；
/// 旧脚本不返回该字段（null），解析与合并链路均按可选处理。
class SiteBookshelfEntry {
  final String title;
  final String url;
  final String? coverUrl;

  const SiteBookshelfEntry({
    required this.title,
    required this.url,
    this.coverUrl,
  });

  @override
  bool operator ==(Object other) =>
      other is SiteBookshelfEntry &&
      other.url == url &&
      other.title == title &&
      other.coverUrl == coverUrl;

  @override
  int get hashCode => Object.hash(title, url, coverUrl);

  @override
  String toString() => 'SiteBookshelfEntry($title, $url, cover: $coverUrl)';
}
