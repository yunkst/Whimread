/// 站点的规范化身份（type-safe 站点键）
///
/// **这是 P1 修复爱丽丝网 no script bug 的核心类型**——把"用 host 字符串当
/// 站点 ID"的隐式假设显式化。
///
/// 现实：同一站点的 host 有多种形态
///   - `www.alice.com` / `alice.com` —— 桌面版
///   - `m.alice.com` —— 手机版
///   - `wap.alice.com` —— 早期手机版
/// 但它们指向同一站点、同一个 SiteScript 应能匹配。
///
/// [SiteKey] 把所有变体归一为「裸注册域」(bare registrable domain)：
///   - 小写
///   - 剥除已知子域前缀 `www.` / `m.` / `wap.` / `mobile.`
/// **只**剥除这四个常见前缀，更复杂的 eTLD+1（如 `co.jp`、多级子域）暂不处理，
/// 后续如遇真实案例再扩展。**不**删除其他子域（`novel.alice.com`、`bbs.alice.com`
/// 是不同子站点，不归并）。
///
/// 用法：
/// ```dart
/// final a = SiteKey.fromHost('www.alice.com');  // SiteKey('alice.com')
/// final b = SiteKey.fromHost('m.alice.com');    // SiteKey('alice.com')
/// a == b;  // true
/// ```
///
/// **不是** DNS 公共后缀解析（PSL）；若需要处理 `co.jp` 等情况应改用
/// `package:tldts` 等。本项目内站点清单有限，按四个常见前缀归一足够。
class SiteKey implements Comparable<SiteKey> {
  /// 裸注册域字符串（如 `alice.com`）
  final String value;

  const SiteKey._(this.value);

  /// 从 host 构造归一化站点键；空字符串或非字符串类型返回 null
  ///
  /// 不校验 host 是否合法 IP/DNS，仅做字符串归一化。
  static SiteKey? tryFromHost(String? host) {
    if (host == null) return null;
    final lower = host.trim().toLowerCase();
    if (lower.isEmpty) return null;
    return SiteKey._(_stripKnownPrefix(lower));
  }

  static SiteKey fromHost(String host) {
    final k = tryFromHost(host);
    if (k == null) {
      throw ArgumentError.value(host, 'host', '不能从空 host 构造 SiteKey');
    }
    return k;
  }

  /// 已知会被剥除的子域前缀（按从长到短顺序，避免误剥）
  static const _knownPrefixes = ['www.', 'mobile.', 'wap.', 'm.'];

  static String _stripKnownPrefix(String lower) {
    // 防止 `m.` 误剥裸域 `m.xxx.com`：前缀剥除后必须还含 '.'
    for (final p in _knownPrefixes) {
      if (lower.startsWith(p) && lower.length > p.length) {
        return lower.substring(p.length);
      }
    }
    return lower;
  }

  /// 是否与另一 host 等价（同一站点变体）
  bool matchesHost(String? otherHost) =>
      tryFromHost(otherHost) == this;

  @override
  bool operator ==(Object other) =>
      other is SiteKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  int compareTo(SiteKey other) => value.compareTo(other.value);

  @override
  String toString() => 'SiteKey($value)';
}
