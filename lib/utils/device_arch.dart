import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import '../services/logger_service.dart';

/// 设备 CPU 架构枚举
///
/// 用于在检查更新时选择对应架构的 APK 文件
enum DeviceArch {
  /// ARM 64-bit（现代 Android 设备主流架构）
  arm64,

  /// ARM 32-bit（老旧设备兼容架构）
  arm,

  /// x86 64-bit（模拟器 / ChromeOS）
  x64,

  /// 未知架构（非 Android 平台或检测失败）
  unknown,
}

extension DeviceArchName on DeviceArch {
  /// 返回 APK 文件名中的架构标识片段
  ///
  /// 对应 Flutter `--split-per-abi` 产出的文件名格式：
  ///   app-arm64-v8a-release.apk
  ///   app-armeabi-v7a-release.apk
  ///   app-x86_64-release.apk
  String get apkNameSegment {
    switch (this) {
      case DeviceArch.arm64:
        return 'arm64-v8a';
      case DeviceArch.arm:
        return 'armeabi-v7a';
      case DeviceArch.x64:
        return 'x86_64';
      case DeviceArch.unknown:
        return '';
    }
  }
}

/// 设备架构检测器
///
/// 通过 Android Build.SUPPORTED_ABIS 获取设备支持的 CPU 指令集列表，
/// 按优先级返回最合适的架构类型。
class DeviceArchDetector {
  DeviceArchDetector._();

  /// 获取当前设备的 CPU 架构
  ///
  /// 非 Android 平台返回 [DeviceArch.unknown]
  static Future<DeviceArch> getCurrent() async {
    if (!Platform.isAndroid) {
      return DeviceArch.unknown;
    }

    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final abis = info.supportedAbis;

      // supportedAbis 按优先级排序，第一位是最优架构
      // 例如：['arm64-v8a', 'armeabi-v7a', 'armeabi']
      if (abis.contains('arm64-v8a')) return DeviceArch.arm64;
      if (abis.contains('x86_64')) return DeviceArch.x64;
      if (abis.contains('armeabi-v7a')) return DeviceArch.arm;

      LoggerService.instance.w(
        '未识别的设备 ABI: $abis，将使用通用 APK',
        category: LogCategory.general,
        tags: ['update', 'arch', 'unknown'],
      );

      return DeviceArch.unknown;
    } catch (e) {
      LoggerService.instance.e(
        '获取设备架构失败: $e',
        category: LogCategory.general,
        tags: ['update', 'arch', 'error'],
      );
      return DeviceArch.unknown;
    }
  }
}
