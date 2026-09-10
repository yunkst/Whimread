/// 本测试专用的 path_provider fake —— 把 getApplicationDocumentsPath
/// 重定向到测试创建的临时目录，避免污染真实文件系统。
library;

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class FakePathProviderPlatform extends PathProviderPlatform {
  final String documentsPath;
  FakePathProviderPlatform(this.documentsPath);

  @override
  Future<String> getApplicationDocumentsPath() async => documentsPath;

  @override
  Future<String> getApplicationSupportPath() async => documentsPath;

  @override
  Future<String> getTemporaryPath() async => documentsPath;
}