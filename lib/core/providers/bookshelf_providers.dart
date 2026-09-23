/// Riverpod Providers for BookshelfScreen
///
/// 管理书架屏幕的所有状态和依赖
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riverpod/riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../models/bookshelf.dart';
import '../../models/novel.dart';
import '../../core/providers/database_providers.dart';
import '../../core/providers/service_providers.dart';
import '../../services/logger_service.dart';
import '../../services/preferences_service.dart';

part 'bookshelf_providers.g.dart';

/// 当前选中的书架
///
/// 书架由"小说来源"派生，用户不可调整：全部/原创固定 +
/// 联网按来源网站（URL host）拆分。支持持久化保存用户选择，
/// 重启 app 后恢复上次打开的书架：
/// - 新键 `current_bookshelf_kind` 存 [Bookshelf.toPersistedValue]
///   （`all` / `original` / `online:<host>`）
/// - 旧键 `current_bookshelf_id`（int）存在时经 [Bookshelf.fromLegacyId] 兜底映射
@riverpod
class CurrentBookshelf extends _$CurrentBookshelf {
  static const String _newKey = 'current_bookshelf_kind';
  static const String _legacyKey = 'current_bookshelf_id';

  @override
  Bookshelf build() {
    // 异步加载已保存的书架分类
    // 使用ref.read访问PreferencesService以支持测试
    final prefsService = ref.watch(preferencesServiceProvider);
    _loadSaved(prefsService);
    // 立即返回默认值，避免阻塞UI渲染
    return Bookshelf.systemShelves.first;
  }

  /// 从SharedPreferences加载保存的书架
  Future<void> _loadSaved(PreferencesService prefsService) async {
    try {
      // 优先读新键（`all` / `original` / `online:<host>`）
      final savedName = await prefsService.getString(_newKey);
      if (savedName.isNotEmpty) {
        final shelf = Bookshelf.fromPersistedValue(savedName);
        LoggerService.instance.d(
          '书架加载完成: $shelf',
          category: LogCategory.ui,
          tags: ['provider', 'bookshelf', 'load'],
        );
        state = shelf;
        return;
      }

      // 兜底：读旧键（int 书架 ID），映射到新分类
      final legacyId = await prefsService.getInt(_legacyKey, defaultValue: 1);
      final shelf = Bookshelf.fromLegacyId(legacyId);
      LoggerService.instance.d(
        '书架从旧 ID 兜底加载: legacyId=$legacyId -> $shelf',
        category: LogCategory.ui,
        tags: ['provider', 'bookshelf', 'load'],
      );
      state = shelf;
    } catch (e, st) {
      LoggerService.instance.e(
        '加载书架失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ui,
        tags: ['provider', 'bookshelf', 'load'],
      );
    }
  }

  /// 设置当前书架并持久化
  void setBookshelf(Bookshelf shelf) {
    state = shelf;
    // 保存到SharedPreferences（使用Provider以支持测试）
    final prefsService = ref.read(preferencesServiceProvider);
    prefsService.setString(_newKey, shelf.toPersistedValue());
  }
}

/// 有藏书的联网来源站点 host 列表
///
/// 供 [bookshelfShelvesProvider] 生成按站点拆分的联网 Tab；
/// 依赖 [onlineNovelsProvider] 使增删小说后 Tab 列表同步刷新。
@riverpod
Future<List<String>> bookshelfSiteDomains(Ref ref) async {
  await ref.watch(onlineNovelsProvider.future);
  final bookshelfRepository = ref.watch(bookshelfRepositoryProvider);
  return bookshelfRepository.getOnlineSourceDomains();
}

/// 站点显示名映射（`domain -> display_name`）
///
/// 取自 `site_scripts.display_name`（提取 Agent 在 save_script 时从页面
/// 推断登记，如 `www.qidian.com -> 起点中文网`）。与 [onlineNovelsProvider]
/// 同生命周期：提取会话导入小说后随 Tab 列表一起刷新。
@riverpod
Future<Map<String, String>> siteDisplayNames(Ref ref) async {
  await ref.watch(onlineNovelsProvider.future);
  final siteScriptRepository = ref.watch(siteScriptRepositoryProvider);
  return siteScriptRepository.getDisplayNamesByDomain();
}

/// 书架 Tab 列表
///
/// 全部/原创固定 + 按来源站点拆分的联网书架（见 [Bookshelf.tabShelves]）。
/// 站点 Tab 名优先用 [siteDisplayNamesProvider] 登记的站点名，回退 host。
@riverpod
Future<List<Bookshelf>> bookshelfShelves(Ref ref) async {
  final siteDomains = await ref.watch(bookshelfSiteDomainsProvider.future);
  final displayNames = await ref.watch(siteDisplayNamesProvider.future);
  return Bookshelf.tabShelves(siteDomains, displayNames: displayNames);
}

/// 联网小说列表（全部站点聚合）
///
/// 站点 Tab 列表的数据源；增删小说后经 invalidate 刷新。
@riverpod
Future<List<Novel>> onlineNovels(Ref ref) async {
  final bookshelfRepository = ref.watch(bookshelfRepositoryProvider);
  return bookshelfRepository.getNovelsByBookshelf(BookshelfKind.online);
}

/// 指定书架的小说列表（family · keepAlive）
///
/// 卡片式滑动切换需要相邻书架的数据即时可用，故按 [Bookshelf] 分桶缓存并
/// keepAlive（避免离开书架页后再回来被 autoDispose 清掉），保证跟手滑动时
/// 下一张"卡片"已经渲染完成。
///
/// 写路径经 [BookshelfMutationNotifier] invalidate 整个 family 刷新。
@Riverpod(keepAlive: true)
Future<List<Novel>> shelfNovels(Ref ref, Bookshelf shelf) async {
  // Web环境特殊处理
  if (kIsWeb) {
    return [
      Novel(
        title: '测试小说1',
        author: '测试作者1',
        url: 'https://example.com/novel1',
        coverUrl: '',
        description: '这是一个测试小说描述',
      ),
      Novel(
        title: '测试小说2',
        author: '测试作者2',
        url: 'https://example.com/novel2',
        coverUrl: '',
        description: '这是另一个测试小说描述',
      ),
    ];
  }

  final bookshelfRepository = ref.watch(bookshelfRepositoryProvider);
  try {
    final novels = shelf.isSiteShelf
        ? await bookshelfRepository.getNovelsBySourceDomain(shelf.domain!)
        : await bookshelfRepository.getNovelsByBookshelf(shelf.kind);
    LoggerService.instance.d(
      '书架小说列表加载成功: shelf=$shelf, count=${novels.length}',
      category: LogCategory.database,
      tags: ['provider', 'bookshelf', 'load'],
    );
    return novels;
  } catch (e, st) {
    LoggerService.instance.e(
      '加载书架小说列表失败: $e',
      stackTrace: st.toString(),
      category: LogCategory.database,
      tags: ['provider', 'bookshelf', 'load'],
    );
    rethrow;
  }
}

/// 指定书架的缓存统计（family · keepAlive）
///
/// 缓存统计依赖同书架的小说列表；同 [shelfNovelsProvider] 一起 keepAlive，
/// 保证滑动切换时元信息条 / 章节进度条数据不抖。
@Riverpod(keepAlive: true)
Future<Map<String, CacheStats>> shelfCacheStats(Ref ref, Bookshelf shelf) async {
  final novels = await ref.watch(shelfNovelsProvider(shelf).future);
  final chapterRepo = ref.watch(chapterRepositoryProvider);

  final stats = <String, CacheStats>{};
  for (final novel in novels) {
    final cached = await chapterRepo.getCachedChaptersCount(novel.url);
    final total = await chapterRepo.getTotalChaptersCount(novel.url);
    if (total > 0) {
      stats[novel.url] = CacheStats(cached: cached, total: total);
    }
  }
  return stats;
}

/// 书架小说列表（当前书架的快捷视图 · 兼容层）
///
/// 委托到 [shelfNovelsProvider(currentBookshelf)]。保留此 provider 以维持
/// 旧 API / 既有注释契约；写路径 invalidate 仅作触发信号，真正数据刷新
/// 由 family 的 invalidate 完成（见 [BookshelfMutationNotifier._wrap]）。
@riverpod
Future<List<Novel>> bookshelfNovels(Ref ref) {
  final shelf = ref.watch(currentBookshelfProvider);
  return ref.watch(shelfNovelsProvider(shelf).future);
}

/// 书架小说列表缓存统计（当前书架的快捷视图 · 兼容层）
///
/// 委托到 [shelfCacheStatsProvider(currentBookshelf)]。
@riverpod
Future<Map<String, CacheStats>> bookshelfCacheStats(Ref ref) {
  final shelf = ref.watch(currentBookshelfProvider);
  return ref.watch(shelfCacheStatsProvider(shelf).future);
}

/// 缓存统计
class CacheStats {
  final int cached;
  final int total;

  const CacheStats({required this.cached, required this.total});

  double get percent => total > 0 ? (cached / total).clamp(0.0, 1.0) : 0.0;
}