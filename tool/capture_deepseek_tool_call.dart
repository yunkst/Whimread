/// DeepSeek-V4-Pro 流式 tool_calls 抓包脚本
///
/// 用法：
///   DEEPSEEK_TOKEN=sk-xxx dart run tool/capture_deepseek_tool_call.dart
///
/// 行为：完全重放 llm_1787760494454_3332 那条原始请求体（同一个 endpoint、
/// model、messages、tools、tool_choice），用 dart:io HttpClient 流式消费，
/// 把每个 SSE data: 帧原样落盘到 `tmp/sse_capture_<ts>.txt`，
/// 并在控制台打印前 5 帧和 tool_calls 帧的逐字段解析结果。
///
/// 用途：确认 function.name 在流式 delta 里的真实形态（缺失/空串/分片），
/// 区分是网关透传 bug 还是客户端聚合问题。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:io' show Platform, stderr, exit;

const String endpoint = 'https://new-api.c2h4.cn/v1/chat/completions';
const String modelName = 'DeepSeek-V4-Pro';

// 与原 llm_1787760494454_3332 完全一致的请求体（除 token 不硬编码）
final Map<String, dynamic> requestBody = {
  'model': modelName,
  'stream': true,
  'temperature': 0.7,
  'max_tokens': 4096,
  'messages': [
    {
      'role': 'system',
      'content': '你是 Whimread 的小说写作助手 Agent。\n你可以读取、修改、创建章节内容、角色信息、背景设定和大纲。\n\n## 工作原则\n1. 选定目标：首次对话时，调用 list_novels 查看书架，然后用 select_novel 选定目标小说。切换小说时也要用 select_novel。\n2. 先查后改：操作章节前先调用 list_chapters 查看章节列表，用 read_chapter_content 读取当前内容，确认后再修改。\n3. 使用 position：章节操作使用 list_chapters 返回的 position （1-based 顺序号），不是 URL 或数据库 ID。\n4. 创建新小说：用户要求"新建一本小说"时，直接调用 create_novel （只需 title，可选 description），系统会自动切换为当前工作小说。\n5. 修改小说封面：先用 create_images（图片）或 create_image_to_video（视频）生成媒体，从返回结果里选最合适的一张，把它的 mediaId 传给 set_novel_cover。封面接受图片或视频，封面图本身不需要包含书名文字（书名会在书架标题区独立展示）。如需恢复默认占位封面，调 set_novel_cover 时 mediaId 传 null。\n6. 修改操作完成后向用户汇报。\n\n',
    },
    {
      'role': 'user',
      'content': '帮我创建一个服装描写tag,主要是包含各种女性的服装设计，超短裙，连衣裙，不要有裤子',
    },
  ],
  'tools': _toolsStub,
  'tool_choice': 'auto',
};

Future<void> main() async {
  final token = Platform.environment['DEEPSEEK_TOKEN'];
  if (token == null || token.isEmpty) {
    stderr.writeln('ERROR: DEEPSEEK_TOKEN 环境变量未设置。');
    stderr.writeln('用法: DEEPSEEK_TOKEN=sk-xxx dart run tool/capture_deepseek_tool_call.dart');
    exit(64);
  }

  final ts = DateTime.now().millisecondsSinceEpoch;
  final outFile = io.File('tmp/sse_capture_$ts.txt');
  await outFile.parent.create(recursive: true);
  final sink = outFile.openWrite();

  // 把 token 掩码后再打印请求头，避免完整泄露到 stdout
  final maskedAuth = token.length <= 8 ? '***' : '${token.substring(0, 4)}...${token.substring(token.length - 4)}';
  print('▶ Endpoint: $endpoint');
  print('▶ Token: $maskedAuth');
  print('▶ Output: ${outFile.path}');
  print('---');

  final client = io.HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  final uri = Uri.parse(endpoint);
  final req = await client.postUrl(uri);
  req.headers.set('Content-Type', 'application/json');
  req.headers.set('Authorization', 'Bearer $token');
  req.add(utf8.encode(jsonEncode(requestBody)));

  final resp = await req.close();
  final status = resp.statusCode;
  print('HTTP $status');
  if (status >= 400) {
    final body = await resp.transform(utf8.decoder).join();
    stderr.writeln('HTTP 错误:\n$body');
    exit(1);
  }

  int frameCount = 0;
  int toolCallFrameCount = 0;
  int rawBytes = 0;

  // 按 SSE 帧切：data: 行 + 空行表示一个事件结束。
  // 必须经 LineSplitter 流式逐行——SSE 行会被 TCP chunk 从中间截断，
  // 逐 chunk split 会把断行残余当作普通行清掉 pending data（丢帧）。
  final events = <String>[];
  String? currentData;
  await for (final line
      in resp.transform(utf8.decoder).transform(const LineSplitter())) {
    rawBytes += utf8.encode(line).length + 1;
    if (line.startsWith('data:')) {
      currentData = line.substring(5).trim();
    } else if (line.isEmpty && currentData != null) {
      events.add(currentData!);
      currentData = null;
    }
  }
  if (currentData != null) events.add(currentData!);

  for (final payload in events) {
    if (payload.isEmpty || payload == '[DONE]') {
      sink.writeln('[DONE or empty]');
      continue;
    }
    frameCount++;
    Map<String, dynamic> json;
    try {
      json = jsonDecode(payload) as Map<String, dynamic>;
    } catch (e) {
      sink.writeln('[parse-error] $payload');
      continue;
    }
    sink.writeln('── frame #$frameCount ──');
    sink.writeln(payload);
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) continue;
    final first = choices.first as Map<String, dynamic>;
    final delta = first['delta'] as Map<String, dynamic>?;
    if (delta == null) continue;
    final tcDeltas = delta['tool_calls'] as List?;
    if (tcDeltas == null || tcDeltas.isEmpty) continue;
    toolCallFrameCount++;
    sink.writeln('  ★ TOOL_CALL DELTA:');
    for (var i = 0; i < tcDeltas.length; i++) {
      final m = tcDeltas[i] as Map<String, dynamic>;
      final fn = m['function'] as Map<String, dynamic>?;
      sink.writeln('    [$i] index=${m['index']} id=${m['id']}');
      sink.writeln('        function.name=${fn?['name']} (type=${fn?['name']?.runtimeType})');
      sink.writeln('        function.arguments=${fn?['arguments']}');
    }
    if (frameCount <= 5) {
      print('frame #$frameCount keys: ${json.keys.toList()}');
      print('  delta keys: ${delta.keys.toList()}');
    }
  }

  await sink.flush();
  await sink.close();

  print('---');
  print('总帧数: $frameCount');
  print('tool_call 帧数: $toolCallFrameCount');
  print('原始流字节数: $rawBytes');
  print('原始流已落盘: ${outFile.path}');
  client.close(force: true);
}

// 为减少脚本依赖（不引入 17 个真实工具），这里用一个最小化的 tools stub：
// OpenAI 协议层面只需要 tools/tool_choice 字段存在以触发流式 tool_call 分支。
// 真正的 list_prompt_tags 名不重要——关键是让模型进入"决策调工具"的路径，
// 然后观察网关如何把这条决策流式编码进 SSE。
final List<Map<String, dynamic>> _toolsStub = [
  {
    'type': 'function',
    'function': {
      'name': 'list_prompt_tags',
      'description': '列出所有提示标签',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
      },
    },
  },
];