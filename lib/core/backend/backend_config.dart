/// 运行时后端 Host 配置：唯一事实来源。
///
/// 之前散落在 5 个文件里的 `kBackendBaseUrl ?? prefs backend_host`
/// 逻辑统一收口到这里；末尾斜杠清理也只在这一处做。
///
/// 编译期常量 [kBackendBaseUrl] / [kHasBundledBackend] 仍由
/// `core/constants/build_config.dart` 定义；本文件只做运行时决策。
library;

import '../../services/preferences_service.dart';
import '../constants/build_config.dart';

/// SharedPreferences key: 用户在「后端服务配置」里手填的后端地址。
///
/// 仅当打包未注入 [kBackendBaseUrl]（非托管包）时生效。
/// 单一事实来源——所有读 / 写都走 [kPrefsBackendHostKey]。
const String kPrefsBackendHostKey = 'backend_host';

/// 解析当前生效的后端 Host（异步,因 prefs 读取是 async）。
///
/// 优先级：
/// 1. 托管模式（[kHasBundledBackend] == true）→ 打包注入的 [kBackendBaseUrl]
/// 2. 自部署模式 → 用户在设置里手填的 prefs 值
///
/// 末尾斜杠会被裁剪，避免拼出 `//api/...` 双斜杠。
///
/// 返回 `''` 表示未配置；调用方按业务决定是否抛错。
///
/// prefs 读取失败（如测试环境 Binding 未初始化）也按「未配置」返回 `''`，
/// 不把存储层异常穿透给业务——host 解析失败不应导致业务整体失败。
Future<String> resolveBackendHost() async {
  final raw = kHasBundledBackend
      ? kBackendBaseUrl
      : await _readPrefsHost();
  return raw.replaceAll(RegExp(r'/+$'), '');
}

Future<String> _readPrefsHost() async {
  try {
    return await PreferencesService.instance.getString(kPrefsBackendHostKey);
  } catch (_) {
    return '';
  }
}
