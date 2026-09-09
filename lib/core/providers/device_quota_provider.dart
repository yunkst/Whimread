/// 设备额度状态 Provider
///
/// 消费方：Agent Chat 顶部 QuotaBadge、设置页「设备额度」条目。
/// 60s 内存缓存（额度只在 LLM 调用后变化，高频轮询无意义）；
/// UI 关键时机（打开对话框、发消息后）可 `refresh(force: true)` 拉新。
///
/// `info == null` 表示额度不可知：非托管包（kHasBundledBackend=false）、
/// 设备尚未注册（fetchQuota 有意不触发注册副作用）、或查询失败。
/// UI 对 null 的统一处理是隐藏入口，不打扰用户。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/device/device_auth_service.dart';

class DeviceQuotaState {
  /// 当前余额；null = 不可知（见文件头注释）
  final DeviceQuotaInfo? info;

  /// 最近一次成功拉取时间；缓存 TTL 判定用
  final DateTime? fetchedAt;

  /// 是否正在拉取
  final bool loading;

  const DeviceQuotaState({this.info, this.fetchedAt, this.loading = false});

  bool get isFresh =>
      info != null &&
      fetchedAt != null &&
      DateTime.now().difference(fetchedAt!) < quotaCacheTtl;
}

/// 缓存有效期。额度只在 LLM 调用后变化（每 1000 token 扣 1 点），
/// 60s 足以让同一次对话内的重复打开不重复打请求。
const Duration quotaCacheTtl = Duration(seconds: 60);

class DeviceQuotaNotifier extends StateNotifier<DeviceQuotaState> {
  DeviceQuotaNotifier() : super(const DeviceQuotaState());

  /// 拉取额度。缓存未过期且非强制时跳过；拉取失败静默保持旧值
  /// （fetchQuota 内部已兜底返回 null，仅记日志）。
  Future<void> refresh({bool force = false}) async {
    if (state.loading) return;
    if (!force && state.isFresh) return;
    state = DeviceQuotaState(
      info: state.info,
      fetchedAt: state.fetchedAt,
      loading: true,
    );
    final info = await DeviceAuthService.instance.fetchQuota();
    if (!mounted) return;
    // 失败（null）时保留旧余额展示，只刷新时间戳推进 TTL，避免每次
    // build 都重打一个注定失败的请求
    state = DeviceQuotaState(
      info: info ?? state.info,
      fetchedAt: DateTime.now(),
    );
  }
}

final deviceQuotaProvider =
    StateNotifierProvider<DeviceQuotaNotifier, DeviceQuotaState>(
  (ref) => DeviceQuotaNotifier(),
);
