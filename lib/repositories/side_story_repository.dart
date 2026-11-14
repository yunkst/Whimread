/// 番外数据仓库
///
/// 番外 = 一条「不入书架」的 bookshelf 行（isSideStory=1，URL 为
/// `custom://sidestory/<微秒时间戳>`），其章节就是 novel_chapters/chapter_cache
/// 里该番外 novelUrl 下的普通章节行——章节列表页/阅读器/AI 写章工具全部复用，
/// 且番外章节的重排/删除与主线天然隔离（各自 novelUrl 命名空间）。
///
/// 本仓库只负责番外行的读写与级联删除；写操作统一经
/// `SideStoryMutationNotifier` 收口（写库成功后 bump `sideStorySignalProvider`，
/// 驱动徽标与列表刷新），普通调用方不要直接持有本仓库的写方法。
///
/// 递归设计：子番外的 anchorNovelUrl 指向父番外的 URL（即「番外套番外」），
/// 查询与删除均按 anchorNovelUrl 链递归处理，层数不限。
library;

import '../models/novel.dart';
import '../models/side_story_summary.dart';
import '../services/logger_service.dart';
import 'base_repository.dart';

/// 番外小说的 URL 前缀（书架过滤、原创分类判定均依赖该约定）
///
/// 必须以 `custom://` 开头：保证 ChapterLoader 对本地小说「不抓网页」的
/// 短路逻辑生效（chapter_loader.dart 对 custom:// 直接走本地库）。
const String kSideStoryUrlPrefix = 'custom://sidestory/';

/// 番外数据仓库
class SideStoryRepository extends BaseRepository {
  /// 构造函数 - 接受数据库连接实例
  SideStoryRepository({required super.dbConnection});

  // ==================== 读 ====================

  /// 查询宿主小说挂载的全部番外（含挂在番外章节上的子番外），带聚合信息
  ///
  /// [anchorNovelUrl] 宿主小说 URL（主线或父番外）
  /// [anchorChapterUrl] 可选；传入时只返回挂载在该章的番外（章级视图）
  ///
  /// 聚合列：章数 / 已读数 / 字数合计 / 锚点章标题与序号（锚点已删为 null）。
  /// 排序按加入时间倒序（新建的在前）。
  Future<List<SideStorySummary>> getSideStories({
    required String anchorNovelUrl,
    String? anchorChapterUrl,
  }) {
    return guard(
      'sideStory.getSideStories',
      () async {
        final db = await database;
        final args = <Object>[anchorNovelUrl];
        var chapterFilter = '';
        if (anchorChapterUrl != null) {
          chapterFilter = ' AND b.anchorChapterUrl = ?';
          args.add(anchorChapterUrl);
        }
        final maps = await db.rawQuery('''
          SELECT b.*,
            (SELECT COUNT(*) FROM novel_chapters nc
              WHERE nc.novelUrl = b.url) AS chapter_count,
            (SELECT COUNT(*) FROM novel_chapters nc2
              WHERE nc2.novelUrl = b.url AND nc2.readAt IS NOT NULL) AS read_count,
            (SELECT COALESCE(SUM(LENGTH(cc.content)), 0) FROM chapter_cache cc
              WHERE cc.novelUrl = b.url) AS total_chars,
            host.title AS anchor_title,
            host.chapterIndex AS anchor_index
          FROM bookshelf b
          LEFT JOIN novel_chapters host
            ON host.novelUrl = b.anchorNovelUrl
            AND host.chapterUrl = b.anchorChapterUrl
          WHERE b.isSideStory = 1 AND b.anchorNovelUrl = ?$chapterFilter
          ORDER BY b.addedAt DESC
        ''', args);
        return maps.map(_mapToSummary).toList();
      },
      message: (e) => '查询番外列表失败: $anchorNovelUrl - $e',
      category: LogCategory.database,
      tags: ['side-story', 'query', 'failed'],
    );
  }

  /// 统计宿主小说各章节挂载的番外数量（目录页/阅读器徽标数据源）
  ///
  /// 返回 `Map<anchorChapterUrl, count>`；只含有锚点章的番外行。
  Future<Map<String, int>> getSideStoryCountsByChapter(String anchorNovelUrl) {
    return guard(
      'sideStory.getSideStoryCountsByChapter',
      () async {
        final db = await database;
        final maps = await db.rawQuery('''
          SELECT anchorChapterUrl, COUNT(*) AS cnt
          FROM bookshelf
          WHERE isSideStory = 1 AND anchorNovelUrl = ?
            AND anchorChapterUrl IS NOT NULL
          GROUP BY anchorChapterUrl
        ''', [anchorNovelUrl]);
        return {
          for (final row in maps)
            row['anchorChapterUrl'] as String: row['cnt'] as int,
        };
      },
      message: (e) => '统计章节番外数失败: $anchorNovelUrl - $e',
      category: LogCategory.database,
      tags: ['side-story', 'counts', 'failed'],
    );
  }

  /// 收集以 [rootUrl] 为根的整棵番外树（含自身，含任意层级子番外）
  ///
  /// 主线小说删除时级联清理用。返回的集合一定包含 [rootUrl] 自身。
  Future<Set<String>> collectSideStoryTree(String rootUrl) {
    return guard(
      'sideStory.collectSideStoryTree',
      () async {
        final db = await database;
        final result = <String>{};
        final pending = <String>[rootUrl];
        while (pending.isNotEmpty) {
          final url = pending.removeLast();
          if (!result.add(url)) continue; // 环防御：已访问过则跳过
          final rows = await db.query(
            'bookshelf',
            columns: ['url'],
            where: 'isSideStory = 1 AND anchorNovelUrl = ?',
            whereArgs: [url],
          );
          pending.addAll(rows.map((r) => r['url'] as String));
        }
        return result;
      },
      message: (e) => '收集番外树失败: $rootUrl - $e',
      category: LogCategory.database,
      tags: ['side-story', 'collect-tree', 'failed'],
    );
  }

  // ==================== 写（须经 SideStoryMutationNotifier） ====================

  /// 创建番外行（不入书架）
  ///
  /// 作者字段继承宿主小说的作者；URL 为 [kSideStoryUrlPrefix] + 毫秒时间戳。
  /// 返回已落库的 [Novel]（含生成的主键 id）。
  ///
  /// [title] 番外标题（AI 拟定或用户输入）；[description] 需求描述存档，
  /// 留作后续「重新生成/查看创作意图」的上下文。
  Future<Novel> createSideStory({
    required String title,
    required String anchorNovelUrl,
    required String anchorChapterUrl,
    String? description,
  }) {
    return guard(
      'sideStory.createSideStory',
      () async {
        final db = await database;
        final hostRows = await db.query(
          'bookshelf',
          where: 'url = ?',
          whereArgs: [anchorNovelUrl],
          limit: 1,
        );
        final hostAuthor =
            hostRows.isNotEmpty ? hostRows.first['author'] as String? : null;

        // URL 生成：时间戳 + 探测去重。Windows 下时钟存在量化粒度，
        // 同一 tick 内连续创建（测试夹具/AI 场景快速连建）会撞
        // bookshelf.url 的 UNIQUE 约束，纯时间戳不可靠，故探测到重复
        // 就追加序号后缀。
        String url;
        var attempt = 0;
        while (true) {
          final suffix =
              attempt == 0 ? '' : '_$attempt';
          url = '$kSideStoryUrlPrefix'
              '${DateTime.now().microsecondsSinceEpoch}$suffix';
          final exists = await db.query(
            'bookshelf',
            columns: ['id'],
            where: 'url = ?',
            whereArgs: [url],
            limit: 1,
          );
          if (exists.isEmpty) break;
          attempt++;
          if (attempt > 100) {
            throw StateError('无法生成唯一的番外 URL（连续 100 次撞车）');
          }
        }

        final novel = Novel(
          title: title,
          author: hostAuthor ?? '番外',
          url: url,
          description: description,
          isSideStory: true,
          anchorNovelUrl: anchorNovelUrl,
          anchorChapterUrl: anchorChapterUrl,
        );
        final id = await db.insert('bookshelf', {
          ...novel.toMap()..remove('id'),
          'addedAt': DateTime.now().millisecondsSinceEpoch,
          'lastReadChapter': 0,
        });
        LoggerService.instance.i(
          '创建番外: "$title" (id=$id, anchor=$anchorChapterUrl)',
          category: LogCategory.database,
          tags: ['side-story', 'create', 'success'],
        );
        return novel.copyWith(id: id);
      },
      message: (e) => '创建番外失败: $title - $e',
      category: LogCategory.database,
      tags: ['side-story', 'create', 'failed'],
    );
  }

  /// 级联删除番外（含其全部子番外）
  ///
  /// 单事务删除整棵番外树的：bookshelf 行、novel_chapters、chapter_cache、
  /// chapter_versions、paragraph_annotations。只删 isSideStory=1 的行
  /// （WHERE 双重保险，杜绝误删主线小说）。
  ///
  /// 返回删除的番外部数（含子番外）。
  Future<int> deleteSideStoryTree(String sideStoryUrl) {
    return guard(
      'sideStory.deleteSideStoryTree',
      () async {
        final db = await database;
        final tree = await collectSideStoryTree(sideStoryUrl);
        var deletedCount = 0;
        await db.transaction((txn) async {
          for (final url in tree) {
            // 番外自身的章节 URL 集合（先收集，后面随 novel_chapters 一起删）
            final chapterRows = await txn.query(
              'novel_chapters',
              columns: ['chapterUrl'],
              where: 'novelUrl = ?',
              whereArgs: [url],
            );
            final chapterUrls = chapterRows
                .map((r) => r['chapterUrl'] as String)
                .toList(growable: false);

            for (final chapterUrl in chapterUrls) {
              await txn.delete(
                'paragraph_annotations',
                where: 'chapterUrl = ?',
                whereArgs: [chapterUrl],
              );
              await txn.delete(
                'chapter_versions',
                where: 'chapterUrl = ?',
                whereArgs: [chapterUrl],
              );
            }
            await txn.delete(
              'chapter_cache',
              where: 'novelUrl = ?',
              whereArgs: [url],
            );
            // 双重保险：isSideStory=1 才删 bookshelf 行
            deletedCount += await txn.delete(
              'bookshelf',
              where: 'url = ? AND isSideStory = 1',
              whereArgs: [url],
            );
            await txn.delete(
              'novel_chapters',
              where: 'novelUrl = ?',
              whereArgs: [url],
            );
          }
        });
        LoggerService.instance.i(
          '级联删除番外树: root=$sideStoryUrl, 共 $deletedCount 部',
          category: LogCategory.database,
          tags: ['side-story', 'delete', 'success'],
        );
        return deletedCount;
      },
      message: (e) => '级联删除番外失败: $sideStoryUrl - $e',
      category: LogCategory.database,
      tags: ['side-story', 'delete', 'failed'],
    );
  }

  /// 级联删除挂载在宿主小说下的全部番外（含番外的番外，任意层级）
  ///
  /// 主线小说从书架移除时调用。宿主自身的 bookshelf 行/章节/缓存不受影响
  /// （只删 isSideStory=1 的番外行及其章节体系）。返回删除的番外部数。
  Future<int> deleteSideStoriesOfNovel(String anchorNovelUrl) {
    return guard(
      'sideStory.deleteSideStoriesOfNovel',
      () async {
        final db = await database;
        final children = await db.query(
          'bookshelf',
          columns: ['url'],
          where: 'isSideStory = 1 AND anchorNovelUrl = ?',
          whereArgs: [anchorNovelUrl],
        );
        var deleted = 0;
        for (final row in children) {
          deleted += await deleteSideStoryTree(row['url'] as String);
        }
        if (deleted > 0) {
          LoggerService.instance.i(
            '级联删除宿主小说的番外: $anchorNovelUrl, 共 $deleted 部',
            category: LogCategory.database,
            tags: ['side-story', 'cascade-delete', 'success'],
          );
        }
        return deleted;
      },
      message: (e) => '级联删除宿主番外失败: $anchorNovelUrl - $e',
      category: LogCategory.database,
      tags: ['side-story', 'cascade-delete', 'failed'],
    );
  }

  // ==================== 内部 ====================

  /// 行 Map → [SideStorySummary]（聚合列与锚点列一并解析）
  SideStorySummary _mapToSummary(Map<String, dynamic> row) {
    final novel = Novel.fromMap(row);
    return SideStorySummary(
      novel: novel,
      chapterCount: (row['chapter_count'] as int?) ?? 0,
      readCount: (row['read_count'] as int?) ?? 0,
      totalChars: (row['total_chars'] as int?) ?? 0,
      anchorChapterTitle: row['anchor_title'] as String?,
      anchorChapterIndex: row['anchor_index'] as int?,
    );
  }
}
