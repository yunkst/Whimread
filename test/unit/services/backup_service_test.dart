/// BackupService 单元测试
///
/// 验证：
/// - getBackupList / deleteBackupOnServer 委托逻辑
/// - restoreBackup 的 10 步流程
///   - SQLite header 校验（防止恢复错误文件）
///   - 临时文件清理
///   - .bak 备份创建
///   - 目标文件替换
///   - DB 重新打开成功 → 删除 .bak
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/services/backup_service_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/services/api_service_wrapper.dart';
import 'package:novel_app/services/backup_service.dart';

import '../../test_bootstrap.dart';

@GenerateMocks([ApiServiceWrapper])
import 'backup_service_test.mocks.dart';

/// 测试用：生成有效的 SQLite 文件字节（header-only，仅用于校验测试）
Uint8List _validSqliteHeaderBytes() {
  final header = 'SQLite format 3\x00'.codeUnits;
  final bytes = Uint8List(64);
  for (var i = 0; i < header.length; i++) {
    bytes[i] = header[i];
  }
  return bytes;
}

/// 测试用：生成无效的文件字节
Uint8List _invalidBytes() {
  return Uint8List.fromList(utf8.encode('not a sqlite file at all...'));
}

/// 在指定路径创建一个真实的 SQLite 数据库并返回其路径
Future<String> _createRealSqliteDb(String path) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(version: 1, onCreate: (db, v) async {
      await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY)');
      await db.insert('t', {'id': 1});
    }),
  );
  await db.close();
  return path;
}

void main() {
  initDatabaseTests();

  group('getBackupList', () {
    test('应正确委托给 ApiServiceWrapper', () async {
      final mockApi = MockApiServiceWrapper();
      final expectedList = [
        {'backup_id': '2026-06-15/test.db', 'file_size': 1024},
      ];

      when(mockApi.getBackupList()).thenAnswer((_) async => expectedList);

      final service = BackupService();
      final result = await service.getBackupList(apiWrapper: mockApi);

      expect(result, expectedList);
      verify(mockApi.getBackupList()).called(1);
    });

    test('网络异常应向上抛出', () async {
      final mockApi = MockApiServiceWrapper();
      when(mockApi.getBackupList()).thenThrow(Exception('网络错误'));

      final service = BackupService();
      expect(
        () => service.getBackupList(apiWrapper: mockApi),
        throwsException,
      );
    });
  });

  group('deleteBackupOnServer', () {
    test('应正确委托给 ApiServiceWrapper', () async {
      final mockApi = MockApiServiceWrapper();
      when(mockApi.deleteBackupOnServer(backupId: anyNamed('backupId')))
          .thenAnswer((_) async {});

      final service = BackupService();
      await service.deleteBackupOnServer(
        apiWrapper: mockApi,
        backupId: '2026-06-15/test.db',
      );

      verify(mockApi.deleteBackupOnServer(backupId: '2026-06-15/test.db'))
          .called(1);
    });
  });

  group('restoreBackup', () {
    late String dbDir;
    late String dbPath;
    late String tempPath;
    late String bakPath;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SharedPreferences.getInstance();

      // 使用 getDatabasesPath() 返回的实际路径（sqflite_ffi 内部目录）
      // 这样 restoreBackup 和测试使用同一个目录
      dbDir = await getDatabasesPath();
      dbPath = p.join(dbDir, 'novel_reader.db');
      tempPath = p.join(dbDir, 'novel_app_restore_temp.db');
      bakPath = p.join(dbDir, 'novel_reader.db.bak');

      // 确保数据库目录存在（sqflite_ffi 仅在首次打开数据库时创建该目录；
      // 若本测试组在目录创建前执行，restoreBackup 的 mock 写临时文件会
      // 触发 PathNotFoundException，在干净的 CI 环境上尤为明显）
      await Directory(dbDir).create(recursive: true);

      // 强制重置 DatabaseConnection 单例 + 清理残留文件。
      // 单例 static _database / _instance 不重置会让前一个测试留下的 stale
      // handle 污染本测试（典型表现：'no such table: novel_chapters'，
      // 因为 sqflite 拿到空文件 → 跳过 onCreate → 不跑迁移）。
      await DatabaseConnection.resetInstance();
      for (final f in [dbPath, tempPath, bakPath]) {
        try {
          File(f).deleteSync();
        } catch (_) {}
      }
    });

    tearDown(() async {
      await DatabaseConnection.resetInstance();
      for (final f in [dbPath, tempPath, bakPath]) {
        try {
          File(f).deleteSync();
        } catch (_) {}
      }
    });

    test('下载文件不是 SQLite 应被拦截并清理临时文件', () async {
      final mockApi = MockApiServiceWrapper();

      when(mockApi.downloadBackup(
        backupId: anyNamed('backupId'),
        savePath: anyNamed('savePath'),
      )).thenAnswer((invocation) async {
        final sp = invocation.namedArguments[#savePath] as String;
        File(sp).writeAsBytesSync(_invalidBytes());
        return sp;
      });

      final service = BackupService();
      expect(
        () => service.restoreBackup(
          apiWrapper: mockApi,
          backupId: '2026-06-15/bad.db',
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('SQLite'),
        )),
      );

      // 临时文件应被删除
      expect(File(tempPath).existsSync(), isFalse);
    });

    test('下载文件过小应被拒绝', () async {
      final mockApi = MockApiServiceWrapper();

      when(mockApi.downloadBackup(
        backupId: anyNamed('backupId'),
        savePath: anyNamed('savePath'),
      )).thenAnswer((invocation) async {
        final sp = invocation.namedArguments[#savePath] as String;
        File(sp).writeAsBytesSync(Uint8List(10));
        return sp;
      });

      final service = BackupService();
      expect(
        () => service.restoreBackup(
          apiWrapper: mockApi,
          backupId: '2026-06-15/tiny.db',
        ),
        throwsA(isA<Exception>()),
      );

      expect(File(tempPath).existsSync(), isFalse);
    });

    test('happy path: 成功恢复后 .bak 应被删除', () async {
      // 用 DatabaseConnection 初始化一个完整的应用数据库作为「源」
      // (保证迁移表结构完整, 重新打开时不会失败)
      final conn = DatabaseConnection();
      await conn.initialize();
      await conn.close();
      expect(File(dbPath).existsSync(), isTrue);

      // 把这个完整数据库的字节作为「下载内容」
      final realDbBytes = File(dbPath).readAsBytesSync();

      final mockApi = MockApiServiceWrapper();
      when(mockApi.downloadBackup(
        backupId: anyNamed('backupId'),
        savePath: anyNamed('savePath'),
      )).thenAnswer((invocation) async {
        final sp = invocation.namedArguments[#savePath] as String;
        File(sp).writeAsBytesSync(realDbBytes);
        return sp;
      });

      final service = BackupService();
      await service.restoreBackup(
        apiWrapper: mockApi,
        backupId: '2026-06-15/good.db',
      );

      // DB 文件应被替换
      expect(File(dbPath).existsSync(), isTrue);
      // .bak 应被删除（恢复成功后）
      expect(File(bakPath).existsSync(), isFalse);
      // 临时文件应被清理
      expect(File(tempPath).existsSync(), isFalse);
    });

    test('回滚: 恢复不兼容 DB 后能从 .bak 恢复', () async {
      // 先创建一个合法的源数据库
      final conn = DatabaseConnection();
      await conn.initialize();
      await conn.close();
      expect(File(dbPath).existsSync(), isTrue);

      // 下载内容是「仅 header」的无效 SQLite（能通过 header 校验，但迁移会失败）
      final headerOnlyBytes = _validSqliteHeaderBytes();
      final headerOnlyDb = p.join(dbDir, 'header_only.db');
      // 用一个完整但表结构不对的 SQLite 文件
      await _createRealSqliteDb(headerOnlyDb);
      final wrongSchemaBytes = File(headerOnlyDb).readAsBytesSync();

      final mockApi = MockApiServiceWrapper();
      when(mockApi.downloadBackup(
        backupId: anyNamed('backupId'),
        savePath: anyNamed('savePath'),
      )).thenAnswer((invocation) async {
        final sp = invocation.namedArguments[#savePath] as String;
        File(sp).writeAsBytesSync(wrongSchemaBytes);
        return sp;
      });

      final service = BackupService();
      // 恢复会因迁移失败而抛异常
      expect(
        () => service.restoreBackup(
          apiWrapper: mockApi,
          backupId: '2026-06-15/wrong.db',
        ),
        throwsA(isA<Exception>()),
      );

      // 但原数据库应该被 .bak 恢复（回滚成功）
      expect(File(dbPath).existsSync(), isTrue);
      try { File(headerOnlyDb).deleteSync(); } catch (_) {}
    });

    test('恢复失败时异常应向上抛出', () async {
      final mockApi = MockApiServiceWrapper();
      when(mockApi.downloadBackup(
        backupId: anyNamed('backupId'),
        savePath: anyNamed('savePath'),
      )).thenThrow(Exception('下载失败'));

      final service = BackupService();
      expect(
        () => service.restoreBackup(
          apiWrapper: mockApi,
          backupId: '2026-06-15/fail.db',
        ),
        throwsException,
      );
    });
  });

  group('backup 时间管理', () {
    test('getLastBackupTime 初始为 null', () async {
      SharedPreferences.setMockInitialValues({});
      await SharedPreferences.getInstance();

      final service = BackupService();
      final result = await service.getLastBackupTime();
      expect(result, isNull);
    });

    test('saveBackupTime 后 getLastBackupTime 应返回相同时间', () async {
      SharedPreferences.setMockInitialValues({});
      await SharedPreferences.getInstance();

      final service = BackupService();
      final now = DateTime.now();
      await service.saveBackupTime(now);

      final result = await service.getLastBackupTime();
      expect(result, isNotNull);
      expect(result!.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
    });

    test('getLastBackupTimeText 未备份时应返回"从未备份"', () async {
      SharedPreferences.setMockInitialValues({});
      await SharedPreferences.getInstance();

      final service = BackupService();
      final result = await service.getLastBackupTimeText();
      expect(result, '从未备份');
    });
  });
}
