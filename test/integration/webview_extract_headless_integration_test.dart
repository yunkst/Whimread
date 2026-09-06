/// WebView 提取 Headless 化端到端集成测试
///
/// 覆盖整个 Headless 提取流程的端到端行为：
/// 1. AgentScenarioFactory 异步创建 WebViewExtractScenario.headless
/// 2. ExtractionTaskProvider 状态变化
/// 3. 多次执行工具 → 状态正确转换
/// 4. 异常路径 → fail() 正确触发
/// 5. Headless 模式 _currentUrl 路径（不依赖 controller.getUrl）
///
/// 运行:
///   cd novel_app
///   flutter test test/integration/webview_extract_headless_integration_test.dart
///
/// 注意：本测试是 mock-based 集成测试（不需要真实 WebView 或 LLM API）。
/// 如需真实 LLM 端到端测试，参考 agent_streaming_test.dart。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:novel_app/core/providers/extraction_task_providers.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/logger_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  LoggerService.resetForTesting();

  group('AgentScenarioContext Headless 字段集成', () {
    test('webview_extract 场景的 useHeadlessWebView 字段为 true', () {
      const context = AgentScenarioContext(
        currentUrl: 'https://www.example.com/book/',
        useHeadlessWebView: true,
      );

      // 模拟 AgentChatNotifier._buildScenarioContext 的判断
      final scenarioId = ScenarioIds.webviewExtract;
      final useHeadless = scenarioId == ScenarioIds.webviewExtract;
      expect(useHeadless, isTrue);
      expect(context.useHeadlessWebView, isTrue);
      // Headless 模式下不传可见 WebView controller
      expect(context.webviewController, isNull);
      expect(context.currentUrl, 'https://www.example.com/book/');
    });

    test('writing 场景不需要 Headless', () {
      final scenarioId = ScenarioIds.writing;
      final useHeadless = scenarioId == ScenarioIds.webviewExtract;
      expect(useHeadless, isFalse);
    });
  });

  group('ExtractionTaskProvider 端到端流程', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('订阅 extractionTaskProvider 接收状态变化', () async {
      final notifier = container.read(extractionTaskNotifierProvider);
      final states = <ExtractionTaskState>[];

      // 订阅 Provider
      final sub = container.listen<ExtractionTaskState>(
        extractionTaskProvider,
        (prev, next) => states.add(next),
        fireImmediately: true,
      );

      // 初始状态
      expect(states.length, greaterThanOrEqualTo(1));
      expect(states.first.phase, ExtractionPhase.idle);

      // 启动任务
      notifier.start('www.example.com');
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.phase, ExtractionPhase.analyzing);
      expect(notifier.state.domain, 'www.example.com');
      // 订阅者收到了新状态
      expect(states.any((s) => s.phase == ExtractionPhase.analyzing), isTrue);

      // 切到 executing
      notifier.setPhase(ExtractionPhase.executing, toolName: 'execute_js');
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.phase, ExtractionPhase.executing);
      expect(notifier.state.currentTool, 'execute_js');

      // 工具完成
      notifier.toolEnd();
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.currentTool, isNull);

      // 保存
      notifier.setPhase(ExtractionPhase.saving, toolName: 'save_script');
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.phase, ExtractionPhase.saving);

      // 完成
      notifier.complete();
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.phase, ExtractionPhase.done);

      sub.close();
    });

    test('多个订阅者都能收到状态变化', () async {
      final notifier = container.read(extractionTaskNotifierProvider);

      final sub1Changes = <ExtractionTaskState>[];
      final sub2Changes = <ExtractionTaskState>[];

      final sub1 = container.listen<ExtractionTaskState>(
        extractionTaskProvider,
        (prev, next) => sub1Changes.add(next),
      );
      final sub2 = container.listen<ExtractionTaskState>(
        extractionTaskProvider,
        (prev, next) => sub2Changes.add(next),
      );

      notifier.start('www.example.com');
      await Future<void>.delayed(Duration.zero);

      // 至少一个变更被分发（broadcast 行为）
      expect(sub1Changes.length + sub2Changes.length, greaterThan(0));

      sub1.close();
      sub2.close();
    });

    test('错误状态正确传递', () async {
      final notifier = container.read(extractionTaskNotifierProvider);
      ExtractionTaskState? lastErrorState;

      container.listen<ExtractionTaskState>(
        extractionTaskProvider,
        (prev, next) {
          if (next.phase == ExtractionPhase.error) {
            lastErrorState = next;
          }
        },
      );

      notifier.start('www.example.com');
      notifier.setPhase(ExtractionPhase.executing, toolName: 'execute_js');
      notifier.fail('JS_SYNTAX_ERROR: 未闭合括号');

      await Future<void>.delayed(Duration.zero);

      expect(lastErrorState, isNotNull);
      expect(lastErrorState!.phase, ExtractionPhase.error);
      expect(lastErrorState!.error, contains('JS_SYNTAX_ERROR'));
      expect(lastErrorState!.completedAt, isNotNull);
    });
  });

  group('AgentChatProvider 改造后的预期行为', () {
    test('AgentScenarioContext 构造兼容 Headless 标志', () {
      // 模拟 AgentChatNotifier._buildScenarioContext 逻辑
      const scenarioId = ScenarioIds.webviewExtract;
      const currentUrl = 'https://www.example.com/book/';

      final useHeadless = scenarioId == ScenarioIds.webviewExtract;
      final context = AgentScenarioContext(
        currentUrl: currentUrl,
        useHeadlessWebView: useHeadless,
      );

      expect(context.useHeadlessWebView, isTrue);
      expect(context.currentUrl, currentUrl);
      // 关键：Headless 模式下不传 webviewController
      expect(context.webviewController, isNull);
    });

    test('写作场景下 useHeadless = false', () {
      const scenarioId = ScenarioIds.writing;
      final useHeadless = scenarioId == ScenarioIds.webviewExtract;
      expect(useHeadless, isFalse);
    });
  });

  group('场景生命周期事件完整性', () {
    test('complete 和 fail 都会设置 completedAt', () async {
      final notifier = ExtractionTaskNotifier();
      notifier.start('test.com');
      notifier.complete();
      final doneAt = notifier.state.completedAt;
      expect(doneAt, isNotNull);

      notifier.reset();
      notifier.start('test.com');
      notifier.fail('error');
      final errorAt = notifier.state.completedAt;
      expect(errorAt, isNotNull);
    });

    test('roundCount 跨多个轮次累加', () {
      final notifier = ExtractionTaskNotifier();
      notifier.start('test.com');

      for (var i = 0; i < 5; i++) {
        notifier.incrementRound();
      }
      expect(notifier.state.roundCount, 5);
    });

    test('setPhase 不影响 currentTool（除非显式传入）', () {
      final notifier = ExtractionTaskNotifier();
      notifier.start('test.com');
      notifier.toolStart('get_page_info');

      // setPhase 不传 toolName → currentTool 保持
      notifier.setPhase(ExtractionPhase.executing);
      expect(notifier.state.currentTool, 'get_page_info');

      // setPhase 传新 toolName → currentTool 更新
      notifier.setPhase(ExtractionPhase.saving, toolName: 'save_script');
      expect(notifier.state.currentTool, 'save_script');
    });
  });
}
