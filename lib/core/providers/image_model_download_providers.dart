/// 生图模型下载 Provider
///
/// [localDreamPackDownloaderProvider] 提供 Local Dream 模型包（多文件
/// 目录）下载服务单例；[imageModelAdminServiceProvider] 收敛管理页的
/// CRUD 动作（改库 → 刷新 lifecycle 的约定只此一份）；
/// [imageModelLifecycleProvider] 聚合「列表 + 下载事件」为响应式列表，
/// 管理页 watch 它即可实时看到进度。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/interfaces/repositories/i_image_model_repository.dart';
import '../../core/providers/image_model_providers.dart';
import '../../models/image_model.dart';
import '../../services/local_dream_embedded/model_pack_downloader.dart';

/// Local Dream 模型包下载服务单例
final localDreamPackDownloaderProvider =
    Provider<LocalDreamModelPackDownloader>((ref) {
  final service = LocalDreamModelPackDownloader(ref: ref);
  ref.onDispose(service.dispose);
  return service;
});

/// 生图模型管理动作门面（供管理页调用；改库后统一刷新列表）
class ImageModelAdminService {
  final Ref _ref;

  ImageModelAdminService(this._ref);

  IImageModelRepository get _repo => _ref.read(imageModelRepositoryProvider);

  /// 仅刷新列表（包下载器已自行发 onChanged 时也走这里，幂等）
  void refresh() => _refresh();

  void _refresh() => _ref.invalidate(imageModelLifecycleProvider);

  /// 保存（编辑/启停/新建）；name 唯一冲突抛 ImageModelNameConflictException
  Future<void> save(ImageModel model) async {
    await _repo.save(model);
    _refresh();
  }

  Future<void> setDefault(int id) async {
    await _repo.setDefault(id);
    _refresh();
  }

  Future<void> pause(int id) async {
    _ref.read(localDreamPackDownloaderProvider).pause(id);
    _refresh();
  }

  /// 继续下载 / 失败重试（同为 startDownload：.part 断点续传）
  Future<void> resume(ImageModel model) async {
    await _ref.read(localDreamPackDownloaderProvider).startDownload(model);
    _refresh();
  }

  /// 删除模型包（取消任务 + 删包目录 + 删行）
  Future<void> delete(ImageModel model) async {
    await _ref.read(localDreamPackDownloaderProvider).cancelAndDelete(model);
    _refresh();
  }
}

final imageModelAdminServiceProvider =
    Provider<ImageModelAdminService>((ref) => ImageModelAdminService(ref));

/// 模型列表的响应式视图：FutureProvider 基础上叠加下载事件自动刷新。
///
/// 用法（`.when`）：downloading 状态变更会自动 re-fetch，
/// 管理页 watch 本 provider 即可看到进度条实时走动。
final imageModelLifecycleProvider =
    FutureProvider<List<ImageModel>>((ref) async {
  final packDownloader = ref.watch(localDreamPackDownloaderProvider);
  final sub = packDownloader.onChanged.listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);

  final repo = ref.watch(imageModelRepositoryProvider);
  return repo.getAll();
});
