import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/remote_script.dart';
import '../../models/site_script.dart';
import '../../repositories/site_script_repository.dart';
import '../api_service_wrapper.dart';
import '../logger_service.dart';

/// 云端脚本仓库用例层（v47 起）
///
/// 把 [ApiServiceWrapper] 的 HTTP DTO 与 [SiteScriptRepository] 的本地
/// 读写粘合成业务用例：
/// - [findApprovedCandidate]：FAB noScript 分支前置远程查找
/// - [downloadAndPersist]：下载并落库（已含本地冲突处理）
/// - [shareLocal] / [unshareRemote]：共享与取消共享
/// - [checkUpdate]：检查单条已下载脚本是否有新版本
///
/// 所有方法在网络 / 服务错误时抛 [RemoteScriptException]，由调用方
/// 决定降级（FAB 直接走 AI 写脚本流程；脚本面板仅 toast 错误）。
class RemoteScriptException implements Exception {
  final String message;
  final Object? cause;
  const RemoteScriptException(this.message, [this.cause]);

  @override
  String toString() =>
      'RemoteScriptException: $message${cause != null ? ' (cause: $cause)' : ''}';
}

class RemoteScriptService {
  final ApiServiceWrapper _api;
  final SiteScriptRepository _scriptRepo;

  RemoteScriptService({
    required ApiServiceWrapper api,
    required SiteScriptRepository scriptRepo,
  })  : _api = api,
        _scriptRepo = scriptRepo;

  /// 按 host 在云端搜索管理员已审核通过的脚本，返回最优候选。
  ///
  /// 「最优」：按版本号降序取第一条（后端已按 version DESC 返回）。
  /// 命中返回 [RemoteScriptMeta]；云端无候选返回 null。
  Future<RemoteScriptMeta?> findApprovedCandidate(String host) async {
    try {
      final results = await _api.searchRemoteScripts(host: host);
      if (results.isEmpty) {
        LoggerService.instance.d(
          'RemoteScriptService: host=$host 无云端候选',
          category: LogCategory.crawler,
          tags: ['script_repo', 'search', 'empty'],
        );
        return null;
      }
      final best = results.first;
      LoggerService.instance.i(
        'RemoteScriptService: host=$host 命中云端脚本 '
        'remoteId=${best.remoteId} v${best.version} downloads=${best.downloadCount}',
        category: LogCategory.crawler,
        tags: ['script_repo', 'search', 'hit'],
      );
      return best;
    } catch (e) {
      LoggerService.instance.w(
        'RemoteScriptService: 远程搜索失败 host=$host - $e',
        category: LogCategory.crawler,
        tags: ['script_repo', 'search', 'failed'],
      );
      throw RemoteScriptException('远程脚本搜索失败', e);
    }
  }

  /// 下载完整载荷并落库。
  ///
  /// - 若同 domain 已存在 **本地自建**（source='local'）脚本，**不覆盖**，
  ///   抛 [LocalScriptConflictException]，由调用方弹「替换 / 保留 / 另存」
  ///   对话框让用户决策。决策后再调 [forceReplaceLocalWithRemote] 或
  ///   [insertAsNewScript] 完成写入。
  /// - 其它情况：直接落库（INSERT 或 UPDATE 同 remote_id 副本）。
  ///
  /// 返回 (本地 id, isInsert)。
  Future<({String id, bool isInsert})> downloadAndPersist(
    RemoteScriptMeta meta,
  ) async {
    final payload = await _api.getRemoteScript(meta.remoteId);
    final draft = _payloadToScript(payload);

    final existing = await _scriptRepo.findByUrlHost(meta.domain);
    if (existing != null && !existing.isRemote) {
      throw LocalScriptConflictException(existingLocal: existing, meta: meta);
    }

    final result = await _scriptRepo.insertRemoteDownload(draft);
    LoggerService.instance.i(
      'RemoteScriptService: 下载并落库 domain=${meta.domain} '
      'remoteId=${meta.remoteId} v${meta.version} id=${result.id} '
      'isInsert=${result.isInsert}',
      category: LogCategory.crawler,
      tags: ['script_repo', 'download', 'persisted'],
    );
    return result;
  }

  /// 用户在「替换」决策后调用：把本地脚本覆盖为远程副本（保留原 id）。
  Future<({String id})> forceReplaceLocalWithRemote(
    SiteScript existing,
    RemoteScriptMeta meta,
  ) async {
    final payload = await _api.getRemoteScript(meta.remoteId);
    await _scriptRepo.updateFromRemote(
      existing.id,
      chapterListJs: payload.chapterListJs,
      chapterContentJs: payload.chapterContentJs,
      bookshelfJs: payload.bookshelfJs,
      urlPattern: payload.urlPattern,
      sampleUrl: payload.sampleUrl.isNotEmpty
          ? payload.sampleUrl
          : existing.sampleUrl,
      chapterListOcr: payload.chapterListOcr,
      chapterContentOcr: payload.chapterContentOcr,
      sha256: meta.sha256,
      remoteVersion: meta.version,
    );
    // 同步 source=remote / remote_id（updateFromRemote 不改这些标识）
    final db = await _scriptRepo.database;
    await db.update(
      'site_scripts',
      {
        'source': ScriptSource.remote.storageValue,
        'remote_id': meta.remoteId,
      },
      where: 'id = ?',
      whereArgs: [existing.id],
    );
    LoggerService.instance.i(
      'RemoteScriptService: 覆盖本地脚本 domain=${meta.domain} '
      'id=${existing.id} remoteId=${meta.remoteId}',
      category: LogCategory.crawler,
      tags: ['script_repo', 'download', 'force_replace'],
    );
    return (id: existing.id);
  }

  /// 「另存」决策后调用：保留原本地脚本，另 INSERT 一条 remote 副本
  /// （同 domain 允许多条 source=remote，按 last_used_at 取最新）。
  Future<({String id})> insertAsNewScript(RemoteScriptMeta meta) async {
    final payload = await _api.getRemoteScript(meta.remoteId);
    // 临时把 draft 的 id 留空，让 insertRemoteDownload 生成新 id
    final draft = _payloadToScript(payload).copyWith(
      domain: '${meta.domain}+remote',
    );
    final result = await _scriptRepo.insertRemoteDownload(draft);
    LoggerService.instance.i(
      'RemoteScriptService: 另存为新脚本 remoteId=${meta.remoteId} id=${result.id}',
      category: LogCategory.crawler,
      tags: ['script_repo', 'download', 'save_as_new'],
    );
    return (id: result.id);
  }

  /// 共享本地脚本到云端，成功后回写本地 remote_id/version/shared。
  Future<RemoteShareResult> shareLocal(SiteScript script) async {
    if (script.isRemote) {
      throw RemoteScriptException('云端脚本无需再共享');
    }
    final sha256 = script.sha256 ?? computeScriptSha256(script);
    try {
      final result = await _api.shareScriptToRemote(
        domain: script.domain,
        displayName: script.displayName,
        chapterListJs: script.chapterListJs,
        chapterContentJs: script.chapterContentJs,
        bookshelfJs: script.bookshelfJs,
        sampleUrl: script.sampleUrl,
        urlPattern: script.urlPattern,
        chapterListOcr: script.chapterListOcr,
        chapterContentOcr: script.chapterContentOcr,
        preferredMode: script.preferredMode,
        sha256: sha256,
      );
      await _scriptRepo.markShared(
        script.id,
        remoteId: result.remoteId,
        version: result.version,
        sha256: sha256,
      );
      LoggerService.instance.i(
        'RemoteScriptService: 共享成功 domain=${script.domain} '
        'remoteId=${result.remoteId} v${result.version} '
        'deduplicated=${result.deduplicated}',
        category: LogCategory.crawler,
        tags: ['script_repo', 'share', 'success'],
      );
      return result;
    } catch (e) {
      LoggerService.instance.w(
        'RemoteScriptService: 共享失败 domain=${script.domain} - $e',
        category: LogCategory.crawler,
        tags: ['script_repo', 'share', 'failed'],
      );
      throw RemoteScriptException('共享脚本失败', e);
    }
  }

  /// 取消共享。
  Future<void> unshareRemote(SiteScript script) async {
    final remoteId = script.remoteId;
    if (remoteId == null || remoteId.isEmpty) {
      throw RemoteScriptException('脚本未共享');
    }
    try {
      await _api.unshareRemoteScript(remoteId);
      await _scriptRepo.markUnshared(script.id);
      LoggerService.instance.i(
        'RemoteScriptService: 取消共享 id=${script.id} remoteId=$remoteId',
        category: LogCategory.crawler,
        tags: ['script_repo', 'unshare', 'success'],
      );
    } catch (e) {
      LoggerService.instance.w(
        'RemoteScriptService: 取消共享失败 id=${script.id} - $e',
        category: LogCategory.crawler,
        tags: ['script_repo', 'unshare', 'failed'],
      );
      throw RemoteScriptException('取消共享失败', e);
    }
  }

  /// 检查单条已下载脚本是否有新版本。返回新版本载荷，未更新返回 null。
  Future<RemoteScriptPayload?> checkUpdate(SiteScript script) async {
    if (!script.isRemote || script.remoteId == null) return null;
    try {
      final updates = await _api.checkRemoteScriptUpdates(items: [
        (remoteId: script.remoteId!, version: script.remoteVersion),
      ]);
      if (updates.isEmpty) return null;
      final hit = updates.first;
      if (hit.latestVersion <= script.remoteVersion) {
        LoggerService.instance.d(
          'RemoteScriptService: 已是最新 remoteId=${script.remoteId} '
          'local=v${script.remoteVersion} latest=v${hit.latestVersion}',
          category: LogCategory.crawler,
          tags: ['script_repo', 'check_update', 'no_change'],
        );
        return null;
      }
      // 有新版本：拉详情
      return await _api.getRemoteScript(script.remoteId!);
    } catch (e) {
      LoggerService.instance.w(
        'RemoteScriptService: 检查更新失败 id=${script.id} - $e',
        category: LogCategory.crawler,
        tags: ['script_repo', 'check_update', 'failed'],
      );
      throw RemoteScriptException('检查更新失败', e);
    }
  }

  /// 把 [RemoteScriptPayload] 转成本地 [SiteScript]（无 id，由 repo 生成）
  SiteScript _payloadToScript(RemoteScriptPayload p) {
    return SiteScript(
      id: '', // 由 repo 生成
      domain: p.meta.domain,
      urlPattern: p.urlPattern,
      chapterListJs: p.chapterListJs,
      chapterContentJs: p.chapterContentJs,
      sampleUrl: p.sampleUrl,
      createdAt: 0,
      lastUsedAt: 0,
      useCount: 0,
      verified: 1,
      chapterListOcr: p.chapterListOcr,
      chapterContentOcr: p.chapterContentOcr,
      bookshelfJs: p.bookshelfJs,
      displayName: p.meta.displayName,
      preferredMode: p.preferredMode,
      source: ScriptSource.remote,
      remoteId: p.meta.remoteId,
      remoteVersion: p.meta.version,
      sha256: p.meta.sha256,
      shared: false,
      lastSyncedAt: 0,
      enabled: true,
    );
  }
}

/// 「同 domain 已存在本地自建脚本」冲突
class LocalScriptConflictException implements Exception {
  final SiteScript existingLocal;
  final RemoteScriptMeta meta;

  const LocalScriptConflictException({
    required this.existingLocal,
    required this.meta,
  });

  @override
  String toString() =>
      'LocalScriptConflictException: domain=${meta.domain} 已存在本地脚本 id=${existingLocal.id}';
}

/// 计算脚本载荷 SHA-256 指纹
///
/// 仅覆盖 chapterListJs / chapterContentJs / bookshelfJs 三类 JS
/// 文本，按 `listJs\n---\ncontentJs\n---\nbookshelfJs` 顺序拼接后
/// UTF-8 编码；返回 hex 小写 64 字符。
String computeScriptSha256(SiteScript script) {
  final digest = sha256.convert(utf8.encode(
    '${script.chapterListJs}\n---\n${script.chapterContentJs}\n---\n${script.bookshelfJs}',
  ));
  return digest.toString();
}
