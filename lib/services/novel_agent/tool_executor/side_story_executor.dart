/// 番外创作子执行器 — create_side_story / save_side_story_chapter /
/// list_side_stories（主聊 writing 场景直接创作番外）
///
/// 设计要点：
/// - currentNovel 不切换——create_side_story 建完隐藏行后工作小说仍是宿主，
///   read/search/list_chapters/list_characters 天然指宿主（查证通道零成本），
///   主聊「工具作用于当前小说」的一致性约定不被破坏
/// - 写入显式定位：save_side_story_chapter 从 ctx.sideStoryWritingTarget
///   取番外 id 构造目标上下文，复用 [ChapterWriteExecutor.saveChapter]
///   （position 范围 / 转义还原 / JSON 污染检测 / markdown 净化 / 300 字
///   下限五道闸门全部白得），绝不触碰宿主命名空间
/// - 幂等：create 按「锚点章 + 需求 description」查库复用（其次按标题）——
///   进程重启丢会话内存态后，Agent 重调 create 自动找回已建番外
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_providers.dart';
import '../../../core/providers/reading_context_providers.dart';
import '../../../core/providers/side_story_mutation_provider.dart';
import '../../../services/logger_service.dart';
import '../agent_scenario.dart';
import '../tool_arg_parser.dart' show ToolArgParser;
import '../tool_executor_helpers.dart';
import 'chapter_write_executor.dart';

class SideStoryExecutor with ToolExecutorHelpers {
  SideStoryExecutor(this.ref);
  @override
  final Ref ref;

  /// create_side_story：建番外隐藏行（不入书架）。
  ///
  /// 锚点解析优先级：当前阅读章（[readingContextProvider]，在番外章节内
  /// 阅读时 novelUrl 即父番外 URL → 「番外套番外」递归免费）→
  /// anchorChapterPosition（currentNovel 的章节序号）→ 都无则
  /// no_active_reading 引导。
  Future<String> createSideStory(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    final parser = ToolArgParser(args);
    final (title, titleErr) = parser.requireString('title');
    if (titleErr != null) return titleErr;
    final (requirement, reqErr) = parser.optionalString('requirement');
    if (reqErr != null) return reqErr;
    final (anchorPos, posErr) = parser.optionalInt('anchorChapterPosition');
    if (posErr != null) return posErr;

    // ── 锚点解析 ──
    String anchorNovelUrl;
    String anchorChapterUrl;
    String anchorNovelTitle;
    String anchorChapterTitle;
    final reading = ref.read(readingContextProvider);
    final readingUsable = reading.novelUrl != null &&
        reading.novelUrl!.isNotEmpty &&
        reading.chapterUrl != null &&
        reading.chapterUrl!.isNotEmpty;
    if (anchorPos != null) {
      // 显式指定宿主章节位置（当前工作小说的列表序号）
      final resolve = await resolveChapterUrlByPosition(ctx, anchorPos);
      if (resolve.errorJson != null) {
        return jsonEncode(resolve.errorJson);
      }
      anchorNovelUrl = resolve.novelUrl!;
      anchorChapterUrl = resolve.chapterUrl!;
      anchorNovelTitle = ctx?.currentNovelTitle ?? '当前小说';
      anchorChapterTitle = '第 $anchorPos 章';
      // 取真实章节标题
      final chapters = await ref
          .read(chapterRepositoryProvider)
          .getCachedNovelChapters(anchorNovelUrl);
      if (anchorPos >= 1 && anchorPos <= chapters.length) {
        anchorChapterTitle = chapters[anchorPos - 1].title;
      }
    } else if (readingUsable) {
      anchorNovelUrl = reading.novelUrl!;
      anchorChapterUrl = reading.chapterUrl!;
      anchorNovelTitle = reading.novelTitle ?? '当前小说';
      anchorChapterTitle = reading.chapterTitle ?? '未知章节';
    } else {
      LoggerService.instance.w(
        '工具引导错误: create_side_story no_active_reading',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'create_side_story', 'no_active_reading'],
      );
      return jsonEncode({
        'error': 'no_active_reading',
        'message': '无法确定番外的挂载点。请用户先在阅读页打开想挂番外的章节'
            '（锚点 = 当前正在阅读的章），或告知章节位置后由你传 '
            'anchorChapterPosition（当前小说的章节序号，来自 list_chapters）。',
      });
    }

    // ── 幂等查库：同锚点 + 同需求（其次同标题）→ 复用已建番外 ──
    final repo = ref.read(sideStoryRepositoryProvider);
    final existing =
        await repo.getSideStories(
      anchorNovelUrl: anchorNovelUrl,
      anchorChapterUrl: anchorChapterUrl,
    );
    for (final s in existing) {
      final descMatch = requirement != null &&
          requirement.isNotEmpty &&
          s.novel.description == requirement;
      final titleMatch = requirement == null || requirement.isEmpty
          ? s.novel.title == title
          : false;
      if (descMatch || titleMatch) {
        LoggerService.instance.i(
          'create_side_story 幂等复用: "${s.novel.title}" (id=${s.novel.id})',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'create_side_story', 'idempotent_reuse'],
        );
        return jsonEncode({
          'success': true,
          'sideStoryId': s.novel.id,
          'sideStoryUrl': s.novel.url,
          'sideStoryTitle': s.novel.title,
          'anchorChapterTitle': anchorChapterTitle,
          'sideStoryChapterCount': s.chapterCount,
          'message': '本需求已创建过番外《${s.novel.title}》'
              '（${s.chapterCount} 章），已定位为写入目标，继续用 '
              'save_side_story_chapter 保存即可，不要重复创建。',
        });
      }
    }

    final novel = await ref
        .read(sideStoryMutationProvider.notifier)
        .createSideStory(
          title: title,
          anchorNovelUrl: anchorNovelUrl,
          anchorChapterUrl: anchorChapterUrl,
          description:
              (requirement != null && requirement.isNotEmpty) ? requirement : null,
        );

    LoggerService.instance.i(
      'create_side_story: "${novel.title}" (id=${novel.id}, '
      'anchor=$anchorChapterUrl)',
      category: LogCategory.ai,
      tags: ['agent', 'tool', 'create_side_story', 'created'],
    );
    return jsonEncode({
      'success': true,
      'sideStoryId': novel.id,
      'sideStoryUrl': novel.url,
      'sideStoryTitle': novel.title,
      'anchorChapterTitle': anchorChapterTitle,
      'sideStoryChapterCount': 0,
      'message': '番外《${novel.title}》已建立（挂载于「$anchorChapterTitle」）。'
          '逐章创作：在回复中直接写出该章完整正文（1500~3000 字），'
          '然后调用 save_side_story_chapter 保存（一次只写一章、保存一章）。',
      'anchorNovelTitle': anchorNovelTitle,
    });
  }

  /// save_side_story_chapter：把回复中写好的正文保存进番外。
  ///
  /// 显式写番外命名空间（ctx.sideStoryWritingTarget 定位），currentNovel
  /// （宿主）不受影响；落库校验复用 [ChapterWriteExecutor.saveChapter]。
  Future<String> saveSideStoryChapter(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    // 参数前置校验（正式解析与落库校验由 saveChapter 完成——这里显式读取
    // 以保持 schema ↔ 执行端双向对齐，并让缺参错误在目标校验后立刻返回）
    final parser = ToolArgParser(args);
    final (position, posErr) = parser.requireInt('position');
    if (posErr != null) return posErr;
    final (content, contentErr) = parser.requireString('content');
    if (contentErr != null) return contentErr;
    parser.optionalString('title');

    final target = ctx?.sideStoryWritingTarget;
    if (target == null) {
      LoggerService.instance.w(
        '工具引导错误: save_side_story_chapter no_side_story',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'save_side_story_chapter', 'no_side_story'],
      );
      return jsonEncode({
        'error': 'no_side_story',
        'message': '本会话尚未定位番外写入目标。请先调用 '
            'create_side_story(title) 建立番外（重复调用同一需求会自动找回'
            '已建番外，不会重复创建）。',
        'suggested_tool': 'create_side_story',
      });
    }

    final sideCtx = AgentScenarioContext(
      scenarioId: ctx?.scenarioId ?? ScenarioIds.writing,
      currentNovelId: target.novelId,
      currentNovelTitle: target.title,
    );
    final result =
        await ChapterWriteExecutor(ref).saveChapter(args, sideCtx);

    // 成功结果补充番外语境元信息（供跳转卡与 Agent 自纠下一章 position）
    try {
      final json = jsonDecode(result) as Map<String, dynamic>;
      if (json['success'] == true) {
        final chapters = await ref
            .read(chapterRepositoryProvider)
            .getCachedNovelChapters(target.novelUrl);
        json['sideStoryTitle'] = target.title;
        json['sideStoryChapterCount'] = chapters.length;
        json['message'] =
            '番外《${target.title}》已保存第 ${json['position']} 章'
            '（当前共 ${chapters.length} 章）。';
        LoggerService.instance.i(
          '番外章节保存: sideStory="${target.title}" position=${json['position']}',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'save_side_story_chapter'],
        );
        return jsonEncode(json);
      }
    } catch (_) {
      // 非 JSON（理论不可能）或解析失败 → 原样返回
    }
    return result;
  }

  /// list_side_stories：当前工作小说的全部番外（只读）
  Future<String> listSideStories(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    final novelResolve = await resolveCurrentNovelUrl(ctx);
    if (novelResolve.errorJson != null) {
      return jsonEncode(novelResolve.errorJson);
    }
    final summaries = await ref
        .read(sideStoryRepositoryProvider)
        .getSideStories(anchorNovelUrl: novelResolve.url!);
    final list = summaries
        .map((s) => {
              'sideStoryId': s.novel.id,
              'title': s.novel.title,
              'chapterCount': s.chapterCount,
              'totalChars': s.totalChars,
              'anchorChapterTitle': s.anchorChapterTitle ?? '原章节已移除',
              'description': s.novel.description,
            })
        .toList();
    return jsonEncode({
      'count': list.length,
      'sideStories': list,
      'note': '以上是当前小说的全部番外。要继续为已有番外写章，先 '
          'create_side_story（同锚点同需求会幂等找回）。',
    });
  }
}
