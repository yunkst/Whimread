/// 工具执行器 — Agent 工具 → Repository 调度（facade）
///
/// 上下文驱动：通过 [AgentScenarioContext] 读取当前小说，position 解析为 chapterUrl。
/// 错误响应包含 suggested_tool，引导 AI 自助修复。
///
/// ★ 本类是 facade：负责 execute 入口（短路 / switch 分发 / try-catch），
/// 把 21 个工具按业务域拆给 7 个子执行器。共享 helper 抽到
/// [ToolExecutorHelpers] mixin。所有子执行器懒创建（late final），
/// 避免构造时 ref.read 触发副作用。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logger_service.dart';
import '../dsl_engine/llm_provider.dart' show kArgsParseErrorKey,
    kArgsParseErrorDetailKey, kArgsRawPreviewKey;
import 'agent_scenario.dart';
import 'tool_executor/chapter_read_executor.dart';
import 'tool_executor/chapter_write_executor.dart';
import 'tool_executor/character_executor.dart';
import 'tool_executor/media_executor.dart';
import 'tool_executor/novel_navigation_executor.dart';
import 'tool_executor/outline_executor.dart';
import 'tool_executor/prompt_tag_executor.dart';
import 'tool_executor_helpers.dart';

class ToolExecutor with ToolExecutorHelpers {
  ToolExecutor(this.ref);

  @override
  final Ref ref;

  // 懒创建子执行器（避免构造时 Eager 触发 ref.read）
  late final _novelNav = NovelNavigationExecutor(ref);
  late final _chapterRead = ChapterReadExecutor(ref);
  late final _chapterWrite = ChapterWriteExecutor(ref);
  late final _character = CharacterExecutor(ref);
  late final _outline = OutlineExecutor(ref);
  late final _promptTag = PromptTagExecutor(ref);
  late final _media = MediaExecutor(ref);

  /// 分发工具调用
  ///
  /// [scenarioContext] 写作场景专用，包含当前小说 ID。
  /// 对于 `select_novel` 工具，返回的结果会包含 success 标记，
  /// 上游（AgentChatNotifier）需自行维护状态。
  Future<String> execute(
    String toolName,
    Map<String, dynamic> args, {
    AgentScenarioContext? scenarioContext,
    void Function(int generatedChars)? onProgress,
  }) async {
    // ★ 短路：tool_call arguments JSON 解析失败
    //
    // 此分支由 [ToolCall.fromJson] / [StreamingResult.buildToolCalls] 在
    // 流式拼接截断 / JSON 不闭合 / 解析成功但不是对象时填入。
    // 不进入 switch 分发，直接返回引导错误，让 LLM 自助修复（通常是网络抖动
    // 导致的流末尾截断）。这样 LLM 不会拿到空参数 {} 而误判调用成功，
    // 避免用户输入意图丢失。
    if (args.containsKey(kArgsParseErrorKey)) {
      final detail = args[kArgsParseErrorDetailKey]?.toString() ?? '未知错误';
      final preview = args[kArgsRawPreviewKey]?.toString() ?? '';
      LoggerService.instance.w(
        '工具参数解析失败短路: $toolName, detail=$detail',
        category: LogCategory.ai,
        tags: ['agent', 'tool', toolName, 'args_parse_error'],
      );
      return jsonEncode({
        'error': 'args_parse_failed',
        'message': '你为本工具提供的参数 JSON 格式不合法（流式输出被截断或 JSON 不闭合）。'
            '请重新调用本工具，确保 arguments 是合法 JSON 对象。',
        'parse_error_detail': detail,
        'previous_args_preview': preview,
        'suggested_action':
            '重新调用 $toolName，使用完整、合法闭合的 JSON 对象作为 arguments。',
      });
    }

    LoggerService.instance.d('执行工具: $toolName (args=${args.keys.toList()})',
        category: LogCategory.ai, tags: ['agent', 'tool', toolName, 'exec']);
    try {
      switch (toolName) {
        // ===== 小说导航 =====
        case 'list_novels':
          return await _novelNav.listNovels(args);
        case 'select_novel':
          return await _novelNav.selectNovel(args);
        case 'create_novel':
          return await _novelNav.createNovel(args);
        // ===== 章节读取 =====
        case 'read_chapter_content':
          return await _chapterRead.readChapterContent(args, scenarioContext);
        case 'list_chapters':
          return await _chapterRead.listChapters(args, scenarioContext);
        case 'search_in_chapters':
          return await _chapterRead.searchInChapters(args, scenarioContext);
        // ===== 章节写入 =====
        case 'create_chapter':
          return await _chapterWrite.createChapter(args, scenarioContext,
              onProgress: onProgress);
        case 'update_chapter_content':
          return await _chapterWrite.updateChapterContent(args, scenarioContext,
              onProgress: onProgress);
        case 'rewrite_chapter':
          return await _chapterWrite.rewriteChapterContent(args, scenarioContext,
              onProgress: onProgress);
        case 'delete_chapter':
          return await _chapterWrite.deleteChapter(args, scenarioContext);
        // ===== 角色 =====
        case 'list_characters':
          return await _character.listCharacters(args, scenarioContext);
        case 'update_character':
          return await _character.updateCharacter(args, scenarioContext);
        case 'create_character':
          return await _character.createCharacter(args, scenarioContext);
        case 'delete_character':
          return await _character.deleteCharacter(args, scenarioContext);
        // ===== 设定 / 大纲 =====
        case 'get_background_setting':
          return await _outline.getBackgroundSetting(args, scenarioContext);
        case 'update_background_setting':
          return await _outline.updateBackgroundSetting(args, scenarioContext);
        case 'update_outline':
          return await _outline.updateOutline(args, scenarioContext);
        case 'write_outline':
          return await _outline.writeOutline(args, scenarioContext);
        case 'get_outline':
          return await _outline.getOutline(args, scenarioContext);
        // ===== 小说封面 =====
        case 'set_novel_cover':
          return await _novelNav.setNovelCover(args, scenarioContext);
        // ===== 提示标签 =====
        case 'list_prompt_tags':
          return await _promptTag.listPromptTags(args);
        case 'get_prompt_tag':
          return await _promptTag.getPromptTag(args);
        case 'save_prompt_tag':
          return await _promptTag.savePromptTag(args);
        case 'delete_prompt_tag':
          return await _promptTag.deletePromptTag(args);
        // ===== 文生图（ComfyUI）=====
        case 'list_text2img_models':
          return await _media.listText2ImgModels(args);
        case 'create_images':
          return await _media.createImages(args);
        case 'create_image_to_video':
          return await _media.createImageToVideo(args);
        default:
          LoggerService.instance.w('未知工具: $toolName',
              category: LogCategory.ai, tags: ['agent', 'tool', toolName, 'unknown']);
          return jsonEncode({
            'error': 'unknown_tool',
            'message': '未知工具: $toolName',
          });
      }
    } catch (e, stack) {
      LoggerService.instance.e('工具执行失败: $toolName, error=$e',
          stackTrace: stack.toString(),
              category: LogCategory.ai,
              tags: ['agent', 'tool', toolName, 'error']);
      return jsonEncode({
        'error': 'execution_failed',
        'message': e.toString(),
      });
    }
  }
}
