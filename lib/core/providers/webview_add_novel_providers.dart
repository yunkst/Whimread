/// WebView「添加小说」相关 Provider
///
/// 三个反应式 Provider，监听当前 URL，自动判断是否应该显示「添加小说」按钮：
///   1. `webviewCurrentDomainProvider` —— 提取当前 URL 的 host
///   2. `webviewCurrentSiteScriptProvider` —— 按 host 查询 site_scripts
///   3. `webviewHasAddNovelButtonProvider` —— 是否显示按钮（基于脚本是否有 chapterListJs）
///
/// FAB 按钮和提取流程都依赖 `webviewCurrentSiteScriptProvider.valueOrNull`，
/// 避免重复查询数据库。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/site_script.dart';
import 'database_providers.dart';
import 'webview_providers.dart';

/// 当前 URL 的 host（domain）
///
/// 监听 `webviewCurrentUrlProvider`，提取 URI 的 host 部分。
/// 无效 URL / 非 http(s) 协议 → 返回 `null`。
final webviewCurrentDomainProvider = Provider<String?>((ref) {
  final currentUrl = ref.watch(webviewCurrentUrlProvider);
  if (currentUrl.isEmpty) return null;

  final uri = Uri.tryParse(currentUrl);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;

  return uri.host;
});

/// 当前域名的 SiteScript 缓存
///
/// - domain 为 null → 返回 `null`（同步），不触发 IO
/// - 否则通过 `SiteScriptRepository.getByDomain` 异步查询
///
/// FAB 按钮可见性 + 提取流程都通过此 Provider 复用查询结果。
final webviewCurrentSiteScriptProvider =
    FutureProvider<SiteScript?>((ref) async {
  final domain = ref.watch(webviewCurrentDomainProvider);
  if (domain == null) return null;

  final repository = ref.watch(siteScriptRepositoryProvider);
  return repository.getByDomain(domain);
});

/// 是否显示"添加到书架"FAB
///
/// 改为：当前页是 http(s) 页面即显示（无脚本时点击走 agent 降级生成）。
final webviewHasAddNovelButtonProvider = Provider<bool>((ref) {
  final domain = ref.watch(webviewCurrentDomainProvider);
  return domain != null;
});
