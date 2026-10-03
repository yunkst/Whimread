/// 设备 SoC 探测 Provider（生图 NPU 能力判定单一来源）
///
/// 模型包下载页与引擎自检页共用本探测，避免各调一次 DeviceInfoPlugin。
/// socModel 仅 Android API 31+ 可得，低版本/非 Android 走 null（按无 NPU 处理，
/// 与 Local Dream 同款语义）。
library;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/local_dream_embedded/model_pack.dart';

class DeviceSocInfo {
  final String manufacturer;
  final String model;
  final String androidVersion;
  final int sdkInt;

  /// 芯片型号（如 SM8750）；API < 31 或非 Android 时为空
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
}

final deviceSocProvider = FutureProvider<DeviceSocInfo>((ref) async {
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    final raw = info.data['socModel'] as String? ?? '';
    final soc = raw.isEmpty ? null : raw;
    return DeviceSocInfo(
      manufacturer: info.manufacturer,
      model: info.model,
      androidVersion: info.version.release,
      sdkInt: info.version.sdkInt,
      socModel: soc,
      npuSuffix: soc == null ? null : chipsetSuffixForSoc(soc),
    );
  } catch (_) {
    return const DeviceSocInfo(
      manufacturer: '未知',
      model: '未知',
      androidVersion: '-',
      sdkInt: 0,
      socModel: null,
      npuSuffix: null,
    );
  }
});
