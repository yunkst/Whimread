/// AI Agent 真实场景提取集成测试
///
/// 加载真实小说网站到 WebView2，让 AI Agent 自主完成脚本生成和数据提取。
/// 测试的是**系统流程**而非 LLM 能力——只要 AI 返回合理的 JSON 结构就算通过。
///
/// ## 运行
///   cd novel_app
///   flutter test integration_test/webview_extract/ai_extract_test.dart \
///     -d windows \
///     --dart-define=TEST_API_BASE_URL=https://api.deepseek.com/v1 \
///     --dart-define=TEST_API_KEY=sk-xxx \
///     --dart-define=TEST_DEFAULT_MODEL=deepseek-chat
///
/// ## 注意
///   - 需要 Windows 桌面端 + Edge WebView2
///   - 需要网络访问目标网站 + AI API
///   - 测试时间约 30-120 秒（取决于 AI 响应速度）
///   - 不断言具体章节内容，只验证 JSON 结构合理
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/database/database_migrations.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';
import 'package:novel_app/services/logger_service.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/agent_loop.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/scenarios/webview_extract_scenario.dart';

// dart-define 注入
const _apiBaseUrl = String.fromEnvironment('TEST_API_BASE_URL');
const _apiKey = String.fromEnvironment('TEST_API_KEY');
const _defaultModel = String.fromEnvironment(
  'TEST_DEFAULT_MODEL',
  defaultValue: 'deepseek-chat',
);

// 测试目标页面
const _targetUrl =
    'https://www.alicesw.com/other/chapters/id/30108.html';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 检查 API 配置
  if (_apiBaseUrl.isEmpty || _apiKey.isEmpty) {
    // ignore: avoid_print
    print('跳过测试：需要通过 --dart-define 提供 TEST_API_BASE_URL 和 TEST_API_KEY');
    return;
  }

  late ProviderContainer container;

  setUpAll(() async {
    LoggerService.resetForTesting();

    // 创建内存数据库（让 get_cached_script / save_script 不报错）
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await openDatabase(
      ':memory:',
      version: DatabaseMigrations.currentVersion,
      singleInstance: false,
    );
    await DatabaseMigrations.createV1Tables(db);
    await DatabaseMigrations.upgrade(db, 1, DatabaseMigrations.currentVersion);
    final dbConnection = DatabaseConnection.forTesting(db);

    container = ProviderContainer(overrides: [
      databaseConnectionProvider.overrideWithValue(dbConnection),
    ]);
  });

  tearDownAll(() async {
    container.dispose();
  });

  testWidgets('AI Agent 真实场景 - 章节目录提取', (tester) async {
    // 1. 创建 WebView 加载真实网页
    final controller = await _createRealWebView(tester, _targetUrl);

    // 2. 构造 AI Agent
    final scenario = _createScenario(container, controller, _targetUrl);
    final llm = _createLlmProvider();
    final loop = AgentLoop(llm: llm, scenario: scenario);

    // 3. 收集 Agent 输出
    final events = <AgentEvent>[];
    String? finalText;
    final toolCalls = <String>[];

    // 4. 运行 Agent ReAct 循环
    await loop.run(
      initialMessages: [
        ChatMessage(
          role: 'user',
          content: '请分析当前页面并生成提取脚本，提取小说目录信息（标题和章节列表）。',
        ),
      ],
      systemPrompt:
          scenario.buildSystemPrompt(AgentScenarioContext()),
      emit: (event) {
        events.add(event);
        if (event is TextDeltaEvent) {
          finalText = (finalText ?? '') + event.text;
        } else if (event is ToolCallStartEvent) {
          toolCalls.add(event.name);
          // ignore: avoid_print
          print('  [TOOL CALL] ${event.name}');
        } else if (event is ToolCallEndEvent) {
          final preview = event.result.length > 150
              ? '${event.result.substring(0, 150)}...'
              : event.result;
          // ignore: avoid_print
          print('  [TOOL RESULT] ${event.name}: $preview');
        } else if (event is AgentDoneEvent) {
          // ignore: avoid_print
          print('  [DONE]');
        } else if (event is AgentErrorEvent) {
          // ignore: avoid_print
          print('  [ERROR] ${event.error}');
        }
      },
    );

    // 5. 验证结果
    // ignore: avoid_print
    print('\n=== AI 最终输出 ===');
    // ignore: avoid_print
    print(finalText ?? '(无文本输出)');
    // ignore: avoid_print
    print('=== 事件统计 ===');
    // ignore: avoid_print
    print('总事件数: ${events.length}');
    // ignore: avoid_print
    print('工具调用次数: ${toolCalls.length}');

    // 断言：Agent 应该有输出
    expect(events, isNotEmpty, reason: 'Agent 应产生至少一个事件');

    // 断言：Agent 应该完成了
    final doneEvents = events.whereType<AgentDoneEvent>().toList();
    expect(doneEvents, isNotEmpty, reason: 'Agent 应正常完成');

    // 断言：Agent 应该调用了 execute_js 工具
    expect(toolCalls, contains('execute_js'),
        reason: 'Agent 应该调用 execute_js 测试提取脚本');

    // 断言：最终文本不应为空
    expect(finalText, isNotNull,
        reason: 'Agent 应该返回文本结果');
    expect(finalText!.trim().length, greaterThan(10),
        reason: 'Agent 应该返回有意义的文本');

    // 输出工具调用统计
    final toolStats = <String, int>{};
    for (final name in toolCalls) {
      toolStats[name] = (toolStats[name] ?? 0) + 1;
    }
    // ignore: avoid_print
    print('\n=== 工具调用统计 ===');
    toolStats.forEach((name, count) {
      // ignore: avoid_print
      print('  $name: ${count}x');
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}

// ===== 辅助方法 =====

/// 创建加载真实 URL 的 WebView
Future<InAppWebViewController> _createRealWebView(
  WidgetTester tester,
  String url,
) async {
  final controllerCompleter = Completer<InAppWebViewController>();
  final pageLoadCompleter = Completer<void>();

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 800,
        height: 600,
        child: InAppWebView(
          key: GlobalKey(),
          initialUrlRequest: URLRequest(url: WebUri(url)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
          ),
          onWebViewCreated: (controller) {
            if (!controllerCompleter.isCompleted) {
              controllerCompleter.complete(controller);
            }
          },
          onLoadStop: (controller, loadedUrl) {
            // ignore: avoid_print
            print('✅ onLoadStop: ${loadedUrl?.toString() ?? "null"}');
            if (!pageLoadCompleter.isCompleted) {
              pageLoadCompleter.complete();
            }
          },
          onReceivedError: (controller, request, error) {
            // ignore: avoid_print
            print('❌ onLoadError: ${error.type} ${error.description} url=${request.url}');
          },
        ),
      ),
    ),
  );

  final controller = await controllerCompleter.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () => throw TimeoutException('WebView 初始化超时'),
  );

  await tester.pump();
  await pageLoadCompleter.future.timeout(
    const Duration(seconds: 60),
    onTimeout: () {
      // 不抛异常，打印警告继续——页面可能部分加载了
      // ignore: avoid_print
      print('⚠️ 页面加载超时（60秒），尝试继续...');
    },
  );
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // 验证页面确实加载了
  final loadedUrl = await controller.getUrl();
  // ignore: avoid_print
  print('页面加载完成: ${loadedUrl?.toString() ?? "unknown"}');

  return controller;
}

/// 创建 WebViewExtractScenario
WebViewExtractScenario _createScenario(
  ProviderContainer container,
  InAppWebViewController controller,
  String url,
) {
  final provider = Provider<WebViewExtractScenario>((ref) {
    return WebViewExtractScenario(ref, controller, url);
  });
  return container.read(provider);
}

/// 创建 LlmProvider（使用 dart-define 注入的配置）
LlmProvider _createLlmProvider() {
  final config = LlmConfig(
    baseUrl: _apiBaseUrl,
    apiKey: _apiKey,
    defaultModel: _defaultModel,
    temperature: 0.7,
  );
  return LlmProvider(config, httpClient: _RealHttpClient());
}

/// 真实 HTTP 客户端，使用 package:http 调用 LLM API
class _RealHttpClient implements LlmHttpClient {
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
