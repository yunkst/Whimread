import '../services/crawler/browser_mode.dart';

/// 脚本来源：本地自建 vs 云端下载（v47 起）
///
/// 落库字段为 [ScriptSource.storageValue]（'local' / 'remote'），枚举仅在
/// 模型边界翻译，DB 列仍是 TEXT。
enum ScriptSource {
  local('local'),
  remote('remote');

  const ScriptSource(this.storageValue);

  final String storageValue;

  static ScriptSource fromStorage(String? value) {
    if (value == 'remote') return ScriptSource.remote;
    return ScriptSource.local;
  }
}

/// 站点提取脚本数据模型
///
/// 对应 site_scripts 表的字段。
/// 每个 domain 有一条记录，包含目录提取脚本、内容提取脚本与（v40 起）
/// 网站书架提取脚本（用于提取"我的书架/收藏"页的小说列表）。
class SiteScript {
  final String id;
  final String domain;
  final String urlPattern;
  final String chapterListJs;
  final String chapterContentJs;
  final String sampleUrl;
  final int createdAt;
  final int lastUsedAt;
  final int useCount;
  final int verified;

  /// 目录提取脚本是否需要 OCR 后处理（字体反爬）。
  ///
  /// v39 拆列后独立标记——典型如番茄小说，目录页 title/chapter.title 是正常汉字
  /// （无 PUA），所以此字段为 false；正文页有 PUA，chapterContentOcr 才为 true。
  /// 两者互不覆盖。
  final bool chapterListOcr;

  /// 正文提取脚本是否需要 OCR 后处理（字体反爬）。
  ///
  /// v39 拆列后独立标记。多数普通目录点两列均为 false；字体反爬站点（如番茄）
  /// 一般 content_ocr=true、list_ocr=false。
  final bool chapterContentOcr;

  /// 网站书架提取脚本（v40 起）。
  ///
  /// 在小说站「我的书架/收藏」页运行，返回 `{novels:[{title,url}]}`。
  /// 空字符串表示该域名未配置书架脚本。
  final String bookshelfJs;

  /// 站点显示名（v45 起），如「起点中文网」。
  ///
  /// 由提取 Agent 在 save_script 时从页面推断填写；空字符串 = 未填写，
  /// 展示方（书架站点 Tab）回退 host。
  final String displayName;

  /// 脚本创作/验证时的浏览器展示模式（v46 起）。
  ///
  /// 决定执行此脚本时使用的 Headless WebView 模式：1=桌面、2=手机。
  /// 0=未设置（老脚本），执行时回退到用户当前全局模式。
  ///
  /// 同一域名的三个脚本（目录/正文/书架）共用一个模式，因为它们通常在同一次
  /// Agent 会话里创作，模式一致。脚本是对特定 DOM（UA + viewport 决定的
  /// 桌面版或手机版）写的，在另一种模式上跑容易因选择器失效而失败。
  final int preferredMode;

  /// [preferredMode] 的类型安全枚举视图（P1 起统一爬取子系统所有组件的
  /// 模式表达形式；DB 列仍是 int，仅在模型边界翻译）。
  ///
  /// - [BrowserMode.unknown] = preferredMode=0（老脚本/未设置）
  /// - [BrowserMode.desktop] / [BrowserMode.mobile] = 1/2
  ///
  /// 调用方应据此判断「是否指定了模式」用 [BrowserMode.isKnown]，
  /// 不要直接判 `== unknown`。
  BrowserMode get preferredBrowserMode =>
      BrowserMode.fromStorage(preferredMode);

  /// 脚本来源（v47 起）。
  ///
  /// 本地自建 vs 从云端脚本仓库下载。命中本地 `site_scripts` 表的脚本可
  /// 能是上述两种之一：FAB 路径默认走 AI 本地创作（local），云端仓库命中
  /// 后由用户确认下载（remote）。
  final ScriptSource source;

  /// 云端脚本主键（v47 起）。
  ///
  /// [source] = remote 时由后端在 share/download 时下发；local 时为 null。
  /// 配合 [remoteVersion] 支持「检查更新」与同包版本对齐。
  final String? remoteId;

  /// 云端脚本版本号（v47 起）。
  ///
  /// 由后端在 share 时按 (author, domain) 单调自增；下载时写入客户端，
  /// 后续 [checkUpdate] 调用以 (remoteId, remoteVersion) 询问后端是否有
  /// 更高版本。
  final int remoteVersion;

  /// 脚本载荷指纹（v47 起）。
  ///
  /// 对 chapterListJs / chapterContentJs / bookshelfJs 序列化后的 SHA-256。
  /// 用于：
  /// 1. 客户端下载后做完整性校验；
  /// 2. 后端 share 时去重（同 author+domain+sha256 复用旧版本，不刷 pending）。
  final String? sha256;

  /// 是否已共享到云端（v47 起，0/1）。
  ///
  /// 仅本地脚本有意义；remote 脚本自带云端主键，无需再标记 shared。
  /// shared=1 时 [remoteId] / [remoteVersion] 一定有值。
  final bool shared;

  /// 最近一次与云端同步的毫秒时间戳（v47 起）。
  ///
  /// download / checkUpdate 成功后刷新，用于诊断「是否近期同步过」。
  final int lastSyncedAt;

  /// 用户显式启停开关（v47 起，0/1）。
  ///
  /// 与 [verified]（连续失败自动 unverified 的自动化语义）解耦：用户可
  /// 手动禁用一条脚本而无需修改 verified 状态。CrawlRequestResolver 在
  /// 命中本地脚本后会同时校验 enabled=1。
  final bool enabled;

  const SiteScript({
    required this.id,
    required this.domain,
    required this.urlPattern,
    required this.chapterListJs,
    required this.chapterContentJs,
    required this.sampleUrl,
    required this.createdAt,
    required this.lastUsedAt,
    required this.useCount,
    required this.verified,
    this.chapterListOcr = false,
    this.chapterContentOcr = false,
    this.bookshelfJs = '',
    this.displayName = '',
    this.preferredMode = 0,
    this.source = ScriptSource.local,
    this.remoteId,
    this.remoteVersion = 0,
    this.sha256,
    this.shared = false,
    this.lastSyncedAt = 0,
    this.enabled = true,
  });

  /// 从数据库 Map 构造
  factory SiteScript.fromMap(Map<String, dynamic> map) {
    return SiteScript(
      id: map['id'] as String,
      domain: map['domain'] as String,
      urlPattern: (map['url_pattern'] as String?) ?? '',
      chapterListJs: map['chapter_list_js'] as String,
      chapterContentJs: map['chapter_content_js'] as String,
      sampleUrl: (map['sample_url'] as String?) ?? '',
      createdAt: map['created_at'] as int,
      lastUsedAt: map['last_used_at'] as int,
      useCount: (map['use_count'] as int?) ?? 0,
      verified: (map['verified'] as int?) ?? 0,
      chapterListOcr: (map['chapter_list_ocr'] as int?) == 1,
      chapterContentOcr: (map['chapter_content_ocr'] as int?) == 1,
      bookshelfJs: (map['bookshelf_js'] as String?) ?? '',
      displayName: (map['display_name'] as String?) ?? '',
      preferredMode: (map['preferred_mode'] as int?) ?? 0,
      source: ScriptSource.fromStorage(map['source'] as String?),
      remoteId: map['remote_id'] as String?,
      remoteVersion: (map['remote_version'] as int?) ?? 0,
      sha256: map['sha256'] as String?,
      shared: (map['shared'] as int?) == 1,
      lastSyncedAt: (map['last_synced_at'] as int?) ?? 0,
      enabled: ((map['enabled'] as int?) ?? 1) == 1,
      // 注：旧 'ocr' 列 v39 起不再读取，保留在 DB 仅作历史兼容。
    );
  }

  /// 转换为数据库 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'domain': domain,
      'url_pattern': urlPattern,
      'chapter_list_js': chapterListJs,
      'chapter_content_js': chapterContentJs,
      'sample_url': sampleUrl,
      'created_at': createdAt,
      'last_used_at': lastUsedAt,
      'use_count': useCount,
      'verified': verified,
      'chapter_list_ocr': chapterListOcr ? 1 : 0,
      'chapter_content_ocr': chapterContentOcr ? 1 : 0,
      'bookshelf_js': bookshelfJs,
      'display_name': displayName,
      'preferred_mode': preferredMode,
      'source': source.storageValue,
      'remote_id': remoteId,
      'remote_version': remoteVersion,
      'sha256': sha256,
      'shared': shared ? 1 : 0,
      'last_synced_at': lastSyncedAt,
      'enabled': enabled ? 1 : 0,
    };
  }

  /// 是否有目录脚本
  bool get hasChapterListJs => chapterListJs.isNotEmpty;

  /// 是否有内容脚本
  bool get hasChapterContentJs => chapterContentJs.isNotEmpty;

  /// 是否有网站书架脚本
  bool get hasBookshelfJs => bookshelfJs.isNotEmpty;

  /// 是否已验证
  bool get isVerified => verified == 1;

  /// 是否来自云端下载（v47）
  bool get isRemote => source == ScriptSource.remote;

  /// 是否已共享到云端（v47）
  bool get isShared => shared;

  /// 是否启用（v47）
  bool get isEnabled => enabled;

  /// 创建时间（DateTime）
  DateTime get createdAtDateTime =>
      DateTime.fromMillisecondsSinceEpoch(createdAt);

  /// 复制并修改字段
  SiteScript copyWith({
    String? id,
    String? domain,
    String? urlPattern,
    String? chapterListJs,
    String? chapterContentJs,
    String? sampleUrl,
    int? createdAt,
    int? lastUsedAt,
    int? useCount,
    int? verified,
    bool? chapterListOcr,
    bool? chapterContentOcr,
    String? bookshelfJs,
    String? displayName,
    int? preferredMode,
    ScriptSource? source,
    String? remoteId,
    int? remoteVersion,
    String? sha256,
    bool? shared,
    int? lastSyncedAt,
    bool? enabled,
  }) {
    return SiteScript(
      id: id ?? this.id,
      domain: domain ?? this.domain,
      urlPattern: urlPattern ?? this.urlPattern,
      chapterListJs: chapterListJs ?? this.chapterListJs,
      chapterContentJs: chapterContentJs ?? this.chapterContentJs,
      sampleUrl: sampleUrl ?? this.sampleUrl,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      useCount: useCount ?? this.useCount,
      verified: verified ?? this.verified,
      chapterListOcr: chapterListOcr ?? this.chapterListOcr,
      chapterContentOcr: chapterContentOcr ?? this.chapterContentOcr,
      bookshelfJs: bookshelfJs ?? this.bookshelfJs,
      displayName: displayName ?? this.displayName,
      preferredMode: preferredMode ?? this.preferredMode,
      source: source ?? this.source,
      remoteId: remoteId ?? this.remoteId,
      remoteVersion: remoteVersion ?? this.remoteVersion,
      sha256: sha256 ?? this.sha256,
      shared: shared ?? this.shared,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      enabled: enabled ?? this.enabled,
    );
  }

  /// 显式清空 [remoteId]，用于本地脚本「取消共享」后的清理。
  ///
  /// 直接 `copyWith(remoteId: null)` 无法区分「未传」与「传 null」，因此
  /// 提供专门的清理方法。
  SiteScript copyWithClearedRemote() {
    return SiteScript(
      id: id,
      domain: domain,
      urlPattern: urlPattern,
      chapterListJs: chapterListJs,
      chapterContentJs: chapterContentJs,
      sampleUrl: sampleUrl,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
      useCount: useCount,
      verified: verified,
      chapterListOcr: chapterListOcr,
      chapterContentOcr: chapterContentOcr,
      bookshelfJs: bookshelfJs,
      displayName: displayName,
      preferredMode: preferredMode,
      source: source,
      remoteId: null,
      remoteVersion: 0,
      sha256: sha256,
      shared: false,
      lastSyncedAt: lastSyncedAt,
      enabled: enabled,
    );
  }
}
