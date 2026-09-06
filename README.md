<div align="center">

# 随心阅读
### Whimread · AI 原生小说阅读平台

**读喜欢的 · 改不爽的 · 写自己的**

[⬇️ 下载 APK](https://github.com/yunkst/Whimread/releases/latest)  ·  [🌐 在线介绍](https://yunkst.github.io/novel_builder/)  ·  [⭐ 给个 Star](https://github.com/yunkst/Whimread)

本地书架 · 任意网站阅读 · 离线缓存 · AI 改写 · AI 创作

</div>

---

## 📖 读 · APP 里就能逛任意小说站

打开 APP 就有一个**内置浏览器**。用它打开任意小说站，翻到目录页，右下角会浮出「加入书架」按钮——点一下就进书架了。

- 🌍 **任意站点都能加**：第一次访问某个站时，**AI 现场帮你生成提取脚本**（你要做的只是等一下、确认预览），之后这个站就一劳永逸——下次直接用，不用再生成
- 📖 **干净的正文**：从原页提取正文文本，正文里那些弹窗广告、"请下载 APP 继续"、推广链接，通通没有
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
- 🖼️ **顺手配图**：按场景描述生成封面或插图，文字+画面一起出（需后端 ComfyUI）
- 📚 **全部本地、永远属于你**：你的书、章节、角色都存在本地，导出备份随你带走

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
- 生图：`create_images` / `create_image_to_video` → 后端 ComfyUI（`agent_tools.dart:838+`）
- 本地存储：`bookshelf` / `novel_chapters` / `chapter_cache` 表，`backup_service.dart` 可导出

</details>

## 🧩 还能做这些

除了读/改/写三大核心，还有些顺手就能用的能力：

| 能力 | 说明 |
|---|---|
| 👥 **角色卡 & 关系图** | 手动建/AI 帮你建角色卡（姓名/外貌/性格/背景），人物关系用力导向图可视化 |
| 🎨 **场景配图 & 动态图** | 按段落描述生成插图，或把静态图变成动态视频（需后端 ComfyUI） |
| 💬 **让 AI 扮演角色** | 在 Agent Chat 里说"扮演 XX 角色跟我聊"，AI 按角色设定和你对话 |
| 📔 **多书架分类** | 「我的收藏」「玄幻」「待看」随便分，一本书可属于多个书架 |
| 🌗 **阅读风主题** | 护眼纸张色 + 衬线字体，长时间看也不累；亮/暗/跟随系统三档 |
| 📤 **本地备份导出** | 书架、进度、章节、角色全在本地 SQLite，随时导出备份带走 |

<details>
<summary>🔧 技术细节</summary>

- 角色卡：`characters` 表 v35（`first_appearance_chapter`）+ `character_list/detail/edit_screen.dart`；AI 创建角色走 `create_character` / `update_character` 工具（`agent_tools.dart:481-537`）
- 关系图：`character_relationships` 表（v35 区间模型）+ `relationship_graph_screen.dart` + `flutter_force_directed_graph`
- 场景配图 & 动态图：`create_images`（文生图）+ `create_image_to_video`（图生视频，依赖后端 ComfyUI）+ `media_proxy.dart` 媒体代理 + `media_cache_screen.dart`
- AI 扮演角色：Agent Chat 调用 + 角色设定 prompt（由用户在角色卡里编辑）注入
- 多书架：`bookshelves` / `novel_bookshelves` 多对多表（v16）
- 主题：阅读风令牌 paper/ink/赭石/金，`app_colors.dart`
- 备份：`backup_service.dart` 导出本地 SQLite → 后端 `/api/backup/*`（4 端点）

</details>

## 🔧 面向开发者

<details>
<summary>点开看技术栈与构建</summary>

**技术栈**

- 前端：Flutter 3.0+ / Dart / Riverpod / SQLite (v39) / Material 3
- AI 层：OpenAI 兼容 LLM + Agent Chat（多 Subagent 协作）+ 端侧 PP-OCRv6 (onnxruntime)
- 章节：Headless WebView + 本地 JS 提取脚本（`site_scripts` 表）
- 后端（可选）：FastAPI + ComfyUI（文生图/图生视频）+ 备份/日志上报

**源码运行**

```bash
git clone https://github.com/yunkst/Whimread.git
cd novel_builder/novel_app
flutter pub get
flutter run
```

> App 默认离线可用，本地书架/阅读/Agent Chat/角色卡均无需后端。后端只在需要 AI 生图/备份/日志时才启动。

**深入文档**

- [开发者指南](docs/developer-guide.md) · [部署指南](docs/deployment.md) · [前端模块](novel_app/CLAUDE.md) · [后端模块](backend/CLAUDE.md)

**贡献**

欢迎提 Issue / PR，详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

</details>

---

<div align="center">

**觉得这个 APP 有用？给个 ⭐ 支持一下独立开发 🙏**

</div>

---

## 📄 许可证

本项目采用 [MIT 许可证](LICENSE)。
