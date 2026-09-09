import '../../../models/llm_config.dart';

/// LLM 配置 Repository 接口
abstract class ILlmConfigRepository {
  /// 获取所有配置（按 sort_order 排序）
  Future<List<LlmConfig>> getAll();

  /// 根据 ID 获取配置
  Future<LlmConfig?> getById(int id);

  /// 获取默认配置
  Future<LlmConfig?> getDefault();

  /// 保存配置（id 为 null 时插入，否则更新）
  Future<int> save(LlmConfig config);

  /// 删除配置
  Future<void> delete(int id);

  /// 设置指定配置为默认（同时取消其他配置的默认标记）
  Future<void> setDefault(int id);

  /// 获取下一个排序值
  Future<int> getNextSortOrder();

  /// 获取配置数量
  Future<int> count();

  /// 清空所有配置的 API Key（保留 name/api_url/model 等元数据）。
  ///
  /// AI 托管模式下使用：客户端不再持有任何第三方 LLM Key。
  /// 返回实际清空的配置条数（原本 Key 为空的行不计入）。
  Future<int> clearAllApiKeys();
}
