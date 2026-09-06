import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 当前阅读上下文
///
/// 记录用户在哪个小说/章节页面，用于 AI 聊天时注入上下文。
class ReadingContext {
  /// 当前小说名称
  final String? novelTitle;
  /// 当前章节名称
  final String? chapterTitle;
  /// 小说 URL（唯一标识，可用于查询详细信息）
  final String? novelUrl;

  const ReadingContext({
    this.novelTitle,
    this.chapterTitle,
    this.novelUrl,
  });

  /// 是否有有效的阅读上下文
  bool get hasContext => novelTitle != null;

  /// 转为人类可读标签
  String get displayLabel {
    if (!hasContext) return '';
    if (chapterTitle != null) {
      return '$novelTitle · $chapterTitle';
    }
    return novelTitle!;
  }

  /// 生成 system prompt 文本，用于注入到聊天消息中
  String toSystemPrompt() {
    if (!hasContext) return '';
    final parts = <String>['当前用户正在使用小说阅读应用'];
    parts.add('当前小说: $novelTitle');
    if (chapterTitle != null) {
      parts.add('当前章节: $chapterTitle');
    }
    return parts.join('，');
  }

  /// 清除上下文的快捷方法
  static const none = ReadingContext();
}

/// 全局阅读上下文 Provider
///
/// 用于在 Agent 聊天时注入当前小说/章节信息。
final readingContextProvider = StateProvider<ReadingContext>((ref) {
  return const ReadingContext();
});