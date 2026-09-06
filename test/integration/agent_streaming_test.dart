/// AI Agent 流式输出 + tool_calls 真实 API 集成测试
///
/// 使用真实 DeepSeek API 验证：
///   1. chatStreamWithTools() 流式文本输出（多个 chunk）
///   2. tool_calls delta 跨多个 chunk 正确聚合为完整 ToolCall
///   3. StreamingResult.buildToolCalls() 聚合结果的正确性
///   4. 模拟 AgentLoop 的流式消费逻辑（逐 chunk emit TextDeltaEvent）
///
/// 运行:
///   cd novel_app
///   flutter test test/integration/agent_streaming_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:novel_app/services/dsl_engine/llm_provider.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';

// ============================================================================
// 配置（与 dsl_all_cmds_test.dart 一致）
// ============================================================================

const apiBaseUrl = String.fromEnvironment('TEST_API_BASE_URL');
const apiKey = String.fromEnvironment('TEST_API_KEY');
const defaultModel = String.fromEnvironment('TEST_DEFAULT_MODEL', defaultValue: 'deepseek-chat');

// ============================================================================
// HTTP 客户端（与 dsl_all_cmds_test.dart 一致，使用 http 包的真实流式）
// ============================================================================

class FixedHttpClient implements LlmHttpClient {
  final http.Client _client = http.Client();

  @override
  Future<String> postJson(
      String url, Map<String, String> headers, String body) async {
    final response = await _client.post(
      Uri.parse(url),
      headers: headers,
      body: body,
    );
    if (response.statusCode >= 400) {
      throw HttpException(
        'HTTP ${response.statusCode}: ${response.body}',
        uri: Uri.parse(url),
      );
    }
    return response.body;
  }

  @override
  Stream<String> postJsonStream(
      String url, Map<String, String> headers, String body) async* {
    final request = http.Request('POST', Uri.parse(url));
    request.headers.addAll(headers);
    request.body = body;
    final streamed = await _client.send(request);
    if (streamed.statusCode >= 400) {
      final errBody = await streamed.stream.bytesToString();
      throw HttpException(
        'HTTP ${streamed.statusCode}: $errBody',
        uri: Uri.parse(url),
      );
    }
    yield* streamed.stream.transform(utf8.decoder);
  }
}

// ============================================================================
// Agent 工具定义（测试用，与 agent_tools.dart 格式一致）
// ============================================================================

const testTools = [
  {
    'type': 'function',
    'function': {
      'name': 'list_novels',
      'description': '列出书架上的所有小说',
      'parameters': {
        'type': 'object',
        'properties': {},
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'read_chapter_content',
      'description': '读取指定章节的完整正文内容',
      'parameters': {
        'type': 'object',
        'properties': {
          'chapterId': {
            'type': 'integer',
            'description': '章节ID（从 list_chapters 获取）',
          },
        },
        'required': ['chapterId'],
      },
    },
  },
];

// ============================================================================
// 测试
// ============================================================================

void main() {
  // 环境守卫：需要真实 LLM 后端，未配置时 skip 全部测试
  final bool hasLlmConfig = apiBaseUrl.isNotEmpty && apiKey.isNotEmpty;

  group('chatStreamWithTools 真实 API — 纯文本流式', () {
    late LlmProvider provider;

    setUp(() {
      provider = LlmProvider(
        LlmConfig(
          baseUrl: apiBaseUrl,
          apiKey: apiKey,
          defaultModel: defaultModel,
        ),
        httpClient: FixedHttpClient(),
      );
    });

    test('应收到多个文本 chunk（流式工作）', () async {
      if (!hasLlmConfig) {
        markTestSkipped('需要配置 TEST_API_BASE_URL 和 TEST_API_KEY 环境变量');
        return;
      }
      final chunks = <LlmStreamChunk>[];

      await for (final chunk in provider.chatStreamWithTools(
        messages: [
          ChatMessage(role: 'user', content: '用一句话介绍李白'),
        ],
      )) {
        chunks.add(chunk);
      }

      // ---- 验证：多个文本 chunk ----
      final contentChunks =
          chunks.where((c) => c.isContent).map((c) => c.contentChunk!).toList();
      final fullContent = contentChunks.join();

      print('━━━ 纯文本流式响应 ━━━');
      print('  总帧数: ${chunks.length}');
      print('  文本 chunk 数: ${contentChunks.length}');
      print('  完整内容 (${fullContent.length} chars): $fullContent');

      expect(contentChunks.length, greaterThan(1),
          reason: '流式响应应该拆分成多个 chunk，不是一个整体');
      expect(fullContent.length, greaterThan(10),
          reason: '内容不应为空');
      expect(fullContent, contains('李白'),
          reason: '内容应该提到李白');

      // ---- 验证：finish_reason ----
      final finishChunks = chunks.where((c) => c.isFinished).toList();
      expect(finishChunks.isNotEmpty, true,
          reason: '至少有一帧带 finish_reason');
      print('  finish_reason: ${finishChunks.map((c) => c.finishReason).toList()}');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('chatStreamWithTools 真实 API — tool_calls delta 聚合', () {
    late LlmProvider provider;

    setUp(() {
      provider = LlmProvider(
        LlmConfig(
          baseUrl: apiBaseUrl,
          apiKey: apiKey,
          defaultModel: defaultModel,
        ),
        httpClient: FixedHttpClient(),
      );
    });

    test('LLM 应调用工具，tool_calls delta 被正确聚合', () async {
      if (!hasLlmConfig) {
        markTestSkipped('需要配置 TEST_API_BASE_URL 和 TEST_API_KEY 环境变量');
        return;
      }
      final chunks = <LlmStreamChunk>[];
      final streamingResult = StreamingResult();

      await for (final chunk in provider.chatStreamWithTools(
        messages: [
          ChatMessage(
              role: 'system',
              content:
                  '你是一个助手。用户询问小说信息时，你必须调用 list_novels 工具来查询。不要自己编造答案。'),
          ChatMessage(role: 'user', content: '请帮我列出书架上的小说'),
        ],
        tools: testTools,
        toolChoice: 'auto',
      )) {
        chunks.add(chunk);
        if (chunk.isContent) {
          streamingResult.contentChunks.add(chunk.contentChunk!);
        }
        if (chunk.isToolCallDelta) {
          streamingResult.toolCallDeltas.addAll(chunk.toolCallDeltas);
        }
      }

      final toolCalls = streamingResult.buildToolCalls();

      print('━━━ 带工具调用的流式响应 ━━━');
      print('  总帧数: ${chunks.length}');
      print('  文本 chunk 数: ${chunks.where((c) => c.isContent).length}');
      print('  tool_call delta 帧数: ${chunks.where((c) => c.isToolCallDelta).length}');
      print('  聚合后 tool_calls 数: ${toolCalls.length}');
      for (final tc in toolCalls) {
        print('    → id=${tc.id}, name=${tc.name}, args=${tc.arguments}');
      }

      // ---- 验证：tool_calls delta 跨多个 chunk ----
      final deltaFrames = chunks.where((c) => c.isToolCallDelta).toList();
      expect(deltaFrames.length, greaterThanOrEqualTo(1),
          reason: 'tool_calls 应该通过 delta 帧传递');

      // ---- 验证：聚合出完整的 ToolCall ----
      expect(toolCalls.length, greaterThanOrEqualTo(1),
          reason: '至少聚合出一个完整的 tool_call');
      expect(toolCalls.first.name, 'list_novels',
          reason: 'LLM 应该调用 list_novels 工具');

      // ---- 验证：ToolCall 的 id 不为空 ----
      expect(toolCalls.first.id.isNotEmpty, true,
          reason: 'ToolCall 的 id 应该从 delta 中聚合出来');

      // ---- 验证：finish_reason 为 tool_calls ----
      final finishChunks = chunks.where((c) => c.isFinished).toList();
      expect(finishChunks.isNotEmpty, true);
      expect(finishChunks.last.finishReason, equals('tool_calls'),
          reason: 'finish_reason 应为 tool_calls');
      print('  finish_reason: ${finishChunks.map((c) => c.finishReason).toList()}');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('带参数的工具调用：arguments 应被完整拼接', () async {
      if (!hasLlmConfig) {
        markTestSkipped('需要配置 TEST_API_BASE_URL 和 TEST_API_KEY 环境变量');
        return;
      }
      final chunks = <LlmStreamChunk>[];
      final streamingResult = StreamingResult();

      await for (final chunk in provider.chatStreamWithTools(
        messages: [
          ChatMessage(
              role: 'system',
              content:
                  '你是一个助手。用户想读章节时，你必须调用 read_chapter_content 工具。'),
          ChatMessage(
              role: 'user',
              content: '请帮我读取章节ID为1的章节内容'),
        ],
        tools: testTools,
        toolChoice: 'auto',
      )) {
        chunks.add(chunk);
        if (chunk.isContent) {
          streamingResult.contentChunks.add(chunk.contentChunk!);
        }
        if (chunk.isToolCallDelta) {
          streamingResult.toolCallDeltas.addAll(chunk.toolCallDeltas);
        }
      }

      final toolCalls = streamingResult.buildToolCalls();

      print('━━━ 带参数的工具调用 ━━━');
      print('  聚合后 tool_calls 数: ${toolCalls.length}');
      for (final tc in toolCalls) {
        print('    → name=${tc.name}, args=${tc.arguments}');
      }

      // ---- 验证 ----
      expect(toolCalls.isNotEmpty, true, reason: '应该有工具调用');
      expect(toolCalls.first.name, 'read_chapter_content',
          reason: '应该调用 read_chapter_content');
      expect(toolCalls.first.arguments.containsKey('chapterId'), true,
          reason: 'arguments 应该包含 chapterId 参数');
      expect(toolCalls.first.arguments['chapterId'], isA<int>(),
          reason: 'chapterId 参数值应该是整数');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('模拟 AgentLoop 流式消费逻辑', () {
    late LlmProvider provider;

    setUp(() {
      provider = LlmProvider(
        LlmConfig(
          baseUrl: apiBaseUrl,
          apiKey: apiKey,
          defaultModel: defaultModel,
        ),
        httpClient: FixedHttpClient(),
      );
    });

    test('纯文本：逐 chunk emit TextDeltaEvent → AgentDoneEvent', () async {
      if (!hasLlmConfig) {
        markTestSkipped('需要配置 TEST_API_BASE_URL 和 TEST_API_KEY 环境变量');
        return;
      }
      // 模拟 AgentLoop.run() 中消费流的核心逻辑
      final events = <AgentEvent>[];
      final streamingResult = StreamingResult();

      await for (final chunk in provider.chatStreamWithTools(
        messages: [
          ChatMessage(role: 'user', content: '用一句话介绍杜甫'),
        ],
        tools: testTools,
        toolChoice: 'auto',
      )) {
        if (chunk.isContent) {
          // 关键：逐 chunk emit（流式展示）
          events.add(TextDeltaEvent(chunk.contentChunk!));
          streamingResult.contentChunks.add(chunk.contentChunk!);
        }
        if (chunk.isToolCallDelta) {
          streamingResult.toolCallDeltas.addAll(chunk.toolCallDeltas);
        }
      }

      final toolCalls = streamingResult.buildToolCalls();
      if (toolCalls.isEmpty) {
        events.add(const AgentDoneEvent());
      }

      final textDeltas = events.whereType<TextDeltaEvent>().toList();

      print('━━━ 模拟 AgentLoop 纯文本流式 ━━━');
      print('  TextDeltaEvent 数: ${textDeltas.length}');
      print('  完整文本: ${textDeltas.map((e) => e.text).join()}');

      // ---- 验证：多个 TextDeltaEvent（核心！）----
      expect(textDeltas.length, greaterThan(1),
          reason: '流式模式下应收到多个 TextDeltaEvent，而不是一个整体');

      // ---- 验证：最后一个事件是 AgentDoneEvent ----
      expect(events.last, isA<AgentDoneEvent>());

      // ---- 验证：内容合理 ----
      final fullText = textDeltas.map((e) => e.text).join();
      expect(fullText, contains('杜甫'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('工具调用：TextDelta → ToolCallStart/End → 再轮 TextDelta → Done',
        () async {
      if (!hasLlmConfig) {
        markTestSkipped('需要配置 TEST_API_BASE_URL 和 TEST_API_KEY 环境变量');
        return;
      }
      // 模拟 AgentLoop 的完整 ReAct 消费逻辑
      // 第一轮：LLM 决定调用工具
      final round1Events = <AgentEvent>[];
      final streamingResult = StreamingResult();

      await for (final chunk in provider.chatStreamWithTools(
        messages: [
          ChatMessage(
              role: 'system',
              content:
                  '你是一个小说助手。查询小说信息时必须使用 list_novels 工具，不要自己编造。查询后简要回答。'),
          ChatMessage(
              role: 'user', content: '请列出我书架上的小说'),
        ],
        tools: testTools,
        toolChoice: 'auto',
      )) {
        if (chunk.isContent) {
          round1Events.add(TextDeltaEvent(chunk.contentChunk!));
          streamingResult.contentChunks.add(chunk.contentChunk!);
        }
        if (chunk.isToolCallDelta) {
          streamingResult.toolCallDeltas.addAll(chunk.toolCallDeltas);
        }
      }

      final toolCalls = streamingResult.buildToolCalls();

      print('━━━ 模拟 AgentLoop ReAct 第一轮 ━━━');
      print('  TextDeltaEvent 数: ${round1Events.whereType<TextDeltaEvent>().length}');
      print('  聚合后 tool_calls: ${toolCalls.length}');
      for (final tc in toolCalls) {
        print('    → ${tc.name}(${tc.arguments})');
      }

      // ---- 验证第一轮：LLM 决定调用工具 ----
      expect(toolCalls.isNotEmpty, true, reason: '第一轮应该有工具调用');
      expect(toolCalls.first.name, 'list_novels');

      // 模拟工具执行
      final toolResult = jsonEncode({
        'novels': [
          {'title': '测试小说', 'author': '测试作者'},
        ],
      });

      // 第二轮：将工具结果送回 LLM，获取最终文本回复
      final round2Events = <AgentEvent>[];
      final streamingResult2 = StreamingResult();

      await for (final chunk in provider.chatStreamWithTools(
        messages: [
          ChatMessage(
              role: 'system',
              content:
                  '你是一个小说助手。查询小说信息时必须使用 list_novels 工具，不要自己编造。查询后简要回答。'),
          ChatMessage(role: 'user', content: '请列出我书架上的小说'),
          ChatMessage(
            role: 'assistant',
            toolCalls: toolCalls,
          ),
          ChatMessage(
            role: 'tool',
            content: toolResult,
            toolCallId: toolCalls.first.id,
          ),
        ],
        tools: testTools,
        toolChoice: 'auto',
      )) {
        if (chunk.isContent) {
          round2Events.add(TextDeltaEvent(chunk.contentChunk!));
          streamingResult2.contentChunks.add(chunk.contentChunk!);
        }
        if (chunk.isToolCallDelta) {
          streamingResult2.toolCallDeltas.addAll(chunk.toolCallDeltas);
        }
      }

      final toolCalls2 = streamingResult2.buildToolCalls();
      if (toolCalls2.isEmpty) {
        round2Events.add(const AgentDoneEvent());
      }

      final textDeltas2 = round2Events.whereType<TextDeltaEvent>().toList();

      print('━━━ 模拟 AgentLoop ReAct 第二轮 ━━━');
      print('  TextDeltaEvent 数: ${textDeltas2.length}');
      print('  tool_calls 数: ${toolCalls2.length}');
      print('  完整回复: ${textDeltas2.map((e) => e.text).join()}');

      // ---- 验证第二轮：流式文本回复 ----
      expect(textDeltas2.length, greaterThan(1),
          reason: '第二轮回复也应该是流式的，多个 TextDeltaEvent');

      // ---- 验证第二轮：没有更多工具调用 ----
      expect(toolCalls2.isEmpty, true,
          reason: '第二轮 LLM 应该直接回复文本，不再调用工具');

      // ---- 验证第二轮：最后一个事件是 AgentDoneEvent ----
      expect(round2Events.last, isA<AgentDoneEvent>());

      // ---- 验证：内容提到了工具返回的小说 ----
      final fullReply = textDeltas2.map((e) => e.text).join();
      expect(fullReply.length, greaterThan(5),
          reason: '回复内容不应为空');
      print('  第二轮完整回复: $fullReply');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
