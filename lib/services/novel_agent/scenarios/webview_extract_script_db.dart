/// WebView 提取场景的 site_scripts 表只读查询
///
/// 从 `WebViewExtractScenario` 抽出的独立职责：集中存放对 site_scripts
/// 表的直接 SQL 查询（存在性检查 / 按域名查询 / 最近列表），
/// 供场景工具（get_cached_script / list_cached_scripts / onNoToolCalls）复用。
///
/// 只负责查询本身；异常处理与错误 JSON 组装仍由场景层完成，
/// 以保持日志与返回结构不变。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/core/providers/database_providers.dart';

/// site_scripts 表只读查询助手（纯静态）
abstract final class WebViewExtractScriptDb {
  /// 查询某域名在 site_scripts 表是否有任意记录
  static Future<bool> hasAnyScript(Ref ref, String domain) async {
    final db = await ref.read(databaseConnectionProvider).database;
    final results = await db.query(
      'site_scripts',
      where: 'domain = ?',
      whereArgs: [domain],
      limit: 1,
    );
    return results.isNotEmpty;
  }

  /// 查询某域名的全部缓存脚本（按最近使用排序）
  static Future<List<Map<String, dynamic>>> queryByDomain(
    Ref ref,
    String domain,
  ) async {
    final db = await ref.read(databaseConnectionProvider).database;
    return db.query(
      'site_scripts',
      where: 'domain = ?',
      whereArgs: [domain],
      orderBy: 'last_used_at DESC',
    );
  }

  /// 列出最近使用的缓存脚本（默认 20 条）
  static Future<List<Map<String, dynamic>>> listRecent(
    Ref ref, {
    int limit = 20,
  }) async {
    final db = await ref.read(databaseConnectionProvider).database;
    return db.query(
      'site_scripts',
      orderBy: 'last_used_at DESC',
      limit: limit,
    );
  }
}
