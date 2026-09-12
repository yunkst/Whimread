/// 设备额度状态 Provider
///
/// 消费方：Agent Chat 顶部 QuotaBadge、设置页「设备额度」条目、
/// 模型选择页额度卡片。
/// 60s 内存缓存（额度只在 LLM 调用后变化，高频轮询无意义）；
/// UI 关键时机（打开对话框、发消息后）可 `refresh(force: true)` 拉新；
/// **所有 AI 使用后的自动刷新**走 [DeviceQuotaNotifier.onAiUsage]——
/// 传输层 LlmUsageNotifier 事件经 main.dart 桥接进来，带 1.5s 尾沿
/// 防抖（agent 一轮对话 N 次 tool 调用只刷 1 次）。
///
/// `info == null` 表示额度不可知：非托管包（kHasBundledBackend=false）、
/// 设备尚未注册（fetchQuota 有意不触发注册副作用）、或查询失败。
/// UI 对 null 的统一处理是隐藏入口，不打扰用户。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/device/device_auth_service.dart';

class DeviceQuotaState {
  /// 当前余额；null = 不可知（见文件头注释）
  final DeviceQuotaInfo? info;

  /// 最近一次成功拉取时间；缓存 TTL 判定用
  final DateTime? fetchedAt;

  /// 是否正在拉取
  final bool loading;

  /// 本机是否已完成过 Star 兑换（一次性权益，本地标记）。
  /// 额度耗尽类 UI（错误条/徽标/额度卡片）据此决定是否引导去 Star——
  /// 已兑换过的用户引导了也只能撞后端 ALREADY_REDEEMED。
  final bool hasRedeemedStar;

  const DeviceQuotaState({
    this.info,
    this.fetchedAt,
    this.loading = false,
    this.hasRedeemedStar = false,
  });

  bool get isFresh =>
      info != null &&
      fetchedAt != null &&
      DateTime.now().difference(fetchedAt!) < quotaCacheTtl;
}

/// 缓存有效期。额度只在 LLM 调用后变化（每 1000 token 扣 1 点），
/// 60s 足以让同一次对话内的重复打开不重复打请求。
const Duration quotaCacheTtl = Duration(seconds: 60);

/// AI 使用后刷新的尾沿防抖窗口。agent 一轮对话可能连续多次 LLM 调用
/// （tool 循环），窗口内合流为一次查询；结束后 1.5s 内必刷。
const Duration quotaUsageDebounce = Duration(milliseconds: 1500);

class DeviceQuotaNotifier extends StateNotifier<DeviceQuotaState> {
  /// 拉取函数可注入（单测）；默认走 DeviceAuthService 单例。
  final Future<DeviceQuotaInfo?> Function() _fetchQuota;

  /// Star 兑换标记读取可注入（单测）；默认走 DeviceAuthService。
  final Future<bool> Function() _hasRedeemedStar;

  Timer? _usageDebounce;

  DeviceQuotaNotifier({
    Future<DeviceQuotaInfo?> Function()? fetchQuota,
    Future<bool> Function()? hasRedeemedStar,
  })  : _fetchQuota = fetchQuota ?? DeviceAuthService.instance.fetchQuota,
        _hasRedeemedStar =
            hasRedeemedStar ?? DeviceAuthService.instance.hasRedeemedStarQuota,
        super(const DeviceQuotaState());

  /// AI 使用事件入口（传输层 LlmUsageNotifier 桥接）。
  /// 尾沿防抖：连续使用只保留最后一次，静默 1.5s 后强刷一次。
  void onAiUsage() {
    _usageDebounce?.cancel();
    _usageDebounce = Timer(quotaUsageDebounce, () {
      refresh(force: true);
    });
  }

  /// 拉取额度。缓存未过期且非强制时跳过；拉取失败静默保持旧值
  /// （fetchQuota 内部已兜底返回 null，仅记日志）。
  Future<void> refresh({bool force = false}) async {
    if (state.loading) return;
    if (!force && state.isFresh) return;
    state = DeviceQuotaState(
      info: state.info,
      fetchedAt: state.fetchedAt,
      loading: true,
      hasRedeemedStar: state.hasRedeemedStar,
    );
    final info = await _fetchQuota();
    if (!mounted) return;
    // 失败（null）时保留旧余额展示，只刷新时间戳推进 TTL，避免每次
    // build 都重打一个注定失败的请求
    state = DeviceQuotaState(
      info: info ?? state.info,
      fetchedAt: DateTime.now(),
      hasRedeemedStar: state.hasRedeemedStar,
    );
    // Star 标记不阻塞余额更新（标记写失败/存储慢都不应拖住 UI），
    // 到达后补写；getBool 内部兜底不抛错。
    _hasRedeemedStar().then((redeemed) {
      if (!mounted) return;
      if (redeemed != state.hasRedeemedStar) {
        state = DeviceQuotaState(
          info: state.info,
          fetchedAt: state.fetchedAt,
          hasRedeemedStar: redeemed,
        );
      }
    });
  }

  @override
  void dispose() {
    _usageDebounce?.cancel();
    super.dispose();
  }
}

final deviceQuotaProvider =
    StateNotifierProvider<DeviceQuotaNotifier, DeviceQuotaState>(
  (ref) => DeviceQuotaNotifier(),
);
