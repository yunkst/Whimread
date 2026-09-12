import '../../../models/paragraph_annotation.dart';

/// 段落标注仓库接口
///
/// 负责阅读页段落标注的增删查（每段落最多一条，写入走 upsert）
abstract class IParagraphAnnotationRepository {
  /// 获取指定章节的全部段落标注（按段落序号升序）
  ///
  /// [chapterUrl] 章节URL
  Future<List<ParagraphAnnotation>> getForChapter(String chapterUrl);

  /// 获取指定段落的标注，无则返回 null
  Future<ParagraphAnnotation?> getForParagraph(
      String chapterUrl, int paragraphIndex);

  /// 保存标注（同章节同段落已存在时覆盖更新）
  ///
  /// 返回落库后的行 ID
  Future<int> upsert(ParagraphAnnotation annotation);

  /// 删除指定标注，返回受影响行数
  Future<int> delete(int id);

  /// 删除指定章节的所有标注（章节缓存删除时级联清理）
  Future<int> deleteByChapter(String chapterUrl);

  /// 删除指定小说所有章节的标注（小说删除时级联清理）
  Future<int> deleteByNovel(String novelUrl);
}
