import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/repositories/prompt_tag_repository.dart';
import 'package:novel_app/repositories/prompt_tag_category_repository.dart';
import 'package:novel_app/models/prompt_tag.dart';
import 'package:novel_app/models/prompt_tag_category.dart';

import '../../helpers/test_database_setup.dart';

/// PromptTagRepository 集成测试
///
/// 使用真实内存数据库验证标签移动功能
///
/// 测试覆盖：
/// - moveToCategory: 标签跨分类移动
/// - getNextSortOrder: 获取下一个排序序号
/// - 移动后数据一致性
/// - 边界场景
void main() {
  late PromptTagRepository tagRepo;
  late PromptTagCategoryRepository categoryRepo;

  setUp(() async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    final connection = DatabaseConnection.forTesting(db);
    tagRepo = PromptTagRepository(dbConnection: connection);
    categoryRepo = PromptTagCategoryRepository(dbConnection: connection);
  });

  // ============================================================
  // 辅助方法
  // ============================================================

  Future<int> createCategory(String name, {int sortOrder = 0}) async {
    final now = DateTime.now();
    return categoryRepo.save(PromptTagCategory(
      name: name,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<int> createTag(int categoryId, String name, String prompt,
      {int sortOrder = 0}) async {
    final now = DateTime.now();
    return tagRepo.save(PromptTag(
      categoryId: categoryId,
      name: name,
      promptText: prompt,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    ));
  }

  // ============================================================
  // getNextSortOrder 测试
  // ============================================================

  group('getNextSortOrder', () {
    test('空分类应返回 0', () async {
      final catId = await createCategory('测试分类');

      final result = await tagRepo.getNextSortOrder(catId);

      expect(result, 0);
    });

    test('有标签的分类应返回 max(sort_order) + 1', () async {
      final catId = await createCategory('测试分类');
      await createTag(catId, '标签A', '提示词A', sortOrder: 0);
      await createTag(catId, '标签B', '提示词B', sortOrder: 3);
      await createTag(catId, '标签C', '提示词C', sortOrder: 7);

      final result = await tagRepo.getNextSortOrder(catId);

      expect(result, 8);
    });

    test('不同分类的标签互不影响', () async {
      final catA = await createCategory('分类A');
      final catB = await createCategory('分类B');
      await createTag(catA, '标签A', '提示词A', sortOrder: 5);
      await createTag(catB, '标签B', '提示词B', sortOrder: 10);

      expect(await tagRepo.getNextSortOrder(catA), 6);
      expect(await tagRepo.getNextSortOrder(catB), 11);
    });
  });

  // ============================================================
  // moveToCategory 测试
  // ============================================================

  group('moveToCategory', () {
    test('应该将标签移动到目标分类', () async {
      final catA = await createCategory('分类A');
      final catB = await createCategory('分类B');
      final tagId = await createTag(catA, '待移动标签', '提示词内容');

      await tagRepo.moveToCategory(tagId, catB);

      // 原分类不再有该标签
      final catATags = await tagRepo.getByCategory(catA);
      expect(catATags, isEmpty);

      // 目标分类包含该标签
      final catBTags = await tagRepo.getByCategory(catB);
      expect(catBTags.length, 1);
      expect(catBTags.first.name, '待移动标签');
      expect(catBTags.first.promptText, '提示词内容');
      expect(catBTags.first.categoryId, catB);
    });

    test('移动后 sortOrder 应为目标分类的末尾', () async {
      final catA = await createCategory('分类A');
      final catB = await createCategory('分类B');
      // catB 已有 2 个标签
      await createTag(catB, '已有标签1', 'p1', sortOrder: 0);
      await createTag(catB, '已有标签2', 'p2', sortOrder: 5);
      final tagId = await createTag(catA, '待移动', 'p', sortOrder: 99);

      await tagRepo.moveToCategory(tagId, catB);

      final catBTags = await tagRepo.getByCategory(catB);
      final moved = catBTags.firstWhere((t) => t.name == '待移动');
      expect(moved.sortOrder, 6); // max(0,5)+1 = 6
    });

    test('移动到空分类时 sortOrder 应为 0', () async {
      final catA = await createCategory('分类A');
      final catB = await createCategory('分类B');
      final tagId = await createTag(catA, '标签', '提示词');

      await tagRepo.moveToCategory(tagId, catB);

      final catBTags = await tagRepo.getByCategory(catB);
      expect(catBTags.first.sortOrder, 0);
    });

    test('移动后标签的其他字段保持不变', () async {
      final catA = await createCategory('分类A');
      final catB = await createCategory('分类B');
      final tagId = await createTag(catA, '原始标签', '原始提示词');

      // 获取原始标签数据
      final originalTags = await tagRepo.getByCategory(catA);
      final original = originalTags.first;
      final originalCreatedAt = original.createdAt;

      // 等待 5ms 确保 updatedAt 时间戳能产生差异
      await Future.delayed(const Duration(milliseconds: 5));
      await tagRepo.moveToCategory(tagId, catB);

      final movedTags = await tagRepo.getByCategory(catB);
      final moved = movedTags.first;
      expect(moved.id, tagId);
      expect(moved.name, '原始标签');
      expect(moved.promptText, '原始提示词');
      expect(moved.createdAt, originalCreatedAt);
      // updatedAt 应该被更新
      expect(moved.updatedAt.millisecondsSinceEpoch,
          greaterThan(originalCreatedAt.millisecondsSinceEpoch));
    });

    test('连续移动多个标签到同一分类排序应递增', () async {
      final catA = await createCategory('分类A');
      final catB = await createCategory('分类B');
      final tag1 = await createTag(catA, '标签1', 'p1');
      final tag2 = await createTag(catA, '标签2', 'p2');
      final tag3 = await createTag(catA, '标签3', 'p3');

      await tagRepo.moveToCategory(tag1, catB);
      await tagRepo.moveToCategory(tag2, catB);
      await tagRepo.moveToCategory(tag3, catB);

      final catBTags = await tagRepo.getByCategory(catB);
      expect(catBTags.length, 3);
      // 验证排序值递增
      final sortOrders = catBTags.map((t) => t.sortOrder).toList();
      expect(sortOrders[0], 0);
      expect(sortOrders[1], 1);
      expect(sortOrders[2], 2);
    });

    test('只移动指定标签，不影响同分类其他标签', () async {
      final catA = await createCategory('分类A');
      final catB = await createCategory('分类B');
      final tag1 = await createTag(catA, '标签1', 'p1');
      await createTag(catA, '标签2', 'p2');
      await createTag(catA, '标签3', 'p3');

      await tagRepo.moveToCategory(tag1, catB);

      // 原分类还剩 2 个标签
      final catATags = await tagRepo.getByCategory(catA);
      expect(catATags.length, 2);
      expect(catATags.any((t) => t.name == '标签1'), isFalse);
      expect(catATags.any((t) => t.name == '标签2'), isTrue);
      expect(catATags.any((t) => t.name == '标签3'), isTrue);
    });

    test('标签来回移动应正常工作', () async {
      final catA = await createCategory('分类A');
      final catB = await createCategory('分类B');
      final tagId = await createTag(catA, '往返标签', '提示词');

      // A → B
      await tagRepo.moveToCategory(tagId, catB);
      expect((await tagRepo.getByCategory(catA)), isEmpty);
      expect((await tagRepo.getByCategory(catB)).length, 1);

      // B → A
      await tagRepo.moveToCategory(tagId, catA);
      expect((await tagRepo.getByCategory(catA)).length, 1);
      expect((await tagRepo.getByCategory(catB)), isEmpty);

      // 验证数据完整
      final tags = await tagRepo.getByCategory(catA);
      expect(tags.first.name, '往返标签');
    });
  });

  // ============================================================
  // save (copyWith categoryId) 兼容性测试
  // ============================================================

  group('save - 通过 copyWith 修改 categoryId', () {
    test('应该也能实现分类移动', () async {
      final catA = await createCategory('分类A');
      final catB = await createCategory('分类B');
      final tagId = await createTag(catA, 'copyWith移动', '提示词');

      // 模拟通过 save + copyWith 移动
      final tags = await tagRepo.getByCategory(catA);
      final original = tags.first;
      await tagRepo.save(original.copyWith(
        categoryId: catB,
        updatedAt: DateTime.now(),
      ));

      expect((await tagRepo.getByCategory(catA)), isEmpty);
      final catBTags = await tagRepo.getByCategory(catB);
      expect(catBTags.length, 1);
      expect(catBTags.first.name, 'copyWith移动');
      expect(catBTags.first.categoryId, catB);
    });
  });
}
