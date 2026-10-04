/// 编译期构建配置。
///
/// 通过 `--dart-define` 在打包时注入，替代旧的"用户手填后端地址"模式：
///
/// ```bash
/// flutter build apk --release \
///   --dart-define=BACKEND_BASE_URL=https://api.example.com
/// ```
///
/// 本地联调：`--dart-define=BACKEND_BASE_URL=http://10.0.2.2:3800`（模拟器）
/// 或局域网 IP（真机）。
library;

/// 后端服务基地址（打包时注入，不含末尾斜杠）。
///
/// 唯一的后端 Host 来源——为空表示未注入（开发构建），客户端不做回退。
const String kBackendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

/// 是否注入了托管后端（发布包恒为 true）。
const bool kHasBundledBackend = kBackendBaseUrl != '';
