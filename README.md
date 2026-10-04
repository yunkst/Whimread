<div align="center">

# 随心阅读
### Whimread · AI 原生小说阅读平台

**读喜欢的 · 改不爽的 · 写自己的**

[⬇️ 下载 APK](https://github.com/yunkst/Whimread/releases/latest)  ·  [🌐 在线介绍](https://yunkst.github.io/Whimread/)  ·  [⭐ 给个 Star](https://github.com/yunkst/Whimread)

本地书架 · 任意网站阅读 · 离线缓存 · AI 改写 · AI 创作 · 文字游戏

> 在线介绍页的每个功能演示都是用 HTML 动画实时模拟的 App 界面（非截图、非视频），
> 手机上就能交互体验：[yunkst.github.io/Whimread](https://yunkst.github.io/Whimread/)

</div>

---

## 📖 读 · APP 里就能逛任意小说站

打开 APP 就有一个**内置浏览器**（底部第 3 个 Tab）。用它打开任意小说站，翻到目录页，右下角会浮出「添加小说」按钮——点一下就进书架了。

- 🌍 **任意站点都能加**：第一次访问某个站时，**AI 现场帮你生成提取脚本**（你要做的只是等一下、确认预览），之后这个站就一劳永逸——下次直接用，不用再生成（该站已有脚本时按钮变金色，秒加）
- 📖 **干净的正文**：从原页提取正文文本，正文里那些弹窗广告、"请下载 APP 继续"、推广链接，通通没有
- 📥 **整站书架搬家**：网站自己的收藏列表，点「导入我的书架」一键勾选导入
- 💾 **看过的章节自动存本地**：断网、飞机上、地铁里，照样翻回去重读；还会偷偷预加载下一章，翻页时不卡
- 🔤 **字体反爬也能读**（番茄这类把字做成乱码的站）：端侧 OCR 自动把乱码还原成正常汉字，不用你管
- 🔎 **书内找东西**：在已缓存章节里搜关键词，按上下文定位；也能让 AI 帮你搜"某个道具第一次出现在第几章"

<details>
<summary>🔧 技术细节</summary>

- **加书流程**：内置浏览器打开站点 → 目录页 FAB 浮出（条件 = 当前 URL 是 http(s)）→ 该域名有 `chapter_list_js` 脚本则直接执行；**无脚本则走 webview_extract 场景 agent 现场生成脚本**（`save_script` 工具），生成后落库，下次复用（`webview_add_novel_button.dart` + `webview_extract_scenario.dart`）
- **正文提取**：`HeadlessWebViewContentService.fetchContent`，前台 high 优先级可抢占后台 low 预加载，HeadlessInAppWebView 单例 + 互斥锁
- **预加载**：`PreloadService` 当前章渲染后入队后续章，FIFO + 30s/任务速率限制，命中缓存 reset
- **OCR 还原**：`site_scripts.chapter_content_ocr` 列标 true → `OcrRestoreService.restorePuaInText` → 端侧 PP-OCRv6（onnxruntime）把 PUA 码点渲染成图再识别
- **搜索双入口**：UI 走 `chapter_search_screen.dart`（已缓存章节全文）；Agent 走 `search_in_chapters` 工具（返回 ~80 字上下文片段）
- **用户章节保护**：`is_user_inserted=1` 章节不被自动更新覆盖

</details>

## ✏️ 改 · 不爽的剧情，改成你想要的

读到意难平、崩人设、烂尾——不用忍，让 AI 帮你改：

- 👆 **长按段落写想法**：读到不对劲的地方，长按那段文字标注（"节奏太慢，加一场雨夜追逐"），AI 按标注重写本章
- ✍️ **补全作者没写的细节**：原文一笔带过的打斗、留白的心理活动、没展开的支线——让 AI 帮你写出来接进去
- 📖 **续写烂尾 / 太监文**：作者弃坑了？AI 按现有设定续写后续剧情
- 🆕 **插入自己喜欢的情节**：在某章后插入新章节，AI 按你的脑洞写正文（比如"在这里加一段主角和女二的对手戏"）
- 🔀 **改原著设定 / 走向**：让结局变开放式、让反派洗白、让主角走另一条路——AI 按你的新设定重写整章
- 🎯 **小修小补也省 token**：改个错别字、调一段对话、润色一句描写——AI 直接动你指的那一句，其他一字不改
- 🏷️ **风格标签**：`赛博朋克` `暗黑` 这种标签自由组合，每章套用对应风格写
- 📚 **改了不满意能回滚**：每次 AI 重写都留一份历史版本，不喜欢就退回去

<details>
<summary>🔧 技术细节</summary>

- **补全/续写**：本质是 `create_chapter`（任意位置插入新章节）或 `rewrite_chapter`（AI 按指令重写整章，原文作为上下文）
- **改设定/走向**：`rewrite_chapter` + 修改要求（`agent_tools.dart:333`），AI 注入人物卡 + 写作标签重生成
- **插入情节**：`create_chapter` 指定 position + instruction，AI 写正文插入（`agent_tools.dart:240`）
- **小修小补**：`update_chapter_content` 精确字符串替换（old→new），不调 LLM，多处匹配未设 `replaceAll` 会报 `ambiguous_match`（`agent_tools.dart:290`）
- **风格标签**：`prompt_tags` / `prompt_tag_categories` 表，每章按 `tagNames` 随机抽一条 prompt 拼入
- **版本留档**：`chapter_versions` 表（v30），每次重写存历史版本可回滚

</details>

## 🖋️ 写 · 从 0 创作一本自己的小说

读完别人的故事，想写自己的——不用懂写作技巧，AI 全程陪你。

**怎么开始（三步）：**

1. 💬 **跟 AI 说一句**："帮我写一本赛博朋克悬疑，主角是个失忆黑客"——AI 会帮你建好书、定世界观、列出角色
2. 📋 **先定骨架**：AI 帮你写全书大纲和章节细纲，故事不散、节奏有人帮你把控
3. 🎬 **逐章生成**：每章说一句你这章想写什么（"主角在酒馆遇到神秘老人，获得关键线索"），AI 结合人物设定 + 你定的风格写出整章正文

**AI 是真"陪写"，不是模板填空：**

- 🎭 **人设不漂**：每个角色的外貌、性格、背景独立建档，写章节时按角色注入上下文，前后一致
- 🎨 **风格随你定**：`赛博朋克` `暗黑` `轻松日常` 这些标签自由组合，每章套用；还能自定义「AI 作家设定」（比如"参考烽火戏诸侯的文风"）
- 🖼️ **顺手配图**：按场景描述生成封面或插图，文字+画面一起出（**跑在你手机上的端侧扩散模型**，不耗云端额度、离线也能出图）
- 📚 **全部本地、永远属于你**：你的书、章节、角色、游戏存档全部存在手机本地 SQLite，不依赖任何账号

### 🧠 越用越懂你：你攒的素材越多，AI 写得越稳

不是玄学推荐算法。AI 看到的上下文会随你的使用**真实增长**——下面三件事你做得越多，每次写章节 AI 能调用的素材就越丰富：

- 🏷️ **写作标签库**：你在「设置 → 提示词标签管理」里建的标签（赛博朋克、暗黑、轻松日常……），每个标签就是一段 prompt 文本。同一名字还能存多条变体——AI 写章节时会**随机抽一条**拼到 LLM 输入里。**标签全局共享、不绑书**：你在 A 书建的"悬疑感开场"标签，B 书直接复用
- 🧠 **经验记忆**：你在 Agent Chat 里交代的偏好（"别写错别字""每章结尾留个钩子""反派要立体别扁平"），AI 会**主动**用 `patch_memory` 工具记下来，**跨会话跨书**生效，换次开聊不用重新交代。**你想收拾随时收拾**——「设置 → Agent 记忆管理」可逐条查看、新增、修改、删除
- ✍️ **AI 作家设定**：在「设置 → AI 配置」里给 AI 定个调（"参考烽火戏诸侯的文风""冷峻克制不滥用形容词"），AI 把这段话作为 system prompt 头部**每次写章节都套用**。配合标签组合，每章都能套不同风格

> 一句话：**你把角色卡、大纲、标签、风格、记忆这些素材整理得越扎实，AI 每次写章节能调用的"弹药库"就越满**——输出自然更稳、更连贯、更对你胃口。

> 不知道第一句怎么起？直接问 AI："我想写一本 XX 题材的小说，但不知道从哪开始"——它会帮你出点子、定大纲、起人名。

<details>
<summary>🔧 技术细节</summary>

- **创作引导机制**：AI 在 system prompt 里被设定为「Whimread 的小说写作助手」+ 「专业的小说写作助手，只输出小说正文」（`agent_system_prompt.dart:31` / `chapter_write_executor.dart:549`）；工作原则第 4 条指令 AI 在用户说"新建一本小说"时直接 `create_novel`（`agent_system_prompt.dart:42-43`）
- `create_novel`：建空白书并自动切为当前工作小说（`agent_tools.dart:132`）
- `create_chapter`：position + instruction + `characterNames` + `tagNames` → 调 LLM 生成正文插入（`agent_tools.dart:240`）；前一章正文作为衔接上下文注入（`chapter_write_executor.dart:90`）
- `write_outline` / `update_outline` / `get_outline`：大纲 CRUD（`agent_tools.dart:625+`）
- 人物卡：`characters` 表（v35 `first_appearance_chapter` / v34 `avatar_media_id`），写章节按 `characterNames` 注入
- 风格：`prompt_tags` / `prompt_tag_categories` 表 + 用户自定义 `ai_writer_prompt`（SharedPreferences `ai_writer_prompt`，`chapter_write_executor.dart:400`）
- **写作标签全局共享**：`prompt_tags` / `prompt_tag_categories` 表（v23/24/28）不绑 novelUrl；写章节时 `chapter_write_executor.dart:441-454` 取全部标签按 name 匹配 → 同名多条变体 `shuffle()` 随机抽一条 `promptText` 拼进 user prompt
- **经验记忆手动 + AI 主动**：写入唯一入口是 LLM 调 `patch_memory` 工具（`agent_scenario.dart:284-`），**非自动埋点推荐**；`agent_memory` 表（v27）按 `scenario_id` 分桶（写作 / 网页提取），跨书跨会话持久化；回灌位置 `agent_system_prompt.dart:52-60`「## 经验记忆」段编号 [N] 列出
- **AI 作家设定生效路径**：SharedPreferences `ai_writer_prompt` key（`ai_settings_screen.dart:55-56`）→ `_loadWriterPrompt()`（`chapter_write_executor.dart:411-415`）每章写前同步读取 → 拼到 system prompt 头部（line 561 / 621）→ LLM 始终按这个调子写
- **上下文六件套 = AI 弹药库**：写章节时 AI 看到的素材 = 角色卡 + 大纲（LLM 主动 `get_outline`）+ 标签（随机抽）+ 作家设定 + 经验记忆 + 前一章正文（衔接上下文）。**没有跨书章节正文自动学习机制**——所有 Repository 调用都按 `novelUrl` 严格过滤；"借鉴其他小说技巧"的诚实边界 = 你主动把这些素材整理好（建角色、定大纲、囤标签、设风格、积累记忆），AI 每次写都能用上
- 生图：`create_images` → 端侧 Local Dream 引擎（本机嵌入式子进程，SD1.5 / SDXL，QNN NPU 加速，不依赖云端后端）
- 本地存储：`bookshelf` / `novel_chapters` / `chapter_cache` 表，全部数据存本机 SQLite

</details>

## 🎲 玩 · 文字游戏：让 AI 给你当 GM

读完别人的故事，也可以**住进一个故事里**——把书架上的小说变成互动文字冒险。

- 🕯️ **AI 游戏主持人**：AI 逐段旁白、让 NPC 开口，每回合递上 2–4 个选项；你可以点选项，也可以**直接打字描述自己的行动**——两条路都算数
- 🎲 **命运骰子真掷真算**：带权重的真实随机判定，概率明示、结果公开，**连 GM 自己都不能改**
- 📖 **改编自你书架上的书**：NPC 的性格、说话腔调、头像全部来自那本书的角色卡，改了角色卡，下一轮游戏立刻生效
- ⏪ **任何一步都能回溯**：对某个选择不满意？「回溯到这一步」重新来——剧情重跑，你的设定与记忆原样保留
- 🎬 **打字机式流式演出**：旁白逐字蹦出，关键场景自动配插图（端侧生成）；还有「幕后」按钮能围观 GM 的思考过程
- 💾 **存档永远在本地**：离开页面剧情在后台照跑，回来接着玩

> 和写作助手说一句"我想创建一个文字游戏"，聊聊题材和规则，它就帮你把游戏建出来。

<details>
<summary>🔧 技术细节</summary>

- **一个游戏 = `text_game` 场景下的一个 chat session**：持久化 / 上下文压缩 / 失败重试全部复用 Agent 场景设施，消息链就是剧情的真理源（`text_game_scenario.dart`）
- **回合协议**：玩家输入（user 消息）→ GM 经 `narrate`（旁白）/ `speak`（台词）输出剧情 → 终局工具 `present_choices`（2–4 选项）收尾；忘记给选项时控制器会自动补一次协议提醒
- **游戏必须绑定小说**：参战角色直接引用小说 `characters` 表（头像/别名/近况共享），游戏内状态变化写入角色卡并留版本记录（`character_revisions`，可回滚）
- **掷骰在客户端**：`Random()` + 权重归一化（`pickWeightedEvent`），结果对 GM 有约束力；分支 2–6 条
- **回溯** = 截断该选择之后的消息链并重开决策；设定演化不回滚
- 游玩页独立于通用聊天壳：`text_game_play_screen.dart` + `game_transcript_projector.dart`（纯函数把消息链投影成旁白/台词/骰子/选项分段）
- 规模：功能全量约 6,000 行（screens/widgets/scenario/executor）

</details>

## 🔑 AI 已内置，开箱即用

装上就能用——**不需要申请 API Key、不需要配置任何 AI 供应商**。

- 🔓 **零配置**：首次使用自动完成匿名设备注册（Android 硬件级密钥认证），即可使用改写、创作、文字游戏等全部 AI 能力
- 🪙 **额度透明**：约 `1000 token = 1 点`，聊天头顶实时显示「AI 剩余 N 点」；模型目录标注每个模型的消耗速率，基准模型最省
- ⭐ **点 Star 免费补额度**：额度用完，给项目点一个 Star 并填 GitHub 用户名即可免费补充一次——托管额度由独立开发者自费承担，Star 是最实在的支持
- 🔑 **Key 不落客户端**：所有 LLM 请求走服务端代理，客户端不持有任何第三方 Key
- 🖼️ **生图不耗额度**：扩散模型跑在你手机 NPU 上（Local Dream 引擎 + QNN 加速），离线也能出图

<details>
<summary>🔧 技术细节</summary>

- 编译期注入：`--dart-define=BACKEND_BASE_URL=...`；未注入的非托管包**直接隐藏**模型选择 / 额度入口（`build_config.dart`）
- 注册链路：`POST /api/v1/devices/challenge` → Android Key Attestation（TEE 内不可导出密钥）→ `POST /api/v1/devices/register` → 下发 30 天设备 JWT（存 Keystore）；`android_id` 服务端去重，401 由拦截器自愈重注册
- 额度：`GET /api/v1/devices/me`；1 点 = 1000 token（`device_quota_provider.dart`）；Star 补额度 `POST /api/v1/devices/star/redeem`（服务端核验真实 stargazers）
- 自配供应商模式已整体移除，新手引导页为「AI 已内置就绪」
- 托管服务同时提供：云备份（`/api/backup/*`）、应用更新通道、远程站点脚本库、反馈与日志上报

</details>

## 🧩 还能做这些

除了读/改/写/玩四大核心，还有一大批顺手就能用的能力：

**阅读与书架**

| 能力 | 说明 |
|---|---|
| 🗂️ **书架按来源自动归类** | 「全部 / 原创 / 各来源站点」自动分架，横滑切换，一本书不用手动归档 |
| 📊 **读/缓双进度条** | 每本书一眼看到「读到 34%」和「已缓存 81%」 |
| 🌌 **沉浸模式** | 点一下正文，顶栏底栏和系统状态栏全部淡出，只剩文字；再点恢复 |
| 🔗 **跨章无缝衔接** | 往下滚自动接下一章；重开一本书直接回到上次读到的段落 |
| 🔍 **书内全文搜索** | 在已缓存章节里搜关键词，直达匹配段落（Agent 也有 `search_in_chapters` 工具） |
| 📥 **手动插入章节** | 把自己的章节粘贴进任意一本书；章节可拖拽重排 |
| 📷 **自定义封面** | 相册选图裁剪设为封面，或用 AI 生成的图 |

**浏览器与抓书**

| 能力 | 说明 |
|---|---|
| ⭐ **浏览器收藏夹** | 站点分组收藏，长按重命名/移动/删除 |
| 📜 **脚本管理 + 云端脚本库** | 查看/验证/删除本地提取脚本；可安装人工审核过的云端脚本 |
| 🖥️ **桌面模式** | 伪装桌面 UA + 1200px 视口，对付只给桌面端的站 |

**创作与 AI**

| 能力 | 说明 |
|---|---|
| 👥 **人物卡 & 关系图** | 手动建/AI 帮你建角色卡（性别筛选 + 姓名搜索），关系图拖章节时间轴看关系演变；角色卡每次修改都有版本历史可回滚 |
| 🎨 **端侧场景配图** | 按段落描述生成插图/封面，模型跑在本机 NPU 上（SD1.5 / SDXL），离线可用 |
| 🖼️ **生图模型管理** | 按手机 SoC 过滤可装模型包，测试工作台可调步数/CFG/种子/负向提示词，下载支持断点续传 |
| 💬 **会话历史与回滚** | AI 对话按场景存会话（可重命名/删除），任意消息可回滚；子 Agent 任务有只读详情页 |
| 🧠 **记忆与技巧管理** | 经验记忆按场景分组，逐条查看/新增/编辑/删除；写作技巧库支持分类 + 同名多变体 |

**App 体验**

| 能力 | 说明 |
|---|---|
| 🌗 **晨读 / 暗夜双主题** | 纸张米色与暗夜墨金两套配色 + 衬线正文，亮/暗/跟随系统三档 |
| 🩺 **自诊断工具** | 应用日志（按级别/分类筛选）、数据库修复、预加载队列监控、媒体缓存管理 |
| 📮 **问题反馈** | 可选附带近期日志与 AI 调用记录；崩溃自动弹报告可一键上传 |
| 🔄 **双通道更新** | 检查更新 + 可选预览版通道（带风险确认） |
| 🎓 **新手引导 + 资源引导** | 5 页引导可重看；首次按需下载阅读字体 / OCR 模型 / NPU 运行库，可跳过后台静默补齐 |

<details>
<summary>🔧 技术细节</summary>

- 角色卡：`characters` 表 v35（`first_appearance_chapter`）+ `character_list/detail/edit_screen.dart`；AI 创建角色走 `create_character` / `update_character` 工具
- 角色版本：`character_revisions` 表，文字游戏内的人设变更也走同一条版本链（`source='text_game'`）
- 关系图：`character_relationships` 表（v35 区间模型）+ `relationship_graph_screen.dart` + `flutter_force_directed_graph` + 章节时间轴滑杆
- 端侧配图：`create_images` 工具 → `LocalDreamEmbeddedBackend`（本机嵌入式子进程，QNN NPU 加速）；模型包 `sd15Cpu/sd15Npu/sdxl` 按 SoC 过滤（SDXL 仅 8 Gen 3+），下载 `.part + Range` 断点续传，测试工作台 `image_gen_test_sheet.dart`
- 书架：按来源 URL 派生（`custom://` = 原创，其余按 host），用户不可手动建/改/移动（`bookshelf.dart`）；`bookshelves` 多对多表仅留在 schema 已不读写
- 章节搜索：UI 走 `chapter_search_screen.dart`（命中处 ±20 字上下文，点击跳转阅读器定位）；Agent 走 `search_in_chapters` 工具
- 会话与回滚：`chat_sessions`/`chat_messages` 按场景分桶；消息级回滚见 `agent_chat_messages.dart`；子 Agent 只读详情 `subagent_detail_screen.dart`
- 主题：`AppColors` 扩展，亮色「晨读书馆」`#FFFDF8`/`#2B2620`，暗色「暗夜书馆」`#241F16`/`#E8DCC4`，品牌琥珀 `#B8843A`（`app_colors.dart`）
- 反馈与诊断：`feedback_submit_screen.dart`（日志/AI 调用记录开关默认关）+ `crash_report_dialog.dart` + `log_viewer_screen.dart` + 修复数据库（重跑迁移不删数据）
- 更新：`检查更新` + `获取预览版` 开关两件式，预览通道带风险确认（`settings_screen.dart`）

</details>

## 🔧 面向开发者

<details>
<summary>点开看技术栈与构建</summary>

**技术栈**

- 客户端：Flutter 3.35.x（CI 锁定 3.35.5）/ Dart 3 / Riverpod（代码生成）/ SQLite (schema v55) / Material 3
- AI 层：OpenAI 兼容 LLM + Agent 多场景 + Subagent 协作 + 端侧 PP-OCRv6 (onnxruntime) + 端侧生图（Local Dream 引擎，QNN NPU）
- 章节：Headless WebView + 本地 JS 提取脚本（`site_scripts` 表，AI 可现场生成并落库）
- 托管服务（可选，编译期注入）：设备注册 + LLM 代理 + 额度 + 云备份 + 更新通道 + 远程脚本库
- 平台：Android 为发布主平台；iOS / Windows / macOS / Linux / Web 源码齐备可自行编译

**源码运行**

```bash
git clone https://github.com/yunkst/Whimread.git
cd Whimread

flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Riverpod/mock 代码生成
flutter run

# 可选：接入自建托管后端（不注入则隐藏模型选择/额度入口）
flutter build apk --release --split-per-abi \
  --dart-define=BACKEND_BASE_URL=https://your-backend.example.com
```

> 本仓即 Flutter 客户端仓库本身（`lib/`、`pubspec.yaml` 在根目录）。App 默认本地优先：书架、阅读、角色卡、文字游戏存档全部离线可用；AI 能力按需联网。

**深入文档**

- [开发者指南](docs/developer-guide.md) · [部署指南](docs/deployment.md) · [本地开发](docs/local-dev.md) · [文字游戏设计](docs/text_game.md) · [项目模块说明](CLAUDE.md)

**贡献**

欢迎提 Issue / PR，详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

</details>

---

<div align="center">

**觉得这个 APP 有用？给个 ⭐ 支持一下独立开发 🙏**

</div>

---

## 📄 许可证

本项目采用自定义许可协议：**个人学习、研究等非商业用途可免费使用，任何商业用途须事先取得作者书面授权**，详见 [LICENSE](LICENSE)。

v3.0.0-preview.4 及更早的发布版本基于 MIT 许可证发布，对应源码副本继续按 MIT 适用。
