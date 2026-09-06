# Flutter 测试最佳实践参考

## 目录结构

```
test/
├── unit/
│   ├── services/           # 服务层测试
│   │   ├── database_service_test.dart
│   │   ├── character_extraction_service_test.dart
│   │   └── ...
│   ├── controllers/        # 控制器测试
│   │   ├── chapter_loader_test.dart
│   │   └── ...
│   ├── widgets/            # Widget测试
│   │   └── stream_content_widget_test.dart
│   └── repositories/       # 仓库测试
├── test_helpers/           # 测试辅助工具
│   └── mock_data.dart
└── widget_test.dart        # 示例widget测试
```

## 完整测试示例

### 服务层测试（带数据库）

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:novel_app/services/database_service.dart';
import 'package:novel_app/models/chapter.dart';
import '../../test_helpers/mock_data.dart';

/// ChapterService 单元测试
///
/// 测试章节服务的核心功能：
/// - 章节缓存
/// - 章节查询
/// - 章节更新
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ChapterService - 章节缓存测试', () {
    late DatabaseService dbService;

    setUp(() async {
      dbService = DatabaseService();
      final db = await dbService.database;
      await db.delete('chapter_cache');
    });

    test('cacheChapter 应该成功缓存章节内容', () async {
      final chapter = MockData.createTestChapter(
        title: '测试章节',
        content: '这是测试内容',
      );

      final result = await dbService.cacheChapter(
        'https://test.com/novel',
        chapter,
        chapter.content!,
      );

      expect(result, greaterThan(0));
    });

    test('getCachedChapter 应该返回已缓存的章节', () async {
      // 先缓存
      final chapter = MockData.createTestChapter(
        url: 'https://test.com/chapter/1',
        content: '原始内容',
      );
      await dbService.cacheChapter('https://test.com', chapter, chapter.content!);

      // 再查询
      final cached = await dbService.getCachedChapter('https://test.com/chapter/1');

      expect(cached, isNotNull);
      expect(cached!.content, '原始内容');
    });
  });
}
```

### 字符串处理服务测试

```dart
import 'package:flutter_test/flutter_test.dart';

/// StringProcessingService 单元测试
void main() {
  group('StringProcessingService - 字符串处理测试', () {
    test('mergeAndDeduplicateContexts 空列表应该返回空字符串', () {
      final service = StringProcessingService();
      final result = service.mergeAndDeduplicateContexts([]);

      expect(result, isEmpty);
    });

    test('mergeAndDeduplicateContexts 重叠片段应该合并', () {
      final service = StringProcessingService();
      final contexts = [
        '这是一段很长的内容，有重叠的部分',
        '很长的内容，有重叠的部分在这里继续',
      ];

      final result = service.mergeAndDeduplicateContexts(contexts, minGap: 10);

      // 验证重叠部分被去重
      expect(result.length, lessThan(contexts[0].length + contexts[1].length));
      expect(result, contains('这是一段很长的内容'));
      expect(result, contains('在这里继续'));
    });
  });
}
```

### 控制器测试

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:novel_app/controllers/chapter_loader.dart';

/// ChapterLoader 单元测试
void main() {
  group('ChapterLoader - 加载控制测试', () {
    late ChapterLoader loader;
    late MockApiService mockApi;

    setUp(() {
      mockApi = MockApiService();
      loader = ChapterLoader(apiService: mockApi);
    });

    test('loadChapter 应该成功加载章节', () async {
      final mockChapter = MockData.createTestChapter();
      when(mockApi.fetchChapter(any)).thenAnswer((_) async => mockChapter);

      final result = await loader.loadChapter('https://test.com/chapter/1');

      expect(result, isNotNull);
      expect(result.title, mockChapter.title);
      verify(mockApi.fetchChapter('https://test.com/chapter/1')).called(1);
    });

    test('loadChapter 网络错误应该返回null', () async {
      when(mockApi.fetchChapter(any)).thenThrow(Exception('网络错误'));

      final result = await loader.loadChapter('https://test.com/chapter/1');

      expect(result, isNull);
    });
  });
}
```

## 常用断言

```dart
// 相等性
expect(actual, equals(expected));
expect(actual, expected);
expect(actual, same(expected));  // 同一实例

// 空值检查
expect(value, isNull);
expect(value, isNotNull);
expect(list, isEmpty);
expect(list, isNotEmpty);

// 数值比较
expect(number, greaterThan(0));
expect(number, greaterThanOrEqualTo(10));
expect(number, lessThan(100));
expect(number, closeTo(10.0, 0.1));  // 浮点数近似

// 字符串
expect(string, contains('substring'));
expect(string, startsWith('prefix'));
expect(string, endsWith('suffix'));
expect(string, matches(r'^\d+$'));

// 列表
expect(list, length(3));
expect(list, contains(element));
expect(list, orderedEquals([1, 2, 3]));

// 异常
expect(() => throwException(), throwsA(isA<StateException>()));
expect(() => throwException(), throwsException);

// 异步
expectFuture = expectLater(future, completion(expected));
expectLater(future, throwsA(isA<Exception>()));
```

## Mock Data 扩展

```dart
/// 扩展 MockData 类以支持更多测试场景
class MockData {
  /// 创建带特殊字符的章节（用于测试边界情况）
  static Chapter createChapterWithSpecialChars({
    String? content,
  }) {
    return createTestChapter(
      content: content ?? '包含\n换行符\t和"引号"的内容',
    );
  }

  /// 创建空内容章节
  static Chapter createEmptyChapter() {
    return createTestChapter(content: '');
  }

  /// 创建超长内容章节（用于测试长度限制）
  static Chapter createLongChapter({int length = 100000}) {
    return createTestChapter(
      content: 'A' * length,
    );
  }
}
```

## 测试覆盖率

```bash
# 生成覆盖率报告
flutter test --coverage

# 在线查看覆盖率（需要安装 lcov）
genhtml coverage/lcov.info -o coverage/html

# 在浏览器中打开
open coverage/html/index.html
```
