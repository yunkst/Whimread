# Whimread CloudBase 迁移 — 当前会话交接文档

> **目的**:新会话启动时,先读这份文档,5 分钟内接手继续推进。

---

## 1. 项目一句话

把 Whimread Flutter App 的后端从自建 FastAPI/PostgreSQL 迁到 CloudBase(腾讯云),**当前 v2-minimal 范围:A 设备鉴权 + B APP 版本发布 + LLM 代理**(冻结 C 备份 / D 文生图 / E 图生视频)。

---

## 2. 关键文件速查

| 文件 | 角色 |
|---|---|
| `docs/superpowers/specs/2026-09-07-cloudbase-migration-design.md` | v1 设计(已废弃,**别看**) |
| `docs/superpowers/specs/2026-09-07-cloudbase-migration-v2-minimal.md` | **v2-minimal 真实 spec** |
| `docs/superpowers/plans/2026-09-07-cloudbase-migration.md` | 实施计划 |
| `README-cloudbase.md` | 部署/调试运维指南 |
| `cloudfunctions/common/tcb-admin.js` | **TC3-HMAC-SHA256 签名 + tcb.ExecutePGSql**(核心) |
| `cloudfunctions/common/db.js` | **链式 Builder over ExecutePGSql**(替换原 stub) |
| `cloudfunctions/common/{jwt,quota,errors,logger}.js` | 共享库 |
| `cloudfunctions/device-auth/index.js` | 设备鉴权 |
| `cloudfunctions/app-release/index.js` | APP 版本发布 |
| `cloudfunctions/llm-proxy/index.js` | LLM 转发 |
| `cloudfunctions/common/__tests__/db.test.js` | db.js SQL 编译单测(14 个) |
| `cloudbase/migrations/2026090712000{1..5}_*.sql` | 4 张 PG 表 + GRANT(已应用) |

---

## 3. 已完成 ✅

- [x] CloudBase env `whimread-dev-d0gm4oi0z3099082d`(个人版 PG 模式)
- [x] 4 张 PG 表 + GRANT + RLS 关闭(全部应用成功)
- [x] 3 个云函数部署 + 3 条 HTTP 网关路由(device-auth/app-release/llm-proxy)
- [x] 自定义域名 `whimread.dazhi.site` 绑定 + TLS
- [x] 设备 JWT 公私钥生成 + 注入函数环境变量
- [x] **`cloudfunctions/common/db.js` 真实能跑**(本轮新完成)
- [x] **`cloudfunctions/common/tcb-admin.js` TC3 签名封装**(本轮新完成)
- [x] **网关 header 小写 bug 修复**(本轮新完成)
- [x] 端到端冒烟测试通过:challenge / register / me 全 ✅;chat 鉴权 + 配额预检 + PG select ✅(上游 LLM 401 因 LLM_KEY 还是占位)
- [x] 本地 **48 个单测全过**(common 20 原有 + 14 db 新增 + device-auth 8 + llm-proxy 6)
- [x] `cloudbase` skill v2.33.0 + `cloudbase-mcp` 插件

---

## 4. 端到端实测状态(2026-09-08,本轮更新)

| 端点 | 状态 | 说明 |
|---|---|---|
| `POST /api/v1/devices/challenge` | ✅ 200 | 无 PG 依赖 |
| `GET /api/v1/app/releases/latest` | ✅ 200 | PG 查空表返 null(预期) |
| `POST /api/v1/devices/register` | ✅ **200** | PG insert devices + insert device_jwts + insert quota_changes(register_bonus +100) |
| `GET /api/v1/devices/me`(有效 JWT) | ✅ **200** | PG select devices + device_jwts 联校 |
| `GET /api/v1/devices/me`(无/坏 JWT) | ✅ 401 NO_BEARER / JWT_INVALID | 鉴权链路通 |
| `POST /v1/chat/completions`(有效 JWT) | ⚠️ 401 LLM_UPSTREAM_ERROR | JWT 鉴权 + PG select quota_balance + 上游 LLM fetch **全部跑通**;401 是因为 `.env` 里 `LLM_API_KEY=PLACEHOLDER_NOT_SET`,DeepSeek 拒认 |
| `POST /v1/chat/completions`(无 JWT) | ✅ 401 | 鉴权链路通 |

**唯一剩下的卡点**:把 `.env` 里的 `LLM_API_KEY` 从 `PLACEHOLDER_NOT_SET` 换成真实的 DeepSeek/OpenAI Key,然后 `tcb fn config update llm-proxy` 重注入,chat 就端到端通了**。

---

## 6. 上一会话的最大障碍 → 已解决 ✅

### 上一会话误判

| 进路 | 旧结论(错的) | 实际 |
|---|---|---|
| `app.rdb()` | SDK 当 MySQL 解析,PG 报 Invalid schema | 仍然不通(spec §12.2) |
| `app.mysql()` | 协议错 | 仍然不通 |
| `auth().getClientCredential()` + fetch REST | 网关 INVALID_CREDENTIALS | 仍然不通 |
| 直接 fetch + Publishable Key | publish_key 是 anon 角色,被 RLS 挡 | 仍然不通 |
| **TC3 自签 tcb.ExecutePGSql** | **"云函数内无 SDK 入口"** | ❌ **错的**! SCF 运行时**完整暴露** `TENCENTCLOUD_SECRETID/SECRETKEY/SESSIONTOKEN/REGION`,手动 TC3 签名就能调 |

### 关键探针(`env-probe` 函数,2026-09-08 部署并删除)

```js
// 列出 env var NAMES + 尝试 TC3 自签 tcb.ExecutePGSql
const secretId = process.env.TENCENTCLOUD_SECRETID;
const secretKey = process.env.TENCENTCLOUD_SECRETKEY;
const sessionToken = process.env.TENCENTCLOUD_SESSIONTOKEN;
const region = process.env.TENCENTCLOUD_REGION; // ap-shanghai 自动注入
const envId = process.env.TCB_ENV_ID;            // 需手动注入
```

**结果**:
- ✅ `TENCENTCLOUD_SECRETID_set: true`
- ✅ `TENCENTCLOUD_SECRETKEY_set: true`
- ✅ `TENCENTCLOUD_SESSIONTOKEN_set: true`
- ✅ `TENCENTCLOUD_REGION: ap-shanghai`
- ❌ `TCB_ENV_ID` 默认**未注入**,需 `tcb fn config update` 显式塞
- ✅ TC3 自签 `ExecutePGSql` 返回 `200` + 真实行:`["1", "cloudbase_postgres_pgdb_bdeluuah"]`

**结论**:从云函数内调 `tcb.ExecutePGSql` 是当前唯一可行的 PG 写入路径。

---

## 7. 已实现的核心模块

### `cloudfunctions/common/tcb-admin.js`(新增,主要 API)

```js
const { executePGSql, rowsToObjects } = require('./tcb-admin');
const result = await executePGSql('SELECT * FROM devices WHERE android_id = $1 LIMIT 1', ['abc']);
// result: { rows: ['["col1_val", "col2_val"]'], fields: ['col1', 'col2'], rowCount, affectedRows, executionTimeMs, raw }
// rowsToObjects(result) → [{col1: '...', col2: '...'}, ...]
```

内部做:
- TC3-HMAC-SHA256 签名(腾讯云 API v3 标准)
- 读取 SCF 凭据 + `TCB_ENV_ID`
- POST 到 `https://tcb.tencentcloudapi.com`
- 解析 + 错误分类(`NO_CREDS` / `PG_SQL_FAILED` / `HTTP_ERROR`)

### `cloudfunctions/common/db.js`(重写,链式 API)

保留原 stub 的所有调用方式,业务代码无感替换:

```js
const { data, error } = await db.from('devices')
    .select('android_id, quota_balance, status')
    .eq('android_id', claims.sub).single();
// insert / update / delete / in / gte / order / limit / is 也都支持
```

内部:
- Builder 状态 → SQL 编译(参数化,白名单列名防注入)
- 参数内联(因为 ExecutePGSql 不支持预编译,只能直接拼)
- 自动 `RETURNING` for `.update().select(...)` 链
- `.single()` → 空数组时返 `{data: null, error: {code: 'NOT_FOUND'}}`
- `db.raw(sql)` 暴露逃生口

**14 个 SQL 编译单测在 `__tests__/db.test.js` 全过**。

---

## 8. 上一会话没踩到的坑(已踩并修了)

1. **CloudBase HTTP 网关把 header 名转小写** —— `event.headers.authorization`,不是 `event.headers.Authorization`
   - 修复:`common/jwt.js` 改用 `headers?.authorization || headers?.Authorization`(优先 lowercase)
   - 影响:`device-auth/index.js`(`/me`)+ `llm-proxy/index.js`(`/chat`)
   - **debug 方法**:写个 `headers-probe` 函数挂临时路由,curl 加 `Authorization` 头,看 `Object.keys(event.headers)` 是小写

2. **`app.rdb()` 永远不通** —— 已知 SDK 限制(spec §12.2),直接用 `db.js` 即可

3. **PG REST 网关拒绝 service_role API Key** —— 这是控制面 token,数据面要别的 token
   - 不重要,不走 PG REST,走 ExecutePGSql

4. **ExecutePGSql 必须是单条 SQL** —— 不能批量;复杂操作拆成多条 + 用 transaction SQL

---

## 9. 关键设计决策(不要再讨论,直接复用)

| 决策 | 内容 | 来源 |
|---|---|---|
| 数据库 | CloudBase PostgreSQL(PG 模式) | spec §2.1 |
| 函数形态 | Event Function + HTTP 网关 | spec §2.2 |
| 鉴权 | 设备 JWT(RS256,30 天),云函数签发 | spec §2.3 |
| LLM Key | **服务端持有**,客户端零配置 | spec §2.4 |
| 配额扣减 | 按 token(1 额度 = 1000 tokens) | spec §7.3 |
| LLM 上游 | 默认 DeepSeek | spec §8 |
| 环境分离 | dev / staging / prod,显式带 EnvId | spec §2.5 |
| **云函数 → PG 路径** | **TC3-HMAC-SHA256 自签 tcb.ExecutePGSql** | 本轮探针确认 |
| 网关 header | lowercase(`event.headers.authorization`) | 本轮探针确认 |
| 冻结范围 | C 备份 + D 文生图 + E 图生视频 | spec §1.1 |

---

## 10. 立即能跑的测试命令

```bash
cd D:/myspace/novel_builder

# 端到端冒烟
source <(grep -E "^(TCB_ENV_ID_DEV|TCB_API_KEY)" .env | sed 's/^/export /')

echo "1. challenge"
curl -s -m 15 -X POST "https://whimread.dazhi.site/api/v1/devices/challenge" -H "Content-Type: application/json" -d "{}" -w " [HTTP %{http_code}]\n"

echo "2. releases"
curl -s -m 15 "https://whimread.dazhi.site/api/v1/app/releases/latest" -w " [HTTP %{http_code}]\n"

echo "3. me no JWT"
curl -s -m 15 "https://whimread.dazhi.site/api/v1/devices/me" -w " [HTTP %{http_code}]\n"

echo "4. chat no JWT"
curl -s -m 15 -X POST "https://whimread.dazhi.site/v1/chat/completions" -H "Content-Type: application/json" -d '{}' -w " [HTTP %{http_code}]\n"

echo "5. register"
TOKEN=$(curl -s -X POST "https://whimread.dazhi.site/api/v1/devices/register" \
  -H "Content-Type: application/json" \
  -d '{"android_id":"smoke-test-001","platform":"android","app_version":"2.0.0","challenge":"nonce","certificate_chain_pem":["-----BEGIN CERTIFICATE-----\nMIIBkTCB+wIBADANBgkqhkiG9w0BAQUFADAUMRIwEAYDVQQDEwlTbW9rZSBDQTAe\nFw03MDAxMDEwMDAwMDBaFw0zOTEyMzEwMDAwMDBaMBQxEjAQBgNVBAMTCVNtb2tl\nIENBMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDTcF9XSmGvjxv0Cr3Q\n-----END CERTIFICATE-----"]}' | jq -r .token)

echo "6. me with JWT"
curl -s -m 15 "https://whimread.dazhi.site/api/v1/devices/me" -H "Authorization: Bearer ${TOKEN}" -w " [HTTP %{http_code}]\n"

# 单测
cd cloudfunctions/common && node --test __tests__/common.test.js __tests__/db.test.js
cd ../device-auth && node --test __tests__/index.test.js
cd ../llm-proxy && node --test __tests__/sse-parser.test.js
```

---

## 11. 下一会话的优先任务

### 任务 1(本轮必做):填真 LLM Key 并端到端验证 chat

```bash
# 1. .env 里把 LLM_API_KEY 改成真实 Key
vim .env  # 填 LLM_API_KEY=sk-xxx...

# 2. 重注入到函数
tcb fn config update llm-proxy -e whimread-dev-d0gm4oi0z3099082d \
    --env "$(grep -E '^(LLM_|TCB_ENV_ID_DEV)=' .env | jq -R 'split("=")|{(.[0]):.[1]}' | jq -s add)"

# 3. 重新打 release APK 用真 BACKEND_BASE_URL
flutter build apk --release --split-per-abi \
  --dart-define=BACKEND_BASE_URL=https://whimread.dazhi.site
```

### 任务 2:Flutter 端联调

- `--dart-define=BACKEND_BASE_URL=https://whimread.dazhi.site` 打 release APK
- 真机测试 register → me → chat 全链路
- ChatCompletions 流式响应(注意 Event Function 网关会缓冲整个 body,**伪流式**)

### 任务 3:清理 PG 测试数据 + 真实 app_releases 行

```sql
DELETE FROM devices WHERE android_id LIKE 'smoke-test%';
DELETE FROM device_jwts WHERE android_id LIKE 'smoke-test%';
DELETE FROM quota_changes WHERE android_id LIKE 'smoke-test%';
-- 插一行真版本
INSERT INTO app_releases (version, build, download_url, release_notes, force_update, min_supported_version)
VALUES ('2.0.0', 112, 'https://github.com/yunkst/novel_builder/releases/latest',
        'CloudBase 迁移完成', false, '2.0.0');
```

### 任务 4:可选优化(后置)

- 接 KMS 替换 PEM 私Token
- attestation 占位换成真实 KMS VerifyAttestation
- 加 CloudBase logs 告警(quota 异常消耗)
- 接 staging/prod 环境(现在只有 dev)
- **优化 ExecutePGSql 延迟**:每个调用 ~50-100ms,register 链路有 3 次 PG 调用 → 改成事务 / 并发

---

## 12. 重新部署的注意事项

```bash
# 改了 common/* 后必须跑 sync-common 把 common/ 复制进每个函数目录
cd D:/myspace/novel_builder && node scripts/cloudbase/sync-common.mjs

# 然后用 deploy.sh 或 MCP updateFunctionCode 重新部署
# MCP 推荐(无需 tcb CLI):
#   manageFunctions(action="updateFunctionCode", functionName="device-auth",
#                   func={name:"device-auth", runtime:"Nodejs18.15", handler:"index.main"},
#                   functionRootPath="D:/myspace/novel_builder/cloudfunctions")
```

部署后**必须**给 3 个函数都注入 `TCB_ENV_ID`(ExecutePGSql 需要):

```bash
ENV_ID=whimread-dev-d0gm4oi0z3099082d
tcb fn config update device-auth -e $ENV_ID --env "{\"TCB_ENV_ID\":\"$ENV_ID\",\"DEVICE_JWT_PRIVATE_KEY\":\"...\",\"DEVICE_JWT_PUBLIC_KEY\":\"...\"}"
tcb fn config update app-release -e $ENV_ID --env "{\"TCB_ENV_ID\":\"$ENV_ID\"}"
tcb fn config update llm-proxy -e $ENV_ID --env "{\"TCB_ENV_ID\":\"$ENV_ID\",\"DEVICE_JWT_PUBLIC_KEY\":\"...\",\"LLM_API_KEY\":\"...\",\"LLM_BASE_URL\":\"...\",\"LLM_DEFAULT_MODEL\":\"...\"}"
```

或者用 `scripts/cloudbase/inject-env.mjs` 一次性注入所有(已更新)。