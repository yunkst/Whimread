[根目录](../../CLAUDE.md) > **novel_app**

# Flutter移动应用模块

## 变更记录 (Changelog)

- **2026-08-05**: **修复"全部小说"书架移动图书失败 + 合并冗余菜单**。`BookshelfRepository.moveNovelToBookshelf` 在 `from=1`(虚拟书架"全部小说")时从抛 `ArgumentError` 改为 add-only 降级;`BookshelfScreen._showNovelMenu` 在 `currentBookshelfId==1` 时把"移动到书架"和"复制到书架"两条菜单合并为单一"加入书架"入口(走 `copyToBookshelf`,UI 文案诚实表达"书仍留在全部小说")。`_showBookshelfSelectionDialog` 新增 `mode='join'` 分支。详见 spec `docs/superpowers/specs/2026-08-05-all-novels-bookshelf-join-design.md` + plan `docs/superpowers/plans/2026-08-05-all-novels-bookshelf-join.md`。widget test 豁免(测试环境启动全屏 BookshelfScreen 卡在原生插件 channel MissingPlugin),菜单渲染由手动验证覆盖。
- **2026-08-05**: **修复应用日志「全部级别」/「全部分类」按钮失效**。根因：Flutter `PopupMenuItem` 文档明确 "If itemBuilder returns an item with a null value, the item will not be selectable." —— 原代码两个过滤菜单的"全部"项用 `value: null`，framework 故意吞掉点击、`onSelected` 不触发，表现为"点了没反应、列表仍是当前过滤结果"。修复：`log_viewer_screen.dart` 顶部加文件级 `const Object _kNoFilterSentinel = Object()`，两个 `PopupMenuButton<T?>` 改 `PopupMenuButton<Object?>`，菜单项的"全部"项 `value: _kNoFilterSentinel`，`onSelected` 用 `identical(v, _kNoFilterSentinel)` 判别还原成 nullable。回归测试：`test/unit/screens/log_viewer_filter_menu_test.dart`(3 个 widget test 端到端) + `test/bug/log_viewer_all_level_button_repro_test.dart`(framework 行为对比)。analyze 0 告警。
- **2026-07-29**: **修复 Agent Chat 对话窗口「新建会话」入口丢失**。`a52c8ab`(2026-07-27 dialog 瘦身 shell)删除顶栏 inline「新建会话」按钮后,入口被埋进 `⋮ → 会话历史 → sheet +` 三层菜单,可发现性回归。`AgentChatHeader` 加 `onNewSession` 字段 + `IconButton(AgentIcons.plus, tooltip '新建会话')`(全屏按钮后、关闭按钮前);`agent_chat_dialog.dart` 加 `_startNewSession()` 连线 `scenarioSessionsProvider.notifier.startNewSession`。更新 `agent_chat_header_test.dart` 四按钮断言 + 回调触发用例。analyze 零告警、dialog 测试无回归。
- **2026-07-27**: **文档同步现状**。App 版本 2.0.2-preview.2+111，DB v39，3 Tab（书架 / 浏览器 / 设置，删除"生图调试"），Repository 12 个（按 `ls novel_app/lib/repositories/` 实际结果，剔除 `base_repository.dart`；plan 写的 15 是粗估），Screen 24+，Service 48+，Widget 50+，Provider 40+，Model 25；删除 `core/di/`（实际不存在）、`illustration_repository` / `chat_scene_repository` / `novel_export_repository` / `prompt_history_repository` 等幽灵 module 引用；`chapter_cache` 服务端 PostgreSQL 段删除（2026-07-08 后端已删 `/api/cache/*`）；DSL Engine 段去"本地 Dify 工作流复刻"措辞，标 2026-06-09 已彻底解耦。详见 `docs/superpowers/specs/2026-07-27-github-display-optimization-design.md` + `docs/superpowers/plans/2026-07-27-github-display-optimization.md`。
- **2026-07-18**: **LLM 重试 UI 展示**。Agent Chat 底部输入栏上方浮动横幅(变体 2:错误码类别 + 倒计时,传输层橙/回合层蓝)。新建 `retry_signals.dart`(模块级单例 + `categorizeRetryError` 共享工具);`withRetry` 加可选 `onRetry` 回调(向后兼容);`IoLlmHttpClient` 接入 `RetrySignals.reportTransport` + 成功 `clear()`(rethrow 不 clear 避免与 round-level race);`agent_loop` round-level `emit RetryEvent` + `reportRound` 同一处(绕开事件流过滤);新建 `RetryBanner` widget(订阅 `RetrySignals.instance.notifier`,Timer.periodic 倒计时)。完整方案见 `docs/superpowers/specs/2026-07-17-llm-retry-ui-design.md` + `docs/superpowers/plans/2026-07-17-llm-retry-ui.md`。
- **2026-07-18**: **上下文压缩 UI 展示**。Agent Chat 消息流内嵌可展开分隔条(M3) + 一次性 SnackBar + 持久落 DB 重启可见。压缩提示以 `role:'system'` 约定 KV 消息(`[上下文压缩|...]`)为唯一真理源,运行时与 hydrate 走同一 `_projectUiMessages` 投影层,marker 渲染不依赖 `CompactionEvent`。新建 `CompactionMarkerSegment`(AgentChatSegment sealed 子类) + `AgentChatRole.marker` + `CompactionNoteParser`(KV 解析器) + `CompactionMarkerCard`(可展开卡片) + `agentEventsProvider`(StreamProvider)。改 `context_compactor._buildCompactionNote`(加 KV) + `CompactionEvent`(补 `compactedChars`/`compactionNote`) + `_handleCompaction`(insert 压缩提示) + `_projectUiMessages`(system 分流) + `agent_chat_dialog`(itemBuilder marker 分支 + ref.listen SnackBar)。新增 69 个测试(模型序列化/解析器/投影/hydrate/marker 卡片/dialog 集成/SnackBar/回归)。不改 DB schema。完整设计与实现计划见 `docs/superpowers/specs/2026-07-18-context-compaction-ui-design.md` + `docs/superpowers/plans/2026-07-18-context-compaction-ui.md`。
- **2026-07-18**: **ContextCompactor P1 预剪枝层**。`context_compactor.dart` `compact()` 第一步新增 `_pruneOldToolResults`：Pass 1 MD5 去重（200 字符阈值，保留最新一条，前面重复替换为 `[toolName dup of idx#md5]`）+ Pass 2 按工具类型 1-liner 改写（500 字符阈值，覆盖 read_chapter_content / list_chapters / search_in_chapters / execute_js 四个高频工具 + 通用 fallback，错误分支保留 `{error, message}`）。默认保护最近 6 条 tool result 不动（`protectRecentToolResults`）。只改 tool result 的 content（改写后仍是合法 JSON，read_chapter 纯文本特例除外），assistant.toolCalls / system / user / toolCallId / 消息顺序不变。改写后同样 `preserveTailChars` 预算能装下更多消息，减少丢消息数。`CompactionResult.rewrittenContent` + `CompactionEvent.rewrittenContent` 携带改写记录透传给 `ScenarioSession._handleCompaction`，复用现有 `_deleteAgentMessagesBeforeDb`（clearMessages + 重写 `_agentMessages`）自动把 1-liner 版落库，hydrate 续聊时 LLM 看精简版。新增 `CompactorConfig.{prePruneEnabled, dedupThresholdChars, longFieldChars, protectRecentToolResults}` 4 个配置项，`prePruneEnabled=false` 退化为 v32 行为。借鉴 `hermes-agent/agent/context_compressor.py` 的 `_prune_old_tool_results`。agent_loop emit / scenario_session `_handleCompaction` 同步更新。新增 20 个单测（4 group：1-liner 模板 / 去重 / 保护区间 / 契约）。
- **2026-07-17**: **LLM HTTP 错误统一重试**。`retry_helper` 删除 `NonRetryableHttpException` 类，`isRetryableStatus` 改为 `>= 400`（所有 4xx/5xx 一律重试）；`llm_provider` 的 `_postJsonOnce`/`_postJsonStreamHandshake` 移除 4xx 分支，统一抛 `RetryableHttpException`；`chatForJson` 应用层 `retryOnParseError` 默认 1→0（彻底交给传输层 8 次/60s 重试）。瞬态 4xx（代理网关偶发 400/401 等）不再直接打断会话。同步反转 `retry_helper_test`/`agent_loop_retry_test` 断言并新增 400/401 round-level 重试用例。
- **2026-07-17**: **save_script 错误归因修正**。`validateAndPersistScript` 内 `await _validateOcr` 包 `try/catch TimeoutException`，新增 `ocr_verify_timeout` reason，区分 OCR 验证超时（实际 30s，源自 OCR-JS 模板首行 `await document.fonts.ready` 在 `loadUrl(test_url)` 冷启动页面上等字体下载）与主脚本超时（>120s）；`_saveScript` 外层 `on TimeoutException` 文案改为"主脚本…超时(>120s)"，避免 OCR 渲染超时被误报成主脚本 120s。仅 catch `TimeoutException`，OCR 渲染失败抛的 `Exception` 仍冒泡走 `internal_error`。新增 2 个单测覆盖 verifyFontFamily / restorePuaInText 超时归因。后续 P2（未做）：`loadUrl` 后显式等 `document.fonts.ready` 把字体冷加载从 OCR-JS 内部抽到外层阶段。
- **2026-07-15**: OCR 提取器产品化。site_scripts 加 ocr 列（v37）；OcrPredictor 改 recognizeImage(base64Png)；新增 OcrRestoreService（restorePuaInText/verifyFontFamily/readableRatio）+ 系统 OCR-JS 模板；HeadlessWebViewContentService/ChapterListService 加 OCR 还原钩子；save_script 重写为分次保存+落库前验证（domain/run_id/script_type/test_url/ocr）；prompt 加提取器创建流程。番茄字体反爬正文可读。
- **2026-07-17**: **移除 webview 模型下载链路**。Webview 浏览器不再支持下载模型到后端 `/app/models`：删除 `model_download_manager_screen` / `model_save_location_dialog` / `model_download_service` / `model_download_repository` / `model_download_task` 模型 / `model_download_providers` 共 6 文件；移除 `webview_providers.handleDownloadStart` + `InAppWebView.onDownloadStartRequest` 入口；删除 `ApiServiceWrapper` 中 `listModelDirs` / `initModelUpload` / `uploadModelChunk` / `getModelUploadStatus` / `completeModelUpload` / `cancelModelUpload` 6 个方法；DB v37→v38 migration drop `model_download_tasks` 表；pubspec 移除 `background_downloader` 依赖、Manifest 同步删除 `Background Downloader Service`；原本器自带的模型文件可通过 `docker compose cp` / `scp` 直传，不再需要 APP 内导。
- **2026-07-17**: **site_scripts 拆 ocr 为两列，番茄场景 list/content OCR 独立判定**。v38→v39 migration 加 `chapter_list_ocr` + `chapter_content_ocr` 两列（INTEGER NOT NULL DEFAULT 0）；旧 `ocr` 列保留不读不写（SQLite < 3.35 不支持 DROP COLUMN，避免 Android < 12 风险）；`SiteScript` 模型 `ocr`/`needsOcr` 字段改为 `chapterListOcr`/`chapterContentOcr`；`SiteScriptRepository.updateScriptPart` 按 `scriptType` 写对应列，`upsertByDomain` 签名改为两个独立参数；`HeadlessWebViewChapterListService` 读 `chapterListOcr`、`HeadlessWebViewContentService` 读 `chapterContentOcr`，互不影响；save_script 工具描述 / buildSystemPrompt / 设计文档去掉"list+content 必须一致"的措辞。修复番茄小说场景：目录页 title/chapter.title 是正常汉字（`chapterListOcr=false`），正文页 content 有 PUA（`chapterContentOcr=true`），分次保存互不覆盖。
- **2026-07-14**: 浏览器桌面/手机模式切换开关。新建 `BrowserSettingsService`（SharedPreferences 持久化 + 桌面 UA 常量）+ `browserDesktopModeProvider`（手写 StateNotifier）；`WebViewControllerNotifier` 加 `applyDesktopMode`（运行时 setSettings + reload）；浏览器 AppBar 改部分溢出菜单（保留后退/前进/刷新 + `⋮` 收纳收藏夹/脚本/模型下载/桌面模式开关）。仅影响用户浏览器 Tab，不动后台 Headless WebView。
- **2026-07-13**: Agent Chat 图片上传。输入栏加 `+` 按钮（相册选图 + image_cropper 1:1 裁剪），复用 `MediaProxy.upload` 注册 `local_` mediaId；`AgentChatSegment` 新增 `ImageSegment` 子类；`ScenarioSession.sendMessage` 加 `imageMediaIds` 参数，mediaId 编码成占位文本 `[用户上传了图片 mediaId=xxx]` 拼进 content 落库；投影层 `_projectUiMessages` 解析占位文本还原 `ImageSegment`（重启可见，无需 DB 迁移）；user 气泡按 segments 渲染遇 `ImageSegment` 走 `MediaView`。新增 `image_picker` 依赖、iOS 相册/相机权限描述。图片作为"素材"供 `create_image_to_video` / `update_character` 等工具使用，不走多模态 LLM 链路。
- **2026-06-29**: DatabaseService 门面彻底删除，所有调用改为直接使用 Repository Provider；删除 PaginationController、repository_providers.dart（合并入 database_providers.dart）等死代码；清理 Dify 残留引用
- **2026-06-11**: 更新文档，移除 Dify 引用，DSL Engine + AI Agent 成为 AI 主力
- **2026-06-09**: 移除 Dify 云端依赖（v1.7.4），仅保留本地 DSL Engine
- **2026-06-05**: DSL Engine 客户端 Dify 工作流复刻（v1.7.0）
- **2026-05-10**: Riverpod 状态管理迁移完成（v1.5.0）
- **2026-02-04**: 完整更新项目架构文档，反映 Riverpod 状态管理、Repository 模式和数据库 v21
- **2025-11-13**: 模块文档初始化，详细描述应用架构和核心功能

## 模块职责

Flutter移动应用是Whimread 平台的前端客户端，提供跨平台的小说阅读体验。主要负责：
- 小说搜索与发现（章节内容搜索，阅读器内）
- 本地书架管理
- 离线阅读体验
- AI增强功能（角色聊天、特写生成）
- 大纲管理（全书大纲、章节细纲）
- 用户偏好设置

## 入口与启动

### 主入口文件
- **路径**: `lib/main.dart`
- **应用类**: `NovelReaderApp`
- **主页**: `HomePage` 底部导航结构

### 应用启动流程
1. **初始化Flutter绑定**: `WidgetsFlutterBinding.ensureInitialized()`
2. **API服务初始化**: `ApiServiceWrapper().init()`
3. **Provider容器初始化**: `UncontrolledProviderScope` 创建 Riverpod 容器
4. **Material3主题设置**: 默认暗色主题
5. **Onboarding 状态分支**: `_AppRoot` 检查 `onboardingNotifierProvider.onboardingCompleted`；首次启动进入 `OnboardingScreen`，完成后进入 `HomePage`（后续可从设置复看 onboarding）
6. **底部导航**（HomePage）: **3 个 Tab** —— 书架（`BookshelfScreen`）/ 浏览器（`WebViewBrowserScreen`）/ 设置（`SettingsScreen`）。**注意**：不存在独立的"生图调试"Tab，相关入口在书架内或通过 debug 屏幕访问。

## 项目架构

### 架构层次

```
┌─────────────────────────────────────────────────────────┐
│                    UI Layer (Screens)                    │
│  ConsumerWidget + Riverpod Watch/Read                   │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│                  State Management (Providers)            │
│  flutter_riverpod + riverpod_annotation                 │
└─────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────┬──────────────────────────────────┐
│  Controller Layer    │         Repository Layer         │
│  业务逻辑协调         │         数据访问层               │
└──────────────────────┴──────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│                   Service Layer                          │
│              网络请求、文件操作、业务服务                  │
└─────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────┬──────────────────────────────────┐
│    SQLite Database   │      Backend API Service         │
│   本地数据存储        │        远程数据服务               │
└──────────────────────┴──────────────────────────────────┘
```

### 目录结构

#### lib/ 目录详解

**核心架构目录**:
- `core/` - 核心架构组件
  - `database/` - 数据库连接与迁移（v1→v39，inline 在 `database_migrations.dart`）
  - `interfaces/` - 接口定义（IDatabaseConnection、I*Repository）
  - `providers/` - Riverpod 状态管理 Providers（40+ 个文件，含 `.g.dart` 派生）
    - `services/` - 服务层 Provider 分类（AI service / core / database / network）
    - `*_providers.dart` - 各业务域 Provider（bookshelf / chapter_list / chapter_search / character / chat_session / agent_chat / agent_scenario / ocr / onboarding / reader_* / relationship_graph / prompt_tag 等）
    - `database_providers.dart` - 数据库连接 + Repository Provider 统一入口

**业务逻辑层**:
- `controllers/` - 控制器层（`lib/controllers/` 下 reader_content + chapter_list/ 子控制器；具体计数以代码为准）
  - `reader_content_controller.dart` - 阅读器内容控制器
  - `chapter_list/` - 章节列表相关控制器
    - `chapter_action_handler.dart` - 章节操作处理器
    - `chapter_reorder_controller.dart` - 章节重排控制器
    - `chapter_loader.dart` - 章节加载器

- `repositories/` - 数据访问层（按 `ls` 实际文件计 13 个 .dart，剔除 `base_repository.dart` 后 12 个 Repository；多用途 Repository 用括号说明合并的实体）
  - `base_repository.dart` - Repository 基类
  - `agent_memory_repository.dart` - Agent 经验记忆数据访问
  - `bookshelf_repository.dart` - 书架分类数据访问（书架 CRUD + 小说-书架多对多）
  - `chapter_repository.dart` - 章节缓存与章节列表元数据访问
  - `chapter_version_repository.dart` - 章节版本历史访问（AI 编辑/重写留档）
  - `character_relation_repository.dart` - 角色关系访问
  - `character_repository.dart` - 角色数据访问（含 v34 `avatar_media_id` / v35 `first_appearance_chapter`）
  - `chat_session_repository.dart` - Agent Chat 会话 / 聊天场景访问（v31，含 `scenarioId` / `currentNovelId`，承接旧 `chat_scenes` 用途）
  - `llm_config_repository.dart` - LLM 配置 CRUD（v29）
  - `novel_repository.dart` - 小说数据访问（含 v36 `coverMediaId`）
  - `outline_repository.dart` - 大纲数据访问（v9）
  - `prompt_tag_category_repository.dart` - 标签分类数据访问（v23）
  - `prompt_tag_repository.dart` - 标签数据访问（v23）
  - `site_script_repository.dart` - 站点提取脚本数据访问（v25+，含 v37 `ocr` / v39 `chapter_list_ocr` + `chapter_content_ocr`）

- `services/` - 业务服务层（48+ 个文件）
  - `chapter_history_service.dart` - 章节历史服务
  - `chapter_search_service.dart` - 章节搜索服务
  - `backup_service.dart` - 备份服务
  - `preferences_service.dart` - 偏好设置服务
  - `reader_settings_service.dart` - 阅读器设置服务
  - `novel_context_service.dart` - 小说上下文服务
  - `llm_config_service.dart` - LLM配置服务
  - `api_service_wrapper.dart` - API服务包装器
  - `dsl_engine/` - DSL Engine 本地工作流引擎
  - `novel_agent/` - AI Agent 智能对话
  - `llm_logger/` - LLM调用日志

**UI层**:
- `screens/` - 完整页面界面（24+ 个 Screen）
- `widgets/` - 可复用 UI 组件（50+ 个 Widget）
- `dialogs/` - 对话框组件（1个对话框）

**辅助层**:
- `models/` - 数据模型（25 个 Model 类）
- `utils/` - 工具类（13个工具类）
- `constants/` - 常量定义
- `config/` - 配置文件
- `mixins/` - Mixin复用代码（1个Mixin）
- `extensions/` - API扩展方法（已删除，功能合并入其他模块）

**生成代码**:
- `generated/` - OpenAPI生成的API客户端代码（70+个文件）

## 状态管理架构

### Riverpod状态管理

应用使用 **Riverpod** 作为状态管理方案，而非文档早期版本的Provider。

### 核心依赖

```yaml
dependencies:
  flutter_riverpod: ^2.4.9        # Riverpod核心
  riverpod_annotation: ^2.3.3     # 注解支持
  equatable: ^2.0.5                # 对象比较

dev_dependencies:
  riverpod_generator: ^2.3.9      # 代码生成器
  riverpod_lint: ^2.3.7           # Lint规则
```

### Provider类型

#### 1. Service Providers (`core/providers/service_providers.dart`)

```dart
// 服务单例Providers
final apiServiceProvider = Provider<ApiServiceWrapper>((ref) {
  return ApiServiceWrapper();
});

final preferencesServiceProvider = Provider<PreferencesService>((ref) {
  return PreferencesService();
});

final loggerServiceProvider = Provider<LoggerService>((ref) {
  return LoggerService.instance;
});
```

#### 2. Repository Providers (`core/providers/database_providers.dart`)

```dart
// Repository Providers（通过DatabaseConnection注入，统一入口）
final databaseConnectionProvider = Provider<IDatabaseConnection>((ref) {
  return DatabaseConnection();
});

final novelRepositoryProvider = Provider<NovelRepository>((ref) {
  final dbConnection = ref.watch(databaseConnectionProvider);
  return NovelRepository(dbConnection: dbConnection);
});

final chapterRepositoryProvider = Provider<ChapterRepository>((ref) {
  final dbConnection = ref.watch(databaseConnectionProvider);
  return ChapterRepository(dbConnection: dbConnection);
});
```

#### 3. StateNotifierProviders（状态管理）

```dart
// 示例：章节列表状态管理
final chapterListProvider = StateNotifierProvider.family<
    ChapterList, ChapterListState, Novel>((ref, novel) {
  return ChapterList(ref, novel);
});

// 使用方式
class ChapterListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chapterListProvider(widget.novel));
    final notifier = ref.read(chapterListProvider(widget.novel).notifier);

    return Scaffold(...);
  }
}
```

### 状态管理模式

- **ConsumerWidget**: 使用 `ref.watch()` 读取状态
- **ConsumerStatefulWidget**: 使用 `ref.watch()` 和 `ref.listen()`
- **StateNotifierProvider**: 可变状态管理
- **Provider**: 不可变服务/依赖
- **FutureProvider**: 异步数据加载
- **StreamProvider**: 流式数据监听

## 对外接口

### API服务层

#### API Service Wrapper
**文件**: `lib/services/api_service_wrapper.dart`

**职责**:
- OpenAPI生成代码的包装器
- 自动初始化和配置
- 统一错误处理
- 认证Token管理

**使用方式**:
```dart
final apiService = ref.watch(apiServiceProvider);
```

### AI集成接口

#### DSL Engine（本地工作流引擎）
**文件**: `lib/services/dsl_engine/`

**功能**:
- 流式AI响应处理
- 特写内容生成
- 角色聊天对话
- 大纲生成辅助

#### AI Agent（LLM 直连对话）
**文件**: `lib/services/novel_agent/`、`lib/core/providers/agent_chat_providers.dart`

**功能**:
- 角色对话（单角色 / 多角色）
- 沉浸式聊天
- 流式输出支持

## 关键依赖与配置

### 核心依赖

#### UI框架与渲染
```yaml
flutter:
  sdk: flutter
flutter_markdown: ^0.6.14    # Markdown渲染
video_player: ^2.8.0          # 视频播放
visibility_detector: ^0.4.0+2 # 可见性检测
```

#### 状态管理
```yaml
flutter_riverpod: ^2.4.9      # Riverpod状态管理
riverpod_annotation: ^2.3.3   # Riverpod注解
equatable: ^2.0.5             # 对象比较
```

#### 网络请求
```yaml
http: ^1.1.0                  # HTTP客户端
dio: ^5.4.0                   # Dio HTTP客户端
```

#### 数据序列化
```yaml
built_value: ^8.9.0           # 不可变值类型
built_collection: ^5.1.1      # 不可变集合
json_annotation: ^4.8.0       # JSON注解
```

#### 数据库与存储
```yaml
sqflite: ^2.3.0               # SQLite数据库
path_provider: ^2.1.1         # 文件路径
shared_preferences: ^2.2.2    # 键值存储
```

#### HTML解析
```yaml
html: ^0.15.4                 # HTML解析
```

#### 图片与媒体
```yaml
image_cropper: ^8.0.2         # 图片裁剪
```

#### 应用功能
```yaml
fluttertoast: ^8.2.4          # Toast消息
permission_handler: ^11.0.0   # 权限请求
package_info_plus: ^8.0.0     # 包信息
```

> 已移除：`background_downloader: ^8.0.0`（2026-07-17 webview 不再下载模型；APP更新仍走 `AppUpdateService` + `Dio.download`）。

#### 图可视化
```yaml
flutter_force_directed_graph: ^1.0.8  # 力导向图
```

#### 加密工具
```yaml
crypto: ^3.0.7                # 加密算法
```

#### OpenAPI生成代码
```yaml
novel_api:
  path: generated/api         # 本地路径依赖
```

### 开发工具依赖

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter

  # Lint规则
  flutter_lints: ^5.0.0

  # 测试依赖
  sqflite_common_ffi: ^2.3.0  # 桌面平台SQLite
  mockito: ^5.4.0             # Mock框架
  coverage: ^1.6.0            # 代码覆盖率
  integration_test:
    sdk: flutter              # 集成测试

  # 代码生成
  build_runner: ^2.4.7        # 代码生成工具
  json_serializable: ^6.7.0   # JSON序列化生成
  built_value_generator: ^8.9.0  # built_value生成

  # Riverpod代码生成
  riverpod_generator: ^2.3.9  # Provider生成器
  riverpod_lint: ^2.3.7       # Riverpod Lint
```

### 配置文件

- **pubspec.yaml** - 项目依赖和配置
- **analysis_options.yaml** - 代码分析配置
- **openapi-config.yaml** - API客户端生成配置
- **dart_test.yaml** - Dart测试配置
- **coverage_config.yaml** - 覆盖率配置

## 数据模型

### Novel模型
**文件**: `lib/models/novel.dart`

```dart
class Novel {
  final String title;              // 小说标题
  final String author;             // 作者
  final String url;                // 小说URL（唯一标识）
  final bool isInBookshelf;        // 是否在书架
  final String? coverUrl;          // 封面URL（旧字段，兼容保留）
  final String? coverMediaId;      // 封面媒体资源 ID（图/视频，v36 新增，走 MediaView，BoxFit.cover 不拉伸）
  final String? description;       // 简介
  final String? backgroundSetting; // 背景设定
}
```

### Chapter模型
**文件**: `lib/models/chapter.dart`

```dart
class Chapter {
  final String title;          // 章节标题
  final String url;            // 章节URL
  final String? content;       // 章节内容
  final bool isCached;         // 是否已缓存
  final int? chapterIndex;     // 章节索引
  final bool isUserInserted;   // 是否用户插入
  final int? readAt;           // 阅读时间戳
  final bool isAccompanied;    // 是否有AI特写

  /// 是否已读
  bool get isRead => readAt != null;
}
```

### Character模型
**文件**: `lib/models/character.dart`

角色数据模型，支持角色管理和多角色聊天。

### ~~SceneIllustration 模型~~（v34 已删）
**状态**: v34 起移除，AI 生成的场景插图统一由 `media_items` 媒体代理承载（见"8. 插图管理"段）。

### Outline模型
**文件**: `lib/models/outline.dart`

```dart
class Outline {
  final int? id;
  final String novelUrl;       // 关联小说URL
  final String title;          // 大纲标题
  final String content;        // 大纲内容（JSON/Markdown）
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ChapterOutlineDraft {
  final String title;          // 章节细纲标题
  final String content;        // 章节细纲内容
  final List<String> keyPoints; // 关键点列表
}
```

### ChatScene模型
**文件**: `lib/models/chat_scene.dart`

聊天场景模型，用于角色对话场景管理。

### CharacterRelationship模型
**文件**: `lib/models/character_relationship.dart`

角色关系模型，支持人物关系图可视化。

### AI模型

#### LlmConfig
**文件**: `lib/models/llm_config.dart`

LLM 配置模型（API URL、Key、模型名称等）。

#### AgentChatMessage
**文件**: `lib/models/agent_chat_message.dart`

AI Agent 对话消息模型。

### 其他模型

- **SearchResult** - 搜索结果封装
- **Bookshelf** - 书架分类模型（id, name, icon, color）
- **RoleGallery** - 角色画廊模型
- **AppVersion** - 应用版本信息

## 数据库设计

### 本地数据库

- **类型**: SQLite
- **版本**: v39
- **文件名**: novel_reader.db
- **位置**: 应用私有目录（通过`path_provider`获取）
- **迁移工具**: inline `_migrateToVersion(int oldVersion, int newVersion)` 在 `lib/core/database/database_migrations.dart`；`currentVersion` 常量统一在同文件 `DatabaseMigrations.currentVersion`（v39）

### 表结构

#### 重要命名说明

- `bookshelf` 表：物理表，存储小说元数据（历史遗留命名）
- `novels` 视图：bookshelf表的别名视图，提供更清晰的语义
- `bookshelves` 表：书架分类表（注意复数形式）
- `Bookshelf` 模型：书架分类功能（id, name, icon, color）

#### 物理表列表

1. **bookshelf** (小说表，v1+ ; v3 `background_setting` ; v36 `coverMediaId`)
   - 存储小说元数据、阅读进度
   - 字段：id, title, author, url, coverUrl, coverMediaId, description, background_setting
   - 索引：url（唯一）、last_read_at、is_in_bookshelf
   - coverMediaId（v36 新增）存 set_novel_cover 工具写入的 mediaId，NovelCover 命中走 MediaView 渲染（图/视频，BoxFit.cover 不拉伸）

2. **bookshelves** (书架分类表，v16)
   - 书架分类功能（如"我的收藏"、"玄幻小说"）
   - 字段：id, name, icon, color, created_at

3. **novel_bookshelves** (小说-书架关联表，v16)
   - 多对多关系表
   - 字段：novel_url, bookshelf_id
   - 支持一本小说属于多个书架

4. **chapter_cache** (章节内容缓存，v1+ ; v18 `isAccompanied`)
   - 章节内容、索引、缓存时间
   - 字段：id, novel_url, chapter_url, title, content, chapter_index, cached_at
   - 特性：支持 `isUserInserted` 章节保护、`isAccompanied` 标记是否带 AI 特写

5. **novel_chapters** (章节列表元数据，v1+ ; v2 `is_user_inserted` ; v11 `read_at` ; v18 `is_accompanied`)
   - 章节索引自动管理
   - 字段：id, novel_url, title, url, chapter_index, is_user_inserted, read_at, is_accompanied

6. **characters** (角色表，v1+ ; v5 `face_prompts` ; v6 `cached_image_url` ; v12 `aliases` ; v34 `avatar_media_id` ; v35 `first_appearance_chapter`)
   - 角色基本信息和头像
   - 字段：id, novel_url, name, avatar_url, avatar_media_id, description, face_prompts, aliases, first_appearance_chapter

7. **character_relationships** (角色关系表，v13+ ; v35 区间模型重建)
   - 人物关系图数据
   - 字段：id, novel_url, character1_name, character2_name, relationship_type

8. **outlines** (大纲表，v9)
   - 小说全书大纲
   - 字段：id, novel_url, title, content, created_at, updated_at

9. **chat_scenes** (聊天场景表，v10 — 与 chat_sessions 不同)
   - 角色对话场景
   - 字段：id, title, characters_json, created_at

10. **chat_sessions** (Agent Chat 会话表，v31)
    - 字段含 `scenarioId` / `currentNovelId`，区分 scenario 与 novel 上下文

11. **chat_messages** (Agent Chat 消息表，v31-32)
    - 字段含 `toolCallsJson` / `toolCallId` / `agentMsgIndex`

12. **media_items** (统一媒体代理表，v34)
    - mediaId / kind / source / local_only
    - 承接旧 `scene_illustrations` 与角色头像二进制，统一走 MediaProxy + MediaView

13. **prompt_history** (提示词历史表，v22 ; v26 `tag_group_ids`)

14. **prompt_tag_categories** (标签分类表，v23)

15. **prompt_tags** (标签表，v23 ; v24 约束重建 ; v28 `reason`)

16. **agent_memory** (Agent 经验记忆表，v27)

17. **prompt_tag_history** (标签变更历史表，v28)

18. **llm_configs** (LLM 配置表，v29)
    - API URL / Key / 模型名称 CRUD

19. **chapter_versions** (章节版本历史表，v30)
    - AI 编辑/重写留档

20. **site_scripts** (站点提取脚本表，v25+ ; v37 `ocr` ; v39 加 `chapter_list_ocr` + `chapter_content_ocr` 两列)
    - 番茄字体反爬场景：目录页正常汉字 → `chapterListOcr=false`、正文页 PUA → `chapterContentOcr=true`，分次保存互不覆盖
    - 旧 `ocr` 列保留不读不写（SQLite < 3.35 不支持 DROP COLUMN，避免 Android < 12 风险）

**已删除表**:
- `scene_illustrations`（v34 删除，由 `media_items` 替代）
- `model_download_tasks`（v38 删除，webview 不再下载模型，2026-07-17）
- 后端 `novel_cache_tasks` / `novel_chapters_cache` / `chapter_list_cache`（2026-07-08 由后端迁移删除，前端不再相关）

#### 逻辑视图

- **novels**: bookshelf表的别名视图
  - 推荐新代码使用此视图进行查询
  - 保持数据兼容性

### 数据库连接

**接口**: `lib/core/interfaces/i_database_connection.dart`

**实现**: `lib/core/database/database_connection.dart`

```dart
class DatabaseConnection implements IDatabaseConnection {
  @override
  Future<Database> get database async {
    // 单例模式，返回SQLite实例
    // 版本: v39（DatabaseMigrations.currentVersion）
    // onCreate: 创建所有表
    // onUpgrade: 委托 DatabaseMigrations._migrateToVersion
  }
}
```

### Repository模式

**架构说明**:

所有数据库操作通过专门的 Repository 类完成，Repository Provider 统一在 `database_providers.dart` 中注册。DatabaseService 门面类已删除，所有调用点改为直接使用 Repository Provider。

#### Repository层列表

**文件**: `lib/repositories/`（按 `ls` 实际文件；详见上文目录结构中的清单）

1. **base_repository.dart** - Repository基类
   - 定义通用数据库操作接口
   - 提供事务处理方法

2. **novel_repository.dart** - 小说Repository
   - CRUD操作
   - 阅读进度更新
   - 书架状态管理（v36 `coverMediaId` 写入由 set_novel_cover 工具触发）

3. **chapter_repository.dart** - 章节Repository
   - 章节缓存管理
   - 章节列表维护
   - 用户插入章节保护（`is_user_inserted`）

4. **character_repository.dart** - 角色Repository
   - 角色信息管理
   - 角色头像存储（v34 `avatar_media_id` 走 MediaProxy）

5. **character_relation_repository.dart** - 角色关系Repository
   - 关系图数据管理（v35 区间模型重建）
   - 关系查询和更新

6. **outline_repository.dart** - 大纲Repository
   - 全书大纲CRUD
   - 大纲版本管理

7. **bookshelf_repository.dart** - 书架分类Repository
   - 书架分类CRUD
   - 小说-书架关联管理

8. **chat_session_repository.dart** - Agent Chat 会话/聊天场景 Repository（v31）
   - 会话与场景管理（`scenarioId` / `currentNovelId`）
   - 承接旧 `chat_scenes` 用途

9. **llm_config_repository.dart** - LLM 配置 Repository（v29）
   - API URL / Key / 模型名称 CRUD

10. **agent_memory_repository.dart** - Agent 经验记忆 Repository（v27）
    - 跨会话记忆持久化

11. **chapter_version_repository.dart** - 章节版本历史 Repository（v30）
    - AI 编辑/重写留档

12. **prompt_tag_repository.dart** / **prompt_tag_category_repository.dart** - 标签 + 分类 Repository（v23/24/28）
    - 写作标签库 CRUD

13. **site_script_repository.dart** - 站点提取脚本 Repository（v25+ → v39）
    - `chapterListOcr` / `chapterContentOcr` 两列独立判定（2026-07-17）

#### 使用方式

**推荐方式（Riverpod Providers）**:
```dart
class NovelListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(novelRepositoryProvider);

    return FutureBuilder(
      future: repository.getNovelsInBookshelf(),
      builder: (context, snapshot) {
        // ...
      },
    );
  }
}
```

## 核心功能

### 1. 书架管理

**Screen**: `lib/screens/bookshelf_screen.dart`

**功能**:
- 小说收藏与管理
- 阅读进度跟踪
- 书架分类（多个书架）
- 批量操作（删除、移动）

**状态管理**: `core/providers/bookshelf_providers.dart`

**数据存储**: 本地SQLite

### 2. 章节内容搜索

**Screen**: 阅读器内 `chapter_search_screen.dart`

**Service**:
- `chapter_search_service.dart` - 章节内容搜索

**Provider**: `core/providers/chapter_search_providers.dart`

**支持**: 已缓存章节内容全文搜索、搜索结果高亮定位

### 3. 章节列表

**Screen**: `lib/screens/chapter_list_screen_riverpod.dart`

**Controller**:
- `chapter_list/chapter_action_handler.dart` - 章节操作
- `chapter_list/chapter_reorder_controller.dart` - 章节重排
- `chapter_list/chapter_loader.dart` - 章节加载

**Provider**: `core/providers/chapter_list_providers.dart`

**功能**:
- 章节列表展示（分页，每页100章）
- 自动滚动到上次阅读位置
- 章节重排序
- 大纲集成显示
- 章节搜索和过滤

**Bug修复**:
- ✅ 异步加载时序问题已修复（使用-1作为未加载默认值）

### 4. 阅读体验

**Screen**: `lib/screens/reader_screen.dart`

**Controller**:
- `reader_content_controller.dart` - 内容管理

**Provider**: `core/providers/reader_state_providers.dart`、`core/providers/reader_settings_state.dart`

**功能**:
- 章节阅读（段落式渲染）
- AI特写生成
- 场景插图请求
- 阅读进度自动保存
- 编辑模式（段落改写、删除）

**特色**:
- 支持用户插入章节保护
- 自动滚动控制（`mixins/reader/auto_scroll_mixin.dart`）
- 流式AI响应显示

### 5. 角色管理

**Widget**: `lib/widgets/agent_chat/` - Agent 对话组件（支持角色对话场景）

**Repository**: `character_repository.dart`, `character_relation_repository.dart`

**功能**:
- 角色信息管理
- 角色头像（AI生成/自定义）
- 角色关系可视化（力导向图）
- 多角色对话（通过 AI Agent）

### 6. 大纲管理

**Repository**: `outline_repository.dart`

**功能**:
- 全书大纲生成（AI辅助）
- 章节细纲草稿
- 大纲与章节集成

### 7. 设置管理

**Screen**: `lib/screens/settings_screen.dart`

**子页面**:
- `prompt_tag_management_screen.dart` - 提示词标签管理
- `agent_memory_management_screen.dart` - Agent 记忆管理
- `log_report_settings_screen.dart` - 日志上报设置
- `log_viewer_screen.dart` - 日志查看
- `preload_queue_debug_screen.dart` - 预加载队列调试

**存储**: SharedPreferences

**功能**:
- 阅读设置(字体、字号、行间距)
- 主题设置
- Agent 提示词 / 记忆管理
- 检查 APP 更新(后端为主,GitHub Release 兜底)

### 8. 插图管理

**说明**: 旧 `illustration_repository.dart` 与 `scene_illustrations` 表已于 v34（media_items 引入时）移除，现统一走 `MediaProxy` + `media_items` 表 + `NovelCover` / `MediaView` 渲染。

**功能**:
- AI 文生图（Agent 工具 `create_images`，走后端 ComfyUI 出图）
- 小说封面媒体化（v36 `coverMediaId`，`NovelCover` 命中走 `MediaView`）
- 角色头像镜像媒体化（v34 `avatar_media_id`）

### 9. 备份与恢复

**Service**: `lib/services/backup_service.dart`

**功能**:
- 数据库备份
- 恢复功能
- 备份文件管理

## 缓存系统

### 章节内容缓存

**本地SQLite**:
- 表：`chapter_cache` / `novel_chapters`
- Repository: `ChapterRepository`
- 特性：用户插入章节保护（`is_user_inserted`）、`is_accompanied` 标记是否带 AI 特写

**后端兜底已移除**（2026-07-08）：`/api/cache/*` 等服务端接口已删除，前端不再依赖服务端缓存。如需重新跨设备同步，使用备份（`lib/services/backup_service.dart`）+ 后端 `/api/backup/upload|list|download` 链路。

### 缓存策略

- **章节内容**: 本地 SQLite（`chapter_cache` 表，无服务端兜底）
- **搜索结果**: 内存缓存
- **图片资源**: 文件系统缓存（`utils/image_cache_manager.dart`，写穿 `media_items`）
- **视频资源**: 文件系统缓存（`utils/video_cache_manager.dart`，写穿 `media_items`）

### 缓存相关服务

- `chapter_history_service.dart` - 章节缓存协调
- `preload_service.dart` - 预加载服务

## AI集成功能

### DSL Engine（本地 LLM 工作流引擎）

**核心组件** (`lib/services/dsl_engine/`):
- `llm_provider.dart` / `llm_provider_client.dart` / `llm_provider_config.dart` / `llm_provider_core.dart` / `llm_provider_sse.dart` - OpenAI 兼容的 LLM 调用
- `retry_signals.dart` - LLM 重试 UI 信号（2026-07-18 重构：`RetrySignals` 模块级单例 + `categorizeRetryError` 共享工具）

**说明**: DSL Engine 已与 Dify 完全解耦（2026-06-09 移除 Dify 云端依赖；2026-06-29 清理 Dify 残留引用）。当前仅保留 LLM 调用核心；结构化工作流能力迁移至 AI Agent（`lib/services/novel_agent/`）。

**用途**:
- 创意写作（段落重写、全文重写）
- 章节/背景摘要生成
- 场景插图提示词生成
- 统一错误重试（`withRetry` / `RetrySignals`）

**配置** (设置 → AI 配置):
- LLM API URL（OpenAI 兼容地址）
- LLM API Key
- 默认模型（可选）

### AI Agent（LLM 直连对话）

**核心组件**:
- `lib/core/providers/agent_chat_providers.dart` - Riverpod Provider
- `lib/widgets/agent_chat/` - 对话 UI 组件
- `lib/services/novel_agent/` - Agent 执行引擎（agent_loop、agent_scenario 等）

**用途**:
- 角色对话（单角色 / 多角色）
- 沉浸式聊天
- 流式输出支持
- AI 续写/重写章节（`create_chapter` / `update_chapter_content` 工具，组合"修改要求 + 人物卡 + 写作标签 + AI 作家设定"调 LLM）
- AI 文生图（`list_text2img_models` + `create_images` 工具，调后端 ComfyUI 出图）
  - `create_images` 参数: `prompt`(必填) / `negativePrompt`(可选) / `count`(1-4) / `modelName`
  - `list_text2img_models` 返回 `promptSkill` 字段供 LLM 撰写针对性提示词
  - 这两个工具始终由 `WritingScenario` 注入 LLM；后端/ComfyUI 不可用时由 tool_executor 返回错误消息引导用户修复

**兼容层**:
- `AgentChatNotifier` 保留为兼容层（仍被测试使用），`agent_chat_dialog.dart` 的写入路径已改为直接使用 ScenarioSession

### AI相关Widget

- `widgets/streaming_content_display.dart` - 流式内容显示
- `widgets/streaming_status_indicator.dart` - 状态指示器

## 控制器层

### Controller职责

Controller负责协调业务逻辑，连接UI层和数据层。

### Controller列表

**文件位置**: `lib/controllers/`

1. **reader_content_controller.dart** - 阅读器内容控制器
   - 章节内容管理
   - 段落渲染控制
   - 编辑模式切换

2. **chapter_list/chapter_action_handler.dart** - 章节操作处理器
   - 章节删除、缓存等操作
   - 批量操作支持

3. **chapter_list/chapter_reorder_controller.dart** - 章节重排控制器
   - 拖拽重排序
   - 重排序状态管理

4. **chapter_list/chapter_loader.dart** - 章节加载器
   - 章节列表加载
   - 最后阅读位置加载

## Mixins

### Mixin列表

**文件位置**: `lib/mixins/`

1. **reader/auto_scroll_mixin.dart** - 阅读器自动滚动Mixin
   - 自动滚动控制
   - 滚动速度调节

## 扩展方法

**说明**: `lib/extensions/` 目录已删除，API 模型转换功能已合并入其他模块。

## 测试与质量

### 测试结构

**test/** 目录:

```
test/
├── helpers/              # 测试辅助工具
├── mocks/               # Mock对象
├── factories/           # 测试数据工厂
├── unit/                # 单元测试
│   ├── repositories/    # Repository测试
│   ├── services/        # Service测试
│   ├── providers/       # Provider测试
│   ├── screens/         # Screen测试
│   └── widgets/         # Widget测试
├── bug/                 # Bug修复验证测试
├── verification/        # 功能验证测试
├── experiments/         # 实验性测试
└── reports/             # 测试报告
```

### 主要测试文件

- `test/widget_test.dart` - 主测试文件
- `test/unit/screens/chapter_list_auto_scroll_test.dart` - 自动滚动测试（23个用例）
- `test/unit/screens/chapter_list_scroll_bug_verification_test.dart` - Bug验证测试（7个用例）

### 测试配置

- `dart_test.yaml` - Dart测试配置
- `coverage_config.yaml` - 覆盖率配置
- `playwright.config.ts` - E2E测试配置（Playwright集成）

### 代码质量

**静态分析**:
```bash
flutter analyze                    # 代码分析
flutter analyze --no-fatal-infos   # 严格模式
```

**代码格式化**:
```bash
flutter format lib/                # 格式化代码
flutter format --set-exit-if-changed lib/  # CI检查
```

**依赖管理**:
```bash
flutter pub get                    # 获取依赖
flutter pub upgrade               # 升级依赖
flutter pub outdated              # 检查过时依赖
```

### 开发工具

**API生成**:
```bash
# 生成OpenAPI客户端代码
dart run tool/generate_api.dart
flutter pub get
```

**数据库工具**:
```bash
# 清理测试数据库
dart run tool/clean_test_database.dart

# 强制重建数据库
dart run tool/force_rebuild_database.dart
```

**Python迁移脚本**:
- `tool/migrate_database_log.py` - 数据库日志迁移
- `tool/migrate_dify_log.py` - Dify日志迁移
- `tool/migrate_api_log.py` - API日志迁移
- `tool/fix_logger_calls.py` - 修复Logger调用
- `tool/fix_screen_toast_calls.py` - 修复Screen Toast调用
- `tool/extract_repository.py` - 提取Repository代码
- `tool/fix_import_paths.py` - 修复导入路径

## 构建与部署

### 构建配置

```bash
# Android
flutter build apk                              # APK调试版
flutter build apk --release                    # APK发布版
flutter build appbundle --release              # App Bundle（Google Play）

# Windows
flutter build windows                          # Windows可执行文件

# iOS (仅macOS)
flutter build ios                              # iOS应用
flutter build ios --release                    # iOS发布版

# Web（实验性）
flutter build web                              # Web应用
```

### 平台支持

| 平台 | 支持状态 | 说明 |
|------|---------|------|
| Android | ✅ 完整支持 | APK + App Bundle |
| iOS | ✅ 支持开发 | 需要macOS开发环境 |
| Windows | ✅ 支持开发 | 桌面应用（SQLite FFI） |
| Web | ⚠️ 实验性 | sqflite不支持，需替代方案 |

### 版本管理

**当前版本**: 2.0.2-preview.2+111

**版本号规则**: `major.minor.patch+build`

## 常见问题 (FAQ)

### Q: 如何解决API连接失败？

**A**: 检查以下项目：
1. 后端服务是否运行（`http://localhost:3800`）
2. 在设置页面重新配置API地址
3. 检查API Token是否正确
4. 查看日志：`lib/screens/log_viewer_screen.dart`

### Q: 用户插入章节如何保护？

**A**: 数据库操作中 `isUserInserted=1` 的章节：
- 不会被自动删除
- 不会被爬虫更新
- 保留用户编辑内容

### Q: 如何更新API客户端代码？

**A**:
```bash
# 1. 确保后端服务运行
# 2. 运行生成工具
dart run tool/generate_api.dart

# 3. 更新依赖
flutter pub get

# 4. 验证生成代码
flutter analyze lib/generated/api/
```

### Q: Riverpod vs Provider，应该用哪个？

**A**: **使用Riverpod**。
- ✅ 项目已迁移到Riverpod（`flutter_riverpod: ^2.4.9`）
- ❌ Provider已弃用（`pubspec.yaml`中已注释）
- 使用 `ConsumerWidget` + `ref.watch()`
- 查看 `lib/core/providers/` 了解Provider定义

### Q: 如何添加新的Repository？

**A**:
1. 创建 `lib/repositories/your_repository.dart`
2. 继承 `BaseRepository`
3. 注入 `IDatabaseConnection`
4. 在 `lib/core/providers/database_providers.dart` 中添加Provider
5. 使用 `ref.watch(yourRepositoryProvider)` 访问

### Q: 数据库版本如何升级？

**A**:
1. 修改 `lib/core/database/database_connection.dart` 中的版本号
2. 在 `_onUpgrade()` 方法中添加迁移逻辑
3. 测试数据库迁移
4. 更新文档中的版本号

## 相关文件清单

### 核心文件

**应用入口**:
- `lib/main.dart` - 应用入口

**架构层**:
- `lib/core/providers/` - Riverpod 状态管理（40+ 个文件，含派生）
- `lib/repositories/` - 数据访问层（12 个 Repository + base_repository；按 `ls` 实际文件）
- `lib/controllers/` - 控制器层（`lib/controllers/` 下 reader_content + chapter_list/ 子控制器；具体计数以代码为准）
- `lib/services/` - 业务服务层（48+ 个 Service）

**UI层**:
- `lib/screens/` - 完整页面（24+ 个 Screen）
- `lib/widgets/` - UI 组件（50+ 个 Widget）
- `lib/dialogs/` - 对话框（1 个 Dialog）

**数据层**:
- `lib/models/` - 数据模型（25 个 Model）
- `lib/core/database/` - 数据库连接
- `lib/core/interfaces/` - 接口定义

**工具层**:
- `lib/utils/` - 工具类（13个工具）
- `lib/constants/` - 常量定义
- `lib/config/` - 配置文件

**复用代码**:
- `lib/mixins/` - Mixin（1个）

### 配置文件

- `pubspec.yaml` - 项目配置和依赖
- `analysis_options.yaml` - 代码分析规则
- `.gitignore` - Git忽略规则
- `dart_test.yaml` - Dart测试配置
- `coverage_config.yaml` - 覆盖率配置
- `openapi-config.yaml` - API生成配置

### 工具和脚本

**Dart工具**:
- `tool/generate_api.dart` - API代码生成
- `tool/clean_test_database.dart` - 清理测试数据库
- `tool/force_rebuild_database.dart` - 重建数据库

**Python脚本**:
- `tool/migrate_database_log.py` - 数据库日志迁移
- `tool/migrate_dify_log.py` - Dify日志迁移
- `tool/migrate_api_log.py` - API日志迁移
- `tool/fix_logger_calls.py` - 修复Logger调用
- `tool/fix_screen_toast_calls.py` - 修复Toast调用
- `tool/extract_repository.py` - 提取Repository
- `tool/fix_import_paths.py` - 修复导入路径

**Shell脚本**:
- `tool/fix_logger_error_param.sh` - 修复Logger错误参数

### 测试文件

- `test/widget_test.dart` - 主测试文件
- `test/helpers/` - 测试辅助工具
- `test/mocks/` - Mock对象
- `test/factories/` - 测试数据工厂
- `test/unit/` - 单元测试（repositories, services, providers, screens, widgets）
- `test/bug/` - Bug修复验证
- `test/verification/` - 功能验证
- `test/reports/` - 测试报告

### 构建产物

- `build/` - 构建输出（忽略提交）
- `lib/generated/` - API生成代码（忽略提交）

### 平台配置

- `android/` - Android平台配置
- `windows/` - Windows平台配置
- `ios/` - iOS平台配置
- `web/` - Web平台配置

## 开发工作流

### 新功能开发

1. **创建功能分支**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **更新数据模型**（如需要）
   - 修改/创建 `lib/models/your_model.dart`
   - 运行 `dart run build_runner build` 生成代码

3. **创建Repository**（如需要）
   - 创建 `lib/repositories/your_repository.dart`
   - 继承 `BaseRepository`
   - 在 `database_providers.dart` 中注册Provider

4. **创建Service**（如需要）
   - 创建 `lib/services/your_service.dart`
   - 在 `service_providers.dart` 中注册Provider

5. **创建Controller**（如需要）
   - 创建 `lib/controllers/your_controller.dart`
   - 协调业务逻辑

6. **编写UI界面**
   - 创建 `lib/screens/your_screen.dart`
   - 使用 `ConsumerWidget` 或 `ConsumerStatefulWidget`
   - 使用 `ref.watch()` 读取状态
   - 使用 `ref.read()` 调用方法

7. **添加测试用例**
   - 单元测试：`test/unit/your_test.dart`
   - Widget测试：`test/widgets/your_widget_test.dart`
   - 运行 `flutter test`

8. **运行代码检查**
   ```bash
   flutter analyze
   flutter format lib/
   flutter test
   ```

9. **提交代码审查**
   ```bash
   git add .
   git commit -m "feat: add your feature"
   git push origin feature/your-feature-name
   ```

### API集成更新

1. **确保后端服务运行**
   ```bash
   # 启动后端服务
   cd ../backend
   python -m uvicorn app.main:app --reload
   ```

2. **重新生成API客户端**
   ```bash
   dart run tool/generate_api.dart
   flutter pub get
   ```

3. **更新API包装器**（如需要）
   - 修改 `lib/services/api_service_wrapper.dart`
   - 适配新的API变更

4. **添加转换方法**（如需要）
   - 在 API 模型类中添加便捷转换方法
   - 方便API模型转换

5. **测试集成功能**
   - 单元测试：Mock API响应
   - 集成测试：连接真实API
   - E2E测试：Playwright自动化

6. **验证错误处理**
   - 网络错误
   - API错误响应
   - 数据解析错误

### 数据库变更

1. **更新Repository**
   - 修改对应的Repository类
   - 添加新方法或字段

2. **添加迁移逻辑**
   ```dart
   // lib/core/database/database_connection.dart
   Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
     if (oldVersion < 22) {
       // 添加新表或修改表结构
       await db.execute('ALTER TABLE xxx ADD COLUMN yyy TEXT');
     }
   }
   ```

3. **更新数据库版本**
   ```dart
   version: 22, // 增加版本号
   ```

4. **测试数据兼容性**
   - 测试从旧版本升级
   - 验证数据迁移正确性

5. **更新模型定义**
   - 修改 `lib/models/your_model.dart`
   - 确保与数据库表结构匹配

6. **验证回滚机制**
   - 测试降级场景
   - 确保不丢失数据

### Riverpod Provider开发

1. **定义状态类**
   ```dart
   class YourState {
     final bool isLoading;
     final List<Item> items;
     final String? error;

     const YourState({
       this.isLoading = false,
       this.items = const [],
       this.error,
     });

     YourState copyWith({...}) => ...;
   }
   ```

2. **创建StateNotifier**
   ```dart
   class YourNotifier extends StateNotifier<YourState> {
     YourNotifier(this.ref) : super(const YourState());

     final Ref ref;

     Future<void> loadData() async {
       state = state.copyWith(isLoading: true);
       try {
         final repository = ref.watch(yourRepositoryProvider);
         final items = await repository.getItems();
         state = state.copyWith(items: items, isLoading: false);
       } catch (e) {
         state = state.copyWith(error: e.toString(), isLoading: false);
       }
     }
   }
   ```

3. **创建Provider**
   ```dart
   final yourProvider = StateNotifierProvider.family<YourNotifier, YourState, String>(
     (ref, id) => YourNotifier(ref),
   );
   ```

4. **使用Provider**
   ```dart
   class YourScreen extends ConsumerWidget {
     @override
     Widget build(BuildContext context, WidgetRef ref) {
       final state = ref.watch(yourProvider('id'));
       final notifier = ref.read(yourProvider('id').notifier);

       return Scaffold(
         body: state.isLoading
           ? CircularProgressIndicator()
           : ListView.builder(
               itemCount: state.items.length,
               itemBuilder: (context, index) => ...,
             ),
       );
     }
   }
   ```

5. **生成代码**（使用注解时）
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

### Bug修复流程

1. **创建Bug分支**
   ```bash
   git checkout -b fix/bug-name
   ```

2. **编写测试用例**
   - 在 `test/bug/` 中创建复现测试
   - 在 `test/unit/` 中编写修复验证测试

3. **修复Bug**
   - 修改相关代码
   - 运行测试验证

4. **更新文档**（如需要）
   - 在 `test/reports/` 中添加Bug报告
   - 更新CLAUDE.md

5. **提交修复**
   ```bash
   git add .
   git commit -m "fix: resolve bug-name"
   git push origin fix/bug-name
   ```

## 架构演进历史

### Phase 1: 初始架构
- Provider状态管理
- DatabaseService单例（已删除，改为 Repository Provider 直连）
- 紧耦合的Service层

### Phase 2: 代码质量改进（当前）
- ✅ 迁移到Riverpod状态管理
- ✅ 引入Repository模式
- ✅ DatabaseConnection接口化
- ✅ Controller层解耦
- ✅ 依赖注入通过Providers
- ✅ DatabaseService门面删除，全部改为 Repository Provider
- ✅ Dify云端链路完全删除，DSL Engine + AI Agent 成为主力

### 未来计划
- 添加更多集成测试
- 优化性能和内存使用
- 增强错误处理和日志
- 改进离线功能

## 参考资源

### 官方文档
- [Flutter Documentation](https://flutter.dev/docs)
- [Riverpod Documentation](https://riverpod.dev)
- [sqflite Documentation](https://pub.dev/packages/sqflite)

### 内部文档
- 根目录CLAUDE.md - 项目总览
- backend/CLAUDE.md - 后端服务文档

### 测试报告
- `test/reports/chapter_list_auto_scroll_test_report.md` - 自动滚动测试报告
- `test/reports/chapter_list_scroll_bug_report.md` - Bug分析报告

---

**文档维护**: 本文档应随代码变更同步更新
**最后更新**: 2026-07-27
**文档状态**: 🔄 已同步现状（2026-07-27 文档系统梳理）
