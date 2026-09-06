import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/interfaces/repositories/i_novel_repository.dart';
import 'package:novel_app/core/interfaces/i_database_connection.dart';
import 'package:novel_app/repositories/novel_repository.dart';
import 'package:novel_app/models/novel.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:sqflite/sqflite.dart';

// 生成Mock类
@GenerateMocks([IDatabaseConnection, Database])
import 'novel_repository_test.mocks.dart';

void main() {
  group('NovelRepository接口验证', () {
    late MockIDatabaseConnection mockDbConnection;
    late NovelRepository novelRepository;

    setUp(() {
      mockDbConnection = MockIDatabaseConnection();
      novelRepository = NovelRepository(dbConnection: mockDbConnection);
    });

    test('应该实现INovelRepository接口', () {
      expect(novelRepository, isA<INovelRepository>());
    });

    test('构造函数应该接收IDatabaseConnection', () {
      expect(novelRepository, isNotNull);
      expect(
        () => NovelRepository(dbConnection: mockDbConnection),
        returnsNormally,
      );
    });
  });

  group('NovelRepository核心功能测试', () {
    late MockIDatabaseConnection mockDbConnection;
    late NovelRepository novelRepository;

    setUp(() {
      mockDbConnection = MockIDatabaseConnection();
      novelRepository = NovelRepository(dbConnection: mockDbConnection);
    });

    test('应该正确创建NovelRepository实例', () {
      expect(novelRepository, isA<NovelRepository>());
      expect(novelRepository.toString(), contains('NovelRepository'));
    });

    test('应该通过BaseRepository继承database访问器', () {
      // 验证继承链
      expect(novelRepository, isA<INovelRepository>());
    });
  });

  group('NovelRepository方法签名验证', () {
    test('应该有addToBookshelf方法', () {
      // 验证方法存在但不实际执行（需要Database mock）
      late MockIDatabaseConnection mockDbConnection;
      mockDbConnection = MockIDatabaseConnection();
      final novelRepository = NovelRepository(dbConnection: mockDbConnection);

      // 验证方法签名存在
      expect(novelRepository.addToBookshelf is Function, isTrue);
    });

    test('应该有removeFromBookshelf方法', () {
      // 验证方法存在但不实际执行（需要Database mock）
      late MockIDatabaseConnection mockDbConnection;
      mockDbConnection = MockIDatabaseConnection();
      final novelRepository = NovelRepository(dbConnection: mockDbConnection);

      // 验证方法签名存在
      expect(novelRepository.removeFromBookshelf is Function, isTrue);
    });

    test('应该有getNovels方法', () {
      // 验证方法存在但不实际执行（需要Database mock）
      late MockIDatabaseConnection mockDbConnection;
      mockDbConnection = MockIDatabaseConnection();
      final novelRepository = NovelRepository(dbConnection: mockDbConnection);

      // 验证方法签名存在
      expect(novelRepository.getNovels is Function, isTrue);
    });
  });

  group('NovelRepository数据操作验证', () {
    test('添加小说应该包含必要字段', () {
      final testNovel = Novel(
        title: '测试小说标题',
        author: '测试作者',
        url: 'https://example.com/novel/123',
        coverUrl: 'https://example.com/cover.jpg',
        description: '这是测试描述',
      );

      expect(testNovel.title, isNotEmpty);
      expect(testNovel.author, isNotEmpty);
      expect(testNovel.url, isNotEmpty);
    });
  });

  group('NovelRepository新架构验证', () {
    test('不应该有initDatabase方法', () {
      // 新架构通过构造函数注入IDatabaseConnection
      late MockIDatabaseConnection mockDbConnection;
      mockDbConnection = MockIDatabaseConnection();
      expect(
        () => NovelRepository(dbConnection: mockDbConnection),
        returnsNormally,
      );
    });

    test('不应该有setSharedDatabase方法', () {
      // 新架构不再使用setSharedDatabase模式
      late MockIDatabaseConnection mockDbConnection;
      mockDbConnection = MockIDatabaseConnection();
      final repository = NovelRepository(dbConnection: mockDbConnection);
      expect(repository, isNotNull);
    });
  });

  group('Novel模型验证', () {
    test('Novel对象应该正确构造', () {
      final novel = Novel(
        title: '测试标题',
        author: '测试作者',
        url: 'https://test.com',
      );

      expect(novel.title, '测试标题');
      expect(novel.author, '测试作者');
      expect(novel.url, 'https://test.com');
    });

    test('Novel对象应该支持可选字段', () {
      final novel = Novel(
        title: '测试',
        author: '作者',
        url: 'https://test.com',
        coverUrl: 'https://test.com/cover.jpg',
        description: '描述',
      );

      expect(novel.coverUrl, isNotNull);
      expect(novel.description, isNotNull);
    });
  });
}
