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
    buffer.writeln('5. 修改小说封面：先用 create_images（图片）或 '
        'create_image_to_video（视频）生成媒体，从返回结果里选最合适的一张，'
        '把它的 mediaId 传给 set_novel_cover。封面接受图片或视频，'
        '封面图本身不需要包含书名文字（书名会在书架标题区独立展示）。'
        '如需恢复默认占位封面，调 set_novel_cover 时 mediaId 传 null。');
    buffer.writeln('6. 修改操作完成后向用户汇报。');
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
