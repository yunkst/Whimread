# 文字游戏（互动小说）设计说明

> 2026-10-02 引入。游戏运行时复用 Agent 场景体系（text_game scenario），
> 游玩页是全新独立页面（不搭通用聊天壳）。
> 2026-10-02 统一模型：**游戏必须绑定小说，角色卡共享小说 characters 表**
>（含头像/近况），并引入**角色卡版本管理**（character_revisions）。

## 总体架构

```
写作助手（writing 场景对话）              文字游戏 Tab / 游玩页
  探讨设定 ── create_text_game ──┐            │
                                 ▼            ▼
                    text_games 表（游戏侧设定）  TextGamePlayController（独立状态层）
                    chat_session（剧情历史）◄── ScenarioSession(text_game)
                                 │            │
                                 ▼            ▼
                    AgentLoop ◄── TextGameScenario（GM：静态协议 + 动态设定块 + 回合工具）
                         │                    │
                    characters 表 ◄────────── 共享角色卡（参战名单引用）
                    character_revisions（版本记录）
                                 │
                    narrate / speak / present_choices / create_scene_image
                    / roll_random_event
```

- **一个游戏 = text_game 场景下的一个 chat_session**：持久化 / 上下文压缩 /
  失败重试 / hydrate 重放全部复用现有设施；消息链是剧情的真理源。
- **必须绑定小说**：settings_json 只存游戏侧数据（开场/规则/参战名单
  characterIds/玩家角色卡 playerCharacterId），角色设定不再拷贝——改卡后
  游戏下一轮即生效，头像/别名/版本管理天然共享。自定义玩法 = agent 先
  create_novel 建轻量小说壳再绑定（用户无感）。
- **同刻只玩一局**：ScenarioSession 按 scenarioId 单实例，切换游戏 =
  `adoptSession` 自动中断上一局运行中的回合并落库 partial（存档）。
- **离开游玩页**：控制器 autoDispose 停止监听，agent 继续在后台跑完，
  回来重放消息链。

## 回合协议

每回合：玩家输入（user 消息）→ agent 输出剧情 → present_choices 收尾。

| 工具 | 作用 | 执行 |
|---|---|---|
| `narrate(text)` | 旁白（环境/时间/剧情推进 + 角色动作/神态/心理描写） | 参数即内容，返回 `{ok:true}` |
| `speak(character, text)` | 登场角色台词（**纯直接引语**，动作神态走 narrate） | 校验角色在参战名单（名字或别名） |
| `create_scene_image(prompt)` | 关键场景插图 | **异步**：入队立即返回，完成后自动插入 |
| `present_choices(choices[2-4])` | 结束回合，交给玩家 | 校验数量；**终止工具**：成功即 AgentLoop 结束回合 |
| `update_game_state(character_name?, target?, add_facts, remove_facts?, reason?)` | 状态账本回写 | 三类目标：角色（传 name）/ 玩家（省略）/ 世界与剧情线（target="world"）；add/remove 条目，单条 ≤60 字、每目标 ≤8 条；remove 按包含匹配，未命中/超限在返回值引导 |
| `create_character(name, ...)` | 剧情引入新角色 | 落小说角色卡 + 自动入参战名单（同名卡复用） |
| `roll_random_event(events[2-6], reason?)` | 概率判定：多分支随机 outcome | 按相对权重归一化随机抽取一个分支（weight 省略=1 等概率）；结果即锁定，返回 note 明示不得改写/重判；每次判定落日志（分支+权重+结果） |

规则：
1. **剧情内容禁止裸文本输出**——所有内容经工具，保证 UI 可渲染（旁白段落、
   台词气泡、选项按钮）。双侧强制：① 投影器侧 assistant 裸文本**一律不渲染**
   （只有 narrate/speak/present_choices/create_scene_image/roll_random_event
   等工具产出入剧情流——绕过工具写的正文玩家看不到）；② `onNoToolCalls` 钩子
   注入一次协议提醒（前缀 `【协议提醒】`，同样过滤不渲染）要求 GM 用工具重写，
   提醒轮的内容经工具输出后在同一回合内呈现。
2. **推进幅度 = 完整剧情单元**：一回合把一个场景从铺垫写到收束（若干轮
   NPC 对话、动作、局势变化），不要写一两段就停下来问玩家。NPC 交流、环境
   演变、以及玩家角色**不影响走向的过场动作/简短应答**由 GM 在叙述中合理
   带过；只在真正的**分岔口**（不同选择导向明显不同的走向/代价/关系变化）
   停下来交给玩家——"主角任何一句话都要玩家选"是节奏慢的主因（用户反馈）。
3. **关键抉择收尾**：每回合仍必以 present_choices 收尾，但只给**关键抉择**：
   每个选项导向明显不同的走向/不可逆代价/关系质变；细枝末节（说哪句话、
   无关痛痒的小动作）不拿来问玩家，结果大同小异的"伪分岔"不硬凑。玩家
   始终可自由输入补充行动。代码兜底不变：
   - **终止工具**（`AgentScenario.terminalToolNames` = {`present_choices`}）：
     该工具成功即回合终点，AgentLoop 跑完本轮工具、入链后立即
     `AgentDoneEvent`，不再请求下一轮（工具返回 error 时不终止，交给 LLM
     纠偏重调）。缺这一层时 GM 交完选项会被 onNoToolCalls 的提醒推着续写，
     把同一段剧情重演一遍并二次提交选项（用户反馈 #10 的现场）。
   - **投影器回合截断**：每回合首个 `present_choices` 之后同回合的
     旁白/台词/插图/判定/重复选项一律不渲染——历史脏数据重放时同样自愈。
   - 另有「自动补选」：`diagnoseTurnEnding` + `shouldAutoNudgeChoices`
     守卫（失败回合不补、玩家按过「停止」绝不重启、每条玩家输入至多补 1 次）。
4. **台词与描写分离**：`speak.text` 只放角色说的话本身（含语气词/称呼），
   角色的动作/神态/心理一律走 `narrate`——两者渲染样式不同（台词=带头像与
   底色气泡，旁白=无装饰阅读段落），混写会让玩家分不清谁在说话。
5. **状态账本**：角色/玩家的重大持久变化（致残/突破/关键物品得失/立场质变）
   与世界线动向（任务/势力/悬念）以**条目**记录——`add_facts` 新增、
   `remove_facts` 划掉不再成立的旧条目（引用动态块原文），加事实不丢旧事实、
   过期状态显式退场；近况/世界逐条进每轮动态上下文抗遗忘。角色卡变化落
   版本历史（source=text_game + reason）。基底设定（性格/来历/说话风格）
   GM 不可写——近况条目覆盖演出，基底只在手动编辑/写作助手改动（过版本）。
6. **概率判定**：剧情分岔的随机性（战斗胜负/行动成败/机关触发/随机遭遇）
   交给 `roll_random_event`——GM 提交全部分支（含失败分支）与相对权重，
   系统抽取一个作为既定事实回填；GM 必须照结果演出，不得改写或重复判定
   （防"掷骰作弊"）。

## 核心体验（演出的最高准则）

`settings_json.coreExperience`：用户想获得的**游玩感受**（节奏快慢/爽感来源/
描写密度/叙事人称/挫败感容忍度），写成对 GM 的正向演出指令。来源三处：
创建时写作助手**必问**（ask_user 给候选方向）→ create_text_game 必填；
游玩中用户在设定编辑页手动修改；写作助手 update_text_game 可改。

GM 协议侧的让位（防体验偏差）：静态协议身份段声明「核心体验是演出的最高
准则，与其它设定或通用规则冲突时以它为准」；原硬编码的回合节奏默认值
（完整场景单元，3-6 段、600-1200 字）退为**未设定核心体验时**的兜底；动态块把
「核心体验」小节**置顶渲染**（排在世界观之前），GM 每轮最先读到。
无工具纠偏通道——体验诉求的修改只走设定编辑页 / update_text_game。

## 上下文布局（缓存友好）

```
[system: GM 身份 + 输出协议 + "设定见末尾状态块"指针]   ← 静态，前缀稳定
[剧情消息链（只增，可被压缩裁剪）]                      ← append-only
[「游戏当前状态」设定块 + 玩家输入]                     ← 动态，每轮重新生成
```

- **设定数据不进 system prompt、不落库**：由 `AgentScenario.buildDynamicContext`
  钩子（NovelAgentService 在 sendMessage / resumeFromMessages 构建载荷时
  应用）拼在最后一条 user 消息前缀，仅存在于运行时载荷
- 收益：静态前缀 + append-only 历史可命中供应商 prompt cache；设定被
  update_game_state 或手动编辑频繁变更时只影响尾部新 token，不使缓存失效
- 设定每轮从数据库新鲜读取：AI 回写或用户手动编辑后**下一轮即生效**

## 回合一次性展示（无流式）

GM 回合内容**不在写作过程中流出**：运行期间玩家只看到进度——底部「剧情
推进中」状态条（转圈 + 停止按钮）与 GM 幕后（思维链实时累积 + 动作标签
"正在描写旁白…"，可在 AppBar 开关）；回合收尾（AgentDone → session
finalize 汇总消息链）时，本回合全部产出（旁白/台词/插图/判定/选项）一次性
进入剧情流并自动滚到底部。

- **实现**：session 只在 finalize 时把 `_pendingSegments` 汇总为消息链，所以
  transcript 运行期间天然不动——游玩页不需要"扣住内容"的任何逻辑，也不再有
  打字机/定稿双渲染路径（`ToolArgDeltaEvent`/`streamableToolNames`/
  `GameStreamingPart` 等机制已整体移除，preview.14 的"打字机吞字"修复随之
  作废删除——那类 bug 的根源就是双路径）。
- runId 打标保留：text_game 所有运行统一 runId=sessionId（`ScenarioSession._
  launchAgentRun` 场景门控），GM 幕后事件据此过滤本局。

## 【后悔重置】（discard_output，loop 层拦截）

GM 在回合中发现写错（角色名写错/与既定事实矛盾/剧情走偏）时调用，撤回
**本回合尚未展示**的展示类调用——一次性展示保证了"未展示"这个前提，撤回
对玩家完全无感。

- 工具面恒在（不受插图策略影响）；可撤集合由 `AgentScenario.
  retractableToolNames` 声明（text_game = narrate/speak/present_choices）。
  既成事实类工具（update_game_state / roll_random_event / create_scene_image）
  已落库/回填，**不撤**——撤叙述不撤账本会造成状态与剧情不一致。
- `count` 可选：不传 = 本回合全撤；传 N = 只撤最近 N 条。
- **双处清理**：① `AgentLoop` 在本地 `messages`（下一轮 LLM 上下文）原位
  截断（`truncateRetractableToolCalls` 纯函数，单测覆盖）——GM 下一轮即
  "忘掉"作废草稿，不会锚着错误版重写；② emit `DraftDiscardedEvent`，
  `ScenarioSession` 据此从 `_pendingSegments` 移除对应段——否则回合收尾
  finalize 时作废内容会被汇总写回消息链落库，撤回失效。
- discard 调用本身照常入链留痕（工具卡/消息链），工具结果带精确撤回条数
  与"重新创作"指引；撤空后若 GM 直接停手，回合收尾的协议兜底
  （自动补 present_choices 提醒）照常生效。
- 防滥用写进协议与工具描述：仅在确实写错时使用（频繁撤回浪费额度且可能
  反复）。

## 场景生图（同步执行）

- `create_scene_image` 与 `create_images` **共用同一门面**
  `ImageGenerationService.generate`（模型三级回退、负向词、比例校验、
  错误码归一只有一份实现），无独立的场景生图服务。
- **同步语义**：工具执行内 `await` 到出图完成（端侧引擎数十秒），返回
  JSON 内含 mediaIds；GM 协议明确告知「调用后阻塞到出图完成，不要重复
  调用」。生成结果已同步落 MediaStore/media_items，游玩页渲染直接
  resolve 本地文件。
- 游玩页渲染：消息链 tool result 里的 mediaIds → `GameSceneImageView`；
  出图失败展示错误卡（工具返回 error 时调用状态为 error）。
- 回合被取消时若 create_scene_image 仍在跑，该调用以 running 状态入链，
  插图位展示占位 shimmer（等结果永不来的少数情况）。
- `imagePolicy`：auto = agent 判断关键场景主动调用；manual = 仅玩家点
  「生成插图」（发一条固定语义消息，agent 调工具，不推进剧情）。

## 游玩页（全新独立页面）

- `lib/screens/text_game/`：投影器（消息链 → GameSegment）、控制器（独立
  状态层）、游玩页；`lib/widgets/text_game/`：段渲染组件。**不 import
  widgets/agent_chat/ 任何组件**（媒体渲染复用通用 MediaView）。
- GameSegment 映射：user → 玩家输入气泡；narrate → 阅读器风格旁白段（无装饰
  文本）；speak → 台词气泡（彩色角色名签 + 头像 + 底色气泡，与旁白刻意拉开
  区分度）；create_scene_image → 插图卡；present_choices → 选项
  按钮组（只有最后一条可点；玩家输入精确命中 label 标记 ✓）；
  roll_random_event → 命运骰子卡。
- **失败调用不进剧情流**：`isFailedToolCall`（读持久化状态
  `AgentToolStatus.error/rejected`，即 AgentLoop `!result.containsKey('error')`
  落库的同一标志，不二次解析结果 JSON）判定 narrate/speak 失败
  （`unknown_character` / `missing_character` / 工具异常）。失败尝试视为
  "没演成"，GM 会按纠错提示重调，只渲染重调成功的那次——否则同一句台词
  会以"失败版 + 重调版"显示两遍（现场日志：speak 失败 → create_character →
  同文重调成功）。插图与骰子例外：失败态本身是信息（错误卡/判定失败），
  照常渲染。运行中（结果未产出）按未失败处理。
- **动画纪律：只为"本次到访新增的内容"播一次，历史永不重播**。游玩页在
  首次见到非空定稿链时播种（`_seedAnimationBookkeeping`）：链内已有的
  判定/选项 toolCallId 记为已播、记录链长度；回溯使链缩短时以当前长度
  重新起算。ListView 滚动重建/页面重入时按记账直接静态展示。
- **入场动画**（配合 GM 幕后进度感的补充）：
  - 选项组错峰入场（GameChoicesView，460ms）：回合收尾时定稿组随剧情流
    内联渲染（不常驻输入区上方，免得长期压掉阅读空间），逐个上滑淡入
    （每项错峰 0.16、单项占 0.66 区间），按 toolCallId 记账只播一次；
    历史选项组静态置灰。
  - 玩家输入气泡上滑淡入（260ms）：仅播种长度之后新增的输入。
  - 场景插图：生成中占位 shimmer 流光 + 转圈；出图后淡入+缩放登场
    （AnimatedSwitcher 按 mediaId 记账，同图重建不重播）。
  - 运行状态条"剧情推进中"三点依次明灭。
  - 命运骰子卡（见下）。
- **命运骰子卡**（GameDiceRollView，概率判定的可视演出）：三态——
  - **判定中**（工具未完成且回合 live）：循环动画，骰子自旋 + 分支高亮
    轮转 + 边框呼吸辉光，状态词「概率判定中」；
  - **揭晓**（结果首展，animate=true）：一次性扫动 1.8s——高亮沿分支
    减速轮转（easeOutCubic，步数 3n+选中项保证落点即选中），选中分支
    弹簧放大（过冲 1.16 回落 1.03）+ 主色辉光淡入 + 骰子减速回正；
  - **静态**：历史回放/滚动重建（animate=false）、判定中断（定稿链里
    未完成）、判定失败，直接展示落定态或错误。
  动画只播一次：游玩页按 toolCallId 记账（onAnimated 回调后入
  _settledRollIds），pending 段结果一出即播（不等回合结束）。
- 玩家输入（点选项 / 自由输入）都走 `session.sendMessage`；运行中输入走
  现有 supplementary inject 队列（只在每轮 LLM 调用前 drain）。**与终止工具
  的交互**：AgentLoop 在因 present_choices 终止前会先 drain 一次队列——有
  排队内容说明玩家在回合期间又发了言，注入并继续下一轮（GM 对新输入做出
  反应、重新收尾），队列为空才真正终止；否则补充消息会随运行结束被清队
  丢弃（玩家看到自己发了言、GM 毫无反应）。
- **扉页与跟随**：未开始的新游戏（含首回合失败重试）显示扉页
  `GameIntroView`——标题 + 开场情境/世界观可滚动卡片，「开始游戏」固定
  底部；键盘弹出时跟随状态下的剧情流继续贴底。管理页「剧情推进中」徽标
  按会话 id 归属到具体游戏（场景会话单例，跨游戏切换不错挂）。

## 回溯重选（历史选项继续）

历史选项组带「回溯到这一步」入口（确认弹窗说明不可恢复）。实现链路：

- 投影器给每个历史 `GameChoices` 记录锚点 `rollbackUiIndex` = 其后那条
  玩家输入在消息链（UI 列表）中的索引；跳过型系统文本（协议提醒/图片
  占位）不产生锚点，活动选项（其后无输入）锚点为 null 不可回溯。
- 控制器 `rollbackToChoices` → `session.rollbackToMessage(anchor)`：删除
  该玩家输入及其后全部剧情，内存与 DB 同步重写；运行中回溯先取消当前
  回合（partial 随切尾一并删除）。回溯后该选项组成为最后一条 → 恢复为
  可点选项（重选同一项 / 换一项 / 改自由输入均可）。
- 边界：设定演化（角色 arc / 玩家 stateNote）不随剧情回退，确认弹窗中有
  提示；被删消息上未完成的生图任务完成时按 toolCallId 定位失败，安全
  no-op（消息已不存在）。

## AI 模型入口（选模型，非「配置」）

游玩页「更多 → AI 模型选择」与管理页 AppBar 调参图标，两个入口都直接开
`showAgentModelPickerSheet` 模型切换抽屉（`AgentModelPickerSheet`，与 Agent
Chat 内切换同款）。

- 语义：LLM 走打包注入的托管后端，API Key 由服务端持有，客户端**只能选
  不能配**——入口文案是「AI 模型选择」而非「AI 模型配置」。历史上这里挂的是
  场景级自配 LLM 覆盖弹窗，托管模式下该机制不生效，弹窗只能显示一段托管
  说明（点开啥也选不了），用户反馈「好奇怪，点开就一个弹窗」即源于此。
- 目录来源 `GET {BACKEND_BASE_URL}/v1/models`（`managedModelProvider`，60s
  缓存，抽屉打开时强刷）；每行展示模型名、基准徽标、相对基准的消耗倍数。
  选中写 `managed_model_selection`（**全局单值，所有 Agent 场景生效**，
  作用于后续请求），抽屉内即时生效。
- 模型目录不可达时抽屉内展示空态与重试入口；`model_picker_sheet_test`
  直接 pump 抽屉本体覆盖三条行为。

## 重新开始（保留设定，重开一局）

游玩页 AppBar「更多 → 重新开始」：清空本局全部剧情，回到扉页
「开始游戏」前，从同一份设定重新开局。

- 入口在从未开始的新游戏上不显示（`state.isEmptyGame` 时无剧情可重开）。
- 实现链路：控制器 `restartGame` 复位取消标记/补选额度/运行态记账 →
  `ScenarioSession.clearConversation()`（内存 `_agentMessages` +
  `_pendingSegments` 清空、会话状态重置、`chat_session` 消息表清空，运行中
  先取消当前回合；取消会摘掉事件订阅，残留 loop 的迟到事件不会写回）→
  `_reproject`。**清的是剧情消息，不是游戏行**：会话 id 复用，设定全部保留。
- 设定保留范围：世界观、开场、参战名单、玩家角色、玩法规则、世界与剧情线
  条目——含游玩期演化（`update_game_state` 写入的角色近况/世界线条目、
  `create_character` 加入的参战角色）。与回溯重选「设定演化不随剧情回退」
  同一语义，确认弹窗如实告知。
- 动画记账（`_settledRollIds` / `_settledChoiceIds` / `_seededTranscriptLen`）
  在清空前复位——否则空链会先走「缩短重算」把播种长度钉在 0，新一局的内容
  反而不会按新到访重播入场/揭晓动画。
- 不可恢复：剧情消息直接删除，无版本记录（与回溯重选一致）。

## 「GM 思考」开关（可选幕后展示）

游玩页 AppBar 的心理学图标切换（SharedPreferences 持久化，全局偏好）。
开启后，剧情流尾部出现「GM 幕后」块，实时展示两类信息：

- **思维链**：模型的 reasoning_content 增量（`ReasoningDeltaEvent`，由
  `AgentLoop` 从流式 chunk 原样透出——此前该数据在 provider 层被丢弃）。
  仅部分模型/网关提供；不提供时此区域为空。
- **幕后动作**：工具调用开始的语义化标签（"正在描写旁白…" / "林昭 正在
  说话…" / "正在整理本回合选项…" / "正在提交场景插图…" / "正在记录剧情
  状态…" / "正在进行概率判定…"），来自 ToolCallStartEvent。

机制约束：思维链**不落库、不进消息链**，动作开始即清空上一段思考（防跨轮
堆积）；离开页面/回合结束后不可回看。与"纯剧情视图"的产品默认（沉浸、
不透明）形成对照——这是玩家主动开启的透视模式，默认关闭。

## 角色卡共享与版本管理

**共享模型**：游戏参战名单（settings_json.characterIds）引用小说 characters
表的行；玩家角色也是一张卡（playerCharacterId），occupation 填身份、
backgroundStory 填初始目标。角色卡新增两列：`speechStyle`（说话风格）、
`currentState`（**近况账本**：一行一条条目，单条 ≤60 字、每卡 ≤8 条，
由 GM update_game_state / 手动编辑共同增删），头像 avatarMediaId 沿用
v34 既有列。factory 每次运行按名单加载角色卡渲染动态上下文（近况逐条
`·` 渲染在档案之后，演出以近况为准）；改卡后下一轮生效。

**世界与剧情线**（settings_json.worldNotes）：任务/势力动向/未解悬念的
持久锚点，同一账本语义（target="world"），动态块独立小节每轮在场——旧
对话被压缩裁掉后主线不丢。游戏侧数据，**不进角色卡版本管理**（变更痕迹
在剧情消息链的工具调用里），玩家可在设定 sheet 查看并在编辑页手动增删。

**版本管理**（DB v53 `character_revisions`）：所有改卡路径（手动编辑页 /
头像设置 / 写作助手 create_character·update_character / 文字游戏
update_game_state·create_character）在**成功修改后**追加一条改后整卡快照，
带三元组 `{source, sourceRef, reason}`：

- source：manual（手动编辑）/ writing_agent（写作助手）/ text_game（文字
  游戏）/ rollback（回滚动作本身）
- reason：agent 回写时由工具参数给一句话（如「击败风笑天，获得玄重尺」），
  手动路径记「更新头像」等

版本历史页（角色详情页 / 游戏设定 sheet 每个角色行的 ⏱ 入口）：时间 /
来源徽标 / 原因列表 → 点开看整卡快照 → 一键回滚。**回滚 = 写回快照 + 追加
一条 rollback 版本**（append-only 线性历史，回滚可再回滚）。角色删除时其
版本记录级联清理。

设计取舍：游戏演化直接写共享卡（而非游戏侧私有），同一小说多局会互相可见
——靠「同刻只玩一局 + 来源可溯 + 可回滚」兜底；世界观事实以最新卡为准。

## 台词头像

游玩页台词段渲染小圆头像：控制器进页时按参战名单加载
名字/别名 → avatarMediaId 映射（`avatarByName`），投影器把映射写进台词段
（`GameDialogue.avatarMediaId`），经 `AvatarMedia` 渲染（媒体缺失回退姓名
首字占位，无映射回退纯彩色名）。

## 创建入口（小说写作助手）

`WritingScenario` 工具：`create_text_game`（**必绑小说**：source_novel_id +
**coreExperience（核心体验，必问必填）** + character_names 参战名单 +
player_character_name 玩家卡（按角色名引用，全经归属校验）；双行落库）/
`list_text_games` / `update_text_game`（参战名单支持 add/remove_character_names
增量调整或 character_names 整体替换，二者互斥，玩家角色不可移出；可改
coreExperience，传空串 = 清空、GM 回退通用节奏）。系统提示词「文字游戏」
流程：确定绑定小说（书架小说 id，或 create_novel 建轻量壳）→ 逐项探讨确认
（**核心体验必问**：用 ask_user 给候选方向 + 节奏/人称/挫败感确认）→
create_character 落全部角色卡（含玩家卡）→ create_text_game 传角色名引用。
创建成功后聊天窗口的工具卡下方渲染「进入文字游戏」跳转入口
（`TextGameEntryCard`，解析结果里的 gameId 直达游玩页），与章节写作的
「查看新创建的章节」同一模式；游戏同时出现在底部管理页。

## UI 入口

- 底部第 2 个 Tab「文字游戏」= 管理页（列表 / 进行中徽标 / 空态引导 /
  新建按钮预填草稿打开写作助手）。
- text_game 场景 `showInChatMenu=false`：不出现在通用聊天的场景菜单
  （在聊天里玩会退化成无选项纯文本）；AI 模型配置入口在管理页/游玩页菜单。

## 数据（DB v53）

```
text_games: id / title / sourceType(novel) / sourceNovelId / sourceNovelTitle /
            settingsJson / status(active|finished|abandoned) /
            chatSessionId / coverMediaId / lastPlayedAt / createdAt / updatedAt
+ idx_text_games_session(chatSessionId)

characters（共享，v53 加列）: ... 既有列 ... / speechStyle / currentState
character_revisions: id / characterId / snapshotJson(改后整卡) /
                     source(manual|writing_agent|text_game|rollback) /
                     sourceRef / reason / createdAt
+ idx_character_revisions_char(characterId)
```

settingsJson（瘦身后）：worldview（空 = 回退小说 backgroundSetting）/
opening / **coreExperience（核心体验，GM 演出最高准则）** /
**characterIds（参战名单，引用 characters.id）** /
**playerCharacterId（玩家角色卡 id）** / **worldNotes（世界与剧情线条目）** /
rules[narrativeStyle, contentBoundary, choicesCount(2-4), imagePolicy(auto|manual)]。

近况演化在共享角色卡的 currentState（每行一条账本），世界线在 worldNotes，
进每轮动态上下文抗遗忘；角色卡修改落版本记录（见「角色卡共享与版本管理」）。

删除游戏 = 单事务删 chat_session 行（messages 经 FK CASCADE）+ text_games 行；
删除小说 = 书架删除入口检测绑定游戏，提示后一并删除。

## 手动编辑设定

游玩页/管理页的「查看设定」sheet 底部有「编辑设定」入口，进入全屏编辑页：
标题 / **核心体验（GM 演出的最高准则）** / 世界观 / 开场 / 规则（叙事风格、
内容边界、选项数、插图策略）/ **世界与剧情线（每行一条）** / **参战名单
勾选（该小说下的角色卡）+ 玩家角色指定**。角色卡内容（性格/近况账本/
说话风格/头像）属共享卡，点行进角色详情/编辑页维护（近况字段同样每行一条）。
保存后游戏中下一轮生效。

## 已知边界（v1 接受）

- 生图任务仅内存态：App 被杀则队列丢失，历史卡片显示「生成中断」占位
  （无重试按钮）。
- 生图完成事件若发生在 compaction 整链重写之后且会话未驻内存，历史卡片
  可能退化为占位（媒体文件仍在）。
- 生图任务表无上限：长会话多次生图缓慢累积内存（单任务很小，可后续加
  已完成任务清扫）。
- create_text_game 双行落库非事务：极小概率游戏行失败留下孤儿会话。
- 【后悔重置】截断的是 loop 内存消息链与会话待定稿段，已落库的历史回合
  不受影响；撤回不计费不限次，重写的 token 消耗是既有取舍。
- 回溯重选不回滚设定演化：删掉的是消息链剧情，此前 update_game_state 已
  写入的角色近况/玩家状态保留（视为已确立的世界观事实）。
- text_game 场景工具不支持单工具重试（`retryToolCall` 已显式拒绝）。
- 台词头像映射进页加载一次：游戏中途 GM 新建的角色（尚无头像）不出现在
  映射里，重新进入游玩页后生效。
- 旧快照回滚对跨版本字段容错：parseSnapshot 对缺键补默认值（快照永远由
  改后 toMap 生成，正常路径不触发）。
- 同一小说开多局共享角色卡：一局的角色演化对另一局可见（版本可溯源可回滚），
  v1 接受。
