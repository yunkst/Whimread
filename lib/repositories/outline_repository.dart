import 'package:sqflite/sqflite.dart';
import '../models/outline.dart';
import '../services/logger_service.dart';
import 'base_repository.dart';
import '../core/interfaces/repositories/i_outline_repository.dart';

/// 大纲数据仓库
///
/// 负责管理小说大纲的数据库操作，包括大纲的创建、更新、查询和删除。
/// 每本小说对应一个大纲记录，通过 novelUrl 进行关联。
///
/// 注意：此Repository现在使用统一的数据库版本v21，不再有独立的数据库版本管理。
class OutlineRepository extends BaseRepository implements IOutlineRepository {
  /// 构造函数 - 接受数据库连接实例
  OutlineRepository({required super.dbConnection});

  /// 创建或更新大纲
  ///
  /// 如果小说URL已存在大纲则更新，否则创建新的。
  ///
  /// 参数：
  /// - [outline] 要保存的大纲对象
  ///
  /// 返回：
  /// - 受影响的行数（更新）或新插入记录的ID（创建）
  ///
  /// 示例：
  /// ```dart
  /// final outline = Outline(
  ///   novelUrl: 'https://example.com/novel/123',
  ///   title: '小说大纲',
  ///   content: '第一章：开始...',
  ///   createdAt: DateTime.now(),
  ///   updatedAt: DateTime.now(),
  /// );
  /// final result = await repository.saveOutline(outline);
  /// ```
  @override
  Future<int> saveOutline(Outline outline) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // 检查是否已存在该小说的大纲
    final existing = await getOutlineByNovelUrl(outline.novelUrl);

    if (existing != null) {
      // 更新现有大纲
      final result = await db.update(
        'outlines',
        {
          'title': outline.title,
          'content': outline.content,
          'updated_at': now,
        },
        where: 'novel_url = ?',
        whereArgs: [outline.novelUrl],
      );
      LoggerService.instance.i(
        '大纲已更新: ${outline.novelUrl}',
        category: LogCategory.database,
        tags: ['outline', 'save', 'update'],
      );
      return result;
    } else {
      // 创建新大纲
      final result = await db.insert(
        'outlines',
        {
          'novel_url': outline.novelUrl,
          'title': outline.title,
          'content': outline.content,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      LoggerService.instance.i(
        '大纲已创建: ${outline.novelUrl}',
        category: LogCategory.database,
        tags: ['outline', 'save', 'create'],
      );
      return result;
    }
  }

  /// 根据小说URL获取大纲
  /// ... (文档注释不变)
  @override
  Future<Outline?> getOutlineByNovelUrl(String novelUrl) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'outlines',
      where: 'novel_url = ?',
      whereArgs: [novelUrl],
    );

    if (maps.isNotEmpty) {
      return Outline.fromMap(maps.first);
    }
    return null;
  }

  /// 获取所有大纲
  /// ... (文档注释不变)
  @override
  Future<List<Outline>> getAllOutlines() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'outlines',
      orderBy: 'updated_at DESC',
    );

    return List.generate(maps.length, (i) {
      return Outline.fromMap(maps[i]);
    });
  }

  /// 删除大纲
  /// ... (文档注释不变)
  @override
  Future<int> deleteOutline(String novelUrl) async {
    final db = await database;
    final result = await db.delete(
      'outlines',
      where: 'novel_url = ?',
      whereArgs: [novelUrl],
    );
    LoggerService.instance.i(
      '大纲已删除: $novelUrl',
      category: LogCategory.database,
      tags: ['outline', 'delete'],
    );
    return result;
  }

  /// 更新大纲内容
  /// ... (文档注释不变)
  @override
  Future<int> updateOutlineContent(
    String novelUrl,
    String title,
    String content,
  ) async {
    final db = await database;
    final result = await db.update(
      'outlines',
      {
        'title': title,
        'content': content,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'novel_url = ?',
      whereArgs: [novelUrl],
    );
    LoggerService.instance.i(
      '大纲内容已更新: $novelUrl',
      category: LogCategory.database,
      tags: ['outline', 'update', 'content'],
    );
    return result;
  }
}
