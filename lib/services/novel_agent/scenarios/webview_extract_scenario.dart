/// WebView 网页小说提取场景
///
/// 在用户浏览小说网站时，通过 ReAct 循环生成 JS 脚本
/// 提取小说目录和章节内容。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/extraction_task_providers.dart';
import 'package:novel_app/core/providers/webview_add_novel_providers.dart';
import 'package:novel_app/core/providers/webview_providers.dart';
import 'package:novel_app/repositories/site_script_repository.dart';
import 'package:novel_app/services/browser_settings_service.dart';
import 'package:novel_app/services/logger_service.dart';
import 'package:novel_app/services/ocr_render_js.dart';
import 'package:novel_app/services/ocr_restore_service.dart';

import '../agent_scenario.dart';
import '../tool_arg_parser.dart';
import 'network_request_recorder.dart';
import 'run_store.dart';
import 'webview_extract_js_diagnostics.dart';
import 'webview_extract_page_scripts.dart';
import 'webview_extract_script_db.dart';
import 'webview_extract_script_validator.dart';
import 'webview_extract_tool_schemas.dart';
import 'webview_js_executor.dart';

class WebViewExtractScenario with AgentScenarioCleanupMixin, AgentMemoryPatchMixin
    implements AgentScenario {
  final Ref _ref;
  final InAppWebViewController _webviewController;
  final String _currentUrl;

  /// 是否为 Headless 模式
  ///
  /// Headless 模式下使用 `HeadlessInAppWebView`（后台无 UI），
  /// 不受可见 WebView 页面生命周期影响。
  /// 普通模式下使用可见 `InAppWebView`（向后兼容）。
  final bool _isHeadless;

  /// Headless 模式下，是否已把 _currentUrl 同步到 Headless WebView
  ///
  /// Headless WebView 是全局单例池，复用同一实例。
  /// 上次执行可能停留在任意页面（about:blank / 上次的章节 URL），
  /// 必须在第一次执行 WebView 类工具前显式 loadUrl + 等待 onLoadStop。
  bool _headlessPageSynced = false;

  /// 需要 Headless WebView 已就绪的工具（其余 3 个是纯数据库工具）
  static const _webviewRequiredTools = {
    'get_page_info',
    'execute_js',
    'navigate_to',
    'get_current_url',
  };

  /// 脚本执行记录内存存储（句柄机制）
  ///
  /// 每次 execute_js 成功执行后，脚本自动登记到此处并返回 run_id；
  /// save_script 通过 run_id 引用已验证脚本（零重传）；
  /// get_cached_script 从数据库加载的脚本也登记到此处，
  /// 后续 execute_js 通过 run_id 重跑（零重抄）。
  final RunStore _runStore = RunStore();

  /// 自上次 onNoToolCalls 检查以来，是否产生过工具调用
  ///
  /// 状态机核心：注入提示的前提是 agent "行动过"（产生过 tool_call）。
  /// - true（调过工具）→ 结束时检查脚本是否存在，无脚本则注入并复位
  /// - false（首次空响应 / 注入后仍无行动）→ 不注入，结束
  /// executeTool 开头置 true，onNoToolCalls 注入后复位为 false。
  bool _hadToolCallSinceLastCheck = false;

  /// 本次会话是否已成功保存脚本（save_script 成功时置 true）
  bool _scriptSavedThisSession = false;

  /// 当前场景的网络请求观察器。
  ///
  /// 仅 Android Headless 模式下由工厂绑定到 HeadlessWebViewPool；
  /// 工具 list_network_requests 从此读取本页面的 AJAX 请求历史。
  final NetworkRequestRecorder _networkRecorder = NetworkRequestRecorder();

  /// 供 AgentScenarioFactory 在 Headless 模式下绑定到 pool（回调委托到此）。
  NetworkRequestRecorder get networkRecorder => _networkRecorder;

  /// 释放网络请求观察器（由 AgentScenarioFactory 在 cleanup 时调用）。
  void disposeNetworkRecorder() => _networkRecorder.dispose();

  /// 普通 WebView 模式构造函数（向后兼容）
  WebViewExtractScenario(this._ref, this._webviewController, this._currentUrl)
    : _isHeadless = false;

  /// Headless 模式工厂构造函数
  ///
  /// 注意：Headless 模式下，_currentUrl 与 WebView 实际页面**不同步**。
  /// 第一次执行工具时会通过 [_ensureHeadlessPageLoaded] 显式同步。
  WebViewExtractScenario.headless(
    this._ref,
    this._webviewController,
    this._currentUrl,
  ) : _isHeadless = true;

  @override
  String get id => ScenarioIds.webviewExtract;

  @override
  String get displayName => '网页小说提取';

  @override
  String buildSystemPrompt(AgentScenarioContext context) {
    final url = context.currentUrl ?? _currentUrl;
    final buf = StringBuffer();

    buf.writeln('## 当前页面');
    buf.writeln('URL: $url');
    buf.writeln();

    buf.writeln('## 工作目标');
    buf.writeln('为当前小说网站编写可复用的 JS 提取脚本，先完成目录提取并立即保存，再跳转到章节页完成内容提取并保存。');
    buf.writeln('核心产出：目录提取（chapter_list_js）+ 内容提取（chapter_content_js）。');
    buf.writeln();

    buf.writeln('## 工作流程');
    buf.writeln('0. (可选) list_network_requests → 看当前页面发了哪些 AJAX 请求（URL/参数/请求头），用于推断章节接口模式，辅助编写提取脚本。注意：响应体与 POST body 不采集。');
    buf.writeln('1. get_page_info → 获取 DOM 结构和页面类型');
    buf.writeln('2. get_cached_script → 看 present/missing 列表：已有项 execute_js(run_id=...) 重跑验证，缺失项只补缺失的那一种（save_script(script_type=...)），无缓存则新生成');
    buf.writeln('3. 阶段一：目录页 execute_js 测试 chapter_list 脚本 → 成功立刻 save_script 落库');
    buf.writeln('4. navigate_to → 从目录结果中挑一个章节 URL 跳转到内容页');
    buf.writeln('5. 阶段二：内容页 execute_js 测试 chapter_content 脚本 → 成功立刻 save_script 落库');
    buf.writeln();

    buf.writeln('## run_id 机制');
    buf.writeln('- 不要在上下文保留完整脚本 → 用 run_id 句柄引用');
    buf.writeln('- 重跑: execute_js(run_id=<id>) → 保存: save_script(domain, run_id=<id>, script_type=..., test_url=..., ocr=..., display_name=<网站自身的名字，如「起点中文网」，仅在第一次传一次>)');
    buf.writeln();

    buf.writeln('## JS 脚本规范');
    buf.writeln('- 脚本是 async IIFE: (async function() { ... return JSON.stringify(result); })()');
    buf.writeln('- 首行必须声明 `const PAGE_URL = \'{{URL}}\';`，禁止 window.location.href');
    buf.writeln('- 安全边界（违反会被拒绝执行）：禁止 document.cookie / localStorage / sessionStorage / indexedDB；禁止 sendBeacon / WebSocket / EventSource / window.open / import()；fetch 与 XMLHttpRequest 仅允许请求与 PAGE_URL 同源的地址（执行时已注入同源守卫，跨域会抛 WHIMREAD_SANDBOX 错误）。提取只需读 DOM 并 return 结果');
    buf.writeln('- 目录返回: { "title": "...", "cover_url": "...", "chapters": [{ "title": "...", "url": "..." }] }');
    buf.writeln('- chapters 必须按章节顺序从小到大排列（第一章 → 最新章），不要倒序');
    buf.writeln('- cover_url（必填字段，缺失会拒绝落库）：优先 <meta property="og:image" content="...">，其次目录页书籍封面 <img> 的 src / data-src；取绝对 URL（相对路径用 new URL(src, PAGE_URL).href 补全）；确实无封面时返回空串 ""');
    buf.writeln('- 内容返回: { "title": "...", "content": "..." }，content 中段落之间必须用 \\n 分隔');
    buf.writeln('- 书架脚本（可选，仅在「我的书架/收藏」页运行；用户要求生成时才做）返回: { "novels": [{ "title": "...", "url": "...", "cover_url": "..." }] }。url 应为该站小说目录页绝对路径，便于应用跳转后复用 chapter_list_js。cover_url 为每本书的封面槽位：取书架条目内 <img> 的 src / data-src / data-original（懒加载优先取 data-* 属性），相对路径用 new URL(src, PAGE_URL).href 补全为绝对 URL，确实无封面时返回空串 ""。保存用 save_script(script_type="bookshelf", test_url=<书架页>, ocr=false)。');
    buf.writeln('- 翻页: 检测下一页 → 点击 → await new Promise(r => setTimeout(r, 1000)) → 继续');
    buf.writeln('- 只使用标准 DOM API（querySelector, innerText），不依赖 jQuery/Vue/React');
    buf.writeln('- 跳过广告段落（含本章未完、一秒记住等）');
    buf.writeln();

    buf.writeln('## 提取器创建流程（强制，分阶段）');
    buf.writeln('完整提取器必须按顺序分两个阶段完成，每个阶段独立测试通过后立即落库，不要攒到一起处理。');
    buf.writeln('save_script 会在落库前强制试运行验证，失败返回诊断指导你修 JS。');
    buf.writeln();
    buf.writeln('### 阶段一：目录提取（落库后才能进阶段二）');
    buf.writeln('1. 当前已在目录页（chapter_list）：get_page_info 确认页面类型');
    buf.writeln('2. execute_js(script=...) 反复调试，确认返回 {title, cover_url, chapters:[{title,url}]} 且 chapters 非空、cover_url 字段存在（允许空串）');
    buf.writeln('3. 拿到 __meta.run_id 后立刻调用：');
    buf.writeln('   save_script(domain, run_id, script_type="chapter_list", test_url=<目录页>, ocr=<true|false>, display_name=<站点自身的名字>)');
    buf.writeln('4. save_script 返回 success=true 才能进入阶段二；返回 success=false 则按 diagnostic/suggestion 修 JS，重新 execute_js，再 save_script');
    buf.writeln();
    buf.writeln('### 阶段二：内容提取');
    buf.writeln('1. 从阶段一拿到的 chapters 数组里挑一个章节 URL（建议选非第一/最后章节的中间章节）');
    buf.writeln('2. navigate_to(url=<该章节URL>) 跳转到内容页，等待加载完成');
    buf.writeln('3. execute_js(script=...) 反复调试 chapter_content 脚本，确认返回 {title, content, font_family}');
    buf.writeln('4. 拿到 __meta.run_id 后立刻调用：');
    buf.writeln('   save_script(domain, run_id, script_type="chapter_content", test_url=<该章节URL>, ocr=<独立判定：正文页 content 有 PUA 才传 true>)');
    buf.writeln('5. save_script 返回 success=false 仍按诊断修 JS 重试，直到成功');
    buf.writeln();
    buf.writeln('### 字体反爬检测（ocr 判定）');
    buf.writeln('若 DOM 文本含大量 PUA 私用区码点（U+E000-F8FF，表现为不可读的乱码方块），');
    buf.writeln('且页面通过 @font-face 加载自定义字体绑定到正文/标题元素（典型如番茄小说），');
    buf.writeln('这是字体反爬，ocr 应传 true。');
    buf.writeln();
    buf.writeln('OCR 模式下：');
    buf.writeln('- chapter_content_js 必须额外返回 font_family（用 getComputedStyle(正文元素).fontFamily）');
    buf.writeln('- content 保留原始 PUA 文本（不要在 JS 里尝试解码）');
    buf.writeln('- chapter_list 与 chapter_content 的 ocr 各自独立判定，按各自页面是否真有 PUA 传值，不必一致');
    buf.writeln('  （典型如番茄小说：目录页 title/chapter.title 是正常汉字传 false，正文页 content 有 PUA 传 true）');
    buf.writeln();
    buf.writeln('不要在 JS 里做 PUA 到真字的替换（你拿不到字体映射），交给运行时 OCR。');
    buf.writeln();

    buf.writeln('## 错误处理');
    buf.writeln('- 工具返回 error 时 → 先读 suggestion 字段');
    buf.writeln('- 错误码: JS_SYNTAX_ERROR/REFERENCE_ERROR/TYPE_ERROR/TIMEOUT/RUNTIME_ERROR → 按 suggestion 修');
    buf.writeln('- SCRIPT_VALIDATION_FAILED → 检查 {{URL}} 占位符和 PAGE_URL');
    buf.writeln('- 同一错误连续 3 次 → 换完全不同的选择器/思路');
    buf.writeln();

    buf.writeln('## 脚本实际使用日志');
    buf.writeln('脚本在对话中 execute_js 跑通，不代表真实使用也能成功。用 get_script_logs 查看实际运行日志：');
    buf.writeln('- get_script_logs() → 无参数，返回最近 30 条爬虫运行日志（时间倒序）');
    buf.writeln('- get_script_logs(outcome="failure") → 只看失败记录；outcome="success" 只看成功记录');
    buf.writeln('- 适用：execute_js 通过但用户反馈抓取失败（内容为空、超时、页面结构变化）');
    buf.writeln('- 日志来源：阅读器获取章节内容、FAB 添加小说、获取站点书架等非对话场景');
    buf.writeln('- 消息中含 domain=xxx，可自行按域名区分不同网站');
    buf.writeln();

    if (cachedMemories.isNotEmpty) {
      buf.writeln('## 经验记忆');
      buf.writeln('以下是以往对话中的经验记录，请优先参考：');
      for (var i = 0; i < cachedMemories.length; i++) {
        buf.writeln('[${i + 1}] ${cachedMemories[i]}');
      }
      buf.writeln();
    }

    return buf.toString();
  }

  /// 无 tool_call 注入钩子：Agent 即将"无工具调用结束"时调用
  ///
  /// 注入前提：自上次检查以来 agent 必须产生过 tool_call（即"行动过"）。
  /// 一个字段 `_hadToolCallSinceLastCheck` 统一表达所有终止条件：
  /// - 首次无 tool_call（从未调过工具）→ 标记为 false → 不注入，直接结束
  /// - agent 行动过 + 脚本已存在 → 正常结束
  /// - agent 行动过 + 脚本不存在 → 注入提示，复位标记为 false
  /// - 注入后再次结束：期间有新 tool_call → 标记为 true → 重新检查；无 → 结束
  @override
  Future<String?> onNoToolCalls(List<ChatMessage> messages) async {
    // 前提：agent 自上次检查以来必须"行动过"。
    // 首次空响应、或注入后仍无新行动，都落入此分支 → 不注入。
    if (!_hadToolCallSinceLastCheck) {
      return null;
    }

    // agent 行动过了，检查脚本是否真的存在（内存标志短路，否则查库）
    final hasScript = _scriptSavedThisSession || await _hasScriptInDb();
    if (hasScript) {
      return null; // 有脚本，正常结束
    }

    // 无脚本，注入提示；复位标记，等待下一轮是否有新行动
    _hadToolCallSinceLastCheck = false;

    LoggerService.instance.i(
      'WebViewExtract 注入提示: agent 已行动但未保存脚本 (url=$_currentUrl)',
      category: LogCategory.ai,
      tags: ['agent', 'webview-extract', 'injection', 'hint'],
    );
    return '系统检测：本次会话中尚未保存任何提取脚本到数据库。\n'
        '请立即采取以下任一行动：\n'
        '1) 若 execute_js 已成功解析出目录/正文，调用 save_script 保存脚本；\n'
        '2) 若确实无法生成脚本，请说明具体原因（反爬、动态加载、需登录等）。';
  }

  /// 查询当前域名的 site_scripts 表是否有记录
  Future<bool> _hasScriptInDb() async {
    final domain = Uri.tryParse(_currentUrl)?.host ?? '';
    if (domain.isEmpty) return false;
    try {
      return await WebViewExtractScriptDb.hasAnyScript(_ref, domain);
    } catch (e) {
      LoggerService.instance.w(
        '查询 site_scripts 失败: $e',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'db_query_error'],
      );
      return false;
    }
  }

  @override
  List<Map<String, dynamic>> get tools {
    final base = <Map<String, dynamic>>[
      WebViewExtractToolSchemas.getPageInfoTool,
      WebViewExtractToolSchemas.executeJsTool,
      WebViewExtractToolSchemas.navigateToTool,
      WebViewExtractToolSchemas.getCurrentUrlTool,
      WebViewExtractToolSchemas.getCachedScriptTool,
      WebViewExtractToolSchemas.saveScriptTool,
      WebViewExtractToolSchemas.listCachedScriptsTool,
      WebViewExtractToolSchemas.inspectScriptTool,
      WebViewExtractToolSchemas.getScriptLogsTool,
      patchMemoryToolDefinition,
    ];
    // 网络请求观察仅 Headless + Android 支持
    // （Headless 模式才挂 shouldInterceptRequest 回调；iOS 无 shouldInterceptRequest）
    if (_isHeadless && Platform.isAndroid) {
      base.add(WebViewExtractToolSchemas.listNetworkRequestsTool);
    }
    return base;
  }

  /// 记忆缓存（由 AgentMemoryPatchMixin 提供，本类复用 mixin 的实现）
  @override
  Future<List<String>> getMemories() async {
    final repo = _ref.read(agentMemoryRepositoryProvider);
    return await loadMemories(repo);
  }

  @override
  Future<MemoryPatchResult> patchMemory(int? index, String newText) async {
    final repo = _ref.read(agentMemoryRepositoryProvider);
    return patchMemoryImpl(repo, index, newText);
  }

  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    // 任意工具调用都视为 agent 在"行动"，标记供 onNoToolCalls 状态机判断
    _hadToolCallSinceLastCheck = true;
    // onProgress 在本场景不使用：webview_extract 的工具均为 WebView/DB 操作，
    // 没有内部走 LLM 流式的工具。参数仅为对齐 AgentScenario 接口签名。

    LoggerService.instance.i(
      'WebViewExtractScenario 执行工具: $name',
      category: LogCategory.ai,
      tags: ['agent', 'scenario', 'webview-extract', name],
    );

    // patch_memory 由场景自行处理（复用 mixin 的统一工具执行器）
    if (name == 'patch_memory') {
      return executePatchMemoryTool(args, logTag: 'webview-extract');
    }

    // Headless 模式：仅 WebView 类工具（get_page_info / execute_js / navigate_to）
    // 需要确保 Headless WebView 加载了 _currentUrl。
    // 数据库工具（get_cached_script / save_script / list_cached_scripts）不依赖 WebView。
    if (_isHeadless && _webviewRequiredTools.contains(name)) {
      final syncResult = await _ensureHeadlessPageLoaded();
      if (syncResult != null) {
        return syncResult;
      }
    }

    // 更新提取任务状态
    _updateTaskPhase(name);

    try {
      String result;
      switch (name) {
        case 'get_page_info':
          result = await _getPageInfo();
        case 'execute_js':
          result = await _executeJs(args);
        case 'navigate_to':
          result = await _navigateTo(args);
        case 'get_current_url':
          result = await _getCurrentUrl();
        case 'get_cached_script':
          result = await _getCachedScript(args);
        case 'save_script':
          result = await _saveScript(args);
        case 'list_cached_scripts':
          result = await _listCachedScripts();
        case 'inspect_script':
          result = await _inspectScript(args);
        case 'get_script_logs':
          result = await _getScriptLogs(args);
        case 'list_network_requests':
          result = await _listNetworkRequests(args);
        default:
          result = jsonEncode({
            'error': 'unknown_tool',
            'message': '未知工具: $name',
          });
      }

      // 工具完成后更新状态
      _ref.read(extractionTaskNotifierProvider).toolEnd();

      return result;
    } catch (e, stackTrace) {
      _ref.read(extractionTaskNotifierProvider).toolEnd();

      LoggerService.instance.e(
        'WebViewExtractScenario 工具执行失败: $name, error=$e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.ai,
        tags: ['agent', 'scenario', 'webview-extract', name, 'error'],
      );
      return jsonEncode({
        'error': 'execution_failed',
        'message': e.toString(),
      });
    }
  }

  /// 根据工具名更新提取任务阶段
  void _updateTaskPhase(String toolName) {
    final notifier = _ref.read(extractionTaskNotifierProvider);
    notifier.toolStart(toolName);

    // 首次执行时，从 _currentUrl 提取域名并启动任务
    if (notifier.isIdle) {
      final domain = Uri.tryParse(_currentUrl)?.host ?? '';
      if (domain.isNotEmpty) {
        notifier.start(domain);
      }
    }

    switch (toolName) {
      case 'get_page_info':
      case 'navigate_to':
        notifier.setPhase(ExtractionPhase.analyzing, toolName: toolName);
      case 'execute_js':
        notifier.setPhase(ExtractionPhase.executing, toolName: toolName);
      case 'save_script':
        notifier.setPhase(ExtractionPhase.saving, toolName: toolName);
    }
  }

  // ===== 工具实现 =====

  /// 获取当前页面信息（URL + 精简 DOM + 页面类型推断）
  ///
  /// Headless 模式下使用 [_currentUrl] 作为页面 URL（Headless WebView
  /// 的 getUrl() 在某些平台上可能不准确或返回 about:blank）。
  Future<String> _getPageInfo() async {
    try {
      // Headless 模式使用 _currentUrl；普通模式从 WebView 获取实际 URL
      final String pageUrl;
      if (_isHeadless) {
        pageUrl = _currentUrl;
      } else {
        final url = await _webviewController.getUrl();
        pageUrl = url?.toString() ?? _currentUrl;
      }

      final domResult = await _webviewController.evaluateJavascript(
        source: WebViewExtractPageScripts.domSimplifyJs,
      );

      // 推断页面类型
      final pageTypeResult = await _webviewController.evaluateJavascript(
        source: WebViewExtractPageScripts.inferPageTypeJs,
      );
      String pageType = 'unknown';
      String? pageTitle;
      if (pageTypeResult != null && pageTypeResult is String) {
        try {
          final parsed = jsonDecode(pageTypeResult);
          pageType = parsed['pageType'] ?? 'unknown';
          pageTitle = parsed['title'] ?? '';
        } catch (_) {
          // 推断失败不影响主流程
        }
      }

      LoggerService.instance.i(
        '获取页面信息: $pageUrl (domLen=${(domResult ?? '').length}, pageType=$pageType, headless=$_isHeadless)',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'get_page_info'],
      );
      return jsonEncode({
        'url': pageUrl,
        'pageType': pageType,
        'title': pageTitle ?? '',
        'dom': domResult ?? '',
      });
    } catch (e) {
      LoggerService.instance.w(
        'get_page_info 失败: $e (pageUrl=$_currentUrl)',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'get_page_info', 'error'],
      );
      return jsonEncode({
        'error': 'PAGE_NOT_READY',
        'message': '页面尚未加载完成或 WebView 未初始化',
        'raw': e.toString(),
        'suggestion': '请等待几秒后重试 get_page_info',
      });
    }
  }

  /// 确保 Headless WebView 已加载 _currentUrl
  ///
  /// Headless WebView 是全局单例池，复用同一实例。
  /// 上次执行可能停留在任意页面，必须在第一次执行 WebView 工具前显式同步。
  ///
  /// 优化：先检查 WebView 当前 URL 是否就是 _currentUrl，避免无效 loadUrl。
  ///
  /// 返回 `null` 表示同步成功；返回 JSON 字符串表示同步失败（作为工具错误返回给 LLM）。
  Future<String?> _ensureHeadlessPageLoaded() async {
    if (_headlessPageSynced) return null;

    try {
      // 池复用：先检查 WebView 实际 URL，可能已经是 _currentUrl
      final currentUrl = await _webviewController.getUrl();
      if (currentUrl != null && currentUrl.toString() == _currentUrl) {
        await Future.delayed(_domStabilizeDelay);
        _headlessPageSynced = true;
        return null;
      }

      LoggerService.instance.i(
        'Headless 模式: 同步加载 _currentUrl → $_currentUrl',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'headless-sync'],
      );

      await _webviewController.loadUrl(
        urlRequest: URLRequest(url: WebUri(_currentUrl)),
      );

      final loaded = await _waitForUrl(_currentUrl, timeout: _pageLoadTimeout);
      if (loaded) {
        _headlessPageSynced = true;
        return null;
      }

      // 超时：Headless WebView 的 getUrl() 在某些平台可能不更新，
      // 但 loadUrl 调用本身是成功的，信任它并继续
      LoggerService.instance.w(
        'Headless 模式: URL 同步超时，信任 loadUrl 调用并继续',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'headless-sync', 'timeout'],
      );
      await Future.delayed(_headlessTrustDelay);
      _headlessPageSynced = true;
      return null;
    } catch (e) {
      LoggerService.instance.e(
        'Headless 模式: URL 同步失败 $e',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'headless-sync', 'error'],
      );
      return jsonEncode({
        'error': 'PAGE_NOT_READY',
        'message': 'Headless WebView 加载目标页面失败: $e',
        'url': _currentUrl,
        'suggestion': '请稍后重试 get_page_info',
      });
    }
  }

  // ===== WebView 加载等待（统一 _ensureHeadlessPageLoaded 和 _navigateTo 的轮询逻辑）=====

  static const _pageLoadTimeout = Duration(seconds: 60);
  static const _pollInterval = Duration(milliseconds: 500);
  static const _domStabilizeDelay = Duration(milliseconds: 500);
  static const _headlessTrustDelay = Duration(seconds: 2);

  /// 等待 WebView 加载完成（URL 匹配 targetUrl）
  ///
  /// 返回 `true` 表示成功等到 URL 匹配；`false` 表示超时。
  /// 超时后的处理（如 Headless 模式信任 loadUrl 调用）由调用方自行判断。
  Future<bool> _waitForUrl(
    String targetUrl, {
    Duration timeout = _pageLoadTimeout,
  }) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      await Future.delayed(_pollInterval);
      try {
        final current = await _webviewController.getUrl();
        if (current != null && current.toString() == targetUrl) {
          await Future.delayed(_domStabilizeDelay);
          return true;
        }
      } catch (e) {
        // 轮询错误继续等待
        LoggerService.instance.i(
          '轮询 getUrl 失败: $e',
          category: LogCategory.ai,
          tags: ['agent', 'webview-extract', 'poll_url'],
        );
      }
    }
    return false;
  }

  /// 在 WebView 中执行 JS 脚本（使用 callAsyncJavaScript）
  ///
  /// ## 双模式
  ///
  /// ### run_id 模式（新，推荐）
  /// - 传 `run_id` 参数，从 RunStore 加载脚本执行
  /// - `test_url` 仍可选（覆盖脚本中 {{URL}}，未传则用 _currentUrl）
  /// - 用于「重跑已有脚本」，零重抄
  ///
  /// ### script 模式（旧，兼容）
  /// - 传 `script` 参数（带 {{URL}} 占位符的 async IIFE），直接执行
  /// - 执行成功后自动登记到 RunStore 返回 run_id
  /// - 用于「探测 DOM 结构」或「新写/修改提取脚本」
  ///
  /// 执行前会：
  /// 1. 若 run_id 模式：从 RunStore 读取完整脚本
  /// 2. 若 script 模式：校验脚本包含 `{{URL}}` 占位符（防呆）
  /// 3. 将 `{{URL}}` 替换为 `test_url` 或当前页面 URL
  /// 4. 通过 callAsyncJavaScript 执行替换后的脚本
  ///
  /// callAsyncJavaScript 相比 evaluateJavascript 的优势：
  /// - 支持 async/await（Promise 结果正确返回）
  /// - 支持 setTimeout 等异步操作（翻页等待）
  /// - 结构化返回值 CallAsyncJavaScriptResult{value, error}
  /// - JS 错误通过 error 字段返回，不再静默吞噬
  ///
  /// ## 返回值（结构统一）
  /// 无论执行成功/失败，返回值都包含 `run_id` 字段（成功时登记到 RunStore）；
  /// 成功时 script 字段返回前 200 字符（避免长脚本占上下文）。
  Future<String> _executeJs(Map<String, dynamic> args) async {
    // ── 阶段一：解析参数与脚本来源（run_id 优先）──
    final source = _resolveExecuteJsSource(args);
    if (source.error != null) return source.error!;
    final runId = source.runId;
    final effectiveScript = source.script!;

    // ── 阶段二：参数注入 + 提取 IIFE 函数体 ──
    // 将 {{URL}} 替换为 test_url 或当前页面 URL
    final testUrl = (args['test_url'] as String?) ?? _currentUrl;
    final resolvedScript = WebViewJsExecutor.replaceUrlPlaceholder(effectiveScript, testUrl);
    final functionBody = WebViewJsExecutor.extractAsyncFunctionBody(resolvedScript);

    final modeLabel = runId != null ? 'run_id=$runId' : 'script(len=${effectiveScript.length})';
    LoggerService.instance.i(
      '执行 JS ($modeLabel): {{URL}} → $testUrl (resolvedLen=${resolvedScript.length})',
      category: LogCategory.ai,
      tags: ['agent', 'webview-extract', 'execute_js', runId != null ? 'run_id' : 'script'],
    );

    try {
      // ── 阶段三：执行（callAsyncJavaScript，120s 超时）──
      final result = await _webviewController
          .callAsyncJavaScript(functionBody: functionBody)
          .timeout(const Duration(seconds: 120));

      // callAsyncJavaScript 返回 CallAsyncJavaScriptResult?
      if (result == null) {
        return jsonEncode({'result': null});
      }

      // JS Promise reject → 返回错误信息
      if (result.error != null) {
        return _jsExecutionErrorJson(
          logLabel: 'JS 执行错误',
          raw: result.error.toString(),
          script: effectiveScript,
        );
      }

      // ── 阶段四：成功 → 结果平铺 + RunStore 登记 + 组装响应 ──
      return _buildExecuteJsSuccessResponse(
        runId: runId,
        effectiveScript: effectiveScript,
        testUrl: testUrl,
        value: result.value,
      );
    } on TimeoutException {
      LoggerService.instance.w(
        '执行 JS 超时 (>120s)',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'execute_js', 'timeout'],
      );
      return jsonEncode({
        'error': 'JS_TIMEOUT',
        'message': '脚本执行超过 120 秒未返回',
        'script_length': effectiveScript.length,
        'suggestion':
            '检查脚本中是否有死循环、长时间 setTimeout，或在循环中加 await new Promise(r => setTimeout(r, 100)) 让出主线程',
      });
    } catch (e) {
      // Dart 层异常（如 callAsyncJavaScript 方法本身不可用）
      return _jsExecutionErrorJson(
        logLabel: '执行 JS 失败',
        raw: e.toString(),
        script: effectiveScript,
      );
    }
  }

  /// execute_js 的脚本来源解析结果
  ///
  /// [error] 非 null 表示参数/来源校验失败（错误 JSON 已构造好，直接返回）；
  /// 否则 [script] 为生效脚本（保留 {{URL}} 占位符），[runId] 为 run_id 模式
  /// 的句柄（script 模式为 null）。
  ({String? error, String? script, String? runId}) _resolveExecuteJsSource(
    Map<String, dynamic> args,
  ) {
    final runId = args['run_id'] as String?;
    final script = args['script'] as String?;

    if (runId == null && (script == null || script.isEmpty)) {
      return (
        error: jsonEncode({
          'error': 'missing_param',
          'message': '需要 script 或 run_id 参数',
          'missing': ['script 或 run_id'],
          'suggestion': script != null && script.isEmpty
              ? 'script 参数为空字符串，请传入有效的 JS 代码，或使用 run_id 引用之前执行的脚本'
              : '请传入 script（探测/新写脚本）或 run_id（重跑已有脚本）',
        }),
        script: null,
        runId: null,
      );
    }

    if (runId != null) {
      // run_id 模式：从 RunStore 加载
      final entry = _runStore.get(runId);
      if (entry == null) {
        return (
          error: jsonEncode({
            'error': 'RUN_ID_NOT_FOUND',
            'message': '未找到 $runId（可能已被淘汰或未注册）',
            'suggestion': 'RunStore 有容量限制（50 条 LRU 淘汰）。请重新执行 script 模式注册新 run_id',
          }),
          script: null,
          runId: null,
        );
      }
      return (error: null, script: entry.script, runId: runId);
    }

    // script 模式：校验 + 使用
    final validationError = WebViewJsExecutor.validateScript(script!);
    if (validationError != null) {
      LoggerService.instance.w(
        '脚本校验失败: $validationError',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'execute_js', 'validation'],
      );
      return (
        error: jsonEncode({
          'error': 'SCRIPT_VALIDATION_FAILED',
          'message': '脚本校验失败',
          'validation_error': validationError,
          'suggestion': validationError,
        }),
        script: null,
        runId: null,
      );
    }
    return (error: null, script: script, runId: null);
  }

  /// JS 执行失败的统一出口：解析错误 → 记日志 → 组错误 JSON
  String _jsExecutionErrorJson({
    required String logLabel,
    required String raw,
    required String script,
  }) {
    final errorInfo = WebViewExtractJsDiagnostics.parseJsError(raw, script);
    LoggerService.instance.w(
      '$logLabel: ${errorInfo.code} - ${errorInfo.message}',
      category: LogCategory.ai,
      tags: ['agent', 'webview-extract', 'execute_js', errorInfo.code],
    );
    return jsonEncode({
      'error': errorInfo.code,
      'message': errorInfo.message,
      'raw': raw,
      'suggestion': errorInfo.suggestion,
    });
  }

  /// execute_js 成功路径的收尾：业务字段平铺 + RunStore 登记 + __meta 组装
  String _buildExecuteJsSuccessResponse({
    required String? runId,
    required String effectiveScript,
    required String testUrl,
    required dynamic value,
  }) {
    // stringifyJsResult 总是返回 String（null → '{"result":null}'，对象 → jsonEncode）
    final resultStr = WebViewJsExecutor.stringifyJsResult(value);

    // 尝试解析为业务对象（Map），用于平铺到顶层（保持向后兼容）
    Map<String, dynamic>? businessFields;
    dynamic decoded;
    try {
      decoded = jsonDecode(resultStr);
      if (decoded is Map<String, dynamic>) {
        businessFields = decoded;
      }
    } catch (_) {
      // 非 JSON 字符串，无法平铺，原样放在 result 字段
      final preview = resultStr.length > 200
          ? '${resultStr.substring(0, 200)}...'
          : resultStr;
      LoggerService.instance.i(
        'JS 结果非 JSON: $preview',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'execute_js', 'non_json'],
      );
    }

    // 结果摘要（截断 300 字符）用于 RunStore 记录
    final resultSummary = resultStr.length > 300
        ? '${resultStr.substring(0, 300)}...'
        : resultStr;

    // 仅在 script 模式（新脚本）下登记；run_id 模式是重跑已有记录，不重复登记
    final String storedRunId;
    if (runId != null) {
      storedRunId = runId;
    } else {
      storedRunId = _runStore.put(
        script: effectiveScript,
        success: true,
        source: RunEntrySource.execution,
        testUrl: testUrl,
        resultSummary: resultSummary,
      );
    }

    LoggerService.instance.i(
      '执行 JS 成功: $storedRunId (mode=${runId != null ? "replay" : "register"}), resultLen=${resultStr.length}',
      category: LogCategory.ai,
      tags: ['agent', 'webview-extract', 'execute_js'],
    );

    // 返回值结构：业务字段平铺到顶层（向后兼容）+ __meta 元数据
    //
    // - 业务字段（title / chapters / pageUrl 等）平铺 → 现有测试和旧调用方零改动
    // - __meta.run_id → save_script 引用此 id 即可，无需重传脚本内容
    // - __meta.script_preview → 仅 register 模式返回（截断 200 字符），供 AI 确认
    // - __meta.mode → register（新写脚本）/ replay（重跑 run_id）
    final scriptPreview = effectiveScript.length > 200
        ? '${effectiveScript.substring(0, 200)}...'
        : effectiveScript;

    final response = <String, dynamic>{
      if (businessFields != null) ...businessFields else 'result': decoded ?? resultStr,
      '__meta': <String, dynamic>{
        'run_id': storedRunId,
        'mode': runId != null ? 'replay' : 'register',
        'store_size': _runStore.length,
        if (runId == null) 'script_preview': scriptPreview,
      },
    };
    return jsonEncode(response);
  }

  /// 让 WebView 跳转到指定 URL
  ///
  /// 场景：当前页是目录页，AI 需要提取某个章节的内容。
  /// 章节 URL 在目录页中已提取到，AI 调用本工具跳转到该 URL 后，
  /// 再调用 get_page_info / execute_js 提取正文。
  ///
  /// 等待 onLoadStop 完成才返回，确保后续工具调用看到的是新页面。
  /// 同时禁止跳转至当前页面（避免无意义重载）。
  Future<String> _navigateTo(Map<String, dynamic> args) async {
    final url = args['url'] as String?;
    if (url == null || url.isEmpty) {
      return jsonEncode({
        'error': 'missing_param',
        'message': '缺少 url 参数',
        'missing': ['url'],
        'suggestion': '传入要跳转的完整 URL，例如 https://example.com/chapter/1.html',
      });
    }

    // 校验 URL 格式
    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (e) {
      LoggerService.instance.w(
        'URL 解析失败: $url - $e',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'navigate_to', 'url_parse'],
      );
      return jsonEncode({
        'error': 'INVALID_URL',
        'message': 'URL 格式不合法: $url',
        'suggestion': '请传入完整的 URL（包含 http/https）',
      });
    }
    if (!uri.isAbsolute || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return jsonEncode({
        'error': 'INVALID_URL',
        'message': 'URL 必须是 http(s) 绝对地址: $url',
        'suggestion': '请使用完整 URL（包含 http/https），不支持 javascript: 等伪协议',
      });
    }

    // 阻止跳转到当前页面（避免无意义重载浪费一次 HTTP 请求）
    if (_isHeadless) {
      // Headless 模式：用 _currentUrl 比较
      if (_currentUrl == url) {
        return jsonEncode({
          'ok': true,
          'message': '已在目标页面',
          'url': url,
          'note': '当前页面已为目标 URL，未执行跳转',
        });
      }
    } else {
      try {
        final currentUrl = await _webviewController.getUrl();
        if (currentUrl != null && currentUrl.toString() == url) {
          return jsonEncode({
            'ok': true,
            'message': '已在目标页面',
            'url': url,
            'note': '当前页面已为目标 URL，未执行跳转',
          });
        }
      } catch (_) {
        // getUrl 失败不阻止跳转
      }
    }

    try {
      LoggerService.instance.i(
        'navigate_to: 跳转 $url (headless=$_isHeadless)',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'navigate_to'],
      );

      await _webviewController.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );

      final loaded = await _waitForUrl(url);
      if (!loaded && !_isHeadless) {
        return jsonEncode({
          'error': 'NAVIGATE_TIMEOUT',
          'message': '跳转后等待页面加载超时（60秒）',
          'target_url': url,
          'suggestion': '检查网络连接，或目标网站是否可访问',
        });
      }

      return jsonEncode({
        'ok': true,
        'url': url,
        'message': '跳转成功',
      });
    } catch (e) {
      LoggerService.instance.w(
        'navigate_to 失败: $url, error=$e',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'navigate_to', 'error'],
      );
      return jsonEncode({
        'error': 'NAVIGATE_FAILED',
        'message': '跳转失败: ${e.toString()}',
        'url': url,
      });
    }
  }

  /// 查询 WebView 当前实际加载的 URL
  ///
  /// 区别于 [_currentUrl]（场景构造时传入的预期 URL），本工具返回
  /// WebView 运行时的真实 URL（`getUrl()` 的返回值）。
  ///
  /// 典型用途：
  /// - 在 navigate_to 之后确认 WebView 是否真的停留在目标页面
  /// - 排查 Headless WebView 在某些平台 URL 不更新的问题
  /// - 判断 JS 脚本中的 `{{URL}}` 占位符实际会被替换成什么
  Future<String> _getCurrentUrl() async {
    final expectedUrl = _currentUrl;
    String? actualUrl;
    try {
      final uri = await _webviewController.getUrl();
      actualUrl = uri?.toString();
    } catch (e) {
      LoggerService.instance.w(
        'get_current_url: getUrl() 调用失败 $e',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'get_current_url', 'error'],
      );
      return jsonEncode({
        'error': 'GET_URL_FAILED',
        'message': '无法读取 WebView 当前 URL: $e',
        'expected_url': expectedUrl,
        'suggestion': '可能 WebView 尚未就绪，请稍后重试 get_current_url',
      });
    }

    LoggerService.instance.i(
      'get_current_url: actual=$actualUrl (expected=$expectedUrl, headless=$_isHeadless)',
      category: LogCategory.ai,
      tags: ['agent', 'webview-extract', 'get_current_url'],
    );

    // getUrl() 返回空：某些平台 Headless WebView 未加载页面时会返回 null
    if (actualUrl == null || actualUrl.isEmpty) {
      return jsonEncode({
        'url': null,
        'expected_url': expectedUrl,
        'matched': false,
        'note': 'WebView 当前未加载任何页面（getUrl 返回空）',
        'suggestion': _isHeadless
            ? 'Headless WebView 可能尚未加载页面，可调用 get_page_info 触发加载'
            : '页面可能尚未初始化，请稍后重试',
      });
    }

    return jsonEncode({
      'url': actualUrl,
      'expected_url': expectedUrl,
      'matched': actualUrl == expectedUrl,
    });
  }

  /// 查询该域名是否已有缓存脚本
  ///
  /// ## 新行为（run_id 句柄）
  /// 从数据库读出脚本后自动注册到 RunStore，返回 `list_run_id` + `content_run_id`。
  /// 后续 AI 调用 `execute_js(run_id=...)` 即可重跑，**零重抄**。
  ///
  /// 业务字段（id / domain / use_count / verified）平铺到顶层，保持向后兼容。
  /// 完整脚本内容**不返回**到顶层（避免占上下文）；需要时可调 `inspect_script(run_id)`。
  ///
  /// ## v37+ 增量反馈（script_type + present/missing）
  /// save_script 改为分次落库后，Agent 需要知道**哪些脚本类型已存在、哪些缺失**，
  /// 才能精准补缺失项。本工具：
  /// - 顶层 `present` / `missing` 始终返回，列出当前域名已有/缺失的脚本类型。
  /// - 全查模式（不传 `script_type`）：`list_run_id` / `content_run_id` 始终存在，
  ///   但对应脚本**空字符串**时值为 `null`（让 Agent 明确看到 null，区分"未注册"
  ///   和"已注册"两种状态）。
  /// - 单查模式（传 `script_type`）：只校验/只注册请求的那一种，返回更精简。
  Future<String> _getCachedScript(Map<String, dynamic> args) async {
    final domain = args['domain'] as String?;
    final rawScriptType = args['script_type'] as String?;
    // 仅接受 chapter_list / chapter_content / bookshelf，其它值（null/乱填）走全查兜底
    final scriptType = (rawScriptType == 'chapter_list' ||
            rawScriptType == 'chapter_content' ||
            rawScriptType == 'bookshelf')
        ? rawScriptType
        : null;
    final url = _currentUrl;

    // 提取域名
    final uri = Uri.tryParse(url);
    final effectiveDomain = domain ?? uri?.host ?? '';

    if (effectiveDomain.isEmpty) {
      return jsonEncode({
        'error': 'missing_domain',
        'message': '无法确定域名',
        'current_url': url,
        'suggestion': '当前页面 URL 无法解析出域名。请传入 domain 参数（如 "www.example.com"）',
      });
    }

    /// 查询数据库（SQL 细节见 webview_extract_script_db.dart）
    final List<Map<String, dynamic>> results;
    try {
      results = await WebViewExtractScriptDb.queryByDomain(_ref, effectiveDomain);
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '查询缓存脚本失败: domain=$effectiveDomain - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['agent', 'webview-extract', 'get_cached_script', 'db_error'],
      );
      return jsonEncode({
        'error': 'DB_QUERY_FAILED',
        'message': '查询缓存脚本数据库失败: $e',
        'domain': effectiveDomain,
        'suggestion': '数据库可能被锁或损坏，请重试 get_cached_script',
      });
    }

    if (results.isEmpty) {
      // 整域名无记录：所有类型都列在 missing
      return jsonEncode({
        'found': false,
        'domain': effectiveDomain,
        if (scriptType != null) 'script_type': scriptType,
        'present': <String>[],
        'missing': switch (scriptType) {
          'chapter_list' => <String>['chapter_list'],
          'chapter_content' => <String>['chapter_content'],
          'bookshelf' => <String>['bookshelf'],
          _ => <String>['chapter_list', 'chapter_content', 'bookshelf'],
        },
        'message': scriptType == null
            ? '该域名无缓存脚本，需要新生成提取脚本'
            : '该域名 $scriptType 脚本缺失',
        'suggestion': scriptType == null
            ? '请用 execute_js(script=...) 测试新脚本，测试通过后用 save_script(domain, run_id, script_type=chapter_list, test_url=..., ocr=...) 和 save_script(..., script_type=chapter_content, ...) 分两次落库'
            : '请用 execute_js(script=...) 测试新脚本，测试通过后用 save_script(domain, run_id, script_type=$scriptType, test_url=..., ocr=...) 保存',
      });
    }

    // 取最近使用的一个脚本，注册到 RunStore 并返回 run_id
    final row = results.first;
    final listJs = (row['chapter_list_js'] as String? ?? '').trim();
    final contentJs = (row['chapter_content_js'] as String? ?? '').trim();
    final bookshelfJs = (row['bookshelf_js'] as String? ?? '').trim();
    final dbId = row['id'] as String;

    final hasList = listJs.isNotEmpty;
    final hasContent = contentJs.isNotEmpty;
    final hasBookshelf = bookshelfJs.isNotEmpty;
    final present = <String>[
      if (hasList) 'chapter_list',
      if (hasContent) 'chapter_content',
      if (hasBookshelf) 'bookshelf',
    ];
    final missing = <String>[
      if (!hasList) 'chapter_list',
      if (!hasContent) 'chapter_content',
      if (!hasBookshelf) 'bookshelf',
    ];

    // 单查模式：只处理请求的那一种，未命中走 found=false 分支
    if (scriptType != null && !present.contains(scriptType)) {
      LoggerService.instance.i(
        '查询缓存脚本: domain=$effectiveDomain, type=$scriptType, missing',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'get_cached_script', 'missing'],
      );
      return jsonEncode({
        'found': false,
        'domain': effectiveDomain,
        'script_type': scriptType,
        'present': present,
        'missing': <String>[scriptType],
        'message': '该域名 $scriptType 脚本缺失',
        'suggestion':
            '请用 execute_js(script=...) 测试新脚本，测试通过后用 save_script(domain, run_id, script_type=$scriptType, test_url=..., ocr=...) 保存',
      });
    }

    // 注册到 RunStore（db_xxx 形式）
    // 单查模式：只注册请求的那一种；全查模式：注册所有非空的，空项保持 null
    final String? listRunId;
    final String? contentRunId;
    final String? bookshelfRunId;
    switch (scriptType) {
      case 'chapter_list':
        listRunId = _registerDbScript(
          scriptJs: listJs,
          hasScript: hasList,
          dbId: dbId,
          domain: effectiveDomain,
        );
        contentRunId = null;
        bookshelfRunId = null;
      case 'chapter_content':
        contentRunId = _registerDbScript(
          scriptJs: contentJs,
          hasScript: hasContent,
          dbId: dbId,
          domain: effectiveDomain,
        );
        listRunId = null;
        bookshelfRunId = null;
      case 'bookshelf':
        bookshelfRunId = _registerDbScript(
          scriptJs: bookshelfJs,
          hasScript: hasBookshelf,
          dbId: dbId,
          domain: effectiveDomain,
        );
        listRunId = null;
        contentRunId = null;
      default:
        // 全查模式：只注册非空项，空项保持 null
        listRunId = _registerDbScript(
          scriptJs: listJs,
          hasScript: hasList,
          dbId: dbId,
          domain: effectiveDomain,
        );
        contentRunId = _registerDbScript(
          scriptJs: contentJs,
          hasScript: hasContent,
          dbId: dbId,
          domain: effectiveDomain,
        );
        bookshelfRunId = _registerDbScript(
          scriptJs: bookshelfJs,
          hasScript: hasBookshelf,
          dbId: dbId,
          domain: effectiveDomain,
        );
    }

    LoggerService.instance.i(
      '查询缓存脚本: domain=$effectiveDomain, present=$present, missing=$missing, list=$listRunId, content=$contentRunId, bookshelf=$bookshelfRunId',
      category: LogCategory.ai,
      tags: ['agent', 'webview-extract', 'get_cached_script'],
    );

    // 组装 hint，引导 Agent 补缺失项
    final hintParts = <String>[];
    if (hasList && listRunId != null) {
      hintParts.add('execute_js(run_id=$listRunId) 重跑目录脚本');
    }
    if (hasContent && contentRunId != null) {
      hintParts.add('execute_js(run_id=$contentRunId) 重跑内容脚本');
    }
    if (hasBookshelf && bookshelfRunId != null) {
      hintParts.add('execute_js(run_id=$bookshelfRunId) 重跑书架脚本');
    }
    final String message;
    if (missing.isEmpty) {
      message = '已加载缓存脚本到 RunStore。用 ${hintParts.join('，')}';
    } else {
      final missingSaveHint = missing
          .map((t) =>
              'save_script(domain, run_id, script_type=$t, test_url=..., ocr=...)')
          .join(' 和 ');
      message =
          '已加载 ${present.join('+')} 脚本到 RunStore（${hintParts.join('，')}）。'
          '${missing.join('、')} 缺失 → 生成后用 $missingSaveHint 补全';
    }

    return jsonEncode({
      // found 表示「有可用脚本可执行」，全部为空（异常数据）算作无
      'found': present.isNotEmpty,
      'domain': effectiveDomain,
      if (scriptType != null) 'script_type': scriptType,
      'present': present,
      'missing': missing,
      'id': dbId,
      'list_run_id': listRunId,
      'content_run_id': contentRunId,
      'bookshelf_run_id': bookshelfRunId,
      'use_count': row['use_count'],
      'verified': row['verified'],
      'url_pattern': row['url_pattern'],
      'sample_url': row['sample_url'],
      'message': message,
      if (missing.isNotEmpty)
        'suggestion':
            '请针对 ${missing.join('、')} 单独生成脚本并 save_script 补全；已有项 ${present.join('+')} 可直接 execute_js(run_id=...) 重跑',
    });
  }

  /// 将数据库脚本登记到 RunStore（`db_<rawId>` 句柄）。
  ///
  /// _getCachedScript 原有四份逐字重复的 _runStore.put 调用
  /// （单查/全查 × list/content/bookshelf），收敛到此参数化辅助方法；
  /// [hasScript] 为 false 时不注册、返回 null（全查模式下空项保持 null）。
  String? _registerDbScript({
    required String scriptJs,
    required bool hasScript,
    required String dbId,
    required String domain,
  }) {
    if (!hasScript) return null;
    return _runStore.put(
      script: scriptJs,
      success: true,
      source: RunEntrySource.database,
      rawId: dbId,
      domain: domain,
    );
  }

  /// 通知 UI 层脚本已落库（刷新脚本列表 + 失效当前站点脚本缓存）。
  void _notifyScriptSaved() {
    _ref.read(siteScriptListProvider.notifier).refresh();
    _ref.invalidate(webviewCurrentSiteScriptProvider);
  }

  /// save_script：按 script_type 分次保存，落库前强制试运行验证。
  ///
  /// ## 设计（落库前强制验证）
  ///
  /// 旧逻辑：直接读 RunStore 脚本 → 校验 → 一次 upsertByDomain 写两段。
  /// 新逻辑：分次保存（scheme/agent 协议决定），每次 save_script 只存**一种**
  /// script_type，且**必须**先在 test_url 上跑通验证脚本（含 OCR 验证 if ocr=true），
  /// 再调用 `updateScriptPart` 落库。
  ///
  /// 业务流程拆解：
  /// 1. agent 用 `execute_js(script=...)` 测试 → 返回 `__meta.run_id`
  /// 2. agent 用 `save_script(domain, run_id, script_type=chapter_list, test_url, ocr)`
  ///    → 后端加载 test_url → 跑脚本 → 结构校验 → （ocr=true 时）OCR 验证 →
  ///    `updateScriptPart(domain, script_type=chapter_list, ...)` 落库
  /// 3. 同理 chapter_content 走第二步
  /// 4. list 与 content 的 ocr 各自独立判定，落库到 site_scripts 对应列
  ///    （chapter_list_ocr / chapter_content_ocr），互不覆盖
  ///
  /// ## 测试入口
  ///
  /// 核心验证流程已抽成 static [validateAndPersistScript]（委托
  /// WebViewExtractScriptValidator），单测通过 mock SiteScriptRepository /
  /// OcrRestoreService 注入 jsResult 覆盖。
  /// executor 自身（涉及 HeadlessWebViewPool 平台依赖）只能走集成测试。
  ///
  /// ## 执行流程（拆分为阶段方法）
  ///
  /// 1. 解析参数（domain/run_id/script_type/test_url/ocr）
  /// 2. RunStore.get(run_id) 取脚本
  /// 3. 复用场景 _webviewController → loadPage(test_url) → callAsyncJavaScript(script)
  ///    （不重新 pool.acquire，否则与场景已持有的锁互锁，详见方法内注释）
  /// 4. 结构校验（按 script_type）
  /// 5. ocr=true → OcrRestoreService 验证（verifyFontFamily + restorePuaInText + readableRatio）
  /// 6. 全通过 → updateScriptPart 落库；失败返回诊断 JSON
  ///
  /// 核心校验逻辑在 [validateAndPersistScript]（静态，可单测）；
  /// 本方法只负责参数解析 + WebView 执行 + 异常映射。
  Future<String> _saveScript(Map<String, dynamic> args) async {
    // ── 阶段一：解析参数 + 目标安全性校验（错误 JSON 已构造好，直接返回）──
    final parsed = _parseSaveScriptArgs(args);
    final validationError = parsed.error ??
        _validateSaveScriptTargets(
          domain: parsed.domain,
          scriptType: parsed.scriptType,
          testUrl: parsed.testUrl,
        );
    if (validationError != null) return validationError;

    // bookshelf（网站书架脚本）不适用 OCR：书架页提取的是标题+链接，
    // 无字体反爬还原需求。强制按 ocr=false 走验证与落库。
    final effectiveOcr = parsed.scriptType == 'bookshelf' ? false : parsed.ocr;

    // ── 阶段二：RunStore 取脚本 ──
    final entry = _runStore.get(parsed.runId);
    if (entry == null) return _runIdNotFoundJson(parsed.runId);
    final scriptJs = entry.script;

    // 复用场景已持有的 _webviewController 跑脚本（Headless 模式下即
    // HeadlessWebViewPool acquire 出的同一实例）。**不能**再次 pool.acquire()——
    // 否则与场景已持有的排他锁互锁（30s 超时），表现为 save_script "120s 超时"。
    // execute_js 同样直接用 _webviewController，故两者行为/计时一致。
    // 注意也不在此处调 pool.release()——释放由场景 cleanup 钩子统一负责
    // （见 AgentScenarioFactory.build），否则会把场景已持有的锁错误释放。
    final controller = _webviewController;
    try {
      // ── 阶段三：加载 test_url 试运行脚本（loadUrl + 轮询等待 + 执行）──
      final run = await _runScriptOnTestUrl(controller, scriptJs, parsed.testUrl);
      if (run.error != null) return run.error!;

      // ── 阶段四：结构校验 + OCR 验证 + 落库（委托可单测的静态方法）──
      LoggerService.instance.i(
        'save_script: 开始 validateAndPersistScript domain=${parsed.domain} scriptType=${parsed.scriptType} ocr=$effectiveOcr',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'save_script', 'validate-begin'],
      );
      final outcome = await validateAndPersistScript(
        domain: parsed.domain,
        scriptType: parsed.scriptType,
        ocr: effectiveOcr,
        scriptJs: scriptJs,
        jsResult: run.jsResult,
        repo: _ref.read(siteScriptRepositoryProvider),
        restoreService: _buildRestoreService(controller, effectiveOcr),
        testUrl: parsed.testUrl, // 记录验证页 URL（bookshelf 刷新同步用它定位书架页）
        displayName: parsed.displayName,
        preferredMode:
            BrowserSettingsService.desktopModeSync ? 1 : 2, // v46 起记录创作模式
      );

      if (outcome['success'] == true) {
        _scriptSavedThisSession = true;
        _notifyScriptSaved();
      }
      return jsonEncode(outcome);
    } on TimeoutException {
      // 兜底主脚本 .timeout(120s)。OCR 渲染超时（30s）已被内部 try/catch
      // 转为 ocr_verify_timeout，不会走到这里。
      return jsonEncode({
        'success': false,
        'reason': 'test_timeout',
        'message': '主脚本在 test_url 上执行超时(>120s)',
        'suggestion': '脚本可能卡在翻页/等待，检查 setTimeout 和翻页逻辑',
      });
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        'save_script 验证异常: domain=${parsed.domain} - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'save_script', 'error'],
      );
      return jsonEncode({
        'success': false,
        'reason': 'internal_error',
        'message': '$e',
      });
    }
  }

  /// save_script 参数解析（阶段一）
  ///
  /// [error] 非 null 表示参数错误（错误 JSON 已构造好，其余字段无意义）。
  ({
    String? error,
    String domain,
    String runId,
    String scriptType,
    String testUrl,
    bool ocr,
    String? displayName,
  }) _parseSaveScriptArgs(Map<String, dynamic> args) {
    final parser = ToolArgParser(args);
    final (domain, e1) = parser.requireString('domain');
    final (runId, e2) = parser.requireString('run_id');
    final (scriptType, e3) = parser.requireString('script_type');
    final (testUrl, e4) = parser.requireString('test_url');
    final (ocr, e5) = parser.requireBool('ocr');
    // 可选：站点显示名（书架 Tab 优先显示，空/缺省回退 host）
    final (displayName, _) = parser.optionalString('display_name');

    for (final err in [e1, e2, e3, e4, e5]) {
      if (err != null) {
        return (
          error: err, // 参数错误直接返回（错误 JSON 已构造好）
          domain: '',
          runId: '',
          scriptType: '',
          testUrl: '',
          ocr: false,
          displayName: null,
        );
      }
    }
    return (
      error: null,
      domain: domain,
      runId: runId,
      scriptType: scriptType,
      testUrl: testUrl,
      ocr: ocr,
      displayName: displayName,
    );
  }

  /// save_script 目标安全性校验（test_url / domain / script_type，阶段二）
  ///
  /// 返回 null 表示通过；否则返回错误 JSON（直接作为工具结果）。
  ///
  /// 安全校验（2026-09 审查必修项）：
  /// 1) test_url 必须是 http(s) 绝对地址 — 与 _navigateTo 同强度，
  ///    防止 LLM 被提示注入后传 file:///、javascript: 等伪协议加载；
  /// 2) domain 必须是合法主机名 — 落库为 site_scripts.domain 主键，
  ///    后续 HeadlessWebView*Service 会在用户访问该域名时回放脚本，
  ///    恶意/伪造 domain 会把脚本注入到用户真实浏览的站点。
  String? _validateSaveScriptTargets({
    required String domain,
    required String scriptType,
    required String testUrl,
  }) {
    final testUri = Uri.tryParse(testUrl);
    if (testUri == null ||
        !testUri.isAbsolute ||
        (testUri.scheme != 'http' && testUri.scheme != 'https') ||
        testUri.host.isEmpty) {
      return jsonEncode({
        'error': 'INVALID_TEST_URL',
        'message': 'test_url 必须是带主机名的 http(s) 绝对地址: $testUrl',
        'suggestion': '请传入完整的站点页面 URL（包含 http/https 与主机名）',
      });
    }
    final domainPattern = RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9.\-]*[a-zA-Z0-9])?$');
    if (!domainPattern.hasMatch(domain) || !domain.contains('.')) {
      return jsonEncode({
        'error': 'INVALID_DOMAIN',
        'message': 'domain 必须是合法主机名（仅字母/数字/点/连字符）: $domain',
        'suggestion': '请传入站点真实域名，如 www.example.com',
      });
    }
    // domain 与 test_url 主机一致性：防止把 A 站脚本持久化到 B 站域名下
    final testHost = testUri.host.toLowerCase();
    final domainHost = domain.toLowerCase();
    if (testHost != domainHost && !testHost.endsWith('.$domainHost')) {
      return jsonEncode({
        'error': 'DOMAIN_MISMATCH',
        'message': 'domain($domain) 与 test_url 主机($testHost)不一致',
        'suggestion': 'domain 必须与 test_url 的主机名一致（或为其父域）',
      });
    }

    if (scriptType != 'chapter_list' &&
        scriptType != 'chapter_content' &&
        scriptType != 'bookshelf') {
      return jsonEncode({
        'error': 'invalid_script_type',
        'message': 'script_type 必须是 chapter_list、chapter_content 或 bookshelf',
        'received': scriptType,
      });
    }
    return null;
  }

  /// save_script 找不到 run_id 时的错误返回（阶段二失败出口）
  String _runIdNotFoundJson(String runId) {
    return jsonEncode({
      'success': false,
      'reason': 'run_id_not_found',
      'message': 'RunStore 中未找到 run_id（可能已被淘汰）',
      'run_id': runId,
      'store_size': _runStore.length,
      'suggestion': '用 execute_js(script=...) 重新执行脚本获取新 run_id',
    });
  }

  /// 构造 OCR 还原服务（ocr=true 时通过 controller 渲染 PUA；
  /// bookshelf 已强制 effectiveOcr=false，不构造）。
  OcrRestoreService? _buildRestoreService(
    InAppWebViewController controller,
    bool effectiveOcr,
  ) {
    if (!effectiveOcr) return null;
    return OcrRestoreService(
      _ref,
      (cp, ff) => _renderPuaViaController(controller, cp, ff),
    );
  }

  /// 在场景 controller 上加载 test_url 并试运行脚本（阶段三）
  ///
  /// HeadlessWebViewPool 的 WebView 构造时**未注册 onLoadStop**，沿用
  /// [_waitControllerForUrl] 的 URL 字符串轮询等待。
  ///
  /// 返回 (error: null, jsResult: 已解码的脚本返回值)；执行失败时 error 为
  /// js_execute_failed 诊断 JSON。TimeoutException 由调用方统一映射。
  Future<({String? error, dynamic jsResult})> _runScriptOnTestUrl(
    InAppWebViewController controller,
    String scriptJs,
    String testUrl,
  ) async {
    // 加载 test_url（_webviewController 无 onLoadStop 注册，用 URL 轮询等待）
    LoggerService.instance.i(
      'save_script: loadUrl(test_url=$testUrl)',
      category: LogCategory.ai,
      tags: ['agent', 'webview-extract', 'save_script', 'loadurl'],
    );
    final tLoad = DateTime.now();
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(testUrl)));
    await _waitControllerForUrl(controller, testUrl);
    LoggerService.instance.i(
      'save_script: loadUrl 完成 耗时=${DateTime.now().difference(tLoad).inMilliseconds}ms',
      category: LogCategory.ai,
      tags: ['agent', 'webview-extract', 'save_script', 'loadurl-done'],
    );

    // 替换 {{URL}} → test_url（提取脚本约定含 {{URL}}）
    final resolved = WebViewJsExecutor.replaceUrlPlaceholder(scriptJs, testUrl);
    final functionBody = WebViewJsExecutor.extractAsyncFunctionBody(resolved);
    LoggerService.instance.i(
      'save_script: 执行提取脚本 scriptLen=${resolved.length} bodyLen=${functionBody.length}',
      category: LogCategory.ai,
      tags: ['agent', 'webview-extract', 'save_script', 'extract-begin'],
    );
    final tExtract = DateTime.now();
    final result = await controller
        .callAsyncJavaScript(functionBody: functionBody)
        .timeout(const Duration(seconds: 120));
    LoggerService.instance.i(
      'save_script: 提取脚本完成 耗时=${DateTime.now().difference(tExtract).inMilliseconds}ms error=${result?.error}',
      category: LogCategory.ai,
      tags: ['agent', 'webview-extract', 'save_script', 'extract-done'],
    );
    if (result == null || result.error != null) {
      return (
        error: jsonEncode({
          'success': false,
          'reason': 'js_execute_failed',
          'diagnostic': '脚本在 test_url 上执行失败',
          'js_error': result?.error?.toString(),
          'suggestion': '检查脚本选择器是否匹配该页面，或页面是否需要等待加载',
        }),
        jsResult: null,
      );
    }
    final jsonStr = WebViewJsExecutor.stringifyJsResult(result.value);
    return (error: null, jsResult: jsonDecode(jsonStr));
  }

  /// 在 pool controller 上轮询等待页面 URL 匹配 [targetUrl]。
  ///
  /// HeadlessWebViewPool 的 WebView 构造时**未注册 onLoadStop**（_ensureReady
  /// 用 `HeadlessInAppWebView(onWebViewCreated: ...)` 无 onLoadStop 参数），
  /// 因此 WebViewPageLoader 的事件驱动等待在此不可用，沿用 getUrl 字符串轮询。
  /// 超时信任 loadUrl 调用本身（同 [_ensureHeadlessPageLoaded] 的超时信任策略）。
  Future<void> _waitControllerForUrl(
    InAppWebViewController controller,
    String targetUrl,
  ) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < _pageLoadTimeout) {
      await Future.delayed(_pollInterval);
      try {
        final current = await controller.getUrl();
        if (current != null && current.toString() == targetUrl) {
          await Future.delayed(_domStabilizeDelay);
          return;
        }
      } catch (_) {
        // 轮询getUrl 偶尔失败继续等
      }
    }
    // 超时不抛：Headless WebView getUrl 在某些平台不更新，信任 loadUrl 调用
    LoggerService.instance.w(
      'save_script: test_url 轮询等待超时，信任 loadUrl 调用 url=$targetUrl',
      category: LogCategory.ai,
      tags: ['agent', 'webview-extract', 'save_script', 'page-wait-timeout'],
    );
    await Future.delayed(_headlessTrustDelay);
  }

  /// 通过 pool controller 跑 OCR-JS（渲染单个 PUA 码点 → base64 PNG）。
  ///
  /// 复用 [buildOcrRenderJs]（系统内置 OCR-JS 模板），
  /// 返回 base64 字符串（不带 `data:image/png;base64,` 前缀）。
  ///
  /// 抛异常：[TimeoutException]（>30s）或脚本执行错误。
  Future<String> _renderPuaViaController(
    InAppWebViewController controller,
    int codepoint,
    String fontFamily,
  ) async {
    final js = buildOcrRenderJs(codepoint, fontFamily);
    final functionBody = WebViewJsExecutor.extractAsyncFunctionBody(js);
    final t0 = DateTime.now();
    // 关键诊断：渲染前先探测 WebView 当前 URL + 一个最简单的 JS 调用耗时
    String? preProbeUrl;
    int? preProbeMs;
    try {
      preProbeUrl = (await controller.getUrl())?.toString();
      final tp = DateTime.now();
      await controller
          .callAsyncJavaScript(functionBody: 'return 1;')
          .timeout(const Duration(seconds: 5));
      preProbeMs = DateTime.now().difference(tp).inMilliseconds;
    } catch (e) {
      preProbeMs = -1;
      preProbeUrl = 'probe_err: $e';
    }
    LoggerService.instance.i(
      'OCR 渲染开始 cp=0x${codepoint.toRadixString(16)} fontFamily=$fontFamily | '
      '渲染前探测: url=$preProbeUrl, callAsyncJS(1)耗时=${preProbeMs}ms',
      category: LogCategory.ai,
      tags: ['agent', 'webview-extract', 'save_script', 'ocr-render', 'begin'],
    );
    try {
      final result = await controller
          .callAsyncJavaScript(functionBody: functionBody)
          .timeout(const Duration(seconds: 30));
      final ms = DateTime.now().difference(t0).inMilliseconds;
      LoggerService.instance.i(
        'OCR 渲染完成 cp=0x${codepoint.toRadixString(16)} 耗时=${ms}ms '
        'error=${result?.error} valueType=${result?.value.runtimeType}',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'save_script', 'ocr-render', 'end'],
      );
      if (result == null || result.error != null) {
        throw Exception(
          'OCR 渲染失败 cp=0x${codepoint.toRadixString(16)}: ${result?.error}',
        );
      }
      final value = result.value;
      if (value is String) return value; // base64 字符串，原样返回
      throw Exception('OCR 渲染返回非字符串: $value');
    } on TimeoutException {
      final ms = DateTime.now().difference(t0).inMilliseconds;
      // 诊断：超时后立即测一个简单的 callAsyncJavaScript，判断 WebView 通道是否还活着
      String? probeResult;
      int? probeMs;
      try {
        final tp = DateTime.now();
        final probe = await controller
            .callAsyncJavaScript(functionBody: 'return 1;')
            .timeout(const Duration(seconds: 5));
        probeMs = DateTime.now().difference(tp).inMilliseconds;
        probeResult = probe?.error ?? probe?.value?.toString();
      } catch (e) {
        probeMs = -1;
        probeResult = 'PROBE_FAILED: $e';
      }
      // 超时后再查一次 URL，判断页面是否被导航走了
      String? postUrl;
      try {
        postUrl = (await controller.getUrl())?.toString();
      } catch (_) {
        postUrl = 'getUrl_failed';
      }
      LoggerService.instance.e(
        '【OCR超时诊断】cp=0x${codepoint.toRadixString(16)} 渲染耗时=${ms}ms fontFamily=$fontFamily | '
        '渲染前探测: url=$preProbeUrl callAsyncJS(1)=${preProbeMs}ms | '
        '超时后探测: url=$postUrl callAsyncJS(1)=${probeMs}ms → $probeResult',
        category: LogCategory.ai,
        tags: ['agent', 'webview-extract', 'save_script', 'ocr-render', 'timeout'],
      );
      rethrow;
    }
  }

  /// 验证脚本结果并落库（可单测，绕开 WebView 平台依赖）。
  ///
  /// 静态转发入口：实现已抽到 [WebViewExtractScriptValidator.validateAndPersistScript]
  /// （结构校验 → OCR 验证 → 落库编排，见 webview_extract_script_validator.dart）。
  /// 保留原签名，单测（save_script_tool_test.dart）与既有调用方零改动。
  @visibleForTesting
  static Future<Map<String, dynamic>> validateAndPersistScript({
    required String domain,
    required String scriptType,
    required bool ocr,
    required String scriptJs,
    required dynamic jsResult,
    required SiteScriptRepository repo,
    OcrRestoreService? restoreService,
    String? testUrl,
    String? displayName,
    int? preferredMode,
  }) {
    return WebViewExtractScriptValidator.validateAndPersistScript(
      domain: domain,
      scriptType: scriptType,
      ocr: ocr,
      scriptJs: scriptJs,
      jsResult: jsResult,
      repo: repo,
      restoreService: restoreService,
      testUrl: testUrl,
      displayName: displayName,
      preferredMode: preferredMode,
    );
  }

  /// 列出所有已保存脚本
  Future<String> _listCachedScripts() async {
    final results = await WebViewExtractScriptDb.listRecent(_ref);

    final scripts = results.map((row) => {
          'id': row['id'],
          'domain': row['domain'],
          'urlPattern': row['url_pattern'],
          'useCount': row['use_count'],
          'verified': row['verified'],
          'lastUsedAt': row['last_used_at'],
        }).toList();

    return jsonEncode({
      'count': scripts.length,
      'scripts': scripts,
    });
  }

  /// 查看 RunStore 中某条 run_id 的完整脚本内容
  ///
  /// 调试用：当 AI 需要查看/修改一段已注册的脚本（如 debug execute_js 失败、
  /// 改写缓存脚本）时，用本工具拿到完整脚本，而不是从上下文里翻历史。
  ///
  /// 注意：返回完整脚本会占用上下文，**非必要时不要调用**。
  Future<String> _inspectScript(Map<String, dynamic> args) async {
    final runId = args['run_id'] as String?;
    if (runId == null || runId.isEmpty) {
      return jsonEncode({
        'error': 'missing_param',
        'message': '缺少 run_id 参数',
        'missing': ['run_id'],
        'suggestion': '请传入要查看的 run_id（来自 execute_js 的 __meta.run_id 或 get_cached_script 的 list_run_id/content_run_id）',
      });
    }

    final entry = _runStore.get(runId);
    if (entry == null) {
      return jsonEncode({
        'error': 'RUN_ID_NOT_FOUND',
        'message': '未找到 $runId（可能已被淘汰或未注册）',
        'store_size': _runStore.length,
        'suggestion': 'RunStore 有容量限制（50 条 LRU 淘汰）。若是 database 来源的 id，请重新调用 get_cached_script 加载',
      });
    }

    return jsonEncode({
      'run_id': entry.runId,
      'script': entry.script,
      'success': entry.success,
      'source': entry.source.name,
      'script_length': entry.script.length,
      if (entry.testUrl != null) 'test_url': entry.testUrl,
      if (entry.resultSummary != null) 'result_summary': entry.resultSummary,
      if (entry.domain != null) 'domain': entry.domain,
    });
  }

  /// 列出当前 WebView 捕获的 AJAX 请求（URL / 参数 / 请求头）。
  ///
  /// 用于分析网页接口模式、辅助编写章节提取脚本。
  /// 不采集响应体；POST body 因平台限制也不采集。
  /// 页面跳转后历史自动清空。
  Future<String> _listNetworkRequests(Map<String, dynamic> args) async {
    final parser = ToolArgParser(args);
    final (urlContains, urlErr) = parser.optionalString('url_contains');
    if (urlErr != null) return urlErr;
    final (method, methodErr) = parser.optionalString('method');
    if (methodErr != null) return methodErr;
    final (sinceIndex, sinceErr) = parser.optionalInt('since_index');
    if (sinceErr != null) return sinceErr;
    final (limit, limitErr) = parser.optionalInt('limit');
    if (limitErr != null) return limitErr;

    final snap = _networkRecorder.snapshot(
      urlContains: urlContains,
      method: method,
      sinceIndex: sinceIndex,
      limit: limit ?? 50,
    );
    return jsonEncode(snap);
  }

  /// 查询爬虫运行日志（LogCategory.crawler，最近 30 条，可按成功/失败筛选）
  ///
  /// AI 在对话中用 execute_js 测试脚本时，脚本能跑通不代表真实使用也能成功。
  /// 本工具让 AI 查看 HeadlessWebView 在阅读器/FAB添加小说/获取书架等真实场景中
  /// 执行脚本时的错误、超时、空结果等日志，定位"脚本能跑通但实际抓取失败"的问题。
  ///
  /// 数据来源：所有 category=crawler 的日志（章节内容/目录/书架获取、
  /// WebView 池、脚本面板试运行、预加载抓取）。
  ///
  /// 筛选规则：
  /// - success → 带 success 标签的成功记录
  /// - failure → 级别 ≥ warning 的记录（爬虫栈中 warning/error 均代表失败或异常）
  /// - all（默认）→ 不过滤
  Future<String> _getScriptLogs([Map<String, dynamic>? args]) async {
    final outcome = args?['outcome'] as String? ?? 'all';
    final sorted = LoggerService.instance
        .getLogsByCategory(LogCategory.crawler)
        .reversed
        .where((log) {
      switch (outcome) {
        case 'success':
          return log.tags.contains('success');
        case 'failure':
          return log.level.index >= LogLevel.warning.index;
        default:
          return true;
      }
    }).take(30).toList();

    if (sorted.isEmpty) {
      return jsonEncode({
        'found': false,
        'outcome': outcome,
        'message': '暂无爬虫运行日志（可能尚未在阅读器中使用过，或日志已被清理）',
        'suggestion': '如果脚本刚保存，需要在阅读器中打开该网站的章节后才会产生运行日志',
      });
    }

    return jsonEncode({
      'found': true,
      'outcome': outcome,
      'count': sorted.length,
      'logs': sorted.map((log) {
        final msg = log.message.length > 300
            ? '${log.message.substring(0, 300)}...'
            : log.message;
        return {
          'time': LoggerService.formatTimestamp(log.timestamp),
          'level': log.level.label,
          'message': msg,
          'tags': log.tags,
        };
      }).toList(),
    });
  }
}
