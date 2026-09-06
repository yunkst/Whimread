/// App 更新检查过程中的可恢复异常
///
/// 用于将「网络错误 / 限流 / 服务器错误」与「真无新版本」区分开，
/// 避免把所有 null 都误报成「已是最新版本」。
class AppUpdateCheckException implements Exception {
  final String message;

  /// 失败原因分类：`rate_limited` / `network_error` / `http_xxx` / `unknown`
  final String cause;

  const AppUpdateCheckException(this.message, {required this.cause});

  @override
  String toString() => 'AppUpdateCheckException($cause): $message';
}
