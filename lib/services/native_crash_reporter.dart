/// Native crash 报告器（Dart 侧）。
///
/// 与 Kotlin [CrashReporter]（MethodChannel `com.example.novel_app/crash`）
/// 配合，负责：app 冷启动时读取上次 native crash 的 dump 文件，收集版本/
/// 设备环境信息，拼装 GitHub issue 链接，弹出 [CrashReportDialog] 引导用户
/// 提 issue。
///
/// 流程：
/// 1. `checkDumps` → Kotlin 读 filesDir/crash/*.txt
/// 2. 有 dump → 收集 PackageInfo + AndroidDeviceInfo
/// 3. [_buildIssueBody] 拼 Markdown issue 正文
/// 4. showDialog → 用户选"前往 GitHub"则 launchUrl，或仅复制
/// 5. 弹框关闭 → `deleteDumps` 清掉（下次启动不再弹）
///
/// 全程 try-catch：dump 读取/解析失败不阻塞 app 启动。
library;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/crash_report_dialog.dart';

/// GitHub 仓库地址（issue 提交目标）。
const String kGitHubRepo = 'https://github.com/yunkst/Whimread';

class NativeCrashReporter {
  NativeCrashReporter._();

  static const MethodChannel _channel =
      MethodChannel('com.example.novel_app/crash');

  /// 冷启动时调用：检测上次崩溃并弹框引导。
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

      final issueBody = _buildIssueBody(
        dumpContent: content,
        version: version,
        device: device,
      );
      final issueUrl = _buildIssueUrl(issueBody);

      if (!context.mounted) return true;

      final launchGithub = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CrashReportDialog(
          dumpContent: content,
          version: version,
          device: device,
        ),
      );

      if (launchGithub == true) {
        await launchUrl(issueUrl, mode: LaunchMode.externalApplication);
      }

      // 无论用户是否跳转，弹框关闭即删 dump，避免下次启动重复弹。
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

  /// 构造 GitHub issue URL（title + body 预填）。
  ///
  /// 公开便于测试。
  static Uri _buildIssueUrl(String body) {
    return Uri.parse(
      '$kGitHubRepo/issues/new'
      '?title=${Uri.encodeComponent('[Bug] App 崩溃报告')}'
      '&body=${Uri.encodeComponent(body)}',
    );
  }

  /// 构造 issue 正文（Markdown）。
  ///
  /// 抽成独立纯函数便于单测。
  static String _buildIssueBody({
    required String dumpContent,
    required String version,
    required String device,
  }) {
    return [
      '## 崩溃信息',
      '',
      '```',
      dumpContent,
      '```',
      '',
      '## 环境信息',
      '',
      '- App 版本：`$version`',
      '- 设备：$device',
      '',
      '## 复现步骤',
      '',
      '<!-- 请描述崩溃前在做什么操作，例如：打开某站点 → 派 agent → save_script(ocr=true) -->',
      '',
      '1. ',
      '2. ',
      '',
      '> 💡 提示：dump 文件中的 `pc 0x...` 是 native 指令地址，开发者会用符号表解析定位到具体代码。',
    ].join('\n');
  }
}
