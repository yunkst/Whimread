# Whimread 管理后台(admin-console)实现计划

> **面向 AI 代理的工作者:** 必需子技能:使用 superpowers:subagent-driven-development(推荐)或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框(`- [ ]`)语法来跟踪进度。

**目标:** 为 Whimread CloudBase 托管后端交付一个带密码 + TOTP 双因素登录的独立 Web 管理后台(单管理员),V1 覆盖设备查询/额度调整/封禁踢下线、Star 兑换端点补齐、反馈工单、总览仪表盘与操作审计。

**架构:** 新增 `admin-console` 云函数(Nodejs20.19)承担 `/admin/api/*` 管理 API,SQL 全部集中在 `lib/repo.js`;前端为 `admin/web/` 下的 Vite + React + AntD 5 SPA,与函数同域部署(`whimread.dazhi.site/admin/`);device-auth 函数补一条 `POST /api/v1/devices/star/redeem`。认证为三段式(密码 → 改密/TOTP → 会话),access JWT(HS256)+ refresh token(sha256 入库、family 轮换)。

**技术栈:** CloudBase Event Function + common/db.js Builder(ExecutePGSql)、node:crypto(scrypt/HMAC-SHA1)、jsonwebtoken(HS256)、Vite + React 18 + TypeScript + Ant Design 5 + qrcode、node:test。

**规格:** [`docs/superpowers/specs/2026-09-09-admin-console-design.md`](../specs/2026-09-09-admin-console-design.md)(下文以 §N 引用)

---

## 0. 实施前须知(对规格的实现期修正与验证点)

实现中如遇规格与本计划冲突,**以本计划为准**(均已在本文件中注明理由):

1. **API 前缀细化为 `/admin/api/*`**(修正 §6.1 的 `/admin/*`):§10 已把 SPA 部署在 `/admin/` 静态托管,若 API 也占 `/admin/*`,同一前缀同时被静态托管与函数网关争抢,路由结果不确定。本计划把 API 触发路径定为 `/admin/api`,SPA 独占 `/admin/`。函数内部仍按规格路径(`/overview`、`/devices`…)匹配——`normalizePath` 会剥掉 `/admin` 与 `/api` 前缀,**网关是否透传完整路径都能工作**。
2. **login_token / change_token 改为短签名 JWT**(修正 §5.2 的「内存 Map」):三段式登录的两次请求可能落在不同函数实例(CloudBase 会缩容到 0),内存 Map 会丢 token 导致登录必挂。改为 HS256 签名、5 分钟过期的 JWT,claim `kind:'admin-login'` + `purpose`,无状态、语义不变。
3. **TOTP 自实现而非 otplib**(修正 §5.1):手写 RFC 6238 HMAC-SHA1 仅约 60 行(含 base32),可用 RFC 6238 官方测试向量验证正确性,且能精确测试 ±1 窗口;otplib 对「非当前时刻的码」无直接测试入口。不引入新 npm 依赖。
4. **密码黑名单 V1 内置 top 100**(§5.3 写的 top 1k):计划代码里放 top 100 真实高频口令,数据结构留好,后续扩充只改一个文件。
5. **验证点(§12.1)**:`ExecutePGSql` 单调用多语句的事务性 → 任务 1 探针实测,结果决定审计写入策略(任务 8 的 `AUDIT_BEFORE_CHANGE` 常量)。
6. **验证点**:`quota_changes_reason_check` 约束名以 dev 环境 `\d quota_changes` 实测为准(任务 1 步骤 2);`/admin/api` 前缀在网关/静态托管间的路由归属 → 任务 20 实测。
7. **grant/redeem 不复用 `common/quota.js` 的 `grantQuota()`**(规格 §6.1/§6.2 写「调 grantQuota」):管理台需要乐观锁(§9)与 metadata(github_login),而 `grantQuota()` 是读-改-写、不支持 metadata;计划在 repo.js 与 redeem handler 内自实现「UPDATE devices + INSERT quota_changes」,行为等价、审计更全。

## 1. 文件结构

```
cloudbase/migrations/
  20260909130000_admin_console.sql      # [新] admins/backup/refresh/audit 四表 + star_redeem 约束

cloudfunctions/admin-console/          # [新] 管理后台云函数(Nodejs20.19)
  package.json                          #    依赖:jsonwebtoken(common 合并后另有 node-sdk 等)
  index.js                              #    路由分发(仅 dispatch + requireAdmin 接线)
  lib/http.js                           #    响应工厂:CORS 白名单(ADMIN_WEB_ORIGINS)取代 errors.js 的 *
  lib/password.js                       #    scrypt hash/verify + 口令策略
  lib/password-blacklist.js             #    高频口令黑名单(top 100,可扩充)
  lib/base32.js                         #    RFC 4648 base32 编解码(TOTP secret 用)
  lib/totp.js                           #    RFC 6238 TOTP 生成/±1 窗口校验
  lib/session.js                        #    access/login/change token 签发校验 + refresh token 随机串/sha256
  lib/auth.js                           #    登录状态机(锁定计数/TOTP 绑定/备用码/轮换),SQL 经 repo 注入
  lib/repo.js                           #    全部 SQL(admins/refresh/audit/devices/feedback/overview)
  __tests__/password.test.js
  __tests__/totp.test.js
  __tests__/session.test.js
  __tests__/auth-flow.test.js           #    三段式全流程(注入 FakeRepo)

cloudfunctions/device-auth/
  index.js                              # [改] 新增 star/redeem 路由
  lib/github.js                         # [新] GitHub star 校验 + github_login 校验 + 兑换限流
  __tests__/redeem.test.js              # [新] 校验/限流/GitHub 结果映射(redeem 全链路由冒烟覆盖)

scripts/cloudbase/
  sync-common.mjs                       # [改] FUNCTIONS 数组增加 'admin-console'
  seed-admin.mjs                        # [新] 生成初始密码 + INSERT SQL(打印一次)
  reset-admin-totp.mjs                  # [新] 应急清 TOTP(tcb CLI 直连)
  deploy.sh                             # [改] 步骤 6 部署 admin-console;device-auth 注入 GITHUB_*
  deploy-admin.sh                       # [新] SPA 构建 + tcb hosting deploy --path /admin

cloudbaserc.json                        # [改] functions 数组增加 admin-console(timeout 30s)
.env.example                            # [改] ADMIN_JWT_SECRET/ADMIN_WEB_ORIGINS/GITHUB_STAR_REPO/GITHUB_TOKEN
README-cloudbase.md                     # [改] runbook 附录(TOTP 应急/换密钥/域名变更 + smoke 清单)

admin/web/                              # [新] 管理台 SPA(独立于 Flutter)
  package.json / vite.config.ts / tsconfig.json / index.html
  src/main.tsx / src/App.tsx            #    入口 + HashRouter 路由表 + 登录守卫
  src/api/client.ts                     #    fetch 封装:Bearer/401→refresh→重放/错误码→中文
  src/auth.tsx                          #    会话 Context(localStorage 持久化 refresh)
  src/pages/Login.tsx                   #    三段式向导
  src/pages/Overview.tsx                #    4 张 Statistic 卡
  src/pages/Devices.tsx / DeviceDetail.tsx
  src/pages/Feedback.tsx / Audit.tsx

lib/services/device/device_auth_service.dart   # [改] mapRedeemDioError 读 data['code'](§2.3)
test/unit/services/device/device_auth_service_test.dart  # [新] 错误码映射测试
```

**不做的事(YAGNI):** 不建 `star_redeems` 表(兑换记录 = `quota_changes WHERE reason='star_redeem'`,spec §4);不引入 e2e 框架;不改 device-auth 既有三路由;不做多管理员。

---

# Phase 1:数据层与认证基础(任务 1–8)

### 任务 1:DB migration + 多语句事务性探针

**文件:**
- 创建:`cloudbase/migrations/20260909130000_admin_console.sql`

- [ ] **步骤 1:写 migration 文件**

```sql
-- 20260909130000_admin_console.sql
--
-- 管理后台(admin-console)四张表 + quota_changes reason 约束放宽
-- 规格:docs/superpowers/specs/2026-09-09-admin-console-design.md §4
--   - admins:单行,seed-admin.mjs 插入;scrypt 口令哈希,TOTP 双因素
--   - admin_backup_codes:明文只在 totp/setup 响应出现一次,库存 scrypt hash
--   - admin_refresh_tokens:sha256 入库,family_id 轮换 + 复用检测撤全家
--   - admin_audit_logs:管理操作审计(规格 §6.1 约束:不落口令/TOTP 码)

CREATE TABLE IF NOT EXISTS admins (
    username             VARCHAR(50) PRIMARY KEY,
    pass_hash            TEXT NOT NULL,               -- scrypt$N$r$p$salthex$hashhex(N=2^15,r=8,p=1)
    totp_secret          TEXT,                        -- base32,绑定后非空
    totp_enabled         BOOLEAN NOT NULL DEFAULT FALSE,
    must_change_password BOOLEAN NOT NULL DEFAULT TRUE,
    session_version      INTEGER NOT NULL DEFAULT 0,  -- +1 即作废全部 access JWT
    failed_attempts      INTEGER NOT NULL DEFAULT 0,  -- 密码错误计数
    totp_failed_attempts INTEGER NOT NULL DEFAULT 0,  -- TOTP 错误计数(独立)
    locked_until         TIMESTAMPTZ,
    disabled             BOOLEAN NOT NULL DEFAULT FALSE,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at        TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS admin_backup_codes (
    id             BIGSERIAL PRIMARY KEY,
    admin_username VARCHAR(50) NOT NULL REFERENCES admins(username) ON DELETE CASCADE,
    code_hash      TEXT NOT NULL,
    used_at        TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_admin_backup_codes_admin
    ON admin_backup_codes(admin_username) WHERE used_at IS NULL;

CREATE TABLE IF NOT EXISTS admin_refresh_tokens (
    id             BIGSERIAL PRIMARY KEY,
    admin_username VARCHAR(50) NOT NULL REFERENCES admins(username) ON DELETE CASCADE,
    token_hash     TEXT NOT NULL UNIQUE,
    family_id      UUID NOT NULL,
    expires_at     TIMESTAMPTZ NOT NULL,
    revoked_at     TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_admin_refresh_family ON admin_refresh_tokens(family_id);

CREATE TABLE IF NOT EXISTS admin_audit_logs (
    id             BIGSERIAL PRIMARY KEY,
    admin_username VARCHAR(50) NOT NULL,
    action         VARCHAR(50) NOT NULL,   -- login/login_failed/lockout/quota_grant/quota_reset/
                                           -- device_ban/device_unban/revoke_tokens/totp_setup/
                                           -- change_password/system_reset_totp
    target_type    VARCHAR(30),            -- device / feedback / self / system
    target_id      TEXT,
    detail         JSONB,
    ip             VARCHAR(64),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_admin_audit_created ON admin_audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_action  ON admin_audit_logs(action, created_at DESC);

-- Star 兑换并发防重:同一 github_login 全库仅一条 star_redeem 流水
-- (redeem 幂等检查是先查后插,并发窗口靠此索引兜底,插入冲突 → ALREADY_REDEEMED)
CREATE UNIQUE INDEX IF NOT EXISTS uq_quota_changes_star_login
    ON quota_changes ((metadata->>'github_login')) WHERE reason = 'star_redeem';

-- quota_changes 补 'star_redeem'(Star 兑换此前无审计记录)
-- ⚠️ 实际约束名以 dev 环境 \d quota_changes 为准,不同则改下面两行
ALTER TABLE quota_changes DROP CONSTRAINT quota_changes_reason_check;
ALTER TABLE quota_changes ADD CONSTRAINT quota_changes_reason_check
    CHECK (reason IN ('register_bonus','llm_call','manual_grant',
                      'manual_reset','admin_revoke','star_redeem'));

COMMENT ON TABLE admins IS '管理后台账号(单管理员,seed-admin.mjs 插入)';
COMMENT ON TABLE admin_audit_logs IS '管理操作审计;detail 存 before/after、note、github_login 等';

-- down migration(回滚用)
-- ALTER TABLE quota_changes DROP CONSTRAINT quota_changes_reason_check;
-- ALTER TABLE quota_changes ADD CONSTRAINT quota_changes_reason_check
--     CHECK (reason IN ('register_bonus','llm_call','manual_grant','manual_reset','admin_revoke'));
-- DROP TABLE IF EXISTS admin_audit_logs;
-- DROP TABLE IF EXISTS admin_refresh_tokens;
-- DROP TABLE IF EXISTS admin_backup_codes;
-- DROP TABLE IF EXISTS admins;
```

- [ ] **步骤 2:确认既有约束名**

运行:`node scripts/cloudbase/apply-migration.mjs dev` **之前**,先用 queryPgDatabase 或 CloudBase 控制台对 dev 库执行:

```sql
SELECT conname FROM pg_constraint
WHERE conrelid = 'quota_changes'::regclass AND contype = 'c';
```

预期:输出里 `reason` 相关约束名(规格假定 `quota_changes_reason_check`)。若名字不同,修改 migration 的两行 ALTER。

- [ ] **步骤 3:应用 migration 到 dev**

运行:`node scripts/cloudbase/apply-migration.mjs dev 20260909130000`
预期:成功输出;再跑一遍 `node scripts/cloudbase/apply-migration.mjs dev 20260909130000` 应报「已应用」类错误(**不**重复执行——若脚本对重复 apply 静默通过,改用 `\d admins` 确认表已存在且无副作用即可)。

- [ ] **步骤 4:多语句事务性探针(§12.1 验证点)**

用 CloudBase 控制台 SQL 编辑器或 MCP(单次调用)执行一条含两条语句的 SQL:

```sql
INSERT INTO admin_audit_logs (admin_username, action) VALUES ('__probe__','probe_stmt1');
INSERT INTO admin_audit_logs (admin_username, action) VALUES (NULL, NULL);
```

预期:第二条违反 NOT NULL 报错。随后执行 `SELECT COUNT(*) FROM admin_audit_logs WHERE admin_username='__probe__';`

- 计数 = 0 → **单调用多语句是事务性的**(罕见但理想):任务 8 的 `AUDIT_BEFORE_CHANGE = false`,变更+审计一次调用提交。
- 计数 = 1 → **非事务性**:任务 8 的 `AUDIT_BEFORE_CHANGE = true`,先写审计再变更,接受极端故障下的孤儿审计行(规格 §4 已预留此降级)。

清理:`DELETE FROM admin_audit_logs WHERE admin_username='__probe__';`
**把结果记到任务 8 步骤 1 的常量注释里。**

- [ ] **步骤 5:Commit**

```bash
git add cloudbase/migrations/20260909130000_admin_console.sql
git commit -m "feat(db): admin_console 迁移(admins/refresh/audit 四表 + star_redeem 约束)"
```

---

### 任务 2:seed-admin 脚本

**文件:**
- 创建:`scripts/cloudbase/seed-admin.mjs`

- [ ] **步骤 1:写脚本**

生成随机初始密码(打印**一次**)+ scrypt 哈希,输出 `INSERT ... ON CONFLICT DO NOTHING` SQL 供运维在 CloudBase 控制台 SQL 编辑器执行(手动部署链路,不直连库)。scrypt 参数与任务 3 的 `lib/password.js` 完全一致(`scrypt$32768$8$1$...` 格式)。

```js
#!/usr/bin/env node
/**
 * seed-admin.mjs — 生成管理员初始账号 SQL(单管理员,规格 §10)
 *
 * 用法: node scripts/cloudbase/seed-admin.mjs <username>
 *
 * 输出:
 *   1. 初始密码(仅打印一次,提示立即保存;首登强制改密)
 *   2. INSERT SQL — 复制到 CloudBase 控制台 SQL 编辑器执行
 *
 * 不落任何明文到文件;--quiet 只打印 SQL(用于 CI 场景,慎用)
 */

import crypto from 'node:crypto';

const username = process.argv[2];
if (!username || !/^[a-zA-Z0-9_-]{3,50}$/.test(username)) {
    console.error('用法: node scripts/cloudbase/seed-admin.mjs <username>(3-50 位字母数字_-)');
    process.exit(1);
}

// scrypt 参数必须与 cloudfunctions/admin-console/lib/password.js 一致
const N = 1 << 15, r = 8, p = 1;

function hashPassword(password) {
    const salt = crypto.randomBytes(16).toString('hex');
    const hash = crypto.scryptSync(password, salt, 64, { N, r, p }).toString('hex');
    return `scrypt$${N}$${r}$${p}$${salt}$${hash}`;
}

const password = crypto.randomBytes(18).toString('base64url'); // 24 字符,含大小写数字-_ 不含易混字符问题
const passHash = hashPassword(password);

const sql = `INSERT INTO admins (username, pass_hash, must_change_password)
VALUES ('${username}', '${passHash}', TRUE)
ON CONFLICT (username) DO UPDATE
    SET pass_hash = EXCLUDED.pass_hash,
        must_change_password = TRUE,
        totp_enabled = FALSE,
        totp_secret = NULL,
        totp_failed_attempts = 0,
        failed_attempts = 0,
        locked_until = NULL,
        disabled = FALSE,
        session_version = admins.session_version + 1;`;

if (!process.argv.includes('--quiet')) {
    console.log('======================================================');
    console.log('初始密码(仅此一次,请立即保存到密码管理器):');
    console.log('  ' + password);
    console.log('======================================================');
}
console.log('\n-- 在 CloudBase 控制台 SQL 编辑器(对应环境)执行:\n');
console.log(sql);
console.log('\n-- 首次登录将强制改密并绑定 TOTP。重跑本脚本即重置该账号。');
```

- [ ] **步骤 2:本地演练(不连库)**

运行:`node scripts/cloudbase/seed-admin.mjs admin`
预期:打印 24 字符初始密码与一条合法 SQL;scrypt 计算耗时 < 2s。

- [ ] **步骤 3:Commit**

```bash
git add scripts/cloudbase/seed-admin.mjs
git commit -m "feat(scripts): seed-admin 管理员初始账号生成脚本"
```

---

### 任务 3:admin-console 骨架 + 密码模块

**文件:**
- 创建:`cloudfunctions/admin-console/package.json`
- 创建:`cloudfunctions/admin-console/lib/password.js`
- 创建:`cloudfunctions/admin-console/lib/password-blacklist.js`
- 测试:`cloudfunctions/admin-console/__tests__/password.test.js`

- [ ] **步骤 1:创建 package.json**

```json
{
  "name": "admin-console",
  "version": "0.1.0",
  "description": "Whimread 管理后台云函数:管理员认证 + 设备/反馈/审计管理",
  "main": "index.js",
  "private": true,
  "scripts": {
    "test": "node --test __tests__/"
  },
  "dependencies": {
    "jsonwebtoken": "^9.0.2"
  }
}
```

运行 `node scripts/cloudbase/sync-common.mjs` 会把 `common/` 的依赖(如 `@cloudbase/node-sdk`)自动合并进来并复制 `common/` 到本目录——**见本任务步骤 2,必须先于任务 6/8 中任何 `require('./common/db')` 执行**。TOTP 不需要 otplib(任务 4 手写实现,见 §0.3)。

- [ ] **步骤 2:sync-common 纳入 admin-console**

修改 `scripts/cloudbase/sync-common.mjs` 第 24 行的 FUNCTIONS 数组:

```js
const FUNCTIONS = ['device-auth', 'app-release', 'llm-proxy', 'feedback', 'admin-console'];
```

运行:`node scripts/cloudbase/sync-common.mjs`
预期:输出 `[OK] admin-console: common/ 同步完成(8 个文件, deps 合并)`,函数目录出现 `common/` 子目录,本函数 package.json 依赖被合并入 `@cloudbase/node-sdk` 等(任务 20 部署前重跑同一命令即可,无需再改数组)。

随后本地安装依赖(仓库惯例是每函数独立 `node_modules`;任务 5 起 `jsonwebtoken` 的 require 依赖它):

运行:`cd cloudfunctions/admin-console && npm install`
预期:生成 `node_modules/`,无 error 输出。

- [ ] **步骤 3:编写失败的测试**

`__tests__/password.test.js`:

```js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { hashPassword, verifyPassword, validatePasswordPolicy,
        generateBackupCodes, hashBackupCode, verifyBackupCode } = require('../lib/password');

test('hash/verify roundtrip', () => {
    const hash = hashPassword('Correct-Horse-42x');
    assert.ok(hash.startsWith('scrypt$32768$8$1$'));
    assert.equal(verifyPassword('Correct-Horse-42x', hash), true);
});

test('wrong password / tampered hash', () => {
    const hash = hashPassword('Correct-Horse-42x');
    assert.equal(verifyPassword('wrong-password-99', hash), false);
    const parts = hash.split('$'); parts[5] = parts[5].replace(/.$/, (c) => (c === '0' ? '1' : '0'));
    assert.equal(verifyPassword('Correct-Horse-42x', parts.join('$')), false);
    assert.equal(verifyPassword('x', 'garbage'), false);
});

test('password policy', () => {
    assert.equal(validatePasswordPolicy('Sh0rt-1'), 'TOO_SHORT');
    assert.equal(validatePasswordPolicy('all-lowercase-123'), 'WEAK');
    assert.equal(validatePasswordPolicy('password123456!!'), 'COMMON');   // 黑名单
    assert.equal(validatePasswordPolicy('Whimread-Admin-2026'), null);
});

test('backup codes: 8 位数字,hash 可校验', () => {
    const codes = generateBackupCodes(10);
    assert.equal(codes.length, 10);
    for (const c of codes) assert.match(c, /^\d{8}$/);
    const h = hashBackupCode(codes[0]);
    assert.equal(verifyBackupCode(codes[0], h), true);
    assert.equal(verifyBackupCode('00000000', h), false);
});
```

- [ ] **步骤 4:运行测试验证失败**

运行:`cd cloudfunctions/admin-console && npm test`
预期:FAIL,`Cannot find module '../lib/password'`。

- [ ] **步骤 5:实现 lib/password.js 与黑名单**

`lib/password.js`:

```js
/**
 * 口令哈希与策略(规格 §5.1)
 * 格式:scrypt$N$r$p$salthex$hashhex — 与 scripts/cloudbase/seed-admin.mjs 保持一致
 * scrypt 为 node:crypto 内置,无 native 依赖
 */

'use strict';
const crypto = require('crypto');
const { COMMON_PASSWORDS } = require('./password-blacklist');

const SCRYPT_N = 1 << 15;   // 32768
const SCRYPT_R = 8;
const SCRYPT_P = 1;
const KEYLEN = 64;

function hashPassword(password) {
    const salt = crypto.randomBytes(16).toString('hex');
    const hash = crypto.scryptSync(password, salt, KEYLEN, { N: SCRYPT_N, r: SCRYPT_R, p: SCRYPT_P }).toString('hex');
    return `scrypt$${SCRYPT_N}$${SCRYPT_R}$${SCRYPT_P}$${salt}$${hash}`;
}

function verifyPassword(password, stored) {
    const parts = String(stored || '').split('$');
    if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
    const [, n, r, p, salt, expected] = parts;
    const actual = crypto.scryptSync(password, salt, expected.length / 2,
        { N: parseInt(n, 10), r: parseInt(r, 10), p: parseInt(p, 10) });
    const expectedBuf = Buffer.from(expected, 'hex');
    return actual.length === expectedBuf.length && crypto.timingSafeEqual(actual, expectedBuf);
}

/** 返回 null 表示通过,否则为错误码(TOO_SHORT/TOO_LONG/WEAK/COMMON) */
function validatePasswordPolicy(password) {
    if (typeof password !== 'string' || password.length < 12) return 'TOO_SHORT';
    if (password.length > 128) return 'TOO_LONG';
    if (!/[a-z]/.test(password) || !/[A-Z]/.test(password) || !/[0-9]/.test(password)) return 'WEAK';
    if (COMMON_PASSWORDS.has(password.toLowerCase())) return 'COMMON';
    return null;
}

/** 备用恢复码:8 位数字,库存 scrypt hash(规格 §5.1) */
function generateBackupCodes(count = 10) {
    return Array.from({ length: count }, () => String(crypto.randomInt(0, 1e8)).padStart(8, '0'));
}

const hashBackupCode = hashPassword;
const verifyBackupCode = verifyPassword;

module.exports = { hashPassword, verifyPassword, validatePasswordPolicy,
                   generateBackupCodes, hashBackupCode, verifyBackupCode,
                   SCRYPT_N, SCRYPT_R, SCRYPT_P };
```

`lib/password-blacklist.js`(top 100 高频口令,全小写;后续扩充只改此文件,§0.4):

```js
'use strict';
// top 100 高频口令(来源:公开泄露库高频榜,全小写;命中比较时口令已 toLowerCase)
const LIST = ['123456', 'password', '123456789', '12345678', '12345', 'qwerty', '1234567890',
    '1234567', '111111', '123123', 'abc123', 'password1', '1234', 'qwerty123', '000000',
    'iloveyou', '1q2w3e4r', 'qwertyuiop', 'monkey', 'dragon', '123321', '654321', '666666',
    '123qwe', 'myspace1', '121212', 'homelesspa', '123abc', 'sunshine', 'princess',
    'letmein', 'football', 'welcome', 'admin', 'admin123', 'root', 'toor', 'pass123',
    'master', 'hello', 'freedom', 'whatever', 'qazwsx', 'trustno1', 'batman', 'superman',
    'michael', 'shadow', 'baseball', 'soccer', 'hockey', 'killer', 'george', 'sexy',
    'andrew', 'charlie', 'jordan', 'jennifer', 'hunter', 'buster', 'thomas', 'tigger',
    'robert', 'soccer1', 'harley', 'ranger', 'daniel', 'starwars', 'klaster', '112233',
    'asdf', 'zxcvbnm', 'asdfgh', 'computer', 'michelle', 'jessica', 'pepper', '1111',
    'zxcvbn', '555555', '11111111', '131313', 'freedom1', '777777', 'pass', 'maggie',
    '159753', 'aaaaaa', 'ginger', 'princess1', 'joshua', 'cheese', 'amanda', 'summer',
    'ashley', 'nicole', 'chelsea', 'biteme', 'matthew', 'access', 'yankees', '987654321',
    'dallas', 'austin', 'thunder', 'taylor', 'matrix', 'mustang', 'whimread', 'whimread123'];
module.exports = { COMMON_PASSWORDS: new Set(LIST) };
```

- [ ] **步骤 6:运行测试验证通过**

运行:`cd cloudfunctions/admin-console && npm test`
预期:PASS(4 个用例)。scrypt 每次调用约 100ms,总时长可接受。

- [ ] **步骤 7:Commit**

```bash
git add cloudfunctions/admin-console
git commit -m "feat(admin-console): 函数骨架 + scrypt 口令模块与备用码"
```

---

### 任务 4:base32 + TOTP(RFC 6238 手写实现)

**文件:**
- 创建:`cloudfunctions/admin-console/lib/base32.js`
- 创建:`cloudfunctions/admin-console/lib/totp.js`
- 测试:`cloudfunctions/admin-console/__tests__/totp.test.js`

- [ ] **步骤 1:编写失败的测试**(用 RFC 6238 官方测试向量)

`__tests__/totp.test.js`:

```js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { base32Encode, base32Decode } = require('../lib/base32');
const { generateSecret, totpAt, verifyTotp } = require('../lib/totp');

// RFC 6238 附录 B 的 SHA-1 向量:secret = ASCII "12345678901234567890"
const RFC_SECRET = base32Encode(Buffer.from('12345678901234567890', 'ascii'));

test('base32 roundtrip(RFC 4648 向量)', () => {
    assert.equal(base32Encode(Buffer.from('foo')), 'MZXW6===');
    assert.equal(base32Encode(Buffer.from('foob')), 'MZXW6YQ=');
    assert.equal(Buffer.from(base32Decode('MZXW6===')).toString(), 'foo');
    assert.equal(Buffer.from(base32Decode('MZXW6YQ=')).toString(), 'foob');
});

test('RFC 6238 向量:T=59s → 6 位码 287082(8 位 94287082)', () => {
    assert.equal(totpAt(RFC_SECRET, 59_000, 8), '94287082');
    assert.equal(totpAt(RFC_SECRET, 59_000, 6), '287082');
    assert.equal(totpAt(RFC_SECRET, 1111111109000, 8), '07081804');
    assert.equal(totpAt(RFC_SECRET, 1234567890000, 8), '89005924');
});

test('verifyTotp:当前时刻通过,±1 窗口容错,±2 拒绝', () => {
    const secret = generateSecret();
    const t0 = 1_700_000_000_000;   // 对齐 30s 步长的采样点
    const code = totpAt(secret, t0, 6);
    assert.equal(verifyTotp(secret, code, t0), true);
    assert.equal(verifyTotp(secret, totpAt(secret, t0 - 30_000, 6), t0), true);   // 上一窗
    assert.equal(verifyTotp(secret, totpAt(secret, t0 + 30_000, 6), t0), true);   // 下一窗
    assert.equal(verifyTotp(secret, totpAt(secret, t0 - 90_000, 6), t0), false);  // 超窗
    assert.equal(verifyTotp(secret, '123456', t0), false);
    assert.equal(verifyTotp(secret, 'abcdef', t0), false);   // 非数字
});

test('generateSecret:base32 且长度稳定(20 字节 → 32 字符)', () => {
    assert.equal(generateSecret().length, 32);
});
```

- [ ] **步骤 2:运行测试验证失败**

运行:`cd cloudfunctions/admin-console && npm test`
预期:新增用例 FAIL(`Cannot find module '../lib/totp'`),任务 3 的用例仍 PASS。

- [ ] **步骤 3:实现 base32.js 与 totp.js**

`lib/base32.js`:

```js
'use strict';
// RFC 4648 base32(A-Z2-5,带 = padding),TOTP secret 专用
const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function base32Encode(buf) {
    let bits = 0, value = 0, out = '';
    for (const byte of buf) {
        value = (value << 8) | byte; bits += 8;
        while (bits >= 5) { out += ALPHABET[(value >>> (bits - 5)) & 31]; bits -= 5; }
    }
    if (bits > 0) out += ALPHABET[(value << (5 - bits)) & 31];
    return out + '='.repeat((8 - (out.length % 8)) % 8);
}

function base32Decode(str) {
    const clean = String(str).replace(/=+$/, '').toUpperCase();
    let bits = 0, value = 0;
    const bytes = [];
    for (const ch of clean) {
        const idx = ALPHABET.indexOf(ch);
        if (idx === -1) throw new Error('invalid base32 char');
        value = (value << 5) | idx; bits += 5;
        if (bits >= 8) { bytes.push((value >>> (bits - 8)) & 0xff); bits -= 8; }
    }
    return Buffer.from(bytes);
}

module.exports = { base32Encode, base32Decode };
```

`lib/totp.js`:

```js
/**
 * RFC 6238 TOTP(HMAC-SHA1,30s 步长,默认 6 位)
 * 手写而非 otplib 的理由见计划 §0.3:可用 RFC 官方向量测试,±1 窗口可精确验证。
 * SHA-1 是主流验证器 App(Google/Microsoft Authenticator)的兼容基线。
 */

'use strict';
const crypto = require('crypto');
const { base32Encode, base32Decode } = require('./base32');

const STEP_SEC = 30;
const DEFAULT_DIGITS = 6;
const DRIFT_WINDOWS = 1;

function generateSecret() {
    return base32Encode(crypto.randomBytes(20));
}

/** HOTP(RFC 4226):HMAC-SHA1 动态截断 */
function hotp(secretBuf, counter, digits) {
    const msg = Buffer.alloc(8);
    msg.writeBigUInt64BE(BigInt(counter));
    const h = crypto.createHmac('sha1', secretBuf).update(msg).digest();
    const off = h[h.length - 1] & 0x0f;
    const bin = ((h[off] & 0x7f) << 24) | (h[off + 1] << 16) | (h[off + 2] << 8) | h[off + 3];
    return String(bin % 10 ** digits).padStart(digits, '0');
}

/** 指定时刻的 TOTP 码(timeMs 毫秒;digits 参数仅供测试) */
function totpAt(secret, timeMs, digits = DEFAULT_DIGITS) {
    return hotp(base32Decode(secret), Math.floor(timeMs / 1000 / STEP_SEC), digits);
}

/** 校验:±1 窗口容错,常数时间比较 */
function verifyTotp(secret, code, nowMs = Date.now(), drift = DRIFT_WINDOWS) {
    const c = String(code || '').replace(/\s+/g, '');
    if (!/^\d{6}$/.test(c)) return false;
    const counter = Math.floor(nowMs / 1000 / STEP_SEC);
    let key;
    try { key = base32Decode(secret); } catch { return false; }
    for (let i = -drift; i <= drift; i++) {
        const expected = Buffer.from(hotp(key, counter + i, DEFAULT_DIGITS));
        if (crypto.timingSafeEqual(expected, Buffer.from(c))) return true;
    }
    return false;
}

/** 规格 §5.1:otpauth 绑定链接(qrcode 由前端渲染) */
function otpauthUrl(secret, username) {
    const label = encodeURIComponent(`Whimread:${username}`);
    return `otpauth://totp/${label}?secret=${secret}&issuer=Whimread&algorithm=SHA1&digits=6&period=30`;
}

module.exports = { generateSecret, totpAt, verifyTotp, otpauthUrl, STEP_SEC, DEFAULT_DIGITS };
```

- [ ] **步骤 4:运行测试验证通过**

运行:`cd cloudfunctions/admin-console && npm test`
预期:PASS(含 RFC 向量 4 条断言)。若 287082 断言失败,优先检查 `hotp` 的 `& 0x7f` 截断与 BigInt counter 写法。

- [ ] **步骤 5:Commit**

```bash
git add cloudfunctions/admin-console/lib/base32.js cloudfunctions/admin-console/lib/totp.js cloudfunctions/admin-console/__tests__/totp.test.js
git commit -m "feat(admin-console): RFC 6238 TOTP 手写实现(base32 + ±1 窗口,RFC 向量测试)"
```

---

### 任务 5:会话令牌模块 session.js

**文件:**
- 创建:`cloudfunctions/admin-console/lib/session.js`
- 测试:`cloudfunctions/admin-console/__tests__/session.test.js`

- [ ] **步骤 1:编写失败的测试**

```js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { signAccessToken, verifyAccessToken, signLoginToken, verifyLoginToken,
        newRefreshToken, hashToken } = require('../lib/session');

process.env.ADMIN_JWT_SECRET = 'test-secret-for-unit-tests-only';

test('access token roundtrip(HS256, kind=admin)', () => {
    const t = signAccessToken('admin', 3);
    const claims = verifyAccessToken(t);
    assert.equal(claims.sub, 'admin');
    assert.equal(claims.kind, 'admin');
    assert.equal(claims.ver, 3);
});

test('login token:purpose 校验,5 分钟过期', () => {
    const t = signLoginToken('admin', 'totp_setup');
    assert.equal(verifyLoginToken(t, 'totp_setup').sub, 'admin');
    assert.throws(() => verifyLoginToken(t, 'totp'), (e) => e.code === 'JWT_INVALID');
});

test('access token:设备 JWT 形态的 kind 拒绝', () => {
    // 用同一密钥签一个 kind:device 的 token(模拟设备 token 混入)
    const jwt = require('jsonwebtoken');
    const fake = jwt.sign({ sub: 'dev1', kind: 'device' }, process.env.ADMIN_JWT_SECRET, { algorithm: 'HS256' });
    assert.throws(() => verifyAccessToken(fake), (e) => e.code === 'JWT_INVALID');
});

test('过期 access token → JWT_EXPIRED', () => {
    const jwt = require('jsonwebtoken');
    const expired = jwt.sign({ sub: 'admin', kind: 'admin', ver: 0 },
        process.env.ADMIN_JWT_SECRET, { algorithm: 'HS256', expiresIn: '-10s' });
    assert.throws(() => verifyAccessToken(expired), (e) => e.code === 'JWT_EXPIRED');
});

test('refresh token:32 字节 base64url,sha256 可复算', () => {
    const { raw, hash } = newRefreshToken();
    assert.match(raw, /^[A-Za-z0-9_-]{43}$/);   // 32 字节 base64url 无 padding
    assert.equal(hashToken(raw), hash);
    assert.notEqual(newRefreshToken().raw, raw);
});
```

- [ ] **步骤 2:运行测试验证失败**

运行:`cd cloudfunctions/admin-console && npm test`
预期:新增用例 FAIL(`Cannot find module '../lib/session'`)。

- [ ] **步骤 3:实现 lib/session.js**

```js
/**
 * 会话令牌(规格 §5.2)
 * - access JWT:HS256 + ADMIN_JWT_SECRET,payload {sub, kind:'admin', ver:session_version},2h
 *   与设备 JWT(RS256/DEVICE_JWT_*、kind:'device')完全隔离:不同算法 + 不同密钥 + kind 区分
 * - login/change token:不透明化的短签名 JWT(5min,purpose 区分)——修正规格 §5.2 的
 *   「内存 Map」:云函数实例间不共享内存,三段式跨请求会丢 token(计划 §0.2)
 * - refresh token:32B 随机串,sha256 入库,轮换与复用检测的 DB 逻辑在 lib/auth.js
 */

'use strict';
const crypto = require('crypto');
const jwt = require('jsonwebtoken');

const ACCESS_TTL_SEC = 2 * 3600;
const LOGIN_TTL_SEC = 5 * 60;
const REFRESH_TTL_SEC = 7 * 24 * 3600;

function requireSecret() {
    const s = process.env.ADMIN_JWT_SECRET;
    if (!s) {
        const e = new Error('ADMIN_JWT_SECRET not configured');
        e.code = 'SERVER_NO_SECRET';
        throw e;
    }
    return s;
}

function jwtError(e) {
    const err = new Error(e.name === 'TokenExpiredError' ? 'JWT_EXPIRED' : 'JWT_INVALID');
    err.code = err.message;
    return err;
}

function signAccessToken(username, sessionVersion) {
    return jwt.sign({ sub: username, kind: 'admin', ver: sessionVersion },
        requireSecret(), { algorithm: 'HS256', expiresIn: ACCESS_TTL_SEC, jwtid: crypto.randomUUID() });
}

function verifyAccessToken(token) {
    let claims;
    try {
        claims = jwt.verify(token, requireSecret(), { algorithms: ['HS256'] });
    } catch (e) { throw jwtError(e); }
    if (claims.kind !== 'admin') {
        const e = new Error('JWT_INVALID'); e.code = 'JWT_INVALID'; throw e;
    }
    return claims;
}

function signLoginToken(username, purpose) {   // purpose: 'change_password' | 'totp' | 'totp_setup'
    return jwt.sign({ sub: username, kind: 'admin-login', purpose },
        requireSecret(), { algorithm: 'HS256', expiresIn: LOGIN_TTL_SEC, jwtid: crypto.randomUUID() });
}

function verifyLoginToken(token, expectedPurpose) {
    let claims;
    try {
        claims = jwt.verify(token, requireSecret(), { algorithms: ['HS256'] });
    } catch (e) { throw jwtError(e); }
    if (claims.kind !== 'admin-login' || claims.purpose !== expectedPurpose) {
        const e = new Error('JWT_INVALID'); e.code = 'JWT_INVALID'; throw e;
    }
    return claims;
}

function newRefreshToken() {
    const raw = crypto.randomBytes(32).toString('base64url');
    return { raw, hash: hashToken(raw) };
}

function hashToken(raw) {
    return crypto.createHash('sha256').update(String(raw), 'utf8').digest('hex');
}

module.exports = { signAccessToken, verifyAccessToken, signLoginToken, verifyLoginToken,
                   newRefreshToken, hashToken,
                   ACCESS_TTL_SEC, LOGIN_TTL_SEC, REFRESH_TTL_SEC };
```

- [ ] **步骤 4:运行测试验证通过**

运行:`cd cloudfunctions/admin-console && npm test`
预期:PASS(此文件 5 个用例)。

- [ ] **步骤 5:Commit**

```bash
git add cloudfunctions/admin-console/lib/session.js cloudfunctions/admin-console/__tests__/session.test.js
git commit -m "feat(admin-console): 会话令牌(access HS256 2h / login-token 5min / refresh sha256)"
```

---

### 任务 6:lib/repo.js(SQL 全集中)

**文件:**
- 创建:`cloudfunctions/admin-console/lib/repo.js`

说明:`common/db.js` Builder 不支持 offset / JSON 操作符 / 列间运算(`failed_attempts + 1`),所以 repo.js 的列表与聚合查询走 `db.raw()`,字符串值一律经 `esc()` 内联(与 db.js Builder 内部做法一致,禁止调用方拼 SQL);等值查询尽量走 Builder。**本文件不做单测**(executePGSql 无法注入,§11 的「DB 层 mock」由任务 7 的 FakeRepo 在 auth 层达成),正确性由任务 21 冒烟清单在 dev 环境验证。

- [ ] **步骤 1:实现 lib/repo.js**

```js
/**
 * admin-console 全部 SQL 的唯一出入口(规格 §3.1:为将来迁独立服务留缝隙)
 * 约定:所有函数第一个参数是 db(getDb() 返回的 facade),便于将来替换实现。
 * 禁止在 repo.js 之外出现任何 SQL 字符串。
 *
 * AUDIT_BEFORE_CHANGE:任务 1 步骤 4 探针结论。
 *   true  = ExecutePGSql 单调用多语句非事务 → 先写审计再变更(孤儿审计行可接受)
 *   false = 事务性 → 变更与审计一次调用提交
 * 【实施时按探针结果改这里】
 */
const AUDIT_BEFORE_CHANGE = true;

/** 内联值的 SQL 转义(与 common/db.js QueryBuilder._execute 同风格) */
function esc(v) {
    if (v === null || v === undefined) return 'NULL';
    if (typeof v === 'number') return Number.isFinite(v) ? String(v) : 'NULL';
    if (typeof v === 'boolean') return v ? 'TRUE' : 'FALSE';
    return `'${String(v).replace(/'/g, "''")}'`;
}

/** rowsToObjects 对 JSONB 可能给字符串,统一兜底 parse */
function parseJsonCols(rows, cols) {
    for (const row of rows || []) {
        for (const c of cols) {
            if (typeof row[c] === 'string') { try { row[c] = JSON.parse(row[c]); } catch { /* 保持原样 */ } }
        }
    }
    return rows;
}

function pageClause({ page = 1, pageSize = 20 }, maxPageSize = 100) {
    const limit = Math.min(parseInt(pageSize, 10) || 20, maxPageSize);
    const pageNum = Math.max(parseInt(page, 10) || 1, 1);
    return { limit, offset: (pageNum - 1) * limit };
}

// ---------- admins ----------

async function getAdmin(db, username) {
    const { data, error } = await db.from('admins')
        .select('username, pass_hash, totp_secret, totp_enabled, must_change_password, session_version, failed_attempts, totp_failed_attempts, locked_until, disabled')
        .eq('username', username).single();
    if (error) {
        if (error.code === 'NOT_FOUND') return null;
        throw error;
    }
    return data;
}

async function recordPasswordFailure(db, username) {
    const { data, error } = await db.raw(
        `UPDATE admins SET failed_attempts = failed_attempts + 1
         WHERE username = ${esc(username)} RETURNING failed_attempts`);
    if (error) throw error;
    return { attempts: Number(data?.[0]?.failed_attempts ?? 0) };
}

async function recordTotpFailure(db, username) {
    const { data, error } = await db.raw(
        `UPDATE admins SET totp_failed_attempts = totp_failed_attempts + 1
         WHERE username = ${esc(username)} RETURNING totp_failed_attempts`);
    if (error) throw error;
    return { attempts: Number(data?.[0]?.totp_failed_attempts ?? 0) };
}

async function lockAdmin(db, username, until) {
    const { error } = await db.from('admins')
        .update({ locked_until: until.toISOString() }).eq('username', username);
    if (error) throw error;
}

async function clearAuthFailures(db, username) {
    const { error } = await db.from('admins').update({
        failed_attempts: 0, totp_failed_attempts: 0, locked_until: null,
        last_login_at: new Date().toISOString(),
    }).eq('username', username);
    if (error) throw error;
}

/** 改密并使全部 access JWT 失效(session_version = session_version + 1,须 raw) */
async function updateAdminPassword(db, username, passHash) {
    const { data, error } = await db.raw(
        `UPDATE admins SET pass_hash = ${esc(passHash)},
            must_change_password = FALSE, session_version = session_version + 1
         WHERE username = ${esc(username)} RETURNING session_version`);
    if (error) throw error;
    return Number(data?.[0]?.session_version ?? 0);
}

async function setTotpSecret(db, username, secret) {
    const { error } = await db.from('admins')
        .update({ totp_secret: secret }).eq('username', username);
    if (error) throw error;
}

async function enableTotp(db, username) {
    const { error } = await db.from('admins').update({
        totp_enabled: true, totp_failed_attempts: 0, must_change_password: false,
    }).eq('username', username);
    if (error) throw error;
}

// ---------- backup codes ----------

async function replaceBackupCodes(db, username, codeHashes) {
    await db.from('admin_backup_codes').delete().eq('admin_username', username).is('used_at', null);
    for (const hash of codeHashes) {
        const { error } = await db.from('admin_backup_codes').insert({ admin_username: username, code_hash: hash });
        if (error) throw error;
    }
}

async function listUnusedBackupCodes(db, username) {
    const { data, error } = await db.from('admin_backup_codes')
        .select('id, code_hash').eq('admin_username', username).is('used_at', null);
    if (error) throw error;
    return data || [];
}

/** 单次使用:WHERE used_at IS NULL 保证并发下只有一次命中 */
async function consumeBackupCode(db, id) {
    const { data, error } = await db.from('admin_backup_codes')
        .update({ used_at: new Date().toISOString() })
        .eq('id', id).is('used_at', null).select('id');
    if (error) throw error;
    return (data || []).length > 0;
}

// ---------- refresh tokens ----------

async function getRefreshTokenByHash(db, tokenHash) {
    const { data, error } = await db.from('admin_refresh_tokens')
        .select('id, admin_username, family_id, expires_at, revoked_at')
        .eq('token_hash', tokenHash).single();
    if (error) {
        if (error.code === 'NOT_FOUND') return null;
        throw error;
    }
    return data;
}

async function insertRefreshToken(db, { username, hash, familyId, expiresAt }) {
    const { error } = await db.from('admin_refresh_tokens').insert({
        admin_username: username, token_hash: hash, family_id: familyId,
        expires_at: expiresAt.toISOString(),
    });
    if (error) throw error;
}

async function revokeRefreshTokenById(db, id) {
    const { error } = await db.from('admin_refresh_tokens')
        .update({ revoked_at: new Date().toISOString() })
        .eq('id', id).is('revoked_at', null);
    if (error) throw error;
}

async function revokeRefreshFamily(db, familyId) {
    const { error } = await db.from('admin_refresh_tokens')
        .update({ revoked_at: new Date().toISOString() })
        .eq('family_id', familyId).is('revoked_at', null);
    if (error) throw error;
}

// ---------- audit ----------

async function insertAudit(db, { adminUsername, action, targetType, targetId, detail, ip }) {
    const { error } = await db.from('admin_audit_logs').insert({
        admin_username: adminUsername || 'system',
        action,
        target_type: targetType || null,
        target_id: targetId == null ? null : String(targetId),
        detail: detail == null ? null : JSON.stringify(detail),
        ip: ip || null,
    });
    if (error) throw error;   // 调用方决定是否吞错(登录审计吞,业务审计不吞)
}

async function listAudit(db, { action = '', page = 1, pageSize = 20 }) {
    const { limit, offset } = pageClause({ page, pageSize });
    const where = action ? ` WHERE action = ${esc(action)}` : '';
    const { data, error } = await db.raw(
        `SELECT id, admin_username, action, target_type, target_id, detail, ip, created_at
         FROM admin_audit_logs${where} ORDER BY created_at DESC LIMIT ${limit} OFFSET ${offset}`);
    if (error) throw error;
    parseJsonCols(data, ['detail']);
    return { items: data, has_more: data.length === limit };
}

// ---------- devices ----------

function deviceWhere({ query, status }) {
    const where = [];
    if (status) where.push(`status = ${esc(status)}`);
    if (query) {
        const like = String(query).replace(/[%_\\]/g, (m) => '\\' + m);
        where.push(`android_id LIKE ${esc('%' + like + '%')} ESCAPE '\\'`);
    }
    return where.length ? ' WHERE ' + where.join(' AND ') : '';
}

async function listDevices(db, { query = '', status = '', page = 1, pageSize = 20 }) {
    const { limit, offset } = pageClause({ page, pageSize });
    const cond = deviceWhere({ query, status });
    const { data: items, error } = await db.raw(
        `SELECT android_id, quota_balance, total_consumed, status, last_seen_at, created_at, updated_at
         FROM devices${cond} ORDER BY created_at DESC LIMIT ${limit} OFFSET ${offset}`);
    if (error) throw error;
    const { data: counted, error: cerr } = await db.raw(`SELECT COUNT(*) AS total FROM devices${cond}`);
    if (cerr) throw cerr;
    return { items, total: Number(counted?.[0]?.total ?? 0) };
}

async function getDevice(db, androidId) {
    const { data, error } = await db.from('devices')
        .select('android_id, quota_balance, total_consumed, status, attestation_cert IS NOT NULL AS attestation_verified, last_seen_at, created_at, updated_at')
        .eq('android_id', androidId).single();
    if (error && error.code !== 'NOT_FOUND') throw error;
    return data;   // 不存在时返回 null,由路由映射 404
}

async function listQuotaChanges(db, androidId, limit = 50) {
    const { data, error } = await db.from('quota_changes')
        .select('id, change_amount, reason, balance_after, tokens_used, model, metadata, created_at')
        .eq('android_id', androidId).order('created_at', { ascending: false }).limit(limit);
    if (error) throw error;
    return parseJsonCols(data, ['metadata']);
}

async function countActiveJwts(db, androidId) {
    const { data, error } = await db.raw(
        `SELECT COUNT(*) AS total FROM device_jwts
         WHERE android_id = ${esc(androidId)} AND revoked_at IS NULL AND expires_at > NOW()`);
    if (error) throw error;
    return Number(data?.[0]?.total ?? 0);
}

/** 乐观锁(规格 §9):expected 更新时间不匹配 → 返回 null,调用方映射 409 CONCURRENT_MODIFY */
async function updateDeviceQuota(db, androidId, newBalance, expectedUpdatedAt) {
    const { data, error } = await db.raw(
        `UPDATE devices SET quota_balance = ${esc(Number(newBalance))}, updated_at = NOW()
         WHERE android_id = ${esc(androidId)} AND updated_at = ${esc(expectedUpdatedAt)}
         RETURNING quota_balance, updated_at`);
    if (error) throw error;
    return data?.[0] || null;
}

async function updateDeviceStatus(db, androidId, status, expectedUpdatedAt) {
    const { data, error } = await db.raw(
        `UPDATE devices SET status = ${esc(status)}, updated_at = NOW()
         WHERE android_id = ${esc(androidId)} AND updated_at = ${esc(expectedUpdatedAt)}
         RETURNING status, updated_at`);
    if (error) throw error;
    return data?.[0] || null;
}

async function insertQuotaChange(db, { androidId, changeAmount, reason, balanceAfter, metadata }) {
    const { error } = await db.from('quota_changes').insert({
        android_id: androidId, change_amount: changeAmount, reason,
        balance_after: balanceAfter, metadata: metadata ? JSON.stringify(metadata) : null,
    });
    if (error) throw error;
}

/** 踢下线:撤销该设备全部未撤销 JWT,返回撤销数 */
async function revokeDeviceTokens(db, androidId) {
    const { data, error } = await db.from('device_jwts')
        .update({ revoked_at: new Date().toISOString() })
        .eq('android_id', androidId).is('revoked_at', null).select('jti');
    if (error) throw error;
    return (data || []).length;
}

// ---------- feedback(直查 PG,规格 §3.3) ----------

async function listFeedback(db, { status = '', kind = '', page = 1, pageSize = 20 }) {
    const { limit, offset } = pageClause({ page, pageSize });
    const where = [];
    if (status) where.push(`status = ${esc(status)}`);
    if (kind) where.push(`kind = ${esc(kind)}`);
    const cond = where.length ? ' WHERE ' + where.join(' AND ') : '';
    const { data: items, error } = await db.raw(
        `SELECT id, device_id, kind, category, title, app_version, platform, device_model, log_count, status, created_at
         FROM feedback_reports${cond} ORDER BY created_at DESC LIMIT ${limit} OFFSET ${offset}`);
    if (error) throw error;
    const { data: counted, error: cerr } = await db.raw(`SELECT COUNT(*) AS total FROM feedback_reports${cond}`);
    if (cerr) throw cerr;
    return { items, total: Number(counted?.[0]?.total ?? 0) };
}

async function getFeedback(db, id) {
    const { data, error } = await db.from('feedback_reports')
        .select('id, device_id, kind, category, title, description, steps, contact, app_version, platform, device_model, log_count, status, created_at')
        .eq('id', Number(id)).single();
    if (error && error.code !== 'NOT_FOUND') throw error;
    return data;
}

async function listFeedbackLogs(db, reportId) {
    const { data, error } = await db.from('feedback_logs')
        .select('seq, ts, level, category, message, stack_trace, tags')
        .eq('report_id', Number(reportId)).order('seq', { ascending: true }).limit(300);
    if (error) throw error;
    return parseJsonCols(data, ['tags']);
}

// ---------- overview(§6.1:全部聚合限制在 7 日窗口,规避控制面慢查询) ----------

async function overview(db) {
    const { data, error } = await db.raw(`
        SELECT
            (SELECT COUNT(*) FROM devices)                                           AS devices_total,
            (SELECT COUNT(*) FROM devices WHERE status = 'banned')                   AS devices_banned,
            (SELECT COUNT(*) FROM devices WHERE created_at >= date_trunc('day', NOW())) AS devices_today,
            (SELECT COALESCE(SUM(change_amount) FILTER (WHERE change_amount > 0), 0)
               FROM quota_changes WHERE created_at >= NOW() - INTERVAL '7 days')     AS granted_7d,
            (SELECT COALESCE(SUM(-change_amount) FILTER (WHERE change_amount < 0), 0)
               FROM quota_changes WHERE created_at >= NOW() - INTERVAL '7 days')     AS consumed_7d,
            (SELECT COUNT(*) FROM quota_changes
               WHERE reason = 'llm_call' AND created_at >= NOW() - INTERVAL '7 days') AS llm_calls_7d,
            (SELECT COUNT(*) FROM feedback_reports WHERE status = 'open')            AS feedback_open`);
    if (error) throw error;
    const row = data?.[0] || {};
    for (const k of Object.keys(row)) row[k] = Number(row[k] ?? 0);
    return row;
}

module.exports = {
    AUDIT_BEFORE_CHANGE, esc,
    getAdmin, recordPasswordFailure, recordTotpFailure, lockAdmin, clearAuthFailures,
    updateAdminPassword, setTotpSecret, enableTotp,
    replaceBackupCodes, listUnusedBackupCodes, consumeBackupCode,
    getRefreshTokenByHash, insertRefreshToken, revokeRefreshTokenById, revokeRefreshFamily,
    insertAudit, listAudit,
    listDevices, getDevice, listQuotaChanges, countActiveJwts,
    updateDeviceQuota, updateDeviceStatus, insertQuotaChange, revokeDeviceTokens,
    listFeedback, getFeedback, listFeedbackLogs,
    overview,
};
```

- [ ] **步骤 2:语法检查**

运行:`cd cloudfunctions/admin-console && node -e "require('./lib/repo'); console.log('ok')"`
预期:输出 `ok`(require 链到 common/db → tcb-admin,离线加载应成功;device-auth 的既有测试已证明该链可离线 require)。

- [ ] **步骤 3:Commit**

```bash
git add cloudfunctions/admin-console/lib/repo.js
git commit -m "feat(admin-console): repo.js SQL 集中(设备/反馈/审计/总览 + 乐观锁)"
```

---

### 任务 7:lib/auth.js(登录状态机)

**文件:**
- 创建:`cloudfunctions/admin-console/lib/auth.js`
- 测试:`cloudfunctions/admin-console/__tests__/auth-flow.test.js`

- [ ] **步骤 1:编写失败的测试(注入 FakeRepo + 真实 crypto 模块)**

`__tests__/auth-flow.test.js`:

```js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const crypto = require('crypto');

process.env.ADMIN_JWT_SECRET = 'test-secret-for-unit-tests-only';

const auth = require('../lib/auth');
const password = require('../lib/password');
const totp = require('../lib/totp');
const session = require('../lib/session');
const { totpAt } = totp;

function makeFakeRepo() {
    const state = { admins: new Map(), backups: [], refresh: [], audits: [] };
    let backupId = 1, refreshId = 1;
    return {
        state,
        async getAdmin(_db, u) { return state.admins.get(u) || null; },
        async recordPasswordFailure(_db, u) { const a = state.admins.get(u); a.failed_attempts += 1; return { attempts: a.failed_attempts }; },
        async recordTotpFailure(_db, u) { const a = state.admins.get(u); a.totp_failed_attempts += 1; return { attempts: a.totp_failed_attempts }; },
        async lockAdmin(_db, u, until) { state.admins.get(u).locked_until = until; },
        async clearAuthFailures(_db, u) { Object.assign(state.admins.get(u), { failed_attempts: 0, totp_failed_attempts: 0, locked_until: null }); },
        async updateAdminPassword(_db, u, h) { const a = state.admins.get(u); a.pass_hash = h; a.must_change_password = false; a.session_version += 1; return a.session_version; },
        async setTotpSecret(_db, u, s) { state.admins.get(u).totp_secret = s; },
        async enableTotp(_db, u) { const a = state.admins.get(u); a.totp_enabled = true; a.totp_failed_attempts = 0; a.must_change_password = false; },
        async replaceBackupCodes(_db, u, hashes) { state.backups = hashes.map((h) => ({ id: backupId++, admin_username: u, code_hash: h, used_at: null })); },
        async listUnusedBackupCodes(_db, u) { return state.backups.filter((b) => b.admin_username === u && !b.used_at); },
        async consumeBackupCode(_db, id) { const b = state.backups.find((x) => x.id === id); if (!b || b.used_at) return false; b.used_at = new Date(); return true; },
        async getRefreshTokenByHash(_db, h) { return state.refresh.find((r) => r.token_hash === h) || null; },
        async insertRefreshToken(_db, { username, hash, familyId, expiresAt }) { state.refresh.push({ id: refreshId++, admin_username: username, token_hash: hash, family_id: familyId, expires_at: expiresAt, revoked_at: null }); },
        async revokeRefreshTokenById(_db, id) { const r = state.refresh.find((x) => x.id === id); if (r) r.revoked_at = r.revoked_at || new Date(); },
        async revokeRefreshFamily(_db, f) { for (const r of state.refresh) if (r.family_id === f) r.revoked_at = r.revoked_at || new Date(); },
        async insertAudit(_db, entry) { state.audits.push(entry); },
    };
}

function makeDeps(repo) {
    return { db: null, repo, password, totp, session };
}

function seedAdmin(repo, overrides = {}) {
    const admin = {
        username: 'admin', pass_hash: password.hashPassword('Whimread-Admin-2026'),
        totp_secret: null, totp_enabled: false, must_change_password: true,
        session_version: 0, failed_attempts: 0, totp_failed_attempts: 0,
        locked_until: null, disabled: false, ...overrides,
    };
    repo.state.admins.set('admin', admin);
    return admin;
}

const expectError = (promise, status, code) =>
    assert.rejects(promise, (e) => e instanceof auth.AuthError && e.status === status && e.code === code);

test('登录:密码错 ×5 触发锁定,锁定期间 ACCOUNT_LOCKED', async () => {
    const repo = makeFakeRepo(); seedAdmin(repo);
    const deps = makeDeps(repo);
    const bad = { username: 'admin', password: 'nope-not-right-1', ip: '1.2.3.4' };
    for (let i = 0; i < 4; i++) await expectError(auth.attemptLogin(deps, bad), 401, 'LOGIN_FAILED');
    await expectError(auth.attemptLogin(deps, bad), 401, 'LOGIN_FAILED');   // 第 5 次,同时上锁
    assert.ok(repo.state.admins.get('admin').locked_until);
    await expectError(auth.attemptLogin(deps, { ...bad, password: 'Whimread-Admin-2026' }), 401, 'ACCOUNT_LOCKED');
    assert.ok(repo.state.audits.some((a) => a.action === 'lockout'));
});

test('首登:改密 → TOTP 绑定 → 换发正式会话', async () => {
    const repo = makeFakeRepo(); seedAdmin(repo);
    const deps = makeDeps(repo);
    const r1 = await auth.attemptLogin(deps, { username: 'admin', password: 'Whimread-Admin-2026', ip: '' });
    assert.equal(r1.next, 'change_password');
    await expectError(auth.changePassword(deps, { changeToken: r1.change_token, newPassword: 'short' }), 400, 'VALIDATION_FAILED');
    const r2 = await auth.changePassword(deps, { changeToken: r1.change_token, newPassword: 'Whimread-New-Pw-2026', ip: '' });
    assert.equal(r2.next, 'totp_setup');
    const setup = await auth.totpSetup(deps, { loginToken: r2.login_token });
    assert.equal(setup.backup_codes.length, 10);
    assert.match(setup.otpauth_url, /^otpauth:\/\/totp\/Whimread%3Aadmin\?secret=/);
    const code = totpAt(setup.secret_base32, Date.now());
    const sess = await auth.totpVerifySetup(deps, { loginToken: r2.login_token, code, ip: '' });
    assert.equal(sess.expires_in, session.ACCESS_TTL_SEC);
    const claims = session.verifyAccessToken(sess.access_token);
    assert.equal(claims.sub, 'admin');
    assert.ok(repo.state.admins.get('admin').totp_enabled);
});

test('正常登录:TOTP 码与备用码均可,备用码一次性', async () => {
    const repo = makeFakeRepo(); seedAdmin(repo, { must_change_password: false, totp_enabled: true, totp_secret: totp.generateSecret() });
    const deps = makeDeps(repo);
    const r = await auth.attemptLogin(deps, { username: 'admin', password: 'Whimread-Admin-2026', ip: '' });
    assert.equal(r.next, 'totp');
    const sess = await auth.totpLogin(deps, { loginToken: r.login_token, code: totpAt(repo.state.admins.get('admin').totp_secret, Date.now()), ip: '' });
    assert.ok(sess.refresh_token);

    const setupCodes = ['12345678', '23456789'];
    await repo.replaceBackupCodes(null, 'admin', setupCodes.map(password.hashBackupCode));
    const r2 = await auth.attemptLogin(deps, { username: 'admin', password: 'Whimread-Admin-2026', ip: '' });
    const sess2 = await auth.totpLogin(deps, { loginToken: r2.login_token, code: '12345678', ip: '' });
    assert.ok(sess2.access_token);
    await expectError(auth.totpLogin(deps, { loginToken: r2.login_token, code: '12345678', ip: '' }), 401, 'TOTP_INVALID'); // 已用
});

test('TOTP 错 ×5 独立锁定;refresh 轮换与复用检测撤 family', async () => {
    const repo = makeFakeRepo();
    seedAdmin(repo, { must_change_password: false, totp_enabled: true, totp_secret: totp.generateSecret() });
    const deps = makeDeps(repo);
    const r = await auth.attemptLogin(deps, { username: 'admin', password: 'Whimread-Admin-2026', ip: '' });
    for (let i = 0; i < 5; i++) await expectError(auth.totpLogin(deps, { loginToken: r.login_token, code: '000000', ip: '' }), 401, 'TOTP_INVALID');
    assert.ok(repo.state.admins.get('admin').locked_until);

    const first = await auth.issueSession(deps, 'admin');                                  // token A
    const sess = await auth.refresh(deps, { refreshToken: first.refresh_token, ip: '' });  // 轮换 → B
    assert.ok(sess.refresh_token);
    await expectError(auth.refresh(deps, { refreshToken: first.refresh_token, ip: '' }), 401, 'JWT_INVALID'); // A 重放 → 撤 family
    // family 内尚未用过的 B 也应已被连带撤销
    assert.ok(repo.state.refresh.every((x) => x.revoked_at));
});
```

- [ ] **步骤 2:运行测试验证失败**

运行:`cd cloudfunctions/admin-console && npm test`
预期:FAIL(`Cannot find module '../lib/auth'`)。

- [ ] **步骤 3:实现 lib/auth.js**

```js
/**
 * 登录状态机(规格 §5.3 三段式)+ 会话管理
 * deps = { db, repo, password, totp, session } —— repo 可注入 FakeRepo 供测试
 */

'use strict';
const crypto = require('crypto');

class AuthError extends Error {
    constructor(status, code, message) {
        super(message || code);
        this.status = status;
        this.code = code;
    }
}

const LOCK_POLICY = { maxPasswordAttempts: 5, maxTotpAttempts: 5, lockMinutes: 15 };

function lockedNow(admin) {
    return !!(admin?.locked_until && new Date(admin.locked_until) > new Date());
}

async function attemptLogin(deps, { username, password, ip }) {
    username = String(username || '').trim();
    const admin = await deps.repo.getAdmin(deps.db, username);
    const audit = (action, detail) => deps.repo.insertAudit(deps.db, {
        adminUsername: username || '?', action, targetType: 'self', targetId: username, detail, ip,
    }).catch(() => { /* 登录审计尽力而为 */ });

    if (admin?.disabled) {
        await audit('login_failed', { reason: 'ACCOUNT_DISABLED' });
        throw new AuthError(401, 'ACCOUNT_DISABLED');
    }
    if (lockedNow(admin)) throw new AuthError(401, 'ACCOUNT_LOCKED');

    const pwOk = !!admin && deps.password.verifyPassword(String(password || ''), admin.pass_hash);
    if (!pwOk) {
        if (admin) {
            const { attempts } = await deps.repo.recordPasswordFailure(deps.db, username);
            if (attempts >= LOCK_POLICY.maxPasswordAttempts) {
                await deps.repo.lockAdmin(deps.db, username,
                    new Date(Date.now() + LOCK_POLICY.lockMinutes * 60_000));
                await audit('lockout', { reason: 'password' });
            }
        }
        await audit('login_failed', { reason: 'password' });
        throw new AuthError(401, 'LOGIN_FAILED');   // 统一文案,不区分「无此用户/密码错」
    }

    await deps.repo.clearAuthFailures(deps.db, username);
    await audit('login');
    if (admin.must_change_password) {
        return { next: 'change_password', change_token: deps.session.signLoginToken(username, 'change_password') };
    }
    if (!admin.totp_enabled) {
        return { next: 'totp_setup', login_token: deps.session.signLoginToken(username, 'totp_setup') };
    }
    return { next: 'totp', login_token: deps.session.signLoginToken(username, 'totp') };
}

async function changePassword(deps, { changeToken, newPassword, ip }) {
    const claims = deps.session.verifyLoginToken(changeToken, 'change_password');
    const policy = deps.password.validatePasswordPolicy(String(newPassword || ''));
    if (policy) throw new AuthError(400, 'VALIDATION_FAILED', `新密码不合规:${policy}`);
    await deps.repo.updateAdminPassword(deps.db, claims.sub, deps.password.hashPassword(newPassword));
    await deps.repo.insertAudit(deps.db, { adminUsername: claims.sub, action: 'change_password', targetType: 'self', targetId: claims.sub, ip });
    const admin = await deps.repo.getAdmin(deps.db, claims.sub);
    if (!admin.totp_enabled) {
        return { next: 'totp_setup', login_token: deps.session.signLoginToken(claims.sub, 'totp_setup') };
    }
    return { next: 'totp', login_token: deps.session.signLoginToken(claims.sub, 'totp') };
}

async function totpSetup(deps, { loginToken }) {
    const claims = deps.session.verifyLoginToken(loginToken, 'totp_setup');
    const secret = deps.totp.generateSecret();
    const codes = deps.password.generateBackupCodes(10);
    await deps.repo.setTotpSecret(deps.db, claims.sub, secret);
    await deps.repo.replaceBackupCodes(deps.db, claims.sub, codes.map((c) => deps.password.hashBackupCode(c)));
    await deps.repo.insertAudit(deps.db, { adminUsername: claims.sub, action: 'totp_setup', targetType: 'self', targetId: claims.sub });
    return { secret_base32: secret, otpauth_url: deps.totp.otpauthUrl(secret, claims.sub), backup_codes: codes };
}

/** 失败计数 + 超限锁定(密码/TOTP 各自独立) */
async function recordAuthFailureAndMaybeLock(deps, admin, kind, ip) {
    const { attempts } = kind === 'totp'
        ? await deps.repo.recordTotpFailure(deps.db, admin.username)
        : await deps.repo.recordPasswordFailure(deps.db, admin.username);
    const max = kind === 'totp' ? LOCK_POLICY.maxTotpAttempts : LOCK_POLICY.maxPasswordAttempts;
    if (attempts >= max) {
        await deps.repo.lockAdmin(deps.db, admin.username, new Date(Date.now() + LOCK_POLICY.lockMinutes * 60_000));
        await deps.repo.insertAudit(deps.db, { adminUsername: admin.username, action: 'lockout', targetType: 'self', targetId: admin.username, detail: { reason: kind }, ip });
    }
}

async function totpVerifySetup(deps, { loginToken, code, ip }) {
    const claims = deps.session.verifyLoginToken(loginToken, 'totp_setup');
    const admin = await deps.repo.getAdmin(deps.db, claims.sub);
    if (!admin?.totp_secret) throw new AuthError(400, 'TOTP_REQUIRED', '请先调用 totp/setup');
    if (lockedNow(admin)) throw new AuthError(401, 'ACCOUNT_LOCKED');
    if (!deps.totp.verifyTotp(admin.totp_secret, code)) {
        await recordAuthFailureAndMaybeLock(deps, admin, 'totp', ip);
        throw new AuthError(401, 'TOTP_INVALID');
    }
    await deps.repo.enableTotp(deps.db, claims.sub);
    await deps.repo.clearAuthFailures(deps.db, claims.sub);
    return await issueSession(deps, claims.sub);
}

async function totpLogin(deps, { loginToken, code, ip }) {
    const claims = deps.session.verifyLoginToken(loginToken, 'totp');
    const admin = await deps.repo.getAdmin(deps.db, claims.sub);
    if (!admin || admin.disabled) throw new AuthError(401, 'ACCOUNT_DISABLED');
    if (lockedNow(admin)) throw new AuthError(401, 'ACCOUNT_LOCKED');

    const c = String(code || '').replace(/\s+/g, '');
    if (/^\d{8}$/.test(c)) {
        // 备用码(8 位):逐条 scrypt 校验,命中即消费
        const rows = await deps.repo.listUnusedBackupCodes(deps.db, claims.sub);
        for (const row of rows) {
            if (deps.password.verifyBackupCode(c, row.code_hash)) {
                const consumed = await deps.repo.consumeBackupCode(deps.db, row.id);
                if (consumed) {
                    await deps.repo.clearAuthFailures(deps.db, claims.sub);
                    await deps.repo.insertAudit(deps.db, { adminUsername: claims.sub, action: 'login', targetType: 'self', targetId: claims.sub, detail: { via: 'backup_code' }, ip });
                    return await issueSession(deps, claims.sub);
                }
            }
        }
        throw new AuthError(401, 'TOTP_INVALID');
    }
    if (!admin.totp_secret || !deps.totp.verifyTotp(admin.totp_secret, c)) {
        await recordAuthFailureAndMaybeLock(deps, admin, 'totp', ip);
        throw new AuthError(401, 'TOTP_INVALID');
    }
    await deps.repo.clearAuthFailures(deps.db, claims.sub);
    return await issueSession(deps, claims.sub);
}

async function issueSession(deps, username) {
    const admin = await deps.repo.getAdmin(deps.db, username);
    if (!admin) throw new AuthError(401, 'ACCOUNT_DISABLED');
    const { raw, hash } = deps.session.newRefreshToken();
    await deps.repo.insertRefreshToken(deps.db, {
        username, hash, familyId: crypto.randomUUID(),
        expiresAt: new Date(Date.now() + deps.session.REFRESH_TTL_SEC * 1000),
    });
    return {
        access_token: deps.session.signAccessToken(username, admin.session_version),
        expires_in: deps.session.ACCESS_TTL_SEC,
        refresh_token: raw,
    };
}

async function refresh(deps, { refreshToken, ip }) {
    const hash = deps.session.hashToken(String(refreshToken || ''));
    const row = await deps.repo.getRefreshTokenByHash(deps.db, hash);
    if (!row) throw new AuthError(401, 'JWT_INVALID', 'refresh token 无效');
    if (row.revoked_at) {
        // 复用检测(规格 §5.2):旧 token 二次使用 → 撤销整个 family
        await deps.repo.revokeRefreshFamily(deps.db, row.family_id);
        await deps.repo.insertAudit(deps.db, { adminUsername: row.admin_username, action: 'revoke_tokens', targetType: 'self', targetId: row.admin_username, detail: { reason: 'refresh_reuse', family_id: row.family_id }, ip });
        throw new AuthError(401, 'JWT_INVALID', '检测到 refresh token 重放,会话已全部失效');
    }
    if (new Date(row.expires_at) < new Date()) throw new AuthError(401, 'JWT_EXPIRED');
    const admin = await deps.repo.getAdmin(deps.db, row.admin_username);
    if (!admin || admin.disabled) throw new AuthError(401, 'ACCOUNT_DISABLED');
    await deps.repo.revokeRefreshTokenById(deps.db, row.id);
    // 同 family 续签
    const { raw, hash: newHash } = deps.session.newRefreshToken();
    await deps.repo.insertRefreshToken(deps.db, {
        username: row.admin_username, hash: newHash, familyId: row.family_id,
        expiresAt: new Date(Date.now() + deps.session.REFRESH_TTL_SEC * 1000),
    });
    return {
        access_token: deps.session.signAccessToken(row.admin_username, admin.session_version),
        expires_in: deps.session.ACCESS_TTL_SEC,
        refresh_token: raw,
    };
}

async function logout(deps, { refreshToken, ip }) {
    const row = await deps.repo.getRefreshTokenByHash(deps.db, deps.session.hashToken(String(refreshToken || '')));
    if (row) {
        await deps.repo.revokeRefreshTokenById(deps.db, row.id);
        await deps.repo.insertAudit(deps.db, { adminUsername: row.admin_username, action: 'logout', targetType: 'self', targetId: row.admin_username, ip });
    }
    return { ok: true };
}

/** 业务路由守卫:verify + 回库比对 session_version/disabled(规格 §5.2) */
async function requireAdmin(deps, headers) {
    const header = headers?.authorization || headers?.Authorization || '';
    if (!header.startsWith('Bearer ')) throw new AuthError(401, 'NO_BEARER');
    const claims = deps.session.verifyAccessToken(header.slice(7));
    const admin = await deps.repo.getAdmin(deps.db, claims.sub);
    if (!admin || admin.disabled) throw new AuthError(401, 'ACCOUNT_DISABLED');
    if (Number(admin.session_version) !== Number(claims.ver)) {
        throw new AuthError(401, 'JWT_INVALID', '会话已失效,请重新登录');
    }
    return { username: admin.username };
}

module.exports = { AuthError, attemptLogin, changePassword, totpSetup, totpVerifySetup,
                   totpLogin, issueSession, refresh, logout, requireAdmin, LOCK_POLICY };
```

- [ ] **步骤 4:运行测试验证通过**

运行:`cd cloudfunctions/admin-console && npm test`
预期:PASS(全量;scrypt 多次调用总耗时约 2-4s 属正常)。

- [ ] **步骤 5:Commit**

```bash
git add cloudfunctions/admin-console/lib/auth.js cloudfunctions/admin-console/__tests__/auth-flow.test.js
git commit -m "feat(admin-console): 三段式登录状态机(锁定/TOTP 绑定/备用码/refresh 轮换)"
```

---

### 任务 8:index.js 路由骨架 + CORS 白名单 + 认证路由接线

**文件:**
- 创建:`cloudfunctions/admin-console/lib/http.js`
- 创建:`cloudfunctions/admin-console/index.js`
- 测试:`cloudfunctions/admin-console/__tests__/http.test.js`

- [ ] **步骤 1:编写失败的测试**

`__tests__/http.test.js`:

```js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { normalizePath } = require('../lib/http');

test('normalizePath:兼容网关透传与否(计划 §0.1)', () => {
    assert.equal(normalizePath('/admin/api/auth/login'), '/auth/login');
    assert.equal(normalizePath('/admin/auth/login'), '/auth/login');
    assert.equal(normalizePath('/auth/login/'), '/auth/login');
    assert.equal(normalizePath('/auth/login'), '/auth/login');
    assert.equal(normalizePath('/admin'), '/');
    assert.equal(normalizePath(''), '/');
});
```

- [ ] **步骤 2:运行测试验证失败**

运行:`cd cloudfunctions/admin-console && npm test`
预期:FAIL(`Cannot find module '../lib/http'`)。

- [ ] **步骤 3:实现 lib/http.js**

```js
/**
 * 响应工厂 + CORS 白名单(规格 §7)
 * 不复用 common/errors.js 的 ok/err:它们硬编码 ACAO:*,对管理台过宽。
 * 无 cookie → 无需 credentials;Origin 不在白名单则不回 ACAO(浏览器侧即被拦),
 * 对 curl/CLI 无 Origin 的请求照常响应(管理台是「人 + 偶发脚本」,不做 UA 限制)。
 */

'use strict';

function allowedOrigins() {
    return (process.env.ADMIN_WEB_ORIGINS || '').split(',').map((s) => s.trim()).filter(Boolean);
}

function baseHeaders(event) {
    const h = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', Vary: 'Origin' };
    const origin = event?.headers?.origin || event?.headers?.Origin;
    if (origin && allowedOrigins().includes(origin)) {
        h['Access-Control-Allow-Origin'] = origin;
        h['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS';
        h['Access-Control-Allow-Headers'] = 'Content-Type, Authorization';
    }
    return h;
}

function ok(data, event, statusCode = 200) {
    return { statusCode, headers: baseHeaders(event), body: JSON.stringify(data) };
}

function err(statusCode, code, message, event) {
    const body = { code, ...(message ? { message } : {}) };
    return { statusCode, headers: baseHeaders(event), body: JSON.stringify(body) };
}

function handleOptions(event) {
    return { statusCode: 204, headers: baseHeaders(event), body: '' };
}

/**
 * 兼容两种网关形态(计划 §0.1):
 *   /admin/api/auth/login → /auth/login(触发路径 /admin/api,透传)
 *   /admin/auth/login     → /auth/login(未透传或触发路径 /admin)
 */
function normalizePath(rawPath) {
    let p = String(rawPath || '').split('?')[0].replace(/\/+$/, '');
    p = p.replace(/^\/admin(\/api)?(?=\/|$)/, '');
    return p || '/';
}

function getIp(event) {
    const xf = event?.headers?.['x-forwarded-for'] || event?.headers?.['X-Forwarded-For'];
    if (xf) return String(xf).split(',')[0].trim();
    return event?.headers?.['x-real-ip'] || event?.headers?.['X-Real-Ip'] || '';
}

function parseBody(event) {
    if (!event?.body) return {};
    if (typeof event.body === 'object') return event.body;
    try { return JSON.parse(event.body); } catch { return {}; }
}

module.exports = { ok, err, handleOptions, normalizePath, getIp, parseBody, allowedOrigins };
```

- [ ] **步骤 4:实现 index.js(认证路由接线;业务路由任务 9-11 接入)**

```js
/**
 * Whimread admin-console 云函数(管理后台 API,规格 §5.3/§6.1)
 *
 * 网关触发路径:/admin/api → 本函数。normalizePath 兼容透传与否。
 * 认证路由(无需 access JWT):login / change-password / totp×3 / refresh / logout
 * 业务路由(需 access JWT):overview / devices / feedback / audit(任务 9-11)
 */

'use strict';
const { getDb } = require('./common/db');
const logger = require('./common/logger');
const repo = require('./lib/repo');
const password = require('./lib/password');
const totp = require('./lib/totp');
const session = require('./lib/session');
const auth = require('./lib/auth');
const http = require('./lib/http');

const db = getDb(null);
const deps = { db, repo, password, totp, session };
exports.__setDeps = (patch) => Object.assign(deps, patch);   // 仅供测试注入

exports.main = async (event, context) => {
    if (event.httpMethod === 'OPTIONS') return http.handleOptions(event);
    const method = event.httpMethod || 'GET';
    const path = http.normalizePath(event.path);
    const body = http.parseBody(event);
    const ip = http.getIp(event);
    try {
        if (method === 'POST' && path === '/auth/login') {
            return http.ok(await auth.attemptLogin(deps, { username: body.username, password: body.password, ip }), event);
        }
        if (method === 'POST' && path === '/auth/change-password') {
            return http.ok(await auth.changePassword(deps, { changeToken: body.change_token, newPassword: body.new_password, ip }), event);
        }
        if (method === 'POST' && path === '/auth/totp/setup') {
            return http.ok(await auth.totpSetup(deps, { loginToken: body.login_token }), event);
        }
        if (method === 'POST' && path === '/auth/totp/verify-setup') {
            return http.ok(await auth.totpVerifySetup(deps, { loginToken: body.login_token, code: body.code, ip }), event);
        }
        if (method === 'POST' && path === '/auth/totp') {
            return http.ok(await auth.totpLogin(deps, { loginToken: body.login_token, code: body.code, ip }), event);
        }
        if (method === 'POST' && path === '/auth/refresh') {
            return http.ok(await auth.refresh(deps, { refreshToken: body.refresh_token, ip }), event);
        }
        if (method === 'POST' && path === '/auth/logout') {
            return http.ok(await auth.logout(deps, { refreshToken: body.refresh_token, ip }), event);
        }

        // ---- 以下为业务路由,统一要求 access JWT(任务 9-11 接入) ----
        const admin = await auth.requireAdmin(deps, event.headers);
        // const ctx = { admin, ip };   // 任务 9 起使用

        return http.err(404, 'NOT_FOUND', `Unknown route: ${method} ${path}`, event);
    } catch (e) {
        if (e instanceof auth.AuthError) return http.err(e.status, e.code, e.message, event);
        logger.error(context, `admin-console uncaught: ${e.message}`, { path });
        return http.err(500, 'INTERNAL', 'Internal error', event);
    }
};
```

- [ ] **步骤 5:路由层冒烟测试(追加到 http.test.js)**

```js
test('main:业务路由无 token → 401 NO_BEARER;未知路由 → 404', async () => {
    process.env.ADMIN_JWT_SECRET = 'test-secret-for-unit-tests-only';
    const fn = require('../index');
    const r1 = await fn.main({ httpMethod: 'GET', path: '/admin/api/overview', headers: {} }, {});
    assert.equal(r1.statusCode, 401);
    assert.ok(JSON.parse(r1.body).code === 'NO_BEARER');
    const r2 = await fn.main({ httpMethod: 'GET', path: '/admin/api/nope', headers: {} }, {});
    assert.equal(r2.statusCode, 401);   // 守卫先于 404
});
```

注意:`require('../index')` 会加载 `common/db → common/tcb-admin`,离线 require 应成功(device-auth 既有测试已验证该链路);若 tcb-admin 在 require 时读 env 抛错,在测试文件顶部补必要的空 env stub(不要提交真实凭据)。

- [ ] **步骤 6:运行测试验证通过**

运行:`cd cloudfunctions/admin-console && npm test`
预期:PASS(全量)。

- [ ] **步骤 7:Commit**

```bash
git add cloudfunctions/admin-console/lib/http.js cloudfunctions/admin-console/index.js cloudfunctions/admin-console/__tests__/http.test.js
git commit -m "feat(admin-console): 路由骨架 + CORS 白名单 + 三段式认证路由"
```

---

# Phase 2:管理 API 路由(任务 9–11)

> 三个任务都往 `index.js` 追加路由、往 `__tests__/routes.test.js` 追加用例。统一约定:路由层只做「解析 → 校验 → repo 调用 → 响应映射」,业务规则在 repo/auth;写操作经 `audited()` helper(先审计后变更或反之,由 `repo.AUDIT_BEFORE_CHANGE` 决定,见任务 1 步骤 4)。

### 任务 9:overview + audit 路由

**文件:**
- 修改:`cloudfunctions/admin-console/index.js`
- 测试:`cloudfunctions/admin-console/__tests__/routes.test.js`(新建)

- [ ] **步骤 1:编写失败的测试**

`__tests__/routes.test.js`:

```js
'use strict';
const test = require('node:test');
const assert = require('node:assert');

process.env.ADMIN_JWT_SECRET = 'test-secret-for-unit-tests-only';

const session = require('../lib/session');

/** 带合法 access JWT 的假 event(requireAdmin 可过);path 里的 query 解析成 queryStringParameters */
function authedEvent(method, pathWithPrefix, extra = {}) {
    const token = session.signAccessToken('admin', 0);
    const [path, search = ''] = pathWithPrefix.split('?');
    return {
        httpMethod: method,
        path,
        headers: { authorization: `Bearer ${token}` },
        ...(search ? { queryStringParameters: Object.fromEntries(new URLSearchParams(search)) } : {}),
        ...extra,
    };
}

/** 注入只有本次用例所需方法的 fake repo */
function fakeRepo(methods) {
    return {
        AUDIT_BEFORE_CHANGE: true,
        async getAdmin(_db, u) { return { username: u, session_version: 0, disabled: false }; },
        ...methods,
    };
}

test('GET /overview 与 GET /audit', async () => {
    const fn = require('../index');
    const calls = [];
    fn.__setDeps({ repo: fakeRepo({
        async overview() { calls.push('overview'); return { devices_total: 7 }; },
        async listAudit(_db, q) { calls.push(['audit', q.action, q.page]); return { items: [{ id: 1, action: 'login' }], has_more: false }; },
    }) });
    const r1 = await fn.main(authedEvent('GET', '/admin/api/overview'), {});
    assert.equal(r1.statusCode, 200);
    assert.equal(JSON.parse(r1.body).devices_total, 7);
    const r2 = await fn.main(authedEvent('GET', '/admin/api/audit?action=login&page=2'), {});
    assert.equal(r2.statusCode, 200);
    assert.equal(JSON.parse(r2.body).items.length, 1);
    assert.deepEqual(calls, ['overview', ['audit', 'login', '2']]);
});
```

- [ ] **步骤 2:运行测试验证失败**

运行:`cd cloudfunctions/admin-console && npm test`
预期:routes.test.js 新用例 FAIL(路由 404)。

- [ ] **步骤 3:接线 index.js**

把任务 8 遗留的「业务路由占位段」**整体替换**(从 `// ---- 以下为业务路由…` 注释行到 `return http.err(404, …)`,含其中旧的 `const admin = …` 行,避免重复声明):

```js
        // ---- 以下为业务路由,统一要求 access JWT ----
        const admin = await auth.requireAdmin(deps, event.headers);
        const ctx = { admin, ip };

        if (method === 'GET' && path === '/overview') {
            return http.ok(await deps.repo.overview(deps.db), event);
        }
        if (method === 'GET' && path === '/audit') {
            const q = event.queryStringParameters || {};
            return http.ok(await deps.repo.listAudit(deps.db, {
                action: q.action || '', page: q.page, pageSize: q.page_size,
            }), event);
        }

        return http.err(404, 'NOT_FOUND', `Unknown route: ${method} ${path}`, event);
```

- [ ] **步骤 4:运行测试验证通过**

运行:`cd cloudfunctions/admin-console && npm test`
预期:PASS(全量)。

- [ ] **步骤 5:Commit**

```bash
git add cloudfunctions/admin-console/index.js cloudfunctions/admin-console/__tests__/routes.test.js
git commit -m "feat(admin-console): overview 与 audit 只读路由"
```

---

### 任务 10:devices 路由(列表/详情/额度/封禁/踢下线,乐观锁 + 审计)

**文件:**
- 修改:`cloudfunctions/admin-console/index.js`
- 测试:`cloudfunctions/admin-console/__tests__/routes.test.js`

- [ ] **步骤 1:编写失败的测试**

追加到 routes.test.js:

```js
test('POST /devices/:id/quota:grant 成功、reset 缺 note 400、乐观锁 409', async () => {
    const fn = require('../index');
    const audits = [], changes = [];
    let stale = false;
    fn.__setDeps({ repo: fakeRepo({
        async getDevice(_db, id) {
            return id === 'dev-unknown' ? null
                : { android_id: id, quota_balance: 100, status: 'active', updated_at: '2026-09-09T00:00:00Z' };
        },
        async updateDeviceQuota(_db, id, newBalance, expected) {
            if (stale || expected !== '2026-09-09T00:00:00Z') return null;
            return { quota_balance: newBalance, updated_at: '2026-09-09T01:00:00Z' };
        },
        async insertQuotaChange(_db, entry) { changes.push(entry); },
        async insertAudit(_db, entry) { audits.push(entry); },
    }) });
    const grant = await fn.main(authedEvent('POST', '/admin/api/devices/dev-1/quota', {
        body: JSON.stringify({ action: 'grant', amount: 50, note: '补偿', expected_updated_at: '2026-09-09T00:00:00Z' }),
    }), {});
    assert.equal(grant.statusCode, 200);
    assert.equal(JSON.parse(grant.body).quota_balance, 150);
    assert.equal(changes[0].reason, 'manual_grant');
    assert.equal(changes[0].change_amount, 50);
    assert.equal(audits[0].action, 'quota_grant');

    const noNote = await fn.main(authedEvent('POST', '/admin/api/devices/dev-1/quota', {
        body: JSON.stringify({ action: 'reset', expected_updated_at: '2026-09-09T00:00:00Z' }),
    }), {});
    assert.equal(noNote.statusCode, 400);          // reset 必须带 note(§8 交互红线)

    stale = true;
    const conflict = await fn.main(authedEvent('POST', '/admin/api/devices/dev-1/quota', {
        body: JSON.stringify({ action: 'grant', amount: 1, expected_updated_at: '2026-09-09T00:00:00Z' }),
    }), {});
    assert.equal(conflict.statusCode, 409);
    assert.equal(JSON.parse(conflict.body).code, 'CONCURRENT_MODIFY');

    const missing = await fn.main(authedEvent('GET', '/admin/api/devices/dev-unknown'), {});
    assert.equal(missing.statusCode, 404);
});

test('POST /devices/:id/status 与 /revoke-tokens:审计动作正确', async () => {
    const fn = require('../index');
    const audits = [];
    fn.__setDeps({ repo: fakeRepo({
        async getDevice(_db, id) { return { android_id: id, status: 'active', updated_at: 'u1' }; },
        async updateDeviceStatus(_db, id, status) { return { status, updated_at: 'u2' }; },
        async revokeDeviceTokens(_db, id) { return 3; },
        async insertAudit(_db, e) { audits.push(e); },
    }) });
    const ban = await fn.main(authedEvent('POST', '/admin/api/devices/dev-1/status', {
        body: JSON.stringify({ status: 'banned', note: '滥用', expected_updated_at: 'u1' }),
    }), {});
    assert.equal(ban.statusCode, 200);
    assert.equal(audits[0].action, 'device_ban');
    const rv = await fn.main(authedEvent('POST', '/admin/api/devices/dev-1/revoke-tokens', {
        body: JSON.stringify({ note: '踢下线' }),
    }), {});
    assert.equal(JSON.parse(rv.body).revoked, 3);
    assert.equal(audits[1].action, 'revoke_tokens');
});
```

- [ ] **步骤 2:运行测试验证失败**

运行:`cd cloudfunctions/admin-console && npm test`
预期:新用例 FAIL(404)。

- [ ] **步骤 3:接线 index.js(audited helper + devices 路由)**

在 index.js 顶部 helper 区加:

```js
/** 写操作统一审计(经 deps,测试可注入)。AUDIT_BEFORE_CHANGE=true(探针证伪多语句事务)→ 先审计后变更。 */
async function audited(ctx, action, targetType, targetId, detail, mutation) {
    if (deps.repo.AUDIT_BEFORE_CHANGE) {
        await deps.repo.insertAudit(deps.db, { adminUsername: ctx.admin.username, action, targetType, targetId, detail, ip: ctx.ip });
        return await mutation();
    }
    const result = await mutation();
    await deps.repo.insertAudit(deps.db, { adminUsername: ctx.admin.username, action, targetType, targetId, detail, ip: ctx.ip });
    return result;
}
```

在 `/audit` 路由之后、`404` 之前插入:

```js
        const dm = path.match(/^\/devices\/([^/]+)(\/(quota|status|revoke-tokens))?$/);
        if (dm) {
            const androidId = decodeURIComponent(dm[1]);
            if (method === 'GET') {
                const device = await deps.repo.getDevice(deps.db, androidId);
                if (!device) return http.err(404, ErrorCodes.DEVICE_NOT_FOUND, 'Device not found', event);
                const [quotaChanges, activeJwts] = await Promise.all([
                    deps.repo.listQuotaChanges(deps.db, androidId, 50),
                    deps.repo.countActiveJwts(deps.db, androidId),
                ]);
                return http.ok({ device, quota_changes: quotaChanges, active_jwts: activeJwts }, event);
            }
            if (method === 'POST' && dm[3] === 'quota') {
                const { action, amount, note, expected_updated_at } = body;
                if (!['grant', 'reset'].includes(action)) {
                    return http.err(400, 'VALIDATION_FAILED', 'action must be grant|reset', event);
                }
                if (action === 'grant' && (!Number.isInteger(amount) || amount <= 0 || amount > 1_000_000)) {
                    return http.err(400, 'VALIDATION_FAILED', 'amount must be positive integer', event);
                }
                if (action === 'reset' && !(note || '').trim()) {
                    return http.err(400, 'VALIDATION_FAILED', 'reset requires note', event);
                }
                if (!expected_updated_at) {
                    return http.err(400, 'VALIDATION_FAILED', 'expected_updated_at required(乐观锁)', event);
                }
                const device = await deps.repo.getDevice(deps.db, androidId);
                if (!device) return http.err(404, ErrorCodes.DEVICE_NOT_FOUND, 'Device not found', event);
                const newBalance = action === 'grant' ? device.quota_balance + amount : 0;
                const changeAmount = action === 'grant' ? amount : -device.quota_balance;
                const row = await audited(ctx, action === 'grant' ? 'quota_grant' : 'quota_reset',
                    'device', androidId,
                    { note: note || null, amount: action === 'grant' ? amount : -device.quota_balance, before: device.quota_balance, after: newBalance },
                    () => deps.repo.updateDeviceQuota(deps.db, androidId, newBalance, expected_updated_at));
                if (!row) return http.err(409, 'CONCURRENT_MODIFY', '设备信息已变更,请刷新后重试', event);
                await deps.repo.insertQuotaChange(deps.db, { androidId, changeAmount, reason: action === 'grant' ? 'manual_grant' : 'manual_reset', balanceAfter: row.quota_balance });
                return http.ok({ ok: true, quota_balance: row.quota_balance, updated_at: row.updated_at }, event);
            }
            if (method === 'POST' && dm[3] === 'status') {
                const { status, note, expected_updated_at } = body;
                if (!['banned', 'active'].includes(status)) {
                    return http.err(400, 'VALIDATION_FAILED', 'status must be banned|active', event);
                }
                if (!(note || '').trim() || !expected_updated_at) {
                    return http.err(400, 'VALIDATION_FAILED', 'status change requires note + expected_updated_at', event);
                }
                const row = await audited(ctx, status === 'banned' ? 'device_ban' : 'device_unban',
                    'device', androidId, { note, to: status },
                    () => deps.repo.updateDeviceStatus(deps.db, androidId, status, expected_updated_at));
                if (!row) return http.err(409, 'CONCURRENT_MODIFY', '设备信息已变更,请刷新后重试', event);
                return http.ok({ ok: true, status: row.status, updated_at: row.updated_at }, event);
            }
            if (method === 'POST' && dm[3] === 'revoke-tokens') {
                if (!(body.note || '').trim()) {
                    return http.err(400, 'VALIDATION_FAILED', 'revoke-tokens requires note', event);
                }
                const revoked = await audited(ctx, 'revoke_tokens', 'device', androidId, { note: body.note },
                    () => deps.repo.revokeDeviceTokens(deps.db, androidId));
                return http.ok({ ok: true, revoked }, event);
            }
        }

        if (method === 'GET' && path === '/devices') {
            const q = event.queryStringParameters || {};
            return http.ok(await deps.repo.listDevices(deps.db, {
                query: q.query || '', status: q.status || '', page: q.page, pageSize: q.page_size,
            }), event);
        }
```

并在 index.js 头部 require 区补:

```js
const { ErrorCodes } = require('./common/errors');
```

- [ ] **步骤 4:运行测试验证通过**

运行:`cd cloudfunctions/admin-console && npm test`
预期:PASS(全量)。

- [ ] **步骤 5:Commit**

```bash
git add cloudfunctions/admin-console/index.js cloudfunctions/admin-console/__tests__/routes.test.js
git commit -m "feat(admin-console): 设备管理路由(额度/封禁/踢下线,乐观锁+审计)"
```

---

### 任务 11:feedback 路由(只读,V1 不做状态流转)

**文件:**
- 修改:`cloudfunctions/admin-console/index.js`
- 测试:`cloudfunctions/admin-console/__tests__/routes.test.js`

范围说明:规格 §6.1 的 V1 API 表只有 `GET /feedback` 与 `GET /feedback/:id`——triaged/closed 状态流转**不在 V1**(§2.1「列表/详情/日志查看」),前端只展示状态徽标,YAGNI。

- [ ] **步骤 1:编写失败的测试**

```js
test('GET /feedback 列表与详情(含日志)', async () => {
    const fn = require('../index');
    fn.__setDeps({ repo: fakeRepo({
        async listFeedback(_db, q) { return { items: [{ id: 1, title: '崩溃', status: 'open' }], total: 1, query: q.status }; },
        async getFeedback(_db, id) { return id === 1 ? { id: 1, title: '崩溃', description: '闪退' } : null; },
        async listFeedbackLogs(_db, id) { return [{ seq: 0, level: 'error', message: 'boom' }]; },
    }) });
    const list = await fn.main(authedEvent('GET', '/admin/api/feedback?status=open'), {});
    assert.equal(list.statusCode, 200);
    assert.equal(JSON.parse(list.body).total, 1);
    const detail = await fn.main(authedEvent('GET', '/admin/api/feedback/1'), {});
    assert.equal(JSON.parse(detail.body).logs.length, 1);
    const none = await fn.main(authedEvent('GET', '/admin/api/feedback/99'), {});
    assert.equal(none.statusCode, 404);
});
```

- [ ] **步骤 2:运行测试验证失败**

运行:`cd cloudfunctions/admin-console && npm test`
预期:新用例 FAIL(404)。

- [ ] **步骤 3:接线 index.js**

插入在 `/devices` 列表路由之后:

```js
        if (method === 'GET' && path === '/feedback') {
            const q = event.queryStringParameters || {};
            return http.ok(await deps.repo.listFeedback(deps.db, {
                status: q.status || '', kind: q.kind || '', page: q.page, pageSize: q.page_size,
            }), event);
        }
        const fm = path.match(/^\/feedback\/(\d+)$/);
        if (fm && method === 'GET') {
            const report = await deps.repo.getFeedback(deps.db, fm[1]);
            if (!report) return http.err(404, 'NOT_FOUND', '反馈不存在', event);
            const logs = await deps.repo.listFeedbackLogs(deps.db, fm[1]);
            return http.ok({ report, logs }, event);
        }
```

- [ ] **步骤 4:运行测试验证通过**

运行:`cd cloudfunctions/admin-console && npm test`
预期:PASS(全量)。

- [ ] **步骤 5:Commit**

```bash
git add cloudfunctions/admin-console/index.js cloudfunctions/admin-console/__tests__/routes.test.js
git commit -m "feat(admin-console): 反馈工单只读路由(列表/详情/日志)"
```

---

# Phase 3:Star 兑换补齐 + 客户端修复(任务 12–13)

> **错误码对齐(对规格 §6.2 的命名修正)**:客户端 `mapRedeemDioError`(device_auth_service.dart:334)已映射 `NOT_STARRED / ALREADY_REDEEMED / INVALID_GITHUB_LOGIN / STAR_REDEEM_RATE_LIMITED / GITHUB_CHECK_FAILED`,本计划让服务端**发出与客户端完全一致的码**(规格写的 `GITHUB_VERIFY_FAILED` 改为 `GITHUB_CHECK_FAILED`,避免改两处)。

### 任务 12:device-auth `POST /api/v1/devices/star/redeem`

**文件:**
- 创建:`cloudfunctions/device-auth/lib/github.js`
- 修改:`cloudfunctions/device-auth/index.js`(路由 + `handleRedeem`)
- 测试:`cloudfunctions/device-auth/__tests__/redeem.test.js`

- [ ] **步骤 1:编写失败的测试**

`__tests__/redeem.test.js`:

```js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { checkStarred, isValidGithubLogin, rateLimitAllow } = require('../lib/github');

test('isValidGithubLogin:GitHub 用户名规则', () => {
    assert.equal(isValidGithubLogin('octocat'), true);
    assert.equal(isValidGithubLogin('a-b-c-99'), true);
    assert.equal(isValidGithubLogin('-lead'), false);      // 不能连字符开头
    assert.equal(isValidGithubLogin('a--b'), false);       // 不能连续连字符
    assert.equal(isValidGithubLogin("x'; DROP TABLE users"), false);
    assert.equal(isValidGithubLogin('x'.repeat(40)), false); // ≤39
});

test('rateLimitAllow:同一 key 60s 内仅一次', () => {
    const key = 'unit-device-' + Math.random();
    assert.equal(rateLimitAllow(key, 1_000_000), true);
    assert.equal(rateLimitAllow(key, 1_001_000), false);   // 1s 后
    assert.equal(rateLimitAllow(key, 1_000_000 + 60_001), true); // 窗口外
});

test('checkStarred:204 已 star / 404 未 star / 5xx 可重试不发额度', async () => {
    const originalFetch = globalThis.fetch;
    try {
        globalThis.fetch = async () => ({ status: 204 });
        assert.deepEqual(await checkStarred('owner/repo', 'octocat'), { ok: true, starred: true });
        globalThis.fetch = async () => ({ status: 404 });
        assert.deepEqual(await checkStarred('owner/repo', 'octocat'), { ok: true, starred: false });
        globalThis.fetch = async () => ({ status: 502 });
        assert.deepEqual(await checkStarred('owner/repo', 'octocat'), { ok: false, retryable: true, status: 502 });
        globalThis.fetch = async () => { throw new Error('boom'); };
        assert.deepEqual(await checkStarred('owner/repo', 'octocat'), { ok: false, retryable: true, error: 'boom' });
    } finally {
        globalThis.fetch = originalFetch;
    }
});
```

- [ ] **步骤 2:运行测试验证失败**

运行:`cd cloudfunctions/device-auth && npm test`
预期:FAIL(`Cannot find module '../lib/github'`)。

- [ ] **步骤 3:实现 lib/github.js**

```js
/**
 * GitHub Star 校验 + 兑换防线(规格 §6.2)
 * - GET /repos/{GITHUB_STAR_REPO}/stars/{login} → 204 已 star / 404 未 star
 * - 带 GITHUB_TOKEN 防匿名限流;任何失败一律「不发放」,宁可让用户重试
 * - rateLimitAllow:实例内 LRU 兜底限流(device_id,60s),防刷 GitHub API
 *   (管理台/低频场景与 feedback 函数的 LRU 同思路;多实例下不严格,够用)
 */

'use strict';

const GITHUB_API = 'https://api.github.com';
const REDEEM_WINDOW_MS = 60_000;

/** GitHub 用户名规则:字母数字开头,可含单个连字符,≤39 位 */
function isValidGithubLogin(login) {
    return /^[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}$/.test(String(login || ''));
}

async function checkStarred(repoFullName, login, { token, timeoutMs = 8000 } = {}) {
    if (!repoFullName) return { ok: false, retryable: false, error: 'GITHUB_STAR_REPO not configured' };
    const headers = {
        'User-Agent': 'whimread-device-auth',
        Accept: 'application/vnd.github+json',
    };
    if (token) headers.Authorization = `Bearer ${token}`;
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
        const res = await fetch(`${GITHUB_API}/repos/${repoFullName}/stars/${encodeURIComponent(login)}`,
            { headers, signal: ctrl.signal, redirect: 'manual' });
        if (res.status === 204 || res.status === 200) return { ok: true, starred: true };
        if (res.status === 404) return { ok: true, starred: false };
        return { ok: false, retryable: res.status >= 500 || res.status === 429, status: res.status };
    } catch (e) {
        return { ok: false, retryable: true, error: e.message };
    } finally {
        clearTimeout(timer);
    }
}

const _hits = new Map();   // key → last ts(实例内)
function rateLimitAllow(key, now = Date.now()) {
    if (_hits.size > 10_000) {
        for (const [k, t] of _hits) if (now - t > REDEEM_WINDOW_MS) _hits.delete(k);
    }
    const last = _hits.get(key) || 0;
    if (now - last < REDEEM_WINDOW_MS) return false;
    _hits.set(key, now);
    return true;
}

module.exports = { checkStarred, isValidGithubLogin, rateLimitAllow, GITHUB_API, REDEEM_WINDOW_MS };
```

- [ ] **步骤 4:index.js 接 redeem 路由**

在 device-auth/index.js 的 `handleMe` 路由分支后追加:

```js
        if (method === 'POST' && route === 'redeem') {
            return await handleRedeem(event, context);
        }
```

文件尾部新增 handler(同时补 require:`const { checkStarred, isValidGithubLogin, rateLimitAllow } = require('./lib/github');`):

```js
/**
 * POST /api/v1/devices/star/redeem(设备 JWT,规格 §6.2)
 * 错误码与客户端 mapRedeemDioError 一一对应,勿改名。
 */
const STAR_REDEEM_AMOUNT = parseInt(process.env.STAR_REDEEM_AMOUNT || '50', 10);

async function handleRedeem(event, context) {
    let claims;
    try {
        claims = await verifyDeviceJwt(event.headers, context);
    } catch (e) {
        return err(401, e.code || ErrorCodes.JWT_INVALID, 'Invalid JWT');
    }

    const body = parseBody(event);
    const login = String(body.github_login || '').trim();
    if (!isValidGithubLogin(login)) {
        return err(400, 'INVALID_GITHUB_LOGIN', 'GitHub 用户名格式不正确');
    }
    if (!rateLimitAllow(claims.sub)) {
        return err(429, 'STAR_REDEEM_RATE_LIMITED', '兑换请求过于频繁');
    }

    const db = getDb(context);
    const { data: device, error: devErr } = await db.from('devices')
        .select('quota_balance, status')
        .eq('android_id', claims.sub).single();
    if (devErr || !device) return err(404, ErrorCodes.DEVICE_NOT_FOUND, 'Device not found');
    if (device.status === 'banned') return err(403, ErrorCodes.DEVICE_BANNED, 'Device banned');

    // 幂等:同一 GitHub 账号全库仅可兑一次(并发窗口由迁移里的
    // uq_quota_changes_star_login 部分唯一索引兜底)
    const { data: prev } = await db.raw(
        `SELECT id FROM quota_changes
         WHERE reason = 'star_redeem' AND metadata->>'github_login' = '${login.replace(/'/g, "''")}'
         LIMIT 1`);
    if (prev && prev.length > 0) {
        return err(409, 'ALREADY_REDEEMED', '该 GitHub 账号已兑换过');
    }

    // GitHub 校验:失败/未 star 一律不发放(§9 降级路径)
    const gh = await checkStarred(process.env.GITHUB_STAR_REPO, login, { token: process.env.GITHUB_TOKEN });
    if (!gh.ok) {
        logger.error(context, 'github check failed', { status: gh.status, error: gh.error });
        return err(503, 'GITHUB_CHECK_FAILED', 'GitHub 校验暂不可用,请稍后重试');
    }
    if (!gh.starred) {
        return err(400, 'NOT_STARRED', '未检测到 Star');
    }

    // 发额度(与 register_bonus 同模式:先更余额,再落审计流水)
    const amount = STAR_REDEEM_AMOUNT;
    const newBalance = device.quota_balance + amount;
    const { error: updErr } = await db.from('devices')
        .update({ quota_balance: newBalance, updated_at: new Date().toISOString() })
        .eq('android_id', claims.sub);
    if (updErr) return err(500, ErrorCodes.INTERNAL, 'Failed to grant quota');
    const { error: auditErr } = await db.from('quota_changes').insert({
        android_id: claims.sub,
        change_amount: amount,
        reason: 'star_redeem',
        balance_after: newBalance,
        metadata: JSON.stringify({ github_login: login }),
    });
    if (auditErr) {
        // 并发同账号兑换触发 uq_quota_changes_star_login 部分唯一索引。
        // ⚠️ db.js Builder 对错误是返回 {error} 而非 throw,必须判返回值
        logger.error(context, 'redeem audit insert failed', { message: auditErr.message });
        if (String(auditErr.message || '').includes('duplicate key')) {
            return err(409, 'ALREADY_REDEEMED', '该 GitHub 账号已兑换过');
        }
        return err(500, ErrorCodes.INTERNAL, 'Failed to record redeem');
    }

    logger.info(context, 'star redeemed', { github_login: login, amount });
    return ok({ granted: amount, quota_balance: newBalance, github_login: login, message: '兑换成功' });
}
```

- [ ] **步骤 5:运行测试验证通过**

运行:`cd cloudfunctions/device-auth && npm test`
预期:PASS(redeem.test.js 3 个用例 + 既有 index.test.js 不回归)。

- [ ] **步骤 6:Commit**

```bash
git add cloudfunctions/device-auth
git commit -m "feat(device-auth): star/redeem 兑换端点(GitHub 校验+幂等+限流)"
```

---

### 任务 13:客户端 `mapRedeemDioError` 读 `code` 而非 `error`

**文件:**
- 修改:`lib/services/device/device_auth_service.dart:331-341`(doc 注释 + rawCode 取值)
- 修改:`test/unit/services/device/device_auth_star_redeem_test.dart`(错误体 mock 从 `error` 键改为 `code` 键)

背景(规格 §2.3):`mapRedeemDioError` 读 `data['error']`,但后端 `errors.js` 的错误体是 `{code, message}` —— 现网所有兑换错误都会落进 default 分支。服务端错误码已在任务 12 与本文件既有映射对齐,无需增删 case。

- [ ] **步骤 1:先跑既有测试确认当前行为**

运行:`flutter test test/unit/services/device/device_auth_star_redeem_test.dart`
预期:记录通过/失败基线(该文件随 Star 兑换客户端功能一起尚未 commit)。

- [ ] **步骤 2:修改取值与注释**

`lib/services/device/device_auth_service.dart` 331-341 行改为:

```dart
  /// 把兑换接口的 DioException 映射为带语义 code 的 [DeviceAuthException]。
  ///
  /// 后端错误体统一为 `{"code": <code>, "message": <msg>}`(cloudfunctions/common/errors.js);
  /// 网络层失败（无响应）映射为 NETWORK。
  @visibleForTesting
  static DeviceAuthException mapRedeemDioError(DioException e) {
    final resp = e.response;
    if (resp == null) {
      return DeviceAuthException('NETWORK', '网络不可用，请检查网络后重试');
    }
    final data = resp.data;
    final rawCode = data is Map
        ? (data['code'] ?? data['error'])?.toString()
        : null;
    final message = data is Map ? data['message']?.toString() : null;
```

(`?? data['error']` 仅为兼容过渡期旧字段名,后端从不发送;switch 各 case 与 default 保持不变。)

- [ ] **步骤 3:更新测试的错误体构造**

在 `device_auth_star_redeem_test.dart` 中把所有形如 `{'error': 'NOT_STARRED', ...}` 的 mock body 改为 `{'code': 'NOT_STARRED', ...}`,并补一个用例:

```dart
    test('错误体用 code 键(errors.js 规范)也能映射', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/api/v1/devices/star/redeem'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/devices/star/redeem'),
          statusCode: 400,
          data: {'code': 'NOT_STARRED', 'message': '未检测到 Star'},
        ),
      );
      final ex = DeviceAuthService.mapRedeemDioError(e);
      expect(ex.code, 'NOT_STARRED');
    });
```

(以文件内既有的构造风格为准,保持一致;若既有测试用 helper 构造 DioException,沿用 helper。)

- [ ] **步骤 4:运行测试验证通过**

运行:`flutter test test/unit/services/device/`
预期:PASS(含 device_auth_quota_test.dart 不回归)。

- [ ] **步骤 5:静态检查**

运行:`flutter analyze lib/services/device/ test/unit/services/device/`
预期:No issues。

- [ ] **步骤 6:Commit**

```bash
git add lib/services/device/device_auth_service.dart test/unit/services/device/device_auth_star_redeem_test.dart
git commit -m "fix(device): redeem 错误映射改读 code 键(errors.js 错误体规范)"
```

---

# Phase 4:前端骨架与登录(任务 14–16)

> 目录 `admin/web/`(规格 §8)。门禁:`npm run build`(内含 `tsc --noEmit`)通过;V1 不写前端自动化测试,业务页联调走任务 22 冒烟清单。

### 任务 14:Vite + React + AntD 脚手架

**文件:**
- 创建:`admin/web/package.json`、`admin/web/vite.config.ts`、`admin/web/tsconfig.json`、`admin/web/index.html`
- 创建:`admin/web/src/main.tsx`、`admin/web/src/App.tsx`(路由骨架 + 占位页)

- [ ] **步骤 1:创建配置文件**

`admin/web/package.json`:

```json
{
  "name": "whimread-admin-web",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc --noEmit && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "antd": "^5.21.0",
    "qrcode": "^1.5.4",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "react-router-dom": "^6.26.0"
  },
  "devDependencies": {
    "@types/qrcode": "^1.5.5",
    "@types/react": "^18.3.3",
    "@types/react-dom": "^18.3.0",
    "@vitejs/plugin-react": "^4.3.1",
    "typescript": "^5.5.4",
    "vite": "^5.4.8"
  }
}
```

`admin/web/vite.config.ts`:

```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// base '/admin/':子路径静态托管部署(规格 §10);
// HashRouter:深链无需服务端 404 回退(规格 §10);
// VITE_API_BASE:构建期注入 API 前缀。生产由 deploy-admin.sh 注入 /admin/api;
// 本地开发必须设为完整地址(如 VITE_API_BASE=https://<dev 网关域名>/admin/api npm run dev),
// 否则 fetch 会打到页面 origin 根而 404。
export default defineConfig({
  plugins: [react()],
  base: '/admin/',
  build: { outDir: 'dist', sourcemap: false },
});
```

`admin/web/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "skipLibCheck": true,
    "noEmit": true,
    "types": ["vite/client"]
  },
  "include": ["src"]
}
```

`admin/web/index.html`:

```html
<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="UTF-8" />
    <!-- 规格 §10:管理台登录页不进搜索引擎 -->
    <meta name="robots" content="noindex" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Whimread 管理台</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

- [ ] **步骤 2:创建入口与路由骨架**

`admin/web/src/main.tsx`:

```tsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import { ConfigProvider } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import App from './App';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <ConfigProvider locale={zhCN}>
      <App />
    </ConfigProvider>
  </React.StrictMode>,
);
```

`admin/web/src/App.tsx`(任务 15-19 逐步替换占位):

```tsx
import { HashRouter, Navigate, Route, Routes } from 'react-router-dom';
import 'antd/dist/reset.css';

function Placeholder({ title }: { title: string }) {
  return <div style={{ padding: 24 }}>{title}(任务 16-19 实现)</div>;
}

export default function App() {
  return (
    <HashRouter>
      <Routes>
        <Route path="/login" element={<Placeholder title="登录(任务 16)" />} />
        <Route path="*" element={<Placeholder title="业务页骨架(任务 15 接入布局与守卫)" />} />
      </Routes>
    </HashRouter>
  );
}
```

- [ ] **步骤 3:安装并构建**

运行:`cd admin/web && npm install && npm run build`
预期:tsc 无错误,vite 产出 `dist/`(注意产物路径前缀为 `/admin/`)。

- [ ] **步骤 4:gitignore 检查**

确认仓库根 `.gitignore` 已忽略 `admin/web/node_modules` 与 `admin/web/dist`(若只有 `node_modules/` 通配则无需改)。

- [ ] **步骤 5:Commit**

```bash
git add admin/web
git commit -m "feat(admin-web): Vite+React+AntD 脚手架(/admin/ 子路径 + HashRouter)"
```

---

### 任务 15:API 客户端 + 会话上下文

**文件:**
- 创建:`admin/web/src/api/client.ts`
- 创建:`admin/web/src/auth.tsx`
- 修改:`admin/web/src/App.tsx`(接入布局侧边导航 + 登录守卫)

- [ ] **步骤 1:实现 client.ts**

`admin/web/src/api/client.ts`:

```ts
/**
 * 管理 API fetch 封装(规格 §6.1/§8)
 * - Bearer 注入;401 → 用 refresh token 静默续期一次并重放;仍失败 → 清会话回登录页
 * - 错误统一抛 ApiError(code 为后端错误码,中文文案后端已带,缺省时用 ERROR_TEXT 兜底)
 * 路径都相对 VITE_API_BASE:生产由 deploy-admin.sh 注入 /admin/api;本地 dev 必须显式设
 * VITE_API_BASE=https://<dev 网关域名>/admin/api(完整 URL 同样可用,fetch 原生支持)
 */

const BASE: string = (import.meta as { env?: Record<string, string> }).env?.VITE_API_BASE || '';

const K_AT = 'whimread_admin_at';
const K_RT = 'whimread_admin_rt';

export function getAccessToken(): string | null { return localStorage.getItem(K_AT); }
export function getRefreshToken(): string | null { return localStorage.getItem(K_RT); }
export function setTokens(at: string, rt: string) { localStorage.setItem(K_AT, at); localStorage.setItem(K_RT, rt); }
export function clearTokens() { localStorage.removeItem(K_AT); localStorage.removeItem(K_RT); }

const ERROR_TEXT: Record<string, string> = {
  NO_BEARER: '请先登录',
  JWT_INVALID: '登录已失效,请重新登录',
  JWT_EXPIRED: '登录已过期,请重新登录',
  ACCOUNT_DISABLED: '账号已停用',
  ACCOUNT_LOCKED: '尝试次数过多,账号已临时锁定(15 分钟)',
  CONCURRENT_MODIFY: '数据已被修改,请刷新后重试',
  VALIDATION_FAILED: '提交内容未通过校验',
  SESSION_EXPIRED: '会话已过期,请重新登录',
};

export class ApiError extends Error {
  constructor(readonly code: string, message: string, readonly status: number) {
    super(message);
  }
}

let refreshing: Promise<boolean> | null = null;

async function doRefresh(): Promise<boolean> {
  const rt = getRefreshToken();
  if (!rt) return false;
  try {
    const res = await fetch(`${BASE}/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh_token: rt }),
    });
    if (!res.ok) { clearTokens(); return false; }
    const data = await res.json();
    setTokens(data.access_token, data.refresh_token);
    return true;
  } catch {
    return false;
  }
}

async function raw(path: string, init: RequestInit): Promise<Response> {
  const at = getAccessToken();
  return fetch(`${BASE}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(at ? { Authorization: `Bearer ${at}` } : {}),
      ...(init.headers || {}),
    },
  });
}

export async function api<T = unknown>(path: string, init: RequestInit = {}): Promise<T> {
  let res = await raw(path, init);
  if (res.status === 401 && getRefreshToken() && !path.startsWith('/auth/')) {
    refreshing = refreshing || doRefresh();
    const ok = await refreshing;
    refreshing = null;
    if (ok) {
      res = await raw(path, init);
    } else {
      window.location.hash = '#/login';
      throw new ApiError('SESSION_EXPIRED', ERROR_TEXT.SESSION_EXPIRED, 401);
    }
  }
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    const code = String((body as { code?: string }).code || `HTTP_${res.status}`);
    throw new ApiError(code, (body as { message?: string }).message || ERROR_TEXT[code] || `请求失败(${res.status})`, res.status);
  }
  return body as T;
}
```

- [ ] **步骤 2:实现 auth.tsx**

`admin/web/src/auth.tsx`:

```tsx
import { createContext, useCallback, useContext, useMemo, useState } from 'react';
import { api, clearTokens, getAccessToken, setTokens } from './api/client';

interface Session {
  authed: boolean;
  loginSuccess(data: { access_token: string; refresh_token: string }): void;
  logout(): Promise<void>;
}

const SessionContext = createContext<Session>({ authed: false, loginSuccess: () => {}, logout: async () => {} });

export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [authed, setAuthed] = useState<boolean>(() => !!getAccessToken());

  const loginSuccess = useCallback((data: { access_token: string; refresh_token: string }) => {
    setTokens(data.access_token, data.refresh_token);
    setAuthed(true);
  }, []);

  const logout = useCallback(async () => {
    const rt = localStorage.getItem('whimread_admin_rt');
    try {
      if (rt) await api('/auth/logout', { method: 'POST', body: JSON.stringify({ refresh_token: rt }) });
    } catch { /* 尽力而为 */ }
    clearTokens();
    setAuthed(false);
    window.location.hash = '#/login';
  }, []);

  const value = useMemo(() => ({ authed, loginSuccess, logout }), [authed, loginSuccess, logout]);
  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession() {
  return useContext(SessionContext);
}
```

- [ ] **步骤 3:App.tsx 接入布局 + 守卫**

```tsx
import { HashRouter, Navigate, Route, Routes } from 'react-router-dom';
import { Layout, Menu } from 'antd';
import { Link, useLocation } from 'react-router-dom';
import 'antd/dist/reset.css';
import { SessionProvider, useSession } from './auth';

const { Header, Sider, Content } = Layout;

function Placeholder({ title }: { title: string }) {
  return <div style={{ padding: 24 }}>{title}(后续任务实现)</div>;
}

const NAV = [
  { key: '/overview', label: <Link to="/overview">总览</Link> },
  { key: '/devices', label: <Link to="/devices">设备</Link> },
  { key: '/feedback', label: <Link to="/feedback">反馈</Link> },
  { key: '/audit', label: <Link to="/audit">审计</Link> },
];

function Shell({ children }: { children: React.ReactNode }) {
  const { pathname } = useLocation();
  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Sider>
        <div style={{ color: '#fff', padding: 16, fontWeight: 600 }}>Whimread 管理台</div>
        <Menu theme="dark" mode="inline" selectedKeys={[pathname]} items={NAV} />
      </Sider>
      <Layout>
        <Content style={{ padding: 24 }}>{children}</Content>
      </Layout>
    </Layout>
  );
}

function RequireAuth({ children }: { children: React.ReactNode }) {
  const { authed } = useSession();
  return authed ? <Shell>{children}</Shell> : <Navigate to="/login" replace />;
}

export default function App() {
  return (
    <SessionProvider>
      <HashRouter>
        <Routes>
          <Route path="/login" element={<Placeholder title="登录(任务 16)" />} />
          <Route path="/overview" element={<RequireAuth><Placeholder title="总览(任务 17)" /></RequireAuth>} />
          <Route path="/devices" element={<RequireAuth><Placeholder title="设备(任务 18)" /></RequireAuth>} />
          <Route path="/feedback" element={<RequireAuth><Placeholder title="反馈(任务 19)" /></RequireAuth>} />
          <Route path="/audit" element={<RequireAuth><Placeholder title="审计(任务 19)" /></RequireAuth>} />
          <Route path="*" element={<Navigate to="/overview" replace />} />
        </Routes>
      </HashRouter>
    </SessionProvider>
  );
}
```

- [ ] **步骤 4:构建验证**

运行:`cd admin/web && npm run build`
预期:tsc + vite 通过。

- [ ] **步骤 5:Commit**

```bash
git add admin/web/src
git commit -m "feat(admin-web): API 客户端(401 静默续期)+ 会话上下文 + 布局骨架"
```

---

### 任务 16:三段式登录页

**文件:**
- 创建:`admin/web/src/pages/Login.tsx`
- 修改:`admin/web/src/App.tsx`(/login 路由替换占位)

- [ ] **步骤 1:实现 Login.tsx**

状态机与规格 §5.3 一一对应:`password →(must_change_password)change_password →(无 TOTP)totp_setup → verify-setup;有 TOTP → totp`。

```tsx
import { useState } from 'react';
import { Alert, Button, Card, Form, Input, Modal, Space, Typography, message } from 'antd';
import QRCode from 'qrcode';
import { api, setTokens } from '../api/client';
import { useSession } from '../auth';

type Creds = { access_token: string; refresh_token: string };

interface LoginResp { next: 'change_password' | 'totp_setup' | 'totp'; change_token?: string; login_token?: string }
interface SetupResp { secret_base32: string; otpauth_url: string; backup_codes: string[] }

export default function Login() {
  const { loginSuccess } = useSession();
  const [stage, setStage] = useState<'password' | 'change' | 'bind' | 'totp'>('password');
  const [changeToken, setChangeToken] = useState('');
  const [loginToken, setLoginToken] = useState('');
  const [setup, setSetup] = useState<SetupResp | null>(null);
  const [qr, setQr] = useState('');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  const finish = (data: Creds) => { loginSuccess(data); window.location.hash = '#/overview'; };

  const call = async <T,>(fn: () => Promise<T>): Promise<T | null> => {
    setBusy(true); setErr('');
    try { return await fn(); } catch (e) { setErr((e as Error).message); return null; } finally { setBusy(false); }
  };

  const onPassword = async (v: { username: string; password: string }) => {
    const r = await call(() => api<LoginResp>('/auth/login', { method: 'POST', body: JSON.stringify(v) }));
    if (!r) return;
    if (r.next === 'change_password') { setChangeToken(r.change_token!); setStage('change'); }
    else await enterSetupOrTotp(r);
  };

  const enterSetupOrTotp = async (r: LoginResp) => {
    if (r.next === 'totp_setup') {
      const s = await call(() => api<SetupResp>('/auth/totp/setup', { method: 'POST', body: JSON.stringify({ login_token: r.login_token }) }));
      if (!s) return;
      setSetup(s); setQr(await QRCode.toDataURL(s.otpauth_url, { margin: 1 }));
      setLoginToken(r.login_token!); setStage('bind');
    } else { setLoginToken(r.login_token!); setStage('totp'); }
  };

  const onChangePassword = async (v: { new_password: string }) => {
    const r = await call(() => api<LoginResp>('/auth/change-password', {
      method: 'POST', body: JSON.stringify({ change_token: changeToken, new_password: v.new_password }),
    }));
    if (r) await enterSetupOrTotp(r);
  };

  const onBind = async (v: { code: string }) => {
    const r = await call(() => api<Creds>('/auth/totp/verify-setup', {
      method: 'POST', body: JSON.stringify({ login_token: loginToken, code: v.code.trim() }),
    }));
    if (r) finish(r);
  };

  const onTotp = async (v: { code: string }) => {
    const r = await call(() => api<Creds>('/auth/totp', {
      method: 'POST', body: JSON.stringify({ login_token: loginToken, code: v.code.trim() }),
    }));
    if (r) finish(r);
  };

  return (
    <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 80 }}>
      <Card title="Whimread 管理台" style={{ width: 420 }}>
        {err && <Alert type="error" message={err} style={{ marginBottom: 16 }} showIcon />}
        {stage === 'password' && (
          <Form layout="vertical" onFinish={onPassword} disabled={busy}>
            <Form.Item name="username" label="用户名" rules={[{ required: true }]}><Input autoComplete="username" /></Form.Item>
            <Form.Item name="password" label="密码" rules={[{ required: true }]}><Input.Password autoComplete="current-password" /></Form.Item>
            <Button type="primary" htmlType="submit" block loading={busy}>登录</Button>
          </Form>
        )}
        {stage === 'change' && (
          <Form layout="vertical" onFinish={onChangePassword} disabled={busy}>
            <Alert type="warning" message="首次登录,请设置新密码(≥12 位,含大小写与数字)" style={{ marginBottom: 16 }} showIcon />
            <Form.Item name="new_password" label="新密码" rules={[{ required: true, min: 12 }]}><Input.Password /></Form.Item>
            <Form.Item name="confirm" label="确认新密码" dependencies={['new_password']} rules={[
              { required: true }, ({ getFieldValue }) => ({
                validator: (_, v) => v === getFieldValue('new_password') ? Promise.resolve() : Promise.reject(new Error('两次输入不一致')),
              }),
            ]}><Input.Password /></Form.Item>
            <Button type="primary" htmlType="submit" block loading={busy}>保存并继续</Button>
          </Form>
        )}
        {stage === 'bind' && setup && (
          <Space direction="vertical" style={{ width: '100%' }} size="middle">
            <Typography.Text>用验证器 App(Google Authenticator 等)扫码,或手动输入密钥:</Typography.Text>
            <img src={qr} alt="TOTP 二维码" style={{ width: 200, display: 'block', margin: '0 auto' }} />
            <Typography.Text code copyable>{setup.secret_base32}</Typography.Text>
            <Form layout="vertical" onFinish={onBind} disabled={busy}>
              <Form.Item name="code" label="输入 6 位验证码确认" rules={[{ required: true }]}><Input maxLength={6} inputMode="numeric" /></Form.Item>
              <Button type="primary" htmlType="submit" block loading={busy}>确认绑定</Button>
            </Form>
            <Button block onClick={() => Modal.info({
              title: '备用恢复码(仅显示一次,请立即保存)',
              width: 520,
              content: <Typography.Paragraph style={{ whiteSpace: 'pre-wrap' }}>{setup.backup_codes.join('\n')}</Typography.Paragraph>,
            })}>查看 10 个备用恢复码</Button>
          </Space>
        )}
        {stage === 'totp' && (
          <Form layout="vertical" onFinish={onTotp} disabled={busy}>
            <Form.Item name="code" label="验证码(6 位 TOTP 或 8 位备用码)" rules={[{ required: true }]}>
              <Input maxLength={8} inputMode="numeric" autoFocus />
            </Form.Item>
            <Button type="primary" htmlType="submit" block loading={busy}>验证</Button>
          </Form>
        )}
      </Card>
    </div>
  );
}
```

注意:`message` 从 antd 导入但此实现用 Alert 展示错误——删除未使用的 `message` 导入以免 `noUnusedLocals` 报错(或改用 message.error)。

- [ ] **步骤 2:App.tsx 替换 /login 占位**

```tsx
import Login from './pages/Login';
// <Route path="/login" element={<Login />} />
```

- [ ] **步骤 3:构建 + 手工过一遍类型检查**

运行:`cd admin/web && npm run build`
预期:通过。

- [ ] **步骤 4:Commit**

```bash
git add admin/web/src
git commit -m "feat(admin-web): 三段式登录页(改密/TOTP 绑定+二维码/备用码)"
```

---

# Phase 5:业务页(任务 17–19)

> 共同约定:所有请求走 `api()`;接口返回的中文错误直接展示(规格 §9);封禁/重置/踢下线三个动作必须 Modal 二次确认 + 填 note(§8 红线);409 `CONCURRENT_MODIFY` → message 提示并自动刷新数据。

### 任务 17:Overview 总览页 + 顶栏退出

**文件:**
- 创建:`admin/web/src/pages/Overview.tsx`
- 修改:`admin/web/src/App.tsx`(Shell 顶栏加退出按钮;/overview 替换占位)

- [ ] **步骤 1:实现 Overview.tsx**

```tsx
import { useEffect, useState } from 'react';
import { Alert, Card, Col, Row, Statistic, Spin } from 'antd';
import { api } from '../api/client';

interface Overview {
  devices_total: number; devices_banned: number; devices_today: number;
  granted_7d: number; consumed_7d: number; llm_calls_7d: number; feedback_open: number;
}

export default function Overview() {
  const [data, setData] = useState<Overview | null>(null);
  const [err, setErr] = useState('');

  useEffect(() => {
    api<Overview>('/overview').then(setData).catch((e) => setErr((e as Error).message));
  }, []);

  if (err) return <Alert type="error" message={err} showIcon />;
  if (!data) return <Spin style={{ display: 'block', margin: '80px auto' }} />;

  return (
    <div>
      <Row gutter={[16, 16]}>
        <Col span={6}><Card><Statistic title="设备总数" value={data.devices_total} /></Card></Col>
        <Col span={6}><Card><Statistic title="今日新增设备" value={data.devices_today} /></Card></Col>
        <Col span={6}><Card><Statistic title="封禁中" value={data.devices_banned} valueStyle={data.devices_banned > 0 ? { color: '#cf1322' } : undefined} /></Card></Col>
        <Col span={6}><Card><Statistic title="待处理反馈" value={data.feedback_open} /></Card></Col>
      </Row>
      <Row gutter={[16, 16]} style={{ marginTop: 16 }}>
        <Col span={8}><Card><Statistic title="7 日发放额度" value={data.granted_7d} /></Card></Col>
        <Col span={8}><Card><Statistic title="7 日消耗额度" value={data.consumed_7d} /></Card></Col>
        <Col span={8}><Card><Statistic title="7 日 LLM 调用" value={data.llm_calls_7d} /></Card></Col>
      </Row>
    </div>
  );
}
```

- [ ] **步骤 2:App.tsx 顶栏加退出 + 替换占位**

Shell 的 `<Layout>` 内 Sider 之后补:

```tsx
import { Button } from 'antd';
import { useSession } from './auth';
// Shell 组件内:
function Shell({ children }: { children: React.ReactNode }) {
  const { pathname } = useLocation();
  const { logout } = useSession();
  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Sider>…(不变)…</Sider>
      <Layout>
        <Header style={{ background: '#fff', display: 'flex', justifyContent: 'flex-end', alignItems: 'center', padding: '0 24px' }}>
          <Button onClick={logout}>退出登录</Button>
        </Header>
        <Content style={{ padding: 24 }}>{children}</Content>
      </Layout>
    </Layout>
  );
}
```

`/overview` 路由替换为 `<RequireAuth><Overview /></RequireAuth>`。

- [ ] **步骤 3:构建验证 + Commit**

运行:`cd admin/web && npm run build` → 通过。

```bash
git add admin/web/src
git commit -m "feat(admin-web): 总览仪表盘 + 顶栏退出"
```

---

### 任务 18:Devices 列表 + 设备详情(操作区)

**文件:**
- 创建:`admin/web/src/pages/Devices.tsx`
- 创建:`admin/web/src/pages/DeviceDetail.tsx`
- 修改:`admin/web/src/App.tsx`(/devices、/devices/:androidId 路由)

- [ ] **步骤 1:实现 Devices.tsx**

```tsx
import { useCallback, useEffect, useState } from 'react';
import { Alert, Card, Input, Select, Space, Table, Tag } from 'antd';
import { Link } from 'react-router-dom';
import { api } from '../api/client';

interface DeviceRow {
  android_id: string; quota_balance: number; total_consumed: number | null;
  status: string; last_seen_at: string | null; created_at: string;
}
interface ListResp { items: DeviceRow[]; total: number }

const STATUS_TAG: Record<string, { color: string; text: string }> = {
  active: { color: 'green', text: '正常' },
  banned: { color: 'red', text: '已封禁' },
};

export default function Devices() {
  const [items, setItems] = useState<DeviceRow[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(20);
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('');
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState('');

  const load = useCallback(async () => {
    setLoading(true); setErr('');
    try {
      const qs = new URLSearchParams({ page: String(page), page_size: String(pageSize) });
      if (query) qs.set('query', query);
      if (status) qs.set('status', status);
      const r = await api<ListResp>(`/devices?${qs.toString()}`);
      setItems(r.items); setTotal(r.total);
    } catch (e) { setErr((e as Error).message); } finally { setLoading(false); }
  }, [page, pageSize, query, status]);

  useEffect(() => { load(); }, [load]);

  return (
    <Card title="设备管理">
      {err && <Alert type="error" message={err} showIcon style={{ marginBottom: 16 }} />}
      <Space style={{ marginBottom: 16 }}>
        <Input.Search
          placeholder="按 android_id 搜索" allowClear style={{ width: 280 }}
          onSearch={(v) => { setPage(1); setQuery(v.trim()); }}
        />
        <Select
          value={status || 'all'} style={{ width: 140 }}
          onChange={(v) => { setPage(1); setStatus(v === 'all' ? '' : v); }}
          options={[
            { value: 'all', label: '全部状态' },
            { value: 'active', label: '正常' },
            { value: 'banned', label: '已封禁' },
          ]}
        />
      </Space>
      <Table<DeviceRow>
        rowKey="android_id" loading={loading} dataSource={items}
        pagination={{ current: page, pageSize, total, showSizeChanger: true,
          onChange: (p, ps) => { setPage(p); setPageSize(ps); } }}
        columns={[
          { title: 'android_id', dataIndex: 'android_id',
            render: (v: string) => <Link to={`/devices/${encodeURIComponent(v)}`}><code>{v}</code></Link> },
          { title: '额度', dataIndex: 'quota_balance', width: 100 },
          { title: '累计消耗', dataIndex: 'total_consumed', width: 110,
            render: (v: number | null) => v ?? '-' },
          { title: '状态', dataIndex: 'status', width: 100,
            render: (v: string) => <Tag color={STATUS_TAG[v]?.color}>{STATUS_TAG[v]?.text ?? v}</Tag> },
          { title: '注册时间', dataIndex: 'created_at', width: 180,
            render: (v: string) => new Date(v).toLocaleString('zh-CN') },
          { title: '最近活跃', dataIndex: 'last_seen_at', width: 180,
            render: (v: string | null) => (v ? new Date(v).toLocaleString('zh-CN') : '-') },
        ]}
      />
    </Card>
  );
}
```

- [ ] **步骤 2:实现 DeviceDetail.tsx**

通用操作 Modal:二次确认 + note(封禁/重置/踢下线强制填)。乐观锁 409 → 提示并刷新。

```tsx
import { useCallback, useEffect, useState } from 'react';
import { Alert, Button, Card, Descriptions, Input, InputNumber, Modal, Space, Table, Tag, Typography, message } from 'antd';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ApiError, api } from '../api/client';

interface Device { android_id: string; quota_balance: number; status: string; created_at: string; last_seen_at: string | null; updated_at: string; attestation_verified: boolean }
interface QuotaChange { id: number; change_amount: number; reason: string; balance_after: number; metadata: { github_login?: string } | null; created_at: string }
interface Detail { device: Device; quota_changes: QuotaChange[]; active_jwts: number }

const REASON_TEXT: Record<string, string> = {
  register_bonus: '注册奖励', llm_call: 'LLM 消耗', manual_grant: '人工加额',
  manual_reset: '人工重置', admin_revoke: '管理员扣减', star_redeem: 'Star 兑换',
};

export default function DeviceDetail() {
  const { androidId = '' } = useParams();
  const navigate = useNavigate();
  const [detail, setDetail] = useState<Detail | null>(null);
  const [err, setErr] = useState('');
  const [modal, setModal] = useState<null | 'grant' | 'reset' | 'ban' | 'unban' | 'revoke'>(null);
  const [note, setNote] = useState('');
  const [amount, setAmount] = useState(50);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      setDetail(await api<Detail>(`/devices/${encodeURIComponent(androidId)}`));
      setErr('');
    } catch (e) { setErr((e as Error).message); }
  }, [androidId]);

  useEffect(() => { load(); }, [load]);

  const runAction = async () => {
    if (!detail) return;
    const d = detail.device;
    const paths: Record<string, string> = {
      grant: `/devices/${encodeURIComponent(d.android_id)}/quota`,
      reset: `/devices/${encodeURIComponent(d.android_id)}/quota`,
      ban: `/devices/${encodeURIComponent(d.android_id)}/status`,
      unban: `/devices/${encodeURIComponent(d.android_id)}/status`,
      revoke: `/devices/${encodeURIComponent(d.android_id)}/revoke-tokens`,
    };
    const bodies: Record<string, object> = {
      grant: { action: 'grant', amount, note: note.trim() || undefined, expected_updated_at: d.updated_at },
      reset: { action: 'reset', note: note.trim(), expected_updated_at: d.updated_at },
      ban: { status: 'banned', note: note.trim(), expected_updated_at: d.updated_at },
      unban: { status: 'active', note: note.trim(), expected_updated_at: d.updated_at },
      revoke: { note: note.trim() },
    };
    setBusy(true);
    try {
      await api(paths[modal!], { method: 'POST', body: JSON.stringify(bodies[modal!]) });
      message.success('操作成功');
      setModal(null); setNote('');
      await load();
    } catch (e) {
      if (e instanceof ApiError && e.code === 'CONCURRENT_MODIFY') {
        message.warning('设备数据已被其他操作修改,已为你刷新,请重试');
        await load();
      } else {
        message.error((e as Error).message);
      }
    } finally { setBusy(false); }
  };

  if (err) return <Alert type="error" message={err} showIcon />;
  if (!detail) return null;
  const d = detail.device;
  const needsNote = modal === 'reset' || modal === 'ban' || modal === 'unban' || modal === 'revoke';
  const canSubmit = !busy && (!needsNote || note.trim().length > 0);

  return (
    <div>
      <Link to="/devices">← 返回设备列表</Link>
      <Card title={<span>设备 <code>{d.android_id}</code></span>} style={{ marginTop: 8 }}
        extra={
          <Space>
            <Button onClick={() => { setAmount(50); setModal('grant'); }}>加额度</Button>
            <Button danger onClick={() => setModal('reset')}>重置额度</Button>
            {d.status === 'banned'
              ? <Button onClick={() => setModal('unban')}>解封</Button>
              : <Button danger onClick={() => setModal('ban')}>封禁</Button>}
            <Button danger onClick={() => setModal('revoke')}>踢下线({detail.active_jwts} 个活跃令牌)</Button>
          </Space>
        }>
        <Descriptions size="small" column={3} bordered>
          <Descriptions.Item label="额度">{d.quota_balance}</Descriptions.Item>
          <Descriptions.Item label="状态">
            <Tag color={d.status === 'banned' ? 'red' : 'green'}>{d.status === 'banned' ? '已封禁' : '正常'}</Tag>
          </Descriptions.Item>
          <Descriptions.Item label="Attestation">{d.attestation_verified ? '通过' : '未通过'}</Descriptions.Item>
          <Descriptions.Item label="注册时间">{new Date(d.created_at).toLocaleString('zh-CN')}</Descriptions.Item>
          <Descriptions.Item label="最近活跃">{d.last_seen_at ? new Date(d.last_seen_at).toLocaleString('zh-CN') : '-'}</Descriptions.Item>
          <Descriptions.Item label="更新时间">{new Date(d.updated_at).toLocaleString('zh-CN')}</Descriptions.Item>
        </Descriptions>
      </Card>

      <Card title="额度流水(最近 50 条)" style={{ marginTop: 16 }}>
        <Table<QuotaChange> rowKey="id" dataSource={detail.quota_changes} pagination={false} size="small"
          columns={[
            { title: '时间', dataIndex: 'created_at', width: 180, render: (v: string) => new Date(v).toLocaleString('zh-CN') },
            { title: '变动', dataIndex: 'change_amount', width: 90,
              render: (v: number) => <Typography.Text type={v >= 0 ? 'success' : 'danger'}>{v >= 0 ? `+${v}` : v}</Typography.Text> },
            { title: '变动后余额', dataIndex: 'balance_after', width: 110 },
            { title: '原因', dataIndex: 'reason', width: 120, render: (v: string) => REASON_TEXT[v] ?? v },
            { title: '备注', render: (_: unknown, r: QuotaChange) => (r.metadata?.github_login ? `GitHub: ${r.metadata.github_login}` : '-') },
          ]} />
      </Card>

      <Modal
        open={modal !== null}
        title={{ grant: '加额度', reset: '重置额度(余额清零)', ban: '封禁设备', unban: '解封设备', revoke: '踢下线(撤销全部设备 JWT)' }[modal || ''] }
        onCancel={() => { setModal(null); setNote(''); }}
        onOk={runAction}
        okButtonProps={{ disabled: !canSubmit, danger: modal === 'reset' || modal === 'ban' || modal === 'revoke' }}
        confirmLoading={busy}
        okText="确认执行"
      >
        <Space direction="vertical" style={{ width: '100%' }} size="middle">
          {(modal === 'grant' || modal === 'reset') && (
            <div>当前余额:{d.quota_balance}{modal === 'reset' && ' → 重置为 0'}</div>
          )}
          {modal === 'grant' && (
            <InputNumber min={1} max={1000000} value={amount} onChange={(v) => setAmount(v || 1)} style={{ width: 160 }} addonAfter="额度" />
          )}
          <div>
            操作说明 {needsNote && <Typography.Text type="danger">(必填,进审计)</Typography.Text>}:
            <Input.TextArea value={note} onChange={(e) => setNote(e.target.value)} rows={2} maxLength={200} placeholder="例如:用户反馈无法注册,补偿额度 / 恶意刷量封禁" />
          </div>
        </Space>
      </Modal>
    </div>
  );
}
```

- [ ] **步骤 3:App.tsx 路由**

```tsx
import Devices from './pages/Devices';
import DeviceDetail from './pages/DeviceDetail';
// <Route path="/devices" element={<RequireAuth><Devices /></RequireAuth>} />
// <Route path="/devices/:androidId" element={<RequireAuth><DeviceDetail /></RequireAuth>} />
```

- [ ] **步骤 4:构建验证 + Commit**

运行:`cd admin/web && npm run build` → 通过。

```bash
git add admin/web/src
git commit -m "feat(admin-web): 设备列表/详情 + 额度/封禁/踢下线操作(二次确认+审计备注)"
```

---

### 任务 19:Feedback 反馈页 + Audit 审计页

**文件:**
- 创建:`admin/web/src/pages/Feedback.tsx`
- 创建:`admin/web/src/pages/Audit.tsx`
- 修改:`admin/web/src/App.tsx`(两路由替换占位)

- [ ] **步骤 1:实现 Feedback.tsx**

```tsx
import { useCallback, useEffect, useState } from 'react';
import { Alert, Card, Drawer, Descriptions, Segmented, Table, Tag, Typography } from 'antd';
import { api } from '../api/client';

interface FeedbackRow { id: number; device_id: string; kind: string; category: string | null; title: string; app_version: string | null; log_count: number; status: string; created_at: string }
interface LogRow { seq: number; ts: string; level: string; category: string | null; message: string; stack_trace: string | null }
interface ListResp { items: FeedbackRow[]; total: number }
interface DetailResp { report: FeedbackRow & { description: string; steps: string | null; contact: string | null; device_model: string | null; platform: string | null }; logs: LogRow[] }

const LEVEL_COLOR: Record<string, string> = { error: 'red', warning: 'orange', info: 'blue', debug: 'default' };
const STATUS_TEXT: Record<string, string> = { open: '待处理', triaged: '已分诊', closed: '已关闭' };

export default function Feedback() {
  const [items, setItems] = useState<FeedbackRow[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [status, setStatus] = useState('open');
  const [detail, setDetail] = useState<DetailResp | null>(null);
  const [err, setErr] = useState('');
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true); setErr('');
    try {
      const qs = new URLSearchParams({ page: String(page), page_size: '20' });
      if (status) qs.set('status', status);
      const r = await api<ListResp>(`/feedback?${qs.toString()}`);
      setItems(r.items); setTotal(r.total);
    } catch (e) { setErr((e as Error).message); } finally { setLoading(false); }
  }, [page, status]);

  useEffect(() => { load(); }, [load]);

  const openDetail = async (id: number) => {
    try { setDetail(await api<DetailResp>(`/feedback/${id}`)); } catch (e) { setErr((e as Error).message); }
  };

  return (
    <Card title="反馈工单" extra={
      <Segmented value={status} onChange={(v) => { setPage(1); setStatus(v as string); }}
        options={[{ value: 'open', label: '待处理' }, { value: 'triaged', label: '已分诊' },
                  { value: 'closed', label: '已关闭' }, { value: '', label: '全部' }]} />
    }>
      {err && <Alert type="error" message={err} showIcon style={{ marginBottom: 16 }} />}
      <Table<FeedbackRow> rowKey="id" loading={loading} dataSource={items} size="small"
        pagination={{ current: page, pageSize: 20, total, onChange: setPage }}
        onRow={(r) => ({ onClick: () => openDetail(r.id), style: { cursor: 'pointer' } })}
        columns={[
          { title: 'ID', dataIndex: 'id', width: 70 },
          { title: '标题', dataIndex: 'title' },
          { title: '类型', dataIndex: 'kind', width: 110, render: (v: string) => (v === 'native_crash' ? <Tag color="volcano">原生崩溃</Tag> : '用户反馈') },
          { title: '状态', dataIndex: 'status', width: 90, render: (v: string) => STATUS_TEXT[v] ?? v },
          { title: 'App 版本', dataIndex: 'app_version', width: 120, render: (v: string | null) => v ?? '-' },
          { title: '日志条数', dataIndex: 'log_count', width: 90 },
          { title: '时间', dataIndex: 'created_at', width: 170, render: (v: string) => new Date(v).toLocaleString('zh-CN') },
        ]} />
      <Drawer open={!!detail} onClose={() => setDetail(null)} width={720} title={detail?.report.title}>
        {detail && (
          <>
            <Descriptions size="small" column={2} bordered>
              <Descriptions.Item label="设备" span={2}><code>{detail.report.device_id}</code></Descriptions.Item>
              <Descriptions.Item label="机型">{detail.report.device_model ?? '-'}</Descriptions.Item>
              <Descriptions.Item label="平台/版本">{detail.report.platform ?? '-'} / {detail.report.app_version ?? '-'}</Descriptions.Item>
              <Descriptions.Item label="联系方式" span={2}>{detail.report.contact ?? '未留'}</Descriptions.Item>
              <Descriptions.Item label="描述" span={2}><Typography.Paragraph style={{ whiteSpace: 'pre-wrap' }}>{detail.report.description}</Typography.Paragraph></Descriptions.Item>
              <Descriptions.Item label="复现步骤" span={2}><Typography.Paragraph style={{ whiteSpace: 'pre-wrap' }}>{detail.report.steps ?? '-'}</Typography.Paragraph></Descriptions.Item>
            </Descriptions>
            <Typography.Title level={5} style={{ marginTop: 16 }}>附带日志({detail.logs.length} 条)</Typography.Title>
            <Table<LogRow> rowKey="seq" dataSource={detail.logs} size="small" pagination={{ pageSize: 20 }}
              columns={[
                { title: '时间', dataIndex: 'ts', width: 110, render: (v: string) => new Date(v).toLocaleTimeString('zh-CN') },
                { title: '级别', dataIndex: 'level', width: 80, render: (v: string) => <Tag color={LEVEL_COLOR[v] ?? 'default'}>{v}</Tag> },
                { title: '分类', dataIndex: 'category', width: 120, render: (v: string | null) => v ?? '-' },
                { title: '内容', dataIndex: 'message', ellipsis: true },
              ]}
              expandable={{
                rowExpandable: (r) => !!r.stack_trace,
                expandedRowRender: (r) => <Typography.Paragraph code style={{ whiteSpace: 'pre-wrap' }}>{r.stack_trace}</Typography.Paragraph>,
              }} />
          </>
        )}
      </Drawer>
    </Card>
  );
}
```

- [ ] **步骤 2:实现 Audit.tsx**

```tsx
import { useCallback, useEffect, useState } from 'react';
import { Alert, Button, Card, Space, Table, Typography } from 'antd';
import { api } from '../api/client';

interface AuditRow { id: number; admin_username: string; action: string; target_type: string | null; target_id: string | null; detail: Record<string, unknown> | null; ip: string | null; created_at: string }
interface ListResp { items: AuditRow[]; has_more: boolean }

const PAGE_SIZE = 20;

export default function Audit() {
  const [items, setItems] = useState<AuditRow[]>([]);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState('');

  const load = useCallback(async (p: number) => {
    setLoading(true); setErr('');
    try {
      const r = await api<ListResp>(`/audit?page=${p}&page_size=${PAGE_SIZE}`);
      setItems(r.items); setHasMore(r.has_more); setPage(p);
    } catch (e) { setErr((e as Error).message); } finally { setLoading(false); }
  }, []);

  useEffect(() => { load(1); }, [load]);

  return (
    <Card title="操作审计">
      {err && <Alert type="error" message={err} showIcon style={{ marginBottom: 16 }} />}
      <Table<AuditRow> rowKey="id" loading={loading} dataSource={items} size="small" pagination={false}
        columns={[
          { title: '时间', dataIndex: 'created_at', width: 170, render: (v: string) => new Date(v).toLocaleString('zh-CN') },
          { title: '操作人', dataIndex: 'admin_username', width: 100 },
          { title: '动作', dataIndex: 'action', width: 150 },
          { title: '对象', width: 220, render: (_: unknown, r: AuditRow) => (r.target_id ? `${r.target_type ?? ''}:${r.target_id}` : '-') },
          { title: '详情', render: (_: unknown, r: AuditRow) => (r.detail ? <Typography.Text code style={{ fontSize: 12 }}>{JSON.stringify(r.detail)}</Typography.Text> : '-') },
          { title: 'IP', dataIndex: 'ip', width: 140, render: (v: string | null) => v ?? '-' },
        ]} />
      <Space style={{ marginTop: 16 }}>
        <Button disabled={page <= 1 || loading} onClick={() => load(page - 1)}>上一页</Button>
        <Button disabled={!hasMore || loading} onClick={() => load(page + 1)}>下一页</Button>
        <Typography.Text type="secondary">第 {page} 页</Typography.Text>
      </Space>
    </Card>
  );
}
```

- [ ] **步骤 3:App.tsx 路由替换占位 + 构建**

```tsx
import Feedback from './pages/Feedback';
import Audit from './pages/Audit';
```

运行:`cd admin/web && npm run build` → 通过。

- [ ] **步骤 4:Commit**

```bash
git add admin/web/src
git commit -m "feat(admin-web): 反馈工单(详情+日志)与操作审计页"
```

---

# Phase 6:部署链路与运维(任务 20–21)

> 全程手动部署(规格 §10):本地 `tcb login` 后执行脚本。**不接入 CI**。

### 任务 20:部署脚本与配置接线

**文件:**
- 修改:`scripts/cloudbase/sync-common.mjs`(FUNCTIONS 数组已由任务 3 步骤 2 纳入,此处仅重跑确认)
- 修改:`cloudbaserc.json`(functions 数组)
- 修改:`scripts/cloudbase/deploy.sh`(步骤 2 device-auth 注入 GITHUB_*;新增步骤 6 admin-console)
- 创建:`scripts/cloudbase/deploy-admin.sh`
- 修改:`.env.example`

- [ ] **步骤 1:确认 sync-common 已含 admin-console 并重跑同步**

`admin-console` 已在任务 3 步骤 2 纳入 `sync-common.mjs` 的 FUNCTIONS 数组;部署前重跑:

运行:`node scripts/cloudbase/sync-common.mjs`
预期:五个函数全部输出 `[OK] … common/ 同步完成`,admin-console 的 package.json 依赖为最新合并结果。

- [ ] **步骤 2:cloudbaserc.json 增加 admin-console**

functions 数组追加(与既有条目同风格):

```json
    {
      "name": "admin-console",
      "runtime": "Nodejs20.19",
      "installDependency": true,
      "timeout": 30,
      "envVariables": {},
      "handler": "index.main",
      "src": "./cloudfunctions/admin-console"
    }
```

- [ ] **步骤 3:deploy.sh 两处修改**

(1) 步骤 2 的 device-auth `tcb fn config update` 的 `--env` JSON 内追加两行(缺省空值,函数侧判空不使用):

```bash
tcb fn config update device-auth -e "$ENV_ID" \
    --env "{
        \"DEVICE_JWT_PRIVATE_KEY\": \"${DEVICE_JWT_PRIVATE_KEY}\",
        \"DEVICE_JWT_PUBLIC_KEY\": \"${DEVICE_JWT_PUBLIC_KEY}\",
        \"GITHUB_STAR_REPO\": \"${GITHUB_STAR_REPO:-}\",
        \"GITHUB_TOKEN\": \"${GITHUB_TOKEN:-}\",
        \"STAR_REDEEM_AMOUNT\": \"${STAR_REDEEM_AMOUNT:-50}\",
        \"TCB_ENV_ID\": \"${ENV_ID}\"
    }"
```

(2) 在 feedback 步骤(步骤 5)之后、`部署完成!` 之前插入步骤 6:

```bash
# ============================================
# 6. 部署 admin-console 函数 + 注入管理台密钥
# ============================================
log_info "==> 步骤 6/6: 部署 admin-console"
if [[ -n "${ADMIN_JWT_SECRET:-}" ]]; then
    cd "$ROOT_DIR/cloudfunctions/admin-console"
    [[ -d node_modules ]] || npm install --omit=dev

    tcb fn deploy admin-console -e "$ENV_ID"
    tcb fn config update admin-console -e "$ENV_ID" \
        --env "{
            \"ADMIN_JWT_SECRET\": \"${ADMIN_JWT_SECRET}\",
            \"ADMIN_WEB_ORIGINS\": \"${ADMIN_WEB_ORIGINS:-}\",
            \"TCB_ENV_ID\": \"${ENV_ID}\"
        }"
else
    log_warn "未配置 ADMIN_JWT_SECRET,跳过 admin-console(管理台不可用)"
fi
```

- [ ] **步骤 4:创建 deploy-admin.sh(SPA 构建 + 静态托管上传)**

```bash
#!/usr/bin/env bash
# Whimread 管理台前端部署(SPA → 静态托管 /admin 路径)
#
# 用法: ./scripts/cloudbase/deploy-admin.sh dev|staging|prod
# 前置: .env 中 TCB_ENV_ID_<ENV> 与 ADMIN_API_BASE_<ENV>(同源 API 前缀)已配置
#
# ⚠️ tcb hosting deploy 的路径参数以本机 CLI 版本实测为准;若 --path 不被支持,
#    改用 `tcb hosting deploy ./dist -e "$ENV_ID"` 前先查 tcb hosting deploy --help

set -euo pipefail

ENV_NAME="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

[[ -f "$ENV_FILE" ]] || { echo "[ERROR] 未找到 .env" >&2; exit 1; }
# shellcheck source=/dev/null
source "$ENV_FILE"

case "$ENV_NAME" in
    dev)     ENV_ID="${TCB_ENV_ID_DEV:?}";     API_BASE="${ADMIN_API_BASE_DEV:-/admin/api}" ;;
    staging) ENV_ID="${TCB_ENV_ID_STAGING:?}"; API_BASE="${ADMIN_API_BASE_STAGING:-/admin/api}" ;;
    prod)    ENV_ID="${TCB_ENV_ID_PROD:?}";    API_BASE="${ADMIN_API_BASE_PROD:-/admin/api}" ;;
    *) echo "[ERROR] 未知环境: $ENV_NAME" >&2; exit 1 ;;
esac

cd "$ROOT_DIR/admin/web"
[[ -d node_modules ]] || npm ci

VITE_API_BASE="$API_BASE" npm run build

tcb hosting deploy ./dist -e "$ENV_ID" --path /admin
echo "[INFO] 管理台已部署: https://<静态域名>/admin/ (ENV=$ENV_NAME)"
```

- [ ] **步骤 5:.env.example 追加**

```bash
# ---- 管理后台(admin-console)----
# 生成: node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"
ADMIN_JWT_SECRET=
# 同源部署下填静态域名;多个逗号分隔(防御纵深,规格 §7)
ADMIN_WEB_ORIGINS=https://whimread.dazhi.site
# Star 兑换(注入 device-auth)
GITHUB_STAR_REPO=
GITHUB_TOKEN=
STAR_REDEEM_AMOUNT=50
# 管理台 API 前缀(deploy-admin.sh 构建期注入 SPA;同源默认 /admin/api)
ADMIN_API_BASE_DEV=/admin/api
ADMIN_API_BASE_STAGING=/admin/api
ADMIN_API_BASE_PROD=/admin/api
```

- [ ] **步骤 6:语法与构建检查**

运行:`bash -n scripts/cloudbase/deploy.sh && bash -n scripts/cloudbase/deploy-admin.sh && chmod +x scripts/cloudbase/deploy-admin.sh && cd admin/web && npm run build`
预期:无语法错误,build 通过。

- [ ] **步骤 7:Commit**

```bash
git add scripts/cloudbase cloudbaserc.json .env.example admin/web
git commit -m "feat(cloudbase): admin-console 部署链路(sync-common/cloudbaserc/deploy.sh 步骤6/deploy-admin.sh)"
```

- [ ] **步骤 8:dev 环境部署 + 域名路由验证(§0.6 验证点)**

按顺序执行并记录结果:

```bash
node scripts/cloudbase/seed-admin.mjs admin        # → 到 CloudBase 控制台执行输出的 SQL
./scripts/cloudbase/deploy.sh dev
./scripts/cloudbase/deploy-admin.sh dev
```

然后验证(把 `<HOST>` 换成 whimread.dazhi.site 或环境实际域名):

```bash
# 1. 函数直连可用性(走 HTTP 访问服务默认域名或自定义域均可)
curl -s -X POST https://<HOST>/admin/api/auth/login -H 'Content-Type: application/json' -d '{}'
#    预期: {"code":"LOGIN_FAILED"} 或 {"code":"VALIDATION_FAILED"}(路由到函数)
#    若返回 index.html / 404 HTML → 静态托管抢占了 /admin/*,见下方降级

# 2. SPA 可访问
curl -sI https://<HOST>/admin/ | head -1            # 预期: HTTP/2 200,Content-Type: text/html

# 3. 网关路由绑定(HTTP 访问服务控制台 或 tcb CLI;若仓库 MCP 网关工具可用可代执行)
#    触发路径 /admin/api → 云函数 admin-console;若尚未绑定自定义域,按控制台提示补 CNAME
```

**降级预案(若静态托管抢占 `/admin/api`)**:把网关触发路径改为 `/adminapi`,同步改 `.env.example` 的 `ADMIN_API_BASE_*` 为 `/adminapi` 并重新执行 `deploy-admin.sh`——函数内 `normalizePath` 已兼容任意前缀,代码零改动。把最终采用的路径记入 runbook(任务 21)。

---

### 任务 21:应急脚本 + runbook 附录

**文件:**
- 创建:`scripts/cloudbase/reset-admin-totp.mjs`
- 修改:`README-cloudbase.md`(若根目录无此文件,则在 `docs/` 下创建同名文件)

- [ ] **步骤 1:reset-admin-totp.mjs(规格 §5.1 应急恢复)**

优先复用 `apply-migration.mjs` 里现成的 SQL 执行通道(读其源码,抽公共函数或复制 callCloudApi 段);若抽取代价大,退化为打印 SQL(与 seed-admin.mjs 同流程):

```js
#!/usr/bin/env node
/**
 * reset-admin-totp.mjs — TOTP 双因子全丢的应急恢复(规格 §10 runbook ①)
 *
 * 动作:清空 totp_secret/totp_enabled/totp_failed_attempts、清备用码、
 *       session_version+1 作废全部 access JWT、写一条 system 审计。
 * 登录将回到「密码 → 重新绑定 TOTP」的三段式流程。
 *
 * 用法: node scripts/cloudbase/reset-admin-totp.mjs <username>
 */

import crypto from 'node:crypto';

const username = process.argv[2];
if (!username) {
    console.error('用法: node scripts/cloudbase/reset-admin-totp.mjs <username>');
    process.exit(1);
}

const sql = `BEGIN;
UPDATE admins SET totp_secret = NULL, totp_enabled = FALSE, totp_failed_attempts = 0,
    failed_attempts = 0, locked_until = NULL, session_version = session_version + 1
WHERE username = '${username.replace(/'/g, "''")}';
DELETE FROM admin_backup_codes WHERE admin_username = '${username.replace(/'/g, "''")}';
INSERT INTO admin_audit_logs (admin_username, action, target_type, target_id, detail)
VALUES ('system', 'system_reset_totp', 'self', '${username.replace(/'/g, "''")}', '{"via":"reset-admin-totp.mjs"}');
COMMIT;`;

console.log('-- 在对应环境 CloudBase 控制台 SQL 编辑器执行:\n');
console.log(sql);
console.log('\n-- 之后用「用户名 + 密码」登录,前端会引导重新绑定 TOTP。');
console.log(`-- 校验指纹: ${crypto.createHash('sha256').update(username).digest('hex').slice(0, 16)}`);
```

(执行通道复用 apply-migration.mjs 时,把「打印 SQL」替换为直接执行;SQL 内容不变。)

- [ ] **步骤 2:README-cloudbase.md 追加「管理后台」附录**

内容骨架(直接成文):

````markdown
## 管理后台(admin-console)runbook

**形态**:云函数 `admin-console`(API `/admin/api/*`)+ 静态托管 SPA(`/admin/`),
单管理员,密码 + TOTP 双因素。规格见 `docs/superpowers/specs/2026-09-09-admin-console-design.md`。

### 首次开通
1. `.env` 填 `ADMIN_JWT_SECRET` / `ADMIN_WEB_ORIGINS`
2. `node scripts/cloudbase/seed-admin.mjs admin` → 控制台执行 SQL(初始密码只打印一次)
3. `./scripts/cloudbase/deploy.sh dev`(含 admin-console 步骤)
4. HTTP 访问服务绑定路由:`/admin/api` → 函数 `admin-console`
5. `./scripts/cloudbase/deploy-admin.sh dev`
6. 登录 `<静态域名>/admin/` 完成改密 + TOTP 绑定(备用码立即保存)
7. device-auth 注入 `GITHUB_STAR_REPO` / `GITHUB_TOKEN`(Star 兑换用)

### 应急
| 场景 | 处置 |
|---|---|
| TOTP 设备 + 备用码全丢 | `node scripts/cloudbase/reset-admin-totp.mjs admin` → 控制台执行 → 重新绑定 |
| 疑似密钥泄露 | 换 `ADMIN_JWT_SECRET`:`tcb fn config update admin-console …` + 改密(must_change 重置),所有会话即时失效 |
| 账号锁定 15min | 等待,或控制台执行 `UPDATE admins SET locked_until = NULL, failed_attempts = 0 …` |
| 静态域名更换 | 同步更新 `ADMIN_WEB_ORIGINS` + 重跑 `deploy-admin.sh`(VITE_API_BASE 同源不变) |

### 已知取舍(实现期记录)
- 【记录任务 1 探针结论】`ExecutePGSql` 多语句事务性 = ____ → 审计策略 `AUDIT_BEFORE_CHANGE` = ____
- 【记录任务 20 步骤 8】`/admin/api` 路由归属:____(若降级为 `/adminapi` 记于此)
- redeem 并发同账号兑换:余额多发概率 ≈ 同账号同实例并发窗口,接受;严格串行化需 DB 端函数,暂不引入
- access/refresh token 存 localStorage:XSS 残余风险,单管理员内部工具接受(规格 §12.5)

### 冒烟清单(每次改版后过一遍)
见「任务 22」清单,固定维护于本节:登录三段式 → 设备搜索/调额 → 审计可见 → redeem → 反馈详情 → 退出。
````

- [ ] **步骤 3:Commit**

```bash
git add scripts/cloudbase/reset-admin-totp.mjs README-cloudbase.md
git commit -m "docs(cloudbase): 管理后台 runbook 附录 + TOTP 应急重置脚本"
```

---

# Phase 7:端到端冒烟(任务 22)

### 任务 22:dev 环境手工冒烟(规格 §11)

**前置:** 任务 1(migration)、任务 2(seed)、任务 20 步骤 8(部署 + 路由)均已在 dev 完成;准备一个可 Star 仓库的 GitHub 账号与一台可安装验证器 App 的手机。

- [ ] **步骤 0:云端部署前的本机接线快检**

运行:`node -e "require('./cloudfunctions/admin-console/index'); console.log('ok')"`
预期:`ok`——在进云端之前尽早暴露 require 链与依赖接线类错误(测试用 FakeRepo 覆盖不到这条路径)。

- [ ] **步骤 1:登录三段式**

| # | 操作 | 预期 |
|---|---|---|
| 1.1 | 错误密码登录 | `LOGIN_FAILED` 中文提示 |
| 1.2 | 连续 5 次错误 | 第 5 次后提示锁定;15 分钟内正确密码 → `ACCOUNT_LOCKED` |
| 1.3 | (控制台清锁后)正确密码 | 进入「设置新密码」页 |
| 1.4 | 弱密码(如 `short1A`) | 提示不合规 |
| 1.5 | 合规新密码 | 进入 TOTP 绑定页,显示二维码 + 密钥 + 「查看备用码」 |
| 1.6 | 错误 6 位码确认 | `TOTP_INVALID` |
| 1.7 | 正确 6 位码 | 进入总览;备用码弹窗已看并保存 |
| 1.8 | 退出 → 用 8 位备用码登录 | 成功;**同一备用码再用** → `TOTP_INVALID` |

- [ ] **步骤 2:会话行为**

| # | 操作 | 预期 |
|---|---|---|
| 2.1 | 登录后刷新页面 | 保持登录(HashRouter 不丢状态) |
| 2.2 | 手动清 localStorage 的 access(保留 refresh)后请求任意页 | 自动续期成功,无感 |
| 2.3 | 退出登录后直接访问 `#/devices` | 重定向回登录页 |

- [ ] **步骤 3:设备管理**

| # | 操作 | 预期 |
|---|---|---|
| 3.1 | 搜索一个真实 android_id 前缀 | 列表命中;状态筛选生效 |
| 3.2 | 详情页 | Descriptions 完整;额度流水 ≤ 50 条;活跃 JWT 数显示 |
| 3.3 | 加额度 50(填 note) | 余额 +50,流水新增 `manual_grant` 行 |
| 3.4 | 重置额度不填 note | Modal 无法确认;绕过前端直接 curl → 400 `VALIDATION_FAILED` |
| 3.5 | 重置额度填 note | 余额 0,流水 `manual_reset` |
| 3.6 | 封禁 → App 内触发 LLM 调用 | App 收到封禁错误(llm-proxy 既有拦截) |
| 3.7 | 踢下线 → App 内再发起请求 | 设备 JWT 失效,App 重新注册流程触发 |
| 3.8 | 解封 | 状态回「正常」 |

- [ ] **步骤 4:Star 兑换全链路**

| # | 操作 | 预期 |
|---|---|---|
| 4.1 | App 内提交未 Star 的 GitHub 账号 | `NOT_STARRED` 中文提示 |
| 4.2 | 该账号 Star `GITHUB_STAR_REPO` 后重试 | 成功提示 +50 额度 |
| 4.3 | 同账号再兑(同设备) | `ALREADY_REDEEMED` |
| 4.4 | 同账号换设备再兑 | `ALREADY_REDEEMED`(幂等查库) |
| 4.5 | 管理台搜该设备看流水 | 新增 `star_redeem` 行,备注含 GitHub 账号 |

- [ ] **步骤 5:反馈与审计闭环**

| # | 操作 | 预期 |
|---|---|---|
| 5.1 | App 提交一条反馈(带日志) | 管理台反馈列表出现;详情含日志与堆栈展开 |
| 5.2 | 打开审计页 | 1.x–4.x 的每个写操作都有对应行(login/lockout/quota_grant/quota_reset/device_ban/revoke_tokens);**不含任何口令/TOTP 码** |

- [ ] **步骤 6:安全抽检**

```bash
curl -s https://<HOST>/admin/api/devices                       # → 401 NO_BEARER
curl -s -X POST https://<HOST>/admin/api/auth/login -d '{}' \
  -H 'Content-Type: application/json' -o /dev/null -w '%{http_code}\n'   # → 4xx,响应体不含 secret/env
```

浏览器 DevTools 抽查:`/auth/*` 响应头无 `Set-Cookie`;CORS 白名单外的 Origin 请求无 `Access-Control-Allow-Origin`。

- [ ] **步骤 7:收尾**

- [ ] 冒烟结果与「已知取舍」三条记录补进 `README-cloudbase.md` 附录的占位下划线
- [ ] `flutter analyze` + `flutter test test/unit/ test/bug/` 全量回归
- [ ] `cd cloudfunctions/admin-console && npm test`、`cd cloudfunctions/device-auth && npm test` 全量回归

---

## 计划完成标准

- [ ] 任务 1–22 全部勾选,期间每个任务独立 commit(Conventional Commits 中文)
- [ ] 三个测试入口零失败:admin-console / device-auth(node --test)、Flutter(flutter test)
- [ ] README-cloudbase.md 的「已知取舍」三条占位全部回填
- [ ] 用户确认冒烟通过后,再考虑 staging / prod 的重复部署(脚本已支持,不再需要计划)







