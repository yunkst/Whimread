/// buildSystemPrompt 内容验证测试
///
/// 验证 WebViewExtractScenario 的 system prompt 包含提取器相关的工作原则：
/// - "提取器创建流程"段落（强制两次 save_script + 落库前验证）
/// - "字体反爬（PUA）说明"段落（自动检测，agent 无需判定）
/// - 新 save_script schema 引用（run_id + script_type + test_url，无 ocr）
///
/// 这些字串在 prompt 中必须存在，否则 LLM Agent 不会按新流程创建提取器。
library;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/scenarios/webview_extract_scenario.dart';

import 'webview_extract_prompt_test.mocks.dart';

@GenerateMocks([InAppWebViewController])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 构造一个最小可用的 scenario（buildSystemPrompt 不触发任何 WebView 操作，
  // 只需要 Ref + 任意 InAppWebViewController 实例 + currentUrl）
  // 通过 Provider 拿到 Riverpod 的 Ref 实例（ProviderContainer 本身不是 Ref）。
  WebViewExtractScenario buildScenario() {
    final controller = MockInAppWebViewController();
    // buildSystemPrompt 不调用 controller 的任何方法，但 mockito
    // 默认对未 stub 的调用返回 null，给可能用到的方法打桩：
    when(controller.getUrl()).thenAnswer((_) async => null);
    final container = ProviderContainer();
    final scenarioProvider = Provider<WebViewExtractScenario>((ref) {
      return WebViewExtractScenario(ref, controller, 'https://example.com');
    });
    return container.read(scenarioProvider);
  }

  AgentScenarioContext testContext({String? url}) =>
      AgentScenarioContext(currentUrl: url ?? 'https://example.com');

  test('prompt 含"提取器创建流程"段落', () {
    final scenario = buildScenario();
    final prompt = scenario.buildSystemPrompt(testContext());

    expect(prompt, contains('提取器创建流程'));
    expect(prompt, contains('save_script(domain, run_id, script_type="chapter_list"'));
    expect(prompt, contains('save_script(domain, run_id, script_type="chapter_content"'));
    // v48：OCR 触发为 PUA 自动检测，prompt 不再出现 ocr 传值指引
    expect(prompt, isNot(contains('ocr=')));
    expect(prompt, contains('U+E000-F8FF')); // PUA 说明
    expect(prompt, contains('font_family'));
  });

  test('prompt 工作流程段已更新为两次 save_script', () {
    final scenario = buildScenario();
    final prompt = scenario.buildSystemPrompt(testContext());

    // 旧版本第 4 步签名（list_run_id + content_run_id）必须已被替换
    expect(prompt, isNot(contains('save_script(domain, list_run_id, content_run_id)')));
    // 新流程引用
    expect(prompt, contains('阶段一'));
    expect(prompt, contains('阶段二'));
    expect(prompt, contains('落库前强制试运行验证'));
  });

  test('prompt run_id 机制段已使用新 schema（无 ocr 参数）', () {
    final scenario = buildScenario();
    final prompt = scenario.buildSystemPrompt(testContext());

    // 旧版保存示例必须已被替换
    expect(prompt, isNot(contains('save_script(domain, list_run_id=')));
    expect(prompt, isNot(contains('content_run_id=<id>')));
    // 新版保存示例（display_name 仅首次保存时传；v48 起无 ocr 参数）
    expect(prompt,
        contains('save_script(domain, run_id=<id>, script_type=..., test_url=..., display_name='));
  });

  test('prompt 书架脚本契约含封面槽位（cover_url）说明', () {
    final scenario = buildScenario();
    final prompt = scenario.buildSystemPrompt(testContext());

    // 书架脚本的封面槽位：字段名、懒加载属性指引、空串语义
    expect(prompt, contains('"cover_url"'));
    expect(prompt, contains('封面槽位'));
    expect(prompt, contains('data-original'));
  });
}