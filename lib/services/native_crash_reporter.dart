/// Native crash 报告器（Dart 侧）。
///
/// 与 Kotlin [CrashReporter]（MethodChannel `com.example.novel_app/crash`）
/// 配合，负责：app 冷启动时读取上次 native crash 的 dump 文件，收集版本/
/// 设备环境信息，弹 [CrashReportDialog] 引导用户一键上传到后端
/// （kind=native_crash，附带近期日志，经 [FeedbackService] 提交）。
///
/// 流程：
/// 1. `checkDumps` → Kotlin 读 filesDir/crash/*.txt
/// 2. 有 dump → 收集 PackageInfo + AndroidDeviceInfo
/// 3. showDialog → 用户选"上传报告"则弹框内 [FeedbackService] 提交，
///    或"复制全部"自行留存；网络不可用时复制是兜底路径
/// 4. 弹框关闭 → `deleteDumps` 清掉（下次启动不再弹）
///
/// 全程 try-catch：dump 读取/解析失败不阻塞 app 启动。
library;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../widgets/crash_report_dialog.dart';
import 'feedback_service.dart';
import 'logger_service.dart';

/// GitHub 仓库地址(设置页「去 Star」等入口仍在使用;
/// 崩溃/反馈提交已改为走后端,不再引用此常量)。
const String kGitHubRepo = 'https://github.com/yunkst/Whimread';

class NativeCrashReporter {
  NativeCrashReporter._();

  static const MethodChannel _channel =
      MethodChannel('com.example.novel_app/crash');

  /// 冷启动时调用：检测上次崩溃并弹框引导上传。
  ///
  /// 返回 true 表示检测到崩溃并弹了框。
  /// 任何异常都吞掉（只 debugPrint），绝不阻塞 app 启动。
  static Future<bool> checkAndReport(BuildContext context) async {
    try {
      final raw = await _channel.invokeMethod('checkDumps');
      if (raw == null) return false;
      final dumps = (raw as List).cast<Map<dynamic, dynamic>>();
      if (dumps.isEmpty) return false;

      // 取最早的崩溃（Kotlin 已按 lastModified 升序）。
      final content = dumps.first['content']?.toString() ?? '(空 dump)';

      // 收集环境信息（Dart 侧安全，无 crash 风险）。
      final packageInfo = await PackageInfo.fromPlatform();
      final version = '${packageInfo.version}+${packageInfo.buildNumber}';
      final device = await _collectDeviceInfo();

      if (!context.mounted) return true;

      final uploaded = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CrashReportDialog(
          dumpContent: content,
          version: version,
          device: device,
        ),
      );

      if (uploaded == true) {
        LoggerService.instance.i('native crash 报告已上传到后端',
            category: LogCategory.general,
            tags: ['crash', 'native_crash', 'uploaded']);
      }

      // 无论用户是否上传，弹框关闭即删 dump，避免下次启动重复弹。
      await _channel.invokeMethod('deleteDumps');
      return true;
    } catch (e, stack) {
      debugPrint('NativeCrashReporter.checkAndReport 失败: $e\n$stack');
      return false;
    }
  }

  /// 收集 Android 设备摘要信息（厂商 + 型号 + Android 版本 + SDK）。
  static Future<String> _collectDeviceInfo() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return '${info.manufacturer} ${info.model} '
          '(Android ${info.version.release}, SDK ${info.version.sdkInt})';
    } catch (e) {
      return '(设备信息获取失败: $e)';
    }
  }
}