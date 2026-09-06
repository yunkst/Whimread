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
/// 为空时回退到用户在「后端服务配置」里手填的地址（保留自部署能力）。
const String kBackendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

/// 是否使用内置托管后端（打包注入了地址即为 true）。
const bool kHasBundledBackend = kBackendBaseUrl != '';
