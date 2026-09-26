/// 生图模型下载 Provider
///
/// [imageModelDownloadServiceProvider] 提供单文件模型（gguf/safetensors）
/// 下载服务单例；[localDreamPackDownloaderProvider] 提供 Local Dream
/// 模型包（多文件目录）下载服务单例；[imageModelLifecycleProvider]
/// 聚合「列表 + 两类下载事件」为响应式列表，管理页 watch 它即可实时看到进度。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/image_model_providers.dart';
import '../../models/image_model.dart';
import '../../services/image_model_download_service.dart';
import '../../services/local_dream_embedded/model_pack_downloader.dart';

/// 下载服务单例（随 container 释放）
final imageModelDownloadServiceProvider = Provider<ImageModelDownloadService>(
    (ref) {
  final service = ImageModelDownloadService(
    repo: ref.watch(imageModelRepositoryProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Local Dream 模型包下载服务单例
final localDreamPackDownloaderProvider =
    Provider<LocalDreamModelPackDownloader>((ref) {
  final service = LocalDreamModelPackDownloader(ref: ref);
  ref.onDispose(service.dispose);
  return service;
});

/// 模型列表的响应式视图：FutureProvider 基础上叠加下载事件自动刷新。
///
/// 用法（`.when`）：downloading/converting 状态变更会自动 re-fetch，
/// 管理页 watch 本 provider 即可看到进度条实时走动。
final imageModelLifecycleProvider =
    FutureProvider<List<ImageModel>>((ref) async {
  final service = ref.watch(imageModelDownloadServiceProvider);
  final sub1 = service.onChanged.listen((_) {
    ref.invalidateSelf();
  });
  final packDownloader = ref.watch(localDreamPackDownloaderProvider);
  final sub2 = packDownloader.onChanged.listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(() {
    sub1.cancel();
    sub2.cancel();
  });

  final repo = ref.watch(imageModelRepositoryProvider);
  return repo.getAll();
});
