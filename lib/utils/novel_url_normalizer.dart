/// 小说 URL 归一化工具（仅用于**比较**，不改变落库值）
///
/// 书架去重以 URL 为唯一键（`bookshelf.url UNIQUE`），但两条入库路径对同一本
/// 书很可能拿到字符串不同、语义相同的 URL：
/// - 手动添加（FAB）：存浏览器**当前页 URL**（用户恰好在哪个变体页上就存哪个）
/// - 书架同步：存 `bookshelf_js` 从书架页 HTML 提取的 href 原文
///
/// 常见机械差异：http/https、`www.`/`m.` 手机域、尾部斜杠、锚点、默认端口、
/// scheme/host 大小写。逐字比较会把这些当两本书，书架出现重复条目。
///
/// 设计约束：**归一化只参与判定，不写库**。章节缓存（novel_chapters）、阅读
/// 进度等都以首次入库的原始 URL 为键，改写存量 URL 会打散关联数据。
library;

class NovelUrlNormalizer {
  NovelUrlNormalizer._();

  /// 原创小说 URL 前缀（与 BookshelfRepository._originalPrefix 一致）。
  /// 原创标识由应用内生成、格式稳定，不做归一化。
  static const String _originalPrefix = 'custom://';

  /// 桌面/手机 UA 下同一站点的常见 host 前缀变体
  static const List<String> _hostPrefixAliases = ['www.', 'm.', 'mobile.'];

  /// 归一化 URL，用于比较是否指同一本书。
  ///
  /// - trim；`custom://` 开头原样返回
  /// - scheme/host 小写、去默认端口（80/443）、去 fragment、去路径尾部 `/`
  /// - query 保留（个别站点用 query 区分页面，抹掉风险大于收益）
  /// - 解析失败 → 返回 trim 后的原文（保守：只做精确比较）
  static String normalize(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.toLowerCase().startsWith(_originalPrefix)) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return trimmed;

    final rawScheme = uri.scheme.toLowerCase();
    if (rawScheme.isEmpty) return trimmed;
    // http/https 视为同一资源（站点升级 TLS 前后同一本书），仅用于比较
    final scheme = rawScheme == 'http' ? 'https' : rawScheme;

    final host = uri.host.toLowerCase();
    var port = uri.hasPort ? uri.port : 0;
    if ((scheme == 'http' && port == 80) || (scheme == 'https' && port == 443)) {
      port = 0;
    }
    var path = uri.path;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path == '/') path = '';
    final portPart = port > 0 ? ':$port' : '';
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return '$scheme://$host$portPart$path$query';
  }

  /// 两个 URL 归一化后是否相同（"同一本书"的宽松判定）
  static bool looselyEquals(String a, String b) =>
      normalize(a) == normalize(b);

  /// 去掉 `www.`/`m.`/`mobile.` 前缀后的 host（小写），用于同站判定。
  /// 只剥一层前缀：`www.x.com` 与 `m.x.com` 都归到 `x.com`。
  static String canonicalHost(String host) {
    var h = host.trim().toLowerCase();
    for (final prefix in _hostPrefixAliases) {
      if (h.startsWith(prefix)) {
        h = h.substring(prefix.length);
        break;
      }
    }
    return h;
  }

  /// 两个 host 是否视为同一站点（忽略 www/手机域前缀变体）
  static bool sameSiteHost(String a, String b) {
    final ca = canonicalHost(a);
    if (ca.isEmpty) return false;
    return ca == canonicalHost(b);
  }
}
