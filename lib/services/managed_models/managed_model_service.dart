/// 托管模式 LLM 模型目录
///
/// 数据源:GET {BACKEND_BASE_URL}/v1/models(公开端点,无需鉴权)。
/// 后端契约见 `cloudfunctions/llm-proxy/model-catalog.js#catalogToResponse`。
///
/// 选中的模型通过 `managed_model_selection` SharedPreferences key 持久化
/// (单值,适用于所有 Agent 场景;各场景独立选择在 LlmConfigService 那边另议)。
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/build_config.dart';
import '../api_service_wrapper.dart';
import '../logger_service.dart';
import '../preferences_service.dart';

/// 目录中单个条目(展示用)
class ManagedModel {
  final String id;
  final String displayName;
  final String? shortName;
  final double consumptionRate;
  final bool isBaseline;
  final String? description;

  const ManagedModel({
    required this.id,
    required this.displayName,
    this.shortName,
    required this.consumptionRate,
    required this.isBaseline,
    this.description,
  });

  /// 展示用简称(短称优先,否则用 displayName)
  String get shortLabel => (shortName != null && shortName!.isNotEmpty)
      ? shortName!
      : displayName;

  /// 倍率显示文本(整数去小数)
  String get rateText {
    if (consumptionRate == consumptionRate.truncateToDouble()) {
      return consumptionRate.toInt().toString();
    }
    return consumptionRate.toString();
  }

  @override
  String toString() =>
      'ManagedModel(id=$id, display=$displayName, rate=$consumptionRate, '
      'baseline=$isBaseline)';
}

/// 模型目录(单次拉取的整组)
class ManagedModelCatalog {
  final List<ManagedModel> models;
  final String baselineModelId;

  const ManagedModelCatalog({required this.models, required this.baselineModelId});

  ManagedModel? byId(String id) {
    for (final m in models) {
      if (m.id == id) return m;
    }
    return null;
  }

  ManagedModel? get baseline =>
      models.where((m) => m.isBaseline).cast<ManagedModel?>().firstWhere(
            (m) => m != null,
            orElse: () => null,
          );

  /// 后端 `data[0]` 即 baseline(ratio=1,最便宜)
  /// —— 该约定由 `cloudfunctions/llm-proxy/model-catalog.js` 保证
  ManagedModel? get defaultModel =>
      baseline ?? (models.isNotEmpty ? models.first : null);

  /// 解析 /v1/models 响应;字段缺失 / 类型错 → 抛 [FormatException]
  @visibleForTesting
  static ManagedModelCatalog parse(dynamic data) {
    if (data is! Map) {
      throw const FormatException('catalog response is not an object');
    }
    final rawList = data['data'];
    if (rawList is! List) {
      throw const FormatException('catalog.data missing');
    }
    final models = <ManagedModel>[];
    for (final raw in rawList) {
      if (raw is! Map) continue;
      final idRaw = raw['id'];
      if (idRaw is! String) continue;
      final id = idRaw.trim();
      if (id.isEmpty) continue;
      final rate = raw['consumption_rate'];
      if (rate is! num || rate <= 0) continue;
      models.add(ManagedModel(
        id: id,
        displayName:
            (raw['display_name'] as String?)?.trim().isNotEmpty == true
                ? (raw['display_name'] as String).trim()
                : id,
        shortName: (raw['short_name'] as String?)?.trim().isNotEmpty == true
            ? (raw['short_name'] as String).trim()
            : null,
        consumptionRate: rate.toDouble(),
        isBaseline: raw['is_baseline'] == true,
        description: (raw['description'] as String?)?.trim().isNotEmpty == true
            ? (raw['description'] as String).trim()
            : null,
      ));
    }
    final baselineRaw = data['baseline_model_id'];
    final baselineId = (baselineRaw is String && baselineRaw.isNotEmpty)
        ? baselineRaw
        : (models.where((m) => m.isBaseline).cast<ManagedModel?>().firstWhere(
              (m) => m != null,
              orElse: () => null,
            )?.id) ??
            (models.isNotEmpty ? models.first.id : null);
    if (baselineId == null || models.isEmpty) {
      throw const FormatException('catalog empty or baseline missing');
    }
    // 校正 baseline 标记(后端兜底)
    final fixed = models
        .map((m) => ManagedModel(
              id: m.id,
              displayName: m.displayName,
              shortName: m.shortName,
              consumptionRate: m.consumptionRate,
              isBaseline: m.id == baselineId,
              description: m.description,
            ))
        .toList();
    return ManagedModelCatalog(models: fixed, baselineModelId: baselineId);
  }

  /// 「消耗速度与基准相当 / 是 Flash 的 5 倍」类文案。
  /// 不展示「1 点 = N token」这类直白价格,以 baseline 短称为参考点。
  String rateLabel(ManagedModel model) {
    if (model.isBaseline) return '基准速度 · 消耗最慢';
    final base = baseline;
    final refName = (base != null && base.shortLabel.isNotEmpty)
        ? base.shortLabel
        : '基准';
    final rate = model.consumptionRate;
    final rateStr = rate == rate.truncateToDouble()
        ? rate.toInt().toString()
        : rate.toString();
    return '消耗速度约是$refName 的 $rateStr 倍';
  }
}

/// 托管模式模型服务
///
/// - [fetchCatalog] 拉取后端 /v1/models(无鉴权,失败返回 null)
/// - [getSelectedModelId] / [setSelectedModelId] 持久化用户选择
/// - [resolveForRequest] 把选择落到实际请求字段(null = 不发送 model 字段,
///   让后端用 baseline)
class ManagedModelService {
  ManagedModelService._();

  static final ManagedModelService instance = ManagedModelService._();

  /// 单测/特殊场景注入自定义 wrapper
  ApiServiceWrapper? _apiOverride;
  @visibleForTesting
  void useApiWrapper(ApiServiceWrapper wrapper) => _apiOverride = wrapper;
  ApiServiceWrapper get _api => _apiOverride ?? ApiServiceWrapper();

  static const String _kSelectedKey = 'managed_model_selection';

  // ── 网络 ──────────────────────────────────────────────

  /// 拉取 /v1/models;返回 null 表示「不可用」(非托管包、网络错、目录关闭)。
  /// 网络异常被吞掉(走 fallback 默认 baseline),只记日志。
  Future<ManagedModelCatalog?> fetchCatalog() async {
    if (!kHasBundledBackend) return null;
    try {
      final resp = await _api.dio.get(
        '/v1/models',
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final data = resp.data;
      if (data is! Map) return null;
      // 503 等服务端错误体:{"code":"MODEL_CATALOG_NOT_CONFIGURED",...}
      if (data.containsKey('code')) return null;
      return ManagedModelCatalog.parse(data);
    } catch (e, st) {
      LoggerService.instance.w(
        '拉取托管模型目录失败（不影响使用）: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['managed_model', 'catalog', 'fetch_failed'],
      );
      return null;
    }
  }

  // ── 选中持久化 ────────────────────────────────────────

  Future<String?> getSelectedModelId() async {
    final v = await PreferencesService.instance
        .getString(_kSelectedKey, defaultValue: '');
    return v.isEmpty ? null : v;
  }

  Future<void> setSelectedModelId(String? modelId) async {
    if (modelId == null || modelId.isEmpty) {
      await PreferencesService.instance.remove(_kSelectedKey);
    } else {
      await PreferencesService.instance.setString(_kSelectedKey, modelId);
    }
  }

  /// 把当前选择 + 已拉目录合成一个可用于 LlmConfig.defaultModel 的 id。
  /// 选中不在目录 → 兜底 baseline(null → 由后端决定,这里返回 null 表示不传)。
  String? resolveForRequest({
    required ManagedModelCatalog? catalog,
    required String? selectedId,
  }) {
    if (catalog == null) return selectedId; // 目录未知,信任本地选择
    if (selectedId == null) return catalog.defaultModel?.id;
    final hit = catalog.byId(selectedId);
    if (hit != null) return hit.id;
    return catalog.defaultModel?.id;
  }
}