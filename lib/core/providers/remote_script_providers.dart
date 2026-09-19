/// 云端脚本仓库相关 Provider（v47 起）
///
/// - [remoteScriptServiceProvider]：组合 ApiServiceWrapper + SiteScriptRepository
/// - 列表 / 单脚本的 UI state 由脚本管理面板的 siteScriptListProvider 维护，
///   本文件只暴露 service 注入；UI 通过 Notifier 调方法刷新列表。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/site_script_repository.dart';
import '../../services/remote/remote_script_service.dart';
import 'database_providers.dart';
import 'services/network_service_providers.dart';

/// 云端脚本仓库用例层 Provider
final remoteScriptServiceProvider = Provider<RemoteScriptService>((ref) {
  final api = ref.watch(apiServiceWrapperProvider);
  final SiteScriptRepository scriptRepo =
      ref.watch(siteScriptRepositoryProvider);
  return RemoteScriptService(api: api, scriptRepo: scriptRepo);
});
