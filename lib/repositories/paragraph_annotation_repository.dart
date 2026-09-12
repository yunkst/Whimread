import 'package:sqflite/sqflite.dart';
import '../models/paragraph_annotation.dart';
import '../services/logger_service.dart';
import '../core/interfaces/repositories/i_paragraph_annotation_repository.dart';
import 'base_repository.dart';

/// 段落标注仓库实现
///
/// 每个章节的每个段落最多一条标注，
/// 由 paragraph_annotations 表的 UNIQUE(chapterUrl, paragraphIndex) 保证
class ParagraphAnnotationRepository extends BaseRepository
    implements IParagraphAnnotationRepository {
  static const String _table = 'paragraph_annotations';

  ParagraphAnnotationRepository({required super.dbConnection});

  @override
  Future<List<ParagraphAnnotation>> getForChapter(String chapterUrl) {
    return guard('paragraph_annotation.getForChapter', () async {
      final db = await database;
      final maps = await db.query(
        _table,
        where: 'chapterUrl = ?',
        whereArgs: [chapterUrl],
        orderBy: 'paragraphIndex ASC',
      );
      return maps.map((m) => ParagraphAnnotation.fromMap(m)).toList();
    });
  }

  @override
  Future<ParagraphAnnotation?> getForParagraph(
      String chapterUrl, int paragraphIndex) {
    return guard('paragraph_annotation.getForParagraph', () async {
      final db = await database;
      final maps = await db.query(
        _table,
        where: 'chapterUrl = ? AND paragraphIndex = ?',
        whereArgs: [chapterUrl, paragraphIndex],
        limit: 1,
      );
      if (maps.isEmpty) return null;
      return ParagraphAnnotation.fromMap(maps.first);
    });
  }

  @override
  Future<int> upsert(ParagraphAnnotation annotation) async {
    try {
      final db = await database;
      final id = await db.insert(
        _table,
        annotation.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      LoggerService.instance.i(
        '保存段落标注: chapterUrl=${annotation.chapterUrl} '
        'index=${annotation.paragraphIndex} id=$id',
        category: LogCategory.database,
        tags: ['paragraph_annotation', 'upsert'],
      );
      return id;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '保存段落标注失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['paragraph_annotation', 'upsert', 'failed'],
      );
      rethrow;
    }
  }

  @override
  Future<int> delete(int id) {
    return guard('paragraph_annotation.delete', () async {
      final db = await database;
      final affected = await db.delete(
        _table,
        where: 'id = ?',
        whereArgs: [id],
      );
      LoggerService.instance.d(
        '删除段落标注: id=$id affected=$affected',
        category: LogCategory.database,
        tags: ['paragraph_annotation', 'delete'],
      );
      return affected;
    });
  }

  @override
  Future<int> deleteByChapter(String chapterUrl) {
    return guard('paragraph_annotation.deleteByChapter', () async {
      final db = await database;
      final affected = await db.delete(
        _table,
        where: 'chapterUrl = ?',
        whereArgs: [chapterUrl],
      );
      LoggerService.instance.d(
        '删除章节所有段落标注: chapterUrl=$chapterUrl count=$affected',
        category: LogCategory.database,
        tags: ['paragraph_annotation', 'delete_by_chapter'],
      );
      return affected;
    });
  }

  @override
  Future<int> deleteByNovel(String novelUrl) {
    return guard('paragraph_annotation.deleteByNovel', () async {
      final db = await database;
      final affected = await db.delete(
        _table,
        where: 'novelUrl = ?',
        whereArgs: [novelUrl],
      );
      LoggerService.instance.d(
        '删除小说所有段落标注: novelUrl=$novelUrl count=$affected',
        category: LogCategory.database,
        tags: ['paragraph_annotation', 'delete_by_novel'],
      );
      return affected;
    });
  }
}
