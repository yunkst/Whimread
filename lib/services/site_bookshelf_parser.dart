/// 网站书架脚本（bookshelf_js）返回值的纯解析器
///
/// 与 headless_webview_chapter_list_service 的脚本返回契约一致：
/// 顶层 `{novels: [{title, url}, ...]}`（snake_case）。
/// 每条必须 title/url 非空；缺失字段、类型错误、空数组统一返回 null。
///
/// 抽出为纯函数便于单测，避免在 widget 测试里构造 HeadlessInAppWebView。
library;

import 'dart:convert';

import '../models/site_bookshelf_entry.dart';

class SiteBookshelfParser {
  SiteBookshelfParser._();

  /// 解析 bookshelf_js 返回的 JSON 字符串。
  ///
  /// 返回非 null 表示成功；返回 null 表示解析失败（结构异常 / novels 为空 /
  /// 某项字段缺失）。任何异常（jsonDecode 抛 FormatException 等）也返回 null。
  static List<SiteBookshelfEntry>? parse(String jsonStr) {
    Object? decoded;
    try {
      decoded = jsonDecode(jsonStr);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final novels = decoded['novels'];
    if (novels is! List || novels.isEmpty) return null;

    final out = <SiteBookshelfEntry>[];
    for (final n in novels) {
      if (n is! Map) continue;
      final title = n['title']?.toString().trim();
      final url = n['url']?.toString().trim();
      if (title == null || title.isEmpty || url == null || url.isEmpty) continue;
      out.add(SiteBookshelfEntry(title: title, url: url));
    }
    return out.isEmpty ? null : out;
  }
}