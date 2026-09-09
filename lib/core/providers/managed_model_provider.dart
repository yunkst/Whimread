/// 托管模式模型目录 Provider
///
/// 数据源 [ManagedModelService]:
///   - 目录:`GET /v1/models`(无鉴权,失败兜底 null)
///   - 选中:SharedPreferences `managed_model_selection`
///
/// 60s 缓存(目录变更频率低,切换场景期间不应重复打请求);
/// UI 关键时机(`ManagedModelPickerScreen` 打开后、下拉刷新)可
/// `refresh(force: true)` 拉新。
///
/// `catalog == null && selectedModelId == null` 表示「未配置托管后端 /
/// 拉取失败 / 未注册」,UI 应隐藏入口或展示「暂不可用」态。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/managed_models/managed_model_service.dart';

class ManagedModelState {
  /// 当前拉到的目录(可能为 null)
  final ManagedModelCatalog? catalog;

  /// 用户持久化的选中 id(可能为 null)
  final String? selectedModelId;

  /// 最近一次成功拉取目录的时间;缓存 TTL 判定用
  final DateTime? fetchedAt;

  /// 是否正在拉取
  final bool loading;

  const ManagedModelState({
    this.catalog,
    this.selectedModelId,
    this.fetchedAt,
    this.loading = false,
  });

  bool get isFresh =>
      catalog != null &&
      fetchedAt != null &&
      DateTime.now().difference(fetchedAt!) < managedModelCacheTtl;

  /// copyWith 默认不重置 loading(true 时显式关闭);避免每次刷新写两行 state=。
  ManagedModelState copyWith({
    ManagedModelCatalog? catalog,
    String? selectedModelId,
    DateTime? fetchedAt,
    bool? loading,
    bool clearLoading = false,
  }) {
    return ManagedModelState(
      catalog: catalog ?? this.catalog,
      selectedModelId: selectedModelId ?? this.selectedModelId,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      loading: clearLoading ? false : (loading ?? this.loading),
    );
  }
}

const Duration managedModelCacheTtl = Duration(minutes: 5);

class ManagedModelNotifier extends StateNotifier<ManagedModelState> {
  ManagedModelNotifier() : super(const ManagedModelState());

  /// 拉取目录 + 读最新选择。缓存未过期且非强制时跳过;
  /// 拉取失败保留旧值。
  Future<void> refresh({bool force = false}) async {
    if (state.loading) return;
    if (!force && state.isFresh) return;
    state = state.copyWith(loading: true);
    final svc = ManagedModelService.instance;
    final results = await Future.wait([
      svc.fetchCatalog(),
      svc.getSelectedModelId(),
    ]);
    final catalog = results[0] as ManagedModelCatalog?;
    final selectedId = results[1] as String?;
    if (!mounted) return;
    state = state.copyWith(
      catalog: catalog ?? state.catalog,
      selectedModelId: selectedId ?? state.selectedModelId,
      fetchedAt: DateTime.now(),
      clearLoading: true,
    );
  }

  /// 用户在 picker 选中一个新模型。
  Future<void> select(String modelId) async {
    await ManagedModelService.instance.setSelectedModelId(modelId);
    state = state.copyWith(selectedModelId: modelId);
  }
}

final managedModelProvider =
    StateNotifierProvider<ManagedModelNotifier, ManagedModelState>(
  (ref) => ManagedModelNotifier(),
);