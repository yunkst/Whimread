/// 小说导航子执行器 — list_novels / select_novel / create_novel / set_novel_cover
///
/// 工具依赖关系：
/// - list_novels / select_novel / create_novel 不依赖当前小说上下文
///   （list 无参可调，select_novel 由 novelId 定位，create_novel 是创建并自动切换）。
/// - set_novel_cover 依赖 AgentScenarioContext.currentNovelId，必须在
///   select_novel 之后调用。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/bookshelf_mutation_provider.dart';
import '../../../core/providers/database_providers.dart';
import '../../../models/novel.dart';
import '../../logger_service.dart';
import '../agent_scenario.dart';
import '../tool_arg_parser.dart' show ToolArgParser;
import '../tool_executor_helpers.dart';

class NovelNavigationExecutor with ToolExecutorHelpers {
  NovelNavigationExecutor(this.ref);
  @override
  final Ref ref;

  Future<String> listNovels(Map<String, dynamic> args) async {
    final repo = ref.read(novelRepositoryProvider);
    final novels = await repo.getNovels();
    final list = novels.map((n) => {
          'id': n.id,
          'title': n.title,
          'author': n.author,
          if (n.description != null && n.description!.isNotEmpty)
            'description': n.description!.length > 200
                ? '${n.description!.substring(0, 200)}...'
                : n.description,
        }).toList();
    LoggerService.instance.i('列出小说: ${list.length} 本',
        category: LogCategory.ai, tags: ['agent', 'tool', 'list_novels']);
    return jsonEncode({'novels': list, 'count': list.length});
  }

  Future<String> selectNovel(Map<String, dynamic> args) async {
    final parser = ToolArgParser(args);
    final (novelId, novelIdErr) = parser.requireInt('novelId');
    if (novelIdErr != null) return novelIdErr;
    final repo = ref.read(novelRepositoryProvider);
    final novel = await repo.getNovelById(novelId);
    if (novel == null) {
      LoggerService.instance.w('select_novel: 小说不存在 id=$novelId',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'select_novel', 'not_found']);
      return jsonEncode(guidanceError(
        'novel_not_found',
        '小说ID $novelId 不存在。请先调用 list_novels。',
        suggestedTool: 'list_novels',
        suggestedArgs: const <String, dynamic>{},
      ));
    }
    LoggerService.instance.i('select_novel: id=$novelId, title="${novel.title}"',
        category: LogCategory.ai, tags: ['agent', 'tool', 'select_novel']);
    return jsonEncode({
      'success': true,
      'novelId': novel.id,
      'title': novel.title,
      'message': '已切换到 "${novel.title}"。后续操作将作用于该小说。',
    });
  }

  Future<String> createNovel(Map<String, dynamic> args) async {
    final parser = ToolArgParser(args);
    final (title, titleErr) = parser.requireString('title');
    if (titleErr != null) return titleErr;
    final (description, _) = parser.nullableString('description');

    final novel = Novel(
      title: title,
      author: '原创',
      url: 'custom://custom_novel_${DateTime.now().millisecondsSinceEpoch}',
      coverUrl: null,
      description: description,
      backgroundSetting: null,
    );
    // 走 Notifier 收口：写库 + invalidate(bookshelfNovelsProvider)，
    // 避免直接调 Repository 写完忘刷新书架 UI。
    final id = await ref.read(bookshelfMutationProvider.notifier).addNovel(novel);

    LoggerService.instance.i('create_novel: "$title" (id=$id)',
        category: LogCategory.ai, tags: ['agent', 'tool', 'create_novel']);
    return jsonEncode({
      'success': true,
      'novelId': id,
      'title': title,
      'message': '小说 "$title" 已创建并自动切换为当前工作小说。',
    });
  }

  /// 设置当前小说封面（set_novel_cover 工具）
  ///
  /// 从场景上下文取 currentNovelId，写 bookshelf.coverMediaId。
  /// mediaId 为 null 表示清空封面。与 update_background_setting 同构：
  /// 先 resolveCurrentNovelUrl 校验小说存在，再用 currentNovelId 写库。
  Future<String> setNovelCover(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    final parser = ToolArgParser(args);
    final (mediaId, mediaIdErr) = parser.nullableString('mediaId');
    if (mediaIdErr != null) return mediaIdErr;

    final novelResolve = await resolveCurrentNovelUrl(ctx);
    if (novelResolve.errorJson != null) {
      return jsonEncode(novelResolve.errorJson);
    }
    final currentNovelId = ctx?.currentNovelId;
    if (currentNovelId == null) {
      return jsonEncode(guidanceError(
        'no_current_novel',
        '尚未选择当前小说。请先调用 list_novels 再用 select_novel 选定目标。',
        suggestedTool: 'list_novels',
      ));
    }

    final repo = ref.read(novelRepositoryProvider);
    final affected = await repo.updateCoverMediaIdById(currentNovelId, mediaId);
    if (affected == 0) {
      return jsonEncode(guidanceError(
        'novel_not_found',
        '当前小说不存在。',
        suggestedTool: 'list_novels',
      ));
    }

    LoggerService.instance.i('设置封面: novelId=$currentNovelId, mediaId=$mediaId',
        category: LogCategory.ai, tags: ['agent', 'tool', 'set_novel_cover']);
    return jsonEncode({
      'success': true,
      'novelId': currentNovelId,
      'coverMediaId': mediaId,
      'cleared': mediaId == null,
    });
  }
}
