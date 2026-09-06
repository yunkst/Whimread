/// Riverpod Providers for BookshelfScreen
///
/// 管理书架屏幕的所有状态和依赖
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riverpod/riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../models/novel.dart';
import '../../core/providers/database_providers.dart';
import '../../core/providers/service_providers.dart';
import '../../services/logger_service.dart';
import '../../services/preferences_service.dart';

part 'bookshelf_providers.g.dart';

/// 当前选中的书架ID
///
/// 默认值为 1（"全部小说"书架）
/// 支持持久化保存用户选择，重启app后恢复上次打开的书架
@riverpod
class CurrentBookshelfId extends _$CurrentBookshelfId {
  static const String _key = 'current_bookshelf_id';

  @override
  int build() {
    // 异步加载已保存的书架ID
    // 使用ref.read访问PreferencesService以支持测试
    final prefsService = ref.watch(preferencesServiceProvider);
    _loadSavedBookshelfId(prefsService);
    // 立即返回默认值，避免阻塞UI渲染
    return 1;
  }

  /// 从SharedPreferences加载保存的书架ID
  Future<void> _loadSavedBookshelfId(PreferencesService prefsService) async {
    try {
      final savedId = await prefsService.getInt(_key, defaultValue: 1);
      LoggerService.instance.d(
        '书架ID加载完成: $savedId',
        category: LogCategory.ui,
        tags: ['provider', 'bookshelf', 'load'],
      );
      // 更新状态为保存的值
      state = savedId;
    } catch (e, st) {
      LoggerService.instance.e(
        '加载书架ID失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ui,
        tags: ['provider', 'bookshelf', 'load'],
      );
    }
  }

  /// 设置当前书架ID并持久化
  void setBookshelfId(int bookshelfId) {
    state = bookshelfId;
    // 保存到SharedPreferences（使用Provider以支持测试）
    final prefsService = ref.read(preferencesServiceProvider);
    prefsService.setInt(_key, bookshelfId);
  }
}

/// 书架小说列表
///
/// 根据当前书架ID异步加载小说列表
@riverpod
Future<List<Novel>> bookshelfNovels(Ref ref) async {
  // 获取当前书架ID
  final bookshelfId = ref.watch(currentBookshelfIdProvider);

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
    final novels = await bookshelfRepository.getNovelsByBookshelf(bookshelfId);
    LoggerService.instance.d(
      '书架小说列表加载成功: bookshelfId=$bookshelfId, count=${novels.length}',
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
