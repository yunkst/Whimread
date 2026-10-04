/// 运行时后端 Host 配置：唯一事实来源。
///
/// 编译期常量 [kBackendBaseUrl]（打包时经 `--dart-define=BACKEND_BASE_URL`
/// 注入）是后端 Host 的唯一来源；本文件只做末尾斜杠清理这一件事。
///
/// 编译期常量 [kBackendBaseUrl] / [kHasBundledBackend] 仍由
/// `core/constants/build_config.dart` 定义。
library;

import '../constants/build_config.dart';

/// 解析当前生效的后端 Host（保持异步签名，调用方统一 await）。
///
/// 末尾斜杠会被裁剪，避免拼出 `//api/...` 双斜杠。
///
/// 返回 `''` 表示未注入托管后端（开发构建）；调用方按业务决定是否报错，
/// 不把存储层异常穿透给业务——host 解析失败不应导致业务整体失败。
Future<String> resolveBackendHost() async {
  return kBackendBaseUrl.replaceAll(RegExp(r'/+$'), '');
}
