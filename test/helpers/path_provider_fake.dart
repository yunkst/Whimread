/// 本测试专用的 path_provider fake —— 把 getApplicationDocumentsPath
/// 重定向到测试创建的临时目录，避免污染真实文件系统。
library;

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class FakePathProviderPlatform extends PathProviderPlatform {
  /// 文档目录路径；不传时用固定占位路径（不写文件的测试够用），
  /// 需要真实读写的测试传入 systemTemp 临时目录。
  final String documentsPath;
  FakePathProviderPlatform([this.documentsPath = '/tmp/test_app_documents']);

  @override
  Future<String> getApplicationDocumentsPath() async => documentsPath;

  @override
  Future<String> getApplicationSupportPath() async => documentsPath;

  @override
  Future<String> getTemporaryPath() async => documentsPath;
}