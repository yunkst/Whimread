/// LLM Provider 单元测试
///
/// 验证 OpenAI 兼容 LLM Provider 的核心功能：
/// 1. 阻塞式 chat completion
/// 2. SSE 流式 chat completion
/// 3. response_format JSON 模式（structured_output）
/// 4. 配置管理（baseUrl / apiKey / model）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';

void main() {
  group('LlmConfig', () {
    test('默认配置', () {
      final config = LlmConfig();
      expect(config.baseUrl, '');
      expect(config.apiKey, '');
      expect(config.defaultModel, '');
      expect(config.temperature, 0.7);
    });

    test('自定义配置', () {
      final config = LlmConfig(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-test',
        defaultModel: 'deepseek-chat',
        temperature: 0.5,
      );
      expect(config.baseUrl, 'https://api.deepseek.com/v1');
      expect(config.apiKey, 'sk-test');
      expect(config.defaultModel, 'deepseek-chat');
      expect(config.temperature, 0.5);
    });
  });

  group('SSE Parser', () {
    test('解析标准 SSE 流', () {
      const sseData = 'data: {"choices":[{"delta":{"content":"Hello"}}]}\n'
          'data: {"choices":[{"delta":{"content":" world"}}]}\n'
          'data: {"choices":[{"delta":{"content":"!"}}]}\n'
          'data: [DONE]\n';

      final chunks = SseParser.parseSseStreamWithReasoning(sseData).content;
      expect(chunks, ['Hello', ' world', '!']);
    });

    test('解析带空行的 SSE', () {
      const sseData = 'data: {"choices":[{"delta":{"content":"A"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":"B"}}]}\n\n'
          'data: [DONE]\n\n';

      final chunks = SseParser.parseSseStreamWithReasoning(sseData).content;
      expect(chunks, ['A', 'B']);
    });

    test('忽略非 data 行', () {
      const sseData = 'event: message_start\n'
          'data: {"choices":[{"delta":{"content":"X"}}]}\n'
          ': comment line\n'
          'data: [DONE]\n';

      final chunks = SseParser.parseSseStreamWithReasoning(sseData).content;
      expect(chunks, ['X']);
    });

    test('空 delta content → 不产生 chunk', () {
      const sseData = 'data: {"choices":[{"delta":{"content":""}}]}\n'
          'data: {"choices":[{"delta":{"content":"Y"}}]}\n'
          'data: [DONE]\n';

      final chunks = SseParser.parseSseStreamWithReasoning(sseData).content;
      expect(chunks, ['Y']);
    });

    test('delta 缺少 content 字段 → 不产生 chunk', () {
      const sseData = 'data: {"choices":[{"delta":{"role":"assistant"}}]}\n'
          'data: {"choices":[{"delta":{"content":"Z"}}]}\n'
          'data: [DONE]\n';

      final chunks = SseParser.parseSseStreamWithReasoning(sseData).content;
      expect(chunks, ['Z']);
    });

    test('reasoning_content 分离（Dify thinking 格式）', () {
      const sseData =
          'data: {"choices":[{"delta":{"reasoning_content":"thinking..."}}]}\n'
          'data: {"choices":[{"delta":{"content":"answer"}}]}\n'
          'data: [DONE]\n';

      final result = SseParser.parseSseStreamWithReasoning(sseData);
      expect(result.content, ['answer']);
      expect(result.reasoning, ['thinking...']);
    });
  });

  group('ChatMessage', () {
    test('构造 system / user / assistant 消息', () {
      final system = ChatMessage(role: 'system', content: 'You are a writer');
      final user = ChatMessage(role: 'user', content: 'Write a story');
      final assistant = ChatMessage(role: 'assistant', content: 'Here is...');

      expect(system.role, 'system');
      expect(user.role, 'user');
      expect(assistant.role, 'assistant');
    });

    test('toJson 生成 OpenAI 格式', () {
      final msg = ChatMessage(role: 'user', content: 'Hello');
      final json = msg.toJson();
      expect(json, {'role': 'user', 'content': 'Hello'});
    });
  });

  group('LlmProvider request building', () {
    test('阻塞式请求体构建', () {
      final provider = LlmProvider(
          LlmConfig(
            baseUrl: 'https://api.deepseek.com/v1',
            apiKey: 'sk-test',
            defaultModel: 'deepseek-chat',
          ),
          httpClient: _FakeHttpClient());

      final body = provider.buildRequestBody(
        messages: [
          ChatMessage(role: 'system', content: 'You are helpful'),
          ChatMessage(role: 'user', content: 'Hello'),
        ],
        stream: false,
      );

      expect(body['model'], 'deepseek-chat');
      expect(body['stream'], false);
      expect(body['temperature'], 0.7);
      // max_tokens 已移除：请求体不再携带输出长度约束
      expect(body.containsKey('max_tokens'), isFalse);
      expect(body['messages'].length, 2);
    });

    test('流式请求体构建', () {
      final provider = LlmProvider(
          LlmConfig(
            baseUrl: 'https://api.deepseek.com/v1',
            apiKey: 'sk-test',
            defaultModel: 'deepseek-chat',
          ),
          httpClient: _FakeHttpClient());

      final body = provider.buildRequestBody(
        messages: [ChatMessage(role: 'user', content: 'Hello')],
        stream: true,
      );

      expect(body['stream'], true);
    });

    test('覆盖 model 和参数', () {
      final provider = LlmProvider(
          LlmConfig(
            baseUrl: 'https://api.deepseek.com/v1',
            apiKey: 'sk-test',
            defaultModel: 'deepseek-chat',
          ),
          httpClient: _FakeHttpClient());

      final body = provider.buildRequestBody(
        messages: [ChatMessage(role: 'user', content: 'Hello')],
        model: 'deepseek-reasoner',
        temperature: 0.3,
        stream: false,
      );

      expect(body['model'], 'deepseek-reasoner');
      expect(body['temperature'], 0.3);
    });

    test('structured_output: response_format JSON 模式', () {
      final provider = LlmProvider(
          LlmConfig(
            baseUrl: 'https://api.deepseek.com/v1',
            apiKey: 'sk-test',
            defaultModel: 'deepseek-chat',
          ),
          httpClient: _FakeHttpClient());

      final body = provider.buildRequestBody(
        messages: [ChatMessage(role: 'user', content: 'Generate character')],
        stream: false,
        responseFormat: {'type': 'json_object'},
      );

      expect(body['response_format'], {'type': 'json_object'});
    });

    test('tools 缺少 required 时自动补全为空数组（OpenAI 兼容代理兼容）', () {
      // 背景：严格的 OpenAI 兼容代理（new-api / OneAPI / 部分直连 DeepSeek）
      // 要求 function.parameters.required 必须是数组；缺失会被当作 null
      // 报 400 "null is not of type \"array\""。
      // webview_extract 场景的无参工具（get_page_info 等）恰好缺 required 字段，
      // 必须在请求体构造层统一补全。
      final provider = LlmProvider(
          LlmConfig(
            baseUrl: 'https://api.deepseek.com/v1',
            apiKey: 'sk-test',
            defaultModel: 'deepseek-chat',
          ),
          httpClient: _FakeHttpClient());

      final tools = <Map<String, dynamic>>[
        {
          'type': 'function',
          'function': {
            'name': 'get_page_info',
            'description': 'desc',
            'parameters': {
              'type': 'object',
              'properties': <String, dynamic>{},
              // 故意不写 required
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'navigate_to',
            'description': 'desc',
            'parameters': {
              'type': 'object',
              'properties': {
                'url': {'type': 'string'},
              },
              'required': ['url'], // 已有 required，不应被改动
            },
          },
        },
      ];

      final body = provider.buildRequestBody(
        messages: [ChatMessage(role: 'user', content: 'hi')],
        tools: tools,
        toolChoice: 'auto',
      );

      final outTools = body['tools'] as List;
      expect(outTools.length, 2);

      // 缺 required → 补空数组（修复后此断言通过，修复前为 null → 失败）
      final p1 = (outTools[0] as Map)['function']['parameters'] as Map;
      expect(p1['required'], isA<List>());
      expect(p1['required'] as List, isEmpty);

      // 已有 required → 原样保留
      final p2 = (outTools[1] as Map)['function']['parameters'] as Map;
      expect(p2['required'], ['url']);
    });
  });

  group('LlmProvider URL construction', () {
    test('chat completions endpoint', () {
      final provider = LlmProvider(
          LlmConfig(
            baseUrl: 'https://api.deepseek.com/v1',
            apiKey: 'sk-test',
            defaultModel: 'deepseek-chat',
          ),
          httpClient: _FakeHttpClient());

      expect(provider.chatCompletionsUrl,
          'https://api.deepseek.com/v1/chat/completions');
    });

    test('baseUrl 末尾有 / 时去掉冗余', () {
      final provider = LlmProvider(
          LlmConfig(
            baseUrl: 'https://api.deepseek.com/v1/',
            apiKey: 'sk-test',
            defaultModel: 'deepseek-chat',
          ),
          httpClient: _FakeHttpClient());

      expect(provider.chatCompletionsUrl,
          'https://api.deepseek.com/v1/chat/completions');
    });
  });

  group('chatStreamWithTools usage 帧', () {
    test('SSE 末帧 choices=[] + usage → yield hasUsage=true 且无 content', () async {
      // DeepSeek 等网关在末帧附带 usage（choices 常为空），下游 AgentLoop 据此
      // 被动消费 _lastPromptTokens 做压缩判定。
      const sse = 'data: {"choices":[],"usage":{"prompt_tokens":42,'
          '"completion_tokens":10}}\n'
          'data: [DONE]\n';

      final provider = LlmProvider(
        LlmConfig(
          baseUrl: 'https://api.deepseek.com/v1',
          apiKey: 'sk-test',
          defaultModel: 'deepseek-chat',
        ),
        httpClient: _SseHttpClient(sse),
      );

      final chunks = await provider
          .chatStreamWithTools(messages: const [
            ChatMessage(role: 'user', content: 'hi'),
          ])
          .toList();

      expect(chunks, hasLength(1));
      expect(chunks.single.hasUsage, isTrue);
      expect(chunks.single.usage!.promptTokens, 42);
      expect(chunks.single.usage!.completionTokens, 10);
      expect(chunks.single.isContent, isFalse);
      expect(chunks.single.isFinished, isFalse);
    });

    test('SSE 末帧 choices=[finish_reason=stop] + usage → 同时附带', () async {
      // OpenAI 兼容末帧：delta=null（不再更新内容）+ finishReason + usage
      const sse = 'data: {"choices":[{"delta":null,"finish_reason":"stop"}],'
          '"usage":{"prompt_tokens":7}}\n'
          'data: [DONE]\n';

      final provider = LlmProvider(
        LlmConfig(
          baseUrl: 'https://api.deepseek.com/v1',
          apiKey: 'sk-test',
          defaultModel: 'deepseek-chat',
        ),
        httpClient: _SseHttpClient(sse),
      );

      final chunks = await provider
          .chatStreamWithTools(messages: const [
            ChatMessage(role: 'user', content: 'hi'),
          ])
          .toList();

      expect(chunks.single.isFinished, isTrue);
      expect(chunks.single.finishReason, 'stop');
      expect(chunks.single.hasUsage, isTrue);
      expect(chunks.single.usage!.promptTokens, 7);
    });
  });
}

/// 按 SSE 行内容响应的最小 HTTP 客户端（供 usage 测试用）
class _SseHttpClient implements LlmHttpClient {
  final String body;
  _SseHttpClient(this.body);
  @override
  Future<String> postJson(
          String url, Map<String, String> headers, String reqBody) =>
      throw UnimplementedError();
  @override
  Stream<String> postJsonStream(
          String url, Map<String, String> headers, String reqBody) async* {
    yield body;
  }
}

/// 占位 HTTP 客户端：本测试只覆盖请求体构建/URL 拼接，不发真实请求
class _FakeHttpClient implements LlmHttpClient {
  @override
  Future<String> postJson(
          String url, Map<String, String> headers, String body) =>
      throw UnimplementedError();
  @override
  Stream<String> postJsonStream(
          String url, Map<String, String> headers, String body) =>
      throw UnimplementedError();
}
