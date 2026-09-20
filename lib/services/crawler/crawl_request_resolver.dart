import '../../models/site_script.dart';
import '../../repositories/site_script_repository.dart';
import '../browser_settings_service.dart';
import '../logger_service.dart';
import 'browser_mode.dart';
import 'crawl_request.dart';
import 'site_key.dart';

/// 爬取请求解析器——「URL×脚本×模式」对齐的**唯一入口**
///
/// 这是 P1 的架构关键组件：
/// - 修 [爱丽丝网 no script  bug]：用 [SiteKey] 做 host 变体等价匹配
/// - 修 [跳转问题]：把 [Uri.host] 重写为脚本保存时的 host，加载时与脚本验证
///   时的 host×模式组合自洽，从机制上消除站点对错误 UA×host 组合的 302 跳转
///
/// 所有调用方（三个 headless 服务、FAB 路径、agent 场景等）都必须经过本类；
/// 没有本类之外的 host 提取或脚本查找路径。
class CrawlRequestResolver {
  final SiteScriptRepository _scriptRepo;
  final BrowserMode Function() _globalModeProvider;

  /// 默认构造：从 [SiteScriptRepository] 查脚本，全局模式从
  /// [BrowserSettingsService.desktopModeSync] 同步读取。
  ///
  /// 全局模式读取抽成参数注入，单元测试可不依赖 [BrowserSettingsService]
  /// 静态全局态。
  CrawlRequestResolver({
    required SiteScriptRepository scriptRepo,
    BrowserMode Function()? globalModeProvider,
  })  : _scriptRepo = scriptRepo,
        _globalModeProvider = globalModeProvider ?? _defaultGlobalMode;

  static BrowserMode _defaultGlobalMode() =>
      BrowserSettingsService.desktopModeSync
          ? BrowserMode.desktop
          : BrowserMode.mobile;

  /// 解析一次爬取请求
  ///
  /// 找不到脚本或该 slot 为空 → 返回 [CrawlNoScript]
  /// 找到 → 返回 [CrawlAligned]，三轴已自洽（host 已对齐到脚本 host；
  /// 模式已对齐到脚本 preferredMode，未设置则用全局）
  Future<CrawlResolution> resolve(Uri? inputUrl, ScriptSlot slot) async {
    if (inputUrl == null || inputUrl.host.isEmpty) {
      return CrawlNoScript(url: inputUrl, slot: slot);
    }
    final host = inputUrl.host;

    // 1. 找脚本（变体等价）
    SiteScript? script;
    try {
      script = await _scriptRepo.findByUrlHost(host);
    } catch (e) {
      LoggerService.instance.w(
        'Resolver: 脚本查询失败 host=$host error=$e',
        category: LogCategory.crawler,
        tags: ['crawler', 'resolver', 'script-query-error'],
      );
      return CrawlNoScript(
        url: inputUrl,
        slot: slot,
        siteKey: SiteKey.tryFromHost(host),
      );
    }

    if (script == null || !script.isEnabled || !slot.isFilledOn(script)) {
      return CrawlNoScript(
        url: inputUrl,
        slot: slot,
        siteKey: SiteKey.tryFromHost(host),
      );
    }

    // 2. 对齐 host：把 inputUrl.host 改写为脚本保存时的 host
    final canonical = script.domain.toLowerCase() == host.toLowerCase()
        ? inputUrl
        : inputUrl.replace(host: script.domain);

    // 3. 对齐模式：脚本 preferredMode 已知则用之，否则全局
    final mode = script.preferredBrowserMode.isKnown
        ? script.preferredBrowserMode
        : _globalModeProvider();

    return CrawlAligned(
      CrawlRequest(
        requestedUrl: inputUrl,
        canonicalUrl: canonical,
        mode: mode,
        script: script,
        slot: slot,
      ),
    );
  }
}
