/// 站点提取脚本 Repository
///
/// 提供 site_scripts 表的 CRUD 操作。
/// 遵循项目 Repository 模式，继承 BaseRepository。
library;

import '../models/site_script.dart';
import '../services/crawler/site_key.dart';
import '../services/logger_service.dart';
import 'base_repository.dart';

class SiteScriptRepository extends BaseRepository {
  SiteScriptRepository({required super.dbConnection});

  /// 进程内 ID 单调计数器：与微秒时间戳拼接保证任意两次 INSERT 的 id 必不同
  ///
  /// 原实现 `${ms}_${microseconds % 100000}` 在同毫秒内两次 INSERT 会撞
  /// UNIQUE(site_scripts.id)（CI 高并发测试稳定复现）；追加进程内自增
  /// 序列后即使时钟静止也唯一。历史 id 格式为字符串，无格式约束。
  static int _idSeq = 0;

  /// 生成新的 site_scripts 主键
  static String _newScriptId() {
    final us = DateTime.now().microsecondsSinceEpoch;
    return '${us}_${_idSeq++}';
  }

  /// 查询所有脚本（按最后使用时间倒序）
  ///
  /// [sourceFilter] 非 null 时仅返回指定 [ScriptSource] 的脚本，便于
  /// 「云端下载」Tab 与「本地自建」Tab 的拆分展示。
  Future<List<SiteScript>> getAll({
    int limit = 50,
    ScriptSource? sourceFilter,
  }) {
    return guard(
      'site_script.getAll',
      () async {
        final db = await database;
        final results = await db.query(
          'site_scripts',
          where: sourceFilter != null ? 'source = ?' : null,
          whereArgs: sourceFilter != null ? [sourceFilter.storageValue] : null,
          orderBy: 'last_used_at DESC',
          limit: limit,
        );
        return results.map(SiteScript.fromMap).toList();
      },
      message: (e) => '查询所有脚本失败 - $e',
      category: LogCategory.database,
      tags: ['site_script', 'get_all', 'failed'],
    );
  }

  /// 按 host 变体等价查询脚本（P1 起 FAB / headless 服务的标准查找入口）
  ///
  /// 先按 [host] 精确匹配（走 DB 索引，绝大多数请求一次命中）；
  /// 未命中再做 [SiteKey] 变体等价匹配——`www.alice.com` 与 `m.alice.com`
  /// 视为同一站点（修复：可见浏览器切换桌面/手机模式后 host 变体导致
  /// 找不到已保存脚本、误报 noScript）。
  ///
  /// 变体匹配需要全表扫描，但 site_scripts 是用户级小表（<100 行），
  /// 可接受；精确路径仍是主路径。
  Future<SiteScript?> findByUrlHost(String host) async {
    final exact = await getByDomain(host);
    if (exact != null) return exact;

    final key = SiteKey.tryFromHost(host);
    if (key == null) return null;

    return guard(
      'site_script.findByUrlHost',
      () async {
        final db = await database;
        final results = await db.query('site_scripts');
        for (final row in results) {
          if (key.matchesHost(row['domain'] as String?)) {
            return SiteScript.fromMap(row);
          }
        }
        return null;
      },
      message: (e) => '按 host 变体查询脚本失败: host=$host - $e',
      category: LogCategory.database,
      tags: ['site_script', 'find_by_url_host', 'failed'],
    );
  }

  /// 按 domain 查询
  Future<SiteScript?> getByDomain(String domain) {
    return guard(
      'site_script.getByDomain',
      () async {
        final db = await database;
        final results = await db.query(
          'site_scripts',
          where: 'domain = ?',
          whereArgs: [domain],
          limit: 1,
        );
        if (results.isEmpty) return null;
        return SiteScript.fromMap(results.first);
      },
      message: (e) => '按域名查询脚本失败: domain=$domain - $e',
      category: LogCategory.database,
      tags: ['site_script', 'get_by_domain', 'failed'],
    );
  }

  /// 按 ID 查询
  Future<SiteScript?> getById(String id) {
    return guard(
      'site_script.getById',
      () async {
        final db = await database;
        final results = await db.query(
          'site_scripts',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (results.isEmpty) return null;
        return SiteScript.fromMap(results.first);
      },
      message: (e) => '按ID查询脚本失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['site_script', 'get_by_id', 'failed'],
    );
  }

  /// 删除脚本
  Future<void> delete(String id) {
    return guard(
      'site_script.delete',
      () async {
        final db = await database;
        await db.delete('site_scripts', where: 'id = ?', whereArgs: [id]);
        LoggerService.instance.i(
          '删除脚本: id=$id',
          category: LogCategory.database,
          tags: ['site_script', 'delete', 'success'],
        );
      },
      message: (e) => '删除脚本失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['site_script', 'delete', 'failed'],
    );
  }

  /// 按 domain 删除
  Future<void> deleteByDomain(String domain) {
    return guard(
      'site_script.deleteByDomain',
      () async {
        final db = await database;
        await db.delete('site_scripts', where: 'domain = ?', whereArgs: [domain]);
        LoggerService.instance.i(
          '删除域名所有脚本: domain=$domain',
          category: LogCategory.database,
          tags: ['site_script', 'delete_by_domain', 'success'],
        );
      },
      message: (e) => '删除域名脚本失败: domain=$domain - $e',
      category: LogCategory.database,
      tags: ['site_script', 'delete_by_domain', 'failed'],
    );
  }

  /// 更新 verified 状态
  ///
  /// 重要事件：setVerified(false) 意味着脚本被自动禁用
  Future<void> setVerified(String id, bool verified) {
    return guard(
      'site_script.setVerified',
      () async {
        final db = await database;
        await db.update(
          'site_scripts',
          {'verified': verified ? 1 : 0},
          where: 'id = ?',
          whereArgs: [id],
        );
        LoggerService.instance.w(
          '脚本 verified 状态变更: id=$id verified=$verified',
          category: LogCategory.database,
          tags: ['site_script', 'set_verified'],
        );
      },
      message: (e) => '更新脚本 verified 状态失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['site_script', 'set_verified', 'failed'],
    );
  }

  /// 重命名站点显示名（脚本管理面板手动改名用）。
  ///
  /// 写入 `display_name` 列（书架站点 Tab 优先展示的名字）；传空串则清空、
  /// 展示方回退 host。
  Future<void> setDisplayName(String id, String displayName) {
    return guard(
      'site_script.setDisplayName',
      () async {
        final db = await database;
        await db.update(
          'site_scripts',
          {'display_name': displayName.trim()},
          where: 'id = ?',
          whereArgs: [id],
        );
        LoggerService.instance.i(
          '脚本显示名变更: id=$id displayName=${displayName.trim()}',
          category: LogCategory.database,
          tags: ['site_script', 'set_display_name'],
        );
      },
      message: (e) => '更新脚本显示名失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['site_script', 'set_display_name', 'failed'],
    );
  }

  /// 更新 use_count 和 last_used_at（标记已使用）
  Future<void> markUsed(String id) {
    return guard(
      'site_script.markUsed',
      () async {
        final db = await database;
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.rawUpdate(
          'UPDATE site_scripts SET use_count = use_count + 1, last_used_at = ? WHERE id = ?',
          [now, id],
        );
        LoggerService.instance.d(
          '脚本标记已用: id=$id',
          category: LogCategory.cache,
          tags: ['site_script', 'mark_used'],
        );
      },
      message: (e) => '标记脚本已用失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['site_script', 'mark_used', 'failed'],
    );
  }

  /// 查询所有域名的站点显示名（display_name 非空的行）。
  ///
  /// 返回 `domain -> display_name`；键统一小写，便于与 URL host（书架侧
  /// 同为小写）对齐。用于书架页按站点拆分 Tab 的显示名解析。
  Future<Map<String, String>> getDisplayNamesByDomain() {
    return guard(
      'site_script.getDisplayNamesByDomain',
      () async {
        final db = await database;
        final results = await db.query(
          'site_scripts',
          columns: ['domain', 'display_name'],
          where: "display_name != ''",
        );
        return {
          for (final row in results)
            (row['domain'] as String).toLowerCase():
                row['display_name'] as String,
        };
      },
      message: (e) => '查询站点显示名失败 - $e',
      category: LogCategory.database,
      tags: ['site_script', 'get_display_names', 'failed'],
    );
  }

  /// 按 domain 去重保存：已存在则 UPDATE，不存在则 INSERT
  ///
  /// UPDATE 时保留 id / created_at / use_count，重置 verified=0，
  /// 更新脚本内容和 last_used_at。
  /// 返回 (id, isInsert) —— isInsert=true 表示首次插入。
  ///
  /// v39 拆列后，[chapterListOcr] / [chapterContentOcr] 分别写到对应列，
  /// 互不覆盖。
  Future<({String id, bool isInsert})> upsertByDomain({
    required String domain,
    required String chapterListJs,
    required String chapterContentJs,
    String urlPattern = '',
    String sampleUrl = '',
    bool chapterListOcr = false, // v39 拆列后独立标记
    bool chapterContentOcr = false,
  }) {
    return guard(
      'site_script.upsertByDomain',
      () async {
        final db = await database;
        final now = DateTime.now().millisecondsSinceEpoch;

        final existing = await db.query(
          'site_scripts',
          where: 'domain = ?',
          whereArgs: [domain],
          orderBy: 'last_used_at DESC',
        );

        if (existing.isNotEmpty) {
          // UPDATE：保留 id / created_at / use_count，重置 verified
          final row = existing.first;
          await db.update(
            'site_scripts',
            {
              'chapter_list_js': chapterListJs,
              'chapter_content_js': chapterContentJs,
              'url_pattern': urlPattern,
              'sample_url': sampleUrl,
              'last_used_at': now,
              'verified': 0, // 脚本内容变了，需要重新验证
              'chapter_list_ocr': chapterListOcr ? 1 : 0,
              'chapter_content_ocr': chapterContentOcr ? 1 : 0,
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );

          // 清理同 domain 的历史重复记录（保留第一条，删除其余）
          if (existing.length > 1) {
            final keepId = row['id'] as String;
            final deleted = await db.delete(
              'site_scripts',
              where: 'domain = ? AND id != ?',
              whereArgs: [domain, keepId],
            );
            LoggerService.instance.i(
              '清理同域名重复脚本: domain=$domain, deleted=$deleted',
              category: LogCategory.database,
              tags: ['site_script', 'upsert', 'cleanup'],
            );
          }

          LoggerService.instance.i(
            '更新域名脚本 (upsert): domain=$domain id=${row['id']}',
            category: LogCategory.database,
            tags: ['site_script', 'upsert', 'update'],
          );
          return (id: row['id'] as String, isInsert: false);
        }

        // INSERT：首次保存
        final id = _newScriptId();
        await db.insert('site_scripts', {
          'id': id,
          'domain': domain,
          'url_pattern': urlPattern,
          'chapter_list_js': chapterListJs,
          'chapter_content_js': chapterContentJs,
          'sample_url': sampleUrl,
          'created_at': now,
          'last_used_at': now,
          'use_count': 0,
          'verified': 0,
          'chapter_list_ocr': chapterListOcr ? 1 : 0,
          'chapter_content_ocr': chapterContentOcr ? 1 : 0,
        });
        LoggerService.instance.i(
          '新增域名脚本 (upsert): domain=$domain id=$id',
          category: LogCategory.database,
          tags: ['site_script', 'upsert', 'insert'],
        );
        return (id: id, isInsert: true);
      },
      message: (e) => 'upsert 脚本失败: domain=$domain - $e',
      category: LogCategory.database,
      tags: ['site_script', 'upsert', 'failed'],
    );
  }

  /// 增量更新某域名某类型脚本（save_script 分次保存用）。
  ///
  /// - [scriptType] 为 `'chapter_list'` / `'chapter_content'` / `'bookshelf'`，
  ///   决定更新哪列。
  /// - v39 拆列后，[ocr] 写到与 [scriptType] 匹配的列（chapter_list_ocr /
  ///   chapter_content_ocr），两者独立，互不覆盖；`bookshelf` 类型不适用 OCR
  ///   （书架页无字体反爬需求），[ocr] 被忽略、不动两个 ocr 列。
  /// - [testUrl] 非 null 时写入 `sample_url`（脚本最近一次验证通过的页面
  ///   URL）。bookshelf 类型依赖此值定位「我的书架」页做刷新同步。
  /// - [displayName] 非 null 且去空白后非空时写入 `display_name`（站点显示名，
  ///   v45 起）；null 或空白表示本次不涉及，**保留原值**（save_script 按
  ///   script_type 分次调用，不能互相覆盖）。
  /// - [preferredMode] 非 null 时写入 `preferred_mode`（v46 起，脚本创作/验证
  ///   时的浏览器展示模式：1=桌面、2=手机）；null 表示本次不涉及，保留原值。
  /// - **若 domain 不存在会自动 INSERT** 一条新记录：本次 [scriptType] 列写
  ///   [scriptJs] + 对应 ocr 列（bookshelf 无 ocr 列），其余列留空串、ocr 为 0；
  ///   `verified=0` 标识尚未完成其余类型。这样无论 agent 第一次调的是哪种
  ///   script_type，都能直接落库。
  /// - 已存在的行：更新对应列（+ ocr，bookshelf 除外）+ last_used_at，
  ///   verified 重置为 0。
  Future<({bool success, String? id, String? reason})> updateScriptPart({
    required String domain,
    required String scriptType,
    required String scriptJs,
    required bool ocr,
    String? testUrl,
    String? displayName,
    int? preferredMode,
  }) async {
    // 站点显示名：空白视为"未提供"，避免 agent 传空串清掉已有名字
    final effectiveDisplayName =
        (displayName != null && displayName.trim().isNotEmpty)
            ? displayName.trim()
            : null;
    return guard(
      'site_script.updateScriptPart',
      () async {
        final db = await database;
        final now = DateTime.now().millisecondsSinceEpoch;

        final existing = await db.query(
          'site_scripts',
          where: 'domain = ?',
          whereArgs: [domain],
          orderBy: 'last_used_at DESC',
          limit: 1,
        );

        if (existing.isEmpty) {
          // 首次保存：INSERT 一条新记录，本次列写脚本 + ocr，其余列填空串占位。
          // 其余类型由后续 save_script 调同样的方法补齐，无需前置工具。
          final insertId = _newScriptId();
          await db.insert('site_scripts', {
            'id': insertId,
            'domain': domain,
            'url_pattern': '',
            'chapter_list_js':
                scriptType == 'chapter_list' ? scriptJs : '',
            'chapter_content_js':
                scriptType == 'chapter_content' ? scriptJs : '',
            'bookshelf_js': scriptType == 'bookshelf' ? scriptJs : '',
            'chapter_list_ocr': scriptType == 'chapter_list' ? (ocr ? 1 : 0) : 0,
            'chapter_content_ocr':
                scriptType == 'chapter_content' ? (ocr ? 1 : 0) : 0,
            'sample_url': testUrl ?? '',
            'display_name': effectiveDisplayName ?? '',
            'preferred_mode': preferredMode ?? 0,
            'created_at': now,
            'last_used_at': now,
            'use_count': 0,
            'verified': 0,
          });
          LoggerService.instance.i(
            'updateScriptPart (insert): domain=$domain type=$scriptType ocr=$ocr id=$insertId',
            category: LogCategory.database,
            tags: ['site_script', 'update_part', 'insert'],
          );
          return (success: true, id: insertId, reason: null);
        }

        // 已存在：UPDATE 对应列（+ 对应 ocr 列，bookshelf 除外）+ last_used_at，
        // verified 重置为 0。
        final id = existing.first['id'] as String;
        final Map<String, Object?> updateValues = switch (scriptType) {
          'chapter_list' => {
              'chapter_list_js': scriptJs,
              'chapter_list_ocr': ocr ? 1 : 0,
            },
          'chapter_content' => {
              'chapter_content_js': scriptJs,
              'chapter_content_ocr': ocr ? 1 : 0,
            },
          // bookshelf：无 ocr 列，只写脚本
          _ => {'bookshelf_js': scriptJs},
        };
        updateValues['last_used_at'] = DateTime.now().millisecondsSinceEpoch;
        updateValues['verified'] = 0;
        if (testUrl != null) updateValues['sample_url'] = testUrl;
        // 显示名仅在实际提供时覆盖，分次保存互不清空
        if (effectiveDisplayName != null) {
          updateValues['display_name'] = effectiveDisplayName;
        }
        // 创作模式仅在实际提供时覆盖
        if (preferredMode != null) {
          updateValues['preferred_mode'] = preferredMode;
        }
        await db.update(
          'site_scripts',
          updateValues,
          where: 'id = ?',
          whereArgs: [id],
        );
        LoggerService.instance.i(
          'updateScriptPart (update): domain=$domain type=$scriptType ocr=$ocr id=$id',
          category: LogCategory.database,
          tags: ['site_script', 'update_part', 'update'],
        );
        return (success: true, id: id, reason: null);
      },
      message: (e) => 'updateScriptPart 失败: domain=$domain - $e',
      category: LogCategory.database,
      tags: ['site_script', 'update_part', 'failed'],
    );
  }

  /// 落库一条云端下载的脚本（v47）。
  ///
  /// - 若同 domain 已存在**本地自建**脚本（source='local'），**不覆盖**，
  ///   返回已有 id（isInsert=false），由调用方决定「替换 / 保留 / 另存」。
  /// - 若同 domain 已存在**同一 remote_id** 的副本，走 UPDATE 覆盖载荷
  ///   （重新下载/升级场景），返回 (id, isInsert=false)。
  /// - 否则 INSERT 一条 source='remote' 新记录，写入 sha256 /
  ///   remote_version / last_synced_at=now，verified 沿用云端已审核
  ///   语义置 1（管理员审核通过才允许下载）。
  Future<({String id, bool isInsert})> insertRemoteDownload(
    SiteScript script,
  ) {
    return guard(
      'site_script.insertRemoteDownload',
      () async {
        final db = await database;
        final now = DateTime.now().millisecondsSinceEpoch;

        final existing = await db.query(
          'site_scripts',
          where: 'domain = ?',
          whereArgs: [script.domain],
          orderBy: 'last_used_at DESC',
        );
        if (existing.isNotEmpty) {
          final row = existing.first;
          final existingSource = row['source'] as String? ?? 'local';
          if (existingSource == 'local') {
            // 本地自建脚本优先，不覆盖——调用方提示用户决策
            LoggerService.instance.i(
              'insertRemoteDownload: domain=${script.domain} 已有本地脚本，不覆盖 '
              '(id=${row['id']})',
              category: LogCategory.database,
              tags: ['site_script', 'remote_download', 'skip_local'],
            );
            return (id: row['id'] as String, isInsert: false);
          }
          // 已有 remote 副本：覆盖载荷（重新下载 / 升级）
          await db.update(
            'site_scripts',
            {
              'chapter_list_js': script.chapterListJs,
              'chapter_content_js': script.chapterContentJs,
              'bookshelf_js': script.bookshelfJs,
              'chapter_list_ocr': script.chapterListOcr ? 1 : 0,
              'chapter_content_ocr': script.chapterContentOcr ? 1 : 0,
              'url_pattern': script.urlPattern,
              'sample_url': script.sampleUrl,
              'remote_id': script.remoteId,
              'remote_version': script.remoteVersion,
              'sha256': script.sha256,
              'last_synced_at': now,
              'last_used_at': now,
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
          // 清理同 domain 的其他 remote 重复副本（同 upsert 策略）
          if (existing.length > 1) {
            final keepId = row['id'] as String;
            await db.delete(
              'site_scripts',
              where: 'domain = ? AND id != ?',
              whereArgs: [script.domain, keepId],
            );
          }
          LoggerService.instance.i(
            'insertRemoteDownload (update): domain=${script.domain} '
            'id=${row['id']} version=${script.remoteVersion}',
            category: LogCategory.database,
            tags: ['site_script', 'remote_download', 'update'],
          );
          return (id: row['id'] as String, isInsert: false);
        }

        final id = _newScriptId();
        await db.insert('site_scripts', {
          ...script.toMap(),
          'id': id,
          'created_at': now,
          'last_used_at': now,
          'use_count': 0,
          'verified': 1, // 云端已过审脚本，下载即视为已验证
          'last_synced_at': now,
          'source': ScriptSource.remote.storageValue,
        });
        LoggerService.instance.i(
          'insertRemoteDownload (insert): domain=${script.domain} id=$id '
          'remoteId=${script.remoteId} version=${script.remoteVersion}',
          category: LogCategory.database,
          tags: ['site_script', 'remote_download', 'insert'],
        );
        return (id: id, isInsert: true);
      },
      message: (e) => 'insertRemoteDownload 失败: domain=${script.domain} - $e',
      category: LogCategory.database,
      tags: ['site_script', 'remote_download', 'failed'],
    );
  }

  /// 已下载脚本升级到新版本（v47）：仅覆盖载荷与远端元信息。
  Future<void> updateFromRemote(
    String id, {
    required String chapterListJs,
    required String chapterContentJs,
    String bookshelfJs = '',
    String urlPattern = '',
    String sampleUrl = '',
    bool chapterListOcr = false,
    bool chapterContentOcr = false,
    required String sha256,
    required int remoteVersion,
  }) {
    return guard(
      'site_script.updateFromRemote',
      () async {
        final db = await database;
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.update(
          'site_scripts',
          {
            'chapter_list_js': chapterListJs,
            'chapter_content_js': chapterContentJs,
            'bookshelf_js': bookshelfJs,
            'chapter_list_ocr': chapterListOcr ? 1 : 0,
            'chapter_content_ocr': chapterContentOcr ? 1 : 0,
            'url_pattern': urlPattern,
            'sample_url': sampleUrl,
            'sha256': sha256,
            'remote_version': remoteVersion,
            'last_synced_at': now,
            'verified': 1,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        LoggerService.instance.i(
          'updateFromRemote: id=$id version=$remoteVersion',
          category: LogCategory.database,
          tags: ['site_script', 'update_from_remote', 'success'],
        );
      },
      message: (e) => 'updateFromRemote 失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['site_script', 'update_from_remote', 'failed'],
    );
  }

  /// 本地脚本共享成功后回写远端元信息（v47）。
  Future<void> markShared(
    String id, {
    required String remoteId,
    required int version,
    required String sha256,
  }) {
    return guard(
      'site_script.markShared',
      () async {
        final db = await database;
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.update(
          'site_scripts',
          {
            'remote_id': remoteId,
            'remote_version': version,
            'sha256': sha256,
            'shared': 1,
            'last_synced_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        LoggerService.instance.i(
          'markShared: id=$id remoteId=$remoteId version=$version',
          category: LogCategory.database,
          tags: ['site_script', 'mark_shared', 'success'],
        );
      },
      message: (e) => 'markShared 失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['site_script', 'mark_shared', 'failed'],
    );
  }

  /// 取消共享（v47）：清空 shared 标记与远端元信息。
  Future<void> markUnshared(String id) {
    return guard(
      'site_script.markUnshared',
      () async {
        final db = await database;
        await db.update(
          'site_scripts',
          {
            'remote_id': null,
            'remote_version': 0,
            'shared': 0,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        LoggerService.instance.i(
          'markUnshared: id=$id',
          category: LogCategory.database,
          tags: ['site_script', 'mark_unshared', 'success'],
        );
      },
      message: (e) => 'markUnshared 失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['site_script', 'mark_unshared', 'failed'],
    );
  }

  /// 设置用户显式启停开关（v47，与 verified 自动化语义解耦）。
  Future<void> setEnabled(String id, bool enabled) {
    return guard(
      'site_script.setEnabled',
      () async {
        final db = await database;
        await db.update(
          'site_scripts',
          {'enabled': enabled ? 1 : 0},
          where: 'id = ?',
          whereArgs: [id],
        );
        LoggerService.instance.i(
          '脚本 enabled 状态变更: id=$id enabled=$enabled',
          category: LogCategory.database,
          tags: ['site_script', 'set_enabled'],
        );
      },
      message: (e) => '设置脚本 enabled 失败: id=$id - $e',
      category: LogCategory.database,
      tags: ['site_script', 'set_enabled', 'failed'],
    );
  }
}
