/// Agent 场景工厂
///
/// 根据 scenarioId 和 AgentScenarioContext 构造对应的场景实例。
/// 支持 Headless WebView 模式（webview_extract 场景可使用后台 WebView，
/// 不依赖可见页面生命周期）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logger_service.dart';
import 'agent_scenario.dart';
import '../headless_webview_pool.dart';
import 'scenarios/writing_scenario.dart';
import 'scenarios/webview_extract_scenario.dart';

class AgentScenarioFactory {
  final Ref _ref;

  AgentScenarioFactory(this._ref);

  /// 构造场景实例（异步，因为 Headless WebView 初始化需要异步）
  ///
  /// 当 `context.useHeadlessWebView == true` 且场景为 `webviewExtract` 时，
  /// 从 [HeadlessWebViewPool] 获取后台 WebView controller，使 AI 提取进程
  /// 不依赖可见 WebView 页面生命周期。
  Future<AgentScenario> build(
      String scenarioId, AgentScenarioContext context) async {
    switch (scenarioId) {
      case ScenarioIds.writing:
        return WritingScenario(_ref);
      case ScenarioIds.webviewExtract:
        if (context.useHeadlessWebView) {
          // Headless 模式：从池获取 controller（排他占用）
          final pool = _ref.read(headlessWebViewPoolProvider);
          final controller = await pool.acquire();
          WebViewExtractScenario? scenario;
          try {
            scenario = WebViewExtractScenario.headless(
              _ref,
              controller,
              context.currentUrl ?? '',
            );
            // 绑定网络请求观察器到 pool（构造时回调委托到此 recorder）
            pool.networkRecorder = scenario.networkRecorder;
            // 注入清理钩子：先解绑 recorder，再释放 pool 使用权
            scenario.setCleanupTask(() async {
              pool.networkRecorder = null;
              final s = scenario;
              s?.disposeNetworkRecorder();
              pool.release();
            });
            return scenario;
          } catch (e, stackTrace) {
            // 构造失败也要释放，避免阻塞后续 acquire
            pool.networkRecorder = null;
            pool.release();
            LoggerService.instance.e(
              'WebViewExtractScenario.headless 构造失败: $e',
              stackTrace: stackTrace.toString(),
              category: LogCategory.ai,
              tags: ['agent', 'scenario', 'headless', 'init', 'failed'],
            );
            rethrow;
          }
        }
        // 兼容：普通 WebView 模式
        if (context.webviewController == null) {
          throw ArgumentError('WebViewExtract 场景需要 webviewController');
        }
        return WebViewExtractScenario(
          _ref,
          context.webviewController!,
          context.currentUrl ?? '',
        );
      default:
        throw ArgumentError('未知场景: $scenarioId');
    }
  }

  /// 获取所有可用场景的信息（用于 UI 展示）
  static List<ScenarioInfo> get availableScenarios => [
        const ScenarioInfo(
          id: ScenarioIds.writing,
          displayName: '小说写作助手',
          icon: '✍️',
        ),
        const ScenarioInfo(
          id: ScenarioIds.webviewExtract,
          displayName: '网页小说提取',
          icon: '🔍',
        ),
      ];
}

/// 场景信息（用于 UI 列表展示）
class ScenarioInfo {
  final String id;
  final String displayName;
  final String icon;

  const ScenarioInfo({
    required this.id,
    required this.displayName,
    required this.icon,
  });
}
