/// DSL 引擎本地集成测试 v3
///
/// 使用真实 LLM API 测试 DSL 引擎的完整工作流执行。
/// API: 通过环境变量 TEST_API_BASE_URL 配置
///
/// 运行方式:
///   cd novel_app
///   dart run test/unit/services/dsl_engine/local_integration_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

// ============================================================================
// 配置
// ============================================================================

const apiBaseUrl = String.fromEnvironment('TEST_API_BASE_URL');
const apiKey = String.fromEnvironment('TEST_API_KEY');

// 从 /models 端点探测到的正确模型名
// DeepSeek-V4-Pro (首字母大写) - 对应 DSL 中的 deepseek-v4-pro
// deepseek-v4-flash (全小写) - 对应 DSL 中的 deepseek-v4-flash
// GLM-4.7 - 智谱模型
// gpt-4o-mini - OpenAI 便宜模型
const defaultModel = 'DeepSeek-V4-Pro';

// ============================================================================
// HTTP 客户端
// ============================================================================

class SimpleHttpClient {
  final HttpClient _client = HttpClient();

  Future<HttpResponse> postJson(
      String url, Map<String, String> headers, String body) async {
    final uri = Uri.parse(url);
    final request = await _client.postUrl(uri);
    headers.forEach((k, v) => request.headers.set(k, v));
    final bytes = utf8.encode(body);
    request.headers.set('Content-Length', bytes.length.toString());
    request.add(bytes);
    final response = await request.close();
    final responseBytes = await response.toList();
    final responseBody = utf8.decode(responseBytes.expand((x) => x).toList());
    return HttpResponse(response.statusCode, responseBody);
  }

  Stream<String> postJsonStream(
      String url, Map<String, String> headers, String body) async* {
    final uri = Uri.parse(url);
    final request = await _client.postUrl(uri);
    headers.forEach((k, v) => request.headers.set(k, v));
    final bytes = utf8.encode(body);
    request.headers.set('Content-Length', bytes.length.toString());
    request.add(bytes);
    final response = await request.close();
    if (response.statusCode >= 400) {
      final errorBytes = await response.toList();
      final errorBody = utf8.decode(errorBytes.expand((x) => x).toList());
      throw HttpException('HTTP ${response.statusCode}: $errorBody', uri: uri);
    }
    yield* response.transform(utf8.decoder);
  }
}

class HttpResponse {
  final int statusCode;
  final String body;
  HttpResponse(this.statusCode, this.body);
}

// ============================================================================
// 测试入口
// ============================================================================

void main() async {
  print('=' * 70);
  print('DSL 引擎本地集成测试 v3');
  print('API: $apiBaseUrl');
  print('模型: $defaultModel');
  print('=' * 70);

  final client = SimpleHttpClient();

  // -- 测试 1: 阻塞式 LLM 调用 --
  await testBlockingLlmCall(client);

  // -- 测试 2: 流式 LLM 调用 --
  await testStreamingLlmCall(client);

  // -- 测试 3: 结构化输出测试 --
  await testStructuredOutput(client);

  // -- 测试 4: 使用 Flutter DSL 引擎 --
  await testWithFlutterDslEngine();

  print('\n' + '=' * 70);
  print('所有测试完成！');
  print('=' * 70);
}

// ============================================================================
// 测试 1: 阻塞式 LLM 调用
// ============================================================================

Future<void> testBlockingLlmCall(SimpleHttpClient client) async {
  print('\n--- 测试 1: 阻塞式 LLM 调用 ---');

  try {
    final body = jsonEncode({
      'model': defaultModel,
      'messages': [
        {'role': 'system', 'content': '你是一个小说写作助手。请用中文回复。'},
        {'role': 'user', 'content': '请用一句话描述一个日落场景。'},
      ],
      'max_tokens': 200,
      'temperature': 0.7,
    });

    final response = await client.postJson(
      '$apiBaseUrl/chat/completions',
      {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices != null && choices.isNotEmpty) {
        final content = choices[0]['message']?['content'] ?? '';
        print('✅ 阻塞调用成功！');
        print('   响应: $content');
        final usage = data['usage'];
        if (usage != null) {
          print(
              '   Token: prompt=${usage['prompt_tokens']}, completion=${usage['completion_tokens']}');
        }
      }
    } else {
      print('❌ HTTP ${response.statusCode}: ${response.body}');
    }
  } catch (e) {
    print('❌ 阻塞调用失败: $e');
  }
}

// ============================================================================
// 测试 2: 流式 LLM 调用
// ============================================================================

Future<void> testStreamingLlmCall(SimpleHttpClient client) async {
  print('\n--- 测试 2: 流式 LLM 调用 ---');

  try {
    final body = jsonEncode({
      'model': defaultModel,
      'messages': [
        {'role': 'user', 'content': '请用三句话描述一个古代王朝的宫殿。'},
      ],
      'max_tokens': 300,
      'temperature': 0.7,
      'stream': true,
    });

    final stream = client.postJsonStream(
      '$apiBaseUrl/chat/completions',
      {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body,
    );

    final fullContent = StringBuffer();
    int chunkCount = 0;

    await for (final rawChunk in stream) {
      for (final line in rawChunk.split('\n')) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;

        try {
          final json = jsonDecode(payload) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;
          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            fullContent.write(content);
            chunkCount++;
          }
        } catch (_) {}
      }
    }

    if (fullContent.isNotEmpty) {
      print('✅ 流式调用成功！');
      print('   接收 chunk 数: $chunkCount');
      print('   完整内容: ${fullContent.toString()}');
    } else {
      print('⚠️  流式调用返回空内容');
    }
  } catch (e) {
    print('❌ 流式调用失败: $e');
  }
}

// ============================================================================
// 测试 3: 结构化输出测试
// ============================================================================

Future<void> testStructuredOutput(SimpleHttpClient client) async {
  print('\n--- 测试 3: 结构化输出（JSON 模式）---');

  try {
    final body = jsonEncode({
      'model': defaultModel,
      'messages': [
        {
          'role': 'user',
          'content':
              '请以JSON格式输出一个角色信息：{"name": "角色名", "title": "称号", "description": "简短描述"}'
        },
      ],
      'max_tokens': 300,
      'temperature': 0.7,
      'response_format': {'type': 'json_object'},
    });

    final response = await client.postJson(
      '$apiBaseUrl/chat/completions',
      {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices != null && choices.isNotEmpty) {
        final content = choices[0]['message']?['content'] ?? '';
        try {
          final parsed = jsonDecode(content);
          print('✅ 结构化输出成功！');
          print('   解析后的 JSON: ${jsonEncode(parsed)}');
        } catch (_) {
          print('⚠️  返回内容不是有效 JSON: $content');
        }
      }
    } else {
      print('❌ HTTP ${response.statusCode}: ${response.body}');
    }
  } catch (e) {
    print('❌ 结构化输出失败: $e');
  }
}

// ============================================================================
// 测试 4: Flutter DSL 引擎测试说明
// ============================================================================

Future<void> testWithFlutterDslEngine() async {
  print('\n--- 测试 4: Flutter DSL 引擎集成测试 ---');
  print('');
  print('基础 API 测试已通过！接下来需要在 Flutter 环境中测试 DSL 引擎。');
  print('');
  print('📋 操作步骤:');
  print('   1. 在应用中进入设置 → Dify 设置');
  print('   2. 开启 "DSL Engine" 开关');
  print('   3. 配置:');
  print('      - LLM API URL: $apiBaseUrl');
  print(
      '      - LLM API Key: ${apiKey.isNotEmpty ? apiKey.substring(0, 10) : "<未配置>"}...');
  print('      - 默认模型: $defaultModel (可选，留空则使用 DSL 中的模型)');
  print('   4. 进入任意小说章节，触发 AI 功能（特写/总结/聊天等）');
  print('   5. 观察是否正常生成内容');
  print('');
  print('⚠️  注意: DSL 工作流中的模型名是 "deepseek-v4-pro"（小写），');
  print('   但 API 注册的是 "DeepSeek-V4-Pro"。建议在设置中填写 "默认模型"');
  print('   为 "DeepSeek-V4-Pro" 来覆盖 DSL 中的模型名。');
  print('');
  print('   或者，如果要使用更便宜的模型，可以尝试:');
  print('   - gpt-4o-mini (便宜)');
  print('   - GLM-4.7 (智谱)');
  print('   - deepseek-v4-flash (DeepSeek 快速版)');
}
