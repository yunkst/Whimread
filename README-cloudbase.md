# Whimread CloudBase 后端

> v2-minimal 范围:A 设备鉴权 + B APP 版本发布 + LLM 代理(冻结 C 备份 / D 文生图 / E 图生视频)

## 架构

```
Flutter App (Dio + 设备 JWT)
       │
       │ POST /api/v1/devices/*    POST /v1/chat/completions    GET /api/v1/app/releases/latest
       ▼
CloudBase HTTP 网关(3 条路由)
       │
       ├──► device-auth  (Event Function)──► PG: devices / device_jwts / quota_changes
       ├──► app-release  (Event Function)──► PG: app_releases
       └──► llm-proxy    (Event Function)──► PG: devices / quota_changes
                                                       │
                                                       ▼ 转发
                                                  DeepSeek/OpenAI/GLM/...
                                                  (运营方 Key,客户端零配置)
```

## 目录结构

```
cloudfunctions/
├── common/                # 共享库:db / jwt / quota / errors / logger
├── device-auth/           # 设备鉴权(challenge / register / me)
├── app-release/           # APP 版本发布(latest)
└── llm-proxy/             # LLM 转发(/v1/chat/completions)
cloudbase/migrations/      # PG schema 迁移文件
scripts/cloudbase/         # 部署脚本
```

## 快速开始

### 1. 前置条件

```bash
# 安装 CloudBase CLI
npm install -g @cloudbase/cli

# 登录(扫码或 device code)
tcb login

# 创建 dev 环境
tcb env create --alias whimread-dev \
  --package baas_personal \
  --postgresql \
  --yes
```

### 2. 配置环境变量

```bash
# 复制模板
cp .env.example .env

# 填入:
# - 三个环境的 EnvId(tcb env list --alias whimread-dev 拿到完整 ID)
# - JWT 公私钥(用 openssl 生成)
# - LLM API Key(运营方付费)
vim .env
```

### 3. 应用 PG migrations

```bash
# 查看待执行的 SQL
./scripts/cloudbase/migrate.sh dev

# 用 MCP 或控制台 SQL 编辑器逐个 apply
# 文件: cloudbase/migrations/2026090712*.sql
```

### 4. 部署函数

```bash
./scripts/cloudbase/deploy.sh dev
```

### 5. 验证

```bash
# 看函数日志
tcb fn log device-auth -e $TCB_ENV_ID_DEV --tail

# 直接调函数
tcb fn invoke device-auth -e $TCB_ENV_ID_DEV \
  --params '{"httpMethod":"POST","path":"/api/v1/devices/challenge","body":"{}"}'

# 通过 HTTP 网关调
curl -X POST https://$TCB_ENV_ID_DEV.api.tcloudbasegateway.com/api/v1/devices/challenge
```

## 关键设计

| 维度 | 决策 |
|---|---|
| 数据库 | CloudBase PostgreSQL(PG 模式,4 张表) |
| 函数形态 | Event Function + HTTP 网关(非 HTTP Function) |
| 鉴权 | 设备 JWT(RS256,30 天有效),云函数签发 |
| LLM Key | 服务端持有,客户端零配置 |
| 配额扣减 | 1 额度 = 1000 tokens(`ceil(tokens/1000)`) |
| 部署 | bash 脚本 + tcb CLI,显式带 EnvId |

详细设计见:`docs/superpowers/specs/2026-09-07-cloudbase-migration-v2-minimal.md`
实施计划:`docs/superpowers/plans/2026-09-07-cloudbase-migration.md`

## 端点清单

| 方法 | 路径 | 鉴权 | 函数 | 描述 |
|---|---|---|---|---|
| POST | `/api/v1/devices/challenge` | ❌ | device-auth | 申请一次性 nonce |
| POST | `/api/v1/devices/register` | ❌ | device-auth | 提交 attestation,获取 JWT |
| GET | `/api/v1/devices/me` | ✅ | device-auth | 查询当前设备额度 |
| GET | `/api/v1/app/releases/latest` | ❌ | app-release | APP 最新版本 |
| POST | `/v1/chat/completions` | ✅ | llm-proxy | OpenAI 兼容 LLM 转发 |

## 环境分离

| 环境 | 用途 | Plan |
|---|---|---|
| `whimread-dev` | 本地联调 / 灰度前 | `baas_personal`(免费层,3000 资源点/月) |
| `whimread-staging` | 团队测试 / 外部 beta | `baas_pf_standard` |
| `whimread-prod` | 真实用户 | `baas_pf_standard` |

每个环境的 EnvId / LLM Key / JWT 公私钥**必须显式带**,不要靠 `tcb env use` 的隐式状态。

## 冻结范围(本轮不做)

| 接口 | 路径 | 说明 |
|---|---|---|
| 备份上传 | `/api/backup/upload` | 仍走自建后端 |
| 备份列表 | `/api/backup/list` | 同上 |
| 备份下载 | `/api/backup/download/{id}` | 同上 |
| 备份删除 | `/api/backup/delete/{id}` | 同上 |
| 文生图模型列表 | `/api/models` | 冻结 ComfyUI 链路 |
| 文生图提交 | `/api/text2img/generate` | 同上 |
| 文生图拉取 | `/api/text2img/image/{id}` | 同上 |
| 图生视频提交 | `/api/image-to-video/generate` | 同上 |
| 图生视频拉取 | `/api/image-to-video/video/{id}` | 同上 |

## 下一轮待做(本仓库代码已占位)

- [ ] `app-release/index.js` 完整实现(读 PG 而非返回固定值)
- [ ] `llm-proxy/index.js` 完整实现(转发 + 按 token 扣减 + 流式 SSE)
- [ ] `llm-proxy/sse-parser.js` 解析最后一个 SSE chunk 的 usage
- [ ] `device-auth/__tests__/` 单元测试
- [ ] Flutter 端 LLM Provider 调整(`lib/services/dsl_engine/llm_provider_config.dart` 废弃 apiKey/apiUrl)

## 故障排查

### 函数返回 500

```bash
tcb fn log <function-name> -e $ENV_ID --tail
```

### JWT 校验失败

检查环境变量:
```bash
tcb fn config get device-auth -e $ENV_ID
```
确认 `DEVICE_JWT_PUBLIC_KEY` 与签发时的私钥配对。

### PG 写入失败

```bash
# 查 migration 历史
managePgDatabase(action=listMigrations, envId=$ENV_ID)

# 看具体错误
managePgDatabase(action=migrationDetail, envId=$ENV_ID, migrationVersion=20260907120001)
```
