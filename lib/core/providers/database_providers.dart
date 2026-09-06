import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riverpod/riverpod.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/character_repository.dart';
import '../../repositories/character_relation_repository.dart';
import '../../repositories/novel_repository.dart';
import '../../repositories/chapter_repository.dart';
import '../../repositories/chapter_version_repository.dart';
import '../../repositories/outline_repository.dart';
import '../../repositories/bookshelf_repository.dart';
import '../../repositories/prompt_tag_category_repository.dart';
import '../../repositories/llm_config_repository.dart';
import '../../repositories/prompt_tag_repository.dart';
import '../../repositories/site_script_repository.dart';
import '../../repositories/agent_memory_repository.dart';
import '../../repositories/chat_session_repository.dart';
import '../database/database_connection.dart';
import '../interfaces/repositories/i_novel_repository.dart';
import '../interfaces/repositories/i_chapter_repository.dart';
import '../interfaces/repositories/i_chapter_version_repository.dart';
import '../interfaces/repositories/i_character_repository.dart';
import '../interfaces/repositories/i_character_relation_repository.dart';
import '../interfaces/repositories/i_bookshelf_repository.dart';
import '../interfaces/repositories/i_outline_repository.dart';
import '../interfaces/repositories/i_prompt_tag_category_repository.dart';
import '../interfaces/repositories/i_prompt_tag_repository.dart';

part 'database_providers.g.dart';

/// 数据库连接Provider
///
/// 提供全局单例 DatabaseConnection 实例
/// 使用 keepAlive: true 确保数据库连接不会因为没有监听者而被销毁
@Riverpod(keepAlive: true)
DatabaseConnection databaseConnection(Ref ref) {
  final connection = DatabaseConnection();
  ref.onDispose(() => connection.close());
  return connection;
}

/// NovelRepository Provider
///
/// 使用IDatabaseConnection接口注入，支持测试和依赖替换
@riverpod
INovelRepository novelRepository(Ref ref) {
  final dbConnection = ref.watch(databaseConnectionProvider);
  return NovelRepository(dbConnection: dbConnection);
}

/// 书架写操作 Provider（仅 [BookshelfMutationNotifier] 用）。
///
/// 通过 cast 拿到 [NovelRepository] 的 IBookshelfWriter 能力。
/// 普通调用方应使用 [bookshelfMutationProvider] 走收口路径。
@riverpod
IBookshelfWriter bookshelfWriter(Ref ref) {
  return ref.watch(novelRepositoryProvider) as NovelRepository;
}

/// ChapterRepository Provider
///
/// 使用IDatabaseConnection接口注入，支持测试和依赖替换
/// 依赖 ChapterVersionRepository 实现自动版本保存
@riverpod
IChapterRepository chapterRepository(Ref ref) {
  final dbConnection = ref.watch(databaseConnectionProvider);
  final versionRepo = ref.watch(chapterVersionRepositoryProvider);
  return ChapterRepository(dbConnection: dbConnection, versionRepo: versionRepo);
}

/// 章节写操作 Provider（仅 [ChapterMutationNotifier] 用）。
///
/// 通过 cast 拿到 [ChapterRepository] 的 [IChapterWriter] 能力（含 12 个原写方法
/// + 2 个事务方法 `createCustomChapterWithShift` / `deleteChapterAndReindex`）。
/// 普通调用方应使用 `chapterMutationProvider` 走收口路径——通过
/// `IChapterRepository` 类型拿不到写能力，编译期阻止绕过 Notifier 直接写库
/// （正是「agent 写完章节列表不刷新」bug 的根因）。
@riverpod
IChapterWriter chapterWriter(Ref ref) {
  return ref.watch(chapterRepositoryProvider) as ChapterRepository;
}

/// ChapterVersionRepository Provider
///
/// 章节历史版本的持久化操作
@riverpod
IChapterVersionRepository chapterVersionRepository(Ref ref) {
  final dbConnection = ref.watch(databaseConnectionProvider);
  return ChapterVersionRepository(dbConnection: dbConnection);
}

/// CharacterRepository Provider
///
/// 使用IDatabaseConnection接口注入，支持测试和依赖替换
@riverpod
ICharacterRepository characterRepository(Ref ref) {
  final dbConnection = ref.watch(databaseConnectionProvider);
  return CharacterRepository(dbConnection: dbConnection);
}

/// CharacterRelationRepository Provider
///
/// 使用IDatabaseConnection接口注入，支持测试和依赖替换
@riverpod
ICharacterRelationRepository characterRelationRepository(Ref ref) {
  final dbConnection = ref.watch(databaseConnectionProvider);
  return CharacterRelationRepository(dbConnection: dbConnection);
}

/// OutlineRepository Provider
///
/// 使用IDatabaseConnection接口注入，支持测试和依赖替换
@riverpod
IOutlineRepository outlineRepository(Ref ref) {
  final dbConnection = ref.watch(databaseConnectionProvider);
  return OutlineRepository(dbConnection: dbConnection);
}

/// PromptTagCategoryRepository Provider
@riverpod
IPromptTagCategoryRepository promptTagCategoryRepository(Ref ref) {
  final dbConnection = ref.watch(databaseConnectionProvider);
  return PromptTagCategoryRepository(dbConnection: dbConnection);
}

/// PromptTagRepository Provider
@riverpod
IPromptTagRepository promptTagRepository(Ref ref) {
  final dbConnection = ref.watch(databaseConnectionProvider);
  return PromptTagRepository(dbConnection: dbConnection);
}

/// BookshelfRepository Provider
///
/// 使用IDatabaseConnection接口注入，支持测试和依赖替换
@riverpod
IBookshelfRepository bookshelfRepository(Ref ref) {
  final dbConnection = ref.watch(databaseConnectionProvider);
  return BookshelfRepository(dbConnection: dbConnection);
}

/// 书架关联表写操作 Provider（仅 [BookshelfMutationNotifier] 用）。
@riverpod
IBookshelfAssociationWriter bookshelfAssociationWriter(Ref ref) {
  return ref.watch(bookshelfRepositoryProvider) as BookshelfRepository;
}

/// SiteScriptRepository Provider
///
/// 站点提取脚本的持久化操作
final siteScriptRepositoryProvider = Provider<SiteScriptRepository>((ref) {
  final dbConnection = ref.watch(databaseConnectionProvider);
  return SiteScriptRepository(dbConnection: dbConnection);
});

/// AgentMemoryRepository Provider
///
/// Agent 场景经验记忆的持久化操作
final agentMemoryRepositoryProvider = Provider<AgentMemoryRepository>((ref) {
  final dbConnection = ref.watch(databaseConnectionProvider);
  return AgentMemoryRepository(dbConnection: dbConnection);
});

/// LlmConfigRepository Provider
///
/// LLM 配置序列的持久化操作
final llmConfigRepositoryProvider = Provider<LlmConfigRepository>((ref) {
  final dbConnection = ref.watch(databaseConnectionProvider);
  return LlmConfigRepository(dbConnection: dbConnection);
});

/// ChatSessionRepository Provider
///
/// AI 对话会话历史的持久化操作
final chatSessionRepositoryProvider = Provider<ChatSessionRepository>((ref) {
  final dbConnection = ref.watch(databaseConnectionProvider);
  return ChatSessionRepository(dbConnection: dbConnection);
});
