/// Agent 会话持久化协作类 — 从 ScenarioSession 拆出的 DB 写入层
///
/// 职责：chat_messages / chat_sessions 两张表的全部增量写路径
/// （单条 / 批量落库、currentNovel 同步 + 标题自动同步、以内存为基准的
/// 原子重写、清库）。ScenarioSession 组合持有本类，自身只保留会话编排，
/// DB 写入行为与拆分前逐行一致。
///
/// 两处例外（拆分时的显式变更，其余均为逐行搬移）：
/// - 原 `_deleteAgentMessagesFromDb` / `_deleteAgentMessagesBeforeDb` 除日志
///   tag 外逐行相同，合并为参数化的 [rewriteAgentMessagesInDb]（日志文案与
///   tag 保留区分，见方法注释）。
/// - [persistAgentMessage] 的索引定位由 indexOf 改为 identical() 遍历
///   （行为修复，见方法注释）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat_message_record.dart';
import '../../models/chat_session.dart';
import '../../repositories/chat_session_repository.dart';
import '../../services/dsl_engine/llm_provider.dart' show ChatMessage;
import '../../services/logger_service.dart';
import 'chat_session_providers.dart';
import 'current_novel_provider.dart' show CurrentNovel;
import 'database_providers.dart';

/// ScenarioSession 的 DB 持久化协作类
class AgentSessionPersistence {
  final Ref _ref;
  final String scenarioId;

  /// 活状态读取器：由 ScenarioSession 注入闭包，直接读其可变状态
  /// （不复制），保证重写 DB 时看到的与内存真理源一致。
  final int? Function() _sessionId;
  final CurrentNovel? Function() _currentNovel;
  final List<ChatMessage> Function() _agentMessages;

  AgentSessionPersistence({
    required Ref ref,
    required this.scenarioId,
    required int? Function() sessionId,
    required CurrentNovel? Function() currentNovel,
    required List<ChatMessage> Function() agentMessages,
  })  : _ref = ref,
        _sessionId = sessionId,
        _currentNovel = currentNovel,
        _agentMessages = agentMessages;

  /// 落库单条 agent 消息（user 消息即时落库用）
  ///
  /// [行为修复] 索引定位改为按对象身份（identical）遍历，不再用 indexOf：
  /// indexOf 走 `==` 语义，一旦相等性按内容判定（未来重写 `==` / const 规范化
  /// 等），内容相同的 user 消息会命中列表中第一条同内容消息，导致落库的
  /// agentMsgIndex 错位——appendMessage 按该索引定位 DB 行，错位会打乱 ReAct 链
  /// （hydrate 时 1:1 还原依赖索引顺序）。identical() 把定位锚定在"刚插入本列表
  /// 的本条实例"上，与 `==` 语义彻底解耦。
  Future<void> persistAgentMessage(ChatMessage m) async {
    final sid = _sessionId() ?? _ref.read(currentChatSessionIdProvider(scenarioId));
    if (sid == null) return;
    try {
      final repo = _ref.read(chatSessionRepositoryProvider);
      final msgs = _agentMessages();
      var idx = -1;
      for (var i = 0; i < msgs.length; i++) {
        if (identical(msgs[i], m)) {
          idx = i;
          break;
        }
      }
      await repo.appendMessage(ChatMessageRecord.fromAgentMessage(
        sid,
        idx >= 0 ? idx : msgs.length - 1,
        m,
      ));
      _ref.invalidate(chatSessionsByScenarioProvider(scenarioId));
    } catch (e, st) {
      LoggerService.instance.e(
        'ScenarioSession [$scenarioId] 落库 agent 消息失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['session', 'persist_msg', 'failed', scenarioId],
      );
    }
  }

  /// 批量落库多条 agent 消息（回合结束 finalize 用）
  ///
  /// agentMsgIndex 基于 _agentMessages 的最终位置计算（消息已 addAll 进去）。
  /// 整批单事务提交：中途失败全部回滚，不会留下断裂的 ReAct 链。
  Future<void> persistAgentMessages(List<ChatMessage> msgs,
      {bool partial = false}) async {
    final sid = _sessionId() ?? _ref.read(currentChatSessionIdProvider(scenarioId));
    if (sid == null) return;
    try {
      final repo = _ref.read(chatSessionRepositoryProvider);
      final startIdx = _agentMessages().length - msgs.length;
      final records = [
        for (var i = 0; i < msgs.length; i++)
          ChatMessageRecord.fromAgentMessage(sid, startIdx + i, msgs[i]),
      ];
      await repo.appendMessages(records);
      _ref.invalidate(chatSessionsByScenarioProvider(scenarioId));
      LoggerService.instance.d(
        'ScenarioSession [$scenarioId] 落库 ${msgs.length} 条 agent 消息 '
        'partial=$partial sessionId=$sid startIdx=$startIdx',
        category: LogCategory.ai,
        tags: [
          'session',
          'persist_turn',
          partial ? 'partial' : 'ok',
          scenarioId
        ],
      );
    } catch (e, st) {
      LoggerService.instance.e(
        'ScenarioSession [$scenarioId] 批量落库失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['session', 'persist_turn', 'failed', scenarioId],
      );
    }
  }

  Future<void> persistCurrentNovel() async {
    final sid = _sessionId();
    if (sid == null) return;
    try {
      final repo = _ref.read(chatSessionRepositoryProvider);
      // 先读旧行：标题自动同步策略需要参照旧的 currentNovelTitle，
      // 区分「自动命名（=旧小说标题）」与「用户手动重命名」。
      final oldRow = await repo.getSession(sid);
      final novel = _currentNovel();
      await repo.updateCurrentNovel(
        sid,
        novelId: novel?.id,
        novelTitle: novel?.title,
      );
      await _maybeSyncSessionTitle(repo, sid, oldRow);
    } catch (e, st) {
      LoggerService.instance.e(
        'ScenarioSession [$scenarioId] 同步 currentNovel 失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['session', 'persist_novel', 'failed', scenarioId],
      );
    }
  }

  /// 会话标题自动同步：跟随当前小说变化，但尊重用户手动重命名。
  ///
  /// 判定规则（用旧行做参照，无状态、无需额外字段）：
  /// - 旧标题为空 或 旧标题 == 旧 currentNovelTitle → 视为自动命名 → 改写
  /// - 否则视为用户手动改过名 → 保留
  ///
  /// 改写后失效 sessions 列表缓存，让历史面板刷新显示新标题。
  Future<void> _maybeSyncSessionTitle(
    ChatSessionRepository repo,
    int sid,
    ChatSession? oldRow,
  ) async {
    final newTitle = _currentNovel()?.title.trim();
    if (newTitle == null || newTitle.isEmpty) return;
    if (oldRow == null) return;
    final current = oldRow.title.trim();
    final prevAutoTitle = oldRow.currentNovelTitle?.trim();
    final wasAutoNamed = current.isEmpty || current == prevAutoTitle;
    if (!wasAutoNamed) return;
    if (newTitle == current) return;
    try {
      await repo.renameSession(sid, newTitle);
      _ref.invalidate(chatSessionsByScenarioProvider(scenarioId));
      LoggerService.instance.d(
        'ScenarioSession [$scenarioId] 会话标题自动同步 → "$newTitle" '
        '(sessionId=$sid)',
        category: LogCategory.ai,
        tags: ['session', 'auto_rename', scenarioId],
      );
    } catch (e, st) {
      LoggerService.instance.e(
        'ScenarioSession [$scenarioId] 自动同步会话标题失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['session', 'auto_rename', 'failed', scenarioId],
      );
    }
  }

  /// 以内存为基准原子重写 DB（retry / rollback / 压缩共用）
  ///
  /// 由原 `_deleteAgentMessagesFromDb`（retry/rollback 路径）与
  /// `_deleteAgentMessagesBeforeDb`（压缩路径）合并：二者除日志 tag 外逐行
  /// 相同，故参数化 [logTag] 保留区分，日志文案逐字不变。
  ///
  /// 内存 _agentMessages 是事实来源：调用方先改内存（尾部截断或压缩前缀），
  /// 这里把 DB 重写成与内存一致（replaceMessages 单事务：清空 + 按序整批写入）。
  /// 中途崩溃/失败由事务保证回滚到重写前的完整状态，不会留下断裂会话。
  ///
  /// [triggerIndex] 不参与删除范围计算，仅用于日志定位触发点
  /// （retry/rollback 传 fromIndex，压缩传 beforeIndex）。
  /// [logTag]：`db_rewrite`（retry/rollback）| `compaction_db`（压缩）。
  Future<void> rewriteAgentMessagesInDb(
    int triggerIndex, {
    required String logTag,
  }) async {
    // 两类调用点的日志文案 / tag 保持拆分前原样，仅实现合并
    final isCompaction = logTag == 'compaction_db';
    final successLabel = isCompaction ? '压缩后 DB 重写' : 'DB 重写';
    final failLabel = isCompaction ? '压缩 DB 清理失败' : 'DB 重写失败';
    final indexLabel = isCompaction ? 'beforeIndex' : 'fromIndex';
    final sid = _sessionId();
    if (sid == null) return;
    try {
      final repo = _ref.read(chatSessionRepositoryProvider);
      final msgs = _agentMessages();
      final records = [
        for (var i = 0; i < msgs.length; i++)
          ChatMessageRecord.fromAgentMessage(sid, i, msgs[i]),
      ];
      await repo.replaceMessages(sid, records);
      _ref.invalidate(chatSessionsByScenarioProvider(scenarioId));
      LoggerService.instance.i(
        'ScenarioSession [$scenarioId] $successLabel: '
        '保留 ${records.length} 条 ($indexLabel=$triggerIndex)',
        category: LogCategory.ai,
        tags: ['session', logTag, scenarioId],
      );
    } catch (e, st) {
      LoggerService.instance.e(
        'ScenarioSession [$scenarioId] $failLabel: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['session', logTag, 'failed', scenarioId],
      );
    }
  }

  Future<void> clearMessagesFromDb() async {
    final sid = _sessionId();
    if (sid == null) return;
    try {
      await _ref.read(chatSessionRepositoryProvider).clearMessages(sid);
      _ref.invalidate(chatSessionsByScenarioProvider(scenarioId));
    } catch (e, st) {
      LoggerService.instance.e(
        'ScenarioSession [$scenarioId] 清库 messages 失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['session', 'clear_db', 'failed', scenarioId],
      );
    }
  }
}
