/// 站点提取脚本数据模型
///
/// 对应 site_scripts 表的字段。
/// 每个 domain 有一条记录，包含目录提取脚本和内容提取脚本。
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
  /// v39 拆列后独立标记。多数普通站点两列均为 false；字体反爬站点（如番茄）
  /// 一般 content_ocr=true、list_ocr=false。
  final bool chapterContentOcr;

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
    };
  }

  /// 是否有目录脚本
  bool get hasChapterListJs => chapterListJs.isNotEmpty;

  /// 是否有内容脚本
  bool get hasChapterContentJs => chapterContentJs.isNotEmpty;

  /// 是否已验证
  bool get isVerified => verified == 1;

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
    );
  }
}