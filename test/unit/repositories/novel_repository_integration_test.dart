import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/interfaces/repositories/i_novel_repository.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/repositories/novel_repository.dart';
import 'package:novel_app/models/novel.dart';

import '../../helpers/test_database_setup.dart';

/// NovelRepository 集成测试
///
/// 使用真实内存数据库测试，验证数据库交互逻辑
///
/// 测试覆盖：
/// - 真实的SQL插入、查询、更新、删除操作
/// - 数据映射是否正确
/// - 约束是否生效
/// - 排序逻辑是否正确
void main() {
  group('NovelRepository - 真实数据库集成测试', () {
    late NovelRepository repository;

    setUp(() async {
      // 创建真实内存数据库
      final db = await TestDatabaseSetup.createInMemoryDatabase();

      // 创建数据库连接并注入到Repository
      final connection = DatabaseConnection.forTesting(db);
      repository = NovelRepository(dbConnection: connection);
    });

    group('真实数据库插入和查询', () {
      test('应该真实地插入并查询小说', () async {
        // Arrange - 准备测试数据
        final testNovel = Novel(
          title: '测试小说',
          author: '测试作者',
          url: 'https://test.com/novel/1',
          coverUrl: 'https://test.com/cover.jpg',
          description: '这是测试描述',
          backgroundSetting: '测试设定',
        );

        // Act - 真实插入数据库
        final insertId = await repository.addToBookshelf(testNovel);

        // Assert - 验证插入成功
        expect(insertId, greaterThan(0));

        // Act - 真实查询数据库
        final novels = await repository.getNovels();

        // Assert - 验证查询结果
        expect(novels.length, 1);
        expect(novels[0].title, '测试小说');
        expect(novels[0].author, '测试作者');
        expect(novels[0].url, 'https://test.com/novel/1');
        expect(novels[0].coverUrl, 'https://test.com/cover.jpg');
        expect(novels[0].description, '这是测试描述');
        expect(novels[0].backgroundSetting, '测试设定');
        expect(novels[0].isInBookshelf, isTrue);
      });

      test('URL唯一性约束应该生效', () async {
        // Arrange - 两本URL相同的小说
        final novel1 = Novel(
          title: '小说1',
          author: '作者1',
          url: 'https://test.com/same-url',
        );
        final novel2 = Novel(
          title: '小说2',
          author: '作者2',
          url: 'https://test.com/same-url', // 相同URL
        );

        // Act - 插入第一本
        await repository.addToBookshelf(novel1);

        // Act & Assert - 第二本应该更新（replace策略）
        final insertId = await repository.addToBookshelf(novel2);
        expect(insertId, greaterThan(0));

        // 验证只有一本小说（被替换了）
        final novels = await repository.getNovels();
        expect(novels.length, 1);
        expect(novels[0].title, '小说2'); // 被替换成新的
      });
    });

    group('lastReadChapterIndex 字段映射测试', () {
      test('应该正确映射 lastReadChapter 字段到 Novel.lastReadChapterIndex',
          () async {
        // Arrange - 插入有阅读进度的小说
        final novel1 = Novel(
          title: '有进度的小说',
          author: '作者1',
          url: 'https://test.com/novel/1',
        );
        await repository.addToBookshelf(novel1);

        // Act - 更新阅读进度
        await repository.updateLastReadChapter('https://test.com/novel/1', 5);

        // Assert - 验证字段映射
        final result = await repository.getNovels();
        expect(result.length, 1);
        expect(result[0].lastReadChapterIndex, 5);
      });

      test('lastReadChapter 为 0 应该正确映射', () async {
        // Arrange - 插入小说并设置第一章（索引为0）
        final novel = Novel(
          title: '第一章',
          author: '作者',
          url: 'https://test.com/novel/first',
        );
        await repository.addToBookshelf(novel);

        // Act - 设置 lastReadChapter = 0
        await repository.updateLastReadChapter('https://test.com/novel/first', 0);

        // Assert
        final result = await repository.getNovels();
        expect(result.length, 1);
        expect(result[0].lastReadChapterIndex, 0);
      });

      test('lastReadChapter 为默认值应该正确映射', () async {
        // Arrange - 插入从未阅读过的小说
        final novel = Novel(
          title: '新小说',
          author: '作者',
          url: 'https://test.com/novel/new',
        );
        await repository.addToBookshelf(novel);

        // 不设置 lastReadChapter（保持默认值0）

        // Act
        final result = await repository.getNovels();

        // Assert - 默认值为0
        expect(result.length, 1);
        expect(result[0].lastReadChapterIndex, 0);
      });
    });

    group('排序逻辑测试', () {
      test('应该按 lastReadTime DESC 排序', () async {
        // Arrange - 插入不同阅读时间的小说
        final novels = [
          Novel(
            title: '最早阅读',
            author: '作者1',
            url: 'https://test.com/novel/1',
          ),
          Novel(
            title: '最近阅读',
            author: '作者2',
            url: 'https://test.com/novel/2',
          ),
          Novel(
            title: '中间阅读',
            author: '作者3',
            url: 'https://test.com/novel/3',
          ),
        ];

        // 插入所有小说
        for (final novel in novels) {
          await repository.addToBookshelf(novel);
        }

        // 设置不同的 lastReadChapter（会自动更新 lastReadTime）
        await repository.updateLastReadChapter('https://test.com/novel/1', 1);
        await Future.delayed(const Duration(milliseconds: 10));
        await repository.updateLastReadChapter('https://test.com/novel/3', 2);
        await Future.delayed(const Duration(milliseconds: 10));
        await repository.updateLastReadChapter('https://test.com/novel/2', 3);

        // Act - 查询书架
        final result = await repository.getNovels();

        // Assert - 验证排序（最近阅读的在前）
        expect(result.length, 3);
        expect(result[0].title, '最近阅读');
        expect(result[1].title, '中间阅读');
        expect(result[2].title, '最早阅读');
      });

      test('lastReadTime 相同时应该按 addedAt DESC 排序', () async {
        // Arrange - 插入小说（后添加的 addedAt 更大）
        final novel1 = Novel(
          title: '先添加',
          author: '作者1',
          url: 'https://test.com/novel/1',
        );
        await repository.addToBookshelf(novel1);

        // 等待1毫秒确保 addedAt 不同
        await Future.delayed(const Duration(milliseconds: 1));

        final novel2 = Novel(
          title: '后添加',
          author: '作者2',
          url: 'https://test.com/novel/2',
        );
        await repository.addToBookshelf(novel2);

        // Act - 查询（都没有 lastReadTime）
        final result = await repository.getNovels();

        // Assert - 后添加的在前
        expect(result.length, 2);
        expect(result[0].title, '后添加');
        expect(result[1].title, '先添加');
      });
    });

    group('删除操作测试', () {
      test('应该真实地从数据库删除小说', () async {
        // Arrange - 插入小说
        final novel = Novel(
          title: '要删除的小说',
          author: '作者',
          url: 'https://test.com/novel/delete',
        );
        await repository.addToBookshelf(novel);

        // 验证插入成功
        var novels = await repository.getNovels();
        expect(novels.length, 1);

        // Act - 删除小说
        final deletedCount = await repository.removeFromBookshelf('https://test.com/novel/delete');

        // Assert - 验证删除成功
        expect(deletedCount, 1);

        novels = await repository.getNovels();
        expect(novels.length, 0);
      });

      test('删除不存在的小说应该返回0', () async {
        // Act - 删除不存在的小说
        final deletedCount =
            await repository.removeFromBookshelf('https://test.com/novel/not-exist');

        // Assert
        expect(deletedCount, 0);
      });
    });

    group('更新操作测试', () {
      test('应该真实地更新 lastReadChapter', () async {
        // Arrange
        final novel = Novel(
          title: '测试小说',
          author: '作者',
          url: 'https://test.com/novel/update',
        );
        await repository.addToBookshelf(novel);

        // Act - 更新阅读进度
        final updatedCount =
            await repository.updateLastReadChapter('https://test.com/novel/update', 5);

        // Assert - 验证更新成功
        expect(updatedCount, 1);

        final novels = await repository.getNovels();
        expect(novels[0].lastReadChapterIndex, 5);
      });

      test('应该真实地更新 backgroundSetting', () async {
        // Arrange
        final novel = Novel(
          title: '测试小说',
          author: '作者',
          url: 'https://test.com/novel/setting',
        );
        await repository.addToBookshelf(novel);

        // Act - 更新背景设定
        final updatedCount = await repository
            .updateBackgroundSetting('https://test.com/novel/setting', '新的背景设定');

        // Assert
        expect(updatedCount, 1);

        final novels = await repository.getNovels();
        expect(novels[0].backgroundSetting, '新的背景设定');
      });
    });

    group('边界情况测试', () {
      test('空书架应该返回空列表', () async {
        // Act - 查询空书架
        final result = await repository.getNovels();

        // Assert
        expect(result, isEmpty);
      });

      test('应该正确处理特殊字符', () async {
        // Arrange - 包含特殊字符的小说
        final novel = Novel(
          title: '测试\'小说"包含\n换行\t制表符',
          author: '作者',
          url: 'https://test.com/novel/special',
        );
        await repository.addToBookshelf(novel);

        // Act
        final result = await repository.getNovels();

        // Assert - 特殊字符应该被正确存储和查询
        expect(result.length, 1);
        expect(result[0].title, contains('\''));
        expect(result[0].title, contains('"'));
        expect(result[0].title, contains('\n'));
      });

      test('长文本应该被正确存储', () async {
        // Arrange - 超长描述
        final longDescription = 'A' * 10000; // 10000个字符
        final novel = Novel(
          title: '长文本测试',
          author: '作者',
          url: 'https://test.com/novel/long',
          description: longDescription,
        );
        await repository.addToBookshelf(novel);

        // Act
        final result = await repository.getNovels();

        // Assert
        expect(result.length, 1);
        expect(result[0].description?.length, 10000);
      });
    });

    group('检查小说是否存在', () {
      test('应该正确检查小说是否在书架中', () async {
        // Arrange
        final novel = Novel(
          title: '测试小说',
          author: '作者',
          url: 'https://test.com/novel/check',
        );
        await repository.addToBookshelf(novel);

        // Act & Assert
        expect(await repository.isInBookshelf('https://test.com/novel/check'), isTrue);
        expect(await repository.isInBookshelf('https://test.com/novel/not-exist'), isFalse);
      });
    });
  });
}
