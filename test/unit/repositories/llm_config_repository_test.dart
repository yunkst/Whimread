/// LlmConfigRepository.clearAllApiKeys 单测
///
/// 托管模式下清空用户自配 LLM 配置的 API Key：
/// - 只清空原本非空的行（api_key != ''），不写入空值的 updated_at
/// - 返回实际清空的条数供 UI 提示
/// - 重复调用幂等（第二次返回 0）
/// - 表为空时返回 0
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/database/database_migrations.dart';
import 'package:novel_app/repositories/llm_config_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late LlmConfigRepository repo;

  setUp(() async {
    db = await openDatabase(
      ':memory:',
      version: DatabaseMigrations.currentVersion,
      singleInstance: false,
    );
    await DatabaseMigrations.createV1Tables(db);
    await DatabaseMigrations.upgrade(db, 1, DatabaseMigrations.currentVersion);
    repo = LlmConfigRepository(
      dbConnection: DatabaseConnection.forTesting(db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('空表：clearAllApiKeys 返回 0', () async {
    expect(await repo.clearAllApiKeys(), 0);
  });

  test('混合配置：只清空原本非空的 api_key，返回命中条数', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('llm_configs', {
      'name': 'DeepSeek',
      'api_url': 'https://api.deepseek.com',
      'api_key': 'sk-real-key-1',
      'model': 'deepseek-chat',
      'is_default': 1,
      'sort_order': 0,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('llm_configs', {
      'name': 'OpenAI',
      'api_url': 'https://api.openai.com',
      'api_key': '',
      'model': 'gpt-4',
      'is_default': 0,
      'sort_order': 1,
      'created_at': now,
      'updated_at': now,
    });

    final cleared = await repo.clearAllApiKeys();
    expect(cleared, 1, reason: '只有 DeepSeek 那行的 api_key 非空');

    final rows = await db.query('llm_configs', orderBy: 'sort_order ASC');
    expect(rows[0]['api_key'], '');
    expect(rows[1]['api_key'], '');
    expect(rows[0]['name'], 'DeepSeek');
    expect(rows[1]['name'], 'OpenAI');
  });

  test('全部有 key：清空所有行并返回行数', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < 3; i++) {
      await db.insert('llm_configs', {
        'name': 'cfg-$i',
        'api_url': 'https://example.com/$i',
        'api_key': 'key-$i',
        'model': 'm-$i',
        'is_default': i == 0 ? 1 : 0,
        'sort_order': i,
        'created_at': now,
        'updated_at': now,
      });
    }

    final cleared = await repo.clearAllApiKeys();
    expect(cleared, 3);

    final rows = await db.query('llm_configs');
    expect(rows.every((r) => (r['api_key'] as String).isEmpty), isTrue);
  });

  test('幂等：再次 clearAllApiKeys 返回 0', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('llm_configs', {
      'name': 'cfg',
      'api_url': 'https://example.com',
      'api_key': 'sk-x',
      'model': 'm',
      'is_default': 1,
      'sort_order': 0,
      'created_at': now,
      'updated_at': now,
    });

    expect(await repo.clearAllApiKeys(), 1);
    expect(await repo.clearAllApiKeys(), 0);
    expect(await repo.clearAllApiKeys(), 0);
  });

  test('保留元数据：清空后 name/api_url/model 不变', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('llm_configs', {
      'name': 'DeepSeek',
      'api_url': 'https://api.deepseek.com',
      'api_key': 'sk-real',
      'model': 'deepseek-chat',
      'is_default': 1,
      'sort_order': 0,
      'created_at': now,
      'updated_at': now,
    });

    await repo.clearAllApiKeys();

    final row = (await db.query('llm_configs')).first;
    expect(row['name'], 'DeepSeek');
    expect(row['api_url'], 'https://api.deepseek.com');
    expect(row['model'], 'deepseek-chat');
    expect(row['is_default'], 1);
  });
}
