import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/interfaces/repositories/i_chapter_version_repository.dart';
import 'package:novel_app/models/chapter.dart';
import 'package:novel_app/models/chapter_version.dart';
import 'package:novel_app/models/paragraph_annotation.dart';
import 'package:novel_app/repositories/chapter_repository.dart';
import 'package:novel_app/repositories/paragraph_annotation_repository.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../../helpers/test_database_setup.dart';

/// ParagraphAnnotationRepository 集成测试
///
/// 使用真实内存数据库验证标注 CRUD、upsert 幂等和级联清理
void main() {
  late ParagraphAnnotationRepository repo;
  late ChapterRepository chapterRepo;

  const novelUrl = 'https://example.com/book/1';
  const chapterUrl = 'https://example.com/book/1/chapter/1';

  setUp(() async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    final connection = DatabaseConnection.forTesting(db);
    repo = ParagraphAnnotationRepository(dbConnection: connection);
    chapterRepo = ChapterRepository(
      dbConnection: connection,
      versionRepo: _NoopVersionRepo(),
      annotationRepo: repo,
    );
  });

  ParagraphAnnotation annotation(
    int paragraphIndex, {
    String content = '这段写得真好',
    String chapter = chapterUrl,
    String novel = novelUrl,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ParagraphAnnotation(
      novelUrl: novel,
      chapterUrl: chapter,
      paragraphIndex: paragraphIndex,
      paragraphPreview: ParagraphAnnotation.buildPreview('这是第$paragraphIndex段原文'),
      content: content,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('upsert 新增后可按章节查询', () async {
    await repo.upsert(annotation(0));
    await repo.upsert(annotation(2));

    final list = await repo.getForChapter(chapterUrl);
    expect(list, hasLength(2));
    // 按段落序号升序
    expect(list.map((a) => a.paragraphIndex).toList(), [0, 2]);
    expect(list.first.id, isNotNull);
  });

  test('upsert 同段落覆盖更新，保留创建时间', () async {
    final first = annotation(1, content: '第一版');
    final firstId = await repo.upsert(first);

    final saved = await repo.getForParagraph(chapterUrl, 1);
    expect(saved, isNotNull);
    expect(saved!.content, '第一版');

    // 同段落再写：更新为新内容，createdAt 不变
    final edited = ParagraphAnnotation(
      novelUrl: novelUrl,
      chapterUrl: chapterUrl,
      paragraphIndex: 1,
      paragraphPreview: first.paragraphPreview,
      content: '第二版',
      createdAt: first.createdAt,
      updatedAt: first.updatedAt + 1000,
    );
    final secondId = await repo.upsert(edited);

    final list = await repo.getForChapter(chapterUrl);
    expect(list, hasLength(1));
    expect(list.first.content, '第二版');
    expect(list.first.createdAt, first.createdAt);
    expect(list.first.updatedAt, first.updatedAt + 1000);
    // 冲突替换 = 删旧行插新行，id 重新分配
    expect(secondId, isNot(firstId));
  });

  test('getForParagraph 无标注时返回 null', () async {
    final result = await repo.getForParagraph(chapterUrl, 99);
    expect(result, isNull);
  });

  test('delete 删除指定标注', () async {
    final id = await repo.upsert(annotation(0));

    final affected = await repo.delete(id);
    expect(affected, 1);
    expect(await repo.getForChapter(chapterUrl), isEmpty);
  });

  test('deleteByChapter 只清理指定章节', () async {
    await repo.upsert(annotation(0));
    await repo.upsert(annotation(1, chapter: 'https://example.com/book/1/chapter/2'));

    await repo.deleteByChapter(chapterUrl);

    expect(await repo.getForChapter(chapterUrl), isEmpty);
    expect(
      await repo.getForChapter('https://example.com/book/1/chapter/2'),
      hasLength(1),
    );
  });

  test('deleteByNovel 清理该小说所有章节的标注', () async {
    await repo.upsert(annotation(0));
    await repo.upsert(annotation(1, chapter: 'https://example.com/book/1/chapter/2'));
    await repo.upsert(annotation(
      0,
      chapter: 'https://example.com/book/2/chapter/1',
      novel: 'https://example.com/book/2',
    ));

    await repo.deleteByNovel(novelUrl);

    expect(
      await repo.getForChapter('https://example.com/book/2/chapter/1'),
      hasLength(1),
    );
    expect(await repo.getForChapter(chapterUrl), isEmpty);
  });

  test('buildPreview 截断超长段落并加省略号', () async {
    final long = '字' * (ParagraphAnnotation.previewMaxLength + 10);
    final preview = ParagraphAnnotation.buildPreview(long);
    expect(preview.length, ParagraphAnnotation.previewMaxLength + 1);
    expect(preview.endsWith('…'), isTrue);
  });

  test('ChapterRepository.deleteChapterCache 级联清理章节标注', () async {
    await chapterRepo.cacheChapter(
        novelUrl, Chapter(title: '章节', url: chapterUrl), '正文');
    await repo.upsert(annotation(0));

    await chapterRepo.deleteChapterCache(chapterUrl);

    expect(await repo.getForChapter(chapterUrl), isEmpty);
  });

  test('ChapterRepository.deleteCachedChapters 级联清理小说标注', () async {
    await chapterRepo.cacheChapter(
        novelUrl, Chapter(title: '章节', url: chapterUrl), '正文');
    await chapterRepo.cacheChapter(novelUrl,
        Chapter(title: '章节2', url: 'https://example.com/book/1/chapter/2'), '正文');
    await repo.upsert(annotation(0));
    await repo.upsert(annotation(0, chapter: 'https://example.com/book/1/chapter/2'));

    await chapterRepo.deleteCachedChapters(novelUrl);

    expect(await repo.getForChapter(chapterUrl), isEmpty);
    expect(
      await repo.getForChapter('https://example.com/book/1/chapter/2'),
      isEmpty,
    );
  });
}

/// 级联测试不需要真实版本仓库，提供空实现
class _NoopVersionRepo implements IChapterVersionRepository {
  @override
  Future<int> saveVersion(ChapterVersion version,
          {DatabaseExecutor? executor}) async =>
      0;

  @override
  Future<List<ChapterVersion>> getVersions(String chapterUrl) async => [];

  @override
  Future<int> getVersionCount(String chapterUrl) async => 0;

  @override
  Future<ChapterVersion?> getVersionById(int id) async => null;

  @override
  Future<int> deleteVersion(int id) async => 0;

  @override
  Future<int> deleteVersionsByChapter(String chapterUrl) async => 0;

  @override
  Future<int> deleteVersionsByNovel(String novelUrl) async => 0;

  @override
  Future<int> evictOldestVersions(String chapterUrl,
      {int maxCount = 5, DatabaseExecutor? executor}) async =>
      0;
}
