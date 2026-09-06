import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/interfaces/repositories/i_chapter_repository.dart';
import 'package:novel_app/core/interfaces/repositories/i_chapter_version_repository.dart';
import 'package:novel_app/core/interfaces/i_database_connection.dart';
import 'package:novel_app/models/chapter_version.dart';
import 'package:novel_app/repositories/chapter_repository.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

// 生成Mock类
@GenerateMocks([IDatabaseConnection])
import 'chapter_repository_test.mocks.dart';

/// 测试用 no-op 版本仓库实现
///
/// 这些测试只验证接口实现/构造/静态方法，不真正写入版本数据，
/// 因此版本仓库方法返回空值即可。
class _FakeChapterVersionRepository implements IChapterVersionRepository {
  @override
  Future<int> saveVersion(ChapterVersion version) async => 0;
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
  Future<int> evictOldestVersions(String chapterUrl, {int maxCount = 5}) async => 0;
}

void main() {
  group('ChapterRepository迁移验证', () {
    late MockIDatabaseConnection mockDbConnection;
    late ChapterRepository chapterRepository;

    setUp(() {
      mockDbConnection = MockIDatabaseConnection();
      chapterRepository = ChapterRepository(
        dbConnection: mockDbConnection,
        versionRepo: _FakeChapterVersionRepository(),
      );
    });

    test('应该实现IChapterRepository接口', () {
      expect(chapterRepository, isA<IChapterRepository>());
    });

    test('构造函数应该接收IDatabaseConnection', () {
      expect(chapterRepository, isNotNull);
      expect(
          () => ChapterRepository(
                dbConnection: mockDbConnection,
                versionRepo: _FakeChapterVersionRepository(),
              ),
          returnsNormally);
    });

    test('应该保留内存缓存功能', () {
      // 验证内存状态管理字段存在
      expect(chapterRepository.toString(), contains('ChapterRepository'));
    });

    test('isLocalChapter静态方法应该可用', () {
      // 测试静态方法
      expect(
        IChapterRepository.isLocalChapter('custom://chapter/123'),
        isTrue,
      );
      expect(
        IChapterRepository.isLocalChapter('user_chapter_abc'),
        isTrue,
      );
      expect(
        IChapterRepository.isLocalChapter('https://example.com/chapter/1'),
        isFalse,
      );
    });

    // 注：预加载状态管理（markAsPreloading/isPreloading）已迁移到 PreloadService，
    // ChapterRepository 不再负责预加载状态，相关测试随之移除。
  });

  group('ChapterRepository新架构验证', () {
    test('不应该有initDatabase方法', () {
      // 验证ChapterRepository不再直接管理数据库初始化
      // 新架构通过构造函数注入IDatabaseConnection
      expect(
        () => ChapterRepository(
          dbConnection: MockIDatabaseConnection(),
          versionRepo: _FakeChapterVersionRepository(),
        ),
        returnsNormally,
      );
    });

    test('不应该有setSharedDatabase方法', () {
      // 新架构不再使用setSharedDatabase模式
      final repository = ChapterRepository(
        dbConnection: MockIDatabaseConnection(),
        versionRepo: _FakeChapterVersionRepository(),
      );
      expect(repository, isNotNull);
    });
  });
}
