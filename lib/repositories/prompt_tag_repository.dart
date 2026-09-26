import 'dart:math';
import '../models/prompt_tag.dart';
import '../models/tag_group.dart';
import '../services/logger_service.dart';
import 'base_repository.dart';
import '../core/interfaces/repositories/i_prompt_tag_repository.dart';

class PromptTagRepository extends BaseRepository
    implements IPromptTagRepository {
  PromptTagRepository({required super.dbConnection});

  static const String _table = 'prompt_tags';

  /// 复用单个 Random 实例，避免每次 getRandom* 调用都新建实例。
  /// 静态 + 懒初始化在首次访问时完成；多 isolate 环境各自独立，
  /// 但 prompt tag 随机选取不要求跨 isolate 共享同一序列。
  static final Random _random = Random();

  @override
  Future<List<PromptTag>> getByCategory(int categoryId) async {
    final db = await database;
    LoggerService.instance.d(
      'getByCategory: 查询分类下的标签 (categoryId: $categoryId)',
      category: LogCategory.database,
      tags: ['prompt-tag', 'query', 'getByCategory'],
    );
    final maps = await db.query(
      _table,
      where: 'category_id = ?',
      whereArgs: [categoryId],
      orderBy: 'sort_order ASC, id ASC',
    );
    return maps.map(PromptTag.fromMap).toList();
  }

  @override
  Future<List<PromptTag>> search(String keyword, {int? categoryId}) async {
    final db = await database;
    final kw = keyword.trim();
    LoggerService.instance.d(
      'search: 搜索标签 (keyword: $kw, categoryId: $categoryId)',
      category: LogCategory.database,
      tags: ['prompt-tag', 'query', 'search'],
    );
    final where = <String>[];
    final args = <Object?>[];
    if (categoryId != null) {
      where.add('category_id = ?');
      args.add(categoryId);
    }
    if (kw.isNotEmpty) {
      where.add('(name LIKE ? OR prompt_text LIKE ? OR reason LIKE ?)');
      args.add('%$kw%');
      args.add('%$kw%');
      args.add('%$kw%');
    }
    final maps = await db.query(
      _table,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'sort_order ASC, id ASC',
    );
    return maps.map(PromptTag.fromMap).toList();
  }

  @override
  Future<int> save(PromptTag tag) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return guard(
      'prompt_tag.save',
      () async {
        if (tag.id == null) {
          final newId = await db.insert(_table, {
            'category_id': tag.categoryId,
            'name': tag.name,
            'reason': tag.reason,
            'prompt_text': tag.promptText,
            'sort_order': tag.sortOrder,
            'created_at': now,
            'updated_at': now,
          });
          LoggerService.instance.i(
            'save: 新增标签 (ID: $newId, name: ${tag.name})',
            category: LogCategory.database,
            tags: ['prompt-tag', 'insert'],
          );
          return newId;
        }
        await db.update(
          _table,
          {
            'category_id': tag.categoryId,
            'name': tag.name,
            'reason': tag.reason,
            'prompt_text': tag.promptText,
            'sort_order': tag.sortOrder,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [tag.id],
        );
        LoggerService.instance.i(
          'save: 更新标签 (ID: ${tag.id}, name: ${tag.name})',
          category: LogCategory.database,
          tags: ['prompt-tag', 'update'],
        );
        return tag.id!;
      },
      message: (e) => 'save: 保存标签失败 (ID: ${tag.id}, name: ${tag.name}): $e',
      category: LogCategory.database,
      tags: ['prompt-tag', 'save', 'error'],
    );
  }

  @override
  Future<void> delete(int id) async {
    final db = await database;
    return guard(
      'prompt_tag.delete',
      () async {
        await db.delete(_table, where: 'id = ?', whereArgs: [id]);
        LoggerService.instance.i(
          'delete: 删除标签 (ID: $id)',
          category: LogCategory.database,
          tags: ['prompt-tag', 'delete'],
        );
      },
      message: (e) => 'delete: 删除标签失败 (ID: $id): $e',
      category: LogCategory.database,
      tags: ['prompt-tag', 'delete', 'error'],
    );
  }

  @override
  Future<void> deleteByCategory(int categoryId) async {
    final db = await database;
    return guard(
      'prompt_tag.deleteByCategory',
      () async {
        await db.delete(_table, where: 'category_id = ?', whereArgs: [categoryId]);
        LoggerService.instance.i(
          'deleteByCategory: 删除分类下所有标签 (categoryId: $categoryId)',
          category: LogCategory.database,
          tags: ['prompt-tag', 'delete', 'by-category'],
        );
      },
      message: (e) =>
          'deleteByCategory: 删除分类标签失败 (categoryId: $categoryId): $e',
      category: LogCategory.database,
      tags: ['prompt-tag', 'delete', 'by-category', 'error'],
    );
  }

  @override
  Future<void> reorder(List<int> orderedIds) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update(
        _table,
        {'sort_order': i, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [orderedIds[i]],
      );
    }
    await batch.commit(noResult: true);
    LoggerService.instance.i(
      'reorder: 重排标签顺序 (count: ${orderedIds.length})',
      category: LogCategory.database,
      tags: ['prompt-tag', 'update', 'reorder'],
    );
  }

  @override
  Future<List<PromptTag>> getByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final db = await database;
    LoggerService.instance.d(
      'getByIds: 按ID列表查询标签 (count: ${ids.length})',
      category: LogCategory.database,
      tags: ['prompt-tag', 'query', 'getByIds'],
    );
    final placeholders = List.filled(ids.length, '?').join(',');
    final maps = await db.query(
      _table,
      where: 'id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'sort_order ASC, id ASC',
    );
    return maps.map(PromptTag.fromMap).toList();
  }

  @override
  Future<List<TagGroup>> getGroupedByCategory(int categoryId) async {
    final db = await database;
    LoggerService.instance.d(
      'getGroupedByCategory: 按分组查询标签 (categoryId: $categoryId)',
      category: LogCategory.database,
      tags: ['prompt-tag', 'query', 'grouped'],
    );
    final maps = await db.rawQuery(
      '''
      SELECT MIN(id) AS representative_id,
             category_id,
             name,
             COUNT(*) AS count
      FROM $_table
      WHERE category_id = ?
      GROUP BY category_id, name
      ORDER BY MIN(sort_order) ASC, MIN(id) ASC
    ''',
      [categoryId],
    );
    return maps
        .map((m) => TagGroup(
              name: m['name'] as String,
              count: (m['count'] as int?) ?? 0,
              representativeId: m['representative_id'] as int,
              categoryId: m['category_id'] as int,
            ))
        .toList();
  }

  @override
  Future<String?> getRandomPromptText(int categoryId, String name) async {
    final db = await database;
    LoggerService.instance.d(
      'getRandomPromptText: 随机获取提示词文本 (categoryId: $categoryId, name: $name)',
      category: LogCategory.database,
      tags: ['prompt-tag', 'query', 'random'],
    );
    final maps = await db.query(
      _table,
      columns: ['prompt_text'],
      where: 'category_id = ? AND name = ?',
      whereArgs: [categoryId, name],
    );
    if (maps.isEmpty) return null;
    final picked = maps[_random.nextInt(maps.length)];
    return picked['prompt_text'] as String?;
  }

  @override
  Future<PromptTag?> getRandomTag(int categoryId, String name) async {
    final db = await database;
    LoggerService.instance.d(
      'getRandomTag: 随机获取完整标签 (categoryId: $categoryId, name: $name)',
      category: LogCategory.database,
      tags: ['prompt-tag', 'query', 'random-tag'],
    );
    final maps = await db.query(
      _table,
      where: 'category_id = ? AND name = ?',
      whereArgs: [categoryId, name],
    );
    if (maps.isEmpty) return null;
    final picked = maps[_random.nextInt(maps.length)];
    return PromptTag.fromMap(picked);
  }

  @override
  Future<List<PromptTag>> getAll() async {
    final db = await database;
    LoggerService.instance.d(
      'getAll: 获取所有标签',
      category: LogCategory.database,
      tags: ['prompt-tag', 'query', 'get-all'],
    );
    final maps = await db.query(
      _table,
      orderBy: 'sort_order ASC, id ASC',
    );
    return maps.map(PromptTag.fromMap).toList();
  }

  @override
  Future<void> moveToCategory(int tagId, int newCategoryId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return guard(
      'prompt_tag.moveToCategory',
      () async {
        // 获取目标分类的下一个排序序号
        final maxOrderResult = await db.rawQuery(
          'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order FROM $_table WHERE category_id = ?',
          [newCategoryId],
        );
        final nextOrder = (maxOrderResult.first['next_order'] as int?) ?? 0;
        await db.update(
          _table,
          {
            'category_id': newCategoryId,
            'sort_order': nextOrder,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [tagId],
        );
        LoggerService.instance.i(
          'moveToCategory: 移动标签 (tagId: $tagId → categoryId: $newCategoryId, sortOrder: $nextOrder)',
          category: LogCategory.database,
          tags: ['prompt-tag', 'update', 'move-category'],
        );
      },
      message: (e) =>
          'moveToCategory: 移动标签失败 (tagId: $tagId → categoryId: $newCategoryId): $e',
      category: LogCategory.database,
      tags: ['prompt-tag', 'update', 'move-category', 'error'],
    );
  }

  @override
  Future<int> getNextSortOrder(int categoryId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order FROM $_table WHERE category_id = ?',
      [categoryId],
    );
    return (result.first['next_order'] as int?) ?? 0;
  }
}
