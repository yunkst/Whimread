import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screens/bookshelf_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/webview_browser_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/resource_bootstrap/resource_bootstrap_screen.dart';
import 'services/app_update_service.dart';
import 'services/app_resource_manager.dart' show ResourceItemStatus;
import 'services/app_update_result.dart';
import 'core/providers/service_providers.dart';
import 'core/providers/image_model_download_providers.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/onboarding_providers.dart';
import 'core/providers/ui_providers.dart';
import 'core/providers/agent_scenario_provider.dart';
import 'core/providers/device_quota_provider.dart';
import 'core/providers/resource_bootstrap_providers.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_typography.dart';
import 'utils/toast_utils.dart';
import 'services/ai/llm_usage_notifier.dart';
import 'services/device/device_auth_service.dart';
import 'services/feedback_service.dart';
import 'services/logger_service.dart';
import 'services/llm_logger/llm_logger.dart';
import 'services/log_reporter_service.dart';
import 'services/managed_models/managed_model_service.dart';
import 'services/native_crash_reporter.dart' show kGitHubRepo, NativeCrashReporter;
import 'services/novel_agent/agent_scenario.dart';
import 'services/star_prompt_service.dart';
import 'services/startup_prompts_runner.dart';
import 'widgets/agent_chat/agent_floating_button.dart';
import 'widgets/app_update_dialog.dart';
import 'widgets/star_prompt_dialog.dart';
import 'widgets/startup_splash.dart';

/// 已记录的全局异常签名 hash（前 200 字符）集合，用于去重。
///
/// 4 层全局异常捕获可能对同一条异常触发多次回调，
/// 此函数对签名去重避免日志中重复 2-3 次。
///
/// 容量上限 8 条；溢出时按 FIFO 移除最早插入的条目（而非 LRU），
/// 因为这里只想压住同一异常的重复上报，不需要"最近最常抛出"的语义。
final _seenErrorSignatures = <int>{};

/// 应用标题（用于 MaterialApp.title，在任务切换器/窗口标题上展示）。
/// 遵循项目规则：UI 文案中文、品牌名「随心阅读」。
const String kAppTitle = '随心阅读';

/// 启动期对账：进程被杀遗留的 downloading/converting 行归位为
/// paused/failed（可续传/可重试）。异步执行，失败仅记日志，不阻塞启动。
Future<void> _recoverImageModelDownloads(ProviderContainer container) async {
  try {
    await container.read(imageModelDownloadServiceProvider).recoverOnStartup();
  } catch (e) {
    LoggerService.instance.w(
      '生图模型下载对账失败: $e',
      category: LogCategory.general,
      tags: ['startup', 'image-model', 'recover'],
    );
  }
}

/// 记录全局异常（带去重）。
///
/// 4 层全局异常捕获可能对同一条异常触发多次回调，
/// 此函数对签名去重避免日志中重复 2-3 次。
void _logGlobalError(String source, Object error, StackTrace? stack,
    {LogCategory category = LogCategory.general}) {
  final raw = error.toString();
  final sig = raw.length > 200 ? raw.substring(0, 200).hashCode : raw.hashCode;
  if (_seenErrorSignatures.contains(sig)) return;
  _seenErrorSignatures.add(sig);
  if (_seenErrorSignatures.length > 8) {
    _seenErrorSignatures.remove(_seenErrorSignatures.first);
  }

  LoggerService.instance.e(
    '[$source] $error',
    stackTrace: stack?.toString(),
    category: category,
    tags: [source, 'crash'],
  );
}

void main() async {
  // 确保 Flutter 初始化完成
  WidgetsFlutterBinding.ensureInitialized();

  // 强制竖屏：全平台统一锁定（Android manifest 已声明 portrait，
  // 这里兜住 iOS/桌面端；包 try 防止个别平台不支持时阻塞启动）
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } catch (e) {
    LoggerService.instance.w('竖屏锁定设置失败: $e', tags: ['startup']);
  }

  // 初始化日志服务
  await LoggerService.instance.init();
  LoggerService.instance.i(
    'LoggerService 初始化完成',
    category: LogCategory.general,
    tags: ['startup', 'logger'],
  );

  // 初始化 LLM 调用日志服务（拦截器在 llm_provider.dart 中调用，失败不阻塞）
  await LlmLogger.instance.initialize();
  LoggerService.instance.i(
    'LlmLogger 初始化完成',
    category: LogCategory.general,
    tags: ['startup', 'llm-logger'],
  );

  // 初始化日志上报服务（在 LoggerService 之后）
  try {
    await LogReporterService.instance.init();
    LoggerService.instance.i(
      'LogReporterService 初始化完成',
      category: LogCategory.general,
      tags: ['startup', 'log-reporter'],
    );
  } catch (e, stackTrace) {
    LoggerService.instance.e(
      'LogReporterService 初始化失败: $e',
      stackTrace: stackTrace.toString(),
      category: LogCategory.general,
      tags: ['startup', 'log-reporter', 'error'],
    );
  }

  // 启用详细的错误日志 - 全局错误处理器（带去重）
  FlutterError.onError = (FlutterErrorDetails details) {
    _logGlobalError('flutter-error', details.exception, details.stack,
        category: LogCategory.general);
  };

  // 捕获并记录所有 Widget 构建错误（带去重）— 在 main() 顶层一次性注册，
  // 不随 Widget rebuild 反复赋值；错误兜底页使用固定 dark 主题，
  // 保证 `context.appColors` 永远命中真实扩展而非兜底值。
  ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
    _logGlobalError('widget-error', errorDetails.exception, errorDetails.stack,
        category: LogCategory.ui);
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: kBrandSeedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Error Occurred')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.redAccent),
              const SizedBox(height: 16),
              const Text('An error occurred. Check console for details.'),
              const SizedBox(height: 8),
              Text(
                errorDetails.exception.toString(),
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  };

  // 捕获 isolate / 平台层异步错误（绕过 runZonedGuarded 的最后一道网）
  //
  // FlutterError.onError 只接管框架抛出的同步错误，runZonedGuarded 只接管 zone 内的
  // 未捕获异步错误；Dart VM / 平台通道 / isolate 抛出的部分错误会绕过这两者，需要在此兜底。
  // 返回 true 表示已处理，避免再走默认崩溃处理器（直接 crash 退出）。
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    _logGlobalError('platform', error, stack, category: LogCategory.general);
    return true;
  };

  // 捕获未处理的异步错误
  runZonedGuarded(() async {
    // 初始化 API 服务 - 使用Provider容器
    final container = ProviderContainer();
    try {
      final apiService = container.read(apiServiceWrapperProvider);
      await apiService.init();
      // 设备注册服务复用已初始化的 Dio 实例（AI 托管模式）；
      // 反向注入设备 JWT 请求头，备份/媒体/日志等请求以设备身份鉴权
      DeviceAuthService.instance.useWrapper(apiService);
      apiService.authHeaderProvider = DeviceAuthService.instance.authedHeaders;
      // 401 时经 wrapper 拦截器自动重注册换新 JWT（30 天凭证过期自愈）
      apiService.unauthorizedRecoveryProvider =
          DeviceAuthService.instance.renewAuthHeaders;
      await DeviceAuthService.instance.loadCached();

      // 共享 Dio 拓扑收口：日志上报 / 反馈提交 / 托管模型目录都挂到
      // apiService.dio，吃统一的 401 续签 + 拦截器链。
      // Dio 上的 QuietLogInterceptor 会尊重上报 / 反馈请求里的 quiet 标记。
      LogReporterService.instance.useDio(apiService.dio);
      FeedbackService.instance.useDio(apiService.dio);
      ManagedModelService.instance.useApiWrapper(apiService);
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        'API Service Error: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.network,
        tags: ['api', 'service', 'error'],
      );

      // 继续运行，用户可以在设置中配置
    }

    // 生图模型下载/转换的对账（异步执行，不阻塞启动）
    unawaited(_recoverImageModelDownloads(container));

    // 额度自动刷新桥：任何 LLM 请求到达终态 → 1.5s 防抖后强刷额度。
    // 注册在容器创建后、runApp 前后皆可；放 try 块外避免 apiService
    // 初始化失败时桥也一起丢失。
    LlmUsageNotifier.instance.addListener(() {
      container.read(deviceQuotaProvider.notifier).onAiUsage();
    });

    runApp(UncontrolledProviderScope(
      container: container,
      child: const NovelReaderApp(),
    ));

    // 动态资源（字体/OCR 模型/libsds.so）的启动校验与下载已移交
    // _ResourceGate → resourceBootstrapNotifierProvider（见 _AppRoot）。
  }, (error, stackTrace) {
    _logGlobalError('async-unhandled', error, stackTrace,
        category: LogCategory.general);
  });
}

class NovelReaderApp extends ConsumerWidget {
  const NovelReaderApp({super.key});

  /// 构建 Material 3 主题数据（统一 light/dark 两套 + loading/error 兜底）
  ///
  /// 亮/暗主题分别通过 [ThemeState] 提供（含 AppColors 扩展）；
  /// loading/error 兜底场景使用固定 dark 主题（同样注入 AppColors.dark），
  /// 保证 `context.appColors` 永远命中真实扩展而非兜底值。
  ThemeData _buildFallbackThemeData() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        // 书馆美学种子色，与 ThemeState 默认一致，避免启动闪蓝
        seedColor: kBrandSeedColor,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      fontFamily: AppTypography.sans,
      fontFamilyFallback: AppTypography.sansFallback,
      extensions: const <ThemeExtension<dynamic>>[AppColors.dark],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 监听主题提供者
    final themeAsync = ref.watch(themeNotifierProvider);

    // 同步主题色到 Toast 工具 — 通过 ref.listen 在主题变更时副作用执行，
    // 不再写在 build 方法体内，避免每次 rebuild 都覆盖全局 Toast 配置。
    ref.listen(themeNotifierProvider, (_, next) {
      next.whenData((themeState) {
        final platformBrightness = MediaQuery.platformBrightnessOf(context);
        final isLight = themeState.flutterThemeMode == ThemeMode.light ||
            (themeState.flutterThemeMode == ThemeMode.system &&
                platformBrightness == Brightness.light);
        ToastUtils.setThemeColors(isLight ? AppColors.light : AppColors.dark);
      });
    });

    // 系统主题下 Toast 颜色跟随平台亮度，保持与 MaterialApp 实际渲染一致
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    return themeAsync.when(
      data: (themeState) {
        final isLight = themeState.flutterThemeMode == ThemeMode.light ||
            (themeState.flutterThemeMode == ThemeMode.system &&
                platformBrightness == Brightness.light);
        // 首次渲染同步一次主题色（ref.listen 只在变更时触发，初始值需在这里补一次）
        ToastUtils.setThemeColors(isLight ? AppColors.light : AppColors.dark);
        return MaterialApp(
          title: kAppTitle,
          theme: themeState.getLightTheme(),
          darkTheme: themeState.getDarkTheme(),
          themeMode: themeState.flutterThemeMode,
          home: const _AppRoot(),
          debugShowCheckedModeBanner: true,
          builder: (context, child) {
            // 注：ErrorWidget.builder 已在 main() 顶层一次性注册，此处仅返回子组件。
            return child!;
          },
        );
      },
      loading: () {
        // 主题加载中：品牌开屏层（与原生启动屏同底色，无背景跳变）
        return MaterialApp(
          title: kAppTitle,
          theme: _buildFallbackThemeData(),
          home: const AppStartupSplash(),
          debugShowCheckedModeBanner: true,
        );
      },
      error: (error, stack) {
        LoggerService.instance.e(
          '主题加载失败: $error',
          stackTrace: stack.toString(),
          category: LogCategory.ui,
          tags: ['theme', 'load', 'error'],
        );
        // 错误时显示错误信息
        return MaterialApp(
          title: kAppTitle,
          theme: _buildFallbackThemeData(),
          home: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 64, color: context.appColors.error),
                const SizedBox(height: 16),
                Text('主题加载失败: $error'),
                const SizedBox(height: 8),
                const Text('使用默认主题继续运行'),
              ],
            ),
          ),
          debugShowCheckedModeBanner: true,
        );
      },
    );
  }
}

/// 应用根 Widget，根据 Onboarding 状态决定显示引导页还是主页
class _AppRoot extends ConsumerWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboardingAsync = ref.watch(onboardingNotifierProvider);

    return onboardingAsync.when(
      // onboarding 状态读取中：开屏层继续遮，避免深浅主题切换闪帧
      loading: () => const AppStartupSplash(),
      data: (onboardingState) {
        if (onboardingState.onboardingCompleted) {
          return const _ResourceGate(child: HomePage());
        }
        return const OnboardingScreen();
      },
      error: (error, stack) {
        // 加载失败时直接进入主页
        LoggerService.instance.e(
          '加载 Onboarding 状态失败，直接进入主页: $error',
          stackTrace: stack.toString(),
          category: LogCategory.general,
          tags: ['onboarding', 'error', 'fallback'],
        );
        return const HomePage();
      },
    );
  }
}

/// 动态资源门卫：onboarding 完成后、进首页前，先做一次启动资源校验/下载。
///
/// - 校验期间展示品牌开屏层（与原生启动屏/兜底主题同底色，
///   资源快路径下全程无背景跳变、无闪烁）；
/// - 有缺失且用户在本 manifest 版本内跳过过 → 放行（后台静默补下载）；
/// - 有缺失且未跳过 → 展示 ResourceBootstrapScreen（可跳过/重试）；
/// - manifest 拉取失败 → 放行（各功能按需降级，不比旧行为差）；
/// - 放行时首页在开屏层之上淡入，首页首帧构建被开屏层盖住。
class _ResourceGate extends ConsumerStatefulWidget {
  final Widget child;

  const _ResourceGate({required this.child});

  @override
  ConsumerState<_ResourceGate> createState() => _ResourceGateState();
}

class _ResourceGateState extends ConsumerState<_ResourceGate>
    with SingleTickerProviderStateMixin {
  /// 放行后首页淡入时长：短到不拖慢感知，足够盖掉首页首帧构建的抖动。
  static const _revealDuration = Duration(milliseconds: 420);

  late final AnimationController _revealController =
      AnimationController(vsync: this, duration: _revealDuration)
        ..addStatusListener((status) {
          // 淡入结束后把开屏层从渲染树移除，首页独占
          if (status == AnimationStatus.completed && mounted) {
            setState(() {});
          }
        });

  /// 是否已触发放行淡入（只触发一次）
  bool _revealArmed = false;

  @override
  void initState() {
    super.initState();
    unawaited(
        ref.read(resourceBootstrapNotifierProvider.notifier).bootstrap());
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(resourceBootstrapNotifierProvider);

    if (!state.completed) {
      if (!state.checking) {
        final notifier = ref.read(resourceBootstrapNotifierProvider.notifier);
        // 用户跳过过 → 放行（资源在后台静默补下载）
        if (notifier.skippedThisManifest) return _buildRevealingChild();
        // manifest 拉到后各资源逐个校验/下载；仍全部处于校验态时保持
        // 开屏层，任一资源进入下载/失败态（即确实需要下载）才切引导页，
        // 避免缓存全命中时闪一帧
        final needsUi = state.items.values
            .any((s) => s.status != ResourceItemStatus.checking);
        if (needsUi) return const ResourceBootstrapScreen();
      }
      // 校验中 → 开屏层继续遮
      return const AppStartupSplash();
    }

    return _buildRevealingChild();
  }

  /// 放行进首页：首页在开屏层之上淡入，替代硬切。
  Widget _buildRevealingChild() {
    _armReveal();
    if (_revealController.isCompleted) return widget.child;
    return Stack(
      children: [
        const Positioned.fill(child: AppStartupSplash()),
        FadeTransition(
          opacity: CurvedAnimation(
              parent: _revealController, curve: Curves.easeOut),
          child: widget.child,
        ),
      ],
    );
  }

  /// 首帧把 Stack 摆好后再开始淡入，避免首帧即半透明。
  void _armReveal() {
    if (_revealArmed) return;
    _revealArmed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealController.forward();
    });
  }
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with WidgetsBindingObserver {
  /// 浏览器 Tab 索引（统一进 IndexedStack 后也用于场景切换判定）
  static const int _browserTabIndex = 1;

  void _onItemTapped(int index, WidgetRef ref) {
    // 更新 Tab 索引（单一真相源：homeTabIndexNotifierProvider）。
    // AI Agent 场景切换由 build() 中的 ref.listen(homeTabIndexNotifierProvider)
    // 统一响应，此处不再直接写 currentAgentScenarioProvider，避免双写。
    ref.read(homeTabIndexNotifierProvider.notifier).switchTo(index);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LoggerService.instance.i(
      'HomePage: 初始化并添加生命周期监听器',
      category: LogCategory.ui,
      tags: ['lifecycle', 'init'],
    );
    // post-frame 后执行启动期副作用（只执行一次：
    // _HomePageState 在 app 生命周期内只 initState 一次）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_runStartupPrompts());
    });
  }

  /// 启动期一次性副作用，串行执行：crash 上报 → star 引导 → 静默检查更新。
  ///
  /// 编排交给 [StartupPromptsRunner]：star 引导不满足门槛时的提前返回只
  /// 跳过该阶段自身，不再短路启动期更新检查；整体只受 mounted 门控。
  Future<void> _runStartupPrompts() async {
    final runner = StartupPromptsRunner(
      canContinue: () => mounted,
      crashReportStage: () => NativeCrashReporter.checkAndReport(context),
      starPromptStage: _maybeRunStarPrompt,
      updateCheckStage: _silentCheckStableUpdate,
    );
    await runner.run();
  }

  /// GitHub star 引导阶段:满足全部门槛时弹窗。
  ///
  /// 不满足门槛或中途退出页面时直接返回,只结束本阶段;弹窗后的
  /// mounted 校验由 [StartupPromptsRunner] 继续按阶段门控。
  Future<void> _maybeRunStarPrompt() async {
    await StarPromptService.instance.recordLaunch();
    if (!mounted) return;
    final shouldShow = await StarPromptService.instance.shouldShow();
    if (!shouldShow || !mounted) return;
    final goStar = await showDialog<bool>(
      context: context,
      builder: (_) => const StarPromptDialog(),
    );
    // showDialog 期间用户可能退出页面；后续副作用必须重新 mounted 校验
    if (!mounted) return;
    if (goStar == true) {
      await StarPromptService.instance.onStarClicked();
      if (!mounted) return;
      await launchUrl(Uri.parse(kGitHubRepo),
          mode: LaunchMode.externalApplication);
    } else {
      await StarPromptService.instance.onDismissed();
    }
  }

  /// 启动期静默检查更新：有新版本则弹窗，失败 / 已是最新均不打扰。
  ///
  /// 通道跟随用户设置：预览版开关开启时含 prerelease，否则仅查 stable。
  /// 全程打 info 级日志（release 可见），便于排查「为什么没弹更新」。
  Future<void> _silentCheckStableUpdate() async {
    try {
      final updateService = AppUpdateService();
      final previewChannel = await AppUpdateService.isPreviewChannelEnabled();
      LoggerService.instance.i(
        '启动期更新检查开始 (channel=${previewChannel ? 'preview' : 'stable'})',
        category: LogCategory.network,
        tags: ['update', 'startup-check'],
      );
      final result = await updateService.checkForUpdateDetailed(
        forceCheck: false, // 走 1 小时节流
        includePrerelease: previewChannel,
      );
      if (!mounted) return;

      if (result is! AppUpdateAvailable) {
        // UpToDate / CheckFailed：静默吞掉，不打扰用户。
        // CheckFailed 的详细 reason 已由 checkForUpdateDetailed 内部以
        // w 级记录，此处只补一条结果摘要日志便于串联时间线。
        final summary = switch (result) {
          AppUpdateCheckFailed(:final reason) => 'CheckFailed($reason)',
          _ => result.runtimeType.toString(),
        };
        LoggerService.instance.i(
          '启动期更新检查结束: $summary',
          category: LogCategory.network,
          tags: ['update', 'startup-check'],
        );
        return;
      }

      final version = result.version;

      // 用户此前已点过「稍后提醒」忽略该版本 → 不再弹
      if (await updateService.isVersionIgnored(version.version)) {
        LoggerService.instance.i(
          '启动期更新检查: 新版本 ${version.version} 已被用户忽略, 不弹窗',
          category: LogCategory.network,
          tags: ['update', 'startup-check'],
        );
        return;
      }

      LoggerService.instance.i(
        '启动期更新检查: 发现新版本 ${version.version}, 弹出更新弹窗',
        category: LogCategory.network,
        tags: ['update', 'startup-check'],
      );
      await showAppUpdateDialog(
        context,
        version: version,
        updateService: updateService,
        isNewVersion: true,
      );
    } catch (e, stackTrace) {
      LoggerService.instance.w(
        '启动期更新检查异常(不影响 App): $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.general,
        tags: ['update', 'startup-check', 'silent-error'],
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 应用生命周期标记不再需要（CacheManager已删除）
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LoggerService.instance.i(
      'HomePage: 移除生命周期监听器并清理资源',
      category: LogCategory.ui,
      tags: ['lifecycle', 'dispose', 'cleanup'],
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    LoggerService.instance.i(
      'HomePage: 应用生命周期状态变化: $state',
      category: LogCategory.ui,
      tags: ['lifecycle', 'state-change'],
    );

    switch (state) {
      case AppLifecycleState.paused:
        // 立即上报缓冲日志，避免丢失
        LogReporterService.instance.flush();
        break;
      case AppLifecycleState.resumed:
        // 应用恢复前台时，不自动恢复播放，让可见性检测器处理
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.detached:
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听外部 Tab 切换请求。
    // 用户点击底部导航时也会写回此 Provider，保持单一真相源。
    final selectedIndex = ref.watch(homeTabIndexNotifierProvider);

    // 响应外部/导航触发的 Tab 切换，执行副作用：
    // 切换 AI Agent 场景
    ref.listen<int>(homeTabIndexNotifierProvider, (previous, next) {
      if (previous == null || previous == next) return;
      ref.read(currentAgentScenarioProvider.notifier).state =
          next == _browserTabIndex
              ? ScenarioIds.webviewExtract
              : ScenarioIds.writing;
    });

    // 所有 Tab（含浏览器）统一使用 IndexedStack 保持状态：
    // 浏览器 Tab 此前每次切换都会销毁重建 WebView，导致浏览页面/历史丢失。
    // IndexedStack 会保留各 Tab 的 element 与 State，切换 Tab 不再销毁 WebView。
    return Scaffold(
      body: AgentFloatingShell(
        // 共享 FAB 的场景随当前 Tab 显式声明（issue #23）：
        // 从阅读页 pop 回浏览器 Tab 不会触发 _onItemTapped，读全局残留值
        // 会在浏览器 Tab 误开写作助手；Tab 切换经 setState 重建时同步更新。
        scenarioId: selectedIndex == _browserTabIndex
            ? ScenarioIds.webviewExtract
            : ScenarioIds.writing,
        child: IndexedStack(
          index: selectedIndex,
          children: [
            const BookshelfScreen(),
            // active 标记当前浏览器是否可见：
            // 仅在可见时拦截系统返回手势，避免 offstage 状态下误拦截其他 Tab 的返回键。
            WebViewBrowserScreen(active: selectedIndex == _browserTabIndex),
            const SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          _onItemTapped(index, ref);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.book),
            label: '书架',
          ),
          NavigationDestination(
            icon: Icon(Icons.public),
            label: '浏览器',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
