/// LLM 配置服务
///
/// 统一管理 LLM 配置序列的读取、切换和迁移。
/// 所有 AI 调用路径（AI Agent）都通过此服务获取 LLM 配置。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/build_config.dart';
import '../core/providers/database_providers.dart';
import '../models/llm_config.dart' as app;
import '../services/device/device_auth_service.dart';
import '../services/dsl_engine/llm_provider.dart' as llm;
import '../services/logger_service.dart';
import '../services/managed_models/managed_model_service.dart';
import 'ai/ai_service_factory.dart';

class LlmConfigService {
  final Ref _ref;

  static const String _activeProfileKey = 'active_llm_profile_id'; // 仅迁移用，不再作为运行时 fallback
  static const String _migratedKey = 'llm_configs_migrated';
  static const String _scenarioPrefix = 'active_llm_profile_';
  static const String _globalActiveMigratedV2Key = 'llm_global_active_migrated_v2';
  static const String _apiKeysClearedCountKey = 'llm_api_keys_cleared_count';

  /// 统一未配置错误消息（AgentErrorEvent / Exception 共用）
  static const String notConfiguredMessage =
      '请先在设置中配置 LLM（添加至少一个配置）';

  /// 全局激活 → 默认 迁移的内存标记，避免热路径重复读 SharedPreferences
  bool _migrationChecked = false;
  bool _globalActiveMigratedV2 = false;
  bool _apiKeysClearedChecked = false;

  LlmConfigService(this._ref);

  // ── 查询 ──

  /// 获取所有配置
  Future<List<app.LlmConfig>> getAllConfigs() async {
    final repo = _ref.read(llmConfigRepositoryProvider);
    return repo.getAll();
  }

  /// 获取当前激活的配置（场景级 → 默认 → 第一条）
  ///
  /// 全局激活层已删除：场景级覆盖最高，兜底用 DB 中标记为默认的配置。
  Future<app.LlmConfig?> getActiveConfig({String? scenarioId}) async {
    final repo = _ref.read(llmConfigRepositoryProvider);
    final prefs = await SharedPreferences.getInstance();

    // 1. 场景级配置
    if (scenarioId != null) {
      final scenarioProfileId =
          prefs.getInt('$_scenarioPrefix$scenarioId');
      if (scenarioProfileId != null) {
        final config = await repo.getById(scenarioProfileId);
        if (config != null) return config;
      }
    }

    // 2. 默认配置
    final defaultConfig = await repo.getDefault();
    if (defaultConfig != null) return defaultConfig;

    // 3. 第一条配置
    final all = await repo.getAll();
    return all.isNotEmpty ? all.first : null;
  }

  /// 获取默认配置 ID
  Future<int?> getDefaultConfigId() async {
    final repo = _ref.read(llmConfigRepositoryProvider);
    final config = await repo.getDefault();
    return config?.id;
  }

  // ── 设置激活 ──

  /// 全局激活机制已删除：默认配置由 setDefault() 管理，场景覆盖由
  /// setActiveConfigForScenario() 管理。旧用户数据通过
  /// [ensureGlobalActiveMigrated] 一次性迁移到默认配置。

  /// 设置场景级激活配置（configId 为 null 时清除场景覆盖）
  Future<void> setActiveConfigForScenario(
      String scenarioId, int? configId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_scenarioPrefix$scenarioId';
    if (configId != null) {
      await prefs.setInt(key, configId);
    } else {
      await prefs.remove(key);
    }
    LoggerService.instance.i(
        '场景 $scenarioId 激活 LLM 配置: id=$configId',
        category: LogCategory.ai,
        tags: ['llm_config', 'set_active_scenario']);
  }

  // ── 构建 LlmProvider 配置 ──

  /// 将 LlmConfig 转换为 LlmProvider 的 LlmConfig
  ///
  /// 注意：这是 app 层 → DSL 层的字段映射，两边的字段清单必须人工同步；
  /// app 层新增字段（如未来加 temperature）后要在这里显式转发，否则会被静默丢弃。
  llm.LlmConfig buildLlmProviderConfig(app.LlmConfig config) {
    return llm.LlmConfig(
      baseUrl: config.apiUrl,
      apiKey: config.apiKey,
      defaultModel: config.model,
    );
  }

  /// 构建 Whimread 托管后端代理的 LlmProvider。
  ///
  /// **AI 托管模式(打包注入 BACKEND_BASE_URL)**:所有 LLM 请求走 CloudBase
  /// `llm-proxy` 函数(`/v1/chat/completions`),由服务端持有 LLM API Key 并转发
  /// 到真实 LLM 供应商(DeepSeek/OpenAI/GLM/Kimi/Claude)。客户端只用设备 JWT
  /// 鉴权,**不持有任何 LLM Key**。模型字段由用户在设置中选择(若未选 / 目录
  /// 未知则不发 model 字段,服务端落回 baseline)。
  ///
  /// [scenarioId] 仅用于缓存绑定场景(当前各场景共用同一后端配置)。
  Future<llm.LlmProvider?> buildManagedProvider(String scenarioId) async {
    if (!kHasBundledBackend) return null; // 未注入托管后端 → 走旧用户自配路径
    final token = await DeviceAuthService.instance.ensureRegistered();
    // 用户选择的模型(可能为 null):拉一次目录 + 读选择,组合出真实请求字段。
    // 失败(目录未知) → 直接信任本地选择;选择不存在于目录 → 落回 baseline。
    final svc = ManagedModelService.instance;
    final catalog = await svc.fetchCatalog();
    final selectedId = await svc.getSelectedModelId();
    final modelId = svc.resolveForRequest(
      catalog: catalog,
      selectedId: selectedId,
    );
    return AiServiceFactory.buildLlmProvider(
      llm.LlmConfig(
        baseUrl: '$kBackendBaseUrl/v1',
        apiKey: token,                        // ⚠️ 这里传的是设备 JWT,不是 LLM Key
        defaultModel: modelId ?? '',         // 空 → LlmProvider 不发 model 字段
      ),
    );
  }

  /// 解析场景激活配置并构建 [llm.LlmProvider]（内部先确保旧配置迁移）。
  ///
  /// AI 托管模式（打包注入 BACKEND_BASE_URL）：返回托管代理 Provider，
  /// 与用户自配完全解耦。未注入托管后端时回退旧路径（自部署场景），
  /// 返回 null 表示没有激活配置，调用方各自决定报错形态。
  Future<llm.LlmProvider?> buildActiveProvider(String scenarioId) async {
    await ensureMigratedFromLegacy();
    await ensureGlobalActiveMigrated();
    await ensureApiKeysClearedForManaged();

    // AI 托管模式：托管后端代理是唯一 AI 通道
    final managed = await buildManagedProvider(scenarioId);
    if (managed != null) return managed;

    final activeConfig = await getActiveConfig(scenarioId: scenarioId);
    if (activeConfig == null) return null;
    return AiServiceFactory.buildLlmProvider(
        buildLlmProviderConfig(activeConfig));
  }

  // ── CRUD 委托 ──

  Future<int> saveConfig(app.LlmConfig config) async {
    final repo = _ref.read(llmConfigRepositoryProvider);
    final id = await repo.save(config);

    // 标记为默认，或新建了表里的唯一一条配置时，保证存在默认
    if (config.isDefault || (config.id == null && await repo.count() == 1)) {
      await repo.setDefault(id);
    }
    return id;
  }

  Future<void> deleteConfig(int id) async {
    final repo = _ref.read(llmConfigRepositoryProvider);
    await repo.delete(id);
    // 删除后若仍有配置但无默认，挑第一条补为默认，保证「有配置必有默认」不变量
    // （与 saveConfig 新建唯一配置时自动设默认对称）
    final defaultConfig = await repo.getDefault();
    if (defaultConfig == null) {
      final all = await repo.getAll();
      if (all.isNotEmpty) {
        await repo.setDefault(all.first.id!);
      }
    }
  }

  Future<void> setDefault(int id) async {
    final repo = _ref.read(llmConfigRepositoryProvider);
    await repo.setDefault(id);
  }

  // ── 旧配置迁移 ──

  /// 首次运行时从旧 SharedPreferences 裸 key 迁移数据到 llm_configs 表
  ///
  /// 迁移逻辑：
  /// 1. 检查 _migratedKey 是否已标记
  /// 2. 读取旧 dsl_engine_* SharedPreferences 裸 key（apiUrl/apiKey/model）
  /// 3. 如果有有效数据，创建一条默认配置
  /// 4. 遍历 agent_*_scenario SharedPreferences 裸 key，为每个有覆盖的场景创建配置
  /// 5. 标记迁移完成
  Future<void> ensureMigratedFromLegacy() async {
    // 内存缓存：迁移检查只执行一次
    if (_migrationChecked) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migratedKey) == true) {
      _migrationChecked = true;
      return;
    }

    LoggerService.instance.i('开始从旧配置迁移到 llm_configs 表...',
        category: LogCategory.ai, tags: ['llm_config', 'migration']);

    final repo = _ref.read(llmConfigRepositoryProvider);

    // 读取旧全局配置
    final apiUrl = prefs.getString('dsl_engine_api_url') ?? '';
    final apiKey = prefs.getString('dsl_engine_api_key') ?? '';
    final model = prefs.getString('dsl_engine_model') ?? '';

    if (apiUrl.isNotEmpty && apiKey.isNotEmpty) {
      final now = DateTime.now();
      final id = await repo.save(app.LlmConfig(
        name: '默认配置',
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        isDefault: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ));
      await repo.setDefault(id);
      LoggerService.instance.i('迁移旧全局配置到 id=$id',
          category: LogCategory.ai,
          tags: ['llm_config', 'migration', 'global']);
    }

    // 迁移 Agent 场景级覆盖
    final scenarioKeys = [
      'agent_writing_scenario',
      'agent_webview_extract_scenario',
    ];
    for (int i = 0; i < scenarioKeys.length; i++) {
      final scenarioId = scenarioKeys[i];
      final sApiUrl = prefs.getString('agent_${scenarioId}_api_url') ?? '';
      final sApiKey = prefs.getString('agent_${scenarioId}_api_key') ?? '';
      final sModel = prefs.getString('agent_${scenarioId}_model') ?? '';

      if (sApiUrl.isNotEmpty && sApiKey.isNotEmpty) {
        final now = DateTime.now();
        final id = await repo.save(app.LlmConfig(
          name: '场景-${scenarioId.replaceAll('_', ' ')}',
          apiUrl: sApiUrl,
          apiKey: sApiKey,
          model: sModel,
          isDefault: false,
          sortOrder: i + 1,
          createdAt: now,
          updatedAt: now,
        ));
        // 设置场景激活
        await setActiveConfigForScenario(scenarioId, id);
        LoggerService.instance.i('迁移场景 $scenarioId 配置到 id=$id',
            category: LogCategory.ai,
            tags: ['llm_config', 'migration', 'scenario']);
      }
    }

    // 标记迁移完成
    await prefs.setBool(_migratedKey, true);
    _migrationChecked = true;
    LoggerService.instance.i('旧配置迁移完成',
        category: LogCategory.ai, tags: ['llm_config', 'migration', 'done']);
  }

  /// 将旧「全局激活」（prefs `active_llm_profile_id`）一次性迁移为「默认配置」。
  ///
  /// 删除全局激活层后，老用户原先通过 setActiveConfig 选中的供应商若不迁移，
  /// 升级后会跳变到 DB 默认。本方法把全局激活指向的配置设为默认，保证用户感知不变。
  /// 幂等：用内存标记 + prefs 标记双保险，只跑一次。配置已被删除则跳过。
  Future<void> ensureGlobalActiveMigrated() async {
    if (_globalActiveMigratedV2) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_globalActiveMigratedV2Key) == true) {
      _globalActiveMigratedV2 = true;
      return;
    }

    final repo = _ref.read(llmConfigRepositoryProvider);
    final legacyActiveId = prefs.getInt(_activeProfileKey);
    if (legacyActiveId != null) {
      final config = await repo.getById(legacyActiveId);
      if (config != null) {
        await repo.setDefault(legacyActiveId);
        LoggerService.instance.i(
            '全局激活 → 默认 迁移: id=$legacyActiveId',
            category: LogCategory.ai,
            tags: ['llm_config', 'migration', 'global_active_v2']);
      }
      await prefs.remove(_activeProfileKey);
    }

    await prefs.setBool(_globalActiveMigratedV2Key, true);
    _globalActiveMigratedV2 = true;
  }

  // ── 托管模式安全清除 ──

  /// AI 托管模式下清空本地自配 LLM 配置的 API Key（幂等，只跑一次）。
  ///
  /// 客户端切换到托管后端后不再需要任何第三方 LLM Key；为避免用户付费 Key
  /// 以明文残留在 SQLite 中，在首次构建 Provider 或打开场景配置对话框时
  /// 将 `llm_configs.api_key` 全部置空，仅保留 name/api_url/model 元数据。
  ///
  /// 未打包托管后端（自部署场景）不触碰用户数据，直接返回 0。
  /// 返回本次实际清除的配置条数；已清除过则返回 0。
  Future<int> ensureApiKeysClearedForManaged() async {
    if (!kHasBundledBackend) return 0;
    if (_apiKeysClearedChecked) return 0;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt(_apiKeysClearedCountKey) != null) {
      _apiKeysClearedChecked = true;
      return 0;
    }

    final cleared = await _ref.read(llmConfigRepositoryProvider).clearAllApiKeys();
    await prefs.setInt(_apiKeysClearedCountKey, cleared);
    _apiKeysClearedChecked = true;
    LoggerService.instance.i(
      '托管模式 API Key 清除完成: $cleared 条',
      category: LogCategory.ai,
      tags: ['llm_config', 'managed', 'api_key_cleared'],
    );
    return cleared;
  }

  /// 读取历史清除记录（`llm_api_keys_cleared_count`），供 UI 提示展示。
  ///
  /// 从未执行过清除（非托管包）时返回 null。
  Future<int?> getApiKeysClearedCount() async {
    if (!kHasBundledBackend) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_apiKeysClearedCountKey);
  }
}
