# Whimread 后端 CloudBase 迁移设计

- **日期**:2026-09-07
- **作者**:yunkst(与 ZCode 协同设计)
- **状态**:草案,待用户审阅
- **信息源**:本设计**主要基于**已安装的 CloudBase skill(`tencentcloudbase/cloudbase-skills` v2.33.0)真实文档内容;少量基于工程经验补充的判断会明确标注 [判断]。

---

## 1. 背景与目标

### 1.1 现状(基于 `lib/services/api_service_wrapper.dart` 与 `CLAUDE.md`)

Whimread 当前后端形态:

| 能力 | 现状 |
|---|---|
| 后端运行时 | 自建 Python(FastAPI,端口 3800) |
| LLM 转发 | 用户自配 API(OpenAI 兼容) + 托管 LLM Provider |
| 设备注册 / JWT | `/api/v1/devices/*` + Android 硬件 TEE 私钥(250 行 `device_auth_service.dart`) |
| 设备额度配额 | 后端 PostgreSQL 计数 |
| 数据库备份 | `/api/backup/upload\|list\|download\|delete` |
| 文生图 / 图生视频 | 自建任务调度 + 外部 ComfyUI 服务 |
| 媒体上传(头像/封面) | `MediaProxy` + 后端转发 + `media_items` 本地表 |
| 前端接入 | `ApiServiceWrapper` 单入口(Dio + 设备 JWT 头),Host 通过 `--dart-define=BACKEND_BASE_URL` 打包注入 |

前端已有的抽象:**所有调用都汇聚到 `ApiServiceWrapper`,Host 通过 dart-define 注入**。`kHasBundledBackend` 标志决定走托管还是用户自配——这个抽象天然支持"换一个 Host",迁移**前端改动极小**。

### 1.2 目标

- **P0**:把后端从"自建 CVM + Python + PostgreSQL + 文件存储"迁到 CloudBase,实现免运维
- **P1**:保留现有功能完整,前端零感知(Host 改地址即可)
- **P2**:保留 ComfyUI 在外部,只把调度层放上 CloudBase

### 1.3 非目标(显式排除)

| 项 | 理由 |
|---|---|
| ComfyUI 上 CloudBase | CloudBase 不提供 GPU,出图必须留外部 |
| 前端架构改动 | 已有 `ApiServiceWrapper` 抽象足够 |
| 多模态 LLM | 不是本次目标,只迁 LLM 转发链路 |
| Web 版 Whimread 引入 | 暂不引入 CloudBase 静态托管;聚焦移动端 |

---

## 2. 关键设计决策(基于 skill 真实约束)

### 2.1 数据库:**CloudBase PostgreSQL(PG 模式),而非 MySQL**

**来源**:[Skill: `references/postgresql-development-cloudbase/SKILL.md` + `references/relational-database-mcp-cloudbase/SKILL.md`]

- ✅ **PG 是新环境推荐**:MySQL skill 标注为 `[Deprecated]`,原文写 "New environments should use PostgreSQL — see postgresql-development skill instead."
- ✅ **匹配 Whimread 现有 PostgreSQL**:现有后端用的是 PostgreSQL,SQL 语法基本不需要改
- ✅ **免费环境支持**:`scenarios.md` 提到"每个账号可创建 1 个免费环境 + 3000 资源点/月",PG mode 在 `manageEnv` 的 `resources` 列表里(`["flexdb","storage","function","postgresql"]`)

### 2.2 后端运行时:**Event Function(配 HTTP 网关),不是 HTTP Function**

**来源**:[Skill: `references/cloud-functions/SKILL.md` "Quick decision table"]

> "Only needs HTTP access for an existing Event Function? | Event Function + gateway access"

Whimread 的 API 是 RESTful JSON,Event Function 的 `event` 对象会带 `httpMethod`、`path`、`headers`、`body`,完全够用。**不选 HTTP Function 的理由**:

- HTTP Function 必须监听 9000 端口、写 `scf_bootstrap`(Skill:HTTP Function authoring contract)
- HTTP Function 必须显式配 credentials(Skill:`http-function-credentials.md`)
- HTTP Function 默认安全规则拒绝匿名,需要单独配安全规则

Event Function + 网关 = 一个 `exports.main = async (event, context) => {}` 就完事,代码极简。

### 2.3 资源包:**Token Credits(LLM 转发必备)**

**来源**:[Skill: `references/ai-model-nodejs/SKILL.md` "Mandatory Two-Step Preflight"]

调用任何内置 AI 模型(包括 LLM 转发)前,**必须**确认:
1. `DescribeEnvPostpayPackage` 返回的 `postpayPackageId` 以 `pkg_tcb_tokencredits_` 开头
2. 目标模型在 `cloudbase` 组的 `Models[]` 里(`DescribeAIModels`)
3. 必要时调 `UpdateAIModel` 启用

**Whimread 落地约束**:用户(产品决策者)需要先购买 Token Credits 资源包,否则 LLM 转发会失败。购买链接:`https://buy.cloud.tencent.com/lowcode?buyType=resPack&envId={envId}&resourceType=token`

### 2.4 鉴权:**保留设备 JWT,不引入 CloudBase Auth**

**来源**:[Skill: `references/auth-tool-cloudbase/SKILL.md`]

- Whimread 已经有完整的设备匿名鉴权链路(`device_auth_service.dart`,Android 硬件 TEE 私钥)
- CloudBase Auth 主要面向 Web / 小程序用户登录,不适合"一个设备 = 一个匿名用户"的场景
- **决策**:保留 `device_jwt` + `android_id` 体系,在 CloudBase 上用云函数做 JWT 签发与验证,数据存 PG

### 2.5 ComfyUI 边界:**调度层上 CloudBase,GPU 留在外部**

**来源**:[判断] + Skill `cloudrun-development/SKILL.md` 隐含支持

- ComfyUI 是 GPU 密集型,CloudBase 不提供 GPU 算力
- 调度层(提交任务、轮询状态、回调)用 CloudBase Event Function 实现
- ComfyUI 服务继续跑在外部 CVM / 裸金属,CloudBase 函数通过 HTTP 调它

### 2.6 测试/生产环境:**3 个独立 env,所有命令显式带 EnvId**

**来源**:[Skill: `SKILL.md` "Global rules before action" + `tooling-fallback.md`]

> "Always specify `EnvId` explicitly; do not rely on CLI-selected or implicit env state."
> "When the environment identifier is an alias, nickname, or other short form, **do not pass it directly** ... First resolve it to the canonical full `EnvId` with `envQuery(action=list, alias=..., aliasExact=true)`."

**Whimread 落地约束**:
- 三个 env:`whimread-dev`(开发联调)/ `whimread-staging`(灰度测试)/ `whimread-prod`(生产)
- 每次 CLI/MCP 操作**必须显式带 EnvId**,不要靠 `tcb env use` 的隐式状态
- 环境别名要先用 `envQuery` 解析成完整 ID 再用

---

## 3. 架构设计

### 3.1 整体拓扑

```
┌─────────────────────────────────────────────────────┐
│   Whimread Flutter App (Android/iOS/Windows)         │
│   ┌─────────────────────────────────────────────┐   │
│   │  ApiServiceWrapper (Dio + 设备 JWT)         │   │
│   │  Host: --dart-define=BACKEND_BASE_URL       │   │
│   └─────────────────────────────────────────────┘   │
└─────────────────────┬───────────────────────────────┘
                      │ HTTPS (POST /api/...)
                      ▼
┌─────────────────────────────────────────────────────┐
│   CloudBase HTTP 网关                                │
│   路由:Event Function + 上游 SCF                     │
└─────────────────────┬───────────────────────────────┘
                      │
    ┌─────────────────┼────────────────────┐
    ▼                 ▼                    ▼
┌────────┐      ┌─────────┐         ┌──────────┐
│llm-proxy│    │device-  │         │backup-   │  ... (Event Functions)
│(AI)     │    │auth     │         │storage   │
└───┬─────┘      └────┬────┘         └─────┬────┘
    │                 │                   │
    │ Token Credits   │ PG (devices)      │ Cloud Storage
    ▼                 ▼                   ▼
┌─────────┐      ┌──────────┐        ┌──────────┐
│ 混元/    │      │PostgreSQL│        │ Cloud    │
│ DeepSeek │      │(CloudBase│        │ Storage  │
│ /GLM/   │      │  PG)     │        │(备份文件)│
│ Kimi    │      │          │        │          │
└─────────┘      └──────────┘        └──────────┘
                      │
                      │ 调度出图/出视频
                      ▼
              ┌──────────────────┐
              │ ComfyUI (外部 GPU)│
              │ HTTP API 调度    │
              └──────────────────┘
```

### 3.2 资源清单(每个 env)

**来源**:[Skill: `cloudbase-platform/SKILL.md` "Environment Management"]

通过 `manageEnv` 创建时指定 `resources`:

```
resources=["flexdb","storage","function","postgresql"]
```

| 资源 | 用途 | Whimread 对应 |
|---|---|---|
| `flexdb` | NoSQL 文档数据库 | (暂不用,PG 够) |
| `storage` | Cloud Storage | 备份文件、媒体(头像/封面) |
| `function` | 云函数 | 所有后端 API |
| `postgresql` | PostgreSQL 兼容版 | 设备表、额度表、备份元数据、媒体元数据 |

> ⚠️ [Skill: 警告] "All paid operations (create / modifyPlan / renew) require `confirm="yes"`"——创建/改 plan/续费都要用户显式确认。

### 3.3 免费层与成本

**来源**:[Skill: `references/scenarios.md`]

> "Pricing: each CloudBase account can create 1 free environment (3,000 resource points/month)."

- **1 个免费环境**(3000 资源点/月)→ 适合 dev 或 staging
- prod 需要付费 plan(按用量)
- **Token Credits 独立计费**(Skill: `ai-model-nodejs/SKILL.md` 预检 ①)→ 需要单独购买资源包

---

## 4. 数据层:CloudBase PG Schema

### 4.1 关键约束(来源:[Skill: `postgresql-development-cloudbase/SKILL.md`])

- **API 不是 NoSQL**:`app.rdb().from('table').match({...})` 风格,**不要写 `.where()` / `.orderBy()`**(已废弃)
- **`auth.uid()` 返回 `text`,不是 `uuid`**(与 Supabase 不同)
- **所有 schema 变更走迁移工作流**:`cloudbase/migrations/<14位时间戳>_<name>.sql`,通过 `managePgDatabase(action=applyMigration, confirm=true)` 应用
- **MySQL-style 表不要忘了 `_openid` 列**?——[判断] **这个不适用 PG**,PG 模式用 RLS + `auth.uid()`,不走 `_openid`(仅 MySQL 模式要)

### 4.2 表结构设计(核心表)

**注意**:`auth.uid()` 是 Web SDK 用的;Whimread 是 Flutter 客户端,**云函数走 service_role 绕过 RLS**,所以 `auth.uid()` 不是必用项。但**保留 RLS 字段习惯**(owner_id 等)便于未来扩展。

```sql
-- 设备表
CREATE TABLE devices (
    android_id VARCHAR(64) PRIMARY KEY,        -- 设备唯一 ID
    attestation_cert BYTEA,                    -- TEE attestation 证书
    public_key TEXT NOT NULL,                 -- 设备公钥(签发 JWT 用)
    quota_balance INTEGER NOT NULL DEFAULT 100,
    total_consumed INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'active', -- active / banned
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_devices_status ON devices(status);

-- 设备 JWT 表(可选,如果不存设备维度无状态 JWT)
CREATE TABLE device_jwts (
    jti VARCHAR(64) PRIMARY KEY,              -- JWT ID
    android_id VARCHAR(64) NOT NULL REFERENCES devices(android_id),
    issued_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ
);

CREATE INDEX idx_device_jwts_android_id ON device_jwts(android_id);
CREATE INDEX idx_device_jwts_expires ON device_jwts(expires_at) WHERE revoked_at IS NULL;

-- 配额变更日志
CREATE TABLE quota_changes (
    id BIGSERIAL PRIMARY KEY,
    android_id VARCHAR(64) NOT NULL,
    change_amount INTEGER NOT NULL,            -- 正负
    reason VARCHAR(50) NOT NULL,               -- 'register_bonus' / 'llm_call' / 'image_gen' / 'manual'
    related_task_id VARCHAR(64),               -- 关联任务(task_id)
    balance_after INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_quota_changes_android_id ON quota_changes(android_id);
CREATE INDEX idx_quota_changes_created_at ON quota_changes(created_at);

-- 备份元数据(文件本身存 Cloud Storage)
CREATE TABLE backups (
    id BIGSERIAL PRIMARY KEY,
    android_id VARCHAR(64) NOT NULL,
    storage_path TEXT NOT NULL,                -- Cloud Storage 中的对象 key
    filename VARCHAR(255) NOT NULL,
    size_bytes BIGINT NOT NULL,
    sha256 VARCHAR(64),                       -- 可选:文件指纹
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_backups_android_id ON backups(android_id);
CREATE INDEX idx_backups_uploaded_at ON backups(uploaded_at);

-- 媒体元数据(头像/封面;文件存 Cloud Storage)
CREATE TABLE media_items (
    media_id VARCHAR(64) PRIMARY KEY,          -- 例如 'cm_<uuid>'
    android_id VARCHAR(64) NOT NULL,
    kind VARCHAR(20) NOT NULL,                -- 'image' / 'video' / 'cover'
    storage_path TEXT NOT NULL,
    mime_type VARCHAR(50),
    size_bytes BIGINT NOT NULL,
    local_only BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_media_items_android_id ON media_items(android_id);

-- 文生图/视频任务(对接外部 ComfyUI)
CREATE TABLE media_tasks (
    task_id VARCHAR(64) PRIMARY KEY,
    android_id VARCHAR(64) NOT NULL,
    kind VARCHAR(20) NOT NULL,                -- 'text2img' / 'image2video'
    status VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending / running / done / failed
    prompt TEXT NOT NULL,
    negative_prompt TEXT,
    model_name VARCHAR(100),
    result_media_id VARCHAR(64),               -- 完成时回写
    error_message TEXT,
    comfyui_task_id VARCHAR(64),              -- 外部 ComfyUI 任务 ID
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_media_tasks_android_id ON media_tasks(android_id);
CREATE INDEX idx_media_tasks_status ON media_tasks(status);
```

### 4.3 迁移工作流(来源:[Skill: `postgresql-development-cloudbase/SKILL.md`])

```
cloudbase/
└── migrations/
    ├── 20260907120001_initial_schema.sql
    ├── 20260907120002_add_quota_changes_reason.sql
    └── ...
```

应用迁移:
```
managePgDatabase(action=applyMigration,
                 migrationName="initial_schema",
                 migrationVersion="20260907120001",
                 sql="<读取本地文件>",
                 confirm=true)
```

> ⚠️ [Skill 警告]: "If applyMigration returns `MIGRATION_TASK_TIMEOUT` or `MIGRATION_TASK_PENDING`: the task may still be running ... Call `describeMigrationTask(taskId=...)` first ... Do not re-push the same migrationVersion"

---

## 5. 云函数划分

### 5.1 函数清单(Event Function 风格)

**来源**:[Skill: `cloud-functions/SKILL.md`]

```
cloudfunctions/
├── llm-proxy/                  # LLM 转发(Event Function)
│   ├── index.js
│   └── package.json
├── device-auth/                # 设备注册 / JWT 签发
│   ├── index.js
│   └── package.json
├── device-quota/               # 配额查询
│   ├── index.js
│   └── package.json
├── backup-storage/             # 备份上传/下载/列表/删除
│   ├── index.js
│   └── package.json
├── media-upload/               # 媒体上传(头像/封面)
│   ├── index.js
│   └── package.json
├── media-tasks/                # 文生图/图生视频任务(调外部 ComfyUI)
│   ├── index.js
│   └── package.json
└── common/                     # 共享工具:DB 客户端、JWT 校验、错误处理
    ├── db.js
    ├── jwt.js
    └── errors.js
```

### 5.2 LLM 转发函数示例(基于 skill 真实 API)

**来源**:[Skill: `ai-model-nodejs/SKILL.md`]

```javascript
// cloudfunctions/llm-proxy/index.js
const tcb = require('@cloudbase/node-sdk');

exports.main = async (event, context) => {
    const app = tcb.init({ env: process.env.TCB_ENV_ID });
    const ai = app.ai();

    // ✅ 正确:GroupName 是 "cloudbase",model 是具体模型 id
    const model = ai.createModel('cloudbase');

    const body = typeof event.body === 'string'
        ? JSON.parse(event.body)
        : (event.body || {});

    try {
        const result = await model.streamText({
            model: process.env.LLM_MODEL || 'deepseek-v3.2',
            messages: body.messages,
            temperature: body.temperature ?? 0.7,
        });

        // 流式返回(返回 SSE 友好的格式)
        const chunks = [];
        for await (const chunk of result.textStream) {
            chunks.push(chunk);
        }
        return {
            statusCode: 200,
            headers: { 'Content-Type': 'text/plain; charset=utf-8' },
            body: chunks.join(''),
        };
    } catch (e) {
        // ⚠️ Skill 警告:不能 echo event/context/process.env
        console.error('LLM 调用失败:', e.message);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: 'LLM proxy failed' }),
        };
    }
};
```

**关键约束**(来自 Skill):
- ⚠️ `ai.createModel('cloudbase')`——**GroupName 不是模型名**
- ⚠️ HTTP 网关超时 60s 上限 → 流式响应时设 `func.timeout=60`(skill 推荐 60-120s,但网关卡 60s)
- ⚠️ 不能 echo `event.headers` / `process.env` / `x-cloudbase-context`([Skill: `sensitive-runtime-data-protection.md`])

### 5.3 配额扣减模式(基于 skill 的 idempotency 建议)[判断]

```javascript
// cloudfunctions/device-quota/index.js
async function consumeQuota(androidId, amount, reason, relatedTaskId) {
    const pg = app.rdb();
    const { data: before } = await pg.from('devices')
        .select('quota_balance')
        .eq('android_id', androidId)
        .single();
    
    if (!before || before.quota_balance < amount) {
        throw new Error('QUOTA_EXHAUSTED');
    }
    
    // 事务:扣减 + 记日志
    // PG SQL via execute()
    await pg.rpc('consume_quota', {
        p_android_id: androidId,
        p_amount: amount,
        p_reason: reason,
        p_related_task_id: relatedTaskId,
    });
}
```

---

## 6. 鉴权设计

### 6.1 现有体系保留

- 客户端:`lib/services/device/device_auth_service.dart` 完整不动
- 服务端:`device-auth` 云函数负责:
  - 接收 `challenge` → 验证 TEE attestation → 签发 JWT
  - 校验客户端请求的 `Authorization: Bearer <device_jwt>`
  - 401 时引导客户端重注册(去重,不发新额度)

### 6.2 JWT 签发实现

**来源**:[判断] + 标准 JWT 库

```javascript
// cloudfunctions/device-auth/index.js
const jwt = require('jsonwebtoken');

async function signDeviceJwt(androidId) {
    // 私钥存云函数环境变量或 Secrets Manager
    const privateKey = process.env.DEVICE_JWT_PRIVATE_KEY;
    
    return jwt.sign(
        { sub: androidId, kind: 'device' },
        privateKey,
        {
            algorithm: 'ES256',
            expiresIn: '30d',
            jwtid: crypto.randomUUID(),
        }
    );
}

async function verifyDeviceJwt(token) {
    const publicKey = process.env.DEVICE_JWT_PUBLIC_KEY;
    try {
        const decoded = jwt.verify(token, publicKey, { algorithms: ['ES256'] });
        // 检查 jti 是否在 device_jwts 表里 + 未撤销
        const { data: jwtRow } = await pg.from('device_jwts')
            .select('expires_at, revoked_at')
            .eq('jti', decoded.jti)
            .single();
        if (!jwtRow || jwtRow.revoked_at || new Date(jwtRow.expires_at) < new Date()) {
            throw new Error('JWT_EXPIRED');
        }
        return decoded; // { sub: androidId, jti, ... }
    } catch (e) {
        throw new Error('JWT_INVALID');
    }
}
```

### 6.3 网关安全规则

**来源**:[Skill: `cloud-functions/SKILL.md` "Common mistakes"]

> "Forgetting to configure function security rules after creating an HTTP Function. Default rules reject anonymous callers with `EXCEED_AUTHORITY`."

Whimread 的函数需要**设备 JWT 鉴权**,不能匿名调用。所以函数安全规则需要:
- 关闭匿名访问
- 在每个函数内部做 JWT 校验(通过 `verifyDeviceJwt`)
- 通过校验后才执行业务逻辑

> ⚠️ [Skill 警告] "Anonymous login is disabled by default for new environments — if the function needs public access without authentication, configure the security rule to allow all callers rather than relying on anonymous login."

---

## 7. 存储设计

### 7.1 Cloud Storage 桶结构

**来源**:[Skill: `cloud-storage-web/SKILL.md`]

```
backups/                # 备份文件
  └── {android_id}/
      └── {yyyy}/{mm}/{dd}/{uuid}.db

media/                  # 用户上传媒体(头像/封面)
  └── {android_id}/
      └── {yyyy}/{mm}/{uuid}.{ext}

generated/              # AI 生成的媒体
  └── {android_id}/
      └── {task_id}.{ext}
```

### 7.2 关键约束

**来源**:[Skill: `cloud-storage-web/SKILL.md` "Bucket existence prerequisite"]

- ⚠️ **桶必须先创建再上传**——SDK 不能自动创建
- ⚠️ **临时 URL 不是永久 URL**:`createSignedUrl(path, expiresIn)` 默认 1 小时过期
- ⚠️ **PG 模式 vs NoSQL 模式存储 API 不同**——Whimread 走 PG 模式,用 `app.storage.from('bucket').upload(key, file)` 和 `createSignedUrl`
- ⚠️ **公开 URL 需 ACL 允许 public read**——默认 PRIVATE

### 7.3 Flutter 端备份上传流程

**来源**:[判断]——基于 Whimread 现有 `ApiServiceWrapper.uploadBackup`

```dart
// 前端零改动:仍走 ApiServiceWrapper,只是 Host 变了
final api = ApiServiceWrapper();
await api.uploadBackup(
    dbFile: File(localPath),
    onProgress: (sent, total) { /* ... */ },
);
```

后端云函数收到 multipart upload,流式写入 Cloud Storage。

---

## 8. AI 集成

### 8.1 LLM 转发(走 CloudBase Token Credits)

**来源**:[Skill: `ai-model-nodejs/SKILL.md`]

- 用 `ai.createModel('cloudbase')`,model id 可选 `deepseek-v3.2` / `glm-5` / `kimi-k2.6` / `hunyuan-2.0-instruct-20251111`
- **预检强制**:部署前必须 `DescribeEnvPostpayPackage` 通过 + `DescribeAIModels` 有目标模型
- **前端配置**:从 `lib/services/dsl_engine/llm_provider.dart` 的"用户自配 OpenAI 兼容地址"改为"指向 CloudBase 函数 URL"

### 8.2 文生图 / 图生视频(走 CloudBase + 外部 ComfyUI)

**判断**:CloudBase 函数做调度 + 配额扣减,**GPU 推理在外部 ComfyUI 服务**

```
Flutter → POST /api/text2img/generate
    → media-tasks 函数:
        1. 校验 JWT + 扣减配额(quota_changes INSERT)
        2. INSERT media_tasks (status='pending')
        3. HTTP POST 外部 ComfyUI → 拿到 task_id
        4. UPDATE media_tasks SET comfyui_task_id=xxx
        5. 返回 task_id 给前端
    [异步轮询]
    → media-tasks 函数定时器(Event Function,定时触发)轮询:
        1. SELECT pending/running 任务
        2. 调 ComfyUI 查进度
        3. 完成 → 拉图片 → 上传 Cloud Storage → 写 media_items
        4. UPDATE media_tasks SET status='done', result_media_id=xxx
```

### 8.3 图片生成迁移(可选,如果要彻底摆脱 ComfyUI)

**来源**:[Skill: `ai-model-nodejs/SKILL.md` "Image generation"]

- `ai.createImageModel('hunyuan-image')` + `model: 'hunyuan-image'`
- 走 Token Credits 计费(独立 SKU)
- **超时**:900s(最大),因为出图慢
- ⚠️ HTTP 函数网关 60s 上限 → 用异步任务模式(参考 §8.2 的"轮询"方案)

---

## 9. 前端改动清单

### 9.1 改动矩阵

| 文件 | 改动 | 备注 |
|---|---|---|
| `lib/core/constants/build_config.dart` | **零改动** | `kBackendBaseUrl` 已经是 dart-define 入口 |
| `lib/services/api_service_wrapper.dart` | **零改动** | Dio + 路径不变,只换 Host |
| `lib/services/device/device_auth_service.dart` | **零改动** | 设备 JWT 链路完整保留 |
| `lib/services/dsl_engine/llm_provider.dart` | **配置改一处** | "用户自配 LLM URL" 改为 "CloudBase llm-proxy 函数 URL" |
| `lib/services/novel_agent/agent_loop.dart` | **零改动** | Agent 架构不动 |
| Flutter 构建命令 | **多环境构建** | 加 staging / prod 的 dart-define 注入 |

### 9.2 构建命令示例

```bash
# dev 环境(本地模拟器 / 云端 whimread-dev env)
flutter build apk --release \
  --dart-define=BACKEND_BASE_URL=http://10.0.2.2:3000

# staging 环境(whimread-staging env)
flutter build apk --release \
  --dart-define=BACKEND_BASE_URL=https://whimread-staging.tcloudbaseapp.com

# prod 环境(whimread-prod env)
flutter build apk --release \
  --dart-define=BACKEND_BASE_URL=https://api.whimread.com
```

---

## 10. 部署工作流

### 10.1 环境创建(初始化阶段)

**来源**:[Skill: `cloudbase-platform/SKILL.md` "Environment Management"]

```bash
# 创建 dev 环境(免费层)
tcb env create --alias whimread-dev \
  --package baas_personal \
  --postgresql \
  --yes

# 拿到完整 EnvId 后,所有后续命令显式带
export DEV_ENV=cloudbase-abc123xyz

# 创建 staging(付费版,跟生产同配)
tcb env create --alias whimread-staging \
  --package baas_pf_standard \
  --postgresql \
  --yes

# 创建 prod(付费版)
tcb env create --alias whimread-prod \
  --package baas_pf_standard \
  --postgresql \
  --yes
```

### 10.2 资源准备(每个 env 一次)

```bash
# 启用 PG、函数、存储(如果创建 env 时已选,跳过)

# 1. 启用内置 AI 模型(走 Token Credits 预检)
#    DescribeEnvPostpayPackage → 必须有 pkg_tcb_tokencredits_xxx
#    DescribeAIModels → 启用 deepseek-v3.2

# 2. 创建 Cloud Storage 桶
tcb storage createBucket backups --permission PRIVATE
tcb storage createBucket media --permission PRIVATE

# 3. 应用数据库迁移
managePgDatabase(action=applyMigration, envId=$DEV_ENV,
                 migrationName="initial_schema",
                 migrationVersion="20260907120001",
                 sql="<读取本地文件>",
                 confirm=true)
```

### 10.3 函数部署(每个变更走一次)

**来源**:[Skill: `cloud-functions/SKILL.md` + `cloudbase-cli/SKILL.md`]

```bash
# dev 环境先部署 + 测试
tcb fn deploy llm-proxy -e $DEV_ENV

# 验证
tcb fn invoke llm-proxy -e $DEV_ENV --params '{"messages":[{"role":"user","content":"hi"}]}'

# staging 部署
tcb fn deploy llm-proxy -e $STAGING_ENV

# prod 部署(灰度)
tcb fn deploy llm-proxy -e $PROD_ENV

# 验证
tcb fn log llm-proxy -e $PROD_ENV --tail
```

**关键约束**:
- ⚠️ **不要用 `tcb deploy`**(Skill 反复警告)
- ⚠️ **每次显式带 EnvId**(不能靠 `tcb env use`)
- ⚠️ **生产写操作需用户确认**(Skill: deployment-gate)
- ⚠️ **MinNum instances ≥ 1**(Skill: deployment-workflow)→ 减少冷启动

---

## 11. 迁移步骤(分阶段)

### 阶段 1:验证可行性(1 周)

- [ ] 创建 `whimread-dev` env
- [ ] 部署 1 个最小 Event Function(hello world)
- [ ] Flutter 用 dart-define 指向该函数,验证请求-响应链路
- [ ] **验收**:Flutter 端能调通云函数

### 阶段 2:核心功能迁移(2 周)

- [ ] 部署 PG schema(dev env)
- [ ] 部署 `device-auth` 函数(设备注册/JWT 签发)
- [ ] 部署 `llm-proxy` 函数(配 Token Credits)
- [ ] 部署 `device-quota` 函数
- [ ] **验收**:Flutter 端能注册设备、调 LLM、扣减额度

### 阶段 3:存储与备份(1 周)

- [ ] 创建 `backups` / `media` 桶
- [ ] 部署 `backup-storage` 函数(上传/下载/列表/删除)
- [ ] Flutter 端用 staging env 跑完整备份链路
- [ ] **验收**:备份上传/下载/恢复完整流程通过

### 阶段 4:ComfyUI 集成(1-2 周)

- [ ] 部署 `media-tasks` 函数
- [ ] 接外部 ComfyUI(假设已有 CVM/裸金属)
- [ ] **验收**:Flutter 端能提交文生图任务、看进度、看结果

### 阶段 5:灰度切流(1 周)

- [ ] staging env 跑通所有 P0 链路
- [ ] 切部分生产用户到 CloudBase(whimread-prod env)
- [ ] 监控配额消耗、错误率
- [ ] 全量切换
- [ ] 下线自建后端

---

## 12. 风险与回退

### 12.1 风险点

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| 冷启动延迟 | 中 | LLM 首字 TTFB +1~2s | MinNum instances ≥ 1,预置并发 |
| Token Credits 耗尽 | 中 | LLM 不可用 | 监控配额余额,前端降级提示用户自配 key |
| 数据迁移失败 | 低 | 设备/备份元数据丢失 | 迁移前快照 + 灰度 + 回退 |
| ComfyUI 集成复杂度 | 高 | 出图功能延迟 | 先做"调度层在 CloudBase,GPU 外部"模式,不强制迁移 ComfyUI |
| API 端点不可达 | 低 | Flutter 全断 | 保留 `--dart-define` 多环境构建,出问题切回自建 Host |
| Skill 文档与实际 API 有出入 | 中 | 代码报错 | 关键 API 调用前用 `searchKnowledgeBase(mode=openapi, apiName=...)` 查 OpenAPI Swagger |

### 12.2 回退方案

**判断**——回退通道:

- Flutter 端用 dart-define 注入 Host,**回退 = 重新打一个指向自建后端的 APK**(代价低)
- CloudBase 上的数据保留(不删 env),问题修复后可重新切回
- 自建后端 N+1 个月内不拆,作为 backup

### 12.3 监控指标

**来源**:[Skill: `ops-inspector/SKILL.md`(本轮没读,但 SKILL.md 路由表提到)]

- **Token Credits 余额**(低于 20% 告警)
- **函数冷启动率**(`queryFunctions(action="listFunctionLogs")` 统计启动耗时)
- **错误率**(4xx/5xx 比例,CLS 查询 `module:llm AND logType:llm-tracelog`)
- **设备额度异常消耗**(quota_changes 监控,同一设备短时间大量扣减)

---

## 13. 我尚未读完的 skill 文档(诚实标注)

为了不误导,以下 skill 子模块本轮**没有完整读完**,设计文档中涉及但未深入:

- `ops-inspector/`(运维巡检)——只看了 SKILL.md 路由表
- `cloudbase-agent/ts/skill.md`(Agent TypeScript SDK)——没读
- `cloudbase-agent/py/skill.md`(Agent Python SDK)——没读
- `postgresql-development-cloudbase/references/` 下的 7 个文件(只读了 SKILL.md)
- `cloud-functions/references/` 下的 event-functions/http-functions 等具体函数模式
- `deployment-workflow.md` 关联的 protocols 目录(change-safety、deployment-gate 等)

**完整迁移方案实施前**,建议:
1. 读完 `postgresql-development-cloudbase/references/` 全部
2. 读完 `cloud-functions/references/event-functions.md` 和 `http-functions.md`
3. 读完 `cloudbase-platform/references/protocols/`

---

## 14. 下一步行动建议

按优先级:

1. **创建 `whimread-dev` env**(走 `tcb env create`),验证账号和付费链路
2. **部署最小 hello world 函数** + Flutter 端调通,验证网络可达
3. **完整读完剩余 skill 文档**(§13 清单),补充设计细节
4. **按阶段 1-5 逐步推进**

---

## 附录 A:Skill 真实信息源索引

本文档引用的 CloudBase skill(版本 2.33.0)真实内容来自:

| Skill 路径 | 关键内容 |
|---|---|
| `.agents/skills/cloudbase/SKILL.md` | 主入口、路由规则、MCP/CLI 选择 |
| `.agents/skills/cloudbase/references/scenarios.md` | 场景映射、免费层定价 |
| `.agents/skills/cloudbase/references/tooling-fallback.md` | MCP vs CLI 决策树 |
| `.agents/skills/cloudbase/references/http-api-cloudbase/SKILL.md` | Flutter/Native App 接入,API URL 格式 |
| `.agents/skills/cloudbase/references/cloudbase-platform/SKILL.md` | 平台总览、env 管理、数据库权限、域名管理 |
| `.agents/skills/cloudbase/references/cloudbase-cli/SKILL.md` | tcb CLI 用法 |
| `.agents/skills/cloudbase/references/cloud-functions/SKILL.md` | 函数类型、HTTP Function 约束、网关 |
| `.agents/skills/cloudbase/references/postgresql-development-cloudbase/SKILL.md` | PG 模式、迁移工作流、RLS、`auth.uid()` |
| `.agents/skills/cloudbase/references/relational-database-mcp-cloudbase/SKILL.md` | **MySQL 已弃用**警告 |
| `.agents/skills/cloudbase/references/auth-tool-cloudbase/SKILL.md` | 鉴权 provider 配置 |
| `.agents/skills/cloudbase/references/cloud-storage-web/SKILL.md` | Cloud Storage、桶创建、PG 模式 API |
| `.agents/skills/cloudbase/references/ai-model-nodejs/SKILL.md` | LLM API、`createModel` GroupName、Token Credits 预检 |
| `.agents/skills/cloudbase/references/cloudbase-agent/SKILL.md` | Agent 服务入口 |
| `.agents/skills/cloudbase/references/deployment-workflow.md` | 部署工作流 |

## 附录 B:本设计文档未涉及但实施时需补充

[判断]——这些点不在 skill 主文档里,属于实施细节:

- CloudBase MCP 工具集的具体 schema(本设计假设 MCP 不可用,走 CLI 兜底)
- 自建后端到 CloudBase 的数据迁移脚本(待实施时写)
- Flutter 端 `kHasBundledBackend=false` 时的降级路径(回退到自建 Host)
- ComfyUI 服务的高可用(SLA、备份)
- 跨 env 的备份同步(开发数据 → 生产)
