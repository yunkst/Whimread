/// LLM 配置「复制」功能回归测试 — 真实内存 SQLite
///
/// 回归场景：历史上 `_duplicateConfig` 用 `config.copyWith(id: null, ...)` 生成副本，
/// 但 copyWith 的可空字段用 `id ?? this.id`，传 null 会沿用原 id。于是 save() 走 update
/// 分支，复制操作实际把原配置覆盖了（名字变 "xx (副本)"、默认状态被抹掉、无新行）。
///
/// 本测试模拟屏幕里的复制流程（service.saveConfig(original.duplicate())），断言：
/// 1. 表里确实多出一条记录
/// 2. 原配置的 name / isDefault 完全不变
/// 3. 副本的 id 与原配置不同、name 含 "(副本)"、isDefault=false
///
/// 运行:
///   cd novel_app
///   flutter test test/bug/llm_config_duplicate_test.dart
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ProviderContainer container;
  late LlmConfigService service;
  late LlmConfigRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    final dbConnection = DatabaseConnection.forTesting(db);
    container = ProviderContainer(
      overrides: [databaseConnectionProvider.overrideWithValue(dbConnection)],
    );
    repo = container.read(llmConfigRepositoryProvider);
    service = container.read(llmConfigServiceProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// 插入一条带 id 的配置，模拟「已存在的原配置」
  Future<LlmConfig> insertOne({
    required String name,
    bool isDefault = false,
    int sortOrder = 0,
  }) async {
    final now = DateTime.now();
    final id = await repo.save(LlmConfig(
      name: name,
      apiUrl: 'https://api.example.com/v1',
      apiKey: 'sk-$name',
      model: 'gpt-4',
      isDefault: isDefault,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    ));
    return (await repo.getById(id))!;
  }

  group('复制功能', () {
    test('复制应新增一条记录，且原配置（非默认）完全不变', () async {
      final original = await insertOne(name: 'OpenAI');

      // 模拟屏幕 _duplicateConfig 的核心：duplicate() + saveConfig()
      await service.saveConfig(original.duplicate());

      final all = await repo.getAll();
      expect(all, hasLength(2), reason: '应新增一条，而非覆盖原行');

      // 原行未被动过
      final reloadedOriginal = await repo.getById(original.id!);
      expect(reloadedOriginal!.name, 'OpenAI', reason: '原配置名字不能被改成 (副本)');
      expect(reloadedOriginal.apiKey, 'sk-OpenAI');

      // 副本正确
      final copy = all.firstWhere((c) => c.id != original.id);
      expect(copy.name, 'OpenAI (副本)');
      expect(copy.apiKey, 'sk-OpenAI', reason: '副本继承连接信息');
      expect(copy.isDefault, isFalse);
    });

    test('复制默认配置时，原配置保持默认、副本非默认', () async {
      final original = await insertOne(name: 'DeepSeek', isDefault: true);

      await service.saveConfig(original.duplicate());

      final all = await repo.getAll();
      expect(all, hasLength(2));

      // 原配置仍是默认 —— 这是 bug 修复的关键断言（旧实现会把原默认抹成 false）
      final reloadedOriginal = await repo.getById(original.id!);
      expect(reloadedOriginal!.isDefault, isTrue,
          reason: '复制默认配置时，原配置的默认状态不能被抹掉');
      expect(reloadedOriginal.name, 'DeepSeek',
          reason: '原配置名字不能被改成 (副本)');

      // 副本非默认，避免出现两个默认
      final copy = all.firstWhere((c) => c.id != original.id);
      expect(copy.isDefault, isFalse);
      expect(copy.name, 'DeepSeek (副本)');

      // 表里全局只有一个默认
      final defaults = all.where((c) => c.isDefault).toList();
      expect(defaults, hasLength(1));
      expect(defaults.first.id, original.id);
    });

    test('连续复制两次得到三条独立记录', () async {
      final original = await insertOne(name: 'Claude');

      await service.saveConfig(original.duplicate());
      await service.saveConfig(original.duplicate());

      final all = await repo.getAll();
      expect(all, hasLength(3), reason: '每次复制都应新增一条，不能互相覆盖');
      expect(all.where((c) => c.name == 'Claude'), hasLength(1));
      expect(all.where((c) => c.name == 'Claude (副本)'), hasLength(2));
    });
  });
}
