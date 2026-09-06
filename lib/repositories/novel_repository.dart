import 'package:sqflite/sqflite.dart';
import '../models/novel.dart';
import '../services/logger_service.dart';
import '../core/interfaces/repositories/i_novel_repository.dart';
import 'base_repository.dart';

/// 书架写操作能力接口（[NovelRepository] 实现，不导出）。
///
/// 仅 [BookshelfMutationNotifier] 通过 `bookshelfWriterProvider` 持有此类型引用。
/// 设计意图：写方法从 [INovelRepository] 移除后，普通调用方拿不到这些方法，
/// 编译期阻止"直接写库忘 invalidate"。
///
/// 注意：`updateLastReadChapter` 同时存在于 [INovelRepository]（仅历史查询/兜底
/// 路径仍可能直接调用，但书架表写操作须经 Notifier）。书架写路径已收敛至
/// [BookshelfMutationNotifier.updateReadProgress]，本接口保留此方法让
/// [BookshelfMutationNotifier.updateReadProgress] 走与其他写方法相同的
/// `_writer` 收口路径。
abstract interface class IBookshelfWriter {
  Future<int> addToBookshelf(Novel novel);
  Future<int> removeFromBookshelf(String novelUrl);
  Future<int> updateTitle(String novelUrl, String newTitle);
  Future<int> updateCoverMediaIdByUrl(String novelUrl, String? mediaId);
  Future<int> updateLastReadChapter(String novelUrl, int chapterIndex);
  Future<Novel> createNovel({
    required String title,
    required String author,
    String? description,
    String? coverUrl,
    String? backgroundSetting,
  });
}

/// 小说数据仓库
///
/// 负责小说元数据和阅读进度的数据库操作
class NovelRepository extends BaseRepository
    implements INovelRepository, IBookshelfWriter {
  /// 构造函数 - 接受数据库连接实例
  NovelRepository({required super.dbConnection});

  /// 添加小说到书架
  @override
  Future<int> addToBookshelf(Novel novel) async {
    try {
      final db = await database;
      final result = await db.insert(
        'bookshelf',
        {
          'title': novel.title,
          'author': novel.author,
          'url': novel.url,
          'coverUrl': novel.coverUrl,
          'coverMediaId': novel.coverMediaId,
          'description': novel.description,
          'backgroundSetting': novel.backgroundSetting,
          'addedAt': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      LoggerService.instance.i(
        '添加小说到书架: ${novel.title}',
        category: LogCategory.database,
        tags: ['novel', 'add', 'success'],
      );

      return result;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '添加小说到书架失败: ${novel.title} - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['novel', 'add', 'failed'],
      );
      rethrow;
    }
  }

  /// 从书架移除小说
  @override
  Future<int> removeFromBookshelf(String novelUrl) async {
    try {
      final db = await database;
      final result = await db.delete(
        'bookshelf',
        where: 'url = ?',
        whereArgs: [novelUrl],
      );

      LoggerService.instance.i(
        '从书架移除小说: $novelUrl',
        category: LogCategory.database,
        tags: ['novel', 'remove', 'success'],
      );

      return result;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '从书架移除小说失败: $novelUrl - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['novel', 'remove', 'failed'],
      );
      rethrow;
    }
  }

  /// 获取所有小说
  @override
  Future<List<Novel>> getNovels() async {
    if (isWebPlatform) {
      return [];
    }

    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'novels',
      orderBy: 'lastReadTime DESC, addedAt DESC',
    );

    return List.generate(maps.length, (i) {
      return Novel(
        id: maps[i]['id'] as int?,
        title: maps[i]['title'],
        author: maps[i]['author'],
        url: maps[i]['url'],
        coverUrl: maps[i]['coverUrl'],
        coverMediaId: maps[i]['coverMediaId'],
        description: maps[i]['description'],
        backgroundSetting: maps[i]['backgroundSetting'],
        isInBookshelf: true,
        lastReadChapterIndex: maps[i]['lastReadChapter'] as int?,
      );
    });
  }

  /// 检查小说是否在书架中
  @override
  Future<bool> isInBookshelf(String novelUrl) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'bookshelf',
      where: 'url = ?',
      whereArgs: [novelUrl],
    );
    return maps.isNotEmpty;
  }

  /// 更新最后阅读章节
  @override
  Future<int> updateLastReadChapter(String novelUrl, int chapterIndex) async {
    try {
      final db = await database;
      return await db.update(
        'bookshelf',
        {
          'lastReadChapter': chapterIndex,
          'lastReadTime': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'url = ?',
        whereArgs: [novelUrl],
      );
    } catch (e, stackTrace) {
      // 高频操作（每次翻页都触发），失败必须可见
      LoggerService.instance.e(
        '更新最后阅读章节失败: novelUrl=$novelUrl chapterIndex=$chapterIndex - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['novel', 'last_read', 'failed'],
      );
      rethrow;
    }
  }

  /// 更新小说书名
  @override
  Future<int> updateTitle(String novelUrl, String newTitle) async {
    if (isWebPlatform) {
      return 0;
    }

    try {
      final db = await database;
      final result = await db.update(
        'bookshelf',
        {'title': newTitle},
        where: 'url = ?',
        whereArgs: [novelUrl],
      );

      LoggerService.instance.i(
        '更新小说书名: $novelUrl -> $newTitle',
        category: LogCategory.database,
        tags: ['novel', 'update_title', 'success'],
      );

      return result;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '更新小说书名失败: $novelUrl - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['novel', 'update_title', 'failed'],
      );
      rethrow;
    }
  }

  /// 更新小说背景设定
  @override
  Future<int> updateBackgroundSetting(
      String novelUrl, String? backgroundSetting) async {
    if (isWebPlatform) {
      return 0;
    }

    try {
      final db = await database;
      return await db.update(
        'bookshelf',
        {'backgroundSetting': backgroundSetting},
        where: 'url = ?',
        whereArgs: [novelUrl],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '更新背景设定失败: novelUrl=$novelUrl - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['novel', 'background', 'failed'],
      );
      rethrow;
    }
  }

  /// 获取小说背景设定
  @override
  Future<String?> getBackgroundSetting(String novelUrl) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'bookshelf',
      columns: ['backgroundSetting'],
      where: 'url = ?',
      whereArgs: [novelUrl],
    );

    if (maps.isNotEmpty) {
      return maps.first['backgroundSetting'] as String?;
    }
    return null;
  }

  /// 获取上次阅读的章节索引
  @override
  Future<int> getLastReadChapter(String novelUrl) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'bookshelf',
      columns: ['lastReadChapter'],
      where: 'url = ?',
      whereArgs: [novelUrl],
    );

    if (maps.isNotEmpty) {
      return maps.first['lastReadChapter'] as int? ?? 0;
    }
    return 0;
  }

  /// 根据 title 查找小说
  @override
  Future<Novel?> getNovelByTitle(String title) async {
    if (isWebPlatform) {
      return null;
    }

    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'bookshelf',
      where: 'title = ?',
      whereArgs: [title],
      limit: 1,
    );

    if (maps.isEmpty) {
      return null;
    }

    return Novel(
      id: maps[0]['id'] as int?,
      title: maps[0]['title'],
      author: maps[0]['author'],
      url: maps[0]['url'],
      isInBookshelf: true,
      coverUrl: maps[0]['coverUrl'] as String?,
      coverMediaId: maps[0]['coverMediaId'] as String?,
      description: maps[0]['description'] as String?,
      backgroundSetting: maps[0]['backgroundSetting'] as String?,
      lastReadChapterIndex: maps[0]['lastReadChapter'] as int?,
    );
  }

  /// 根据 URL 查找小说（用于 Agent 重写结果跳转阅读器）
  @override
  Future<Novel?> getNovelByUrl(String novelUrl) async {
    if (isWebPlatform) {
      return null;
    }

    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'bookshelf',
      where: 'url = ?',
      whereArgs: [novelUrl],
      limit: 1,
    );

    if (maps.isEmpty) {
      return null;
    }

    return Novel(
      id: maps[0]['id'] as int?,
      title: maps[0]['title'],
      author: maps[0]['author'],
      url: maps[0]['url'],
      isInBookshelf: true,
      coverUrl: maps[0]['coverUrl'] as String?,
      coverMediaId: maps[0]['coverMediaId'] as String?,
      description: maps[0]['description'] as String?,
      backgroundSetting: maps[0]['backgroundSetting'] as String?,
      lastReadChapterIndex: maps[0]['lastReadChapter'] as int?,
    );
  }

  /// 创建新小说（用于同步下载时创建不存在的书）
  @override
  Future<Novel> createNovel({
    required String title,
    required String author,
    String? description,
    String? coverUrl,
    String? backgroundSetting,
  }) async {
    final novel = Novel(
      title: title,
      author: author,
      url: title, // 使用 title 作为 url（同步匹配用）
      coverUrl: coverUrl,
      description: description,
      backgroundSetting: backgroundSetting,
    );
    await addToBookshelf(novel);
    return novel;
  }

  // ========== ID-based 查询方法（Agent 工具用） ==========

  /// 根据 ID 查询小说
  @override
  Future<Novel?> getNovelById(int id) async {
    if (isWebPlatform) return null;
    final db = await database;
    final maps = await db.query(
      'bookshelf',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Novel(
      id: maps.first['id'] as int?,
      title: maps.first['title'] as String,
      author: maps.first['author'] as String,
      url: maps.first['url'] as String,
      isInBookshelf: true,
      coverUrl: maps.first['coverUrl'] as String?,
      description: maps.first['description'] as String?,
      backgroundSetting: maps.first['backgroundSetting'] as String?,
      coverMediaId: maps.first['coverMediaId'] as String?,
      lastReadChapterIndex: maps.first['lastReadChapter'] as int?,
    );
  }

  /// 根据 ID 获取小说 URL（内部 ID→URL 解析用）
  @override
  Future<String?> getNovelUrlById(int id) async {
    final db = await database;
    final maps = await db.query(
      'bookshelf',
      columns: ['url'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return maps.first['url'] as String;
  }

  /// 根据 ID 更新小说背景设定（解析 URL 后委托 updateBackgroundSetting）
  @override
  Future<int> updateBackgroundSettingById(int id, String? setting) async {
    final novelUrl = await getNovelUrlById(id);
    if (novelUrl == null) return 0;
    return updateBackgroundSetting(novelUrl, setting);
  }

  /// 根据 ID 更新小说封面媒体 ID
  @override
  Future<int> updateCoverMediaIdById(int id, String? mediaId) async {
    if (isWebPlatform) {
      return 0;
    }

    try {
      final db = await database;
      return await db.update(
        'bookshelf',
        {'coverMediaId': mediaId},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '更新封面失败: id=$id - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['novel', 'cover', 'failed'],
      );
      rethrow;
    }
  }

  /// 根据 URL 更新小说封面媒体 ID
  ///
  /// 书架页 UI 清封面用（`getNovelsByBookshelf` 返回的 Novel 不含 id，
  /// UI 只能拿到 url）。与 [updateCoverMediaIdById] 等价，定位键不同。
  @override
  Future<int> updateCoverMediaIdByUrl(String novelUrl, String? mediaId) async {
    if (isWebPlatform) {
      return 0;
    }

    try {
      final db = await database;
      return await db.update(
        'bookshelf',
        {'coverMediaId': mediaId},
        where: 'url = ?',
        whereArgs: [novelUrl],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '更新封面失败: url=$novelUrl - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['novel', 'cover', 'failed'],
      );
      rethrow;
    }
  }
}
