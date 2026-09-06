/// ToolExecutor 提示标签工具单元测试
///
/// 覆盖最近一次重构的两个行为：
/// 1. `list_prompt_tags` 返回精简字段（仅 id / name / reason，不再含 promptText）
/// 2. `get_prompt_tag` 按 id 或 name 查看完整 promptText，含各种错误引导
///
/// 用 Fake Repository 替代真实 SQLite，聚焦 ToolExecutor 调度逻辑，
/// 不依赖数据库迁移。运行：
///   cd novel_app
///   flutter test test/unit/services/novel_agent/tool_executor_prompt_tag_test.dart
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_app/core/interfaces/repositories/i_prompt_tag_repository.dart';
import 'package:novel_app/core/interfaces/repositories/i_prompt_tag_category_repository.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/models/prompt_tag.dart';
import 'package:novel_app/models/prompt_tag_category.dart';
import 'package:novel_app/models/tag_group.dart';
import 'package:novel_app/services/novel_agent/tool_executor.dart';

// ──────────────────────────────────────────────────────────────────────
// Fake Repositories
// ──────────────────────────────────────────────────────────────────────

/// 可编程的 PromptTagRepository 假实现
///
/// 测试用例通过直接修改 [tags] 列表来模拟数据库状态。
class _FakePromptTagRepo implements IPromptTagRepository {
  _FakePromptTagRepo(this.tags);

  List<PromptTag> tags;

  @override
  Future<List<PromptTag>> getByCategory(int categoryId) async =>
      tags.where((t) => t.categoryId == categoryId).toList();

  @override
  Future<List<PromptTag>> getAll() async => List.unmodifiable(tags);

  @override
  Future<List<PromptTag>> getByIds(List<int> ids) async =>
      tags.where((t) => t.id != null && ids.contains(t.id)).toList();

  @override
  Future<List<PromptTag>> search(String keyword, {int? categoryId}) async {
    final kw = keyword.toLowerCase();
    return tags.where((t) {
      if (categoryId != null && t.categoryId != categoryId) return false;
      return t.name.toLowerCase().contains(kw) ||
          t.promptText.toLowerCase().contains(kw) ||
          t.reason.toLowerCase().contains(kw);
    }).toList();
  }

  @override
  Future<int> save(PromptTag tag) async {
    if (tag.id == null) {
      final newId =
          (tags.fold<int>(0, (m, t) => t.id != null && t.id! > m ? t.id! : m)) +
              1;
      tags = [...tags, tag.copyWith(id: newId)];
      return newId;
    }
    tags = [
      for (final t in tags)
        if (t.id == tag.id) tag else t,
    ];
    return tag.id!;
  }

  @override
  Future<void> delete(int id) async {
    tags = tags.where((t) => t.id != id).toList();
  }

  // 以下方法本测试不使用，提供空实现以满足接口契约
  @override
  Future<void> deleteByCategory(int categoryId) async {}
  @override
  Future<void> reorder(List<int> orderedIds) async {}
  @override
  Future<List<TagGroup>> getGroupedByCategory(int categoryId) async => [];
  @override
  Future<String?> getRandomPromptText(int categoryId, String name) async => null;
  @override
  Future<PromptTag?> getRandomTag(int categoryId, String name) async => null;
  @override
  Future<void> moveToCategory(int tagId, int newCategoryId) async {}
  @override
  Future<int> getNextSortOrder(int categoryId) async =>
      tags.where((t) => t.categoryId == categoryId).length;
}

class _FakePromptTagCategoryRepo implements IPromptTagCategoryRepository {
  _FakePromptTagCategoryRepo(this.categories);
  List<PromptTagCategory> categories;

  @override
  Future<List<PromptTagCategory>> getAll() async =>
      List.unmodifiable(categories);

  @override
  Future<int> save(PromptTagCategory category) async {
    if (category.id == null) {
      final newId = (categories
              .fold<int>(0, (m, c) => c.id != null && c.id! > m ? c.id! : m)) +
          1;
      categories = [...categories, category.copyWith(id: newId)];
      return newId;
    }
    categories = [
      for (final c in categories)
        if (c.id == category.id) category else c,
    ];
    return category.id!;
  }

  @override
  Future<void> delete(int id) async {
    categories = categories.where((c) => c.id != id).toList();
  }

  @override
  Future<void> reorder(List<int> orderedIds) async {}

  @override
  Future<int> count() async => categories.length;

  @override
  Future<void> initDefaultCategories() async {}
}

// ──────────────────────────────────────────────────────────────────────
// 测试数据工厂
// ──────────────────────────────────────────────────────────────────────

DateTime _fixedTime() => DateTime(2026, 7, 3, 12, 0, 0);

PromptTagCategory _cat(int id, String name) => PromptTagCategory(
      id: id,
      name: name,
      sortOrder: id,
      createdAt: _fixedTime(),
      updatedAt: _fixedTime(),
    );

PromptTag _tag({
  required int id,
  required int categoryId,
  required String name,
  String reason = '',
  required String promptText,
  int sortOrder = 0,
}) =>
    PromptTag(
      id: id,
      categoryId: categoryId,
      name: name,
      reason: reason,
      promptText: promptText,
      sortOrder: sortOrder,
      createdAt: _fixedTime(),
      updatedAt: _fixedTime(),
    );

/// 构造一组标准测试数据
(List<PromptTagCategory>, List<PromptTag>) _seedData() {
  final cats = [
    _cat(1, '风格'),
    _cat(2, '场景'),
    _cat(3, '人物'),
  ];
  final tags = [
    _tag(
      id: 10,
      categoryId: 1,
      name: '细腻描写',
      reason: '需要慢节奏、感官细节时使用',
      promptText: '请用细腻的笔触描写场景，调动视觉、听觉、触觉等多重感官。',
    ),
    _tag(
      id: 11,
      categoryId: 1,
      name: '快节奏推进',
      reason: '动作戏或情节急转时使用',
      promptText: '短句为主，动词密集，压缩环境描写。',
    ),
    _tag(
      id: 20,
      categoryId: 2,
      name: '雨夜',
      reason: '营造压抑或悬疑氛围',
      promptText: '雨声、湿漉的街灯、模糊的倒影……',
    ),
    // 同名标签（用于测试 name 命中多个的情况）
    _tag(
      id: 21,
      categoryId: 2,
      name: '雨夜',
      reason: '同一名称的另一个标签',
      promptText: '另一个雨夜提示词版本。',
    ),
    _tag(
      id: 30,
      categoryId: 3,
      name: '反派独白',
      reason: '揭示反派动机时使用',
      promptText: '让角色以第一人称倾诉内心，逐步暴露执念。',
    ),
  ];
  return (cats, tags);
}

// 用一个本地 Provider 让 ProviderContainer 暴露带 Ref 的 ToolExecutor
final _toolExecutorProvider = Provider<ToolExecutor>((ref) => ToolExecutor(ref));

// ──────────────────────────────────────────────────────────────────────
// 测试主体
// ──────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePromptTagRepo tagRepo;
  late _FakePromptTagCategoryRepo catRepo;
  late ProviderContainer container;
  late ToolExecutor executor;

  setUp(() {
    // 屏蔽 LoggerService 持久化日志时对 shared_preferences 的 plugin 调用噪音
    SharedPreferences.setMockInitialValues({});
    final (cats, tags) = _seedData();
    catRepo = _FakePromptTagCategoryRepo(cats);
    tagRepo = _FakePromptTagRepo(tags);
    container = ProviderContainer(overrides: [
      promptTagRepositoryProvider.overrideWithValue(tagRepo),
      promptTagCategoryRepositoryProvider.overrideWithValue(catRepo),
    ]);
    executor = container.read(_toolExecutorProvider);
  });

  tearDown(() => container.dispose());

  // 解析工具返回的 JSON
  Map<String, dynamic> decode(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  // =========================================================================
  // list_prompt_tags
  // =========================================================================
  group('list_prompt_tags', () {
    test('不传 categoryName → 返回全部分类，每个标签仅含 id/name/reason', () async {
      final raw = await executor.execute('list_prompt_tags', {});
      final json = decode(raw);

      expect(json['error'], isNull);
      expect(json['totalTags'], equals(5));

      final categories =
          (json['categories'] as List).cast<Map<String, dynamic>>();
      expect(categories.length, equals(3));

      // 校验每个 tag 不含 promptText 字段
      for (final cat in categories) {
        for (final tag in (cat['tags'] as List)) {
          final t = tag as Map<String, dynamic>;
          expect(t.keys, containsAll(['id', 'name', 'reason']));
          expect(t.containsKey('promptText'), isFalse,
              reason: 'list_prompt_tags 不应返回 promptText');
        }
      }

      // 抽取一个具体标签校验字段值
      final styleCat =
          categories.firstWhere((c) => c['categoryName'] == '风格');
      final firstTag =
          (styleCat['tags'] as List).first as Map<String, dynamic>;
      expect(firstTag['id'], equals(10));
      expect(firstTag['name'], equals('细腻描写'));
      expect(firstTag['reason'], equals('需要慢节奏、感官细节时使用'));
    });

    test('传 categoryName=场景 → 仅返回该分类，且包含同名的两个标签', () async {
      final raw =
          await executor.execute('list_prompt_tags', {'categoryName': '场景'});
      final json = decode(raw);

      expect(json['error'], isNull);
      final categories =
          (json['categories'] as List).cast<Map<String, dynamic>>();
      expect(categories.length, equals(1));
      expect(categories.first['categoryName'], equals('场景'));
      expect(categories.first['tagCount'], equals(2));
      expect(json['totalTags'], equals(2));
    });

    test('categoryName 大小写无关匹配', () async {
      // 中文无大小写，这里用一个英文分类名验证
      catRepo.categories = [
        _cat(4, 'Style'),
        _cat(1, '风格'),
      ];
      tagRepo.tags = [];
      final raw =
          await executor.execute('list_prompt_tags', {'categoryName': 'style'});
      final json = decode(raw);
      expect(json['error'], isNull);
      expect((json['categories'] as List).length, equals(1));
      expect(
          ((json['categories'] as List).first as Map)['categoryName'],
          equals('Style'));
    });

    test('不存在的分类 → category_not_found + 可用分类引导', () async {
      final raw = await executor
          .execute('list_prompt_tags', {'categoryName': '不存在的分类'});
      final json = decode(raw);

      expect(json['error'], equals('category_not_found'));
      expect(json['message'], contains('不存在'));
      expect(json['available_categories'], isA<List>());
      final available =
          (json['available_categories'] as List).cast<Map<String, dynamic>>();
      expect(available.map((c) => c['name']).toList(),
          containsAll(['风格', '场景', '人物']));
    });
  });

  // =========================================================================
  // get_prompt_tag
  // =========================================================================
  group('get_prompt_tag', () {
    test('按 id 查看 → 返回完整 promptText 及分类名', () async {
      final raw = await executor.execute('get_prompt_tag', {'id': 10});
      final json = decode(raw);

      expect(json['error'], isNull);
      expect(json['success'], isTrue);
      final tag = json['tag'] as Map<String, dynamic>;
      expect(tag['id'], equals(10));
      expect(tag['name'], equals('细腻描写'));
      expect(tag['categoryName'], equals('风格'));
      expect(tag['reason'], equals('需要慢节奏、感官细节时使用'));
      expect(tag['promptText'],
          equals('请用细腻的笔触描写场景，调动视觉、听觉、触觉等多重感官。'));
    });

    test('id 不存在 → tag_not_found + 引导调 list_prompt_tags', () async {
      final raw = await executor.execute('get_prompt_tag', {'id': 9999});
      final json = decode(raw);

      expect(json['error'], equals('tag_not_found'));
      expect(json['suggested_tool'], equals('list_prompt_tags'));
      expect(json['message'], contains('9999'));
    });

    test('按 name 精确查看（唯一命中）→ 返回完整 promptText', () async {
      final raw =
          await executor.execute('get_prompt_tag', {'name': '反派独白'});
      final json = decode(raw);

      expect(json['error'], isNull);
      expect(json['success'], isTrue);
      final tag = json['tag'] as Map<String, dynamic>;
      expect(tag['name'], equals('反派独白'));
      expect(tag['categoryName'], equals('人物'));
      expect(tag['promptText'], equals('让角色以第一人称倾诉内心，逐步暴露执念。'));
    });

    test('name 大小写无关精确匹配', () async {
      // 插入一个英文名标签，验证大小写无关匹配
      tagRepo.tags = [
        ...tagRepo.tags,
        _tag(
          id: 40,
          categoryId: 1,
          name: 'FastPace',
          reason: 'r',
          promptText: 'short sentences',
        ),
      ];
      final raw =
          await executor.execute('get_prompt_tag', {'name': 'fastpace'});
      final json = decode(raw);
      expect(json['error'], isNull);
      expect(json['success'], isTrue);
      expect((json['tag'] as Map)['name'], equals('FastPace'));
    });

    test('name 命中多个 → 返回列表 + 引导用 id 精确查看', () async {
      final raw = await executor.execute('get_prompt_tag', {'name': '雨夜'});
      final json = decode(raw);

      expect(json['error'], isNull);
      expect(json['success'], isTrue);
      expect(json['message'], contains('2 个'));
      expect(json['tag'], isNull); // 单数 tag 不返回
      final tags = (json['tags'] as List).cast<Map<String, dynamic>>();
      expect(tags.length, equals(2));
      // 每个都含完整 promptText，便于上层选择后用 id 再查（或直接用）
      for (final t in tags) {
        expect(t.containsKey('promptText'), isTrue);
        expect(t.containsKey('id'), isTrue);
      }
      expect(tags.map((t) => t['id']).toSet(), equals({20, 21}));
    });

    test('name 不存在但有近似 → tag_not_found + suggested_names 建议', () async {
      final raw = await executor.execute('get_prompt_tag', {'name': '雨'});
      final json = decode(raw);

      expect(json['error'], equals('tag_not_found'));
      expect(json['suggested_tool'], equals('list_prompt_tags'));
      expect(json['suggested_names'], isA<List>());
      expect((json['suggested_names'] as List), contains('雨夜'));
    });

    test('name 完全不存在且无近似 → tag_not_found 不含 suggested_names', () async {
      final raw = await executor
          .execute('get_prompt_tag', {'name': '完全不可能存在的名字xyz'});
      final json = decode(raw);

      expect(json['error'], equals('tag_not_found'));
      expect(json.containsKey('suggested_names'), isFalse);
    });

    test('既无 id 也无 name → missing_arg', () async {
      final raw = await executor.execute('get_prompt_tag', {});
      final json = decode(raw);
      expect(json['error'], equals('missing_arg'));
      expect(json['message'], contains('id 或 name'));
    });

    test('id 优先于 name（同时传时以 id 为准）', () async {
      final raw = await executor.execute('get_prompt_tag', {
        'id': 30,
        'name': '细腻描写', // 与 id=30 不一致，验证 id 胜出
      });
      final json = decode(raw);
      expect(json['error'], isNull);
      final tag = json['tag'] as Map<String, dynamic>;
      expect(tag['id'], equals(30));
      expect(tag['name'], equals('反派独白'));
    });
  });

  // =========================================================================
  // 参数校验
  // =========================================================================
  group('get_prompt_tag 参数校验', () {
    test('id 类型错误（字符串非数字）→ 返回 param_type_error', () async {
      final raw =
          await executor.execute('get_prompt_tag', {'id': 'abc'});
      final json = decode(raw);
      expect(json['error'], equals('param_type_error'));
      expect(json['param'], equals('id'));
    });
  });
}
