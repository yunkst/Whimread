import '../models/prompt_tag_category.dart';
import '../services/logger_service.dart';
import 'base_repository.dart';
import '../core/interfaces/repositories/i_prompt_tag_category_repository.dart';

class PromptTagCategoryRepository extends BaseRepository
    implements IPromptTagCategoryRepository {
  PromptTagCategoryRepository({required super.dbConnection});

  static const String _table = 'prompt_tag_categories';

  @override
  Future<List<PromptTagCategory>> getAll() async {
    final db = await database;
    LoggerService.instance.d(
      'getAll: 查询全部标签分类',
      category: LogCategory.database,
      tags: ['prompt-tag-category', 'query', 'getAll'],
    );
    final maps = await db.query(_table, orderBy: 'sort_order ASC, id ASC');
    return maps.map(PromptTagCategory.fromMap).toList();
  }

  @override
  Future<int> save(PromptTagCategory category) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      if (category.id == null) {
        final newId = await db.insert(_table, {
          'name': category.name,
          'sort_order': category.sortOrder,
          'created_at': now,
          'updated_at': now,
        });
        LoggerService.instance.i(
          'save: 新增标签分类 (ID: $newId, name: ${category.name})',
          category: LogCategory.database,
          tags: ['prompt-tag-category', 'insert'],
        );
        return newId;
      }
      await db.update(
        _table,
        {
          'name': category.name,
          'sort_order': category.sortOrder,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [category.id],
      );
      LoggerService.instance.i(
        'save: 更新标签分类 (ID: ${category.id}, name: ${category.name})',
        category: LogCategory.database,
        tags: ['prompt-tag-category', 'update'],
      );
      return category.id!;
    } catch (e, stack) {
      LoggerService.instance.e(
        'save: 保存标签分类失败 (ID: ${category.id}, name: ${category.name}): $e',
        stackTrace: stack.toString(),
        category: LogCategory.database,
        tags: ['prompt-tag-category', 'save', 'error'],
      );
      rethrow;
    }
  }

  @override
  Future<void> delete(int id) async {
    final db = await database;
    try {
      await db.delete(_table, where: 'id = ?', whereArgs: [id]);
      LoggerService.instance.i(
        'delete: 删除标签分类 (ID: $id)',
        category: LogCategory.database,
        tags: ['prompt-tag-category', 'delete'],
      );
    } catch (e, stack) {
      LoggerService.instance.e(
        'delete: 删除标签分类失败 (ID: $id): $e',
        stackTrace: stack.toString(),
        category: LogCategory.database,
        tags: ['prompt-tag-category', 'delete', 'error'],
      );
      rethrow;
    }
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
      'reorder: 重排标签分类顺序 (count: ${orderedIds.length})',
      category: LogCategory.database,
      tags: ['prompt-tag-category', 'update', 'reorder'],
    );
  }

  @override
  Future<int> count() async {
    final db = await database;
    LoggerService.instance.d(
      'count: 查询标签分类总数',
      category: LogCategory.database,
      tags: ['prompt-tag-category', 'query', 'count'],
    );
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM $_table');
    return (result.first['cnt'] as int?) ?? 0;
  }

  @override
  Future<void> initDefaultCategories() async {
    if (await count() > 0) {
      LoggerService.instance.d(
        'initDefaultCategories: 已有分类数据，跳过初始化',
        category: LogCategory.database,
        tags: ['prompt-tag-category', 'init', 'skip'],
      );
      return;
    }
    final now = DateTime.now();
    final defaults = ['风格', '场景', '人物', '情节'];
    for (var i = 0; i < defaults.length; i++) {
      await save(PromptTagCategory(
        name: defaults[i],
        sortOrder: i,
        createdAt: now,
        updatedAt: now,
      ));
    }
    LoggerService.instance.i(
      'initDefaultCategories: 初始化默认标签分类完成 (${defaults.join(", ")})',
      category: LogCategory.database,
      tags: ['prompt-tag-category', 'insert', 'init-defaults'],
    );
  }
}
