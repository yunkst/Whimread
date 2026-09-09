import '../../../models/image_model.dart';

/// 生图模型 Repository 接口
abstract class IImageModelRepository {
  /// 获取所有模型（按 sort_order 排序）
  Future<List<ImageModel>> getAll();

  /// 根据 ID 获取模型
  Future<ImageModel?> getById(int id);

  /// 根据名字获取模型（agent 的 modelName key → ImageModel）
  Future<ImageModel?> getByName(String name);

  /// 获取所有启用的模型（按 sort_order 排序）
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

  /// 名字是否已被占用（编辑对话框唯一性校验用；[excludeId] 用于编辑自身时排除）
  Future<bool> nameExists(String name, {int? excludeId});
}

/// 模型名字冲突（image_models.name 唯一索引）
class ImageModelNameConflictException implements Exception {
  final String name;
  const ImageModelNameConflictException(this.name);

  @override
  String toString() => 'ImageModelNameConflictException: "$name" 已存在';
}
