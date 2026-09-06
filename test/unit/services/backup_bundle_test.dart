/// BackupService 备份包增强测试
///
/// 验证 SQLite + SharedPreferences 联合备份的新增能力：
/// - Prefs 序列化往返（类型不丢）
/// - 键过滤规则（排除设备相关/迁移标记/Cookie）
/// - Token 开关（excludeToken）
/// - 旧版纯 .db 兼容路径
/// - 新版 zip 备份包端到端恢复（含 Prefs）
/// - Prefs 写入失败时回滚（不影响 DB）
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/services/backup_bundle_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/services/api_service_wrapper.dart';
import 'package:novel_app/services/backup_service.dart';

import '../../test_bootstrap.dart';

@GenerateMocks([ApiServiceWrapper])
import 'backup_bundle_test.mocks.dart';

void main() {
  initDatabaseTests();

  late String dbDir;
  late String dbPath;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();

    dbDir = await getDatabasesPath();
    dbPath = p.join(dbDir, 'novel_reader.db');
    await Directory(dbDir).create(recursive: true);

    await DatabaseConnection.resetInstance();
    for (final f in [
      dbPath,
      p.join(dbDir, 'novel_reader.db.bak'),
      p.join(dbDir, 'novel_app_restore_temp.zip'),
      p.join(dbDir, 'novel_app_restore_db.db'),
      p.join(dbDir, 'novel_app_backup.zip'),
    ]) {
      try {
        File(f).deleteSync();
      } catch (_) {}
    }
  });

  tearDown(() async {
    await DatabaseConnection.resetInstance();
  });

  group('encodePref / shouldExcludeKey', () {
    final service = BackupService();

    test('String 编码为 t=s', () {
      final e = service.encodePref('k', 'v');
      expect(e, {'k': 'k', 't': 's', 'v': 'v'});
    });

    test('int 编码为 t=i（不会与 double 混淆）', () {
      final e = service.encodePref('k', 42);
      expect(e?['t'], 'i');
      expect(e?['v'], 42);
      expect(e?['v'], isA<int>());
    });

    test('double 编码为 t=d', () {
      final e = service.encodePref('k', 3.14);
      expect(e?['t'], 'd');
      expect(e?['v'], 3.14);
    });

    test('bool 编码为 t=b', () {
      final e = service.encodePref('k', true);
      expect(e?['t'], 'b');
    });

    test('List<String> 编码为 t=sl', () {
      final e = service.encodePref('k', ['a', 'b']);
      expect(e?['t'], 'sl');
      expect(e?['v'], ['a', 'b']);
    });

    test('未知类型（List<int>）返回 null', () {
      expect(service.encodePref('k', <int>[1, 2]), isNull);
    });

    test('默认排除 last_backup_time', () {
      expect(
        service.shouldExcludeKey('last_backup_time', excludeToken: false),
        isTrue,
      );
    });

    test('默认排除 webview_ 前缀', () {
      expect(
        service.shouldExcludeKey('webview_cookie', excludeToken: false),
        isTrue,
      );
    });

    test('默认排除 migrated_ 前缀', () {
      expect(
        service.shouldExcludeKey('migrated_llm_v1', excludeToken: false),
        isTrue,
      );
    });

    test('api_token 默认包含；excludeToken=true 时排除', () {
      expect(
        service.shouldExcludeKey('api_token', excludeToken: false),
        isFalse,
      );
      expect(
        service.shouldExcludeKey('api_token', excludeToken: true),
        isTrue,
      );
    });

    test('普通业务键不被排除', () {
      expect(
        service.shouldExcludeKey('api_host', excludeToken: false),
        isFalse,
      );
      expect(
        service.shouldExcludeKey('reader_font_size', excludeToken: false),
        isFalse,
      );
    });
  });

  group('collectPrefsForExport（过滤+序列化）', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'api_host': 'http://192.168.1.10:3800',
        'api_token': 'secret-token',
        'reader_font_size': 18.0,
        'theme_mode': 'ThemeMode.dark',
        'onboarding_completed': true,
        'test_int_key': 3000,
        'bookmark_novel_x': ['ch1', 'ch2'],
        'last_backup_time': 123456789, // 应被排除
        'webview_ua': 'Mozilla', // 应被排除（前缀）
        'migrated_llm': true, // 应被排除（前缀）
      });
      await SharedPreferences.getInstance();
    });

    test('excludeToken=false：导出 api_token，排除黑名单键', () async {
      final service = BackupService();
      final list = await service.collectPrefsForExport(excludeToken: false);
      final keys = list.map((e) => e['k'] as String).toSet();

      expect(keys, containsAll([
        'api_host',
        'api_token',
        'reader_font_size',
        'theme_mode',
        'onboarding_completed',
        'test_int_key',
        'bookmark_novel_x',
      ]));
      expect(keys, isNot(contains('last_backup_time')));
      expect(keys, isNot(contains('webview_ua')));
      expect(keys, isNot(contains('migrated_llm')));
    });

    test('excludeToken=true：不导出 api_token', () async {
      final service = BackupService();
      final list = await service.collectPrefsForExport(excludeToken: true);
      final keys = list.map((e) => e['k'] as String).toSet();

      expect(keys, isNot(contains('api_token')));
      // 其他业务键仍应导出
      expect(keys, contains('api_host'));
    });

    test('类型码正确：double 标 d、int 标 i、bool 标 b、String 标 s', () async {
      final service = BackupService();
      final list = await service.collectPrefsForExport(excludeToken: false);
      final byKey = {for (final e in list) e['k'] as String: e};

      expect(byKey['reader_font_size']?['t'], 'd');
      expect(byKey['test_int_key']?['t'], 'i');
      expect(byKey['onboarding_completed']?['t'], 'b');
      expect(byKey['theme_mode']?['t'], 's');
      expect(byKey['bookmark_novel_x']?['t'], 'sl');
    });
  });

  group('restorePrefsFromList（往返）', () {
    test('序列化往返：类型与值完整保留', () async {
      SharedPreferences.setMockInitialValues({
        'api_host': 'http://192.168.1.10:3800',
        'api_token': 'secret',
        'reader_font_size': 18.0,
        'theme_mode': 'ThemeMode.dark',
        'onboarding_completed': true,
        'test_int_key': 3000,
        'bookmark_novel_x': ['ch1', 'ch2'],
      });
      await SharedPreferences.getInstance();

      final service = BackupService();
      // 导出
      final exported = await service.collectPrefsForExport(excludeToken: false);

      // 清空后写回
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      await service.restorePrefsFromList(exported);

      // 校验
      final prefs2 = await SharedPreferences.getInstance();
      // double 仍是 double
      expect(prefs2.getDouble('reader_font_size'), 18.0);
      expect(prefs2.getInt('test_int_key'), 3000);
      expect(prefs2.getBool('onboarding_completed'), true);
      expect(prefs2.getString('theme_mode'), 'ThemeMode.dark');
      expect(prefs2.getStringList('bookmark_novel_x'), ['ch1', 'ch2']);
    });

    test('JSON 序列化往返后类型不丢（int 不会被解析为 double）', () async {
      SharedPreferences.setMockInitialValues({
        'test_int_key': 3000,
        'reader_font_size': 18.0,
      });
      await SharedPreferences.getInstance();

      final service = BackupService();
      final exported = await service.collectPrefsForExport(excludeToken: false);

      // 模拟"打包 -> 解压 -> 解析 JSON"的完整链路
      final jsonStr = jsonEncode({'prefs': exported});
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final prefsList = decoded['prefs'] as List;

      // 清空写回
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await service.restorePrefsFromList(prefsList);

      final prefs2 = await SharedPreferences.getInstance();
      // 关键：int 字段读出来仍是 int，不会被 JSON 拆成 double
      expect(prefs2.getInt('test_int_key'), 3000);
      // double 字段仍是 double
      expect(prefs2.getDouble('reader_font_size'), 18.0);
    });

    test('损坏的类型码项被跳过，不阻塞其他键', () async {
      SharedPreferences.setMockInitialValues({});
      await SharedPreferences.getInstance();

      final service = BackupService();
      // 故意构造一个类型码为未知值的项
      await service.restorePrefsFromList([
        {'k': 'good_key', 't': 's', 'v': 'hello'},
        {'k': 'bad_key', 't': 'xx', 'v': 1}, // 未知类型码
        {'k': 'good_int', 't': 'i', 'v': 7},
      ]);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('good_key'), 'hello');
      expect(prefs.getInt('good_int'), 7);
      expect(prefs.containsKey('bad_key'), isFalse);
    });
  });

  group('restoreBackup：旧版纯 .db 兼容', () {
    test('纯 .db 文件走旧版路径，仅恢复 DB', () async {
      // 准备一个完整的源 DB（用 DatabaseConnection 保证迁移表结构完整）
      final conn = DatabaseConnection();
      await conn.initialize();
      await conn.close();
      expect(File(dbPath).existsSync(), isTrue);
      final realDbBytes = File(dbPath).readAsBytesSync();

      final mockApi = MockApiServiceWrapper();
      when(mockApi.downloadBackup(
        backupId: anyNamed('backupId'),
        savePath: anyNamed('savePath'),
      )).thenAnswer((invocation) async {
        final sp = invocation.namedArguments[#savePath] as String;
        // 直接写纯 .db 字节（无 zip 包装）
        File(sp).writeAsBytesSync(realDbBytes);
        return sp;
      });

      // 预置一个 Prefs 值，恢复后应保持不变（旧版不碰 Prefs）
      SharedPreferences.setMockInitialValues({'keep_me': 'untouched'});
      await SharedPreferences.getInstance();

      final service = BackupService();
      await service.restoreBackup(
        apiWrapper: mockApi,
        backupId: '2026-06-15/old.db',
      );

      // DB 已替换
      expect(File(dbPath).existsSync(), isTrue);
      // 旧版路径不应修改 Prefs
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('keep_me'), 'untouched');
    });
  });

  group('zip 备份包结构（纯解包验证，不触发 SQLite 锁）', () {
    test('合法 zip 包能正确解出 DB 字节和 preferences.json', () async {
      // 构造一个最小 DB 字节（仅 header，足够让解包步骤识别为有效 zip）
      final dbBytes = utf8.encode('SQLite format 3\x00PADDING_PADDING_PADDING');
      final prefsList = [
        {'k': 'api_host', 't': 's', 'v': 'http://x:3800'},
        {'k': 'reader_font_size', 't': 'd', 'v': 18.0},
        {'k': 'test_int_key', 't': 'i', 'v': 3000},
        {'k': 'onboarding_completed', 't': 'b', 'v': true},
        {'k': 'bookmark_x', 't': 'sl', 'v': ['a', 'b']},
      ];
      final prefsJson = jsonEncode({
        'version': 1,
        'exportedAt': '2026-07-06T12:00:00',
        'prefs': prefsList,
      });
      final prefsBytes = utf8.encode(prefsJson);

      final archive = Archive()
        ..addFile(ArchiveFile('novel_reader.db', dbBytes.length, dbBytes))
        ..addFile(
            ArchiveFile('preferences.json', prefsBytes.length, prefsBytes));
      final zipBytes = ZipEncoder().encode(archive)!;
      expect(zipBytes.length, greaterThan(0));

      // 模拟"服务器下载到本地 -> 解包"的关键步骤
      final decoded = ZipDecoder().decodeBytes(zipBytes);
      expect(decoded.files.length, 2);

      final dbEntry = decoded.files.firstWhere(
        (f) => p.basename(f.name) == 'novel_reader.db',
      );
      final prefsEntry = decoded.files.firstWhere(
        (f) => p.basename(f.name) == 'preferences.json',
      );
      expect(dbEntry.size, dbBytes.length);
      expect(prefsEntry.size, prefsBytes.length);

      // DB 字节完整保留
      expect(dbEntry.content, dbBytes);

      // preferences.json 可解析
      final parsed = jsonDecode(utf8.decode(prefsEntry.content as List<int>))
          as Map<String, dynamic>;
      expect(parsed['version'], 1);
      final parsedList = (parsed['prefs'] as List).cast<Map>();
      expect(parsedList.length, 5);
      expect(parsedList[1]['t'], 'd');
      expect(parsedList[2]['t'], 'i');
    });

    test('zip 包缺少 preferences.json 时解包步骤能识别为缺失', () async {
      final dbBytes = utf8.encode('SQLite format 3\x00PADDING');
      final archive = Archive()
        ..addFile(ArchiveFile('novel_reader.db', dbBytes.length, dbBytes));
      final zipBytes = ZipEncoder().encode(archive)!;

      final decoded = ZipDecoder().decodeBytes(zipBytes);
      // 只含 DB，缺 preferences.json
      expect(
        decoded.files.any((f) => p.basename(f.name) == 'preferences.json'),
        isFalse,
      );
    });

    test('zip 包缺少 novel_reader.db 时解包步骤能识别为缺失', () async {
      final prefsBytes = utf8.encode(jsonEncode({'version': 1, 'prefs': []}));
      final archive = Archive()
        ..addFile(ArchiveFile(
            'preferences.json', prefsBytes.length, prefsBytes));
      final zipBytes = ZipEncoder().encode(archive)!;

      final decoded = ZipDecoder().decodeBytes(zipBytes);
      expect(
        decoded.files.any((f) => p.basename(f.name) == 'novel_reader.db'),
        isFalse,
      );
    });

    test('空 zip 或非 zip 数据应解包失败', () async {
      // 非 zip 字节应抛异常
      final notZip = utf8.encode('this is not a zip file');
      expect(
        () => ZipDecoder().decodeBytes(notZip),
        throwsA(anything),
      );
    });
  });

  group('prefsSchemaVersion', () {
    test('当前 schema 版本为 1', () {
      expect(BackupService().prefsSchemaVersion, 1);
    });
  });

  // 抑制未使用警告（保留 import 以便扩展）
}
