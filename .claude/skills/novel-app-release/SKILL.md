---
name: novel-app-release
description: Use this skill when building and releasing the Novel Flutter app. This skill provides version management, AI-driven changelog generation, pre-publish validation (analyze + unit tests + APK build), and git commit + tag + push. APK release build is handled by GitHub Actions automatically. Trigger this skill when user asks to "release app", "publish new version", or "deploy app update".
---

# Novel App Release Skill

## Overview

此技能用于自动化 Novel Flutter 应用的发布流程。**由 Claude 执行时,changelog 由 AI 分析代码变更后撰写**(高质量、语义化);脚本本身保留规则生成作为 CI / 纯手动运行的兜底。

**⚠️ 默认发布预览版**。除非用户明确说"发稳定版"、"发正式版"、"stable release",否则一律按预览版发布(tag 含 `-preview.N` 后缀,只有开启「获取预览版」开关的用户能收到)。

发布流程:
1. **确认版本号** — `pubspec.yaml` 的 `version` 已递增
2. **确定发布类型** — 默认预览版,除非用户明确要求稳定版
3. **生成更新日志** — Claude 分析 git diff/log,撰写面向用户的 changelog
4. **运行发布脚本** — 预检(analyze + test + build)→ commit → tag → push → 等 CI
5. **报告结果** — CI 成功即发布完成

> 推送 tag 后,**GitHub Actions**(`.github/workflows/flutter-release.yml`)自动构建 Release APK 并创建 GitHub Release。
> **CI 检查**:push 后等待约 10 分钟(释放构建时间),通过 `gh run list` 确认成功。

## 何时使用

- 用户请求发布新版本应用
- 用户说"发布 APP"、"publish new version"、"deploy app update"

> **默认预览版**:上述任一触发,**默认按预览版发布**(tag `vX.Y.Z-preview.N`),只推送给开启「获取预览版」开关的用户。
> 仅当用户**明确**说"发稳定版"、"发正式版"、"发 stable"、"给所有用户更新"时,才走稳定版通道(tag `vX.Y.Z`,推送给所有用户)。

## 环境要求

- **Git** — 需要能 push 到 origin
- **Python 3.10+** — 运行发布脚本
- **Flutter SDK 3.x (stable)** — 预检需要(analyze + test + build apk)

## 执行流程

### 第零步:确定发布类型(预览版 / 稳定版)

| 用户表述 | 发布类型 | 版本号示例 | 推送范围 |
|---------|---------|-----------|---------|
| "发布"、"发个新版"、"发 APP"(默认) | **预览版** | `2.0.0-preview.1+108` | 仅开启开关的用户 |
| "发预览版"、"发 preview" | **预览版** | `2.0.0-preview.1+108` | 仅开启开关的用户 |
| "发稳定版"、"发正式版"、"发 stable" | 稳定版 | `2.0.0+108` | 所有用户 |

**预览版版本号推导**(默认路径):
- 查看上一个 tag(`git describe --tags --abbrev=0`)
- 若上个是稳定版 `vX.Y.Z` → 本次预览版基线递增小版本号 `vX.{Y+1}.0-preview.1`（如 `v2.0.1` → `v2.0.2-preview.1`）
- 若上个是预览版 `vX.Y.Z-preview.N` → 本次 `vX.Y.Z-preview.{N+1}`（同基线继续迭代）
- 若上个 tag 是 `vX.Y.0-preview.N`（首个小版本为 0 的预览版）→ 继续该基线迭代，不递增
- version_code 始终递增

**稳定版版本号推导**(仅用户明确要求):
- 取当前预览版基线 `vX.Y.Z-preview.N`,去掉后缀 → 稳定版 `vX.Y.Z`
- version_code 始终递增

> 判定不准时直接问用户,不要猜。尤其"发稳定版"会推送给所有用户,影响面大,务必确认。

### 第一步:确认版本号已更新

检查 `novel_app/pubspec.yaml` 的 `version: x.y.z+code`,`+code` 必须递增。若用户未更新,提醒或代为更新。

```yaml
# 例如
version: 1.9.2+75  →  version: 1.9.3+76
```

### 第二步:生成更新日志(AI 驱动,核心)

**这是本次发布用户能看到的核心信息,必须由你(Claude)分析代码后撰写,不要依赖脚本的机械生成。**

#### 1. 收集变更信息

```bash
# 上次发布以来的 commit(如果有新 commit)
LAST_TAG=$(git describe --tags --abbrev=0)
git log --no-merges --pretty=format:"%h %s" $LAST_TAG..HEAD

# 工作区未提交的改动(直接发布、未预先 commit 时主要看这个)
git diff HEAD --stat
git ls-files --others --exclude-standard
# 必要时看具体 diff 内容理解改动语义
git diff HEAD novel_app/lib
```

#### 2. 分析并起草 changelog

读懂上述信息,**站在用户视角**描述"这次更新我能感知到什么变化":

✅ **好的写法**(语义化、功能导向):
```markdown
### ✨ 新功能
- 预加载队列新增历史记录追踪,调试面板可可视化查看队列状态

### ♻️ 重构
- 移除自定义 Deque 实现,改用标准 List,简化预加载队列逻辑
```

❌ **差的写法**(机械、文件导向,这是脚本兜底的水平,不要止步于此):
```markdown
### 🔧 其他
- 优化服务层(5 个文件)
- 优化界面(2 个文件)
```

#### 3. 写作原则

| 原则 | 说明 |
|------|------|
| **语义化** | 描述功能/行为变化,不要罗列文件名 |
| **用户视角** | 写"用户能感知什么",不是"改了哪些代码" |
| **分组合并** | 相关改动合并成一条,避免碎片化 |
| **精简措辞** | 每条一行,重点可加粗 |
| **如实反映** | 没有实质改动就写"Bug 修复和性能优化",不要编造 |

#### 4. 分类与 emoji

| 类型 | emoji | 适用场景 |
|------|-------|---------|
| 新功能 | ✨ | 用户新能看到/用到的东西 |
| 修复 | 🐛 | bug 修复 |
| 优化/重构 | ⚡ / ♻️ | 性能、体验、内部重构 |
| 文档/测试 | 📚 / ✅ | 通常不写入面向用户的日志 |

#### 5. 注入 changelog

把写好的内容通过 `CHANGELOG` 环境变量传给脚本(脚本会优先使用它,跳过规则生成):

**bash / Git Bash**:
```bash
CHANGELOG="$(cat <<'EOF'
### ✨ 新功能
- 预加载队列新增历史记录追踪,调试面板可视化队列状态

### ♻️ 重构
- 移除自定义 Deque 实现,改用标准 List
EOF
)" python .claude/skills/novel-app-release/scripts/build_and_upload.py
```

**Windows PowerShell**:
```powershell
$env:CHANGELOG=@"
### ✨ 新功能
- 预加载队列新增历史记录追踪
"@
python .claude/skills/novel-app-release/scripts/build_and_upload.py
```

### 第三步:运行发布脚本

```bash
python .claude/skills/novel-app-release/scripts/build_and_upload.py
```

脚本内部执行 4 个阶段(已包含上一步注入的 changelog):

| 阶段 | 内容 | 失败处理 |
|------|------|----------|
| 1. 预检 | `flutter analyze` + 单元测试 + 本地 Release APK 打包 | 任一失败即中断 |
| 2. 版本识别 + changelog | 读 `pubspec.yaml` 版本;changelog 取自 `CHANGELOG` 环境变量(无则规则生成兜底) | — |
| 3. git 操作 | `git add .` → `commit` → `tag -a v{version}` → `push` | 失败即中断 |
| 4. CI 验证 | 等待 10 分钟 → `gh run list` 查 CI 状态 | 报告 success/failure/pending |

> 预检三步与 `.github/workflows/flutter-ci.yml` + `flutter-release.yml` 完全一致,任一失败 GitHub Actions 也会失败,必须先修复。

#### changelog 写入载体

脚本把 changelog 写进 **annotated tag message**:
```bash
git tag -a v1.9.3 -m "Release 1.9.3

{changelog 内容}"
```
GitHub Actions 的 `flutter-release.yml` 会用 `git tag -l --format='%(contents)'` 反向取出,渲染进 `.github/release_template.md` 的 `<!--CHANGELOG_START-->...<!--CHANGELOG_END-->` 标记,最终成为 GitHub Release body。App 端 `_extractChangelog()` 据此标记裁取并展示在更新弹窗。

### 第四步:报告发布结果

根据脚本输出报告:
- ✅ `success` — 发布完成,给出 Release 页面链接
- ❌ `failure` — 打印失败日志链接,提示修复后用新版本号重发
- 🟡 `pending` — 提示几分钟后手动检查 Actions 页面

## 脚本兜底机制(无需 Claude 介入时)

若运行脚本时**未设置 `CHANGELOG` 环境变量**,脚本会用规则自动生成 changelog 作为兜底(CI 自动触发、纯手动跑脚本时适用):

- **commit history**:上次 tag 到 HEAD 的非 chore commit,按 Conventional Commits 前缀分类(`feat`→✨、`fix`→🐛、`refactor`→♻️ 等)
- **工作区 diff**:未提交/未跟踪的 `novel_app/` 代码变更,按 `lib/` 子目录归类成模块摘要(新增→✨、删除→♻️、修改→🔧)

> ⚠️ 兜底输出是**文件/模块级**的机械摘要(如"优化服务层(5 个文件)"),语义质量有限。**Claude 执行时应始终走第二步(AI 生成),不要依赖兜底。**

## 跳过预检(不推荐)

紧急修复或已知 CI 失败点时:

```bash
SKIP_PREFLIGHT=1 python .claude/skills/novel-app-release/scripts/build_and_upload.py
```

> ⚠️ 跳过预检后 GitHub Actions 仍会运行同样检查,失败则发布实际失败。

可通过 `SKIP_CI_CHECK=1` 跳过 10 分钟 CI 等待(不推荐)。

## 版本管理

### 版本号格式

`pubspec.yaml` 中:`version: 1.9.3+76`

- `1.9.3` — 版本名称
- `76` — 版本代码,必须递增

### 发布通道(stable / preview)

支持两个发布通道,通过 tag 命名自动区分,**无需手动设置 prerelease 标志**:

| 通道 | Tag 格式 | 示例 | GitHub prerelease | 谁能收到 |
|------|---------|------|-------------------|---------|
| 稳定版 | `vX.Y.Z` | `v2.0.0` | `false` | 所有用户 |
| 预览版 | `vX.Y.Z-preview.N` | `v2.0.0-preview.1` | `true` | 仅在 APP 中开启「获取预览版」开关的用户 |

**CI 自动判定逻辑**(`flutter-release.yml` 的 `Detect prerelease` 步骤):

```bash
# tag 含 '-' → prerelease=true(预览版)
# tag 不含 '-' → prerelease=false(稳定版)
if [[ "${{ steps.tag.outputs.name }}" == *-* ]]; then
  echo "flag=true" >> $GITHUB_OUTPUT
else
  echo "flag=false" >> $GITHUB_OUTPUT
fi
```

> 判定依据是 tag 是否含 `-`,而非具体后缀(如 `-preview` / `-alpha` / `-beta`)。
> 纯语义化版本号 `v2.0.0` 一定不含 `-`,所以稳定版判定可靠。

**App 端获取逻辑**(`github_release_service.dart`):

- 用户**关闭**「获取预览版」(默认):请求 `/releases/latest`,GitHub API 原生跳过所有 prerelease,永远返回最新稳定版
- 用户**开启**「获取预览版」:请求 `/releases?per_page=10`,客户端按 `created_at` 降序取最新一条(排除 draft)。
  > 不用 `per_page=1`:GitHub `/releases` 默认排序在 prerelease 存在时不可靠(社区讨论 #21901),
  > 可能返回 semver 更高的稳定版而非时间最新的预览版。客户端显式排序确保拿到最新发布的版本。

#### 发布预览版(默认)

**除非用户明确要求稳定版,否则一律发预览版。** 预览版只推送给开启「获取预览版」开关的用户,适合平时迭代快速验证。

版本号推导(见「第零步」):
- 上个稳定版 `vX.Y.Z` → 本次 `vX.Y.Z-preview.1`
- 上个预览版 `vX.Y.Z-preview.N` → 本次 `vX.Y.Z-preview.{N+1}`

```yaml
# pubspec.yaml 示例(从 2.0.1 稳定版发首个预览版 → 基线递增为 2.0.2)
version: 2.0.2-preview.1+110
```

```bash
# 发预览版:tag = v2.0.0-preview.1
# changelog 写入方式与稳定版完全一致
CHANGELOG="..." python .claude/skills/novel-app-release/scripts/build_and_upload.py
```

脚本会创建 `v2.0.0-preview.1` tag,CI 自动标记为 prerelease,只有开启预览版的用户能收到。

#### 预览版转稳定版(用户明确要求时)

当用户明确说"发稳定版"时,去掉 `-preview.N` 后缀发同名稳定版,推送给所有用户:

```yaml
# pubspec.yaml
version: 2.0.2-preview.1+110  →  version: 2.0.2+111  # version_code 递增，去掉 -preview.N
```

```bash
# 发稳定版:tag = v2.0.0
CHANGELOG="..." python .claude/skills/novel-app-release/scripts/build_and_upload.py
```

> 同一版本号(如 `2.0.0`)的预览版和稳定版可以共存:
> `v2.0.0-preview.3`(prerelease=true)→ 预览通道
> `v2.0.0`(prerelease=false)→ 稳定通道
> 这两个 tag 指向不同 commit,互不干扰。

## GitHub Actions 流程

tag `v*` 推送后自动触发(`.github/workflows/flutter-release.yml`):

| 步骤 | 说明 | 本地是否预跑 |
|------|------|--------------|
| Checkout | 检出代码(fetch-depth=0) | — |
| Extract changelog | 从 tag message 取 changelog | — |
| Render release body | 套用 `release_template.md` | — |
| Setup Flutter | 安装 Flutter SDK | — |
| **Build release APK** | `flutter build apk --release --split-per-abi` | ✅ |
| Create GitHub Release | 上传 APK + SHA256,生成 Release | — |

PR / push 到 main 时(`.github/workflows/flutter-ci.yml`)还会跑:

| 步骤 | 说明 | 本地是否预跑 |
|------|------|--------------|
| **Analyze** | `flutter analyze --no-fatal-infos` | ✅ |
| **Run unit tests** | `flutter test --no-pub test/unit/ test/bug/ test/verification/` | ✅ |

## 常见问题

### Q: 预检失败了怎么办?

1. 阅读脚本输出,定位是 analyze / test / build apk 哪一步失败
2. 修复代码(不要跳过预检掩盖问题)
3. 重新运行脚本

### Q: 怎么确认 Release 成功?

脚本会自动等 10 分钟并检查 CI。手动确认:
1. 本地 tag:`git tag -l "v*"`
2. Actions:`https://github.com/yunkst/Whimread/actions`
3. Release:`https://github.com/yunkst/Whimread/releases`

### Q: 推送失败怎么办?

通常是网络或远程有新 commit。先 `git pull --rebase` 再重跑。tag 已建但推送失败时:
```bash
git push origin v1.9.3
```

### Q: 想回退一个错误发布?

```bash
git tag -d v1.9.3                    # 删本地 tag
git push origin :refs/tags/v1.9.3    # 删远程 tag
git reset --soft HEAD~1              # 回退 commit
```

## 文件结构

```
.claude/skills/novel-app-release/
├── SKILL.md                    # 本文档
├── FIXES.md                    # 修复记录
└── scripts/
    └── build_and_upload.py     # 发布脚本(preflight + changelog兜底 + commit + tag + push)
```

## 变更记录

- **2026-07-19**: 修正预览版基线推导规则：从稳定版发预览版时基线递增小版本号（`v2.0.1` → `v2.0.2-preview.1`），而非沿用稳定版小版本号。稳定版发完后再迭代新功能应走更高的 minor 版本。
- **2026-06-22**: changelog 生成改为 **AI 驱动**:SKILL.md 新增「第二步:生成更新日志」专章,指导 Claude 分析 git diff/log 撰写语义化 changelog 并通过 `CHANGELOG` 环境变量注入脚本;脚本规则生成降级为兜底机制(CI / 纯手动运行时);明确职责分工
- **2026-06-22**: changelog 数据源扩展为双源(commit history + 工作区 diff);工作区 diff 按 novel_app/lib 子目录归类成模块摘要,无需预先 commit 也能产出 changelog
- **2026-06-22**: 重写 changelog 自动生成:从 git diff 文件路径分析改为 Conventional Commits 分类,输出 Markdown 分组格式,自动跳过 chore/release/style/build commit;commit message 不再附加 changelog(仅 tag message 保留)
- **2026-06-17**: 新增阶段 4(等待 10 分钟 + CI 检查),通过 `gh run list` 验证 release workflow 状态;支持 `SKIP_CI_CHECK=1` 跳过
- **2026-06-13**: 新增预检阶段(flutter analyze + unit test + 本地 APK 打包),与 CI 流程完全对齐;支持 `SKIP_PREFLIGHT=1` 跳过
- **2026-06-12**: 移除本地 APK 构建和后端上传,改为纯 git 操作 + 依赖 GitHub Actions 构建;增加 commit push
- **2026-06-12**: 初版:构建 APK + 上传到 backend
