import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screens/bookshelf_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/webview_browser_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'services/app_update_service.dart';
import 'services/app_update_result.dart';
import 'core/providers/service_providers.dart';
import 'core/providers/image_model_download_providers.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/onboarding_providers.dart';
import 'core/providers/ui_providers.dart';
import 'core/providers/agent_scenario_provider.dart';
import 'core/providers/ocr_providers.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_typography.dart';
import 'utils/toast_utils.dart';
import 'services/device/device_auth_service.dart';
import 'services/logger_service.dart';
import 'services/llm_logger/llm_logger.dart';
import 'services/log_reporter_service.dart';
import 'services/native_crash_reporter.dart' show kGitHubRepo, NativeCrashReporter;
import 'services/novel_agent/agent_scenario.dart';
import 'services/star_prompt_service.dart';
import 'widgets/agent_chat/agent_floating_button.dart';
import 'widgets/app_update_dialog.dart';
import 'widgets/star_prompt_dialog.dart';

/// 最近记录的全局异常签名（前 200 字符 hash），用于去重。
/// 同一异常在多层捕获中只记录第一条。
final _recentGlobalErrorSigs = <int>{};

/// 记录全局异常（带去重）。
///
/// 4 层全局异常捕获可能对同一条异常触发多次回调，
/// 此函数对签名去重避免日志中重复 2-3 次。
void _logGlobalError(String source, Object error, StackTrace? stack,
    {LogCategory category = LogCategory.general}) {
  final raw = error.toString();
  final sig = raw.length > 200 ? raw.substring(0, 200).hashCode : raw.hashCode;
  if (_recentGlobalErrorSigs.contains(sig)) return;
  _recentGlobalErrorSigs.add(sig);
  if (_recentGlobalErrorSigs.length > 8) {
    _recentGlobalErrorSigs.remove(_recentGlobalErrorSigs.first);
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
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        'API Service Error: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.network,
        tags: ['api', 'service', 'error'],
      );

      // 继续运行，用户可以在设置中配置
    }

    // 生图模型下载/转换的对账：进程被杀遗留的 downloading/converting 行
    // 归位为 paused/failed（可续传/可重试）。异步执行，不阻塞启动。
    unawaited(() async {
      try {
        await container
            .read(imageModelDownloadServiceProvider)
            .recoverOnStartup();
      } catch (e) {
        LoggerService.instance.w('生图模型下载对账失败: $e',
            category: LogCategory.general,
            tags: ['startup', 'image-model', 'recover']);
      }
    }());

    runApp(UncontrolledProviderScope(
      container: container,
      child: const NovelReaderApp(),
    ));

    // 首帧渲染后,后台启动 OCR 模型下载(不阻塞 UI,失败不影响 App 运行)
    // 首启:用户首启 ~5-30 秒后模型本地就绪,期间触发 OCR 还原会 await 下载
    // 后续:manifest sha256 命中本地缓存,直接跳过
    WidgetsBinding.instance.addPostFrameCallback((_) {
      container.read(ocrModelDownloaderProvider).ensureLocal().then(
        (_) {},  // success: 不需要做事
        onError: (e, st) {
          LoggerService.instance.w(
            'OCR 模型后台下载启动失败(不影响 App): $e',
            stackTrace: st.toString(),
            category: LogCategory.ai,
            tags: ['ocr', 'model-download', 'startup-error'],
          );
        },
      );
    });
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
        seedColor: const Color(0xFFB8843A),
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

    // 系统主题下 Toast 颜色跟随平台亮度，保持与 MaterialApp 实际渲染一致
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    return themeAsync.when(
      data: (themeState) {
        final isLight = themeState.flutterThemeMode == ThemeMode.light ||
            (themeState.flutterThemeMode == ThemeMode.system &&
                platformBrightness == Brightness.light);
        // 同步主题色到 Toast 工具，使其能感知当前主题
        ToastUtils.setThemeColors(isLight ? AppColors.light : AppColors.dark);
        return MaterialApp(
          title: 'Novel App',
          theme: themeState.getLightTheme(),
          darkTheme: themeState.getDarkTheme(),
          themeMode: themeState.flutterThemeMode,
          home: const _AppRoot(),
          debugShowCheckedModeBanner: true,
          builder: (context, child) {
            // 捕获并记录所有Widget错误（带去重）
            ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
              _logGlobalError('widget-error', errorDetails.exception,
                  errorDetails.stack,
                  category: LogCategory.ui);
              final theme = Theme.of(context);
              return MaterialApp(
                home: Scaffold(
                  appBar: AppBar(title: const Text('Error Occurred')),
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error,
                            size: 64, color: context.appColors.error),
                        const SizedBox(height: 16),
                        const Text(
                            'An error occurred. Check console for details.'),
                        const SizedBox(height: 8),
                        Text(
                          errorDetails.exception.toString(),
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            };
            return child!;
          },
        );
      },
      loading: () {
        // 加载中显示默认主题
        return MaterialApp(
          title: 'Novel App',
          theme: _buildFallbackThemeData(),
          home: const Center(
            child: CircularProgressIndicator(),
          ),
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
          title: 'Novel App',
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
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      data: (onboardingState) {
        if (onboardingState.onboardingCompleted) {
          return const HomePage();
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

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with WidgetsBindingObserver {
  /// 浏览器 Tab 索引（统一进 IndexedStack 后也用于场景切换判定）
  static const int _browserTabIndex = 1;

  void _onItemTapped(int index, WidgetRef ref) {
    // 更新 Tab 索引（单一真相源：homeTabIndexNotifierProvider）
    ref.read(homeTabIndexNotifierProvider.notifier).switchTo(index);

    // 根据当前 Tab 切换 AI Agent 场景：
    // 浏览器 Tab 用网页提取场景，其余 Tab 用写作场景。
    ref.read(currentAgentScenarioProvider.notifier).state =
        index == _browserTabIndex
            ? ScenarioIds.webviewExtract
            : ScenarioIds.writing;
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
    // post-frame 后检查（crash 优先，star 其后，更新最后；互不干扰）。
    // 只检查一次（_HomePageState 在 app 生命周期内只 initState 一次）。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // 1. 上次 native crash 报告
      await NativeCrashReporter.checkAndReport(context);
      if (!mounted) return;

      // 2. GitHub star 引导
      try {
        await StarPromptService.instance.recordLaunch();
        if (!mounted) return;
        final shouldShow = await StarPromptService.instance.shouldShow();
        if (!shouldShow || !mounted) return;
        final goStar = await showDialog<bool>(
          context: context,
          builder: (_) => const StarPromptDialog(),
        );
        if (goStar == true) {
          await StarPromptService.instance.onStarClicked();
          await launchUrl(Uri.parse(kGitHubRepo),
              mode: LaunchMode.externalApplication);
        } else {
          await StarPromptService.instance.onDismissed();
        }
      } catch (_) {
        // 任何异常吞掉，绝不阻塞启动。
      }

      // 3. 启动期静默检查正式版更新
      //    仅 stable 通道（includePrerelease=false），预览版不弹。
      //    失败一律吞掉，不阻塞启动；用户可随时去设置页手动检查。
      if (!mounted) return;
      await _silentCheckStableUpdate();
    });
  }

  /// 启动期静默检查正式版更新：有新正式版则弹窗，预览版 / 失败 / 已是最新均不打扰。
  Future<void> _silentCheckStableUpdate() async {
    try {
      final updateService = AppUpdateService();
      // includePrerelease=false：仅查 stable 通道，预览版不会触发弹窗
      final result = await updateService.checkForUpdateDetailed(
        forceCheck: false, // 走 1 小时节流
        includePrerelease: false,
      );
      if (!mounted) return;

      if (result is! AppUpdateAvailable) {
        // UpToDate / CheckFailed：静默吞掉，不打扰用户
        return;
      }

      final version = result.version;

      // 用户此前已点过「稍后提醒」忽略该版本 → 不再弹
      if (await updateService.isVersionIgnored(version.version)) {
        return;
      }

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
