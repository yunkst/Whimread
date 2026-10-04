/// LLM Provider 构建服务
///
/// 所有 AI 调用路径（AI Agent）统一通过 [buildActiveProvider] 获取 LLM 通道。
/// LLM 请求只走打包注入的托管后端（`--dart-define=BACKEND_BASE_URL`），
/// 由服务端持有 LLM API Key，客户端不持有任何第三方 Key。
///
/// 「用户自配 AI 供应商」模式已整体移除；本服务还负责一次性擦除旧版本
/// 遗留的自配数据（SQLite `llm_configs` 表 / 安全存储 Key 副本 / prefs 标记），
/// 避免用户付费 Key 残留在设备上。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/backend/backend_config.dart';
import '../core/constants/build_config.dart';
import '../core/providers/database_providers.dart';
import '../core/providers/managed_model_provider.dart';
import '../services/device/device_auth_service.dart';
import '../services/dsl_engine/llm_provider.dart' as llm;
import '../services/logger_service.dart';
import '../services/managed_models/managed_model_service.dart';
import 'ai/ai_service_factory.dart';

class LlmConfigService {
  final Ref _ref;

  /// 自配模式时代的 llm_configs 表（只用于读取遗留行后整表擦除，无写入方）
  static const String _legacyTable = 'llm_configs';

  /// 旧仓储为每行配置在安全存储写的 Key（`llm_api_key_<id>`）
  static const String _legacySecureKeyPrefix = 'llm_api_key_';

  static const String _apiKeysClearedCountKey = 'llm_api_keys_cleared_count';

  /// 自配模式遗留的 SharedPreferences key（迁移标记 / 旧裸 Key / 自部署 Host），
  /// 已无任何读取方，擦除时一并清掉，避免死数据随备份扩散。
  static const List<String> _legacyPrefsKeys = [
    'llm_configs_migrated',
    'active_llm_profile_id',
    'llm_global_active_migrated_v2',
    'dsl_engine_api_url',
    'dsl_engine_api_key',
    'dsl_engine_model',
    'backend_host',
  ];

  /// 场景级覆盖 key（`active_llm_profile_<scenarioId>`）与旧场景裸 Key 的前缀
  static const String _legacyScenarioProfilePrefix = 'active_llm_profile_';
  static const List<String> _legacyScenarioOverridePrefixes = [
    'agent_agent_writing_scenario_',
    'agent_agent_webview_extract_scenario_',
  ];

  /// AI 服务不可用错误消息（AgentErrorEvent / Exception 共用）
  static const String unavailableMessage = 'AI 服务暂时不可用，请稍后重试';

  /// API Key 安全存储（沿用旧仓储的 Key 规则，用于擦除遗留副本）
  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// 擦除检查的内存幂等标记，避免热路径重复读 SharedPreferences
  bool _legacyDataClearedChecked = false;

  LlmConfigService(this._ref);

  /// 构建 Whimread 托管后端代理的 LlmProvider。
  ///
  /// 所有 LLM 请求走 CloudBase `llm-proxy` 函数（`/v1/chat/completions`），
  /// 由服务端持有 LLM API Key 并转发到真实 LLM 供应商。客户端只用设备 JWT
  /// 鉴权，**不持有任何 LLM Key**。模型字段由用户在设置中选择（若未选 /
  /// 目录未知则不发 model 字段，服务端落回 baseline）。
  ///
  /// [scenarioId] 仅用于缓存绑定场景（当前各场景共用同一后端配置）。
  /// 返回 null 表示当前构建未注入托管后端（开发态），调用方按不可用处理。
  Future<llm.LlmProvider?> buildManagedProvider(String scenarioId) async {
    if (!kHasBundledBackend) return null;
    final baseHost = await resolveBackendHost();
    if (baseHost.isEmpty) return null;
    final token = await DeviceAuthService.instance.ensureRegistered();
    // 用户选择的模型:复用 managedModelProvider 的 5min 内存缓存,
    // 避免每个 Agent 消息都触发一次 /v1/models 网络往返 + SharedPreferences 读。
    // refresh() 内部走 isFresh 守卫;catalog 为 null 时 resolveForRequest
    // 会回退到 state.selectedModelId → 网络失败时的本地兜底。
    final notifier = _ref.read(managedModelProvider.notifier);
    await notifier.refresh();
    final modelState = _ref.read(managedModelProvider);
    final modelId = ManagedModelService.instance.resolveForRequest(
      catalog: modelState.catalog,
      selectedId: modelState.selectedModelId,
    );
    return AiServiceFactory.buildLlmProvider(
      llm.LlmConfig(
        baseUrl: '$baseHost/v1',
        apiKey: token,                        // ⚠️ 这里传的是设备 JWT,不是 LLM Key
        defaultModel: modelId ?? '',         // 空 → LlmProvider 不发 model 字段
      ),
    );
  }

  /// 构建当前生效的 [llm.LlmProvider]（内部先确保遗留自配数据已擦除）。
  ///
  /// 返回 null 表示 AI 服务不可用（未注入托管后端 / Host 解析失败），
  /// 调用方各自决定报错形态。
  Future<llm.LlmProvider?> buildActiveProvider(String scenarioId) async {
    await ensureLegacyDataWipedForManaged();
    return buildManagedProvider(scenarioId);
  }

  // ── 自配模式遗留数据一次性擦除 ──

  /// 托管模式下一次性清除自配模式遗留数据（幂等，只跑一次）。
  ///
  /// 客户端已全面切换托管后端，不再需要任何第三方 LLM Key；为避免用户
  /// 付费 Key 以明文/安全存储副本残留在设备上，首次构建 Provider 时
  /// 擦除 `llm_configs` 表与相关 prefs，并记录清除条数。
  ///
  /// 未打包托管后端（开发构建）不触碰数据，直接返回 0。
  Future<int> ensureLegacyDataWipedForManaged() async {
    if (!kHasBundledBackend) return 0;
    if (_legacyDataClearedChecked) return 0;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt(_apiKeysClearedCountKey) != null) {
      _legacyDataClearedChecked = true;
      return 0;
    }

    final cleared = await wipeLegacyLlmData(prefs);
    await prefs.setInt(_apiKeysClearedCountKey, cleared);
    _legacyDataClearedChecked = true;
    LoggerService.instance.i(
      '自配模式遗留数据擦除完成: $cleared 条配置',
      category: LogCategory.ai,
      tags: ['llm_config', 'managed', 'legacy_wiped'],
    );
    return cleared;
  }

  /// 擦除自配模式遗留数据：
  /// 1. `llm_configs` 整表删除（先按行删除安全存储里的 Key 副本）
  /// 2. 自配模式的遗留 prefs key（迁移标记 / 场景覆盖 / 旧裸 Key / 自部署 Host）
  ///
  /// 公开以便单测直接注入 prefs 验证；生产路径只经
  /// [ensureLegacyDataWipedForManaged] 调用一次。返回本次删除的配置行数。
  Future<int> wipeLegacyLlmData(SharedPreferences prefs) async {
    var cleared = 0;
    try {
      final db = await _ref.read(databaseConnectionProvider).database;
      final rows = await db.query(_legacyTable, columns: ['id']);
      for (final row in rows) {
        final id = row['id'] as int?;
        if (id == null) continue;
        try {
          await _secure.delete(key: '$_legacySecureKeyPrefix$id');
        } catch (_) {/* 安全存储不可用（如测试环境）：忽略 */}
      }
      cleared = await db.delete(_legacyTable);
    } catch (e) {
      LoggerService.instance.w('遗留 LLM 配置擦除失败: $e',
          category: LogCategory.ai,
          tags: ['llm_config', 'legacy_wipe_failed']);
    }

    try {
      for (final key in prefs.getKeys()) {
        if (key.startsWith(_legacyScenarioProfilePrefix) ||
            _legacyScenarioOverridePrefixes.any(key.startsWith)) {
          await prefs.remove(key);
        }
      }
      for (final key in _legacyPrefsKeys) {
        await prefs.remove(key);
      }
    } catch (_) {/* prefs 异常不阻断主流程 */}

    return cleared;
  }
}
