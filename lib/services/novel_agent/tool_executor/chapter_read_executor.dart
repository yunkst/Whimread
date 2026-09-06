/// 章节读取子执行器 — read_chapter_content / list_chapters / search_in_chapters
///
/// read_chapter_content 是特例：返回纯文本（不是 JSON），其他两个返回 JSON。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_providers.dart';
import '../../../models/search_result.dart';
import '../../logger_service.dart';
import '../tool_arg_parser.dart' show ToolArgParser;
import '../agent_scenario.dart';
import '../tool_executor_helpers.dart';

/// search_in_chapters 阈值常量（长小说高频词场景下的 safety net）
///
/// 规模控制以 agent 主动传 positionFrom/positionTo 为主（见 _searchInChapters 描述），
/// 这些 cap 是防 agent 传超大范围导致结果爆炸的兜底。
const int _kSearchContextRadius = 80;
const int _kSearchSnippetsPerChapter = 3;
const int _kSearchMaxSnippetsTotal = 30;
const int _kSearchMaxChapters = 50;

class ChapterReadExecutor with ToolExecutorHelpers {
  ChapterReadExecutor(this.ref);
  @override
  final Ref ref;

  Future<String> readChapterContent(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    final parser = ToolArgParser(args);
    final (position, posErr) = parser.requireInt('position');
    if (posErr != null) return posErr;
    final resolveResult = await resolveChapterUrlByPosition(ctx, position);
    if (resolveResult.errorJson != null) {
      return jsonEncode(resolveResult.errorJson);
    }
    final chapterUrl = resolveResult.chapterUrl!;

    final repo = ref.read(chapterRepositoryProvider);
    final content = await repo.getCachedChapter(chapterUrl);
    if (content == null || content.isEmpty) {
      LoggerService.instance.w('章节未缓存: position=$position',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'read_chapter_content', 'not_cached']);
      return jsonEncode({
        'error': 'not_cached',
        'message':
            '位置 $position 的章节存在但内容尚未缓存，无法读取。',
        'suggested_action': '请告知用户该章节需要先加载/缓存。',
      });
    }

    LoggerService.instance.i('读取章节成功: position=$position (${content.length} chars)',
        category: LogCategory.ai, tags: ['agent', 'tool', 'read_chapter_content']);
    return content;
  }

  Future<String> listChapters(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    final novelResolve = await resolveCurrentNovelUrl(ctx);
    if (novelResolve.errorJson != null) {
      return jsonEncode(novelResolve.errorJson);
    }
    final novelUrl = novelResolve.url!;

    final repo = ref.read(chapterRepositoryProvider);
    final chapters = await repo.getCachedNovelChapters(novelUrl);
    final list = <Map<String, dynamic>>[];
    for (var i = 0; i < chapters.length; i++) {
      final c = chapters[i];
      list.add({
        'position': i + 1,
        'title': c.title,
        'chapterIndex': c.chapterIndex,
        'isCached': c.isCached,
        'isUserInserted': c.isUserInserted,
      });
    }

    final novelContext = buildCurrentNovelContext(ctx);
    LoggerService.instance.i(
        '列出章节: ${list.length} 章 (currentNovelId=${ctx?.currentNovelId})',
        category: LogCategory.ai, tags: ['agent', 'tool', 'list_chapters']);
    return jsonEncode({
      'novel': novelContext,
      'chapters': list,
      'count': list.length,
    });
  }

  Future<String> searchInChapters(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    final parser = ToolArgParser(args);
    final (keyword, kwErr) = parser.requireString('keyword');
    if (kwErr != null) return kwErr;
    final (positionFrom, fromErr) = parser.optionalInt('positionFrom');
    if (fromErr != null) return fromErr;
    final (positionTo, toErr) = parser.optionalInt('positionTo');
    if (toErr != null) return toErr;
    if (positionFrom != null && positionTo != null && positionFrom > positionTo) {
      return jsonEncode({
        'error': 'invalid_range',
        'message':
            'positionFrom ($positionFrom) 不能大于 positionTo ($positionTo)。',
        'suggested_action': '请调整范围后重试，建议每次查询 20-50 章。',
      });
    }

    final novelResolve = await resolveCurrentNovelUrl(ctx);
    if (novelResolve.errorJson != null) {
      return jsonEncode(novelResolve.errorJson);
    }
    final novelUrl = novelResolve.url!;

    final repo = ref.read(chapterRepositoryProvider);
    final allResults = await repo.searchInCachedContent(
      keyword,
      novelUrl: novelUrl,
    );
    final chapters = await repo.getCachedNovelChapters(novelUrl);
    final urlToPosition = <String, int>{
      for (var i = 0; i < chapters.length; i++) chapters[i].url: i + 1,
    };

    // 1) 按 position 范围过滤（排除未在 list_chapters 顺序里出现的异常 url）
    final rangedResults = allResults.where((r) {
      final pos = urlToPosition[r.chapterUrl];
      if (pos == null) return false;
      if (positionFrom != null && pos < positionFrom) return false;
      if (positionTo != null && pos > positionTo) return false;
      return true;
    }).toList();

    // 2) 真实统计（cap 前）
    final totalChaptersHit = rangedResults.length;
    final totalMatches = rangedResults.fold<int>(0, (s, r) => s + r.matchCount);

    // 3) 章节兜底 cap：取前 N 章
    final truncatedChapters =
        rangedResults.length > _kSearchMaxChapters;
    final cappedResults = truncatedChapters
        ? rangedResults.sublist(0, _kSearchMaxChapters)
        : rangedResults;

    // 4) 构造结果 + 邻近合并 + cap 片段
    final list = <Map<String, dynamic>>[];
    int snippetsBudget = _kSearchMaxSnippetsTotal;
    bool truncated = false;
    for (final r in cappedResults) {
      final pos = urlToPosition[r.chapterUrl]!;
      final windows = _mergeAdjacentMatches(
        r.content,
        r.matchPositions,
        _kSearchContextRadius,
      );
      final windowBudget = windows.length > _kSearchSnippetsPerChapter;
      if (windowBudget) truncated = true;

      final take = windowBudget
          ? _kSearchSnippetsPerChapter
          : windows.length;
      final takeSnippets = snippetsBudget > 0 ? take : 0;
      final actualTake = takeSnippets < take ? takeSnippets : take;

      final snippets = <String>[];
      for (var i = 0; i < actualTake; i++) {
        snippets.add(
          _sliceSnippet(r.content, windows[i][0], windows[i][1]),
        );
      }
      snippetsBudget -= snippets.length;
      if (snippetsBudget < 0) snippetsBudget = 0;

      list.add({
        'position': pos,
        'chapterTitle': r.chapterTitle,
        'matchCount': r.matchCount,
        'matchedText': r.matchPositions.isNotEmpty
            ? r.content.substring(
                r.matchPositions.first.start,
                r.matchPositions.first.end,
              )
            : '',
        'snippets': snippets,
      });
    }

    final novelContext = buildCurrentNovelContext(ctx);
    LoggerService.instance.i(
        '章节搜索: keyword="$keyword", range=[$positionFrom, $positionTo], '
        'totalChaptersHit=$totalChaptersHit, totalMatches=$totalMatches, '
        'truncated=$truncated, truncatedChapters=$truncatedChapters',
        category: LogCategory.ai, tags: ['agent', 'tool', 'search_in_chapters']);
    return jsonEncode({
      'novel': novelContext,
      'keyword': keyword,
      'positionFrom': positionFrom,
      'positionTo': positionTo,
      'totalChaptersHit': totalChaptersHit,
      'totalMatches': totalMatches,
      'truncatedChapters': truncatedChapters,
      'truncated': truncated,
      'count': list.length,
      'results': list,
    });
  }

  /// 邻近合并：把同一段话内相邻的多个命中点合并成一个 [start, end] 窗口
  ///
  /// matchPositions 按 start 升序。新窗口起点 ≤ 上一窗口终点即视为相邻/重叠，合并。
  /// 返回 List&lt;List&lt;int&gt;&gt;，每项 [start, end] 字符区间（含）。
  static List<List<int>> _mergeAdjacentMatches(
    String content,
    List<MatchPosition> matchPositions,
    int radius,
  ) {
    if (matchPositions.isEmpty) return const [];
    final maxLen = content.length;
    final windows = <List<int>>[];
    for (final mp in matchPositions) {
      final ws = mp.start - radius < 0 ? 0 : mp.start - radius;
      final we = mp.end + radius > maxLen ? maxLen : mp.end + radius;
      if (windows.isNotEmpty && ws <= windows.last[1]) {
        windows.last[1] = we;
      } else {
        windows.add([ws, we]);
      }
    }
    return windows;
  }

  /// 截取片段，边界外加 '…' 提示上下文被裁剪
  static String _sliceSnippet(String content, int start, int end) {
    final hasLeft = start > 0;
    final hasRight = end < content.length;
    final body = content.substring(start, end);
    return '${hasLeft ? '…' : ''}$body${hasRight ? '…' : ''}';
  }
}
