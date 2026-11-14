/// 番外创作场景 — 锚点章驱动的番外生成 Agent
///
/// 由创建番外弹层发起（SideStoryCreateSheet → ScenarioSession
/// .startSideStoryCreation），工具面锁定宿主上下文，过程通过全局事件流进入
/// ScenarioSession，在 agent 对话窗口完整查看。
///
/// 锁定设计（与 AnnotationRewriteScenario 同型）：
/// - 目标绑定：宿主小说/锚点章来自构造时注入的 [SideStoryTarget]
///   （经 AgentScenarioContext.sideStoryTarget 传递）。
/// - 上下文切换：`create_side_story` 建番外（不入书架的 bookshelf 行）成功后，
///   内部工作上下文切到番外 novel——后续 `save_chapter` 全部落进番外的
///   章节（复用 ChapterWriteExecutor 的校验/清洗/落库收口），物理上无法
///   写入宿主小说。
/// - 正文由 Agent 在回复中直接写出（完整会话上下文天然可见：锚点章/需求/
///   人物卡/已写各章），`save_chapter` 只做校验与落库，不再有内层 LLM 生成。
/// - 最小工具面：
///   - `read_chapter_content` —— 只读锚点章正文（宿主上下文的唯一正文入口）
///   - `list_chapters`        —— 宿主小说章节列表（了解主线脉络）
///   - `list_characters`      —— 宿主小说人物卡（恒指向宿主，不随上下文切换）
///   - `list_prompt_tags` / `get_prompt_tag` —— 写作技巧（只读）
///   - `create_side_story`    —— 建番外并切换工作上下文
///   - `save_chapter`         —— 保存 Agent 写好的番外章节
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_providers.dart';
import '../../../core/providers/side_story_mutation_provider.dart';
import '../../../models/novel.dart';
import '../../logger_service.dart';
import '../agent_scenario.dart';
import '../tool_executor/character_executor.dart';
import '../tool_executor/chapter_write_executor.dart';
import '../tool_executor/prompt_tag_executor.dart';

class SideStoryScenario with AgentScenarioCleanupMixin implements AgentScenario {
  final Ref _ref;
  final SideStoryTarget _target;

  SideStoryScenario(this._ref, this._target);

  @override
  String get id => ScenarioIds.sideStory;

  @override
  String get displayName => '番外创作';

  @override
  List<Map<String, dynamic>> get tools => const [
        _kReadChapterContentTool,
        _kListChaptersTool,
        _kListCharactersTool,
        _kCreateSideStoryTool,
        _kSaveChapterTool,
        _kListPromptTagsTool,
        _kGetPromptTagTool,
      ];

  /// 锚点上下文（恒定）：read_chapter_content / list_chapters / list_characters
  /// 永远指向宿主小说，不受 create_side_story 后的上下文切换影响。
  AgentScenarioContext get _anchorContext => AgentScenarioContext(
        scenarioId: ScenarioIds.sideStory,
        currentNovelId: _anchorNovelId,
        currentNovelTitle: _target.anchorNovelTitle,
      );

  /// 工作上下文（可变）：create_side_story 成功后切到番外 novel，
  /// save_chapter 据此落库进番外。
  AgentScenarioContext? _writingContext;

  /// 宿主小说 id（创建时由 startSideStoryCreation 注入）
  int? _anchorNovelId;

  /// 注入宿主小说 id（factory build 时调用——context 里只有 URL，id 由
  /// factory 查库补齐，供 resolveCurrentNovelUrl 解析）
  void bindAnchorNovelId(int novelId) {
    _anchorNovelId = novelId;
    _writingContext = AgentScenarioContext(
      scenarioId: ScenarioIds.sideStory,
      currentNovelId: novelId,
      currentNovelTitle: _target.anchorNovelTitle,
    );
  }

  /// 本次运行创建的番外（用于会话层生成跳转卡与统计）
  Novel? createdSideStory;

  // ============================== 系统提示词 ==============================

  @override
  String buildSystemPrompt(AgentScenarioContext context) {
    final countReq = _target.desiredChapterCount != null
        ? '${_target.desiredChapterCount} 章'
        : '由你根据需求体量决定（建议 1~5 章，宁短勿水）';

    return '''你是番外创作 Agent。用户正在阅读小说，想为某一章衍生一段番外剧情——番外是一段独立成篇的支线故事，挂载在这一章之下，不会进入主线正文。你的任务：创建番外并生成全部章节正文。

## 关键理解
- 番外不是主线的延续，而是从锚点章「长出去」的支线：它讲的是这段剧情相关人物/事件的往事、后续或侧面，自成起承转合。
- 番外开篇要能让读者从锚点章自然滑入（时间/视角/事件的衔接点），结尾要收得住，不需要也不应该「未完待续」引导回主线。
- 不要复述锚点章已有内容，番外是新增剧情。

## 你的工作流程（必须按顺序）
1. 调用 `read_chapter_content` 通读锚点章正文，理解番外要挂接的剧情点。
2. 需要了解主线脉络时调用 `list_chapters`；需要人物设定时调用 `list_characters`（人物卡恒指向宿主小说）。
3. 调用 `list_prompt_tags` 查看用户的写作技巧库，与本次创作相关的技巧用 `get_prompt_tag` 读取完整提示词，落笔时遵循。
4. 调用 `create_side_story(title)` 建立番外（标题要像作品名，能概括这条支线，4~10 字为佳）。创建后所有保存操作自动作用于该番外。
5. 逐章创作（一章一轮，写完即存）：
   - 在**你的回复中直接写出该章完整正文**（1500~3000 字），人物性格、关系与口吻要点自然融入行文——你已在第 2 步读到人物卡，写作时它们就在你的上下文里。
   - 写完立即调用 `save_chapter(position, title, content)` 保存，content 必须与你刚写出的正文**逐字一致**（含段落换行）。
   - position 从 1 开始连续递增；一轮回复只写一章、保存一章，不要把多章塞进同一个回复（会被截断）。
   - 每章结尾留有推进感；相邻章节衔接连贯，人物细节前后一致。
6. 全部章节保存完成后，直接输出简短总结（番外名/章数/各章一句话简介），不要调用工具——看到你没有工具调用，流程即结束。

## 硬性规则
1. `save_chapter` 只能保存到番外（自动生效，你无需关心目标）；只调工具不写正文、或只写正文不调工具，都会导致内容丢失。
2. 不调用任何改写/删除宿主章节、改人物、改大纲的工具——工具面里也没有它们。
3. 期望章节数：$countReq。
4. 用户需求是最高优先级；需求与主线设定冲突时，以用户需求为准。

## 当前任务
- 宿主小说：《${_target.anchorNovelTitle}》
- 锚点章：${_target.anchorChapterTitle}（番外挂载于此章之下）
- 用户需求：
${_target.requirement}''';
  }

  // ============================== 场景钩子 ==============================

  @override
  Future<List<String>> getMemories() async {
    // 复用写作场景沉淀的经验记忆（只读，本场景没有 patch_memory 工具）
    try {
      return await _ref
          .read(agentMemoryRepositoryProvider)
          .getAllByScenario(ScenarioIds.writing);
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '番外创作加载经验记忆失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.ai,
        tags: ['agent', 'side-story', 'get_memories', 'failed'],
      );
      return const [];
    }
  }

  @override
  Future<String?> onNoToolCalls(List<ChatMessage> messages) async => null;

  @override
  Future<MemoryPatchResult> patchMemory(int? index, String newText) async =>
      MemoryPatchResult.error('patch_memory 在当前场景不可用', const []);

  // ============================== 工具实现 ==============================

  /// read_chapter_content：锚点章正文（锁定，唯一正文入口）
  Future<String> _readAnchorChapter() async {
    final repo = _ref.read(chapterRepositoryProvider);
    final content = await repo.getCachedChapter(_target.anchorChapterUrl);
    if (content == null || content.isEmpty) {
      return jsonEncode({
        'error': 'not_cached',
        'message': '锚点章内容尚未缓存，无法读取。请提示用户先在阅读页加载该章节。',
      });
    }
    return content;
  }

  /// list_chapters：宿主小说章节列表（了解主线脉络用）
  Future<String> _listAnchorChapters() async {
    final repo = _ref.read(chapterRepositoryProvider);
    final chapters =
        await repo.getCachedNovelChapters(_target.anchorNovelUrl);
    final list = chapters.map((c) => {
          'position': c.chapterIndex != null
              ? (c.chapterIndex! + 1)
              : (chapters.indexOf(c) + 1),
          'title': c.title,
          'isCached': c.isCached,
        }).toList();
    return jsonEncode({
      'novelTitle': _target.anchorNovelTitle,
      'anchorChapter': _target.anchorChapterTitle,
      'chapters': list,
      'count': list.length,
      'note': '这是宿主小说（主线）的章节列表，仅供了解脉络；'
          '你生成的章节全部写入番外，不会出现在这里。',
    });
  }

  /// create_side_story：建番外（不入书架行）+ 切换工作上下文
  Future<String> _createSideStory(Map<String, dynamic> args) async {
    // 本 run 已创建过 → 防重复
    if (createdSideStory != null) {
      return jsonEncode({
        'error': 'already_created',
        'message': '番外《${createdSideStory!.title}》已创建，请继续在回复中写正文并调用 save_chapter 保存，不要重复创建。',
      });
    }
    // 跨 run 幂等保护：场景实例每回合重建，同一次创作任务的后续回合
    // （如用户补充指令）会丢失内存态。按「锚点章 + 相同需求描述」查库
    // 找回本任务已建的番外并复用，避免 LLM 重调 create_side_story 造成
    // 重复番外。不同需求的创建互不影响（需求不同 description 不同）。
    final existing = await _ref
        .read(sideStoryRepositoryProvider)
        .getSideStories(
          anchorNovelUrl: _target.anchorNovelUrl,
          anchorChapterUrl: _target.anchorChapterUrl,
        );
    final prior = existing
        .where((s) => s.novel.description == _target.requirement)
        .toList();
    if (prior.isNotEmpty && prior.first.novel.id != null) {
      final novel = prior.first.novel;
      createdSideStory = novel;
      _switchWritingContext(novel);
      return jsonEncode({
        'success': true,
        'sideStoryId': novel.id,
        'sideStoryTitle': novel.title,
        'anchorChapter': _target.anchorChapterTitle,
        'message': '本任务已创建过番外《${novel.title}》，已切换为当前工作目标，继续在回复中写正文并调用 save_chapter 保存。',
      });
    }
    final title = args['title']?.toString().trim() ?? '';
    if (title.isEmpty) {
      return jsonEncode({
        'error': 'invalid_args',
        'message': 'title 必须是非空字符串（4~10 字，能概括这条支线）。',
      });
    }

    final novel = await _ref
        .read(sideStoryMutationProvider.notifier)
        .createSideStory(
          title: title,
          anchorNovelUrl: _target.anchorNovelUrl,
          anchorChapterUrl: _target.anchorChapterUrl,
          description: _target.requirement,
        );
    createdSideStory = novel;

    // 上下文切换：create_chapter 从此落库进番外（resolveCurrentNovelUrl
    // 按 currentNovelId 解析，无法再触达宿主小说）
    _switchWritingContext(novel);

    LoggerService.instance.i(
      'create_side_story: "${novel.title}" (id=${novel.id}, '
      'anchor=${_target.anchorChapterUrl})',
      category: LogCategory.ai,
      tags: ['agent', 'side-story', 'created'],
    );
    return jsonEncode({
      'success': true,
      'sideStoryId': novel.id,
      'sideStoryTitle': novel.title,
      'sideStoryUrl': novel.url,
      'anchorChapter': _target.anchorChapterTitle,
      'message': '番外《${novel.title}》已建立，后续 create_chapter 将写入该番外。',
    });
  }

  /// 工作上下文切到番外 novel
  void _switchWritingContext(Novel novel) {
    _writingContext = AgentScenarioContext(
      scenarioId: ScenarioIds.sideStory,
      currentNovelId: novel.id,
      currentNovelTitle: novel.title,
    );
  }

  /// save_chapter：把 Agent 在回复中写好的正文保存进番外
  /// （复用 ChapterWriteExecutor 的校验/清洗/落库收口）
  Future<String> _saveChapter(Map<String, dynamic> args) async {
    if (createdSideStory == null) {
      return jsonEncode({
        'error': 'no_side_story',
        'message': '尚未创建番外。请先调用 create_side_story(title)。',
        'suggested_tool': 'create_side_story',
      });
    }
    return ChapterWriteExecutor(_ref).saveChapter(args, _writingContext);
  }

  // ============================== 工具调度 ==============================

  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    switch (name) {
      case 'read_chapter_content':
        return _readAnchorChapter();
      case 'list_chapters':
        return _listAnchorChapters();
      case 'list_characters':
        // 恒指向宿主小说（人物卡在宿主上，不随番外上下文切换）
        return CharacterExecutor(_ref).listCharacters(args, _anchorContext);
      case 'create_side_story':
        return _createSideStory(args);
      case 'save_chapter':
        return _saveChapter(args);
      case 'list_prompt_tags':
        return PromptTagExecutor(_ref).listPromptTags(args);
      case 'get_prompt_tag':
        return PromptTagExecutor(_ref).getPromptTag(args);
      default:
        return jsonEncode({
          'error': 'unknown_tool',
          'message': '工具 $name 不在白名单内',
        });
    }
  }
}

// ============================== 工具定义（LLM 可见 schema） ==============================

const Map<String, dynamic> _kReadChapterContentTool = {
  'type': 'function',
  'function': {
    'name': 'read_chapter_content',
    'description': '读取锚点章（番外挂载的那一章）的完整正文。创作前必须先调用它理解要挂接的剧情。',
    'parameters': {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    },
  },
};

const Map<String, dynamic> _kListChaptersTool = {
  'type': 'function',
  'function': {
    'name': 'list_chapters',
    'description': '查看宿主小说（主线）的章节列表，了解主线脉络。仅供阅读，写操作不会作用于此列表。',
    'parameters': {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    },
  },
};

const Map<String, dynamic> _kListCharactersTool = {
  'type': 'function',
  'function': {
    'name': 'list_characters',
    'description': '查看宿主小说的人物卡（姓名/性格/外貌/关系）。写章节时把涉及人物的性格要点融入 instruction。',
    'parameters': {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    },
  },
};

const Map<String, dynamic> _kCreateSideStoryTool = {
  'type': 'function',
  'function': {
    'name': 'create_side_story',
    'description':
        '创建番外（一段挂载在锚点章下的独立支线，不进入主线章节列表）。'
        '创建成功后，后续所有 save_chapter 自动写入该番外。整个任务只能创建一次。',
    'parameters': {
      'type': 'object',
      'properties': {
        'title': {
          'type': 'string',
          'description': '番外标题，4~10 字，像作品名（如《闺蜜往事》）',
        },
      },
      'required': <String>['title'],
    },
  },
};

const Map<String, dynamic> _kSaveChapterTool = {
  'type': 'function',
  'function': {
    'name': 'save_chapter',
    'description':
        '保存一章番外。你必须在调用前的回复中已经完整写出该章全部正文'
        '（1500~3000 字），然后把同一段正文逐字作为 content 传入。'
        '本工具只负责校验与落库，不会生成任何内容；content 低于 300 字会被拒绝。'
        '必须先 create_side_story。',
    'parameters': {
      'type': 'object',
      'properties': {
        'position': {
          'type': 'integer',
          'description': '章节在番外内的序号（1 起连续递增）',
        },
        'title': {
          'type': 'string',
          'description': '本章标题（如「初遇」）',
        },
        'content': {
          'type': 'string',
          'description':
              '本章正文全文，与你回复中已写出的正文逐字一致（含段落换行），'
              '不要缩写或占位，不要混入标题或说明性文字',
        },
      },
      'required': <String>['position', 'content'],
    },
  },
};

const Map<String, dynamic> _kListPromptTagsTool = {
  'type': 'function',
  'function': {
    'name': 'list_prompt_tags',
    'description': '查看用户的写作技巧列表（分类 + 名称 + 使用场景），选取与本次创作相关的技巧。',
    'parameters': {
      'type': 'object',
      'properties': {
        'categoryName': {
          'type': 'string',
          'description': '可选，按分类名过滤',
        },
      },
      'required': <String>[],
    },
  },
};

const Map<String, dynamic> _kGetPromptTagTool = {
  'type': 'function',
  'function': {
    'name': 'get_prompt_tag',
    'description': '读取某条写作技巧的完整提示词（创作落笔时遵循）。',
    'parameters': {
      'type': 'object',
      'properties': {
        'id': {'type': 'integer', 'description': '技巧 id'},
        'name': {'type': 'string', 'description': '或按名称取'},
      },
      'required': <String>[],
    },
  },
};
