# Whimread 管理后台(admin-console)设计

- **日期**:2026-09-09
- **作者**:yunkst(与 ZCode 协同设计)
- **状态**:草案,待用户审阅
- **关系**:建立在 [`2026-09-07-cloudbase-migration-v2-minimal.md`](2026-09-07-cloudbase-migration-v2-minimal.md) 的 CloudBase 后端之上;依赖 feedback 云函数(本地已实现、**尚未 commit**)
- **使用方**:仅运营者本人(单管理员),非普通用户功能

---

## 1. 背景与目标

Whimread 托管后端(CloudBase 三函数:device-auth / llm-proxy / app-release)目前**没有任何人用的管理界面**:

- 设备封禁状态、额度调整、JWT 撤销的原语在 `common/` 里已备(`devices.status`、`grantQuota()`、`revokeDeviceJwt()`),但没有 HTTP 入口,只能手写 SQL;
- `quota_changes` 审计表为管理员后台预留了 `manual_grant / manual_reset / admin_revoke` reason,同样无人消费;
- 用户反馈表(`feedback_reports` / `feedback_logs`)已落库,管理端目前只有 CLI 脚本(`scripts/cloudbase/feedback-fetch.mjs`);
- Star 兑换(`/api/v1/devices/star/redeem`)**服务端尚未实现**,客户端 `DeviceAuthService.redeemStarQuota()` 正在对接一个不存在的接口。

**目标**:交付一个带登录认证的独立 Web 管理后台,单管理员使用,V1 覆盖:设备查询 / 额度调整 / 封禁与踢下线 / Star 兑换记录 / 反馈工单 / 操作审计。

## 2. 范围

### 2.1 V1 交付

| 模块 | 内容 |
|---|---|
| 管理员账号 | 单账号,首次登录强改密,密码 + **TOTP** 双因素,10 个备用恢复码 |
| 设备管理 | 列表/搜索/分页、详情、额度加/重置、封禁/解封、JWT 撤销(踢下线) |
| Star 兑换 | **补齐服务端兑换端点**(device-auth 新路由)+ 兑换记录查询 |
| 反馈工单 | 列表 / 详情 / 附带日志查看(admin-console 直查 PG,复用 feedback 函数已建的表) |
| 总览仪表盘 | 设备总数、7 日额度发放/消耗、7 日 LLM 调用、封禁数 |
| 审计日志 | 所有管理操作落 `admin_audit_logs`,后台可查 |

### 2.2 明确不做(V2 候选)

- **LLM 代理可配置化**(默认模型 / token 单价 / provider key 从环境变量迁 DB):涉及 llm-proxy 改造,独立周期
- **端侧服务观测**(Agent / 预加载 / WebView 抓取运行状态):app 端没有任何上报链路,数据源不存在,属独立项目
- 多管理员 / 邀请制 / 应用发布管理 UI(继续走 CI + `X-API-TOKEN`)

### 2.3 关联交付(随本设计一起)

- 修客户端 bug:`lib/services/device/device_auth_service.dart` `mapRedeemDioError` 读 `data['error']`,而后端 `errors.js` 错误体是 `{code, message}`——redeem 错误码映射(`NOT_STARRED` / `ALREADY_REDEEMED` 等)依赖此修复才能生效

## 3. 总体架构

### 3.1 形态决策

三个候选:

| 方案 | 说明 | 结论 |
|---|---|---|
| **A. CloudBase 全家桶** | 新增 `admin-console` 云函数 + 静态网站托管 SPA,住进现有环境 | **✅ 采用** |
| B. 独立轻量服务(Hono/Fastify + pg 直连,云托管部署) | 脱离函数限制、PG 直连;但新增一条完整运维线 | V2 若长出重报表再迁移 |
| C. 复用 `X-API-TOKEN` 静态密钥,无登录 | 最快但不满足「登录认证」需求,无审计 | 否决 |

选 A 的理由:零新增运维面(同 `deploy.sh`、同 PG、同账号);管理原语直接调 `common/` 现成函数;错误响应规范沿用 `errors.js`。为给 B 留迁移缝隙,admin-console 内部 SQL 集中在 `lib/repo.js` 单文件。

### 3.2 组件图

```
浏览器(管理员)
   │ HTTPS · Bearer access JWT(2h)
   ▼
CloudBase 静态网站托管 ←—— SPA(Vite + React + TS + Ant Design 5,构建产物)
   │ 跨域白名单(ADMIN_WEB_ORIGINS)
   ▼
HTTP 访问 /admin/* ──→ 云函数 admin-console(Nodejs20.19)
                                    │ lib/repo.js  ← 所有 SQL 集中于此
                                    │ lib/auth.js  ← scrypt / TOTP / JWT / 会话
                                    │ common/db.js → ExecutePGSql → CloudBase PG
                                    ▼
                        devices / device_jwts / quota_changes /
                        feedback_reports / feedback_logs /
                        admins / admin_backup_codes /
                        admin_refresh_tokens / admin_audit_logs(后四张新增)

device-auth 函数新增路由:
   POST /api/v1/devices/star/redeem(设备 JWT,GitHub Star 校验 + 发额度)
```

### 3.3 与既有系统的边界

- **不动** device-auth 现有三路由、llm-proxy、app-release、feedback 函数(它继续承担反馈/日志的**写入**,其 `X-API-TOKEN` 管理端点保留给 CLI 用)
- 管理后台对 feedback 数据**直查 PG**(同库),不让浏览器持有 `PUBLISH_API_TOKEN`
- Flutter 客户端唯一的改动是 §2.3 的错误映射修复 + redeem 端点对齐
- **路径前缀**:管理台人用 API 走 `/admin/*`;客户端/CI 等机器面走 `/api/*`(见 §6.1)

## 4. 数据模型

新增 1 个 migration:`cloudbase/migrations/20260909130000_admin_console.sql`,风格对齐既有 migration(注释头 / `IF NOT EXISTS` / `DO $$` 约束 / 尾部 down 注释)。

```sql
-- 1. 管理员(单行,seed 脚本插入)
CREATE TABLE IF NOT EXISTS admins (
    username            VARCHAR(50) PRIMARY KEY,
    pass_hash           TEXT NOT NULL,            -- scrypt: salt$hash(N=2^15, r=8, p=1)
    totp_secret         TEXT,                     -- base32,绑定后非空
    totp_enabled        BOOLEAN NOT NULL DEFAULT FALSE,
    must_change_password BOOLEAN NOT NULL DEFAULT TRUE,
    session_version     INTEGER NOT NULL DEFAULT 0,  -- +1 即作废全部 access JWT
    failed_attempts     INTEGER NOT NULL DEFAULT 0,  -- 密码错误计数
    totp_failed_attempts INTEGER NOT NULL DEFAULT 0, -- TOTP 错误计数(独立)
    locked_until        TIMESTAMPTZ,
    disabled            BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at       TIMESTAMPTZ
);

-- 2. 备用恢复码(明文只在 setup 响应中出现一次,库存 scrypt hash)
CREATE TABLE IF NOT EXISTS admin_backup_codes (
    id           BIGSERIAL PRIMARY KEY,
    admin_username VARCHAR(50) NOT NULL REFERENCES admins(username) ON DELETE CASCADE,
    code_hash    TEXT NOT NULL,
    used_at      TIMESTAMPTZ
);

-- 3. refresh token(轮换 + 复用检测;库存 sha256)
CREATE TABLE IF NOT EXISTS admin_refresh_tokens (
    id             BIGSERIAL PRIMARY KEY,
    admin_username VARCHAR(50) NOT NULL REFERENCES admins(username) ON DELETE CASCADE,
    token_hash     TEXT NOT NULL UNIQUE,
    family_id      UUID NOT NULL,               -- 一条登录链一个 family
    expires_at     TIMESTAMPTZ NOT NULL,
    revoked_at     TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_admin_refresh_family ON admin_refresh_tokens(family_id);

-- 4. 管理操作审计
CREATE TABLE IF NOT EXISTS admin_audit_logs (
    id             BIGSERIAL PRIMARY KEY,
    admin_username VARCHAR(50) NOT NULL,
    action         VARCHAR(50) NOT NULL,   -- login / login_failed / quota_grant / quota_reset /
                                           -- device_ban / device_unban / revoke_tokens / totp_setup ...
    target_type    VARCHAR(30),            -- device / feedback / self
    target_id      TEXT,
    detail         JSONB,                  -- before/after、note、github_login 等
    ip             VARCHAR(64),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_admin_audit_created ON admin_audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_action  ON admin_audit_logs(action, created_at DESC);

-- 5. quota_changes 的 reason 约束放宽:补 'star_redeem'
--    (现状 CHECK 只有 register_bonus/llm_call/manual_grant/manual_reset/admin_revoke,
--     Star 兑换目前完全无审计记录)
ALTER TABLE quota_changes DROP CONSTRAINT quota_changes_reason_check;
ALTER TABLE quota_changes ADD CONSTRAINT quota_changes_reason_check
    CHECK (reason IN ('register_bonus','llm_call','manual_grant',
                      'manual_reset','admin_revoke','star_redeem'));
```

Star 兑换记录即 `quota_changes WHERE reason='star_redeem'`,`metadata` 存 `github_login`,不另建表。

**事务性说明**:`common/db.js` 是逐语句 Builder。审计行与业务变更要求「同一次 `ExecutePGSql` 调用内顺序执行多条语句」(控制面支持传 SQL 数组);实现期验证,若不支持则降级为**先写审计后执行变更**,接受极端故障下的孤儿审计行,写入实现计划验证点。

## 5. 认证设计

### 5.1 密码与 TOTP

- 密码:`node:crypto.scrypt`(内置,无 native 依赖;云函数已有 `installDependency: true` 先例,jsonwebtoken 同理)
- TOTP:RFC 6230/6238,30s 窗口、±1 窗口容错,SHA-1(主流验证器 App 的兼容基线);服务端用 `otplib`(纯 JS)。**不引入 SMS / 邮件通道**
- 绑定流程:登录后若 `totp_enabled=false` 强制进入绑定页 → 生成 secret + `otpauth://totp/Whimread:admin?secret=...&issuer=Whimread` → 前端用 `qrcode` 渲染二维码(唯一新增前端依赖)→ 输入一次有效码确认 → 展示 10 个备用码(**仅此一次**,提示保存)→ 启用
- 备用码:8 位数字,登录时可代替 TOTP 码,一次性,用后标记 `used_at`
- 应急恢复(设备 + 备用码全丢):`scripts/cloudbase/reset-admin-totp.mjs` 走 tcb CLI 直连 PG,清空 `totp_secret/totp_enabled/totp_failed_attempts` 并写一条 system 审计;runbook 写入 §10

### 5.2 会话令牌

| 令牌 | 形态 | 有效期 | 存储 |
|---|---|---|---|
| access JWT | HS256,`ADMIN_JWT_SECRET`,payload `{sub, kind:'admin', ver: session_version}` | 2h | 前端内存 + localStorage(单管理员内部工具,接受 XSS 残余风险;**不用 cookie**,天然无 CSRF) |
| login_token | 不透明随机串,sha256 存内存 Map(函数实例内,5 分钟过期) | 5min | 仅可调 change-password / totp 系端点 |
| refresh token | 不透明随机串(32B),sha256 入库,family 轮换 | 7d | 复用检测:旧 token 二次使用 → 撤销整个 family |

- access 校验:`jwt.verify` + 回库比对 `session_version` 与 `disabled`(一次单列查询,管理台流量可忽略);改密码 / reset-totp 时 `session_version+1`,全端立即失效
- **与设备 JWT 完全隔离**:不同算法(HS256 vs RS256)、不同密钥(`ADMIN_JWT_SECRET` vs `DEVICE_JWT_*`),设备 token 永远进不了管理面,反之亦然

### 5.3 登录流程(三段式)

```
POST /auth/login {username, password}
  ├─ locked_until 未到 / disabled → 401 ACCOUNT_LOCKED|ACCOUNT_DISABLED
  ├─ 密码错 → failed_attempts+1,≥5 → locked_until=now+15min → 401
  └─ 密码对 → 清零计数,按状态返回:
       must_change_password → {next:'change_password', change_token}
       totp_enabled         → {next:'totp',           login_token}
       否则(首登绑定前)      → {next:'totp_setup',     login_token}

POST /auth/change-password {change_token, new_password}   # ≥12 位,禁常见口令(top 1k 内置黑名单)
POST /auth/totp/setup       {login_token}                 # → {secret_base32, otpauth_url, backup_codes[10]}
POST /auth/totp/verify-setup{login_token, code}           # 启用 TOTP,签发正式会话
POST /auth/totp             {login_token, code}           # code 可为 TOTP 码或备用码
POST /auth/refresh          {refresh_token}               # 轮换;检测复用 → 撤 family
POST /auth/logout           {refresh_token}
```

TOTP 错误计数独立(`totp_failed_attempts`),≥5 同样锁 15 分钟;login/refresh 全部尝试均写审计(不含任何口令/码值)。

## 6. API 设计

### 6.1 admin-console(`/admin/*`,全部要求 access JWT)

**路径约定**:管理后台人用 API 统一 `/admin/*` 前缀;客户端/CI 等机器面统一 `/api/*`。CI 发布端点 `/api/admin/app/releases/*` 维持现状(机器对机器,不属于本管理台),后续如需对齐 `/admin/` 再单独迁移(需同步改 GitHub Actions 与密钥)。两者前缀不重叠,网关按前缀路由无歧义。

统一响应沿用 `errors.js` 的 `ok()/err()`;错误码扩 `ACCOUNT_LOCKED / ACCOUNT_DISABLED / TOTP_REQUIRED / TOTP_INVALID / CONCURRENT_MODIFY / VALIDATION_FAILED`。

| 方法 | 路径 | 入参 | 说明 |
|---|---|---|---|
| GET | `/overview` | — | 设备总数/今日新增、7 日发放/消耗(`quota_changes` 聚合)、7 日 LLM 调用数、封禁数 |
| GET | `/devices` | `query,status,page,page_size(≤100)` | android_id 模糊搜索 + status 筛选;按 created_at DESC |
| GET | `/devices/:androidId` | — | 详情 + 最近 50 条 `quota_changes`(含 star_redeem)+ 活跃 JWT 数 |
| POST | `/devices/:androidId/quota` | `{action:'grant'\|'reset', amount?, note, expected_updated_at}` | grant 调 `grantQuota(reason:'manual_grant')`;reset 置 0 并记 `manual_reset`;乐观锁见 §9 |
| POST | `/devices/:androidId/status` | `{status:'banned'\|'active', note, expected_updated_at}` | 封禁/解封(llm-proxy 与 register 已有 banned 拦截,此处只改状态) |
| POST | `/devices/:androidId/revoke-tokens` | `{note}` | `device_jwts` 全部未撤销行置 `revoked_at` |
| GET | `/feedback` | `status,kind,page` | 直查 `feedback_reports` |
| GET | `/feedback/:id` | — | 详情 + 附带 `feedback_logs`(按 seq) |
| GET | `/audit` | `action,page` | 审计流水,created_at DESC |

约束:响应**不回显**任何 secret/口令/备码;列表一律分页(控制面延迟,见 §12);设备操作类写接口全部写审计(同事务策略见 §4)。

### 6.2 device-auth 补齐:`POST /api/v1/devices/star/redeem`(设备 JWT)

对齐客户端 `DeviceAuthService.redeemStarQuota(githubLogin)` 既有契约(`{granted, quota_balance, github_login, message}`;错误码 `NOT_STARRED / ALREADY_REDEEMED`):

1. `verifyDeviceJwt` → android_id;`devices.status='banned'` 拒绝
2. 幂等检查:`quota_changes WHERE reason='star_redeem' AND metadata->>'github_login' = :login`(同一 GitHub 账号全库仅可兑一次,防换设备重复领)
3. GitHub 校验:`GET api.github.com/repos/{GITHUB_STAR_REPO}/stars/{login}` → 204 即已 star(带 `GITHUB_TOKEN` 环境变量防匿名限流;5xx 降级为 `GITHUB_VERIFY_FAILED`,**不发放**)
4. `grantQuota(androidId, STAR_REDEEM_AMOUNT=50, reason:'star_redeem', metadata:{github_login})`
5. 客户端侧同步修复 §2.3 的 `mapRedeemDioError`

新增环境变量(device-auth):`GITHUB_STAR_REPO`、`GITHUB_TOKEN`(可选)。

## 7. 安全设计

- **CORS**:admin-console 不用 `errors.js` 的 `Access-Control-Allow-Origin: *`,改为按 `ADMIN_WEB_ORIGINS`(逗号分隔白名单)回显 origin;无 cookie,无需 credentials 头
- **注入**:`db.js` 已做标识符白名单 + 参数化;`lib/repo.js` 延续,禁止字符串拼 SQL
- **敏感信息**:不 echo env/headers;审计不落口令与 TOTP 码;日志沿用 `common/logger.js`
- **传输**:CloudBase 默认 HTTPS;域名可后续绑自定义域(实施时记录到 runbook)
- **限流**:登录/TOTP 锁定走 DB 计数(函数多实例内存限流不可靠);feedback 的 LRU 模式不适用于低频管理台

## 8. 前端设计(admin/ 目录,独立于 Flutter)

```
admin/web/                  # Vite + React 18 + TS + Ant Design 5;qrcode(渲染绑定二维码)
  src/api/client.ts         # fetch 封装:Bearer 注入、401→refresh→重放、错误码→中文文案
  src/pages/Login.tsx       # 三段式向导:密码 → 改密(首登)/ TOTP / 绑定(首配)
  src/pages/Overview.tsx    # 4 张 Statistic 卡
  src/pages/Devices.tsx     # Table:搜索/状态筛选/分页
  src/pages/DeviceDetail.tsx# Descriptions + 流水 Table + 操作区(全部 Modal 二次确认 + 填 note)
  src/pages/Feedback.tsx    # Table + Drawer(详情/日志)
  src/pages/Audit.tsx       # Table
```

- 布局:antd `Layout` 侧边导航(总览/设备/反馈/审计);移动端不管(管理台桌面用)
- 路由与构建:`HashRouter`(URL 形如 `/admin/#/devices`,规避静态托管 404 回退配置);`vite.config.ts` 设 `base: '/admin/'`(子路径部署);API 地址经构建期 `VITE_API_BASE` 注入,由部署脚本按环境传入(§10)
- 交互红线:封禁、重置额度、踢下线三个动作必须二次确认并要求填写 note(note 进审计);操作失败展示后端错误码对应中文
- 会话:access 过期静默 refresh;refresh 失效跳登录;路由守卫校验登录态

## 9. 错误处理与并发

- **乐观锁**:`devices` 变更类请求带 `expected_updated_at`(GET 详情返回);update 语句追加 `AND updated_at = :expected`,命中 0 行 → 409 `CONCURRENT_MODIFY`,前端提示刷新重试。单管理员场景概率低,但成本仅一个 WHERE 条件
- **降级路径**:GitHub API 5xx / 超时 → redeem 拒绝发放(宁可让用户重试,不可多发);`ExecutePGSql` 控制面 5xx → 503 + 提示稍后重试
- **前端**:统一错误码→文案映射表;网络层错误与业务错误分离展示

## 10. 部署与运维

```bash
# 后端函数(纳入现有管线)
node scripts/cloudbase/sync-common.mjs
tcb fn deploy admin-console -e $ENV_ID
tcb fn config update admin-console -e $ENV_ID --env '{
  "ADMIN_JWT_SECRET":"...", "TCB_ENV_ID":"...", "ADMIN_WEB_ORIGINS":"https://<static-domain>"
}'
# device-auth 追加:GITHUB_STAR_REPO / GITHUB_TOKEN

# 前端静态托管(新增 scripts/cloudbase/deploy-admin.sh,风格对齐 deploy.sh:ENV 参数 + .env 注入)
./scripts/cloudbase/deploy-admin.sh dev     # dev | staging | prod
# 脚本内部:
#   cd admin/web && npm ci
#   VITE_API_BASE=$(从 .env 按环境取 API 域名) npm run build   # vite.config.ts base:'/admin/'
#   tcb hosting deploy ./dist -e "$ENV_ID" --path /admin        # CLI 参数以实现期实测为准
```

- `cloudbaserc.json` 增加 `admin-console` 函数定义(timeout 30s)
- **seed**:`scripts/cloudbase/seed-admin.mjs` 生成随机初始密码(打印一次)插入 `admins` 行(`must_change_password=true`),并提示首次登录完成 TOTP 绑定
- **runbook**(写入 `README-cloudbase.md` 附录):① TOTP 全丢 → `reset-admin-totp.mjs`;② 改密/换密钥 → 更新 env + `session_version+1`;③ 静态域名更换 → 同步 `ADMIN_WEB_ORIGINS`
- **托管形态决策**:CloudBase 静态网站托管(与函数同环境同账号,CDN/HTTPS 自带,单管理员流量对免费额度可忽略)。对比过 COS+CDN、GitHub Pages、云托管容器:要么新增运维面,要么跨境访问后端不顺,均不采用 [判断]
- **域名与 CORS**:各环境默认域名 `https://<envId>.tcloudbaseapp.com` 开箱可用、HTTPS 自带;可选绑自定义子域(需域名已备案,`whimread.dazhi.site` 已有先例)。域名定稿后写入 `.env`,并同步把前端 origin 加入 `ADMIN_WEB_ORIGINS`
- **SPA 深链**:HashRouter(URL 形如 `/admin/#/devices`)无需任何服务端 404 回退配置;若日后改 BrowserRouter,需在静态托管控制台把错误页指向 `index.html`,记入 runbook
- **可见性**:index.html 加 `<meta name="robots" content="noindex">`,避免被外部搜索引擎收录登录页;数据全部在认证之后,登录页公开可访问无妨
- **CI 自动部署(可选后置)**:GitHub Actions 监听 `admin/web/**` 变更自动构建+部署,需向 CI 注入 TCB 密钥;V1 与后端一致走手动脚本,待 CI 密钥接入到位再迁移

## 11. 测试策略

对齐 feedback 函数既有模式(`__tests__/` + `node:test`,逻辑层脱机可测):

- **函数单测**(`cloudfunctions/admin-console/__tests__/`):密码 hash/校验、TOTP 生成与 ±1 窗口验证、备用码一次性、refresh 轮换与复用检测撤 family、乐观锁 409、审计行组装;DB 层 mock `getDb`
- **device-auth redeem 单测**:幂等(同 github_login 二次兑换 → `ALREADY_REDEEMED`)、banned 拒绝、GitHub 校验失败不发额度
- **前端**:V1 不引 e2e 框架,交付一份手工 smoke 清单(登录三段式 → 设备搜索 → 调额度 → 审计可见 → 退出);`tsc --noEmit` + build 通过为门禁
- **迁移**:新 migration 在 dev 环境跑 `migrate.sh` 验证 up/down 注释正确性

## 12. 风险与实现期验证点

| # | 风险/待验证 | 影响 | 对策 |
|---|---|---|---|
| 1 | `ExecutePGSql` 单调用多语句事务性 | 审计与变更的原子性 | 实现计划第一步验证;不支持则「先审计后变更」降级(§4) |
| 2 | 控制面延迟高于直连 PG | 列表页响应 | 全部接口分页 + 命中已有索引(`idx_quota_changes_android_id` 等);overview 聚合限制 7 日窗口 |
| 3 | feedback 函数尚未 commit | 部署顺序依赖 | 实施前先独立 commit feedback 函数(与本设计解耦) |
| 4 | GitHub API 限流 | redeem 不可用 | `GITHUB_TOKEN` 提额;失败策略为拒绝发放(§6.2),无资损 |
| 5 | access JWT 存 localStorage 的 XSS 面 | 会话被窃 | 单管理员内部工具接受;refresh 7d + 复用检测兜底;V2 可评估 httpOnly cookie + 同域改造 |
| 6 | 静态托管域名与函数域跨域 | 配置遗漏导致前端不可用 | 部署清单强制项:`ADMIN_WEB_ORIGINS` 与实际托管域一致 |
