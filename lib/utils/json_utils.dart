/// JSON 工具函数
///
/// 处理 LLM 输出中的常见 JSON 格式问题：
/// - markdown 代码块包裹（```json ... ```）
/// - 前后空白字符
/// - 非 JSON 文本混入
library;

import 'dart:convert';

/// 匹配 ```json ... ``` 或 ``` ... ``` 包裹的正则（顶层常量，避免重复编译）
final _mdJsonPattern = RegExp(
  r'^```(?:json)?\s*\n?([\s\S]*?)\n?\s*```$',
  dotAll: true,
);

/// 去除 LLM 输出中常见的 markdown 代码块包裹
///
/// 处理以下格式：
/// - ```json\n{...}\n```
/// - ```\n{...}\n```
/// - 纯 JSON 字符串（不做处理）
///
/// 同时去除前后空白字符。
String stripMarkdownJson(String input) {
  var text = input.trim();

  final match = _mdJsonPattern.firstMatch(text);
  if (match != null) {
    text = match.group(1)?.trim() ?? text;
  }

  return text;
}

/// 安全 JSON 解码：先清理 markdown 包裹，再 jsonDecode
///
/// 流程：
/// 1. 调用 [stripMarkdownJson] 清理 markdown 包裹
/// 2. 调用 `jsonDecode` 解码
/// 3. 失败时抛出 [FormatException]，附带原始错误信息和输入片段
dynamic safeJsonDecode(String input) {
  final cleaned = stripMarkdownJson(input);
  try {
    return jsonDecode(cleaned);
  } on FormatException catch (e) {
    // 提供诊断信息：清理前后的片段对比
    final preview = cleaned.length > 200
        ? '${cleaned.substring(0, 200)}...(truncated)'
        : cleaned;
    throw FormatException(
      'JSON 解码失败: ${e.message}\n清理后输入: $preview',
    );
  }
}
