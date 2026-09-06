/// DSL 引擎集成测试（命令行版本）
///
/// 使用真实 LLM API 测试 DSL 引擎的完整工作流执行。
/// 直接 import 项目中的真实 DSL 引擎代码，不依赖 Flutter 框架。
///
/// 运行方式:
///   cd novel_app
///   dart run tool/dsl_integration_test.dart
///
/// 前置条件:
///   - 网络连接正常
///   - API 服务可用
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:novel_app/services/dsl_engine/condition_processor.dart';
import 'package:novel_app/services/dsl_engine/dsl_parser.dart';
import 'package:novel_app/services/dsl_engine/graph_engine.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';
import 'package:novel_app/services/dsl_engine/models/variable_pool.dart';
import 'package:novel_app/services/dsl_engine/real_llm_executor.dart';
import 'package:novel_app/services/dsl_engine/template_renderer.dart';

// ============================================================================
// 配置
// ============================================================================

const apiBaseUrl = String.fromEnvironment('TEST_API_BASE_URL');
const apiKey = String.fromEnvironment('TEST_API_KEY');
const defaultModel = String.fromEnvironment('TEST_DEFAULT_MODEL', defaultValue: 'deepseek-chat');

// ============================================================================
// 修复版 HTTP 客户端
// ============================================================================
//
// 项目自带的 IoLlmHttpClient 使用 dart:io.HttpClient + request.write(body)
// 这种方式对中文字符串会失败（write 默认按 latin1 编码）。
//
// 这里实现一个基于 package:http 的等价实现，作为 LlmHttpClient 的注入。
// 测试完后建议在生产代码中修复 IoLlmHttpClient（改用 request.add(utf8.encode(body))）。
//

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
// 测试入口
// ============================================================================

void main() async {
  print('╔══════════════════════════════════════════════════════════════════╗');
  print('║        DSL 引擎集成测试（真实 API + 真实代码）                    ║');
  print('╠══════════════════════════════════════════════════════════════════╣');
  print('║  API:  $apiBaseUrl');
  print('║  模型: $defaultModel');
  print('╚══════════════════════════════════════════════════════════════════╝');

  int passed = 0;
  int failed = 0;

  // -- 测试 1: LLM Provider 阻塞调用 --
  if (await test1_blockingLlm()) {
    passed++;
  } else {
    failed++;
  }

  // -- 测试 2: LLM Provider 流式调用 --
  if (await test2_streamingLlm()) {
    passed++;
  } else {
    failed++;
  }

  // -- 测试 3: RealLlmExecutor 阻塞 --
  if (await test3_realLlmBlocking()) {
    passed++;
  } else {
    failed++;
  }

  // -- 测试 4: RealLlmExecutor 流式 --
  if (await test4_realLlmStreaming()) {
    passed++;
  } else {
    failed++;
  }

  // -- 测试 5: creater.yml E2E (cmd=特写) --
  if (await test5_createrE2E_closeup()) {
    passed++;
  } else {
    failed++;
  }

  // -- 测试 6: creater.yml E2E (cmd=总结) --
  if (await test6_createrE2E_summary()) {
    passed++;
  } else {
    failed++;
  }

  // -- 测试 7: structured_info.yml E2E (cmd=生成) --
  if (await test7_structuredInfoE2E()) {
    passed++;
  } else {
    failed++;
  }

  print('');
  print('╔══════════════════════════════════════════════════════════════════╗');
  print('║  结果: $passed 通过, $failed 失败                                     ║');
  print('╚══════════════════════════════════════════════════════════════════╝');
}

// ============================================================================
// 辅助函数
// ============================================================================

/// 读取 YAML 文件（用 File 替代 rootBundle）
String loadYaml(String assetPath) {
  final file = File(assetPath);
  if (!file.existsSync()) {
    throw Exception('文件不存在: $assetPath (请确保在 novel_app 目录下运行)');
  }
  return file.readAsStringSync();
}

/// 创建 RealLlmExecutor（用修复版 HTTP 客户端）
RealLlmExecutor createExecutor() {
  return RealLlmExecutor(
    provider: LlmProvider(
      LlmConfig(
        baseUrl: apiBaseUrl,
        apiKey: apiKey,
        defaultModel: defaultModel,
      ),
      httpClient: FixedHttpClient(),
    ),
    defaultModel: defaultModel,
  );
}

/// 注入 inputs 到 VariablePool
void injectInputs(WorkflowGraph graph, VariablePool pool, Map<String, dynamic> inputs) {
  final startNode = graph.rootNode;
  if (startNode == null) return;

  for (final entry in inputs.entries) {
    pool.add([startNode.id, entry.key], entry.value);
  }

  // 为未提供的变量设置默认值
  final variables = startNode.data['variables'] as List?;
  if (variables != null) {
    for (final v in variables) {
      if (v is! Map) continue;
      final name = v['variable']?.toString();
      if (name == null || inputs.containsKey(name)) continue;
      final defaultVal = v['default']?.toString();
      if (defaultVal != null && defaultVal.isNotEmpty) {
        pool.add([startNode.id, name], defaultVal);
      } else {
        pool.add([startNode.id, name], '');
      }
    }
  }
}

/// 节点执行器（与 DslExecutor._nodeExecutor 相同逻辑）
Future<NodeRunResult> nodeExecutor(
  DslNode node,
  VariablePool pool,
  RealLlmExecutor realLlm, {
  void Function(String chunk)? onChunk,
}) async {
  final renderer = TemplateRenderer();

  switch (node.type) {
    case NodeType.start:
      return NodeRunResult(
        nodeId: node.id,
        status: NodeExecutionStatus.succeeded,
        outputs: const {},
      );

    case NodeType.end:
      final outputsConfig = node.data['outputs'] as List?;
      final result = <String, dynamic>{};
      if (outputsConfig != null) {
        for (final out in outputsConfig) {
          if (out is! Map) continue;
          final varName = out['variable']?.toString() ?? '';
          final selector = out['value_selector'] as List?;
          if (varName.isNotEmpty && selector != null) {
            final path = selector.map((e) => e.toString()).toList();
            final segment = pool.get(path);
            result[varName] = segment?.toObject() ?? '';
          }
        }
      }
      return NodeRunResult(
        nodeId: node.id,
        status: NodeExecutionStatus.succeeded,
        outputs: result,
      );

    case NodeType.ifElse:
      final processor = ConditionProcessor();
      final cases = DslParser().parseCases(node.data['cases']);
      for (final caseData in cases) {
        final r = processor.processConditions(
          variablePool: pool,
          conditions: caseData.conditions,
          operator: caseData.logicalOperator,
        );
        if (r.finalResult) {
          return NodeRunResult(
            nodeId: node.id,
            status: NodeExecutionStatus.succeeded,
            selectedHandle: caseData.caseId,
            outputs: {'selected_case_id': caseData.caseId},
          );
        }
      }
      return NodeRunResult(
        nodeId: node.id,
        status: NodeExecutionStatus.succeeded,
        selectedHandle: 'false',
        outputs: {'selected_case_id': 'false'},
      );

    case NodeType.templateTransform:
      final template = node.data['template']?.toString() ?? '';
      final variables = node.data['variables'] as List?;
      String result;
      if (variables is List && variables.isNotEmpty) {
        result = renderer.renderTemplateTransform(
          pool,
          template: template,
          variables: variables.cast<Map<String, dynamic>>(),
        );
      } else {
        result = renderer.convertTemplate(pool, template);
      }
      return NodeRunResult(
        nodeId: node.id,
        status: NodeExecutionStatus.succeeded,
        outputs: {'output': result},
      );

    case NodeType.variableAggregator:
      final variables = node.data['variables'] as List?;
      if (variables != null) {
        for (final v in variables) {
          List<String> path;
          if (v is Map) {
            final selector = v['value_selector'];
            if (selector is! List) continue;
            path = selector.map((e) => e.toString()).toList();
          } else if (v is List) {
            path = v.map((e) => e.toString()).toList();
            if (path.length < 2) continue;
          } else {
            continue;
          }
          final segment = pool.get(path);
          if (segment != null) {
            final val = segment.toObject();
            if (val != null && val.toString().isNotEmpty) {
              return NodeRunResult(
                nodeId: node.id,
                status: NodeExecutionStatus.succeeded,
                outputs: {'output': val},
              );
            }
          }
        }
      }
      return NodeRunResult(
        nodeId: node.id,
        status: NodeExecutionStatus.succeeded,
        outputs: {'output': ''},
      );

    case NodeType.llm:
      if (onChunk != null) {
        return realLlm.executeStreaming(node, pool, onChunk: onChunk);
      }
      return realLlm.executeBlocking(node, pool);

    case NodeType.unknown:
      return NodeRunResult(
        nodeId: node.id,
        status: NodeExecutionStatus.succeeded,
        outputs: const {'output': ''},
      );
  }
}

// ============================================================================
// 测试 1: LLM Provider 阻塞调用
// ============================================================================

Future<bool> test1_blockingLlm() async {
  print('');
  print('── 测试 1: LLM Provider 阻塞调用 ──');

  try {
    final provider = LlmProvider(
      LlmConfig(baseUrl: apiBaseUrl, apiKey: apiKey, defaultModel: defaultModel),
      httpClient: FixedHttpClient(),
    );

    final response = await provider.chat(
      messages: [
        ChatMessage(role: 'user', content: '请用一句话描述日落场景。'),
      ],
      maxTokens: 100,
    );

    if (response.isEmpty || response.length < 5) {
      print('   ❌ 响应为空或过短: "$response"');
      return false;
    }

    print('   ✅ 响应: $response');
    return true;
  } catch (e) {
    print('   ❌ 异常: $e');
    return false;
  }
}

// ============================================================================
// 测试 2: LLM Provider 流式调用
// ============================================================================

Future<bool> test2_streamingLlm() async {
  print('');
  print('── 测试 2: LLM Provider 流式调用 ──');

  try {
    final provider = LlmProvider(
      LlmConfig(baseUrl: apiBaseUrl, apiKey: apiKey, defaultModel: defaultModel),
      httpClient: FixedHttpClient(),
    );

    final chunks = <String>[];
    await for (final chunk in provider.chatStream(
      messages: [
        ChatMessage(role: 'user', content: '请用三句话描述古代宫殿。'),
      ],
      maxTokens: 200,
    )) {
      chunks.add(chunk);
    }

    final fullText = chunks.join();
    if (fullText.isEmpty) {
      print('   ❌ 流式响应为空');
      return false;
    }

    print('   ✅ ${chunks.length} 个 chunk, 内容: $fullText');
    return true;
  } catch (e) {
    print('   ❌ 异常: $e');
    return false;
  }
}

// ============================================================================
// 测试 3: RealLlmExecutor 阻塞
// ============================================================================

Future<bool> test3_realLlmBlocking() async {
  print('');
  print('── 测试 3: RealLlmExecutor 阻塞 ──');

  try {
    final yaml = loadYaml('assets/dsl/creater.yml');
    final parser = DslParser();
    final graph = parser.parseGraphConfig(yaml);

    final llmNode = graph.nodes.firstWhere((n) => n.type == NodeType.llm);
    final pool = VariablePool();
    injectInputs(graph, pool, {
      'cmd': '特写',
      'user_input': '描写一个古代将军在夕阳下回望战场的情景',
      'background_setting': '古代战争背景',
      'current_chapter_content': '将军站在山丘上',
    });

    final executor = createExecutor();
    final result = await executor.executeBlocking(llmNode, pool);

    if (result.status != NodeExecutionStatus.succeeded) {
      print('   ❌ 执行失败: ${result.error}');
      return false;
    }

    final text = result.outputs['text'] as String? ?? '';
    if (text.isEmpty) {
      print('   ❌ 输出为空');
      return false;
    }

    print('   ✅ 输出 (前 200 字符): ${text.substring(0, math.min(200, text.length))}...');
    return true;
  } catch (e) {
    print('   ❌ 异常: $e');
    return false;
  }
}

// ============================================================================
// 测试 4: RealLlmExecutor 流式
// ============================================================================

Future<bool> test4_realLlmStreaming() async {
  print('');
  print('── 测试 4: RealLlmExecutor 流式 ──');

  try {
    final yaml = loadYaml('assets/dsl/creater.yml');
    final parser = DslParser();
    final graph = parser.parseGraphConfig(yaml);

    final llmNode = graph.nodes.firstWhere((n) => n.type == NodeType.llm);
    final pool = VariablePool();
    injectInputs(graph, pool, {
      'cmd': '特写',
      'user_input': '描写雨夜中独行的剑客',
      'background_setting': '武侠世界',
      'current_chapter_content': '剑客在雨中行走',
    });

    final executor = createExecutor();
    final chunks = <String>[];
    final result = await executor.executeStreaming(
      llmNode,
      pool,
      onChunk: (chunk) => chunks.add(chunk),
    );

    if (result.status != NodeExecutionStatus.succeeded) {
      print('   ❌ 执行失败: ${result.error}');
      return false;
    }

    final fullText = chunks.join();
    if (fullText.isEmpty) {
      print('   ❌ 输出为空');
      return false;
    }

    print('   ✅ ${chunks.length} 个 chunk, 内容 (前 200 字符): ${fullText.substring(0, math.min(200, fullText.length))}...');
    return true;
  } catch (e) {
    print('   ❌ 异常: $e');
    return false;
  }
}

// ============================================================================
// 测试 5: creater.yml E2E (cmd=特写)
// ============================================================================

Future<bool> test5_createrE2E_closeup() async {
  print('');
  print('── 测试 5: creater.yml E2E (cmd=特写) ──');

  try {
    final yaml = loadYaml('assets/dsl/creater.yml');
    final parser = DslParser();
    final graph = parser.parseGraphConfig(yaml);
    print('   解析: ${graph.nodes.length} 个节点, ${graph.edges.length} 条边');

    final pool = VariablePool();
    injectInputs(graph, pool, {
      'cmd': '特写',
      'user_input': '描写一个古代将军在夕阳下回望战场的情景',
      'background_setting': '古代战争背景，王朝末年',
      'current_chapter_content': '将军站在山丘上，望着远方的战场',
    });

    final realLlm = createExecutor();
    final engine = GraphEngine(
      graph: graph,
      variablePool: pool,
      nodeExecutor: (node, p) => nodeExecutor(node, p, realLlm),
    );

    final events = await engine.run().toList();

    final lastEvent = events.last;
    if (lastEvent is! GraphRunSucceededEvent &&
        lastEvent is! GraphRunPartialSucceededEvent) {
      print('   ❌ 工作流未正常完成: ${lastEvent.runtimeType}');
      return false;
    }

    final ifElse = events
        .whereType<NodeRunSucceededEvent>()
        .where((e) => e.nodeId == '1759151925879');
    if (ifElse.isEmpty || ifElse.first.selectedHandle != 'false') {
      print('   ❌ if-else 分支不正确');
      return false;
    }

    final llmEvents = events
        .whereType<NodeRunSucceededEvent>()
        .where((e) => e.nodeId == '1759151715295');
    if (llmEvents.isEmpty) {
      print('   ❌ LLM 节点未执行');
      return false;
    }

    final llmOutput = llmEvents.first.outputs['text'] as String? ?? '';
    if (llmOutput.isEmpty) {
      print('   ❌ LLM 输出为空');
      return false;
    }

    print('   ✅ if-else: false → LLM 输出 (前 200 字符): ${llmOutput.substring(0, math.min(200, llmOutput.length))}...');
    return true;
  } catch (e) {
    print('   ❌ 异常: $e');
    return false;
  }
}

// ============================================================================
// 测试 6: creater.yml E2E (cmd=总结)
// ============================================================================

Future<bool> test6_createrE2E_summary() async {
  print('');
  print('── 测试 6: creater.yml E2E (cmd=总结) ──');

  try {
    final yaml = loadYaml('assets/dsl/creater.yml');
    final parser = DslParser();
    final graph = parser.parseGraphConfig(yaml);

    final pool = VariablePool();
    injectInputs(graph, pool, {
      'cmd': '总结',
      'current_chapter_content': '将军在战场上与敌军激战三天三夜，最终以少胜多，但付出了惨重的代价。战后他独自站在山丘上，望着夕阳下的战场，心中充满了对逝去战友的思念。',
    });

    final realLlm = createExecutor();
    final engine = GraphEngine(
      graph: graph,
      variablePool: pool,
      nodeExecutor: (node, p) => nodeExecutor(node, p, realLlm),
    );

    final events = await engine.run().toList();

    final lastEvent = events.last;
    if (lastEvent is! GraphRunSucceededEvent &&
        lastEvent is! GraphRunPartialSucceededEvent) {
      print('   ❌ 工作流未正常完成');
      return false;
    }

    final ifElse = events
        .whereType<NodeRunSucceededEvent>()
        .where((e) => e.nodeId == '1759151925879');
    if (ifElse.isEmpty ||
        ifElse.first.selectedHandle != 'd2112989-3424-433a-8ba6-ce2e3245bff1') {
      print('   ❌ if-else 未选总结分支: ${ifElse.firstOrNull?.selectedHandle}');
      return false;
    }

    final llmEvents = events
        .whereType<NodeRunSucceededEvent>()
        .where((e) => e.nodeId == '1759151715295');
    final llmOutput = llmEvents.firstOrNull?.outputs['text'] as String? ?? '';
    if (llmOutput.isEmpty) {
      print('   ❌ LLM 输出为空');
      return false;
    }

    print('   ✅ if-else: 总结 → LLM 输出 (前 200 字符): ${llmOutput.substring(0, math.min(200, llmOutput.length))}...');
    return true;
  } catch (e) {
    print('   ❌ 异常: $e');
    return false;
  }
}

// ============================================================================
// 测试 7: structured_info.yml E2E (cmd=生成)
// ============================================================================

Future<bool> test7_structuredInfoE2E() async {
  print('');
  print('── 测试 7: structured_info.yml E2E (cmd=生成) ──');

  try {
    final yaml = loadYaml('assets/dsl/structured_info.yml');
    final parser = DslParser();
    final graph = parser.parseGraphConfig(yaml);
    print('   解析: ${graph.nodes.length} 个节点, ${graph.edges.length} 条边');

    final pool = VariablePool();
    injectInputs(graph, pool, {
      'cmd': '生成',
      'user_input': '一个年轻剑客在雨夜中独行的场景',
      'background_setting': '武侠世界',
    });

    final realLlm = createExecutor();
    final engine = GraphEngine(
      graph: graph,
      variablePool: pool,
      nodeExecutor: (node, p) => nodeExecutor(node, p, realLlm),
    );

    final events = await engine.run().toList();

    final lastEvent = events.last;
    if (lastEvent is! GraphRunSucceededEvent &&
        lastEvent is! GraphRunPartialSucceededEvent) {
      print('   ❌ 工作流未正常完成: ${lastEvent.runtimeType}');
      return false;
    }

    final llmEvents = events
        .whereType<NodeRunSucceededEvent>()
        .where((e) {
          final node = graph.nodes.firstWhere(
            (n) => n.id == e.nodeId,
            orElse: () => DslNode(
              id: '', type: NodeType.unknown, title: '', data: const {},
            ),
          );
          return node.type == NodeType.llm;
        });

    if (llmEvents.isEmpty) {
      print('   ❌ 没有 LLM 节点被执行');
      return false;
    }

    print('   ✅ 执行了 ${llmEvents.length} 个 LLM 节点:');
    for (final e in llmEvents) {
      final text = e.outputs['text']?.toString() ?? '';
      print('      节点 ${e.nodeId}: ${text.substring(0, math.min(100, text.length))}...');
    }
    return true;
  } catch (e) {
    print('   ❌ 异常: $e');
    return false;
  }
}
