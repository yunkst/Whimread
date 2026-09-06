import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'package:novel_api/novel_api.dart';

import 'api_service_wrapper.dart';
import 'logger_service.dart';
import 'preferences_service.dart';
import '../utils/format_utils.dart';
import '../core/database/database_connection.dart';

/// 数据库与偏好设置备份服务
///
/// 备份包格式（zip）：
/// ```
/// novel_app_backup.zip
/// ├── novel_reader.db          ← SQLite 数据库
/// └── preferences.json         ← SharedPreferences 全部键值（含类型码）
/// ```
///
/// 兼容性：若下载到的文件是纯 .db（无 zip 结构），自动按旧版"仅数据库"流程处理。
class BackupService {
  static const String _prefsLastBackupTimeKey = 'last_backup_time';

  /// 备份包内 DB 文件名
  static const String _dbFileNameInZip = 'novel_reader.db';

  /// 备份包内偏好设置文件名
  static const String _prefsFileNameInZip = 'preferences.json';

  /// 上传时的默认文件名（zip 包）
  static const String _backupFileName = 'novel_app_backup.zip';

  /// preferences.json schema 版本（向前兼容）
  static const int _prefsSchemaVersion = 1;

  /// API Token 在 SharedPreferences 中的键名（可在备份时按用户选择排除）
  static const String _tokenKey = 'api_token';

  /// 默认排除的键（设备相关 / 缓存时间戳 / 已完成迁移的标记）
  /// 恢复时绝不写入这些键，避免旧设备状态污染新设备
  static const Set<String> _excludedKeys = {
    'last_backup_time',
    'log_reporter_last_upload_time',
  };

  /// 默认排除的键前缀（WebView Cookie、迁移标记等）
  static const List<String> _excludedPrefixes = [
    'webview_',
    'migrated_',
    'global_active_migrated',
    'llm_config_migrated',
  ];

  // 单例模式
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  // Preferences 服务实例
  static final PreferencesService _prefs = PreferencesService();

  // ============================================================
  // 公共 API：上传
  // ============================================================

  /// 获取数据库文件路径
  Future<String> getDatabaseFilePath() async {
    final dbPath = await getDatabasesPath();
    return path.join(dbPath, 'novel_reader.db');
  }

  /// 获取数据库文件
  ///
  /// 返回 SQLite 数据库文件对象，供 UI 估算备份包大小使用。
  /// 如果数据库不存在或无法访问，会抛出异常。
  Future<File> getDatabaseFile() async {
    try {
      final dbFilePath = await getDatabaseFilePath();
      final file = File(dbFilePath);
      if (!await file.exists()) {
        throw Exception('数据库文件不存在: $dbFilePath');
      }
      LoggerService.instance.i(
        '获取数据库文件: ${file.path}',
        category: LogCategory.backup,
      );
      return file;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '获取数据库文件失败: $e',
        category: LogCategory.backup,
        stackTrace: stackTrace.toString(),
      );
      rethrow;
    }
  }

  /// 上传备份到服务器
  ///
  /// [apiWrapper] API服务包装器实例（必须已初始化）
  /// [excludeToken] 是否排除 API Token（默认 false=包含）
  /// [onProgress] 上传进度回调，参数为(已发送字节数, 总字节数)
  ///
  /// 返回 BackupUploadResponse，包含上传结果信息
  Future<BackupUploadResponse> uploadBackup({
    required ApiServiceWrapper apiWrapper,
    bool excludeToken = false,
    ProgressCallback? onProgress,
  }) async {
    File? zipFile;
    try {
      LoggerService.instance.i(
        '开始打包备份（excludeToken=$excludeToken）',
        category: LogCategory.backup,
      );
      zipFile = await _packBackup(excludeToken: excludeToken);

      LoggerService.instance.i(
        '开始上传备份: ${zipFile.path}',
        category: LogCategory.backup,
      );
      final fileSize = await zipFile.length();
      LoggerService.instance.i(
        '备份包大小: ${FormatUtils.formatFileSize(fileSize)}',
        category: LogCategory.backup,
      );

      final result = await apiWrapper.uploadBackup(
        dbFile: zipFile,
        onProgress: onProgress,
      );

      await saveBackupTime(DateTime.now());

      LoggerService.instance.i(
        '备份上传成功: ${result.storedPath}',
        category: LogCategory.backup,
      );
      return result;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '备份上传失败: $e',
        category: LogCategory.backup,
        stackTrace: stackTrace.toString(),
      );
      rethrow;
    } finally {
      // 清理临时 zip
      if (zipFile != null) {
        try {
          if (await zipFile.exists()) await zipFile.delete();
        } catch (_) {
          // 清理失败不影响主流程
        }
      }
    }
  }

  // ============================================================
  // 公共 API：恢复
  // ============================================================

  /// 从服务器恢复备份
  ///
  /// 核心流程：
  /// 1. 下载到临时文件
  /// 2. 尝试按 zip 解包
  /// 3. 若解包失败 → 走旧版"仅 DB"流程（SQLite header 校验 + 现有 10 步恢复）
  /// 4. 若解包成功 → 解出 DB 与 preferences.json
  /// 5. DB 替换：复用现有"备份原 DB → 复制 → 验证 → 回滚"流程
  /// 6. Prefs 恢复：先快照当前所有 Prefs → 写入新值 → 失败则按快照回滚（不影响 DB）
  ///
  /// [apiWrapper] 已初始化的 API 服务包装器实例
  /// [backupId] 备份唯一标识
  Future<void> restoreBackup({
    required ApiServiceWrapper apiWrapper,
    required String backupId,
  }) async {
    final dbPath = await getDatabasesPath();
    final targetFilePath = path.join(dbPath, 'novel_reader.db');
    final tempFilePath = path.join(dbPath, 'novel_app_restore_temp.zip');
    final bakFilePath = path.join(dbPath, 'novel_reader.db.bak');
    final dbFromZipPath = path.join(dbPath, 'novel_app_restore_db.db');

    Map<String, Object?>? prefsSnapshot;

    try {
      LoggerService.instance.i(
        '开始恢复备份: $backupId',
        category: LogCategory.backup,
      );

      // 步骤 1-2：下载到临时文件
      await downloadBackup(
        apiWrapper: apiWrapper,
        backupId: backupId,
        savePath: tempFilePath,
      );

      // 步骤 3-4：判断是新版 zip 还是旧版纯 .db
      final fileBytes = await File(tempFilePath).readAsBytes();
      Archive? archive;
      try {
        archive = ZipDecoder().decodeBytes(fileBytes);
        LoggerService.instance.i(
          '检测到 zip 备份包（${archive.files.length} 个文件）',
          category: LogCategory.backup,
        );
      } catch (e) {
        archive = null;
        LoggerService.instance.i(
          '非 zip 备份包，按旧版纯 .db 流程处理: $e',
          category: LogCategory.backup,
        );
      }

      if (archive == null) {
        // 旧版兼容：仅恢复 DB
        await _restoreDatabaseOnly(
          sourcePath: tempFilePath,
          targetFilePath: targetFilePath,
          bakFilePath: bakFilePath,
        );
        LoggerService.instance.i(
          '旧版备份恢复完成（仅 DB）: $backupId',
          category: LogCategory.backup,
        );
        return;
      }

      // 步骤 5：新版备份 - 解出 DB 与 preferences.json
      final dbEntry = archive.files.firstWhere(
        (f) => path.basename(f.name) == _dbFileNameInZip,
        orElse: () => throw Exception('备份包缺少数据库文件: $_dbFileNameInZip'),
      );
      final prefsEntry = archive.files.firstWhere(
        (f) => path.basename(f.name) == _prefsFileNameInZip,
        orElse: () => throw Exception(
            '备份包缺少偏好设置文件: $_prefsFileNameInZip（此备份可能为不完整快照）'),
      );

      // 写出 DB 到独立临时路径
      final dbBytes = dbEntry.content as List<int>;
      final dbFile = File(dbFromZipPath);
      await dbFile.writeAsBytes(dbBytes, flush: true);

      // 解析 preferences.json
      final prefsBytes = prefsEntry.content as List<int>;
      final prefsJson = jsonDecode(utf8.decode(prefsBytes)) as Map<String, dynamic>;
      final prefsList = (prefsJson['prefs'] as List?) ?? const [];

      // 步骤 6：恢复 DB（复用现有 10 步流程的子集）
      await _restoreDatabaseOnly(
        sourcePath: dbFromZipPath,
        targetFilePath: targetFilePath,
        bakFilePath: bakFilePath,
      );

      // 步骤 7：Prefs 快照（必须包含全部当前键，含 flutter 内部键）
      prefsSnapshot = await _snapshotAllPrefs();

      // 步骤 8：写入新 Prefs
      try {
        await _restorePrefsFromList(prefsList);
        LoggerService.instance.i(
          'SharedPreferences 恢复完成（${prefsList.length} 个键）',
          category: LogCategory.backup,
        );
      } catch (e, stackTrace) {
        // Prefs 写入失败 → 仅回滚 Prefs（DB 不回滚）
        LoggerService.instance.e(
          'Prefs 写入失败，尝试回滚: $e',
          category: LogCategory.backup,
          stackTrace: stackTrace.toString(),
        );
        try {
          await _rollbackPrefs(prefsSnapshot);
          LoggerService.instance.i(
            'Prefs 已回滚到原值',
            category: LogCategory.backup,
          );
        } catch (rollbackErr) {
          LoggerService.instance.e(
            'Prefs 回滚也失败，请重启应用: $rollbackErr',
            category: LogCategory.backup,
          );
        }
        throw Exception('偏好设置恢复失败，已回滚到原值: $e');
      }

      LoggerService.instance.i(
        '备份恢复完成（含 Prefs）: $backupId',
        category: LogCategory.backup,
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '恢复备份失败: $e',
        category: LogCategory.backup,
        stackTrace: stackTrace.toString(),
      );
      rethrow;
    } finally {
      // 清理所有临时文件
      // 注意：bak 由 _restoreDatabaseOnly 内部成功路径清理，
      // 异常路径下保留 bak 以便用户手动恢复，此处不删 bak
      await _tryDelete(tempFilePath);
      await _tryDelete(dbFromZipPath);
    }
  }

  // ============================================================
  // 内部：DB 恢复（与原 10 步流程等价，可被旧版/新版路径复用）
  // ============================================================

  /// 仅恢复 DB（与原 restoreBackup 中步骤 3-10 等价）
  Future<void> _restoreDatabaseOnly({
    required String sourcePath,
    required String targetFilePath,
    required String bakFilePath,
  }) async {
    final sourceFile = File(sourcePath);
    final fileSize = await sourceFile.length();
    if (fileSize < 16) {
      await _tryDelete(sourcePath);
      throw Exception('下载的文件不是有效的 SQLite 数据库（文件过小）');
    }

    // SQLite header 校验
    final headerBytes = await sourceFile.openRead(0, 16).first;
    const sqliteHeader = 'SQLite format 3\x00';
    final header = String.fromCharCodes(headerBytes);
    if (header != sqliteHeader) {
      await _tryDelete(sourcePath);
      throw Exception('下载的文件不是有效的 SQLite 数据库');
    }
    LoggerService.instance.i('SQLite header 校验通过', category: LogCategory.backup);

    // 关闭数据库连接
    final dbConnection = DatabaseConnection();
    await dbConnection.close();

    // 备份现有 DB（rename 加有限重试，应对 Windows 文件句柄释放延迟/临时占用）
    final existingDb = File(targetFilePath);
    if (await existingDb.exists()) {
      final oldBak = File(bakFilePath);
      if (await oldBak.exists()) await _deleteWithRetry(oldBak);
      await _renameWithRetry(existingDb, bakFilePath);
      LoggerService.instance.i(
        '现有数据库已备份: $bakFilePath',
        category: LogCategory.backup,
      );
    }

    // 复制并删除源
    await sourceFile.copy(targetFilePath);
    if (sourcePath != targetFilePath) {
      await _tryDelete(sourcePath);
    }

    // 验证恢复
    try {
      await dbConnection.database;
      LoggerService.instance.i(
        '数据库重新打开成功',
        category: LogCategory.backup,
      );
      // 恢复成功，删除 bak
      final bakFile = File(bakFilePath);
      if (await bakFile.exists()) await _deleteWithRetry(bakFile);
    } catch (e) {
      LoggerService.instance.e(
        '恢复后数据库打开失败，正在回滚...',
        category: LogCategory.backup,
      );
      final bakFile = File(bakFilePath);
      if (await bakFile.exists()) {
        await dbConnection.close();
        final targetFile = File(targetFilePath);
        if (await targetFile.exists()) await _deleteWithRetry(targetFile);
        await _renameWithRetry(bakFile, targetFilePath);
        await dbConnection.database;
      }
      throw Exception('数据库恢复失败，已回滚到原数据库: $e');
    }
  }

  // ============================================================
  // 内部：打包
  // ============================================================

  /// 打包备份：把 DB 与 SharedPreferences 一起打成 zip
  Future<File> _packBackup({required bool excludeToken}) async {
    final dbPath = await getDatabasesPath();
    final dbFilePath = path.join(dbPath, 'novel_reader.db');
    final dbFile = File(dbFilePath);
    if (!await dbFile.exists()) {
      throw Exception('数据库文件不存在: $dbFilePath');
    }

    // 1) 收集 Prefs
    final prefsList = await _collectPrefsForExport(excludeToken: excludeToken);
    final prefsJson = {
      'version': _prefsSchemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'prefs': prefsList,
    };
    final prefsBytes = utf8.encode(jsonEncode(prefsJson));

    // 2) 读取 DB
    final dbBytes = await dbFile.readAsBytes();

    // 3) 打包为 zip
    final archive = Archive()
      ..addFile(ArchiveFile(_dbFileNameInZip, dbBytes.length, dbBytes))
      ..addFile(ArchiveFile(_prefsFileNameInZip, prefsBytes.length, prefsBytes));

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('打包备份失败：ZipEncoder 返回 null');
    }

    // 4) 写入临时 zip（文件名以 .zip 结尾，apiServiceWrapper 会原样作为上传名）
    final tempZipPath = path.join(dbPath, _backupFileName);
    final zipFile = File(tempZipPath);
    await zipFile.writeAsBytes(zipBytes, flush: true);

    LoggerService.instance.i(
      '打包完成: DB=${FormatUtils.formatFileSize(dbBytes.length)}, '
      'Prefs=${prefsList.length} 键, zip=${FormatUtils.formatFileSize(zipBytes.length)}',
      category: LogCategory.backup,
    );
    return zipFile;
  }

  /// 收集要导出的 Prefs 键值（带类型码）
  ///
  /// 返回 [PrefsEntry] 列表
  Future<List<Map<String, dynamic>>> _collectPrefsForExport({
    required bool excludeToken,
  }) async {
    final raw = await _prefs.getInstance();
    final keys = raw.getKeys();
    final result = <Map<String, dynamic>>[];

    for (final key in keys) {
      if (shouldExcludeKey(key, excludeToken: excludeToken)) continue;
      final value = raw.get(key);
      if (value == null) continue;
      final entry = encodePref(key, value);
      if (entry != null) result.add(entry);
    }
    return result;
  }

  /// 判断键是否应被排除
  @visibleForTesting
  bool shouldExcludeKey(String key, {required bool excludeToken}) {
    if (_excludedKeys.contains(key)) return true;
    for (final prefix in _excludedPrefixes) {
      if (key.startsWith(prefix)) return true;
    }
    if (excludeToken && key == _tokenKey) return true;
    return false;
  }

  /// 编码单个 Pref 键值为带类型码的 Map
  ///
  /// 类型码：s=String, i=int, d=double, b=bool, sl=List of String
  @visibleForTesting
  Map<String, dynamic>? encodePref(String key, Object value) {
    if (value is String) {
      return {'k': key, 't': 's', 'v': value};
    } else if (value is int) {
      return {'k': key, 't': 'i', 'v': value};
    } else if (value is double) {
      return {'k': key, 't': 'd', 'v': value};
    } else if (value is bool) {
      return {'k': key, 't': 'b', 'v': value};
    } else if (value is List<String>) {
      return {'k': key, 't': 'sl', 'v': value};
    }
    // 未知类型（如 List<dynamic>）跳过
    return null;
  }

  /// 收集要导出的 Prefs 键值（带类型码），暴露供测试
  @visibleForTesting
  Future<List<Map<String, dynamic>>> collectPrefsForExport({
    required bool excludeToken,
  }) =>
      _collectPrefsForExport(excludeToken: excludeToken);

  /// 从 JSON 数组写回 Prefs，暴露供测试
  @visibleForTesting
  Future<void> restorePrefsFromList(List prefsList) =>
      _restorePrefsFromList(prefsList);

  /// Prefs schema 版本号（供测试与未来兼容判断）
  @visibleForTesting
  int get prefsSchemaVersion => _prefsSchemaVersion;

  // ============================================================
  // 内部：Prefs 快照/回滚/写入
  // ============================================================

  /// 快照当前所有 Prefs（含 flutter 内部键），用于失败回滚
  Future<Map<String, Object?>> _snapshotAllPrefs() async {
    final raw = await _prefs.getInstance();
    final snapshot = <String, Object?>{};
    for (final key in raw.getKeys()) {
      snapshot[key] = raw.get(key);
    }
    return snapshot;
  }

  /// 从快照回滚 Prefs（清空后按快照写回）
  Future<void> _rollbackPrefs(Map<String, Object?> snapshot) async {
    final raw = await _prefs.getInstance();
    await raw.clear();
    // 用 setMultiple 写回（清空后逐项恢复，含 flutter 内部键）
    await _prefs.setMultiple(snapshot.cast<String, dynamic>());
  }

  /// 解析 preferences.json 的 prefs 列表并写入
  Future<void> _restorePrefsFromList(List prefsList) async {
    final raw = await _prefs.getInstance();
    // 不清空现有 Prefs，采用"覆盖"语义：仅写入备份中存在且类型匹配的键
    // 这样不破坏未导出的平台内部键
    for (final item in prefsList) {
      if (item is! Map) continue;
      final k = item['k'];
      final t = item['t'];
      final v = item['v'];
      if (k is! String || t is! String) continue;
      try {
        switch (t) {
          case 's':
            if (v is String) await raw.setString(k, v);
            break;
          case 'i':
            if (v is int) await raw.setInt(k, v);
            break;
          case 'd':
            if (v is num) await raw.setDouble(k, v.toDouble());
            break;
          case 'b':
            if (v is bool) await raw.setBool(k, v);
            break;
          case 'sl':
            if (v is List) {
              await raw.setStringList(k, v.map((e) => e.toString()).toList());
            }
            break;
        }
      } catch (e) {
        // 单个键失败不阻塞其他键
        LoggerService.instance.w(
          '恢复 Prefs 键失败: $k ($t) = $v → $e',
          category: LogCategory.backup,
        );
      }
    }
  }

  /// 异步删除文件（不存在则忽略）
  Future<void> _tryDelete(String filePath) async {
    try {
      final f = File(filePath);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // ignore
    }
  }

  /// 带重试的文件重命名
  ///
  /// Windows 上 sqflite_ffi 的文件句柄释放有延迟，rename 可能偶发
  /// `PathAccessException`。生产环境也存在其他读连接占用导致锁失败
  /// 的情况（杀毒扫描、备份工具等），重试能提升健壮性。
  Future<void> _renameWithRetry(
    File source,
    String newPath, {
    int maxAttempts = 3,
    Duration delay = const Duration(milliseconds: 100),
  }) async {
    Object? lastError;
    for (var i = 0; i < maxAttempts; i++) {
      try {
        await source.rename(newPath);
        if (i > 0) {
          LoggerService.instance.i(
            '文件重命名在第 ${i + 1} 次重试成功: ${source.path} -> $newPath',
            category: LogCategory.backup,
          );
        }
        return;
      } catch (e) {
        lastError = e;
        if (i < maxAttempts - 1) {
          LoggerService.instance.w(
            '文件重命名失败，将重试 (${i + 1}/$maxAttempts): '
            '${source.path} -> $newPath ($e)',
            category: LogCategory.backup,
          );
          await Future.delayed(delay);
        }
      }
    }
    throw Exception('文件重命名失败（已重试 $maxAttempts 次）: $lastError');
  }

  /// 带重试的文件删除
  Future<void> _deleteWithRetry(
    File file, {
    int maxAttempts = 3,
    Duration delay = const Duration(milliseconds: 100),
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      try {
        if (await file.exists()) await file.delete();
        return;
      } catch (_) {
        if (i < maxAttempts - 1) await Future.delayed(delay);
      }
    }
    // 静默忽略最终失败（删除 .bak 失败不影响主流程）
  }

  // ============================================================
  // 公共 API：备份时间记录
  // ============================================================

  /// 获取上次备份时间
  Future<DateTime?> getLastBackupTime() async {
    try {
      final timestamp = await _prefs.getInt(_prefsLastBackupTimeKey);
      if (timestamp == 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '获取上次备份时间失败: $e',
        category: LogCategory.backup,
        stackTrace: stackTrace.toString(),
      );
      return null;
    }
  }

  /// 保存备份时间
  Future<void> saveBackupTime(DateTime time) async {
    try {
      await _prefs.setInt(
          _prefsLastBackupTimeKey, time.millisecondsSinceEpoch);
      LoggerService.instance.i(
        '记录备份时间: $time',
        category: LogCategory.backup,
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '保存备份时间失败: $e',
        category: LogCategory.backup,
        stackTrace: stackTrace.toString(),
      );
    }
  }

  /// 清除备份时间记录
  Future<void> clearBackupTime() async {
    try {
      await _prefs.remove(_prefsLastBackupTimeKey);
      LoggerService.instance.i(
        '清除备份时间记录',
        category: LogCategory.backup,
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '清除备份时间失败: $e',
        category: LogCategory.backup,
        stackTrace: stackTrace.toString(),
      );
    }
  }

  /// 获取上次备份时间的友好显示文本
  Future<String> getLastBackupTimeText() async {
    final lastBackup = await getLastBackupTime();
    if (lastBackup == null) return '从未备份';

    final now = DateTime.now();
    final difference = now.difference(lastBackup);

    if (difference.inSeconds < 60) {
      return '刚刚';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小时前';
    } else if (difference.inDays == 1) {
      return '昨天';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return FormatUtils.formatDateTime(lastBackup, showTime: false);
    }
  }

  // ============================================================
  // 公共 API：服务器备份列表 / 下载 / 删除（与原实现一致）
  // ============================================================

  /// 获取服务器备份列表
  Future<List<Map<String, dynamic>>> getBackupList({
    required ApiServiceWrapper apiWrapper,
  }) async {
    try {
      LoggerService.instance.i(
        '获取服务器备份列表',
        category: LogCategory.backup,
      );
      final backups = await apiWrapper.getBackupList();
      LoggerService.instance.i(
        '获取备份列表成功: ${backups.length} 条',
        category: LogCategory.backup,
      );
      return backups;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '获取备份列表失败: $e',
        category: LogCategory.backup,
        stackTrace: stackTrace.toString(),
      );
      rethrow;
    }
  }

  /// 下载服务器备份到本地文件
  Future<File> downloadBackup({
    required ApiServiceWrapper apiWrapper,
    required String backupId,
    required String savePath,
  }) async {
    try {
      LoggerService.instance.i(
        '下载备份: $backupId -> $savePath',
        category: LogCategory.backup,
      );
      await apiWrapper.downloadBackup(
        backupId: backupId,
        savePath: savePath,
      );
      final file = File(savePath);
      if (!await file.exists()) {
        throw Exception('下载完成但文件不存在: $savePath');
      }
      LoggerService.instance.i(
        '备份下载完成: ${FormatUtils.formatFileSize(await file.length())}',
        category: LogCategory.backup,
      );
      return file;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '下载备份失败: $e',
        category: LogCategory.backup,
        stackTrace: stackTrace.toString(),
      );
      rethrow;
    }
  }

  /// 删除服务器上的备份文件
  Future<void> deleteBackupOnServer({
    required ApiServiceWrapper apiWrapper,
    required String backupId,
  }) async {
    try {
      LoggerService.instance.i(
        '删除服务器备份: $backupId',
        category: LogCategory.backup,
      );
      await apiWrapper.deleteBackupOnServer(backupId: backupId);
      LoggerService.instance.i(
        '备份删除成功: $backupId',
        category: LogCategory.backup,
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '删除备份失败: $e',
        category: LogCategory.backup,
        stackTrace: stackTrace.toString(),
      );
      rethrow;
    }
  }
}
