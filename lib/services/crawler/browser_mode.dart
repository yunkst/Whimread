/// 浏览器展示模式（type-safe 版本）
///
/// v46 在 SiteScript.preferredMode 用 int 0/1/2 记录创作模式，运行时
/// 散落在 4 个 headless 服务里各自做 int→bool 映射；收敛到本枚举后：
/// - 仅在 [SiteScriptRepository] 与 [SiteScript] 模型做 int↔enum 转换
/// - 所有爬取子系统组件（CrawlRequest、Resolver、headless 服务）只看到本枚举
/// - 编译期防止「把 unknown 当 desktop」这类静默 bug
///
/// 老数据迁移：DB 列 `preferred_mode` 仍为 int（不需 v47 迁移），仅在边界处
/// 翻译；`unknown`（0）是「未设置」——保留以兼容老脚本。
enum BrowserMode {
  /// 桌面模式：desktop UA + 1200px viewport
  desktop,

  /// 手机模式：默认 UA + 全屏 viewport
  mobile,

  /// 未设置（仅模型边界使用，运行时不参与决策）
  unknown;

  /// 是否为明确模式（desktop/mobile），用于服务层「脚本优先 vs 全局兜底」判断
  bool get isKnown => this != unknown;

  /// 持久化整数值：1=desktop / 2=mobile / 0=unknown
  int get storageValue => switch (this) {
        BrowserMode.desktop => 1,
        BrowserMode.mobile => 2,
        BrowserMode.unknown => 0,
      };

  /// 从持久化整数值还原；null 或未知值返回 [unknown]
  static BrowserMode fromStorage(int? v) => switch (v) {
        1 => BrowserMode.desktop,
        2 => BrowserMode.mobile,
        _ => BrowserMode.unknown,
      };

  /// 日志可读名
  String get logName => switch (this) {
        BrowserMode.desktop => 'desktop',
        BrowserMode.mobile => 'mobile',
        BrowserMode.unknown => 'unknown',
      };
}
