import '../../../models/image_model.dart';

/// 生图模型 Repository 接口
abstract class IImageModelRepository {
  /// 获取所有模型（按 sort_order 排序）
  Future<List<ImageModel>> getAll();

  /// 根据 ID 获取模型
  Future<ImageModel?> getById(int id);

  /// 根据名字获取模型（agent 的 modelName key → ImageModel）
  Future<ImageModel?> getByName(String name);

  /// 获取所有启用且已就绪（status=ready）的模型
  ///
  /// downloading/paused/converting/failed 状态不返回——agent 永远看不到半成品。
  Future<List<ImageModel>> getEnabled();

  /// 获取默认模型
  Future<ImageModel?> getDefault();

  /// 保存模型（id 为 null 时插入，否则更新）
  ///
  /// [name] 违反唯一约束时抛出 [ImageModelNameConflictException]。
  Future<int> save(ImageModel model);

  /// 删除模型
  Future<void> delete(int id);

  /// 设置指定模型为默认（同时取消其他模型的默认标记）
  Future<void> setDefault(int id);

  /// 获取下一个排序值
  Future<int> getNextSortOrder();

  /// 获取模型数量
  Future<int> count();

  /// 更新下载/转换进度（0-100，高频调用，部分列 UPDATE）
  Future<void> updateProgress(int id, int progress);

  /// 变更生命周期状态（可顺带写入错误摘要、产出文件路径等）
  Future<void> updateStatus(
    int id,
    ImageModelStatus status, {
    String errorMessage = '',
    int? progress,
    String? filePath,
    int? fileSize,
    int? defaultWidth,
    int? defaultHeight,
  });

  /// 按状态查询（启动对账：找 downloading/converting 的遗留行）
  Future<List<ImageModel>> getByStatus(ImageModelStatus status);
}

/// 模型名字冲突（image_models.name 唯一索引）
class ImageModelNameConflictException implements Exception {
  final String name;
  const ImageModelNameConflictException(this.name);

  @override
  String toString() => 'ImageModelNameConflictException: "$name" 已存在';
}
