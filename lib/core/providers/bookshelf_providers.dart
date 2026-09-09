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

/// 当前选中的书架分类
///
/// 三档系统分类（全部/原创/联网），由"小说来源"派生，用户不可调整。
/// 支持持久化保存用户选择，重启 app 后恢复上次打开的书架：
/// - 新键 `current_bookshelf_kind` 存 [BookshelfKind.name]
/// - 旧键 `current_bookshelf_id`（int）存在时经 [Bookshelf.fromLegacyId] 兜底映射
@riverpod
class CurrentBookshelfKind extends _$CurrentBookshelfKind {
  static const String _newKey = 'current_bookshelf_kind';
  static const String _legacyKey = 'current_bookshelf_id';

  @override
  BookshelfKind build() {
    // 异步加载已保存的书架分类
    // 使用ref.read访问PreferencesService以支持测试
    final prefsService = ref.watch(preferencesServiceProvider);
    _loadSavedKind(prefsService);
    // 立即返回默认值，避免阻塞UI渲染
    return BookshelfKind.all;
  }

  /// 从SharedPreferences加载保存的书架分类
  Future<void> _loadSavedKind(PreferencesService prefsService) async {
    try {
      // 优先读新键（字符串枚举名）
      final savedName = await prefsService.getString(_newKey);
      if (savedName.isNotEmpty) {
        final kind = BookshelfKind.values.firstWhere(
          (k) => k.name == savedName,
          orElse: () => BookshelfKind.all,
        );
        LoggerService.instance.d(
          '书架分类加载完成: $kind',
          category: LogCategory.ui,
          tags: ['provider', 'bookshelf', 'load'],
        );
        state = kind;
        return;
      }

      // 兜底：读旧键（int 书架 ID），映射到新三档
      final legacyId = await prefsService.getInt(_legacyKey, defaultValue: 1);
      final kind = Bookshelf.fromLegacyId(legacyId).kind;
      LoggerService.instance.d(
        '书架分类从旧 ID 兜底加载: legacyId=$legacyId -> $kind',
        category: LogCategory.ui,
        tags: ['provider', 'bookshelf', 'load'],
      );
      state = kind;
    } catch (e, st) {
      LoggerService.instance.e(
        '加载书架分类失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ui,
        tags: ['provider', 'bookshelf', 'load'],
      );
    }
  }

  /// 设置当前书架分类并持久化
  void setBookshelfKind(BookshelfKind kind) {
    state = kind;
    // 保存到SharedPreferences（使用Provider以支持测试）
    final prefsService = ref.read(preferencesServiceProvider);
    prefsService.setString(_newKey, kind.name);
  }
}

/// 书架小说列表
///
/// 根据当前书架分类异步加载小说列表（分类由 URL 前缀派生）
@riverpod
Future<List<Novel>> bookshelfNovels(Ref ref) async {
  // 获取当前书架分类
  final kind = ref.watch(currentBookshelfKindProvider);

  // Web环境特殊处理
  if (kIsWeb) {
    // 在Web环境中，返回模拟测试数据
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

  // 获取 Repository
  final bookshelfRepository = ref.watch(bookshelfRepositoryProvider);

  // 从数据库加载小说列表
  try {
    final novels = await bookshelfRepository.getNovelsByBookshelf(kind);
    LoggerService.instance.d(
      '书架小说列表加载成功: kind=$kind, count=${novels.length}',
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

/// 书架小说列表缓存统计
///
/// 刷新时从数据库查询已缓存章节数和总章节数
@riverpod
Future<Map<String, CacheStats>> bookshelfCacheStats(Ref ref) async {
  final novels = await ref.watch(bookshelfNovelsProvider.future);
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

/// 缓存统计
class CacheStats {
  final int cached;
  final int total;

  const CacheStats({required this.cached, required this.total});

  double get percent => total > 0 ? (cached / total).clamp(0.0, 1.0) : 0.0;
}
