/// LlmConfigService 托管模式 Key 清除单测
///
/// 可测范围受 `kHasBundledBackend` 是编译期 const 限制（CI 默认 false）：
///   - 非托管包守卫：返回 0、不读 prefs、不触发 DB
///   - getApiKeysClearedCount 非托管包：返回 null
///
/// 托管包行为（清空 → 写 prefs → 幂等）已在
/// `test/unit/repositories/llm_config_repository_test.dart` 单独覆盖 repo 路径；
/// service 层在托管包下只多一步 prefs 写与内存标记,可由集成测试在带
/// `--dart-define=BACKEND_BASE_URL=...` 的真机/集成 run 中验证。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/database/database_migrations.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/services/ai_service_providers.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ProviderContainer container;

  Future<void> setupContainer() async {
    db = await openDatabase(
      ':memory:',
      version: DatabaseMigrations.currentVersion,
      singleInstance: false,
    );
    await DatabaseMigrations.createV1Tables(db);
    await DatabaseMigrations.upgrade(db, 1, DatabaseMigrations.currentVersion);

    container = ProviderContainer(overrides: [
      databaseConnectionProvider
          .overrideWithValue(DatabaseConnection.forTesting(db)),
    ]);
    addTearDown(container.dispose);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('非托管包守卫（CI 默认编译期常量 false）', () {
    setUp(setupContainer);

    test('ensureApiKeysClearedForManaged 直接返回 0', () async {
      final service = container.read(llmConfigServiceProvider);
      expect(await service.ensureApiKeysClearedForManaged(), 0);
    });

    test('返回 0 时不动数据库：原 api_key 保留', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('llm_configs', {
        'name': 'DeepSeek',
        'api_url': 'https://api.deepseek.com',
        'api_key': 'sk-original',
        'model': 'deepseek-chat',
        'is_default': 1,
        'sort_order': 0,
        'created_at': now,
        'updated_at': now,
      });

      final service = container.read(llmConfigServiceProvider);
      await service.ensureApiKeysClearedForManaged();

      final rows = await db.query('llm_configs');
      expect(rows.single['api_key'], 'sk-original',
          reason: '非托管包不应触碰用户自配 API Key');
    });

    test('getApiKeysClearedCount 在非托管包下返回 null', () async {
      final service = container.read(llmConfigServiceProvider);
      expect(await service.getApiKeysClearedCount(), isNull);
    });

    test('返回 0 时不写入 prefs 标记', () async {
      final service = container.read(llmConfigServiceProvider);
      await service.ensureApiKeysClearedForManaged();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('llm_api_keys_cleared_count'), isNull);
    });
  });
}
