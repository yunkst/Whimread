/// 设备 SoC 探测 Provider（生图 NPU 能力判定单一来源）
///
/// 模型包下载页与引擎自检页共用本探测，避免各调一次 DeviceInfoPlugin。
///
/// SoC 型号的唯一可靠来源是原生侧 `Build.SOC_MODEL`（与 Local Dream
/// `getDeviceSoc()` 同款语义）：device_info_plus 11.x 的 Android build map
/// **不含 socModel 键**，读 `data['socModel']` 恒为 null，会让所有机型
/// （包括骁龙 8 系）都误判成「无 NPU」。故走 [MethodChannel] 取值，
/// device_info 只补齐展示字段并兜底。
///
/// API < 31 无 `SOC_MODEL` 字段、原生返回 null，按无 NPU 处理，与 Local
/// Dream 一致。
library;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/local_dream_embedded/model_pack.dart';
import '../../services/logger_service.dart';

class DeviceSocInfo {
  final String manufacturer;
  final String model;
  final String androidVersion;
  final int sdkInt;

  /// 芯片型号（如 SM8750）；API < 31、非 Android 或原生不可达时为空
  final String? socModel;

  /// NPU zip 芯片后缀（8gen1/8gen2/min）；无 NPU 为空
  final String? npuSuffix;

  const DeviceSocInfo({
    required this.manufacturer,
    required this.model,
    required this.androidVersion,
    required this.sdkInt,
    required this.socModel,
    required this.npuSuffix,
  });

  bool get hasNpu => npuSuffix != null;
}

/// 与 MainActivity 的 DEVICE_CHANNEL 对接（见 MainActivity#readSocInfo）
const MethodChannel _deviceChannel =
    MethodChannel('com.example.novel_app/device');

/// 归一化 SoC 字符串：非串 / 空串 / 纯空白都视同「没探测到」
String? _normalizeSoc(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Future<String?> _socModelFromNative() async {
  try {
    final payload = await _deviceChannel
        .invokeMethod<Map<Object?, Object?>>('socInfo');
    return _normalizeSoc(payload?['socModel']);
  } on MissingPluginException {
    return null; // 非 Android / 测试环境，不算异常
  } on PlatformException catch (e) {
    // 通道异常属于异常态，用 warning 级——LogReporterService 默认只上传
    // warning+，用户反馈时才带得回来。
    LoggerService.instance.w(
      'SoC 探测通道异常，按无 NPU 处理: $e',
      category: LogCategory.ai,
      tags: const ['image', 'npu', 'detect-channel-error'],
    );
    return null;
  }
}

/// Android 12+（API 31+）却没探测到 SoC 型号时判为异常态。
///
/// 反馈 #8 的形态：vivo V2454DA / Android 16 明明是骁龙 8 系，应用却判
/// 「无 NPU」。此类机型不该静默——用 warning 级上报，日志里能直接看到
/// 「有能力但没探测到」，而联发科 / 老机型判无 NPU 是正常态（info 级）。
@visibleForTesting
bool shouldWarnSocProbeEmpty(int sdkInt, String? socModel) =>
    sdkInt >= 31 && socModel == null;

final deviceSocProvider = FutureProvider<DeviceSocInfo>((ref) async {
  // 先取 SoC（权威来源）。设备基础信息取不到时也保留它——NPU 判定不依赖
  // device_info，历史 bug 正是因为两者被绑在一次 try 里。
  final nativeSoc = await _socModelFromNative();

  try {
    final info = await DeviceInfoPlugin().androidInfo;
    final soc = nativeSoc ?? _normalizeSoc(info.data['socModel']);
    final result = DeviceSocInfo(
      manufacturer: info.manufacturer,
      model: info.model,
      androidVersion: info.version.release,
      sdkInt: info.version.sdkInt,
      socModel: soc,
      npuSuffix: soc == null ? null : chipsetSuffixForSoc(soc),
    );
    LoggerService.instance.i(
      'SoC 探测：socModel=${result.socModel ?? "无"}，'
      'npuSuffix=${result.npuSuffix ?? "无"}',
      category: LogCategory.ai,
      tags: const ['image', 'npu', 'detect'],
    );
    // 正常拿到 API 版本却没拿到 SoC 的骁龙机型是本次事故的形态。用
    // warning 级让它随反馈上传，下次才能从日志直接看出「该机有 NPU 能力
    // 但没探测到」。
    if (shouldWarnSocProbeEmpty(result.sdkInt, result.socModel)) {
      LoggerService.instance.w(
        'Android 12+ 未探测到 SoC 型号（Build.SOC_MODEL 为空或通道未返回），'
        'NPU 生图不可用。若同机型 Local Dream 可检测到 NPU，请附带本日志反馈',
        category: LogCategory.ai,
        tags: const ['image', 'npu', 'detect-empty'],
      );
    }
    return result;
  } catch (_) {
    final result = DeviceSocInfo(
      manufacturer: '未知',
      model: '未知',
      androidVersion: '-',
      sdkInt: 0,
      socModel: nativeSoc,
      npuSuffix:
          nativeSoc == null ? null : chipsetSuffixForSoc(nativeSoc),
    );
    LoggerService.instance.w(
      '设备信息读取失败，仅按原生 SoC 判定 NPU：socModel=${result.socModel ?? "无"}',
      category: LogCategory.ai,
      tags: const ['image', 'npu', 'detect-fallback'],
    );
    return result;
  }
});
