import '../../models/site_script.dart';
import 'browser_mode.dart';
import 'site_key.dart';

/// 爬取子系统想要执行的脚本槽（目录 / 正文 / 书架）
///
/// Resolver 按此参数判断「脚本该字段是否非空」——对应 v40 之前的
/// `hasChapterListJs` / `hasChapterContentJs` / `hasBookshelfJs`。
enum ScriptSlot {
  chapterList,
  chapterContent,
  bookshelf;

  /// 该槽位是否在 [script] 中实际可用
  bool isFilledOn(SiteScript script) => switch (this) {
        ScriptSlot.chapterList => script.hasChapterListJs,
        ScriptSlot.chapterContent => script.hasChapterContentJs,
        ScriptSlot.bookshelf => script.hasBookshelfJs,
      };
}

/// 一次「已对齐」的爬取请求（value object）
///
/// **这是 P1 修复跳转问题的核心**：Resolver 解析后三轴（URL×脚本×模式）
/// 自洽，下游组件只需照单执行，不再各做局部对齐决策。
/// 不可变——一旦生成，任何字段不再变化。
class CrawlRequest {
  /// 调用方给的原始 URL（未做 host 重写）
  final Uri requestedUrl;

  /// 解析后实际要加载到 WebView 的 URL；host 已被重写为脚本创作时的 host
  /// （见 [CrawlRequestResolver]）
  final Uri canonicalUrl;

  /// 解析后实际使用的浏览器模式（来自脚本的 preferredMode，未设置则来自全局）
  final BrowserMode mode;

  /// 已匹配到的脚本（已校验 [slot] 字段非空）
  final SiteScript script;

  /// 期望该请求执行的脚本槽
  final ScriptSlot slot;

  /// [requestedUrl] 的 host 是否被改写为 [script.domain]
  bool get hostRewritten =>
      requestedUrl.host.toLowerCase() != script.domain.toLowerCase();

  /// 日志输出：host 重写方向（如 "www.alice.com → m.alice.com"）
  String? get hostRewriteLog =>
      hostRewritten ? '${requestedUrl.host} → ${script.domain}' : null;

  const CrawlRequest({
    required this.requestedUrl,
    required this.canonicalUrl,
    required this.mode,
    required this.script,
    required this.slot,
  });
}

/// Resolver 解析结果
///
/// **不可**作为执行流水线的异常通道——执行中的失败（脚本错误、超时、空结果）
/// 仍走原服务的 `Result` 类型；本类型只表达「resolve 阶段」的对齐结果。
sealed class CrawlResolution {
  const CrawlResolution();
}

/// 对齐成功：[request] 已可直接交给执行引擎
class CrawlAligned extends CrawlResolution {
  final CrawlRequest request;
  const CrawlAligned(this.request);
}

/// 找不到脚本（domain 不在 site_scripts 中），或该 [slot] 字段为空
class CrawlNoScript extends CrawlResolution {
  /// 调用方给的 URL（可能为 null：URL 解析失败）
  final Uri? url;
  final ScriptSlot slot;
  final SiteKey? siteKey;
  const CrawlNoScript({required this.url, required this.slot, this.siteKey});
}
