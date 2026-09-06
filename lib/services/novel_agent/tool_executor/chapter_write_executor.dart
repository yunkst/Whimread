/// 章节写入子执行器 — create_chapter / update_chapter_content /
/// rewrite_chapter / delete_chapter
///
/// 唯一持有 LLM 调用链的子执行器（_callLlm + _loadWriterPrompt +
/// _buildContextParts + _rewriteChapter + _generateChapter）。这些 helper
/// 跟着「章节写入」走，不跨域，所以留在本文件内私有。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/chapter_mutation_provider.dart';
import '../../../core/providers/database_providers.dart';
import '../../../models/character.dart';
import '../../../models/prompt_tag.dart';
import '../../../core/providers/services/ai_service_providers.dart';
import '../../../utils/content_sanitizer.dart';
import '../../dsl_engine/llm_provider.dart';
import '../../logger_service.dart';
import '../../llm_config_service.dart';
import '../../preferences_service.dart';
import '../agent_scenario.dart';
import '../outline_replacer.dart';
import '../tool_arg_parser.dart' show ToolArgParser;
import '../tool_executor_helpers.dart';

/// LLM 重写结果（私有值类，保留原 _RewriteResult 语义）
class _RewriteResult {
  final String? content;
  final Map<String, dynamic>? errorJson;
  const _RewriteResult.success(this.content) : errorJson = null;
  const _RewriteResult.failure(this.errorJson) : content = null;
}

class ChapterWriteExecutor with ToolExecutorHelpers {
  ChapterWriteExecutor(this.ref);
  @override
  final Ref ref;

  Future<String> createChapter(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx, {
    void Function(int generatedChars)? onProgress,
  }) async {
    final parser = ToolArgParser(args);
    final (position, posErr) = parser.requireInt('position');
    if (posErr != null) return posErr;
    final (instruction, instErr) = parser.requireString('instruction');
    if (instErr != null) return instErr;
    final (title, _) = parser.optionalString('title');
    final (characterNames, charNamesErr) = parser.optionalStringList('characterNames');
    if (charNamesErr != null) return charNamesErr;
    final (tagNames, tagNamesErr) = parser.optionalStringList('tagNames');
    if (tagNamesErr != null) return tagNamesErr;
    final charNames = characterNames ?? const <String>[];
    final tags = tagNames ?? const <String>[];

    final novelResolve = await resolveCurrentNovelUrl(ctx);
    if (novelResolve.errorJson != null) {
      return jsonEncode(novelResolve.errorJson);
    }
    final novelUrl = novelResolve.url!;

    // 校验 position 范围：1 ≤ position ≤ 章节总数 + 1
    final chapterRepo = ref.read(chapterRepositoryProvider);
    final chapters = await chapterRepo.getCachedNovelChapters(novelUrl);
    final totalCount = chapters.length;
    if (position < 1 || position > totalCount + 1) {
      LoggerService.instance.d(
        '工具引导错误: create_chapter_position_out_of_range position=$position total=$totalCount',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'create_chapter', 'position_out_of_range'],
      );
      return jsonEncode(guidanceError(
        'position_out_of_range',
        totalCount == 0
            ? '当前小说没有任何章节，position 只能为 1。'
            : '插入位置 $position 超出范围（当前共 $totalCount 章，有效范围 1~${totalCount + 1}）。'
                '请先调用 list_chapters 查看有效位置。',
        suggestedTool: 'list_chapters',
        suggestedArgs: const <String, dynamic>{},
      ));
    }

    // 确定章节标题
    final chapterTitle = (title != null && title.trim().isNotEmpty)
        ? title.trim()
        : '第 $position 章';

    // 取前一章正文作为衔接上下文（position=1 无前一章；前一章未缓存则跳过）
    String? previousChapterContext;
    if (position >= 2) {
      final prevChapter = chapters[position - 2]; // 前一章（列表 0-based）
      final prevContent = await chapterRepo.getCachedChapter(prevChapter.url);
      if (prevContent != null && prevContent.trim().isNotEmpty) {
        previousChapterContext = '《${prevChapter.title}》\n\n$prevContent';
      }
    }

    // 调用 LLM 生成正文
    final generateResult = await _generateChapter(
      novelUrl: novelUrl,
      chapterTitle: chapterTitle,
      instruction: instruction,
      characterNames: charNames,
      tagNames: tags,
      previousChapterContext: previousChapterContext,
      scenarioId: ctx?.scenarioId ?? ScenarioIds.writing,
      onProgress: onProgress,
    );
    if (generateResult.errorJson != null) {
      return jsonEncode(generateResult.errorJson);
    }
    final newContent = ContentSanitizer.sanitize(generateResult.content!);

    // 插入章节：走 ChapterMutationNotifier 收口（单事务 shift+insert + bump signal
    // 触发章节列表软刷新）。insertIndex = position - 1（0-based）。
    final insertIndex = position - 1; // 0-based
    try {
      await ref
          .read(chapterMutationProvider.notifier)
          .createChapter(
            novelUrl: novelUrl,
            title: chapterTitle,
            content: newContent,
            insertIndex: insertIndex,
          );
    } catch (e, stack) {
      LoggerService.instance.e('创建章节入库失败: $e',
          stackTrace: stack.toString(),
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'create_chapter', 'db_error']);
      return jsonEncode({
        'error': 'db_error',
        'message': '章节内容已生成但入库失败：$e',
      });
    }

    // 重新获取章节列表以拿到新章节的 URL
    final updatedChapters = await chapterRepo.getCachedNovelChapters(novelUrl);
    final newChapter = updatedChapters.firstWhere(
      (c) => c.title == chapterTitle && c.chapterIndex == insertIndex,
      orElse: () => updatedChapters[position - 1],
    );

    LoggerService.instance.i(
        'AI 创建章节: position=$position, title="$chapterTitle", ${newContent.length} chars',
        category: LogCategory.ai, tags: ['agent', 'tool', 'create_chapter']);
    return jsonEncode({
      'success': true,
      'message': '章节「$chapterTitle」已创建（${newContent.length} 字）。',
      'chapterTitle': chapterTitle,
      'position': position,
      'novelUrl': novelUrl,
      'chapterUrl': newChapter.url,
      'charCount': newContent.length,
    });
  }

  Future<String> updateChapterContent(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx, {
    void Function(int generatedChars)? onProgress,
  }) async {
    final parser = ToolArgParser(args);
    final (position, posErr) = parser.requireInt('position');
    if (posErr != null) return posErr;
    final (oldString, oldErr) = parser.requireString('oldString');
    if (oldErr != null) return oldErr;
    final (newString, newErr) = parser.requireString('newString');
    if (newErr != null) return newErr;
    final (replaceAll, allErr) = parser.optionalBool('replaceAll');
    if (allErr != null) return allErr;

    if (oldString == newString) {
      return jsonEncode({
        'error': 'invalid_param',
        'message': 'oldString 与 newString 不能相同',
      });
    }

    final resolveResult = await resolveChapterUrlByPosition(ctx, position);
    if (resolveResult.errorJson != null) {
      return jsonEncode(resolveResult.errorJson);
    }
    final chapterUrl = resolveResult.chapterUrl!;
    final novelUrl = resolveResult.novelUrl!;

    final chapterRepo = ref.read(chapterRepositoryProvider);
    final originalContent = await chapterRepo.getCachedChapter(chapterUrl);
    if (originalContent == null || originalContent.isEmpty) {
      return jsonEncode({
        'error': 'not_cached',
        'message': '位置 $position 的章节存在但内容尚未缓存，无法编辑。请告知用户先加载/缓存该章节。',
      });
    }

    // 复用 outline_replacer 的 9 重容错匹配（纯函数，与 outline 无耦合，
    // 同样适用于章节正文这种任意长文本的精确局部替换）。
    String newContent;
    try {
      newContent = replaceOutlineSnippet(
        content: originalContent,
        oldString: oldString,
        newString: newString,
        replaceAll: replaceAll ?? false,
      );
    } on OutlineEditException catch (e) {
      final errorCode =
          e.reason == 'ambiguous' ? 'ambiguous_match' : 'not_found';
      LoggerService.instance.d(
        '编辑章节失败: $errorCode, position=$position',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'update_chapter_content', errorCode],
      );
      return jsonEncode({'error': errorCode, 'message': e.message});
    }

    final affected = await ref
        .read(chapterMutationProvider.notifier)
        .updateChapterContent(
          chapterUrl,
          newContent,
          source: 'ai_edit',
          novelUrl: novelUrl,
        );
    if (affected == 0) {
      LoggerService.instance.d(
        '工具引导错误: chapter_not_found position=$position',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'update_chapter_content', 'chapter_not_found'],
      );
      return jsonEncode(guidanceError(
        'chapter_not_found',
        '章节位置 $position 的数据库记录不存在或内容表无对应行。',
        suggestedTool: 'list_chapters',
        suggestedArgs: const <String, dynamic>{},
      ));
    }

    LoggerService.instance.i(
        '编辑章节: position=$position, ${originalContent.length}→${newContent.length} chars',
        category: LogCategory.ai, tags: ['agent', 'tool', 'update_chapter_content']);
    // 返回元信息（不含正文，避免 LLM 上下文爆炸）
    return jsonEncode({
      'success': true,
      'message': '章节已更新（${newContent.length} 字）。',
      'chapterUrl': chapterUrl,
      'position': position,
      'charCount': newContent.length,
    });
  }

  /// AI 重写整章正文（原 update_chapter_content 的 LLM 全文重写逻辑）。
  ///
  /// 与 [updateChapterContent] 的字符串替换不同，本方法把整章原文 + 修改要求 +
  /// 人物卡 + 写作标签拼成提示词，流式调用 LLM 重新生成整章正文后入库。
  /// 适合大范围重写、风格转换、结构调整；想精确改某段用 update_chapter_content。
  Future<String> rewriteChapterContent(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx, {
    void Function(int generatedChars)? onProgress,
  }) async {
    final parser = ToolArgParser(args);
    final (position, posErr) = parser.requireInt('position');
    if (posErr != null) return posErr;
    final (rewriteInstruction, instErr) =
        parser.requireString('rewriteInstruction');
    if (instErr != null) return instErr;
    final (characterNames, charNamesErr) = parser.optionalStringList('characterNames');
    if (charNamesErr != null) return charNamesErr;
    final (tagNames, tagNamesErr) = parser.optionalStringList('tagNames');
    if (tagNamesErr != null) return tagNamesErr;
    final charNames = characterNames ?? const <String>[];
    final tags = tagNames ?? const <String>[];

    // 一次解析同时拿到 novelUrl + chapterUrl，避免再调一次 resolveCurrentNovelUrl 重复查 DB
    final resolveResult = await resolveChapterUrlByPosition(ctx, position);
    if (resolveResult.errorJson != null) {
      return jsonEncode(resolveResult.errorJson);
    }
    final novelUrl = resolveResult.novelUrl!;
    final chapterUrl = resolveResult.chapterUrl!;

    // 读取章节原文（重写基础）
    final chapterRepo = ref.read(chapterRepositoryProvider);
    final chapters = await chapterRepo.getCachedNovelChapters(novelUrl);
    final chapter =
        chapters.firstWhere((c) => c.url == chapterUrl, orElse: () => chapters[position - 1]);
    final originalContent = await chapterRepo.getCachedChapter(chapterUrl);
    if (originalContent == null || originalContent.isEmpty) {
      return jsonEncode({
        'error': 'not_cached',
        'message':
            '位置 $position 的章节存在但内容尚未缓存，无法重写。请告知用户先加载/缓存该章节。',
      });
    }

    // 组合提示词并调用 LLM 重写
    final rewriteResult = await _rewriteChapter(
      novelUrl: novelUrl,
      chapterTitle: chapter.title,
      originalContent: originalContent,
      rewriteInstruction: rewriteInstruction,
      characterNames: charNames,
      tagNames: tags,
      scenarioId: ctx?.scenarioId ?? ScenarioIds.writing,
      onProgress: onProgress,
    );
    if (rewriteResult.errorJson != null) {
      return jsonEncode(rewriteResult.errorJson);
    }
    final newContent = ContentSanitizer.sanitize(rewriteResult.content!);

    // 保存到数据库
    final affected = await ref
        .read(chapterMutationProvider.notifier)
        .updateChapterContent(
          chapterUrl,
          newContent,
          source: 'ai_rewrite',
          novelUrl: novelUrl,
        );
    if (affected == 0) {
      LoggerService.instance.d(
        '工具引导错误: chapter_not_found position=$position',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'rewrite_chapter', 'chapter_not_found'],
      );
      return jsonEncode(guidanceError(
        'chapter_not_found',
        '章节位置 $position 的数据库记录不存在或内容表无对应行。',
        suggestedTool: 'list_chapters',
        suggestedArgs: const <String, dynamic>{},
      ));
    }

    LoggerService.instance.i(
        'AI 重写章节: position=$position, ${originalContent.length}→${newContent.length} chars',
        category: LogCategory.ai, tags: ['agent', 'tool', 'rewrite_chapter']);
    // 返回元信息（不含正文，避免 LLM 上下文爆炸）
    // __meta 不会被 agent_loop 截断，UI 据此渲染跳转入口
    return jsonEncode({
      'success': true,
      'message': '章节「${chapter.title}」已重写（${newContent.length} 字）。',
      'chapterTitle': chapter.title,
      'position': position,
      'novelUrl': novelUrl,
      'chapterUrl': chapterUrl,
      'charCount': newContent.length,
    });
  }

  /// 删除指定章节（同时清理 novel_chapters 和 chapter_cache），并触发章节索引重排
  ///
  /// position 来自 list_chapters（1-based）。删除后调用 [ChapterRepository.cacheNovelChapters]
  /// 传入剩余章节列表，由其内部把后续章节的 chapterIndex 连续化为 0,1,2...
  /// 以保证再次调用 list_chapters / read_chapter_content 时 position 解析正确。
  Future<String> deleteChapter(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    final parser = ToolArgParser(args);
    final (position, posErr) = parser.requireInt('position');
    if (posErr != null) return posErr;

    // 一次解析同时拿到 novelUrl + chapterUrl，错误码与旧版本完全一致
    final resolveResult = await resolveChapterUrlByPosition(ctx, position);
    if (resolveResult.errorJson != null) {
      return jsonEncode(resolveResult.errorJson);
    }
    final novelUrl = resolveResult.novelUrl!;
    final chapterUrl = resolveResult.chapterUrl!;

    final chapterRepo = ref.read(chapterRepositoryProvider);

    // 先记下要删章节的标题（用于返回 message），避免删后查不到
    final chapters = await chapterRepo.getCachedNovelChapters(novelUrl);
    final deletedChapter = chapters.firstWhere(
      (c) => c.url == chapterUrl,
      orElse: () => chapters[position - 1],
    );
    final deletedTitle = deletedChapter.title;
    final deletedIndex = deletedChapter.chapterIndex;

    // 单事务：delete 两表 + 剩余章节 chapterIndex 连续化，走 ChapterMutationNotifier
    // 收口（bump signal 触发章节列表软刷新）。替代原 delete+重读+cacheNovelChapters 三步。
    await ref.read(chapterMutationProvider.notifier).deleteChapter(
          novelUrl,
          chapterUrl,
        );

    final remaining = await chapterRepo.getCachedNovelChapters(novelUrl);

    LoggerService.instance.i(
        '删除章节: novelUrl=$novelUrl position=$position title="$deletedTitle" index=$deletedIndex',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'delete_chapter']);
    return jsonEncode({
      'success': true,
      'message': '章节「$deletedTitle」已删除（原 position=$position）。',
      'deletedTitle': deletedTitle,
      'deletedPosition': position,
      'remainingChapters': remaining.length,
    });
  }

  // ===== LLM 调用链 helper（仅章节写入域需要）=====

  /// 读取 AI 作家设定（用户在 AI 配置页填写的作家人设 prompt），返回 trim 后的字符串
  Future<String> _loadWriterPrompt() async {
    final raw = await PreferencesService.instance.getString('ai_writer_prompt');
    return raw.trim();
  }

  /// 拼装 LLM 上下文片段：人物卡 + 写作标签。
  ///
  /// 人物卡按名字在当前小说里查找（避免暴露/误传真实 ID）；
  /// 写作标签按名匹配，每个标签随机抽一条 prompt。
  Future<List<String>> _buildContextParts(
    String novelUrl,
    List<String> characterNames,
    List<String> tagNames,
  ) async {
    final parts = <String>[];

    // 人物卡与写作标签两路查询互不依赖：先并发启动，再各自 await 收集
    final charactersFuture = characterNames.isEmpty
        ? Future<List<Character>>.value(const [])
        : ref.read(characterRepositoryProvider).getCharacters(novelUrl);
    final tagsFuture = tagNames.isEmpty
        ? Future<List<PromptTag>>.value(const [])
        : ref.read(promptTagRepositoryProvider).getAll();

    // 人物卡：按名字在当前小说里查找（避免暴露/误传真实 ID）
    final allCharacters = await charactersFuture;
    if (characterNames.isNotEmpty) {
      final wanted = allCharacters
          .where((c) => characterNames.contains(c.name))
          .toList();
      if (wanted.isNotEmpty) {
        parts.add(Character.formatForAI(wanted));
      }
    }

    // 写作标签（每个标签随机抽一条 prompt）
    final allTags = await tagsFuture;
    if (tagNames.isNotEmpty) {
      final buffer = StringBuffer('【写作标签参考】\n');
      for (final name in tagNames) {
        final matched = allTags.where((t) => t.name == name).toList();
        if (matched.isEmpty) continue;
        matched.shuffle();
        buffer.writeln('- $name：${matched.first.promptText}');
      }
      if (buffer.length > '【写作标签参考】\n'.length) {
        parts.add(buffer.toString());
      }
    }

    return parts;
  }

  /// 流式调用 LLM 生成正文。
  ///
  /// 由 [systemPrompt] 和 [userPrompt] 组成消息，使用写作场景的激活配置。
  /// 走 [LlmProvider.chatStream] 逐 chunk 累积正文；每收到非空 chunk 时通过
  /// [onProgress] 回调上报已生成字符数（供 UI 流式进度展示）。
  /// [failTag] 用于失败日志的 tag 归属。
  Future<_RewriteResult> _callLlm({
    required String systemPrompt,
    required String userPrompt,
    required String failTag,
    String scenarioId = ScenarioIds.writing,
    void Function(int generatedChars)? onProgress,
  }) async {
    final llm =
        await ref.read(llmConfigServiceProvider).buildActiveProvider(scenarioId);
    if (llm == null) {
      return _RewriteResult.failure({
        'error': 'llm_not_configured',
        'message': LlmConfigService.notConfiguredMessage,
      });
    }

    try {
      final buffer = StringBuffer();
      await for (final chunk in llm.chatStream(
        messages: [
          ChatMessage(role: 'system', content: systemPrompt),
          ChatMessage(role: 'user', content: userPrompt),
        ],
        temperature: 0.8,
      )) {
        if (chunk.isNotEmpty) {
          buffer.write(chunk);
          if (onProgress != null) {
            onProgress(buffer.length);
          }
        }
      }
      final content = buffer.toString().trim();
      if (content.isEmpty) {
        return _RewriteResult.failure({
          'error': 'llm_empty_response',
          'message': 'LLM 返回了空内容。请稍后重试或调整要求。',
        });
      }
      return _RewriteResult.success(content);
    } catch (e, stack) {
      LoggerService.instance.e('LLM 调用失败: $e',
          stackTrace: stack.toString(),
          category: LogCategory.ai,
          tags: ['agent', 'tool', failTag, 'llm_error']);
      return _RewriteResult.failure({
        'error': 'llm_call_failed',
        'message': '调用 LLM 失败：$e',
      });
    }
  }

  /// 调用 LLM 重写章节
  ///
  /// 组合「原文 + 修改要求 + 人物卡 + 标签 prompt」为提示词，
  /// 流式调用 LLM，返回新正文或错误。
  Future<_RewriteResult> _rewriteChapter({
    required String novelUrl,
    required String chapterTitle,
    required String originalContent,
    required String rewriteInstruction,
    required List<String> characterNames,
    required List<String> tagNames,
    String scenarioId = ScenarioIds.writing,
    void Function(int generatedChars)? onProgress,
  }) async {
    final writerPrompt = await _loadWriterPrompt();
    final contextParts =
        await _buildContextParts(novelUrl, characterNames, tagNames);

    final prompt = StringBuffer()
      ..writeln('请根据以下信息重写章节正文。')
      ..writeln()
      ..writeln('## 章节标题')
      ..writeln(chapterTitle)
      ..writeln()
      ..writeln('## 修改要求')
      ..writeln(rewriteInstruction)
      ..writeln();
    if (contextParts.isNotEmpty) {
      prompt.writeln(contextParts.join('\n'));
      prompt.writeln();
    }
    prompt
      ..writeln('## 原文')
      ..writeln('<<<原文开始>>>')
      ..writeln(originalContent)
      ..writeln('<<<原文结束>>>')
      ..writeln()
      ..writeln('## 输出要求')
      ..writeln('请直接输出重写后的完整章节正文，不要输出任何说明、标题或解释性文字。');

    final systemPrompt = writerPrompt.isNotEmpty
        ? '$writerPrompt\n\n你是专业的小说写作助手，只输出小说正文。'
        : '你是专业的小说写作助手，只输出小说正文。';

    return _callLlm(
      systemPrompt: systemPrompt,
      userPrompt: prompt.toString(),
      failTag: 'update_chapter_content',
      scenarioId: scenarioId,
      onProgress: onProgress,
    );
  }

  /// 调用 LLM 创作新章节
  ///
  /// 组合「前一章正文（可选）+ 创作要求 + 人物卡 + 标签 prompt」为提示词（无原文），
  /// 流式调用 LLM，返回新正文或错误。
  Future<_RewriteResult> _generateChapter({
    required String novelUrl,
    required String chapterTitle,
    required String instruction,
    required List<String> characterNames,
    required List<String> tagNames,
    String? previousChapterContext,
    String scenarioId = ScenarioIds.writing,
    void Function(int generatedChars)? onProgress,
  }) async {
    final writerPrompt = await _loadWriterPrompt();
    final contextParts =
        await _buildContextParts(novelUrl, characterNames, tagNames);

    final prompt = StringBuffer()
      ..writeln('请根据以下信息创作新的章节正文。')
      ..writeln()
      ..writeln('## 章节标题')
      ..writeln(chapterTitle)
      ..writeln();
    // 前一章正文：用成对硬边界符号包裹，明确为只读参考，避免与创作要求/产出混淆
    if (previousChapterContext != null && previousChapterContext.isNotEmpty) {
      prompt
        ..writeln('## 前一章内容（仅供衔接参考：保持人物、情节、场景连贯，'
            '勿与上文矛盾，不要重复上文情节，不要直接续写接龙）')
        ..writeln()
        ..writeln('━━━━━━━━━ 上一章正文开始 ━━━━━━━━━')
        ..writeln(previousChapterContext)
        ..writeln('━━━━━━━━━ 上一章正文结束 ━━━━━━━━━')
        ..writeln();
    }
    prompt
      ..writeln('## 创作要求')
      ..writeln(instruction)
      ..writeln();
    if (contextParts.isNotEmpty) {
      prompt.writeln(contextParts.join('\n'));
      prompt.writeln();
    }
    prompt
      ..writeln('## 输出要求')
      ..writeln('请直接输出完整的章节正文，不要输出任何说明、标题或解释性文字。');

    final systemPrompt = writerPrompt.isNotEmpty
        ? '$writerPrompt\n\n你是专业的小说写作助手，只输出小说正文。'
        : '你是专业的小说写作助手，只输出小说正文。';

    return _callLlm(
      systemPrompt: systemPrompt,
      userPrompt: prompt.toString(),
      failTag: 'create_chapter',
      scenarioId: scenarioId,
      onProgress: onProgress,
    );
  }
}
