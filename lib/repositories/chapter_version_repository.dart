import 'package:sqflite/sqflite.dart';
import '../models/chapter_version.dart';
import '../services/logger_service.dart';
import '../core/interfaces/repositories/i_chapter_version_repository.dart';
import 'base_repository.dart';

/// 章节版本仓库实现
///
/// 负责章节历史版本的增删查操作和版本淘汰逻辑
class ChapterVersionRepository extends BaseRepository
    implements IChapterVersionRepository {
  static const String _table = 'chapter_versions';

  ChapterVersionRepository({required super.dbConnection});

  @override
  Future<int> saveVersion(ChapterVersion version) async {
    try {
      final db = await database;
      final id = await db.insert(_table, version.toMap());
      LoggerService.instance.i(
        '保存版本: chapterUrl=${version.chapterUrl} source=${version.source} id=$id',
        category: LogCategory.database,
        tags: ['chapter_version', 'save'],
      );
      return id;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '保存版本失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['chapter_version', 'save', 'failed'],
      );
      rethrow;
    }
  }

  @override
  Future<List<ChapterVersion>> getVersions(String chapterUrl) async {
    final db = await database;
    final maps = await db.query(
      _table,
      where: 'chapterUrl = ?',
      whereArgs: [chapterUrl],
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => ChapterVersion.fromMap(m)).toList();
  }

  @override
  Future<int> getVersionCount(String chapterUrl) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM $_table WHERE chapterUrl = ?',
      [chapterUrl],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<ChapterVersion?> getVersionById(int id) async {
    final db = await database;
    final maps = await db.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ChapterVersion.fromMap(maps.first);
  }

  @override
  Future<int> deleteVersion(int id) async {
    final db = await database;
    final affected = await db.delete(
      _table,
      where: 'id = ?',
      whereArgs: [id],
    );
    LoggerService.instance.d(
      '删除版本: id=$id affected=$affected',
      category: LogCategory.database,
      tags: ['chapter_version', 'delete'],
    );
    return affected;
  }

  @override
  Future<int> deleteVersionsByChapter(String chapterUrl) async {
    final db = await database;
    final affected = await db.delete(
      _table,
      where: 'chapterUrl = ?',
      whereArgs: [chapterUrl],
    );
    LoggerService.instance.d(
      '删除章节所有版本: chapterUrl=$chapterUrl count=$affected',
      category: LogCategory.database,
      tags: ['chapter_version', 'delete_by_chapter'],
    );
    return affected;
  }

  @override
  Future<int> deleteVersionsByNovel(String novelUrl) async {
    final db = await database;
    // 通过 chapter_cache JOIN 获取该小说所有章节 URL，然后删除对应版本
    final affected = await db.rawDelete('''
      DELETE FROM $_table
      WHERE chapterUrl IN (
        SELECT chapterUrl FROM chapter_cache WHERE novelUrl = ?
      )
    ''', [novelUrl]);
    LoggerService.instance.d(
      '删除小说所有版本: novelUrl=$novelUrl count=$affected',
      category: LogCategory.database,
      tags: ['chapter_version', 'delete_by_novel'],
    );
    return affected;
  }

  @override
  Future<int> evictOldestVersions(String chapterUrl, {int maxCount = 5}) async {
    final db = await database;
    // 查询超出限制的版本 ID（按时间升序，最老的在前）
    final overflow = await db.rawQuery('''
      SELECT id FROM $_table
      WHERE chapterUrl = ?
      ORDER BY createdAt ASC
      LIMIT -1 OFFSET ?
    ''', [chapterUrl, maxCount]);

    if (overflow.isEmpty) return 0;

    final ids = overflow.map((r) => r['id'] as int).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final deleted = await db.delete(
      _table,
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );

    LoggerService.instance.i(
      '淘汰旧版本: chapterUrl=$chapterUrl deleted=$deleted',
      category: LogCategory.database,
      tags: ['chapter_version', 'evict'],
    );
    return deleted;
  }
}
