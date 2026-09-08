# CloudBase 迁移实施计划(v2-minimal)

- **日期**:2026-09-07
- **对应 spec**:`2026-09-07-cloudbase-migration-v2-minimal.md`
- **关联设计**:`2026-09-07-cloudbase-migration-design.md`(v1 全量,已被本计划替代)
- **状态**:草案,待用户审阅后开始落地

---

## 1. 范围与冻结

| 类别 | 内容 |
|---|---|
| **本轮要做** | A 设备鉴权(3 端点)+ B APP 版本发布(1 端点)+ LLM 代理(1 OpenAI 兼容端点) |
| **冻结不做** | 备份(C)/ 文生图(D)/ 图生视频(E) 共 9 个接口 |
| **LLM 方案** | 服务端持有运营方 Key,客户端零配置,按 token 扣减额度 |

---

## 2. 目录结构(新增)

```
novel_builder/
├── cloudfunctions/                    ← 新增,云函数代码
│   ├── common/                        ← 共享库
│   │   ├── package.json               ← 共享依赖(@cloudbase/node-sdk、jsonwebtoken)
│   │   ├── db.js                      ← PG 客户端懒初始化
│   │   ├── jwt.js                     ← 设备 JWT 签发/校验(RS256)
│   │   ├── quota.js                   ← 配额扣减/查询
│   │   ├── errors.js                  ← 统一错误响应
│   │   └── logger.js                  ← 结构化日志
│   ├── device-auth/
│   │   ├── package.json               ← 依赖 common 包
│   │   └── index.js                   ← challenge / register / me
│   ├── app-release/
│   │   ├── package.json
│   │   └── index.js                   ← /latest
│   └── llm-proxy/
│       ├── package.json
│       ├── index.js                   ← /v1/chat/completions
│       └── sse-parser.js              ← 流式响应 usage 解析
├── cloudbase/                         ← 新增,PG migration 文件
│   └── migrations/
│       ├── 20260907120001_create_devices.sql
│       ├── 20260907120002_create_device_jwts.sql
│       ├── 20260907120003_create_quota_changes.sql
│       └── 20260907120004_create_app_releases.sql
├── scripts/
│   └── cloudbase/
│       ├── deploy.sh                  ← 部署脚本(创建 env + 应用 migration + 部署函数)
│       ├── migrate.sh                 ← 单独应用 migration
│       └── seed-app-release.sh        ← 写首行 app_releases
├── .env.example                       ← 模板(dev/staging/prod 三个 env 的 EnvId + JWT 公私钥)
└── README-cloudbase.md                ← 新增,运维说明
```

**注**:`cloudfunctions/common` 用 npm workspaces 还是 local file 引用?——[判断]用 **`file:` 引用**(npm 自带,不引入 Lerna/Turborepo)。每个函数目录下 `npm install ../common`。

---

## 3. 文件清单(本轮要创建/修改)

### 3.1 全新文件(17 个)

| 路径 | 类型 | 描述 |
|---|---|---|
| `cloudfunctions/common/package.json` | 配置 | 共享依赖 |
| `cloudfunctions/common/db.js` | 代码 | PG 客户端懒初始化 + health check |
| `cloudfunctions/common/jwt.js` | 代码 | RS256 设备 JWT 签发/校验 |
| `cloudfunctions/common/quota.js` | 代码 | `consumeQuota()` / `getQuota()` |
| `cloudfunctions/common/errors.js` | 代码 | `ok()` / `err()` 响应工厂 |
| `cloudfunctions/common/logger.js` | 代码 | `log()` 包装 context.logger |
| `cloudfunctions/device-auth/package.json` | 配置 | 函数依赖 |
| `cloudfunctions/device-auth/index.js` | 代码 | 三端点实现 |
| `cloudfunctions/device-auth/lib/attestation.js` | 代码 | Android TEE 证书链验证(占位,生产接 KMS) |
| `cloudbase/migrations/20260907120001_create_devices.sql` | SQL | devices 表 |
| `cloudbase/migrations/20260907120002_create_device_jwts.sql` | SQL | device_jwts 表 |
| `cloudbase/migrations/20260907120003_create_quota_changes.sql` | SQL | quota_changes 表(含 tokens_used + model) |
| `cloudbase/migrations/20260907120004_create_app_releases.sql` | SQL | app_releases 表 |
| `scripts/cloudbase/deploy.sh` | 脚本 | 一键部署脚本 |
| `scripts/cloudbase/migrate.sh` | 脚本 | 单跑 migration |
| `.env.example` | 配置 | 环境变量模板 |
| `README-cloudbase.md` | 文档 | 运维说明 |

### 3.2 修改文件(本轮 0 个,后续阶段)

- Flutter 端 LLM Provider 调整在**独立 commit**(`refactor(LLM): 废弃用户自配 Key,baseUrl 默认指向 CloudBase`)

---

## 4. 实施阶段(本轮)

### 阶段 1:基础设施(本轮完成)

- [x] 写 plan 文档
- [ ] 创建目录结构
- [ ] 写 4 个 migration 文件
- [ ] 写 common 库 5 个文件
- [ ] 写 device-auth 云函数(3 端点 + attestation 占位)
- [ ] 写 deploy.sh / migrate.sh / .env.example / README-cloudbase.md

**验收标准**:
- 4 个 migration SQL 文件语法正确
- `cloudfunctions/common` 各模块可在 Node.js 测试环境加载
- `device-auth/index.js` 三个端点的 OpenAPI 风请求/响应格式清晰
- `deploy.sh` 可读取 `.env` + 跑通 `tcb env create` → `applyMigration` → `fn deploy` 流程(无 tcb CLI 时优雅失败)

### 阶段 2:剩余云函数(下一轮)

- [ ] 写 app-release 云函数(单端点)
- [ ] 写 llm-proxy 云函数(含 sse-parser.js)
- [ ] 测试所有函数本地调用

### 阶段 3:Flutter 端(后续)

- [ ] `lib/services/dsl_engine/llm_provider_config.dart` 的 `apiKey/apiUrl` 字段标注 `@Deprecated`
- [ ] `lib/services/llm_config_service.dart` 移除"用户自配 Key"分支
- [ ] Flutter dart-define 注入 `kBackendBaseUrl`(已存在,确认 OK)
- [ ] `flutter analyze` 通过

### 阶段 4:联调与部署(后续)

- [ ] 创建 `whimread-dev` env(`tcb env create`)
- [ ] 运行 `deploy.sh`,部署到 dev
- [ ] Flutter 端指向 dev env,跑通端到端
- [ ] 灰度切 prod

---

## 5. 关键设计决策(本轮要落实)

### 5.1 共享依赖方案

[判断] 用 npm **`file:` 引用**:`cloudfunctions/device-auth/package.json` 写 `"common": "file:../common"`。npm install 时会创建软链接到 `../common`,开发体验和工作区模式接近,无需引入 monorepo 工具。

### 5.2 PG 客户端

[Skill: `postgresql-development-cloudbase/SKILL.md`] 用 `@cloudbase/node-sdk` 的 `app.rdb()`,**不直接用 `pg` 库**。CloudBase 内部管理连接池。

### 5.3 JWT 私钥存哪

[判断] 用云函数**环境变量**(`DEVICE_JWT_PRIVATE_KEY`、`DEVICE_JWT_PUBLIC_KEY`),部署时通过 `tcb fn config update` 注入。本轮先用开发密钥,生产建议接 KMS(后续优化)。

### 5.4 attestation 校验

[判断] **本轮只做"占位"**:信任非空证书链,生产建议接腾讯云 KMS VerifyAttestation 校验 Android Key Attestation 证书链。占位逻辑:`chain.length > 0` 就视为通过,返回 `attestation_verified: false`。

### 5.5 部署脚本

[判断] **bash 脚本** + 调用 `tcb` CLI + `managePgDatabase` MCP(可选)。`.env` 存 EnvId / 公私钥 / LLM Key。脚本是幂等的(可以重复跑)。

---

## 6. 验收测试(本轮)

由于本轮不部署,验收以**代码静态检查 + Node.js 单元测试**为主:

| 项 | 验收方法 |
|---|---|
| migration SQL 语法 | `psql --dry-run` 或 docker postgres 本地验证(可选) |
| common 库单元测试 | `node --test` 跑 `cloudfunctions/common/__tests__/` |
| device-auth 函数单元测试 | mock PG + JWT,跑三端点覆盖 |
| 部署脚本 | `bash -n scripts/cloudbase/deploy.sh` 语法检查 |

---

## 7. 不在本轮做的事(显式排除)

| 项 | 排除原因 |
|---|---|
| 真正的 Android Key Attestation 验证 | 需要 KMS,本轮占位 |
| LLM 真实转发测试 | 需要 LLM Key,本轮只写代码 |
| 灰度发布 / 版本回滚 | 部署到 dev 后再做 |
| CI/CD 集成 | 本轮只支持手动 `bash deploy.sh` |
| 监控 / 告警 | 通过 ops-inspector skill,后续轮次 |

---

## 8. 下一步

用户审完本 plan 后,我立刻动手阶段 1(目录 + migration + common + device-auth + 部署脚本),完成后停下让你审代码,然后再做阶段 2-4。
