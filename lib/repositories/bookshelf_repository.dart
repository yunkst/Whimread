import 'package:sqflite/sqflite.dart';
import '../models/bookshelf.dart';
import '../models/novel.dart';
import '../services/logger_service.dart';
import 'base_repository.dart';
import '../core/interfaces/repositories/i_bookshelf_repository.dart';

/// 书架关联表写操作能力接口（[BookshelfRepository] 实现，不导出）。
///
/// 仅 [BookshelfMutationNotifier] 通过
/// `bookshelfAssociationWriterProvider` 持有此类型引用。
/// 设计意图：关联表写方法从 [IBookshelfRepository] 移除后，
/// 普通调用方拿不到这些方法，编译期阻止"直接写关联表忘 invalidate"。
abstract interface class IBookshelfAssociationWriter {
  Future<void> addNovelToBookshelf(String novelUrl, int bookshelfId);
  Future<bool> removeNovelFromBookshelf(String novelUrl, int bookshelfId);
  Future<void> moveNovelToBookshelf(
      String novelUrl, int fromBookshelfId, int toBookshelfId);
}

/// 书架数据仓库
///
/// 负责书架分类的数据库操作，包括：
/// - 书架CRUD操作（创建、读取、更新、删除）
/// - 书架与小说的多对多关系管理
/// - 书架排序和分组
/// - 书架统计信息
///
/// ## 重要命名说明
///
/// - **Bookshelf 模型**: 书架分类功能（id, name, icon, color）
/// - **bookshelf 表**: 物理表，存储小说元数据（历史遗留命名）
/// - **bookshelves 表**: 书架分类表（复数形式，与Bookshelf模型对应）
/// - **novel_bookshelves 表**: 小说与书架的多对多关系表
///
/// ## 系统书架
///
/// - ID=1: "全部小说" - 虚拟书架，显示所有小说，不可编辑
/// - ID=2: "我的收藏" - 默认收藏书架，不可删除
class BookshelfRepository extends BaseRepository
    implements IBookshelfRepository, IBookshelfAssociationWriter {
  /// 构造函数 - 接受数据库连接实例
  BookshelfRepository({required super.dbConnection});

  // ==================== 书架CRUD操作 ====================

  /// 获取所有书架列表
  ///
  /// 返回所有书架，包括系统书架和用户创建的书架
  /// 按排序字段（sort_order）升序排列
  ///
  /// Web平台返回默认系统书架（全部小说、我的收藏）
  @override
  Future<List<Bookshelf>> getBookshelves() async {
    if (isWebPlatform) {
      // Web平台返回默认系统书架
      return [
        Bookshelf(
          id: 1,
          name: '全部小说',
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          sortOrder: 0,
          isSystem: true,
        ),
        Bookshelf(
          id: 2,
          name: '我的收藏',
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          sortOrder: 1,
          isSystem: true,
        ),
      ];
    }

    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'bookshelves',
      orderBy: 'sort_order ASC',
    );

    return maps.map((map) => Bookshelf.fromJson(map)).toList();
  }

  /// 创建新书架
  ///
  /// [name] 书架名称
  ///
  /// 返回新创建的书架ID
  ///
  /// 自动计算并设置排序顺序（最大sort_order + 1）
  ///
  /// Web平台抛出UnsupportedError异常
  @override
  Future<int> createBookshelf(String name) async {
    if (isWebPlatform) {
      throw UnsupportedError('Web平台不支持创建书架');
    }

    final db = await database;

    // 获取当前最大sort_order
    final List<Map<String, dynamic>> result = await db.rawQuery(
      'SELECT MAX(sort_order) as max_order FROM bookshelves',
    );
    final int maxOrder = result.first['max_order'] as int? ?? 0;

    final int id = await db.insert(
      'bookshelves',
      {
        'name': name,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'sort_order': maxOrder + 1,
        'is_system': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    LoggerService.instance.i(
      '创建书架: $name (ID: $id)',
      category: LogCategory.database,
      tags: ['bookshelf', 'create'],
    );

    return id;
  }

  /// 删除书架
  ///
  /// [bookshelfId] 书架ID
  ///
  /// 返回是否删除成功
  ///
  /// 限制：
  /// - 系统书架（is_system=1）不能删除
  /// - 书架不存在返回false
  /// - 删除书架会级联删除novel_bookshelves表中的关联记录
  ///
  /// Web平台抛出UnsupportedError异常
  @override
  Future<bool> deleteBookshelf(int bookshelfId) async {
    if (isWebPlatform) {
      throw UnsupportedError('Web平台不支持删除书架');
    }

    final db = await database;

    // 检查书架是否存在
    final List<Map<String, dynamic>> bookshelves = await db.query(
      'bookshelves',
      where: 'id = ?',
      whereArgs: [bookshelfId],
    );

    if (bookshelves.isEmpty) {
      LoggerService.instance.w(
        '删除书架失败: 书架不存在 (ID: $bookshelfId)',
        category: LogCategory.database,
        tags: ['bookshelf', 'delete'],
      );
      return false;
    }

    // 检查是否为系统书架
    if (bookshelves.first['is_system'] == 1) {
      LoggerService.instance.w(
        '删除书架失败: 不能删除系统书架 (ID: $bookshelfId)',
        category: LogCategory.database,
        tags: ['bookshelf', 'delete'],
      );
      return false;
    }

    // 删除书架（novel_bookshelves表会通过CASCADE自动删除关联记录）
    final int count = await db.delete(
      'bookshelves',
      where: 'id = ?',
      whereArgs: [bookshelfId],
    );

    final bool success = count > 0;

    if (success) {
      LoggerService.instance.i(
        '删除书架成功 (ID: $bookshelfId)',
        category: LogCategory.database,
        tags: ['bookshelf', 'delete'],
      );
    }

    return success;
  }

  // ==================== 书架与小说关系管理 ====================

  /// 获取指定书架中的小说列表
  ///
  /// [bookshelfId] 书架ID
  ///
  /// 返回小说列表，按最后阅读时间和添加时间降序排列
  ///
  /// 特殊处理：
  /// - bookshelfId=1（全部小说）：返回bookshelf表中的所有小说
  /// - 其他书架：通过novel_bookshelves关联表查询
  ///
  /// Web平台返回空列表
  @override
  Future<List<Novel>> getNovelsByBookshelf(int bookshelfId) async {
    if (isWebPlatform) {
      return [];
    }

    final db = await database;

    // 如果是"全部小说"书架，返回所有小说
    if (bookshelfId == 1) {
      final List<Map<String, dynamic>> maps = await db.query(
        'bookshelf',
        orderBy: 'lastReadTime DESC, addedAt DESC',
      );

      return List.generate(maps.length, (i) {
        return Novel(
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

    // 其他书架，通过关联表查询
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT b.*
      FROM bookshelf b
      INNER JOIN novel_bookshelves nb ON b.url = nb.novel_url
      WHERE nb.bookshelf_id = ?
      ORDER BY b.lastReadTime DESC, b.addedAt DESC
    ''', [bookshelfId]);

    return List.generate(maps.length, (i) {
      return Novel(
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

  /// 添加小说到指定书架
  ///
  /// [novelUrl] 小说URL
  /// [bookshelfId] 书架ID
  ///
  /// 特殊处理：
  /// - bookshelfId=1（全部小说）：虚拟书架，不需要添加关联
  /// - 其他书架：在novel_bookshelves表中创建关联记录
  ///
  /// Web平台抛出UnsupportedError异常
  @override
  Future<void> addNovelToBookshelf(String novelUrl, int bookshelfId) async {
    if (isWebPlatform) {
      throw UnsupportedError('Web平台不支持书架操作');
    }

    if (bookshelfId == 1) {
      // "全部小说"是虚拟书架，不需要添加关联
      return;
    }

    final db = await database;

    await db.insert(
      'novel_bookshelves',
      {
        'novel_url': novelUrl,
        'bookshelf_id': bookshelfId,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    LoggerService.instance.i(
      '添加小说到书架: $novelUrl -> 书架ID: $bookshelfId',
      category: LogCategory.database,
      tags: ['bookshelf', 'add_novel'],
    );
  }

  /// 从指定书架移除小说
  ///
  /// [novelUrl] 小说URL
  /// [bookshelfId] 书架ID
  ///
  /// 返回是否移除成功
  ///
  /// 特殊处理：
  /// - bookshelfId=1（全部小说）：虚拟书架，不能移除
  /// - 其他书架：从novel_bookshelves表中删除关联记录
  ///
  /// Web平台抛出UnsupportedError异常
  @override
  Future<bool> removeNovelFromBookshelf(
      String novelUrl, int bookshelfId) async {
    if (isWebPlatform) {
      throw UnsupportedError('Web平台不支持书架操作');
    }

    if (bookshelfId == 1) {
      LoggerService.instance.w(
        '不能从"全部小说"书架移除小说',
        category: LogCategory.database,
        tags: ['bookshelf', 'remove_novel'],
      );
      return false;
    }

    final db = await database;

    final int count = await db.delete(
      'novel_bookshelves',
      where: 'novel_url = ? AND bookshelf_id = ?',
      whereArgs: [novelUrl, bookshelfId],
    );

    final bool success = count > 0;

    if (success) {
      LoggerService.instance.i(
        '从书架移除小说: $novelUrl <- 书架ID: $bookshelfId',
        category: LogCategory.database,
        tags: ['bookshelf', 'remove_novel'],
      );
    }

    return success;
  }

  /// 将小说从一个书架移动到另一个书架
  ///
  /// [novelUrl] 小说URL
  /// [fromBookshelfId] 原书架ID
  /// [toBookshelfId] 目标书架ID
  ///
  /// 限制：
  /// - 不能移动到"全部小说"书架（ID=1，虚拟书架无关联可加）
  /// - 源书架和目标书架相同时无操作
  /// - from=1（全部小说）降级为 add-only：只调 addNovelToBookshelf(to)，
  ///   跳过 removeNovelFromBookshelf(_, 1)（该调用本就是 no-op，跳过以避免无意义 warning）
  ///
  /// Web平台抛出UnsupportedError异常
  @override
  Future<void> moveNovelToBookshelf(
    String novelUrl,
    int fromBookshelfId,
    int toBookshelfId,
  ) async {
    if (isWebPlatform) {
      throw UnsupportedError('Web平台不支持书架操作');
    }

    // to=1 是虚拟书架"全部小说"，无关联可加；UI 选择对话框已过滤 id=1，
    // 保留此断言作为防御性兜底，防止未来其他调用方误用。
    if (toBookshelfId == 1) {
      throw ArgumentError('不能移动到"全部小说"虚拟书架');
    }

    if (fromBookshelfId == toBookshelfId) {
      LoggerService.instance.w(
        '原书架和目标书架相同，无需移动',
        category: LogCategory.database,
        tags: ['bookshelf', 'move_novel'],
      );
      return;
    }

    // 先添加到目标书架
    await addNovelToBookshelf(novelUrl, toBookshelfId);

    // from=1 是虚拟书架"全部小说"，无关联可删（removeNovelFromBookshelf(_, 1) 本就 no-op），
    // 跳过以避免无意义的 warning 日志。等价于"加入目标书架，书仍留在全部小说"。
    if (fromBookshelfId != 1) {
      final removed = await removeNovelFromBookshelf(novelUrl, fromBookshelfId);

      if (removed) {
        LoggerService.instance.i(
          '移动小说: $novelUrl 从书架 $fromBookshelfId 到书架 $toBookshelfId',
          category: LogCategory.database,
          tags: ['bookshelf', 'move_novel'],
        );
      } else {
        LoggerService.instance.i(
          '加入小说: $novelUrl 到书架 $toBookshelfId (来源:书架 $fromBookshelfId 无关联可删)',
          category: LogCategory.database,
          tags: ['bookshelf', 'move_novel'],
        );
      }
    } else {
      LoggerService.instance.i(
        '加入小说: $novelUrl 到书架 $toBookshelfId (来源:虚拟书架 全部小说)',
        category: LogCategory.database,
        tags: ['bookshelf', 'move_novel'],
      );
    }
  }

  // ==================== 书架统计和查询 ====================

  /// 获取小说所属的所有书架
  ///
  /// [novelUrl] 小说URL
  ///
  /// 返回书架ID列表
  ///
  /// 特殊处理：
  /// - 始终包含"全部小说"书架（ID=1）
  /// - 返回去重后的列表
  ///
  /// Web平台返回[1]（全部小说）
  @override
  Future<List<int>> getBookshelvesByNovel(String novelUrl) async {
    if (isWebPlatform) {
      return [1]; // Web平台默认返回"全部小说"
    }

    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      'novel_bookshelves',
      columns: ['bookshelf_id'],
      where: 'novel_url = ?',
      whereArgs: [novelUrl],
    );

    // 始终包含"全部小说"书架，并去重
    final result = [1, ...maps.map((m) => m['bookshelf_id'] as int)];
    return result.toSet().toList();
  }

  /// 获取书架中的小说数量
  ///
  /// [bookshelfId] 书架ID
  ///
  /// 返回小说数量
  ///
  /// 特殊处理：
  /// - bookshelfId=1（全部小说）：返回bookshelf表中的所有小说数量
  /// - 其他书架：返回novel_bookshelves表中的关联记录数量
  @override
  Future<int> getNovelCountByBookshelf(int bookshelfId) async {
    if (isWebPlatform) {
      return 0;
    }

    final db = await database;

    if (bookshelfId == 1) {
      // 查询bookshelf表中的小说数量
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM bookshelf',
      );
      return Sqflite.firstIntValue(result) ?? 0;
    }

    // 查询novel_bookshelves表中的关联数量
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM novel_bookshelves WHERE bookshelf_id = ?',
      [bookshelfId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 检查小说是否在指定书架中
  ///
  /// [novelUrl] 小说URL
  /// [bookshelfId] 书架ID
  ///
  /// 返回是否在书架中
  ///
  /// 特殊处理：
  /// - bookshelfId=1（全部小说）：检查小说是否在bookshelf表中
  /// - 其他书架：检查novel_bookshelves表中是否存在关联记录
  @override
  Future<bool> isNovelInBookshelf(String novelUrl, int bookshelfId) async {
    if (isWebPlatform) {
      return false;
    }

    final db = await database;

    if (bookshelfId == 1) {
      // 检查bookshelf表
      final List<Map<String, dynamic>> maps = await db.query(
        'bookshelf',
        where: 'url = ?',
        whereArgs: [novelUrl],
        limit: 1,
      );
      return maps.isNotEmpty;
    }

    // 检查novel_bookshelves表
    final List<Map<String, dynamic>> maps = await db.query(
      'novel_bookshelves',
      where: 'novel_url = ? AND bookshelf_id = ?',
      whereArgs: [novelUrl, bookshelfId],
      limit: 1,
    );
    return maps.isNotEmpty;
  }

  // ==================== 书架排序和分组 ====================

  /// 更新书架排序顺序
  ///
  /// [bookshelfIds] 书架ID列表，按新的显示顺序排列
  ///
  /// 系统书架（ID=1,2）不会改变其位置
  ///
  /// Web平台抛出UnsupportedError异常
  @override
  Future<void> reorderBookshelves(List<int> bookshelfIds) async {
    if (isWebPlatform) {
      throw UnsupportedError('Web平台不支持书架操作');
    }

    final db = await database;

    // 使用事务确保原子性
    await db.transaction((txn) async {
      for (int i = 0; i < bookshelfIds.length; i++) {
        final bookshelfId = bookshelfIds[i];

        // 跳过系统书架
        if (bookshelfId == 1 || bookshelfId == 2) {
          continue;
        }

        await txn.update(
          'bookshelves',
          {'sort_order': i + 1},
          where: 'id = ?',
          whereArgs: [bookshelfId],
        );
      }
    });

    LoggerService.instance.i(
      '更新书架排序: $bookshelfIds',
      category: LogCategory.database,
      tags: ['bookshelf', 'reorder'],
    );
  }

  /// 更新书架信息
  ///
  /// [bookshelf] 书架对象
  ///
  /// 返回更新的行数
  ///
  /// 限制：
  /// - 系统书架（isSystem=true）只能更新sort_order
  /// - 用户书架可以更新name、icon、color、sort_order
  ///
  /// Web平台抛出UnsupportedError异常
  @override
  Future<int> updateBookshelf(Bookshelf bookshelf) async {
    if (isWebPlatform) {
      throw UnsupportedError('Web平台不支持书架操作');
    }

    final db = await database;

    // 检查书架是否存在
    final List<Map<String, dynamic>> existing = await db.query(
      'bookshelves',
      where: 'id = ?',
      whereArgs: [bookshelf.id],
    );

    if (existing.isEmpty) {
      LoggerService.instance.w(
        '更新书架失败: 书架不存在 (ID: ${bookshelf.id})',
        category: LogCategory.database,
        tags: ['bookshelf', 'update'],
      );
      return 0;
    }

    // 准备更新数据
    final Map<String, dynamic> data = {};

    if (!bookshelf.isSystem) {
      // 用户书架可以更新这些字段
      data['name'] = bookshelf.name;
      data['icon'] = bookshelf.icon;
      data['color'] = bookshelf.color;
    }

    data['sort_order'] = bookshelf.sortOrder;

    final int count = await db.update(
      'bookshelves',
      data,
      where: 'id = ?',
      whereArgs: [bookshelf.id],
    );

    if (count > 0) {
      LoggerService.instance.i(
        '更新书架成功 (ID: ${bookshelf.id})',
        category: LogCategory.database,
        tags: ['bookshelf', 'update'],
      );
    }

    return count;
  }
}
