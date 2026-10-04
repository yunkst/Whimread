/// LlmConfigService 单测
///
/// 自配 LLM 模式移除后，服务只剩托管路径 + 遗留数据一次性擦除：
///   - [LlmConfigService.wipeLegacyLlmData]：llm_configs 整表清除 +
///     自配模式遗留 prefs key 清除（保留仍在用的 key）
///   - [LlmConfigService.ensureLegacyDataWipedForManaged]：非托管构建
///     （CI 默认 kHasBundledBackend=false）直接返回 0
///
/// 托管 Provider 构建（buildManagedProvider）依赖设备注册与网络，
/// 由真机/集成测试在带 `--dart-define=BACKEND_BASE_URL=...` 下验证。
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

  group('非托管构建守卫（CI 默认编译期常量 false）', () {
    setUp(setupContainer);

    test('ensureLegacyDataWipedForManaged 返回 0 且不触碰用户数据', () async {
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dsl_engine_api_key', 'sk-original');

      final service = container.read(llmConfigServiceProvider);
      expect(await service.ensureLegacyDataWipedForManaged(), 0);

      expect((await db.query('llm_configs')).single['api_key'], 'sk-original',
          reason: '非托管构建不应触碰用户自配 API Key');
      expect(prefs.getString('dsl_engine_api_key'), 'sk-original');
      expect(prefs.getInt('llm_api_keys_cleared_count'), isNull,
          reason: '未执行擦除时不应写完成标记');
    });
  });

  group('wipeLegacyLlmData（直接注入 prefs 验证，绕开编译期守卫）', () {
    setUp(setupContainer);

    Future<int> insertLegacyConfig(String name, String apiKey) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      return db.insert('llm_configs', {
        'name': name,
        'api_url': 'https://api.example.com',
        'api_key': apiKey,
        'model': 'gpt-x',
        'is_default': 0,
        'sort_order': 0,
        'created_at': now,
        'updated_at': now,
      });
    }

    test('整表清除遗留配置，返回清除条数', () async {
      await insertLegacyConfig('配置 A', 'sk-a');
      await insertLegacyConfig('配置 B', '');

      final service = container.read(llmConfigServiceProvider);
      final prefs = await SharedPreferences.getInstance();
      final cleared = await service.wipeLegacyLlmData(prefs);

      expect(cleared, 2);
      expect(await db.query('llm_configs'), isEmpty);
    });

    test('清除自配模式遗留 prefs key，保留仍在用的 key', () async {
      await insertLegacyConfig('配置 A', 'sk-a');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('llm_configs_migrated', true);
      await prefs.setInt('active_llm_profile_writing', 1);
      await prefs.setInt('active_llm_profile_id', 3);
      await prefs.setString('dsl_engine_api_key', 'sk-legacy');
      await prefs.setString('dsl_engine_model', 'gpt-x');
      await prefs.setString('backend_host', 'https://self-hosted.example.com');
      await prefs.setString('managed_model_selection', 'deepseek-v3');
      await prefs.setString('unrelated_key', 'keep-me');

      final service = container.read(llmConfigServiceProvider);
      await service.wipeLegacyLlmData(prefs);

      expect(prefs.getBool('llm_configs_migrated'), isNull);
      expect(prefs.getInt('active_llm_profile_writing'), isNull);
      expect(prefs.getInt('active_llm_profile_id'), isNull);
      expect(prefs.getString('dsl_engine_api_key'), isNull);
      expect(prefs.getString('dsl_engine_model'), isNull);
      expect(prefs.getString('backend_host'), isNull);
      // 托管模式仍在用的 key 与无关 key 不受影响
      expect(prefs.getString('managed_model_selection'), 'deepseek-v3');
      expect(prefs.getString('unrelated_key'), 'keep-me');
    });

    test('llm_configs 表缺失时静默降级，prefs 照常清理', () async {
      await db.execute('DROP TABLE llm_configs');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dsl_engine_api_key', 'sk-legacy');

      final service = container.read(llmConfigServiceProvider);
      final cleared = await service.wipeLegacyLlmData(prefs);

      expect(cleared, 0);
      expect(prefs.getString('dsl_engine_api_key'), isNull);
    });
  });
}
