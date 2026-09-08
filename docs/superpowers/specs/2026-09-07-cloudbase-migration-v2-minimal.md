# Whimread 后端 CloudBase 迁移设计(v2-minimal)

- **日期**:2026-09-07
- **作者**:yunkst(与 ZCode 协同设计)
- **状态**:草案,待用户审阅
- **关系**:本版是 [`2026-09-07-cloudbase-migration-design.md`](2026-09-07-cloudbase-migration-design.md) 的**精简范围版本**——v1 全量迁移 + LLM 方案 A(Token Credits);**v2 只做 A + B + LLM 方案 B(自配转发)**,冻结 C/D/E
- **信息源**:CloudBase skill v2.33.0 真实文档内容;少量基于工程经验补充的判断会标注 [判断]

---

## 1. 范围变更(v1 → v2-minimal)

### 1.1 冻结范围(不做)

| 类别 | 接口 | 数量 | 原因 |
|---|---|---|---|
| C. 数据库备份 | `/api/backup/upload\|list\|download\|delete` | 4 | 用户决定本轮不迁移 |
| D. 文生图 ComfyUI | `/api/models`、`/api/text2img/*` | 3 | 冻结 ComfyUI 链路 |
| E. 图生视频 ComfyUI | `/api/image-to-video/*` | 2 | 冻结 ComfyUI 链路 |
| **冻结合计** | — | **9 个** | — |

### 1.2 保留范围(本轮目标)

| 类别 | 接口/端点 | 数量 | CloudBase 函数 |
|---|---|---|---|
| A. 设备鉴权 | `/api/v1/devices/challenge`、`/register`、`/me` | 3 | `device-auth` |
| B. APP 版本发布 | `/api/v1/app/releases/latest` | 1 | `app-release` |
| LLM 代理 | `POST /v1/chat/completions`(OpenAI 兼容) | 1 | `llm-proxy` |
| **本轮合计** | — | **5 个端点 / 3 个函数** | — |

### 1.3 LLM 方案:服务端持有 Key + 客户端零配置

- **v1 方案 A**:Token Credits 内置模型(DeepSeek/GLM/Kimi/混元)
- **v2-minimal 方案**:**服务端持有运营方配置的默认 LLM Key(管理员用环境变量 / KMS 存),客户端完全不需要 Key**,只用设备 JWT 鉴权,所有设备的 LLM 请求由服务端用统一 Key 转发
- **效果**:
  - 客户端**彻底废弃** LLM Key 自配 UI(`lib/services/dsl_engine/llm_provider_config.dart` 的 `apiKey/apiUrl` 字段不再使用)
  - 本地 SQLite `llm_configs` 表**整体废弃**(可以保留 schema 作为过渡期兼容,但生产链路不走)
  - 用户不再需要在「设置 → AI 配置」里填任何 LLM 信息
- **理由**:产品最简形态;运营方承担 LLM 成本,通过 Token Credits / 充值额度控制;客户端零认知负担

---

## 2. 关键设计决策(基于 skill 真实约束)

### 2.1 数据库:CloudBase PostgreSQL(PG 模式)

**来源**:[Skill: `references/postgresql-development-cloudbase/SKILL.md` + `references/relational-database-mcp-cloudbase/SKILL.md`]

- ✅ **PG 是新环境推荐**:MySQL skill 标注为 `[Deprecated]`,原文 "New environments should use PostgreSQL"
- ✅ **匹配 Whimread 现有 PostgreSQL**:SQL 语法基本不需要改
- ✅ **免费层支持**:`scenarios.md` 提到 "1 个免费环境 + 3000 资源点/月"

### 2.2 后端运行时:Event Function + HTTP 网关

**来源**:[Skill: `references/cloud-functions/SKILL.md` "Quick decision table"]

> "Only needs HTTP access for an existing Event Function? | Event Function + gateway access"

Event Function 的 `event` 对象带 `httpMethod`、`path`、`headers`、`body`,完全够用 RESTful API。**不选 HTTP Function**(避免端口 9000 + `scf_bootstrap` + 显式 credentials 的复杂度)。

### 2.3 鉴权:保留设备 JWT,云函数签发/校验

**来源**:[Skill: `references/auth-tool-cloudbase/SKILL.md`]

- Whimread 已有完整设备匿名鉴权(`device_auth_service.dart`,Android TEE 私钥)
- CloudBase Auth 主要面向 Web/小程序用户登录,不适合"一设备=一匿名用户"场景
- **决策**:保留 `device_jwt` + `android_id` 体系,CloudBase 云函数做签发/校验,数据存 PG

### 2.4 LLM 转发:服务端持有 Key + 客户端零配置

**来源**:[判断]——基于 OpenAI 协议 + Skill 网关约束

- **服务端用环境变量持有运营方的 LLM Key**(管理员通过 `tcb fn config update llm-proxy --env '{"LLM_API_KEY":"..."}'` 注入)
- **客户端完全不知道 Key**:`POST /v1/chat/completions` 的请求体**只有标准 OpenAI 字段**(`{model, messages, stream, ...}`),不带 Key、不带 baseUrl
- **CloudBase 函数工作流**:
  1. 验证设备 JWT → 取 android_id
  2. 查 `devices` 表:quota_balance > 0(否则 402)
  3. 读 `process.env.LLM_API_KEY` 和 `process.env.LLM_BASE_URL`(运营方配置)
  4. 转发到 `${LLM_BASE_URL}/chat/completions`,带 `Authorization: Bearer ${LLM_API_KEY}`
  5. 配额扣减:非流式按 `usage.total_tokens`,流式按调用次数简化扣 1 额度
  6. 流式:直接透传 SSE 给前端
- **关键约束**:
  - `process.env.LLM_API_KEY` 不能 echo 到响应(违反 skill `sensitive-runtime-data-protection.md`)
  - HTTP 网关 60s 超时 → 流式必须用 SSE 透传(Skill 限制会缓冲,见 §7.4)
  - 配额扣减必须在转发**前**做余额校验,失败后再回滚(避免扣了不发响应)

### 2.5 测试/生产环境:3 个独立 env,显式带 EnvId

**来源**:[Skill: `SKILL.md` "Global rules before action"]

> "Always specify `EnvId` explicitly; do not rely on CLI-selected or implicit env state."

| 环境 | 用途 | plan |
|---|---|---|
| `whimread-dev` | 你的本地联调 + 灰度前测试 | `baas_personal`(免费层) |
| `whimread-staging` | 团队内部测试、外部 beta 用户 | `baas_pf_standard` |
| `whimread-prod` | 真实用户 | `baas_pf_standard` |

---

## 3. 架构设计

```
┌────────────────────────────────────────────────────┐
│  Whimread Flutter App                                │
│  ApiServiceWrapper (Dio + 设备 JWT)                  │
│  Host: --dart-define=BACKEND_BASE_URL                │
└────────────────────┬───────────────────────────────┘
                     │ HTTPS
                     ▼
┌────────────────────────────────────────────────────┐
│  CloudBase HTTP 网关                                  │
│  3 条路由 → 3 个 Event Function                      │
└──────┬──────────────┬──────────────┬────────────────┘
       ▼              ▼              ▼
  ┌─────────┐    ┌─────────┐    ┌─────────┐
  │device-  │    │app-     │    │llm-     │
  │ auth    │    │release  │    │proxy    │
  └────┬────┘    └────┬────┘    └────┬────┘
       │              │              │
       ▼              ▼              ├─→ 配额扣减(quota_changes)
  ┌──────────┐   ┌──────────┐       │
  │ PG       │   │ PG       │       ▼
  │ devices  │   │ app_     │   ┌────────────────────┐
  │ jwts     │   │ releases │   │  透明转发 HTTPS     │
  │ quota_   │   └──────────┘   │  到用户自配的 LLM   │
  │ changes  │                  │  (DeepSeek/OpenAI/  │
  └──────────┘                  │   GLM/Kimi/Claude)  │
                                └────────────────────┘
```

### 3.1 资源清单(每个 env)

**来源**:[Skill: `cloudbase-platform/SKILL.md` "Environment Management"]

```
manageEnv(action="create", alias="whimread-dev", packageId="baas_personal",
          resources=["function","postgresql"], confirm="yes")
```

| 资源 | 用途 |
|---|---|
| `function` | 3 个云函数 |
| `postgresql` | 4 张表 |
| `flexdb` / `storage` | **不开**(本轮不用) |

---

## 4. API 端点规范(5 个)

### 4.1 A. 设备鉴权(3 个)

#### A.1 `POST /api/v1/devices/challenge`

- **鉴权**:❌ 无
- **请求体**:`{}`(空 body)
- **响应**:
  ```json
  { "nonce": "uuid-string", "expires_in": 120 }
  ```
- **错误码**:`500 INTERNAL`(后端异常)
- **调用方**:`device_auth_service.dart:102`

#### A.2 `POST /api/v1/devices/register`

- **鉴权**:❌ 无(注册本身)
- **请求体**:
  ```json
  {
    "android_id": "string",
    "platform": "android",
    "app_version": "x.y.z",
    "challenge": "nonce-string",
    "certificate_chain_pem": ["-----BEGIN CERTIFICATE-----..."]
  }
  ```
- **响应**:
  ```json
  {
    "device_id": "string",
    "token": "jwt-string",
    "attestation_verified": true,
    "quota_balance": 100
  }
  ```
- **业务规则**:
  - 同 `android_id` 重复注册 → 服务端去重,不发新额度(只续 JWT)
  - attestation 校验失败 → 400,不发 JWT
  - 首次注册 → 发 100 免费额度
- **调用方**:`device_auth_service.dart:115`

#### A.3 `GET /api/v1/devices/me`

- **鉴权**:✅ `Authorization: Bearer <设备JWT>`
- **请求体**:无
- **响应**:
  ```json
  {
    "device_id": "string",
    "quota_balance": 100,
    "status": "active",
    "attestation_verified": true
  }
  ```
- **错误码**:`401 UNAUTHORIZED`(JWT 无效/过期)
- **调用方**:`device_auth_service.dart:179`(设置页展示)

### 4.2 B. APP 版本发布(1 个)

#### B.1 `GET /api/v1/app/releases/latest`

- **鉴权**:❌ 无
- **请求体**:无
- **响应**:
  ```json
  {
    "version": "2.0.2",
    "build": 112,
    "download_url": "https://github.com/.../whimread-v2.0.2.apk",
    "release_notes": "...",
    "force_update": false,
    "min_supported_version": "2.0.0"
  }
  ```
- **业务规则**:`force_update=true` → 前端必须强制升级
- **调用方**:`backend_release_service.dart:50`

### 4.3 LLM 代理(1 个 OpenAI 兼容端点)

#### L.1 `POST /v1/chat/completions`

- **鉴权**:✅ `Authorization: Bearer <设备JWT>`
- **请求体**:**OpenAI Chat Completions 标准格式,客户端不发任何 Key**
  ```json
  {
    "model": "deepseek-chat",
    "messages": [{"role":"user","content":"hi"}],
    "temperature": 0.7,
    "stream": true
  }
  ```
- **服务端追加**:`Authorization: Bearer <服务端持有 LLM Key>`(从 `process.env.LLM_API_KEY` 读取)
- **响应**:
  - **非流式**(`stream=false`):OpenAI 标准 JSON
    ```json
    {
      "id": "chatcmpl-xxx",
      "choices": [{"message": {"role":"assistant","content":"..."}, "finish_reason": "stop"}],
      "usage": {"prompt_tokens": 10, "completion_tokens": 20, "total_tokens": 30}
    }
    ```
  - **流式**(`stream=true`):SSE
    ```
    data: {"id":"chatcmpl-xxx","choices":[{"delta":{"content":"你"}}]}
    data: {"id":"chatcmpl-xxx","choices":[{"delta":{"content":"好"}}]}
    data: [DONE]
    ```
- **业务规则**:
  - **配额扣减**:`cost = max(1, ceil(usage.total_tokens / 1000))` —— 1 额度 = 1000 tokens,向上取整,最少扣 1 额度
  - **非流式**:拿到响应 `usage.total_tokens` 后扣减
  - **流式**:从最后一个 SSE 事件读 `usage`,再扣减(标准 OpenAI 协议)
  - **模型字段**:`quota_changes.tokens_used` + `quota_changes.model` 一并写入,审计用
  - 配额不足 → `402 PAYMENT_REQUIRED`
  - JWT 过期 → `401 UNAUTHORIZED`
  - 服务端 LLM Key 配置缺失 → `503 SERVICE_UNAVAILABLE`(`LLM_API_KEY_NOT_CONFIGURED`)
  - 上游 LLM 失败 → 透传原始状态码和错误,不扣减
- **调用方**:`lib/services/dsl_engine/llm_provider_core.dart:88`(`POST {baseUrl}/chat/completions`)
- **关键约束**:
  - 必须支持 SSE 透传(用户流式体验)
  - 不能 echo `event.headers` / `process.env`(Skill: `sensitive-runtime-data-protection.md`)
  - HTTP 网关 60s 超时 → 流式用 chunked transfer encoding 提前发

---

## 5. CloudBase 函数划分

### 5.1 函数清单

```
cloudfunctions/
├── device-auth/
│   ├── index.js                  # 路由 challenge / register / me
│   ├── package.json              # @cloudbase/node-sdk >= 3.16.0
│   └── lib/
│       ├── jwt.js                # JWT 签发/校验(用 RS256 + 私钥存云函数环境变量)
│       └── attestation.js        # Android TEE 证书链验证(用 google-apis 或腾讯云 KMS VerifyAttestation)
├── app-release/
│   ├── index.js                  # 单端点实现
│   └── package.json
├── llm-proxy/
│   ├── index.js                  # 鉴权 + 配额扣减 + 透明转发 + 流式透传
│   ├── package.json              # @cloudbase/node-sdk >= 3.16.0
│   └── lib/
│       ├── quota.js              # 配额扣减(查 devices + 写 quota_changes)
│       └── llm-forwarder.js      # 调用用户自配 LLM(用 undici/fetch)
└── common/
    ├── db.js                     # PG 客户端懒初始化
    ├── errors.js                 # 统一错误响应格式
    └── logger.js                 # 结构化日志(走 context.logger)
```

### 5.2 路由示例(Event Function)

**来源**:[Skill: `cloud-functions/SKILL.md`]

```javascript
// cloudfunctions/device-auth/index.js
const tcb = require('@cloudbase/node-sdk');
const { signDeviceJwt, verifyDeviceJwt } = require('./lib/jwt');

let app = null;
function getApp() {
    if (!app) app = tcb.init({ env: process.env.TCB_ENV_ID });
    return app;
}

exports.main = async (event, context) => {
    const pg = getApp().rdb();
    const path = event.path.replace(/^\/api\/v1\/devices/, '');
    const method = event.httpMethod;

    try {
        if (method === 'POST' && path === '/challenge') {
            const nonce = crypto.randomUUID();
            // 可选:存 nonce 到 PG 防止重放
            return ok(200, { nonce, expires_in: 120 });
        }
        if (method === 'POST' && path === '/register') {
            const body = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
            // 1. 验证 attestation(简化版:信任证书链非空)
            // 2. 查 devices 表:同 android_id 已有 → 只续签 JWT;无 → 新建 + 发额度
            // 3. 签 JWT,写 device_jwts
            // 4. 返回 token
            return ok(200, { device_id, token, attestation_verified: true, quota_balance: 100 });
        }
        if (method === 'GET' && path === '/me') {
            const claims = await verifyDeviceJwt(event.headers.Authorization);
            const { data } = await pg.from('devices')
                .select('device_id, quota_balance, status, attestation_verified')
                .eq('android_id', claims.sub)
                .single();
            if (!data) return err(404, 'DEVICE_NOT_FOUND');
            return ok(200, data);
        }
        return err(404, 'NOT_FOUND');
    } catch (e) {
        context.logger.error(`device-auth failed: ${e.message}`);
        return err(500, 'INTERNAL', { detail: e.message });
    }
};

function ok(statusCode, data) {
    return {
        statusCode,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
    };
}
function err(statusCode, code, extra = {}) {
    return { statusCode, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code, ...extra }) };
}
```

### 5.3 关键约束(全部来自 skill)

- ⚠️ `functionRootPath` = `cloudfunctions/` 父目录(Skill: `cloud-functions/SKILL.md`)
- ⚠️ **生产环境 MinNum instances ≥ 1**(减少冷启动)
- ⚠️ `func.timeout` 文生图 900s,但 LLM 网关 60s 上限(本轮不用文生图,LLM 流式建议 60s)
- ⚠️ **不能用 Event Function 代码形态写 HTTP Function**(本次只用 Event Function,安全)
- ⚠️ **不能 echo `x-cloudbase-context` / `process.env`**(`sensitive-runtime-data-protection.md`)
- ⚠️ **生产写操作需用户确认**(`deployment-gate.md`)

---

## 6. 数据层:CloudBase PG Schema

### 6.1 关键约束(来源:[Skill: `postgresql-development-cloudbase/SKILL.md`])

- ✅ **API 不是 NoSQL**:`app.rdb().from('table').match({...})` 风格,**不要写 `.where()` / `.orderBy()`**(已废弃)
- ✅ **`auth.uid()` 返回 `text`,不是 `uuid`**
- ✅ **schema 变更走迁移工作流**:`cloudbase/migrations/<14位时间戳>_<name>.sql`,通过 `managePgDatabase(action=applyMigration)`
- ✅ **Whimread 云函数走 service_role 绕过 RLS**;`auth.uid()` 暂不直接用(设备鉴权用 JWT 替代)

### 6.2 4 张表

```sql
-- 设备表(主表)
CREATE TABLE devices (
    android_id VARCHAR(64) PRIMARY KEY,
    attestation_cert TEXT,
    quota_balance INTEGER NOT NULL DEFAULT 100,
    total_consumed INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'active', -- active / banned
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 设备 JWT 表
CREATE TABLE device_jwts (
    jti VARCHAR(64) PRIMARY KEY,
    android_id VARCHAR(64) NOT NULL REFERENCES devices(android_id),
    issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ
);
CREATE INDEX idx_device_jwts_android_id ON device_jwts(android_id);
CREATE INDEX idx_device_jwts_active ON device_jwts(expires_at) WHERE revoked_at IS NULL;

-- 配额变更日志
CREATE TABLE quota_changes (
    id BIGSERIAL PRIMARY KEY,
    android_id VARCHAR(64) NOT NULL,
    change_amount INTEGER NOT NULL,           -- 正:充值,负:扣减;LLM 时 = -ceil(tokens/1000)
    reason VARCHAR(50) NOT NULL,              -- 'register_bonus' / 'llm_call' / 'manual'
    balance_after INTEGER NOT NULL,
    tokens_used INTEGER,                      -- LLM 调用消耗的 tokens(仅 llm_call)
    model VARCHAR(100),                       -- LLM 调用使用的模型(仅 llm_call)
    metadata JSONB,                           -- 其他审计字段(预留)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_quota_changes_android_id ON quota_changes(android_id);

-- APP 版本发布表
CREATE TABLE app_releases (
    id BIGSERIAL PRIMARY KEY,
    version VARCHAR(20) NOT NULL,
    build INTEGER NOT NULL,
    download_url TEXT NOT NULL,
    release_notes TEXT,
    force_update BOOLEAN NOT NULL DEFAULT FALSE,
    min_supported_version VARCHAR(20),
    published_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_active BOOLEAN NOT NULL DEFAULT TRUE     -- 一次只一行 active
);
CREATE INDEX idx_app_releases_active ON app_releases(is_active, published_at DESC);
```

### 6.3 迁移工作流

```
cloudbase/
└── migrations/
    ├── 20260907120001_create_devices.sql
    ├── 20260907120002_create_device_jwts.sql
    ├── 20260907120003_create_quota_changes.sql
    └── 20260907120004_create_app_releases.sql
```

> 注:`quota_changes.tokens_used` 和 `quota_changes.model` 已在 `20260907120003_create_quota_changes.sql` 初次创建时包含(避免后续 ALTER TABLE)。如已用旧版 schema,补一个 `20260907120005_add_tokens_to_quota_changes.sql` ALTER。

应用:
```
managePgDatabase(action=applyMigration, envId=$DEV_ENV,
                 migrationName="create_devices",
                 migrationVersion="20260907120001",
                 sql="<读取本地文件>", confirm=true)
```

> ⚠️ [Skill 警告]:如果 applyMigration 返回 `MIGRATION_TASK_TIMEOUT`,**不要重推**;先 `describeMigrationTask(taskId)` 看真实状态。

---

## 7. LLM 代理(服务端持有 Key)详细设计

### 7.1 转发流程

**来源**:[判断]——基于 OpenAI 协议 + Skill 网关约束 + 用户决策

```
Whimread Flutter App
        │
        │ POST /v1/chat/completions
        │ Authorization: Bearer <设备JWT>
        │ Body: {model, messages, stream, ...}    ← 不含任何 Key
        ▼
   CloudBase 网关
        │
        ▼
   llm-proxy 云函数 (Event Function)
   ┌────────────────────────────────────────────┐
   │  1. 解析 body(兼容 string/object)          │
   │  2. 验证 JWT → 取 android_id               │
   │  3. 配额预检:SELECT quota_balance FROM devices│
   │     quota_balance < 1 → 402 拒绝            │
   │  4. 读环境变量 LLM_BASE_URL + LLM_API_KEY  │
   │     缺失 → 503 LLM_API_KEY_NOT_CONFIGURED │
   │  5. 转发 POST {LLM_BASE_URL}/chat/completions│
   │     带 Authorization: Bearer <LLM_API_KEY> │
   │  6. 拿到响应:                              │
   │     - 非流式:读 usage.total_tokens          │
   │     - 流式:转发完成后扣 1 额度(简化)       │
   │  7. 配额扣减:UPDATE devices SET quota_balance -= 1│
   │     写 quota_changes(失败不回滚,仅记日志)  │
   │  8. 响应透传给前端(SSE 直接转发)          │
   └────────────────────────────────────────────┘
        │
        │ POST {LLM_BASE_URL}/chat/completions
        │ Authorization: Bearer <LLM_API_KEY>    ← 服务端 Key
        ▼
   DeepSeek/OpenAI/GLM/Kimi/Claude/...
   (运营方配置的 LLM 供应商)
```

### 7.2 运营方如何配置 LLM Key

**来源**:[Skill: `cloudbase-cli/SKILL.md` + `cloud-functions/SKILL.md` 部署部分]

```bash
# 一次性配置(每个 env 都需配)
tcb fn config update llm-proxy -e $DEV_ENV \
  --env '{
    "LLM_BASE_URL": "https://api.deepseek.com/v1",
    "LLM_API_KEY": "sk-xxx...",
    "LLM_DEFAULT_MODEL": "deepseek-chat"
  }'
```

**生产 Key 管理建议**:
- 用腾讯云 KMS 或 Secrets Manager 存 Key(比环境变量安全)
- 定期轮转 Key(季度一次)
- 给 dev / staging / prod 用**不同的 Key**(便于流量隔离和成本归因)
- 配置变更走 `tcb fn config update`,不要改代码

### 7.3 配额扣减策略(按 token)

**核心规则**:**1 额度 = 1000 tokens**,向上取整,最少扣 1 额度。

```javascript
function calcCost(totalTokens) {
    return Math.max(1, Math.ceil(totalTokens / 1000));
}
```

| 调用类型 | 扣减流程 |
|---|---|
| 非流式 | 拿到响应 → 读 `data.usage.total_tokens` → 算 `cost = ceil(tokens/1000)` → 扣减 + 写 quota_changes |
| 流式 | 解析所有 SSE chunk → 最后一个 chunk 含 `usage`(标准 OpenAI 协议) → 算 cost → 扣减 + 写 quota_changes |
| LLM 报错(非 2xx) | 不扣 |
| 配额不足 | 转发**前**检查(简化:`quota_balance >= 1` 就让调,扣完可能变负数,日志告警) |
| 扣减失败(并发竞争) | 仅记日志,不回滚响应 |

**配额预检的取舍**——[判断]:

```javascript
// 简化预检:只要余额 >= 1 就让调,扣完允许临时变负数
// 理由:精确预估 tokens 成本很高(要用 tiktoken 等),用户实际消耗可能差异大
// 变负数后:该设备下次 LLM 请求会被 402 拒绝,直到充值或重置
const { data: device } = await pg.from('devices')
    .select('quota_balance')
    .eq('android_id', androidId)
    .single();
if (!device || device.quota_balance < 1) {
    return { statusCode: 402, body: JSON.stringify({ code: 'QUOTA_EXHAUSTED' }) };
}
```

**为什么不精确预估 tokens**——预估需要:
- 拿到用户完整 prompt(可能很长,含 system message + tools + 历史)
- 用 tiktoken 之类的 tokenizer 计算
- 流式还得提前知道 output 长度

**对运营方成本影响小**:即使预估漏 30%,单设备最多多扣 1 额度,而 1 额度 = 1000 tokens ≈ 几分钱,风险可控。

### 7.4 流式响应透传关键代码

```javascript
// cloudfunctions/llm-proxy/index.js
exports.main = async (event, context) => {
    // 1. 鉴权 + 配额预检(略)
    
    const userBody = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
    const isStream = userBody.stream === true;
    
    const upstream = await fetch(`${process.env.LLM_BASE_URL}/chat/completions`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${process.env.LLM_API_KEY}`,
        },
        body: JSON.stringify(userBody),
    });
    
    if (!upstream.ok) {
        // ⚠️ 不能 echo event.headers / process.env
        const errText = await upstream.text();
        context.logger.error(`LLM upstream failed: ${upstream.status} ${errText.slice(0, 200)}`);
        return {
            statusCode: upstream.status,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ code: 'LLM_UPSTREAM_ERROR', status: upstream.status }),
        };
    }
    
    // ⚠️ 配额扣减(按 token)
    if (!isStream) {
        const data = await upstream.json();
        const tokens = data.usage?.total_tokens ?? 0;
        const cost = Math.max(1, Math.ceil(tokens / 1000));
        await consumeQuota(androidId, cost, 'llm_call', {
            tokens_used: tokens,
            model: data.model,
        });
        return {
            statusCode: 200,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data),
        };
    }
    
    // 流式:边解析边透传 SSE,收尾时从最后一个 chunk 读 usage 扣减
    const sseText = await upstream.text();
    const lastUsage = parseLastUsageFromSse(sseText);  // 自定义工具函数,~20 行
    if (lastUsage) {
        const tokens = lastUsage.total_tokens ?? 0;
        const cost = Math.max(1, Math.ceil(tokens / 1000));
        await consumeQuota(androidId, cost, 'llm_call', {
            tokens_used: tokens,
            model: lastUsage.model,
        });
    }
    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
        },
        body: sseText,
    };
};

// 解析最后一个 SSE 事件的 usage 字段
// 标准格式:data: {"id":"...","choices":[...null],"usage":{...},"model":"..."}
function parseLastUsageFromSse(sseText) {
    const lines = sseText.split('\n').filter(l => l.startsWith('data: ') && !l.includes('[DONE]'));
    for (let i = lines.length - 1; i >= 0; i--) {
        try {
            const json = JSON.parse(lines[i].slice(6));
            if (json.usage) return { ...json.usage, model: json.model };
        } catch {}
    }
    return null;
}
```

> ⚠️ [判断]:Event Function + CloudBase HTTP 网关对流式响应**支持有限**——网关会缓冲整个 body 再返回,导致流式体验变成"整块返回"。如果用户对流式体验要求高,需要:
> - 方案 A:**接受"伪流式"**(LLM 返回后一次性给前端,前端模拟打字机效果)← 本轮推荐
> - 方案 B:LLM 函数改用 **CloudRun**(长连接,真正流式)[Skill: `cloudrun-development/SKILL.md`]
> - 方案 C:前端用轮询模式(不优雅)

---

## 8. 鉴权设计

### 8.1 JWT 签发与校验

**来源**:[判断] + 标准 JWT 库

```javascript
// cloudfunctions/device-auth/lib/jwt.js
const jwt = require('jsonwebtoken');

async function signDeviceJwt(androidId) {
    const privateKey = process.env.DEVICE_JWT_PRIVATE_KEY; // 云函数环境变量
    return jwt.sign(
        { sub: androidId, kind: 'device' },
        privateKey,
        {
            algorithm: 'RS256',
            expiresIn: '30d',
            jwtid: crypto.randomUUID(),
        }
    );
}

async function verifyDeviceJwt(authHeader) {
    if (!authHeader?.startsWith('Bearer ')) throw new Error('NO_BEARER');
    const token = authHeader.slice(7);
    try {
        const decoded = jwt.verify(token, process.env.DEVICE_JWT_PUBLIC_KEY, {
            algorithms: ['RS256'],
        });
        // 查 device_jwts 表确认未撤销
        const pg = getApp().rdb();
        const { data } = await pg.from('device_jwts')
            .select('revoked_at, expires_at')
            .eq('jti', decoded.jti)
            .single();
        if (!data || data.revoked_at) throw new Error('JWT_REVOKED');
        if (new Date(data.expires_at) < new Date()) throw new Error('JWT_EXPIRED');
        return decoded; // { sub: androidId, jti }
    } catch (e) {
        throw new Error('JWT_INVALID');
    }
}
```

### 8.2 函数安全规则

**来源**:[Skill: `cloud-functions/SKILL.md` "Common mistakes"]

> "Forgetting to configure function security rules after creating an HTTP Function. Default rules reject anonymous callers with `EXCEED_AUTHORITY`."

**Whimread 决策**:
- 3 个函数都配安全规则:**关闭匿名访问**,只允许带设备 JWT 的请求
- A.1 challenge、A.2 register 是注册流程,允许匿名
- A.3 me、B.1 releases(可选)、L.1 chat/completions → 必须鉴权
- 实际部署时通过 `manageFunctions` 的 security rule 配置

---

## 9. 部署工作流

### 9.1 环境创建(初始化)

**来源**:[Skill: `cloudbase-platform/SKILL.md` "Environment Management"]

```bash
# 创建 dev 环境(免费层)
tcb env create --alias whimread-dev \
  --package baas_personal \
  --postgresql \
  --yes

# 解析别名 → 完整 EnvId(Skill 强制)
tcb env list --alias whimread-dev
# → 拿到 ENV_ID = cloud1-abc123xyz

# staging(付费版,跟生产同配)
tcb env create --alias whimread-staging \
  --package baas_pf_standard \
  --postgresql \
  --yes

# prod
tcb env create --alias whimread-prod \
  --package baas_pf_standard \
  --postgresql \
  --yes
```

**所有后续命令显式带 `$ENV_ID`**——不要靠 `tcb env use` 隐式状态。

### 9.2 资源准备(每个 env 一次)

```bash
# 1. 应用 schema 迁移(每个表一个文件)
managePgDatabase(action=applyMigration, envId=$DEV_ENV,
                 migrationName="create_devices",
                 migrationVersion="20260907120001",
                 sql="$(cat cloudbase/migrations/20260907120001_create_devices.sql)",
                 confirm=true)
# ... 重复 3 次

# 2. 配置函数环境变量(设备 JWT 公私钥)
tcb fn config update device-auth -e $DEV_ENV \
  --env '{"DEVICE_JWT_PRIVATE_KEY":"...","DEVICE_JWT_PUBLIC_KEY":"..."}'
```

### 9.3 函数部署(每个变更)

```bash
# dev 先部署
tcb fn deploy device-auth -e $DEV_ENV
tcb fn deploy app-release -e $DEV_ENV
tcb fn deploy llm-proxy -e $DEV_ENV

# 验证
tcb fn invoke device-auth -e $DEV_ENV \
  --params '{"httpMethod":"POST","path":"/api/v1/devices/challenge","body":"{}"}'

# staging
tcb fn deploy device-auth -e $STAGING_ENV
# ... 重复

# prod(灰度)
tcb fn deploy device-auth -e $PROD_ENV
```

**关键约束**(全部来自 skill):
- ⚠️ **不要用 `tcb deploy`**(skill 反复警告,弃用命令)
- ⚠️ **生产写操作需用户确认**
- ⚠️ **MinNum instances ≥ 1**(生产)
- ⚠️ 每次显式带 EnvId

---

## 10. 实施步骤(精简)

### 阶段 1:验证可行性(3-5 天)

- [ ] 创建 `whimread-dev` env(`tcb env create`)
- [ ] 应用 4 个 migration 文件,确认 PG schema
- [ ] 部署 hello world 函数 + Flutter 调通
- [ ] **验收**:Flutter dart-define 注入 CloudBase 函数 URL,POST/GET 走通

### 阶段 2:设备鉴权(3-5 天)

- [ ] 部署 `device-auth` 函数(challenge/register/me)
- [ ] Flutter 端跑注册流程(需 Android 真机,TEE attestation)
- [ ] JWT 签发/校验全链路验证
- [ ] **验收**:Flutter 端能成功注册 + JWT 持久化 + /me 查询额度

### 阶段 3:LLM 代理(2-3 天)

- [ ] 部署 `llm-proxy` 函数
- [ ] 运营方在 dev env 配置 LLM Key(`tcb fn config update llm-proxy --env '{"LLM_API_KEY":"..."}'`)
- [ ] 前端改造:**移除 LLM Key 自配 UI**(`llm_provider_config.dart` 的 `apiKey` 字段改为空字符串),`baseUrl` 默认指向 `kBackendBaseUrl/v1`
- [ ] 验证非流式 / 流式(伪流式)响应
- [ ] 配额扣减链路验证
- [ ] **验收**:Flutter 端发起请求,服务端用运营方 Key 转发到 DeepSeek/OpenAI/GLM,响应正确,额度被扣

### 阶段 4:APP 版本发布(1-2 天)

- [ ] 部署 `app-release` 函数
- [ ] 在 PG 写第一行版本记录
- [ ] Flutter 端能拉到版本信息
- [ ] **验收**:设置页/启动检查能拉到最新版本

### 阶段 5:灰度切流(3-5 天)

- [ ] staging env 跑通全部 P0 链路
- [ ] 切部分生产用户(whimread-prod env)
- [ ] 监控配额消耗、错误率
- [ ] 全量切换
- [ ] **冻结范围不动**:备份 / 文生图 / 图生视频仍走自建后端

### 阶段 6(可选,不在本轮):解除冻结

C/D/E 后续可按 v1 设计文档补做。

---

## 11. 风险与回退

### 11.1 风险点

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| 冷启动延迟 | 中 | 首请求 +1~2s | MinNum instances ≥ 1 |
| 流式响应被网关缓冲 | 高 | 流式体验变"伪流式" | 前端模拟打字机;长期用 CloudRun |
| 设备 JWT 私钥泄露 | 低 | 全部设备额度被盗 | 私钥存云函数环境变量,密钥轮转策略 |
| **服务端 LLM Key 泄露** | 中 | 运营方承担被刷费用 | 用 KMS 存 Key、定期轮转、监控用量告警 |
| LLM 调用成本失控 | 中 | 运营方被刷破产 | 配额预检、quota_changes 监控、按设备频率限制 |
| schema migration 任务卡住 | 中 | 部署阻塞 | `describeMigrationTask` 看真实状态,不要重推 |
| 冻结范围影响用户体验 | 中 | 部分功能仍走自建后端 | 不影响 A/B/LLM,ComfyUI 用户本来就是高级功能 |

### 11.2 回退方案

**判断**——回退通道:

- Flutter 端用 dart-define 注入 Host,**回退 = 重新打一个指向自建后端的 APK**(代价低)
- CloudBase 上的数据保留(不删 env),问题修复后可重新切回
- 自建后端 N+1 个月内不拆

### 11.3 监控指标

**来源**:[Skill 路由表提到 `ops-inspector/SKILL.md` 但本轮未深入读]

- **设备额度异常消耗**(同一设备短时间大量扣减)
- **JWT 失败率**(`device-auth` 返回 401 的比例)
- **LLM 转发失败率**(LLM 502/503 的比例)
- **冷启动率**(`queryFunctions(action="listFunctionLogs")` 统计)

---

## 12. 已知 SDK 限制(2026-09-08 部署验证发现)

### 12.1 问题

CloudBase SDK 3.18.3 在云函数内调 PG REST API 的所有尝试均失败:

| 路径 | 现象 |
|---|---|
| `app.rdb().from('devices').insert(...)` | `Invalid schema` —— SDK 把它当 MySQL 解析 |
| `app.mysql().from('devices').insert(...)` | `this._c[method] is not a function` —— mysql client 内部走 wedaCreateV2 协议,非 postgREST |
| `app.auth().getClientCredential()` + fetch `/v1/rdb/rest` | `INVALID_CREDENTIALS` —— client_credentials 流返回 token 角色不被 PG 网关承认 |
| 直接 REST + Publishable Key | `INVALID_CREDENTIALS` —— publish_key 是 `anon` 角色,被 RLS 挡住 |
| CLI 创建 API Key(`api_key` 类型) | CLI help 说"暂不支持",但命令能跑;产出 JWT role 确实是 `service_role`,但 PG REST 仍拒 |
| `tcb api tcb ExecutePGSql` (admin) | ✅ **能用**,但只能从外部 CLI/MCP 调,**云函数内无 SDK 入口** |

### 12.2 根因

- **`app.mysql()` 内部 `wxCloudClient.generateMySQLClient`**:走的协议是 `httpOverCallFunction` → `wedaCreateV2`/`wedaUpdateV2` 等(微搭低代码),不是 postgREST。
- **`app.rdb()`**:SDK 3.18.3 的 rdb 客户端基于 `IMySqlClient` 类型,与 PG 不兼容。
- **publish_key 是 anon 角色**:CLI 的 `tcb env apikey create --type publish_key` 拿到的 token payload 明确 `role: "anon"`。
- **service_role token 没有 SDK 入口**:云函数内 SDK 不暴露 `TENCENTCLOUD_SECRETID/SECRETKEY` 用于签发 admin 调用。

### 12.3 当前落地状态(部署后实测)

| 项 | 状态 |
|---|---|
| `device-auth /challenge` | ✅ 200(不需要 PG) |
| `app-release /latest` | ✅ 200(因 db.js mock 改为返回 null,实际未走 PG) |
| `device-auth /register` | ❌ 500(INTERNAL, db.js 占位返回 NotImplementedError) |
| `device-auth /me` | ❌ 500(同上) |
| `llm-proxy /v1/chat/completions` 鉴权 | ✅ 401 NO_BEARER |
| `llm-proxy /v1/chat/completions` 配额扣减 | ❌ 同 register(调 PG) |

### 12.4 三种可行解(待用户决策)

**方案 A:用 NoSQL (`app.database()`) 替代 PG** ⭐ **推荐**
- 改 4 张 PG 表为 NoSQL collections
- `lib/services/dsl_engine/llm_provider.dart` 等 Flutter 端**零改动**
- 缺点:已有 4 个 PG migration 浪费;放弃 PG 高级特性
- **工作量**:1 天

**方案 B:自建 admin 云函数(代理模式)**
- 写一个 `pg-admin` 函数,通过 SDK 内部 callFunction → httpOverCallFunction 走 admin token
- `db.js` 改成 fetch 调 `https://{envId}.app.tcloudbase.com/pg-admin`
- 缺点:多一跳,延迟增加;权限边界需小心
- **工作量**:2 天

**方案 C:客户端走 publish_key + 关掉 RLS**
- 改 db.js 直接 fetch + 用 publish_key;PG 表 `DISABLE ROW LEVEL SECURITY` + `GRANT ALL TO anon`
- 缺点:**放弃 RLS 安全模型,anyone 知道 envId 都能读写**,仅适合 dev
- **工作量**:0.5 天

### 12.5 已验证的基础设施(确认云端 OK)

- ✅ CloudBase env 创建 + 3 函数部署 + 网关路由 + 自定义域名 `whimread.dazhi.site` 全通
- ✅ JWT 公私钥注入 + 鉴权链路工作(401 → 200)
- ✅ ExecutePGSql 直接 SQL 写入正常(说明 PG 数据层本身 OK,问题在云函数 → PG 链路)
- ✅ 4 个 PG migration 全部应用成功,grant service_role 也已执行

---

## 13. 我尚未读完的 skill 子模块(诚实标注)

实施前建议补读:

- `cloud-functions/references/event-functions.md`(Event Function 详细)
- `postgresql-development-cloudbase/references/` 全部 7 个文件
- `cloudbase-platform/references/protocols/change-safety-protocol.md` 和 `deployment-gate.md`
- `ops-inspector/SKILL.md`(巡检)
- `auth-tool-cloudbase/references/extended-guide.md`(provider 配置细节)

---

## 14. 下一步行动建议

按优先级:

1. **你审阅本文档**(`docs/superpowers/specs/2026-09-07-cloudbase-migration-v2-minimal.md`),看决策是否合预期
2. **审完后**:
   - 创建 `whimread-dev` env(走 `tcb env create`,需要你确认付费)
   - 部署 hello world 函数 + Flutter 调通,验证链路
   - 按阶段 1-5 逐步推进

---

## 附录 A:Skill 真实信息源索引

| Skill 路径 | 关键内容 | 用在本文档哪一节 |
|---|---|---|
| `SKILL.md` 主入口 | 路由规则、强制显式 EnvId | §2.5 |
| `scenarios.md` | 免费层定价(3000 资源点/月) | §3.1 |
| `tooling-fallback.md` | MCP vs CLI 决策树 | §9 |
| `http-api-cloudbase/SKILL.md` | Flutter/Native App 接入,API URL 格式 | §5 |
| `cloudbase-platform/SKILL.md` | env 创建、域名管理 | §3.1、§9 |
| `cloudbase-cli/SKILL.md` | tcb CLI 规范、禁用 `tcb deploy` | §9 |
| `cloud-functions/SKILL.md` | Event Function 选型、安全规则 | §2.2、§5.3、§8.2 |
| `postgresql-development-cloudbase/SKILL.md` | PG 模式、迁移工作流 | §2.1、§6 |
| `relational-database-mcp-cloudbase/SKILL.md` | **MySQL 已弃用**警告 | §2.1 |
| `auth-tool-cloudbase/SKILL.md` | 鉴权 provider | §2.3 |
| `ai-model-nodejs/SKILL.md` | LLM API(本轮不用内置模型) | §7 |

## 附录 B:本设计与 v1 的差异汇总

| 维度 | v1(全量) | v2-minimal(本版) |
|---|---|---|
| 接口总数 | 13 + 1(LLM) | **5**(A:3 + B:1 + LLM:1) |
| CloudBase 函数 | 5 个 | **3 个** |
| 数据库表 | 7 张 | **4 张** |
| ComfyUI | CloudBase 调度 + 外部 GPU | **冻结**(用 v1 不动) |
| 备份 | CloudBase 函数 + Cloud Storage | **冻结**(用 v1 不动) |
| LLM 方案 | A.Token Credits 内置模型 | **服务端持有运营方 Key,客户端零配置** |
| 前端 LLM Key 自配 UI | 保留 | **废弃** |
| 资源 | function + PG + storage + flexdb | function + PG(不开 storage/flexdb) |
| 预计工期 | 5 阶段 / 7 周 | **5 阶段 / 2.5 周** |
