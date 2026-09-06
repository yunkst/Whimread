import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/core/providers/bookshelf_providers.dart';
import 'package:novel_app/core/providers/service_providers.dart';
import 'package:novel_app/services/preferences_service.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bookshelf_providers_test.mocks.dart';

@GenerateMocks([SharedPreferences])
void main() {
  // 初始化Flutter绑定以支持SharedPreferences
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('[CurrentBookshelfId] - Provider状态管理测试', () {
    late ProviderContainer container;
    late MockSharedPreferences mockSharedPreferences;

    setUp(() {
      // 创建 SharedPreferences 的 mock
      mockSharedPreferences = MockSharedPreferences();

      // 配置 mock 的行为
      when(mockSharedPreferences.getInt('currentBookshelfId')).thenReturn(null);
      when(mockSharedPreferences.setInt(any, any)).thenAnswer((_) async => true);

      // 使用 mockito 来替换 SharedPreferences 的实际实现
      SharedPreferences.setMockInitialValues({});

      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('build 应该返回默认值1', () async {
      // Act - 等待异步加载完成
      final result = container.read(currentBookshelfIdProvider);
      await Future.delayed(const Duration(milliseconds: 100)); // 等待_loadSavedBookshelfId完成

      // Assert
      expect(result, equals(1),
          reason: '应该返回默认书架ID（全部小说）');
    });

    test('setBookshelfId 应该更新Provider状态', () {
      // Arrange
      const newBookshelfId = 5;

      // Act
      container
          .read(currentBookshelfIdProvider.notifier)
          .setBookshelfId(newBookshelfId);

      // Assert
      final result = container.read(currentBookshelfIdProvider);
      expect(result, equals(newBookshelfId));
    });

    test('setBookshelfId 应该支持多次设置不同的书架ID', () {
      // Arrange
      const firstId = 3;
      const secondId = 7;

      final notifier = container.read(currentBookshelfIdProvider.notifier);

      // Act
      notifier.setBookshelfId(firstId);
      final firstResult = container.read(currentBookshelfIdProvider);

      notifier.setBookshelfId(secondId);
      final secondResult = container.read(currentBookshelfIdProvider);

      // Assert
      expect(firstResult, equals(firstId));
      expect(secondResult, equals(secondId));
    });

    test('setBookshelfId 应该支持设置为0（边界值测试）', () {
      // Arrange
      const zeroBookshelfId = 0;

      // Act
      container
          .read(currentBookshelfIdProvider.notifier)
          .setBookshelfId(zeroBookshelfId);

      // Assert
      final result = container.read(currentBookshelfIdProvider);
      expect(result, equals(zeroBookshelfId));
    });

    test('setBookshelfId 应该支持设置较大的书架ID值', () {
      // Arrange
      const largeBookshelfId = 999999;

      // Act
      container
          .read(currentBookshelfIdProvider.notifier)
          .setBookshelfId(largeBookshelfId);

      // Assert
      final result = container.read(currentBookshelfIdProvider);
      expect(result, equals(largeBookshelfId));
    });

    test('setBookshelfId 应该支持快速连续设置相同的书架ID', () {
      // Arrange
      const bookshelfId = 3;

      final notifier = container.read(currentBookshelfIdProvider.notifier);

      // Act - 快速连续设置相同值3次
      notifier.setBookshelfId(bookshelfId);
      notifier.setBookshelfId(bookshelfId);
      notifier.setBookshelfId(bookshelfId);

      // Assert
      final result = container.read(currentBookshelfIdProvider);
      expect(result, equals(bookshelfId));
    });

    test('应该支持负数ID（虽然实际场景不会出现）', () {
      // Arrange
      const negativeId = -1;

      // Act
      container
          .read(currentBookshelfIdProvider.notifier)
          .setBookshelfId(negativeId);

      // Assert
      final result = container.read(currentBookshelfIdProvider);
      expect(result, equals(negativeId),
          reason: 'Provider不验证值范围，由调用方保证正确性');
    });
  });
}
