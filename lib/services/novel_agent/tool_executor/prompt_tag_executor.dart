/// 提示标签子执行器 — list_prompt_tags / get_prompt_tag / save_prompt_tag /
/// delete_prompt_tag
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_providers.dart';
import '../../../models/prompt_tag.dart';
import '../../logger_service.dart';
import '../tool_arg_parser.dart' show ToolArgParser;
import '../tool_executor_helpers.dart';

class PromptTagExecutor with ToolExecutorHelpers {
  PromptTagExecutor(this.ref);
  @override
  final Ref ref;

  Future<String> listPromptTags(Map<String, dynamic> args) async {
    final parser = ToolArgParser(args);
    final (categoryName, _) = parser.optionalString('categoryName');

    final categoryRepo = ref.read(promptTagCategoryRepositoryProvider);
    final tagRepo = ref.read(promptTagRepositoryProvider);

    // 获取全部分类
    final allCategories = await categoryRepo.getAll();

    // 按分类名筛选
    List categories;
    if (categoryName != null && categoryName.isNotEmpty) {
      categories = allCategories
          .where((c) => c.name.toLowerCase() == categoryName.toLowerCase())
          .toList();
      if (categories.isEmpty) {
        LoggerService.instance.d(
          '工具引导错误: category_not_found categoryName=$categoryName',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'list_prompt_tags', 'category_not_found'],
        );
        return jsonEncode({
          'error': 'category_not_found',
          'message': '分类 "$categoryName" 不存在。可用分类：${allCategories.map((c) => c.name).join("、")}',
          'available_categories': allCategories
              .map((c) => {'id': c.id, 'name': c.name})
              .toList(),
        });
      }
    } else {
      categories = allCategories;
    }

    // 按分类获取标签
    final result = <Map<String, dynamic>>[];
    for (final category in categories) {
      final tags = await tagRepo.getByCategory(category.id!);
      result.add({
        'categoryId': category.id,
        'categoryName': category.name,
        'tags': tags
            .map((t) => {
                  'id': t.id,
                  'name': t.name,
                  'reason': t.reason,
                })
            .toList(),
        'tagCount': tags.length,
      });
    }

    final totalTags =
        result.fold<int>(0, (sum, c) => sum + (c['tagCount'] as int));
    LoggerService.instance.i(
        '列出提示标签: ${categories.length} 个分类, $totalTags 个标签',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'list_prompt_tags']);
    return jsonEncode({
      'categories': result,
      'totalTags': totalTags,
    });
  }

  Future<String> getPromptTag(Map<String, dynamic> args) async {
    final parser = ToolArgParser(args);
    final (id, idErr) = parser.optionalInt('id');
    if (idErr != null) return idErr;
    final (name, _) = parser.optionalString('name');

    if (id == null && (name == null || name.isEmpty)) {
      LoggerService.instance.d(
        '工具引导错误: missing_arg (id 和 name 均未提供)',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'get_prompt_tag', 'missing_arg'],
      );
      return jsonEncode({
        'error': 'missing_arg',
        'message': '需要提供 id 或 name 来查看标签详情',
      });
    }

    final tagRepo = ref.read(promptTagRepositoryProvider);
    final categoryRepo = ref.read(promptTagCategoryRepositoryProvider);
    final categories = await categoryRepo.getAll();
    final categoryNameById = <int, String>{};
    for (final c in categories) {
      if (c.id != null) categoryNameById[c.id!] = c.name;
    }

    // id 精确查询
    if (id != null) {
      final tags = await tagRepo.getByIds([id]);
      if (tags.isEmpty) {
        LoggerService.instance.d(
          '工具引导错误: tag_not_found id=$id',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'get_prompt_tag', 'tag_not_found'],
        );
        return jsonEncode(guidanceError(
          'tag_not_found',
          '标签 ID $id 不存在。请先调用 list_prompt_tags 查看所有标签。',
          suggestedTool: 'list_prompt_tags',
        ));
      }
      final t = tags.first;
      LoggerService.instance.i('查看提示标签详情: "${t.name}" (id=$id)',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'get_prompt_tag']);
      return jsonEncode({
        'success': true,
        'tag': _tagDetail(t, categoryNameById[t.categoryId]),
      });
    }

    // name 大小写无关精确匹配
    final all = await tagRepo.getAll();
    final matched = all
        .where((t) => t.name.toLowerCase() == name!.toLowerCase())
        .toList();
    if (matched.isEmpty) {
      final fuzzy = await tagRepo.search(name!);
      final suggestedNames = fuzzy.map((t) => t.name).toSet().toList();
      LoggerService.instance.d(
        '工具引导错误: tag_not_found name=$name',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'get_prompt_tag', 'tag_not_found'],
      );
      return jsonEncode(<String, dynamic>{
        ...guidanceError(
          'tag_not_found',
          '没有名为 "$name" 的标签。',
          suggestedTool: 'list_prompt_tags',
        ),
        if (suggestedNames.isNotEmpty) 'suggested_names': suggestedNames,
      });
    }
    if (matched.length == 1) {
      final t = matched.first;
      LoggerService.instance.i('查看提示标签详情: "${t.name}" (by name)',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'get_prompt_tag']);
      return jsonEncode({
        'success': true,
        'tag': _tagDetail(t, categoryNameById[t.categoryId]),
      });
    }
    LoggerService.instance.i(
        '查看提示标签: name="$name" 命中 ${matched.length} 个',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'get_prompt_tag']);
    return jsonEncode({
      'success': true,
      'message': '找到 ${matched.length} 个名为 "$name" 的标签，请用 id 精确查看',
      'tags': matched
          .map((t) => _tagDetail(t, categoryNameById[t.categoryId]))
          .toList(),
    });
  }

  /// 构造标签详情（含完整 promptText）
  Map<String, dynamic> _tagDetail(PromptTag t, String? categoryName) => {
        'id': t.id,
        'name': t.name,
        'categoryName': categoryName,
        'reason': t.reason,
        'promptText': t.promptText,
      };

  Future<String> savePromptTag(Map<String, dynamic> args) async {
    final parser = ToolArgParser(args);
    final (categoryName, cnErr) = parser.requireString('categoryName');
    if (cnErr != null) return cnErr;
    final (name, nameErr) = parser.requireString('name');
    if (nameErr != null) return nameErr;
    final (promptText, ptErr) = parser.requireString('promptText');
    if (ptErr != null) return ptErr;
    final (reasonRaw, _) = parser.optionalString('reason');
    final reason = reasonRaw ?? '';
    final (id, idErr) = parser.optionalInt('id');
    if (idErr != null) return idErr;

    final categoryRepo = ref.read(promptTagCategoryRepositoryProvider);
    final tagRepo = ref.read(promptTagRepositoryProvider);

    // 通过分类名查找 categoryId
    final allCategories = await categoryRepo.getAll();
    final category = allCategories
        .where((c) => c.name.toLowerCase() == categoryName.toLowerCase())
        .firstOrNull;
    if (category == null || category.id == null) {
      LoggerService.instance.d(
        '工具引导错误: category_not_found categoryName=$categoryName',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'save_prompt_tag', 'category_not_found'],
      );
      return jsonEncode({
        'error': 'category_not_found',
        'message': '分类 "$categoryName" 不存在。可用分类：${allCategories.map((c) => c.name).join("、")}',
        'available_categories': allCategories
            .map((c) => {'id': c.id, 'name': c.name})
            .toList(),
      });
    }
    final categoryId = category.id!;

    if (id != null) {
      // 更新已有标签
      final existingTags = await tagRepo.getByIds([id]);
      if (existingTags.isEmpty) {
        LoggerService.instance.d(
          '工具引导错误: tag_not_found id=$id',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'save_prompt_tag', 'tag_not_found'],
        );
        return jsonEncode(guidanceError(
          'tag_not_found',
          '标签 ID $id 不存在。请先调用 list_prompt_tags 查看所有标签。',
          suggestedTool: 'list_prompt_tags',
          suggestedArgs: const <String, dynamic>{},
        ));
      }
      final existing = existingTags.first;
      final updated = existing.copyWith(
        categoryId: categoryId,
        name: name,
        reason: reason.isNotEmpty ? reason : existing.reason,
        promptText: promptText,
        updatedAt: DateTime.now(),
      );
      await tagRepo.save(updated);

      LoggerService.instance.i('更新提示标签: "$name" (id=$id)',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'save_prompt_tag']);
      return jsonEncode({
        'success': true,
        'message': '标签 "$name" 已更新',
        'tagId': id,
      });
    }

    // 创建新标签
    final sortOrder = await tagRepo.getNextSortOrder(categoryId);
    final now = DateTime.now();
    final newTag = PromptTag(
      categoryId: categoryId,
      name: name,
      reason: reason,
      promptText: promptText,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
    final newId = await tagRepo.save(newTag);

    LoggerService.instance.i(
        '创建提示标签: "$name" (id=$newId, category="${category.name}")',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'save_prompt_tag']);
    return jsonEncode({
      'success': true,
      'message': '标签 "$name" 已创建（分类：${category.name}）',
      'tagId': newId,
    });
  }

  Future<String> deletePromptTag(Map<String, dynamic> args) async {
    final parser = ToolArgParser(args);
    final (id, idErr) = parser.requireInt('id');
    if (idErr != null) return idErr;

    final tagRepo = ref.read(promptTagRepositoryProvider);

    // 确认标签存在
    final existingTags = await tagRepo.getByIds([id]);
    if (existingTags.isEmpty) {
      LoggerService.instance.d(
        '工具引导错误: tag_not_found id=$id',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'delete_prompt_tag', 'tag_not_found'],
      );
      return jsonEncode(guidanceError(
        'tag_not_found',
        '标签 ID $id 不存在。请先调用 list_prompt_tags 查看所有标签。',
        suggestedTool: 'list_prompt_tags',
      ));
    }

    final existing = existingTags.first;
    await tagRepo.delete(id);

    LoggerService.instance.i(
        '删除提示标签: "${existing.name}" (id=$id)',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'delete_prompt_tag']);
    return jsonEncode({
      'success': true,
      'message': '标签 "${existing.name}" 已删除',
    });
  }

  // 域内不依赖 ctx：list_prompt_tags/get_prompt_tag/save_prompt_tag/
  // delete_prompt_tag 都不需要当前小说上下文。
}
