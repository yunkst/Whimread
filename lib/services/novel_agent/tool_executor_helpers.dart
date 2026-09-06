/// ToolExecutor 共享 helper mixin
///
/// 把所有子执行器共用的解析/错误/上下文 helper 提到 mixin 里，避免每个子执行器
/// 重复实现。子执行器通过 `class XxxExecutor with ToolExecutorHelpers` 注入，
/// 调用时与原来 ToolExecutor 上的私有方法同名（无下划线变体），保证调用点一致。
///
/// ★ 此文件不引用任何具体子执行器，避免循环依赖。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_providers.dart';
import '../logger_service.dart';
import 'agent_scenario.dart';

/// ID/位置解析结果（仅 novel 维度的解析）
class IdResolveResult {
  final String? url;
  final Map<String, dynamic>? errorJson;
  const IdResolveResult.success(this.url) : errorJson = null;
  const IdResolveResult.failure(this.errorJson) : url = null;
}

/// 章节 + 所属小说 URL 的解析结果
///
/// 由 [_resolveChapterUrlByPosition] 返回，成功时 novelUrl / chapterUrl 必非空。
/// 把两段解析合并到一次调用中，避免下游重复查 DB，也消除 `url!` 链式强解包。
class ChapterResolveResult {
  final String? novelUrl;
  final String? chapterUrl;
  final Map<String, dynamic>? errorJson;
  const ChapterResolveResult.success({
    required this.novelUrl,
    required this.chapterUrl,
  }) : errorJson = null;
  const ChapterResolveResult.failure(this.errorJson)
      : novelUrl = null,
        chapterUrl = null;
}

/// ToolExecutor 与所有子执行器共用的 helper 集合
///
/// `ref` 由使用方（facade 或子执行器）通过构造函数注入；helper 不直接构造
/// 任何 repository，所有 IO 都走 `ref.read(...RepositoryProvider)`。
mixin ToolExecutorHelpers {
  /// Riverpod 引用，用于读 repository / service
  Ref get ref;

  /// 构造统一的引导错误 JSON Map。
  ///
  /// 由所有需要「引导 AI 自助修复」的失败分支调用：返回固定的
  /// `{error, message, suggested_tool?, suggested_args?}` 结构，
  /// 避免散落 12+ 处手写字面量导致键名/大小写漂移。
  ///
  /// [suggestedArgs] 为 null 时不写 suggested_args 键（向后兼容早期只带
  /// suggested_tool 的错误，例如 outline_not_found）。
  Map<String, dynamic> guidanceError(
    String code,
    String message, {
    String? suggestedTool,
    Map<String, dynamic>? suggestedArgs,
  }) {
    return <String, dynamic>{
      'error': code,
      'message': message,
      if (suggestedTool != null) 'suggested_tool': suggestedTool,
      if (suggestedArgs != null) 'suggested_args': suggestedArgs,
    };
  }

  /// 解析当前小说 URL（从场景上下文中读取 currentNovelId）。
  ///
  /// 未设置时返回 no_current_novel 错误，引导 AI 调用 list_novels + select_novel。
  Future<IdResolveResult> resolveCurrentNovelUrl(
    AgentScenarioContext? ctx,
  ) async {
    final currentNovelId = ctx?.currentNovelId;
    if (currentNovelId == null) {
      LoggerService.instance.d(
        '工具引导错误: no_current_novel',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'no_current_novel'],
      );
      return IdResolveResult.failure(guidanceError(
        'no_current_novel',
        '尚未选择当前小说。请先调用 list_novels 查看书架，然后用 select_novel 选定目标。',
        suggestedTool: 'list_novels',
        suggestedArgs: const <String, dynamic>{},
      ));
    }
    return resolveNovelUrl(currentNovelId);
  }

  /// novelId → novelUrl 解析，失败时返回错误 JSON
  Future<IdResolveResult> resolveNovelUrl(int novelId) async {
    final repo = ref.read(novelRepositoryProvider);
    final novelUrl = await repo.getNovelUrlById(novelId);
    if (novelUrl == null) {
      LoggerService.instance.d(
        '工具引导错误: novel_not_found novelId=$novelId',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'novel_not_found'],
      );
      return IdResolveResult.failure(guidanceError(
        'novel_not_found',
        '小说ID $novelId 不存在。请先调用 list_novels 查看书架中的所有小说及其ID。',
        suggestedTool: 'list_novels',
        suggestedArgs: const <String, dynamic>{},
      ));
    }
    return IdResolveResult.success(novelUrl);
  }

  /// 构造小说上下文对象 {id, title} 用于返回结果（同步，无 IO）
  Map<String, dynamic>? buildCurrentNovelContext(AgentScenarioContext? ctx) {
    final currentNovelId = ctx?.currentNovelId;
    if (currentNovelId == null) return null;
    return {
      'id': currentNovelId,
      'title': ctx?.currentNovelTitle,
    };
  }

  /// position → (novelUrl, chapterUrl) 联合解析
  ///
  /// 一次调用同时返回 novelUrl + chapterUrl，避免下游二次调用
  /// resolveCurrentNovelUrl 重复查 DB，也消除 `url!` 链式强解包。
  /// position 是 1-based 的顺序号，依赖 list_chapters 返回的顺序
  /// （按 chapterIndex ASC 排序）。
  Future<ChapterResolveResult> resolveChapterUrlByPosition(
    AgentScenarioContext? ctx,
    int position,
  ) async {
    final novelResolve = await resolveCurrentNovelUrl(ctx);
    if (novelResolve.errorJson != null) {
      return ChapterResolveResult.failure(novelResolve.errorJson);
    }
    final novelUrl = novelResolve.url!;

    final repo = ref.read(chapterRepositoryProvider);
    final chapters = await repo.getCachedNovelChapters(novelUrl);
    if (position < 1 || position > chapters.length) {
      LoggerService.instance.d(
        '工具引导错误: chapter_position_out_of_range position=$position total=${chapters.length}',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'chapter_position_out_of_range'],
      );
      return ChapterResolveResult.failure(guidanceError(
        'chapter_position_out_of_range',
        chapters.isEmpty
            ? '当前小说没有任何章节。请先调用 list_chapters 确认。'
            : '章节位置 $position 超出范围（当前小说共 ${chapters.length} 章）。'
                '请先调用 list_chapters 查看有效位置。',
        suggestedTool: 'list_chapters',
        suggestedArgs: const <String, dynamic>{},
      ));
    }
    return ChapterResolveResult.success(
      novelUrl: novelUrl,
      chapterUrl: chapters[position - 1].url,
    );
  }
}
