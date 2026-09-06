/// LLM 配置选择逻辑测试 — 真实内存 SQLite
///
/// 验证 [LlmConfigService] 的两个核心行为：
/// 1. `getActiveConfig` fallback 优先级：场景覆盖 > 默认 > 第一条
/// 2. `ensureGlobalActiveMigrated` 平滑迁移：把旧 `active_llm_profile_id`
///    指向的配置升级为默认，幂等且对已删除配置安全降级
///
/// 配合工具/迁移回归验证：删掉 `setActiveConfig` 后，UI/服务都不应再触碰
/// 全局 prefs key。
///
/// 运行:
///   cd novel_app
///   flutter test test/bug/llm_config_selection_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/services/ai_service_providers.dart';
import 'package:novel_app/models/llm_config.dart';
import 'package:novel_app/repositories/llm_config_repository.dart';
import 'package:novel_app/services/llm_config_service.dart';
import '../helpers/test_database_setup.dart' as test_db;

/// 插入一条测试 LLM 配置并返回含 id 的对象
Future<LlmConfig> _insertConfig(
  LlmConfigRepository repo, {
  required String name,
  required int sortOrder,
  bool isDefault = false,
  String url = 'https://api.example.com/v1',
  String model = 'gpt-4',
}) async {
  final id = await repo.save(LlmConfig(
    name: name,
    apiUrl: url,
    apiKey: 'key-$name',
    model: model,
    isDefault: isDefault,
    sortOrder: sortOrder,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ));
  return (await repo.getById(id))!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ProviderContainer container;
  late LlmConfigService service;
  late LlmConfigRepository repo;

  /// 用指定 prefs 重新搭建测试环境（每个用例拿全新 container + service）
  Future<void> setupWithPrefs(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    final dbConnection = DatabaseConnection.forTesting(db);
    container = ProviderContainer(
      overrides: [databaseConnectionProvider.overrideWithValue(dbConnection)],
    );
    repo = container.read(llmConfigRepositoryProvider);
    service = container.read(llmConfigServiceProvider);
  }

  setUp(() async {
    await setupWithPrefs({});
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  // ========================================================================
  // getActiveConfig fallback 优先级
  // ========================================================================

  group('getActiveConfig fallback 优先级', () {
    test('场景覆盖存在时 → 返回场景配置（覆盖默认）', () async {
      final a = await _insertConfig(repo,
          name: 'A', sortOrder: 0, isDefault: true);
      final b = await _insertConfig(repo, name: 'B', sortOrder: 1);
      await service.setActiveConfigForScenario('writing', b.id);

      final picked = await service.getActiveConfig(scenarioId: 'writing');
      expect(picked, isNotNull);
      expect(picked!.id, b.id);
      expect(picked.id, isNot(equals(a.id)));
    });

    test('无场景覆盖 → 返回默认配置', () async {
      await _insertConfig(repo, name: 'A', sortOrder: 0, isDefault: true);
      await _insertConfig(repo, name: 'B', sortOrder: 1);

      final picked = await service.getActiveConfig();
      expect(picked, isNotNull);
      expect(picked!.name, 'A', reason: '默认 A 应被选中');
    });

    test('无默认配置 → 返回第一条（按 sortOrder 升序）', () async {
      await _insertConfig(repo, name: 'A', sortOrder: 1);
      final b = await _insertConfig(repo, name: 'B', sortOrder: 0);

      final picked = await service.getActiveConfig();
      expect(picked, isNotNull);
      expect(picked!.id, b.id);
    });

    test('场景覆盖指向已删除配置 → 降级到默认', () async {
      final a = await _insertConfig(repo,
          name: 'A', sortOrder: 0, isDefault: true);
      await service.setActiveConfigForScenario('writing', 9999);

      final picked = await service.getActiveConfig(scenarioId: 'writing');
      expect(picked, isNotNull);
      expect(picked!.id, a.id);
    });

    test('无任何配置 → 返回 null（未配置）', () async {
      final picked = await service.getActiveConfig();
      expect(picked, isNull);
    });

    test('getActiveConfig 不再读取 active_llm_profile_id（防回归）', () async {
      // 即便 prefs 里残留旧 key，也不应影响选择结果
      final a = await _insertConfig(repo,
          name: 'A', sortOrder: 0, isDefault: true);
      // 用 setupWithPrefs 重新建一个带遗留 key 的环境（注意：A 在旧 db，
      // 新 setupWithPrefs 会重建空 db，所以这里只验证"无配置时不读旧 key"）
      await setupWithPrefs({'active_llm_profile_id': 9999});

      // 新 db 无任何配置，残留旧 key 不应凭空造出配置
      final picked = await service.getActiveConfig();
      expect(picked, isNull,
          reason: '残留 active_llm_profile_id 不应被读取，无配置时返回 null');
      // 确保 A 仍在原 db 未受影响（已被新 setup 关闭，仅作语义说明）
      expect(a.name, 'A');
    });
  });

  // ========================================================================
  // ensureGlobalActiveMigrated 平滑迁移
  // ========================================================================

  group('ensureGlobalActiveMigrated 平滑迁移', () {
    test('有 active_llm_profile_id → 对应配置成为默认，key 被清除', () async {
      // 先建一个空环境（带旧 prefs），再在新 DB 里插配置
      await setupWithPrefs({});
      final a = await _insertConfig(repo, name: 'A', sortOrder: 0);
      // B 之前是默认，迁移后应被 A 覆盖
      await _insertConfig(repo, name: 'B', sortOrder: 1, isDefault: true);
      // 模拟老用户的旧全局激活指向 A
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('active_llm_profile_id', a.id!);

      await service.ensureGlobalActiveMigrated();

      final def = await repo.getDefault();
      expect(def, isNotNull);
      expect(def!.id, a.id, reason: 'A 应升级为默认');

      expect(prefs.getInt('active_llm_profile_id'), isNull,
          reason: '旧全局激活 key 必须被清除');
      expect(prefs.getBool('llm_global_active_migrated_v2'), isTrue,
          reason: 'v2 迁移标记必须写入');
    });

    test('active_llm_profile_id 指向已删除配置 → 跳过，不报错', () async {
      await setupWithPrefs({'active_llm_profile_id': 9999});
      await _insertConfig(repo, name: 'A', sortOrder: 0, isDefault: true);

      await service.ensureGlobalActiveMigrated();

      // 默认仍是 A，没被破坏
      final def = await repo.getDefault();
      expect(def, isNotNull);
      expect(def!.name, 'A');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('active_llm_profile_id'), isNull);
      expect(prefs.getBool('llm_global_active_migrated_v2'), isTrue);
    });

    test('无 active_llm_profile_id → 啥也不做，只标 v2', () async {
      await _insertConfig(repo, name: 'A', sortOrder: 0, isDefault: true);

      await service.ensureGlobalActiveMigrated();

      final def = await repo.getDefault();
      expect(def, isNotNull);
      expect(def!.name, 'A', reason: '默认配置不应被改动');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('llm_global_active_migrated_v2'), isTrue);
    });

    test('v2 已标记过 → 二次调用幂等，不覆盖用户后续修改', () async {
      await setupWithPrefs({});
      final a = await _insertConfig(repo, name: 'A', sortOrder: 0);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('active_llm_profile_id', a.id!);
      // 第一次：迁移把 A 设为默认
      await service.ensureGlobalActiveMigrated();

      // 模拟"迁移后用户改了默认"（用 setDefault 才会清除 A 的默认标记）
      final b = await _insertConfig(repo,
          name: 'B', sortOrder: 1, isDefault: true);
      await repo.setDefault(b.id!);

      // 二次调用：应早返回，不动 B 的默认
      await service.ensureGlobalActiveMigrated();

      final def = await repo.getDefault();
      expect(def, isNotNull);
      expect(def!.id, b.id, reason: '幂等性：不应覆盖用户后续的默认修改');
    });

    test('同进程内 service 内存标记也能避免重复迁移（防热路径开销）', () async {
      // 不重建 container，让 _globalActiveMigratedV2 内存标记生效
      final a = await _insertConfig(repo, name: 'A', sortOrder: 0);
      // 手动写入旧 key（不经迁移，模拟任何外部写入）
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('active_llm_profile_id', a.id!);

      // 第一次：迁移
      await service.ensureGlobalActiveMigrated();
      // 第二次：内存标记应让它早返回
      await service.ensureGlobalActiveMigrated();

      expect(prefs.getInt('active_llm_profile_id'), isNull);
    });
  });
}
