/// 站点提取脚本 Repository
///
/// 提供 site_scripts 表的 CRUD 操作。
/// 遵循项目 Repository 模式，继承 BaseRepository。
library;

import '../models/site_script.dart';
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
  Future<List<SiteScript>> getAll({int limit = 50}) async {
    try {
      final db = await database;
      final results = await db.query(
        'site_scripts',
        orderBy: 'last_used_at DESC',
        limit: limit,
      );
      return results.map(SiteScript.fromMap).toList();
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '查询所有脚本失败 - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['site_script', 'get_all', 'failed'],
      );
      rethrow;
    }
  }

  /// 按 domain 查询
  Future<SiteScript?> getByDomain(String domain) async {
    try {
      final db = await database;
      final results = await db.query(
        'site_scripts',
        where: 'domain = ?',
        whereArgs: [domain],
        limit: 1,
      );
      if (results.isEmpty) return null;
      return SiteScript.fromMap(results.first);
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '按域名查询脚本失败: domain=$domain - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['site_script', 'get_by_domain', 'failed'],
      );
      rethrow;
    }
  }

  /// 按 ID 查询
  Future<SiteScript?> getById(String id) async {
    try {
      final db = await database;
      final results = await db.query(
        'site_scripts',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (results.isEmpty) return null;
      return SiteScript.fromMap(results.first);
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '按ID查询脚本失败: id=$id - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['site_script', 'get_by_id', 'failed'],
      );
      rethrow;
    }
  }

  /// 删除脚本
  Future<void> delete(String id) async {
    try {
      final db = await database;
      await db.delete('site_scripts', where: 'id = ?', whereArgs: [id]);
      LoggerService.instance.i(
        '删除脚本: id=$id',
        category: LogCategory.database,
        tags: ['site_script', 'delete', 'success'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '删除脚本失败: id=$id - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['site_script', 'delete', 'failed'],
      );
      rethrow;
    }
  }

  /// 按 domain 删除
  Future<void> deleteByDomain(String domain) async {
    try {
      final db = await database;
      await db.delete('site_scripts', where: 'domain = ?', whereArgs: [domain]);
      LoggerService.instance.i(
        '删除域名所有脚本: domain=$domain',
        category: LogCategory.database,
        tags: ['site_script', 'delete_by_domain', 'success'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '删除域名脚本失败: domain=$domain - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['site_script', 'delete_by_domain', 'failed'],
      );
      rethrow;
    }
  }

  /// 更新 verified 状态
  ///
  /// 重要事件：setVerified(false) 意味着脚本被自动禁用
  Future<void> setVerified(String id, bool verified) async {
    try {
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
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '更新脚本 verified 状态失败: id=$id - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['site_script', 'set_verified', 'failed'],
      );
      rethrow;
    }
  }

  /// 更新 use_count 和 last_used_at（标记已使用）
  Future<void> markUsed(String id) async {
    try {
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
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '标记脚本已用失败: id=$id - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['site_script', 'mark_used', 'failed'],
      );
      rethrow;
    }
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
  }) async {
    try {
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
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        'upsert 脚本失败: domain=$domain - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['site_script', 'upsert', 'failed'],
      );
      rethrow;
    }
  }

  /// 增量更新某域名某类型脚本（save_script 分次保存用）。
  ///
  /// - [scriptType] 为 `'chapter_list'` 或 `'chapter_content'`，决定更新哪列。
  /// - v39 拆列后，[ocr] 写到与 [scriptType] 匹配的列（chapter_list_ocr /
  ///   chapter_content_ocr），两者独立，互不覆盖。
  /// - **若 domain 不存在会自动 INSERT** 一条新记录：本次 [scriptType] 列写
  ///   [scriptJs] + 对应 ocr 列，另一段（list/content）留空串、ocr 为 0；
  ///   `verified=0` 标识尚未完成另一半。这样无论 agent 第一次调的是
  ///   `chapter_list` 还是 `chapter_content`，都能直接落库。
  /// - 已存在的行：更新对应列 + ocr + last_used_at，verified 重置为 0。
  /// - url_pattern / sample_url 不写（save_script 不再产出该字段，DB 列保留
  ///   历史值不动；新记录时给空串占位）。
  Future<({bool success, String? id, String? reason})> updateScriptPart({
    required String domain,
    required String scriptType,
    required String scriptJs,
    required bool ocr,
  }) async {
    try {
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
        // 首次保存：INSERT 一条新记录，本次列写脚本 + ocr，另一列填空串占位。
        // 另一半由后续 save_script 调同样的方法补齐，无需前置工具。
        final insertId = _newScriptId();
        await db.insert('site_scripts', {
          'id': insertId,
          'domain': domain,
          'url_pattern': '',
          'chapter_list_js': scriptType == 'chapter_list' ? scriptJs : '',
          'chapter_content_js': scriptType == 'chapter_content' ? scriptJs : '',
          'chapter_list_ocr': scriptType == 'chapter_list' ? (ocr ? 1 : 0) : 0,
          'chapter_content_ocr': scriptType == 'chapter_content' ? (ocr ? 1 : 0) : 0,
          'sample_url': '',
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

      // 已存在：UPDATE 对应列 + 对应 ocr 列 + last_used_at，verified 重置为 0。
      final id = existing.first['id'] as String;
      final Map<String, Object?> updateValues = scriptType == 'chapter_list'
          ? {
              'chapter_list_js': scriptJs,
              'chapter_list_ocr': ocr ? 1 : 0,
            }
          : {
              'chapter_content_js': scriptJs,
              'chapter_content_ocr': ocr ? 1 : 0,
            };
      updateValues['last_used_at'] = DateTime.now().millisecondsSinceEpoch;
      updateValues['verified'] = 0;
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
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        'updateScriptPart 失败: domain=$domain - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['site_script', 'update_part', 'failed'],
      );
      rethrow;
    }
  }
}
