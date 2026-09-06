# Whimread (随心阅读) - 全栈小说阅读平台

## 变更记录 (Changelog)

- **2026-09-04**: **修复 OCR OnnxValue native 内存泄露 + 清理 deprecated PoC 路径**。读 `flutter_onnxruntime-1.8.3` Android 源码确认 `FlutterOnnxruntimePlugin` 维护插件级 `ortValues = ConcurrentHashMap<String, OnnxValue>` 注册表（L143），`runInference` 每次把 output tensor 写入（L452）从不删除，`closeSession`（L477-496）也不清空，`releaseOrtValue`（L1152）是唯一清理入口。`OcrPredictor.recognizeImage` 从不 dispose → 每字 ~634KB native 内存永久驻留（番茄场景每章 200+ PUA ≈ 127MB/章，读几章即逼近 native heap 上限）。三个问题一起修：(1) **P0** `recognizeImage` 内 input + 全部 outputs 在 finally 中显式 `dispose`，run 抛异常路径同样覆盖（outputs 兜底 `const {}` 防未赋值）；(2) **P1** `load()` 声称可重复热重载但从不关旧 session → 重建前先 `close`，防 native sessions 注册表驻留旧 OrtSession + 10MB 模型 buffer；(3) **P2** 删除 deprecated `recognizeGlyph` PoC 入口与 `_render`（`PictureRecorder`/`ui.Image` 三件套 GPU 纹理不释放，CLAUDE.md 2026-07-15 条目明确"Task 15 清理时移除"未做），构造器瘦身无参 + 移除 `family`/`fontSize`/`canvasSize` 字段与 `material.dart` import，`main_ppocr_demo.dart` 改为本地 TextPainter 渲染 base64 PNG 走产品 `recognizeImage` 入口；测试侧新增 `test/unit/services/ocr_predictor_dispose_test.dart`（mock `flutter_onnxruntime` MethodChannel 计数句柄生命周期，3 用例覆盖 P0 成功/异常 + P1），`ocr_predictor_test.dart` 改反向断言（"源文件不含 recognizeGlyph" + "无 @Deprecated"）。两个独立 commit：`fix(ocr)` 含 P0+P1+新测试、`refactor(ocr)` 含 P2+demo+测试更新。详见 plan `docs/superpowers/plans/2026-09-04-ocr-ortvalue-leak.md`。analyze 0 告警（除 `main_pua_ocr_diag.dart` 1 个存量 dangling doc comment，本 PR 不在范围），OCR 相关测试 14/14 全绿。
- **2026-08-05**: **修复"全部小说"书架移动图书失败 + 合并冗余菜单**。`BookshelfRepository.moveNovelToBookshelf` 在 `from=1`(虚拟书架"全部小说")时从抛 `ArgumentError` 改为 add-only 降级;`BookshelfScreen._showNovelMenu` 在 `currentBookshelfId==1` 时把"移动到书架"和"复制到书架"两条菜单合并为单一"加入书架"入口(走 `copyToBookshelf`,UI 文案诚实表达"书仍留在全部小说")。`_showBookshelfSelectionDialog` 新增 `mode='join'` 分支。详见 spec `docs/superpowers/specs/2026-08-05-all-novels-bookshelf-join-design.md` + plan `docs/superpowers/plans/2026-08-05-all-novels-bookshelf-join.md`。
- **2026-08-05**: **修复应用日志「全部级别」/「全部分类」按钮失效**。根因：Flutter `PopupMenuItem` 文档明确 "If itemBuilder returns an item with a null value, the item will not be selectable." —— 原代码两个过滤菜单的"全部"项用 `value: null`，framework 故意吞掉点击、`onSelected` 不触发，表现为"点了没反应、列表仍是当前过滤结果"。修复：`log_viewer_screen.dart` 顶部加文件级 `const Object _kNoFilterSentinel = Object()`，两个 `PopupMenuButton<T?>` 改 `PopupMenuButton<Object?>`，菜单项的"全部"项 `value: _kNoFilterSentinel`，`onSelected` 用 `identical(v, _kNoFilterSentinel)` 判别还原成 nullable。回归测试：`test/unit/screens/log_viewer_filter_menu_test.dart`(3 个 widget test 端到端验证点"全部级别/全部分类"能清掉当前过滤 + 对照点具体级别项能切换) + `test/bug/log_viewer_all_level_button_repro_test.dart`(framework 行为对比，证坏实现 + 证好实现)。analyze 0 告警，2 个测试文件 5 个 case 全绿。
- **2026-07-30**: **README + 落地页强化「越用越懂你」卖点**。原 README 第 76 行单 bullet「🧠 越用越懂你」升级为独立子模块，三大支撑点写清：① 🏷️ 写作标签库（`prompt_tags` 全局共享 + 同名变体随机抽，`chapter_write_executor.dart:441-454`）② 🧠 经验记忆（`agent_memory` 跨会话跨书 + LLM 主动 `patch_memory` 写入 +「设置 → Agent 记忆管理」可手改，**非自动埋点推荐**）③ ✍️ AI 作家设定（SharedPreferences `ai_writer_prompt` 每章套用，`chapter_write_executor.dart:411-415`）。诚实边界写入技术细节折叠区：所有 Repository 按 `novelUrl` 过滤无跨书章节正文自动学习机制，"借鉴其他小说技巧"= 用户主动整理素材（角色 / 大纲 / 标签 / 风格 / 记忆）→ AI 弹药库越攒越满。落地页 `docs-site/index.html` 新增独立 `smart` section（标签库 / 经验记忆 / AI 作家设定三栏卡片 + 金句 quote 区），导航加「越用越懂你」锚点；下载版本号同步从 v2.0.1 升到 v2.0.2。
- **2026-07-29**: **章节写入收口 ChapterMutationNotifier(根治 agent 写章节不刷新 bug)**。仿 `BookshelfMutationNotifier` 模式，把 4 个 agent 工具(`createChapter` / `updateChapterContent` / `rewriteChapterContent` / `deleteChapter`)+ `reader_screen._saveEditedContent` + `reader_screen._loadChapterContent` (markChapterAsRead) + `reader_content_controller.cacheChapter` + `version_history_sheet._confirmRestore` + `chapter_loader.refreshFromBackend` + `webview_add_novel_button._saveChapters` + `chapter_list_providers.clearCache` + `chapter_list_screen._insertChapter/_deleteChapter` 共 **11 处**直接调 `IChapterRepository` 写库的路径，全部收敛到 `ChapterMutationNotifier`(8 个公共方法：`updateChapterContent` / `deleteCachedChapters` / `createChapter` / `deleteChapter` / `cacheNovelChapters` / `cacheChapter` / `updateChaptersOrder` / `markChapterAsRead`，每个走统一 `_wrap`：写库 → bump signal，失败不 bump)。`IChapterRepository` 接口脱钩 12 个写方法(迁到内部 `IChapterWriter`，定义在 `chapter_repository.dart` 文件内)，`ChapterRepository implements IChapterRepository, IChapterWriter`；新增 `chapterWriterProvider`(仅 ChapterMutationNotifier 用，cast 拿能力，**编译期阻止普通调用方写库**)。新增 ChapterRepository 层事务方法 `createCustomChapterWithShift` / `deleteChapterAndReindex`(替代 action_handler / executor 的"先 shift 再 create""delete + cacheNovelChapters(remaining)"多次独立 DB 调用为单 `db.transaction`，原子化)。invalidate 策略：**不用 `ref.invalidate(chapterListProvider)`**(family by Novel + Novel 无 `==`/`hashCode` → 全 family invalidate 会重置 currentPage=1 / 退出重排模式 / 重查 isInBookshelf / 触发 HeadlessWebView 重抓，UX 跳页；且 agent 工具只有 novelUrl String，从 URL 重构 Novel 与 UI 实例对象身份不等 → invalidate 命中不到)，改用 **family by String** 的 `chapterMutationSignalProvider(novelUrl, int tick)`，Notifier 写后 bump tick，`ChapterList.build` 内 `ref.listen` 自己 novel.url 的 signal 触发 **softReload**(只重读 chapters 替换 `state.chapters`，重算 totalPages，**保留** currentPage / isReorderingMode / isInBookshelf / lastReadChapterIndex / isLoading)。Controller 改造：ChapterActionHandler 删 `insertChapter` / `deleteChapter`(保留 `isChapterCached`)，ChapterReorderController 删 `saveReorderedChapters`(保留 `onReorder` 纯函数，构造不再需要 chapterRepo)，ChapterLoader 加 `Ref` 注入、`refreshFromBackend` 内 `cacheNovelChapters` 走 Notifier。VersionHistorySheet 加 `novelUrl` 字段(reader_screen 调用方传 `widget.novel.url`)。新增 `chapter_mutation_provider_test.dart`(17 个 test 覆盖 8 方法 × 成功/失败 + novelUrl 分桶隔离，手写 `_FakeChapterWriter implements IChapterWriter`)+ `chapter_list_soft_reload_test.dart`(bump → chapters 更新 + currentPage 保留 + 软刷新静默失败)。重写 `chapter_action_handler_test.dart`(删 insertChapter/deleteChapter group，保留 isChapterCached)。修复"agent 创建/修改章节内容 / 用户编辑保存 / 还原历史版本 / 重排 / 清缓存 / 标记已读 / 阅读页下载章节首次缓存后，章节列表不立即刷新"的根因缺陷，连带消化 CLAUDE.md 长期 TODO「Novel App 章节列表 Notifier 待重构」+ 历次记录中"markChapterAsRead 同类 bug 待重构"。详见 plan `docs/superpowers/plans/2026-07-29-chapter-mutation-notifier.md`。
- **2026-07-29**: **修复 Agent Chat 对话窗口「新建会话」入口丢失**。`a52c8ab`(2026-07-27 dialog 瘦身 shell 重做)删除顶栏 inline「新建会话」IconButton 后,入口被埋进 `⋮ → 会话历史 → sheet 顶部 +` 三层菜单,`scenario_sessions_provider.startNewSession` doc 注释承诺的"对话窗口右上角按钮"不复存在,可发现性回归。`AgentChatHeader` 加 `onNewSession` 字段 + `IconButton(AgentIcons.plus, tooltip '新建会话')`(位置:全屏按钮后、关闭按钮前,与 sheet `+` 入口同图标同语义);`agent_chat_dialog.dart` 加 `_startNewSession()` 读 `currentAgentScenarioProvider` → `scenarioSessionsProvider.notifier.startNewSession(...)`,连线 `onNewSession`。复用同一 `startNewSession`(运行中新建由 `adoptSession` 内部 cancel 老 agent 兜底),与 sheet 入口行为一致。更新 `agent_chat_header_test.dart`:「三按钮」断言改「四按钮」+ 新增点击触发 `onNewSession` 回调用例(TDD 先红后绿)。analyze 零告警、dialog 3 个测试无回归。
- **2026-07-28**: **修复阅读进度不刷新 bug**。`BookshelfMutationNotifier` 增 `updateReadProgress(String novelUrl, int chapterIndex)`,内部 `_wrap` 统一"写库 + invalidate(bookshelfNovelsProvider)"。`ReaderContentController.updateReadingProgress` 改调 Notifier(`_ref.read(bookshelfMutationProvider.notifier).updateReadProgress(...)`)而不是直接调 `NovelRepository.updateLastReadChapter`,修复"阅读完返回书架看不到进度更新"——书架页进度条 + 排序(`getNovelsByBookshelf` 按 lastReadTime DESC)同步受影响。顺手清理 Task 1 拆 `IBookshelfWriter` 后遗留的 `ReaderContentController._novelRepository` dead field + 构造参数 + `reader_screen.dart` 调用点。补 2 个 Notifier 单测(成功路径写 + invalidate / 失败路径不 invalidate)。`markChapterAsRead`(章节列表已读高亮同类 bug)记录独立 issue 待后续重构。详见 `docs/superpowers/plans/2026-07-28-fix-read-progress-refresh.md`。
- **2026-07-28**: **书架写入收口 Notifier 重构(根治刷新 bug)**。`BookshelfMutationNotifier` 收口所有改书架数据的写路径(9 方法:addNovel/removeNovel/toggleBookshelf/updateTitle/updateCoverMediaId/removeCoverMediaId/moveToBookshelf/copyToBookshelf/createNovel),内部 `_wrap` 统一"写库 + invalidate(bookshelfNovelsProvider)",失败不 invalidate。接口瘦身:`INovelRepository` 移除 5 个写方法、`IBookshelfRepository` 移除 3 个写方法,新增内部 `IBookshelfWriter`/`IBookshelfAssociationWriter`(定义在 repository 实现文件内)仅 `BookshelfMutationNotifier` 通过 `bookshelfWriterProvider`/`bookshelfAssociationWriterProvider` 持有 → **编译期阻止绕过 Notifier 直接写库**。`addNovel` 返回 `Future<int>`(Agent create_novel 需 novelId)。迁移调用点:浏览器 FAB / Agent createNovel / 章节页 toggleBookshelf / 书架页 6 处(含 plan 调查遗漏的 copyToBookshelf)/ 2 个 test 文件。根治"浏览器添加小说后书架不刷新"根因(`IndexedStack` 保 state + 写库忘 invalidate)。详见 spec + plan。
- **2026-07-28**: **网页提取场景网络请求观察工具**。`WebViewExtractScenario` 新增 `list_network_requests` 工具(仅 Android),用 `flutter_inappwebview` 的 `shouldInterceptRequest` 原生观察模式(`return null` 放行)捕获当前 Headless WebView 页面发出的请求(URL/method/请求头/query_params)。新建 `NetworkRequestRecorder`(ring buffer cap 500 FIFO + header 值截断 1KB + query_params 解析,纯 Dart 可测,`snapshot` 返回 `{total,returned,truncated_to,requests}` 完整 envelope);`HeadlessWebViewPool` 加 `networkRecorder` 引用槽,构造时挂 `shouldInterceptRequest`/`onLoadStart`(回调在调用时读槽委托,无需重建 webview 即可命中当前场景 recorder);`AgentScenarioFactory` Headless 分支 acquire 后绑定 recorder、cleanup 时解绑(null)→`disposeNetworkRecorder()`→`release()`;`onLoadStart` 跳转即清空。不采集响应体(约定)、不采集请求体(`WebResourceRequest` 无 body 字段,平台限制)、不采集 status/content-type(观察模式拿不到)。iOS 工具不挂。零 JS、零 monkey-patch。记录所有子资源(不启发式过滤,Agent 用 `url_contains` 自行过滤)。详见 spec + plan。
- **2026-07-27**: **Agent Chat 晨读书馆风重做**。`agent_chat_dialog.dart` 1230 行巨石拆为 4 组件 + 1 shell：新建 `agent_chat_header.dart`（去 indigo 渐变改 paper 底 + serif `novelTitle` 标题 + 上下文行：writing 显「阅读《title》· 章节」/webview 显 URL + 3 按钮场景菜单含切换/配置/全屏）、`agent_status_strip.dart`（`selectStatus` 纯函数 `error > retry > supplement` 优先级 + `AgentStatusStrip` widget 含 retry 倒计时，5 个手写 status bar 合 1）、`agent_chat_messages.dart`（ListView + 空状态用扩展后的 `EmptyStateView` + `FloatingActionButton.small`）、`agent_chat_composer.dart`（统一 ActionChip 样式 + 双模 attach/send 按钮 + 可选注入外部 controller）；新建 `agent_icons.dart` 集中 Material `IconData` 常量替换所有 emoji；扩展 `empty_state_view.dart` 加 `iconWidget`/`titleStyle` 可选参（向后兼容）。气泡 user 改琥珀 wash (`chatButtonPrimary@0.10`)、assistant 改 `paper` + `divider` 描边 + serif `bodyProse.copyWith(fontSize:13)`，删除冷调遗留 `chatRoleBubble`/`chatUserBubble` 误用；删除 `errorAccent` (与 `error` 同值)；`retry_banner.dart` 删除（逻辑入 `AgentStatusStrip`，dialog 用 `ValueListenableBuilder<RetryState?>` 包裹兜底订阅）；`agent_scenario_config_dialog.dart` 标题 emoji 改 `AgentIcons.quill`。切场景行为不变（透明化）。dialog 1230->275 行（-77.7%）。详见 `docs/superpowers/specs/2026-07-27-agent-chat-reading-style-redesign-design.md` + `docs/superpowers/plans/2026-07-27-agent-chat-reading-style-redesign.md`。
- **2026-07-27**: **文档系统同步现状**。根 CLAUDE.md 同步到 v39 / 17 端点 / 3 Tab / 24+ screens / 已知问题；项目愿景改为"AI 原生小说阅读平台"；移除"多站点/全文搜索/9 个小说站点"等过期措辞。详见 `docs/superpowers/specs/2026-07-27-github-display-optimization-design.md` + `docs/superpowers/plans/2026-07-27-github-display-optimization.md`。
- **2026-07-18**: **LLM 重试 UI 展示**。Agent Chat 底部输入栏上方浮动横幅(变体 2:错误码类别 + 倒计时,传输层橙/回合层蓝)。`withRetry` 加可选 `onRetry(attempt, maxAttempts, delayMs, error)` 回调(默认 null 向后兼容);新建模块级单例 `RetrySignals`(`ValueNotifier<RetryState?>` + `RetryLevel` + `RetryState` + `categorizeRetryError` 共享工具 + `resetForTest`);`IoLlmHttpClient.postJson/postJsonStream` 注入 onRetry → `reportTransport`,成功 return 单点 `clear()`(rethrow 不 clear,避免与 round-level 竞争空白闪烁);`agent_loop` round-level catch 块在 `await Future.delayed` 前 `emit RetryEvent` + `RetrySignals.reportRound(maxAttempts: _config.networkRetryPerRound)` 同一处(走方案 B 绕开 `shouldMainSessionHandleEvent` 过滤,子 Agent 重试也能显示),`AgentErrorEvent`/`AgentDoneEvent`(取消 + 无工具调用 + max_rounds 四个退出分支)emit 时 clear;`RetryEvent extends AgentEvent` 必带 `super.runId` 转发(否则 `EventTagger.tag`/`SubagentStateProjector.project`/`scenario_session._handleAgentEvent` 三个 exhaustive switch 编译失败);新建 `RetryBanner` widget(`Timer.periodic` 倒计时,delayMs≤1s 或到 0 切「重试中…」)。无取消按钮(spec §1.3)。多 session 串号限制接受(YAGNI)。详见 `docs/superpowers/specs/2026-07-17-llm-retry-ui-design.md` + `docs/superpowers/plans/2026-07-17-llm-retry-ui.md`。
- **2026-07-18**: **ContextCompactor 预剪枝层（P1 cheap pre-pruning）**。`context_compactor.dart` 的 `compact()` 第一步新增 `_pruneOldToolResults`，对压缩候选区间（`[0, protectEnd)`，默认保护最近 6 条 tool result）内的老 tool result 做 Pass 1 MD5 去重（`dedupThresholdChars=200`，保留最新一条，前面重复替换为 `[toolName dup of idx#md5]`）+ Pass 2 按工具类型 1-liner 改写（`longFieldChars=500`，覆盖 read_chapter_content / list_chapters / search_in_chapters / execute_js 四个高频工具 + 通用 fallback，错误分支保留 `{error, message}`）。只改 tool result 的 content，不动 assistant.toolCalls / system / user / toolCallId / 消息顺序；改写后 content 仍是合法 JSON（read_chapter 纯文本特例除外）。新增 `CompactionResult.rewrittenContent` / `CompactionEvent.rewrittenContent` 携带改写记录透传给 `ScenarioSession._handleCompaction`，复用现有 `_deleteAgentMessagesBeforeDb`（clearMessages + 重写）自动把 1-liner 版落库，hydrate 续聊时 LLM 看精简版。新增 `CompactorConfig.{prePruneEnabled, dedupThresholdChars, longFieldChars, protectRecentToolResults}` 配置项，`prePruneEnabled=false` 退化为 v32 行为。改写后同样 `preserveTailChars` 预算能装下更多消息，减少丢消息数。新增 20 个单测覆盖模板/去重/保护/契约。借鉴 `hermes-agent/agent/context_compressor.py` 的 `_prune_old_tool_results`。
- **2026-07-17**: **LLM HTTP 错误统一重试**。`retry_helper` 删除 `NonRetryableHttpException` 类，`isRetryableStatus` 改为 `>= 400`（所有 4xx/5xx 一律重试）；`llm_provider` 的 `_postJsonOnce`/`_postJsonStreamHandshake` 移除 4xx 分支，统一抛 `RetryableHttpException`；`chatForJson` 应用层 `retryOnParseError` 默认值 1→0（彻底交给传输层 8 次/60s 重试）。瞬态 4xx（代理网关偶发 400/401 等）不再直接打断会话。同步反转 `retry_helper_test`/`agent_loop_retry_test` 断言并新增 400/401 round-level 重试用例。
- **2026-07-15**: OCR 提取器产品化。site_scripts 加 ocr 列（v37）；OcrPredictor 改 recognizeImage(base64Png)；新增 OcrRestoreService（restorePuaInText/verifyFontFamily/readableRatio）+ 系统 OCR-JS 模板；HeadlessWebViewContentService/ChapterListService 加 OCR 还原钩子；save_script 重写为分次保存+落库前验证（domain/run_id/script_type/test_url/ocr）；prompt 加提取器创建流程。番茄字体反爬正文可读。
- **2026-07-17**: **移除 webview 模型下载链路**。Webview 浏览器不再支持下载模型到后端 `/app/models`：删除 `model_download_manager_screen` / `model_save_location_dialog` / `model_download_service` / `model_download_repository` / `model_download_task` 模型 / `model_download_providers` 共 6 文件；移除 `webview_providers.handleDownloadStart` + `InAppWebView.onDownloadStartRequest` 入口；删除 `ApiServiceWrapper` 中 `listModelDirs` / `initModelUpload` / `uploadModelChunk` / `getModelUploadStatus` / `completeModelUpload` / `cancelModelUpload` 6 个方法；DB v37→v38 migration drop `model_download_tasks` 表；pubspec 移除 `background_downloader` 依赖、Manifest 同步删除 `Background Downloader Service`；原本器自带的模型文件可通过 `docker compose cp` / `scp` 直传，不再需要 APP 内导。
- **2026-07-17**: **site_scripts 拆 ocr 为两列，番茄 list/content OCR 独立判定**。v38→v39 migration 加 `chapter_list_ocr` + `chapter_content_ocr` 两列；`SiteScript` 模型字段由单一 `ocr`/`needsOcr` 拆为 `chapterListOcr`/`chapterContentOcr`；`SiteScriptRepository.updateScriptPart` 按 `scriptType` 写对应列；`HeadlessWebViewChapterListService` / `HeadlessWebViewContentService` 分别读对应列；save_script 工具描述 / buildSystemPrompt / 设计文档去掉"list+content 必须一致"措辞。修复番茄场景：目录页正常汉字→`chapterListOcr=false`、正文页 PUA→`chapterContentOcr=true`，分次保存互不覆盖。
- **2025-11-13**: AI上下文初始化，重新设计架构文档，添加模块化结构
- **2026-06-11**: 文档大整理，移除 Dify 引用，更新为 DSL Engine + Scrapling + Riverpod
- **2026-07-07**: 校准爬虫站点（9→11）、DB 版本（v21→v33）、移除无依据端口；DSL Engine 统一命名
- **2026-07-08**: **移除 backend 搜索与多站点爬虫功能**。前端已改用 headless WebView + 本地 JS 提取脚本获取章节内容、本地书架搜索；后端爬虫/搜索/章节缓存成为死代码，删除 `app/services/` 下 21 个文件、4 张缓存表、Scrapling/Playwright 等依赖；新增 `20260708_drop_cache_tables` 迁移 drop `novel_cache_tasks` / `novel_chapters_cache` / `chapter_list_cache`。
- **2026-07-10**: 小说封面媒体化。bookshelf 加 coverMediaId 列（v36），新增 set_novel_cover 工具，NovelCover 命中走 MediaView（图/视频，BoxFit.cover 不拉伸）。镜像角色头像 avatarMediaId 模式。

## 项目愿景

Whimread 是一个 **AI 原生小说阅读平台**。前端 Flutter 离线优先（本地书架 + Headless WebView 章节提取 + PP-OCRv6 字体反爬还原），AI 层由 DSL Engine + Agent Chat + Subagent 驱动，后端 FastAPI 仅承担 ComfyUI 文生图/图生视频、AI 结果轮询、客户端备份、客户端日志上报 等轻量职责。

## 架构总览

```mermaid
graph TD
    A["(根) Whimread"] --> B["novel_app"];
    A --> C["backend"];
    A --> D["docker-compose.yml"];
    A --> E["PostgreSQL"];

    B --> F["Flutter移动应用"];
    B --> G["SQLite本地缓存"];

    C --> H["FastAPI后端服务"];
    C --> J["PostgreSQL任务表"];

    F --> K["书架管理"];
    F --> L["搜索功能（本地）"];
    F --> M["阅读界面（headless WebView）"];
    F --> N["AI集成（DSL Engine + Agent）"];

    H --> O["AI文生图/图生视频API"];
    H --> P["备份/日志API"];
    H --> Q["ComfyUI 模型分块上传 API"];

    click B "./novel_app/CLAUDE.md" "查看 Flutter 移动应用模块"
    click C "./backend/CLAUDE.md" "查看 Python 后端模块"
```

## 技术栈

### 前端技术
- **Flutter 3.0+**: 跨平台移动应用框架
- **Dart SDK**: 编程语言
- **SQLite**: 本地数据存储
- **Riverpod**: 状态管理
- **Material Design 3**: UI设计系统

### 后端技术
- **FastAPI**: Python Web框架
- **PostgreSQL / SQLite**: 主数据库（生产 PostgreSQL，本地默认 SQLite）
- **SQLAlchemy**: ORM框架
- **Alembic**: 数据库迁移

### 基础设施
- **Docker & Docker Compose**: 容器化部署
- **Alembic**: 数据库迁移
- **OpenAPI**: API文档生成
- **GitHub Actions**: CI/CD 自动化

## 模块索引

| 模块路径 | 类型 | 主要功能 | 状态 |
|---------|------|----------|------|
| [novel_app](./novel_app/CLAUDE.md) | Flutter移动应用 | 小说阅读器，搜索，缓存，AI功能 | ✅ 活跃 |
| [backend](./backend/CLAUDE.md) | FastAPI后端 | AI文生图/图生视频、ComfyUI 客户端、备份、模型管理、日志上报 | ✅ 活跃 |

## 核心功能

### 📱 移动应用功能
- **书架管理**: 本地小说收藏与阅读进度跟踪
- **本地搜索**: 本地书架搜索（前端实现，不调后端）
- **离线阅读**: 章节内容本地缓存 + headless WebView 提取
- **AI增强**: DSL Engine 本地工作流 + Agent Chat 智能对话
- **场景插图**: AI生成的场景插图功能（ComfyUI 后端，支持负向提示词）
- **角色卡管理**: 智能识别和提取章节角色信息
- **人物关系图**: 可视化角色关系网络
- **提纲管理**: 小说结构和章节规划

### 🌐 后端服务功能
- **ComfyUI 文生图 / 图生视频**: 任务提交与结果轮询，支持负向提示词
- **ComfyUI 模型分块上传**: 分块 init / chunk / status / complete / cancel 五段式
- **客户端数据库备份**: 上传 / 列表 / 下载 / 删除（4 端点）
- **客户端日志上报**: 批量 1–50 条/次持久化
- **ComfyUI 健康检查**: `/text2img/health`（注意：无 `/api` 前缀，与业务前缀不一致）

> 注：**多站点爬虫、搜索/章节接口、章节缓存已移除**（前端改用 headless WebView + 本地 JS 提取脚本 + 本地书架搜索，2026-07-08）。

### 🔧 基础设施功能
- **容器化部署**: Docker Compose一键部署
- **数据库管理**: PostgreSQL + Alembic迁移
- **代理支持**: 网络代理配置
- **健康检查**: 服务状态监控

## 运行与开发

### 环境要求
- Flutter SDK 3.0+
- Python 3.11+
- Docker & Docker Compose
- PostgreSQL 15+

### 快速启动

```bash
# 克隆项目
git clone git@github.com:yunkst/novel_builder.git
cd novel_builder

# 使用Docker Compose启动所有服务
docker-compose up -d

# 查看服务状态
docker-compose ps
```

### 端口映射
- **后端 API**: 3800 → 8000 (FastAPI)
- **debugpy**: 6678 → 5678 (Dockerfile.debug)
- **PostgreSQL**: 5432 (Docker 内部，不对宿主机暴露)
- **ComfyUI**: 8188 (宿主机本地，文生图后端 —— 通过 `host.docker.internal` 引用)

### 开发环境配置

创建 `.env` 文件：
```env
NOVEL_API_TOKEN=your_api_token_here
DATABASE_URL=postgresql://novel_user:novel_pass@postgres:5432/novel_db
COMFYUI_API_URL=http://host.docker.internal:8188
```

## 测试策略

### 测试原则
- **功能优先**: 先实现功能，再补充测试
- **渐进测试**: 从单元测试开始，逐步增加复杂度
- **维护可控**: 测试代码维护成本不高于业务代码

### 测试覆盖率
- **Flutter应用**: 核心业务逻辑单元测试 + Riverpod Provider 测试
- **后端服务**: API端点集成测试
- **AI 功能**: ComfyUI 文生图/图生视频任务接口与工作流配置测试

## 编码规范

### Python后端
```bash
# 代码质量检查
ruff check .          # 快速检查
pylint app/           # 深度检查
mypy app/             # 类型检查

# 代码格式化
ruff format .         # 自动格式化
isort .               # 导入排序
```

### Flutter应用
```bash
# 代码分析
flutter analyze

# 代码格式化
flutter format lib/

# 测试
flutter test

# 代码生成（Riverpod）
dart run build_runner build --delete-conflicting-outputs
```

## AI使用指引

### Claude Code集成
- 使用根级和模块级CLAUDE.md获取上下文
- 通过Mermaid图理解系统架构
- 遵循各模块的具体开发规范

### 技能系统
- 使用 `.claude/skills/` 中的技能进行开发辅助
- 提交时使用 chinese-commit-conventions 技能
- 代码审查使用 chinese-code-review 技能

## 部署指南

### 生产环境部署
1. 配置环境变量
2. 设置数据库连接
3. 启用HTTPS
4. 配置反向代理
5. 设置监控和日志

### Docker部署
```bash
# 生产环境构建
docker-compose -f docker-compose.yml up -d --build

# 查看日志
docker-compose logs -f
```

## 数据库设计

### 主要表结构
- **bookshelf**: 小说元数据（历史命名，含阅读进度，v36 加 coverMediaId 走 MediaView 渲染封面）
- **bookshelves / novel_bookshelves**: 多书架分类（v16）
- **novel_chapters**: 章节列表元数据（v2 `is_user_inserted`，v11 `read_at`，v18 `is_accompanied`）
- **chapter_cache**: 章节内容缓存（前端 SQLite 本地；用户插入章节保护）
- **chapter_versions**: 章节历史版本（v30，AI 编辑/重写留档）
- **characters / character_relationships**: 角色与关系图（v34 `avatar_media_id`，v35 first_appearance_chapter，关系区间模型 v35）
- **scene_illustrations**: ~~v34 已删，由 media_items 统一承载~~
- **media_items**: 统一媒体代理（v34；mediaId / kind / source / local_only）
- **outlines**: 大纲（v9）
- **chat_sessions / chat_messages**: Agent Chat 会话与消息（v31-32）
- **prompt_tags / prompt_tag_categories / prompt_history / prompt_tag_history**: 写作标签库（v22-28）
- **agent_memory**: Agent 经验记忆（v27）
- **llm_configs**: LLM 配置 CRUD（v29）
- **site_scripts**: 站点提取脚本（v25+；v37 加 ocr 列；v39 加 `chapter_list_ocr` 与 `chapter_content_ocr` 两列，番茄场景互不覆盖）
- **text2img_task**: ComfyUI 文生图任务（prompt_id=task_id；v2026-07-10 加 negative_prompt）
- **image_to_video_task**: ComfyUI 图生视频任务
- **client_logs**: 客户端日志（后端 PostgreSQL）

**已移除**（2026-07-08 by `20260708_drop_cache_tables`）：`novel_cache_tasks`、`novel_chapters_cache`、`chapter_list_cache`、`model_download_tasks`（v38 删）。

### 数据库版本
- **前端SQLite**: v39 (novel_reader.db) — v38→v39 加 `chapter_list_ocr` + `chapter_content_ocr` 两列（2026-07-17 site_scripts 拆 OCR 列）
- **后端PostgreSQL**: Alembic 管理（head: `20260708_drop_cache_tables`）
- **迁移工具**: Alembic (后端) + 数据库升级服务 (前端)

## API文档

### OpenAPI规范
- **文档地址**: http://localhost:3800/docs
- **规范文件**: backend/openapi.json
- **认证方式**: X-API-TOKEN header

### 主要端点
**AI 接口**（ComfyUI 任务）：
- `POST /api/text2img/generate` - 提交文生图任务（含 negative_prompt）
- `GET  /api/text2img/image/{task_id}` - 按 task_id 取文生图结果（202 / 200 png / 404）
- `GET  /text2img/health` - ComfyUI 健康检查（**注意**：无 `/api` 前缀）
- `POST /api/image-to-video/generate` - 上传图片 + prompt，提交图生视频任务
- `GET  /api/image-to-video/video/{task_id}` - 按 task_id 取视频结果（202 / 200 mp4 / 404）

**ComfyUI 模型管理**：
- `GET  /api/models` - 列出 T2I / I2V 工作流
- `GET  /api/models/dirs` - 列出 ComfyUI 模型一级子目录（容器内）
- `POST /api/models/upload/init` - 初始化模型分块上传任务
- `POST /api/models/upload/{upload_id}/chunk/{index}` - 上传单个分块
- `GET  /api/models/upload/{upload_id}/status` - 查询分块上传进度
- `POST /api/models/upload/{upload_id}/complete` - 合并分块到最终路径
- `DELETE /api/models/upload/{upload_id}` - 取消并清理分块临时目录

**备份接口**：
- `POST   /api/backup/upload` - 上传 .db/.zip 备份
- `GET    /api/backup/list` - 列出已上传备份
- `GET    /api/backup/download/{backup_id:path}` - 下载备份
- `DELETE /api/backup/delete/{backup_id:path}` - 删除备份

**日志接口**：
- `POST /api/logs/upload` - 批量上报客户端日志（1-50 条/次）

**杂项**：
- `GET /` - 服务信息 + 端点清单
- `GET /health` - 服务自身健康检查
- `GET /security-check` - 安全配置自检（仅 DEBUG）

> 已移除：`/search`、`/chapters`、`/chapter-content`、`/novel-by-url`、`/source-sites`、`/api/cache/*`、`/ws/cache/*`、`/api/app-version/*`（版本管理迁移到 GitHub Releases，前端 `github_release_service.dart` 直接调 GitHub API）（2026-07-08）。

## 已知问题（不在本次 PR 范围）

下列问题已识别但属"展示层 + 仓库卫生"scope 之外，需后续 PR 处理：

- `backend/openapi.json` 严重过期：仍记录 2026-07-08 删除前的爬虫/缓存端点（10039 字节），不含任何现行端点。前端若依赖其做客户端生成会全错。**修复方式**：重生成后端运行后 `python -m openapi-spec-validator` 并重新导出。
- `backend/Dockerfile.debug` 仍 `playwright install chromium`：因 `pyproject.toml` 已删 playwright，镜像构建会失败。**修复方式**：删除 Dockerfile.debug 的 playwright 段，或新建 Dockerfile.dev 取代。
- `backend/Dockerfile.test` 仍装 `scrapling[fetchers]` 与 `scrapling[core]`、`backend/Dockerfile.simple` 装 `beautifulsoup4 lxml`。**修复方式**：删除这两个文件或合并。
- `backend/tests/unit/test_crawlers.py.disabled` 仍在仓库。**修复方式**：删除。
- `backend/app/exceptions.py` 残留 `CrawlerError` / `ParseError` / `CacheError` 死类。**修复方式**：删除。
- `backend/.ruff.toml` 仍为 `*_crawler.py` / `scene_illustration_service.py` / `role_card_service.py` / `search_service.py` 配 per-file ignore，对应文件已不存在。**修复方式**：删除这些 per-file override 段。
- `backend/alembic/env.py` autogenerate 仅 `import Text2ImgTask, ImageToVideoTask`，漏 `import ClientLog`。**修复方式**：补 import。
- 后端版本号三处不一致：pyproject=`0.1.0` / FastAPI 实例=`0.2.0` / `__init__.py`=`1.0.0`。**修复方式**：统一到单一版本来源。
- `novel_app/CLAUDE.md` 列 `novel_context_service.dart` 待二次确认（plan 阶段）。

## 故障排除

### 常见问题
1. **Flutter应用无法连接后端**: 检查API地址配置和Token
2. **数据库连接失败**: 检查 PostgreSQL 服务状态
3. **DSL Engine执行失败**: 确认AI设置中已配置API URL和Key
4. **ComfyUI图片生成失败**: 确认 ComfyUI 服务运行正常

### 日志查看
```bash
# 查看后端日志
docker-compose logs -f backend

# 查看数据库日志
docker-compose logs -f postgres
```

## 贡献指南

### 开发流程
1. Fork项目
2. 创建功能分支
3. 编写代码和测试
4. 提交Pull Request
5. 代码审查和合并

### 代码提交规范
- 使用清晰的提交消息
- 遵循 Conventional Commits 规范
- 一个提交只做一件事
- 包含必要的测试
- 遵循代码规范

## 许可证

MIT License - 详见LICENSE文件
