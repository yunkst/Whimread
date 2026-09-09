/// 网站书架条目（bookshelf_js 提取的单本小说）
///
/// [url] 为该站小说目录页路径，供应用跳转后复用 chapter_list_js 链路。
class SiteBookshelfEntry {
  final String title;
  final String url;

  const SiteBookshelfEntry({required this.title, required this.url});

  @override
  bool operator ==(Object other) =>
      other is SiteBookshelfEntry && other.url == url && other.title == title;

  @override
  int get hashCode => Object.hash(title, url);

  @override
  String toString() => 'SiteBookshelfEntry($title, $url)';
}