/// 脚本存在感知（缓存型）
///
/// 解决「FAB 应在到达有缓存 chapter_list_js 的页面时变金色」的需求：
/// - `webviewCurrentSiteScriptProvider` 是 FutureProvider，在 widget build 中
///   `ref.watch` 会立即触发 DB 查询。而 `webviewCurrentUrlProvider` 默认值是
///   `'https://so.com'`，导致所有 WebView 屏幕一挂载就发起 DB 查询——
//    sqflite 在无平台 channel 的 widget 测试环境下会留下 pending Timer，
///   触发 "A Timer is still pending" 失败。
/// - 因此改为**同步缓存**：Notifier 持有 `Map<domain, bool>`；domain 变化时由
///   `webview_browser_screen` 的 `ref.listen` 回调（非 build 阶段）fire-and-forget
///   查一次库并写回缓存。FAB 仅 `ref.watch` 同步 Provider 读缓存，绝不在
///   build 中发起异步。
///
/// 数据流：`webviewCurrentDomainProvider` 变化
///   → `refreshScriptPresence`（listener 内）
///   → `SiteScriptRepository.getByDomain`
///   → `ScriptPresenceNotifier.put(domain, hasChapterListJs)`
///   → `webviewHasCachedChapterListScriptProvider` 同步更新 → FAB 变色。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'webview_add_novel_providers.dart';

/// 域名 → 是否有 chapter_list_js 缓存脚本 的同步缓存
///
/// key: domain（host）；value: true = 该域名有可用的 chapter_list_js 脚本，
/// false = 已查实该域名无脚本。缺失 key 表示尚未查询（保守返回 false）。
final scriptPresenceByDomainProvider =
    NotifierProvider<ScriptPresenceNotifier, Map<String, bool>>(
  ScriptPresenceNotifier.new,
);

class ScriptPresenceNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const {};

  /// 写回某域名的脚本存在性查询结果
  void put(String domain, bool hasCachedChapterListJs) {
    // 同值跳过，避免无谓的 listener 级联触发
    if (state[domain] == hasCachedChapterListJs) return;
    state = {...state, domain: hasCachedChapterListJs};
  }

  /// 清除某域名的缓存（脚本被删除/重新生成时可调用，强制下次重新查库）
  void invalidateDomain(String domain) {
    if (!state.containsKey(domain)) return;
    final next = {...state}..remove(domain);
    state = next;
  }
}

/// 查询函数类型：domain → 该域名是否有 chapter_list_js 缓存脚本
typedef ScriptPresenceFetcher = Future<bool> Function(String domain);

/// 异步刷新某域名的缓存（fire-and-forget，须在 ref.listen 回调中调用，
/// 不要在 widget build 中调用）
///
/// 查询失败时静默跳过（不写缓存，保持缺失态，下次 domain 变化会再试）。
/// [fetch]/[onResult] 均为注入点，便于单测绕开 WebView/DB 平台依赖。
Future<void> refreshScriptPresence({
  required String domain,
  required ScriptPresenceFetcher fetch,
  required void Function(String domain, bool hasScript) onResult,
}) async {
  try {
    onResult(domain, await fetch(domain));
  } catch (_) {
    // 失败保守：不写缓存
  }
}

/// 当前域名是否有可用的 chapter_list_js 缓存脚本（同步派生 Provider）
///
/// FAB `webview_add_novel_button` watch 此值：有 → 金色（快速提取可用）；
/// 无 → 默认色，点击降级到 Agent 生成脚本流程。
final webviewHasCachedChapterListScriptProvider = Provider<bool>((ref) {
  final domain = ref.watch(webviewCurrentDomainProvider);
  if (domain == null) return false;
  final cache = ref.watch(scriptPresenceByDomainProvider);
  return cache[domain] ?? false;
});