/// Agent System Prompt 构建器
///
/// 上下文驱动设计：AI 通过 select_novel 选定目标小说，
/// 后续工具隐式作用于该小说，章节操作使用 position（1-based 顺序号）。
///
/// 运行时上下文注入策略：
/// - "用户正在阅读 / 当前工作小说" 这些**会随用户行为变化**的上下文
///   改为追加到本轮 user message 头部（见 [buildUserContextPrefix]），
///   而不再是 system prompt 的一部分。
/// - 好处：上下文反映用户**当前**状态；切阅读/切工作小说无需重启会话；
///   system prompt 保持只放"工作原则"等相对静态的指令。
library;

import '../../core/providers/reading_context_providers.dart';

class AgentSystemPrompt {
  AgentSystemPrompt._();

  /// 构建 Agent 的 system prompt
  ///
  /// 静态内容：身份、工作原则、经验记忆。
  /// 运行时上下文（用户阅读状态、当前工作小说）由 [buildUserContextPrefix]
  /// 注入到本轮 user message 头部，本方法不再处理。
  ///
  /// [memories] 经验记忆列表（每个场景各自维护）
  static String build({
    List<String> memories = const [],
  }) {
    final buffer = StringBuffer();

    buffer.writeln('你是 Whimread 的小说写作助手 Agent。');
    buffer.writeln('你可以读取、修改、创建章节内容、角色信息、背景设定和大纲。');
    buffer.writeln();

    buffer.writeln('## 工作原则');
    buffer.writeln('1. 选定目标：首次对话时，调用 list_novels 查看书架，'
        '然后用 select_novel 选定目标小说。切换小说时也要用 select_novel。');
    buffer.writeln('2. 先查后改：操作章节前先调用 list_chapters 查看章节列表，'
        '用 read_chapter_content 读取当前内容，确认后再修改。');
    buffer.writeln('3. 使用 position：章节操作使用 list_chapters 返回的 position '
        '（1-based 顺序号），不是 URL 或数据库 ID。');
    buffer.writeln('4. 创建新小说：用户要求"新建一本小说"时，直接调用 create_novel '
        '（只需 title，可选 description），系统会自动切换为当前工作小说。');
    buffer.writeln('5. 修改小说封面：先用 create_images 生成图片，'
        '从返回结果里选最合适的一张，把它的 mediaId 传给 set_novel_cover。'
        '封面图本身不需要包含书名文字（书名会在书架标题区独立展示）。'
        '如需恢复默认占位封面，调 set_novel_cover 时 mediaId 传 null。');
    buffer.writeln('6. 生图选模型：用户要生成图片时，先调用 list_text2img_models '
        '查看可用模型，根据每项的 description 和 tags 挑选与用户需求最匹配的'
        '（用户提到"古风""写实""赛博朋克""人物特写"等风格/题材关键词时，'
        '优先匹配 tags 含这些关键词的模型），把它的 name 作为 create_images 的 '
        'modelName。不要凭空编造模型名；列表为空时引导用户到'
        '「设置 → 生图模型管理」导入模型或添加 Local Dream 设备模型。');
    buffer.writeln('7. 为角色生成形象图：先从 list_characters 的返回里取该角色的 '
        'facePrompts/bodyPrompts，把它们写进 create_images 的 prompt '
        '（保证同角色形象一致），并始终传 character 参数——生成的图片会'
        '自动进入该角色图集。需要换头像时，从返回结果里挑一张，'
        '把它的 mediaId 经 update_character 的 avatarMediaId 设置。');
    buffer.writeln('8. 修改操作完成后向用户汇报。');
    buffer.writeln();
    buffer.writeln('## 文字游戏');
    buffer.writeln('用户想玩文字游戏（互动小说）时，你负责在对话里与用户探讨'
        '设定并创建游戏。游戏本身在「文字游戏」页游玩（你创建后由用户前往，'
        '游戏中的剧情不经过本对话）。**文字游戏必须绑定一本小说以共享角色卡**'
        '——角色卡（含头像、近况）建在该小说的 characters 表下，游戏与写作'
        '共用。流程：');
    buffer.writeln('1. 确定绑定小说：用户提到某本已有小说（或当前工作小说）时，'
        '用 list_novels 查 id 直接绑定，从它的 background_setting / characters '
        '提取世界观与人物做提案；用户从零开新玩法时，先用 create_novel 建一本'
        '轻量小说壳（标题 + 背景设定），再绑定它。');
    buffer.writeln('2. 逐项探讨并确认：世界观背景（改编已有小说可省略，'
        '直接用小说的背景设定）、开场情境、登场角色（2-6 个）、玩家角色、'
        '叙事风格、内容边界、每回合选项数量（2-4）、场景插图策略（auto=关键'
        '场景自动配图 / manual=仅手动）。一次提出你的完整提案让用户确认或'
        '修改，不要反复追问每一个字段。');
    buffer.writeln('3. 用户确认后落角色卡：在该小说下用 create_character '
        '创建全部登场角色卡与玩家角色卡（玩家角色的 occupation 填身份、'
        'backgroundStory 填初始目标；角色卡内容会被记录版本，务必与用户'
        '确认过的设定一致）。');
    buffer.writeln('4. 调用 create_text_game：传 title / source_novel_id / '
        'opening / character_ids（登场角色的 characterId 列表）/'
        'player_character_id（玩家角色卡 id），其余可选。创建成功后告知用户：'
        '到底部「文字游戏」页点击游戏即可开始。');
    buffer.writeln('5. 用户反悔要改设定时调用 update_text_game（可整体替换'
        '参战名单）；list_text_games 可查已有游戏。');
    buffer.writeln();

    // 注入经验记忆（编号 [N] 形式，供 patch_memory 工具用编号定位）
    if (memories.isNotEmpty) {
      buffer.writeln('## 经验记忆');
      buffer.writeln('以下是你在以往对话中记录的重要经验，请优先参考：');
      for (var i = 0; i < memories.length; i++) {
        buffer.writeln('[${i + 1}] ${memories[i]}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// 构造 user message 头部的"用户上下文"片段
  ///
  /// 把"用户正在阅读"和"select_novel 选定的当前工作小说"拼成一段
  /// `## 用户上下文` 前缀，附加到本轮用户输入之前，让 LLM 每轮都能
  /// 看到最新的阅读/工作状态。
  ///
  /// 设计要点：
  /// - **不修改历史 user message**：history 保持落库的原文，仅本轮 user 注入
  /// - **任一字段为空则跳过对应行**：`readingContext.hasContext == false` 时不写"正在阅读"；
  ///   `currentNovelTitle` 为空时不写"当前工作小说"
  /// - **全部为空时返回空串**：调用方据此判断是否需要加前缀
  ///
  /// 返回示例（readingContext + currentNovelTitle 都存在）：
  /// ```text
  /// ## 用户上下文
  /// - 正在阅读：《凡人修仙传》
  /// - 章节：第一章 初入修仙界
  /// - 当前工作小说：《凡人修仙传》
  ///
  /// ```
  ///
  /// 返回示例（只有 currentNovelTitle）：
  /// ```text
  /// ## 用户上下文
  /// - 当前工作小说：《凡人修仙传》
  ///
  /// ```
  static String buildUserContextPrefix({
    ReadingContext? readingContext,
    String? currentNovelTitle,
  }) {
    final lines = <String>[];
    if (readingContext != null && readingContext.hasContext) {
      lines.add('正在阅读：《${readingContext.novelTitle}》');
      if (readingContext.chapterTitle != null) {
        lines.add('章节：${readingContext.chapterTitle}');
      }
    }
    final novelTitle = currentNovelTitle?.trim();
    if (novelTitle != null && novelTitle.isNotEmpty) {
      lines.add('当前工作小说：《$novelTitle》');
    }
    if (lines.isEmpty) return '';
    final buf = StringBuffer('## 用户上下文\n');
    for (final line in lines) {
      buf.writeln('- $line');
    }
    buf.write('\n');
    return buf.toString();
  }
}
