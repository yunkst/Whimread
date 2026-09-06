import '../../../models/chat_session.dart';
import '../../../models/chat_message_record.dart';

/// AI 对话会话仓库接口
///
/// 管理 chat_sessions / chat_messages 两表的 CRUD：
/// - 会话级：创建 / 列出 / 重命名 / 删除（messages 经外键 CASCADE 级联删除）
/// - 消息级：appendMessage 用事务保证 orderIndex 单调递增 + session.updatedAt 同步
abstract class IChatSessionRepository {
  // ===== 会话 =====

  /// 创建一条新会话，自动写入 createdAt / updatedAt（=now）
  /// 返回插入后的行 id
  Future<int> createSession(ChatSession session);

  /// 列出指定 scenario 的所有会话（按 updatedAt DESC 排序）
  ///
  /// [limit] 硬上限（默认 200），防止 UI 一次拉太多导致卡顿
  Future<List<ChatSession>> listSessionsByScenario(
    String scenarioId, {
    int limit = 200,
  });

  /// 按 id 查单条会话
  Future<ChatSession?> getSession(int id);

  /// 重命名会话（同时刷新 updatedAt）
  Future<int> renameSession(int id, String title);

  /// 删除会话（messages 经外键 CASCADE 自动清空）
  Future<int> deleteSession(int id);

  /// 刷新 updatedAt（每条新消息入栈时由 appendMessage 内部调用，单测覆盖用）
  Future<int> touchSession(int id);

  /// 更新会话关联的 currentNovel（写 currentNovelId / currentNovelTitle / updatedAt）
  ///
  /// [novelId] / [novelTitle] 任一为 null 都会写入 null（清空关联）。
  Future<void> updateCurrentNovel(
    int id, {
    int? novelId,
    String? novelTitle,
  });

  // ===== 消息 =====

  /// 追加一条 agent 消息到 session。
  ///
  /// [record.agentMsgIndex] 由调用方传入。
  /// 用 `db.transaction` 把"写入消息 + 刷新 session.updatedAt"包成原子单元。
  /// 失败时整体回滚。返回新插入的 message 行 id。
  Future<int> appendMessage(ChatMessageRecord record);

  /// 更新单条已落库消息的 content（用于工具重试原地覆盖结果）。
  ///
  /// 仅刷新 message 自身的 timestamp，**不**刷新 session.updatedAt——
  /// 重试不改变会话活跃度，只改一条历史工具结果。
  /// 返回受影响行数（0 表示消息已被删/不存在）。
  Future<int> updateMessageContent(int messageId, String content);

  /// 获取会话的消息（按 agentMsgIndex ASC 排序）
  ///
  /// [limit] / [offset] 支持分页，避免长会话冷启动一次性全量加载。
  /// 不传 limit 表示全量。
  Future<List<ChatMessageRecord>> listMessages(
    int sessionId, {
    int? limit,
    int offset = 0,
  });

  /// 获取会话的消息总数
  Future<int> getMessageCount(int sessionId);

  /// 清空会话的全部消息（保留 session 行，updatedAt 由 transaction 内统一刷新）
  Future<int> clearMessages(int sessionId);

  /// 删除会话中 agentMsgIndex < [beforeIndex] 的所有消息。
  ///
  /// 用于上下文压缩 / retry / rollback 时同步删 DB，保证内存与 DB 一致。
  /// 同步刷新 session.updatedAt。返回删除行数。
  Future<int> deleteMessagesBefore(int sessionId, int beforeIndex);
}
