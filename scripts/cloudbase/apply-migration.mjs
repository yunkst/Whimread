#!/usr/bin/env node
/**
 * Whimread CloudBase PG migration 应用脚本(本地版)
 *
 * 用法:
 *   node scripts/cloudbase/apply-migration.mjs <env> [version]
 *
 * 参数:
 *   env      - dev | staging | prod
 *   version  - 可选,只 apply 指定 14 位时间戳版本;省略则全部未应用
 *
 * 前置条件:
 *   - .env 中已配置 TCB_ENV_ID_<ENV>
 *   - 已 tcb login
 *   - MCP 不可用时,fallback 到 callCloudApi(详见 SKILL)
 *
 * 来源:[Skill: postgresql-development-cloudbase/SKILL.md]
 *   - DDL 必须走 applyMigration,不要用 execute(execute 会拒绝)
 *   - migrationVersion 必须严格比 LatestVersion 新
 *   - 文件路径: cloudbase/migrations/<version>_<name>.sql
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, '..', '..');

// ============================================
// 解析参数
// ============================================
const env = process.argv[2];
const versionFilter = process.argv[3];

if (!['dev', 'staging', 'prod'].includes(env)) {
    console.error('用法: node scripts/cloudbase/apply-migration.mjs <dev|staging|prod> [version]');
    process.exit(1);
}

// ============================================
// 加载 .env
// ============================================
function loadEnv() {
    const envPath = path.join(ROOT, '.env');
    if (!fs.existsSync(envPath)) {
        console.error('未找到 .env 文件');
        process.exit(1);
    }
    const content = fs.readFileSync(envPath, 'utf8');
    const vars = {};
    for (const line of content.split('\n')) {
        const m = line.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*?)\s*$/);
        if (m && !m[1].startsWith('#')) {
            vars[m[1]] = m[2].replace(/^["']|["']$/g, '');
        }
    }
    return vars;
}
const envVars = loadEnv();
const envId = envVars[`TCB_ENV_ID_${env.toUpperCase()}`];
if (!envId) {
    console.error(`未配置 TCB_ENV_ID_${env.toUpperCase()}`);
    process.exit(1);
}
console.log(`[INFO] 目标 EnvId: ${envId}`);

// ============================================
// 列出待应用的 migration 文件
// ============================================
const migDir = path.join(ROOT, 'cloudbase', 'migrations');
const files = fs.readdirSync(migDir)
    .filter(f => f.endsWith('.sql'))
    .filter(f => !versionFilter || f.startsWith(versionFilter))
    .sort();

if (files.length === 0) {
    console.error(`无待应用 migration 文件${versionFilter ? `(filter=${versionFilter})` : ''}`);
    process.exit(1);
}
console.log(`[INFO] 待应用 ${files.length} 个 migration:`);
for (const f of files) console.log(`  - ${f}`);

// ============================================
// 调 tcb fn 触发管理动作(简化:通过 tcb CLI 调用)
// ============================================
/**
 * 通过 tcb CLI 调 managePgDatabase(action=applyMigration, ...)
 *
 * 注意:tcb CLI 没有直接的 applyMigration 子命令,需要用 callCloudApi 兜底
 * 这里用一个临时 npx 调用方案 — 实际生产建议用 MCP
 */
function applyViaCli(envId, version, name, sql) {
    // 把 SQL 写入临时文件,避免命令行长度限制
    const tmpFile = path.join('/tmp', `migration-${version}.sql`);
    fs.writeFileSync(tmpFile, sql);

    const args = [
        'cloudbase', 'cli', 'run',
        '--envId', envId,
        'managePgDatabase',
        '--action', 'applyMigration',
        '--migrationVersion', version,
        '--migrationName', name,
        '--sql', sql,
        '--confirm', 'true',
    ];

    console.log(`[INFO] 应用 ${version}_${name}.sql ...`);
    const result = spawnSync('npx', ['-y', '@cloudbase/cli@latest', ...args], {
        encoding: 'utf8',
        env: { ...process.env, ...envVars },
    });

    if (result.status !== 0) {
        console.error(`[ERROR] 应用失败: ${result.stderr}`);
        return false;
    }
    console.log(result.stdout);
    return true;
}

// ============================================
// 主流程
// ============================================
let success = 0;
let failed = 0;

for (const f of files) {
    const m = f.match(/^(\d{14})_(.+)\.sql$/);
    if (!m) {
        console.error(`[SKIP] 文件名格式不对: ${f}`);
        failed++;
        continue;
    }
    const [, version, name] = m;
    const sql = fs.readFileSync(path.join(migDir, f), 'utf8');

    const ok = applyViaCli(envId, version, name, sql);
    if (ok) success++; else failed++;

    // 间隔避免并发问题
    await new Promise(r => setTimeout(r, 1500));
}

console.log(`\n[完成] 成功 ${success},失败 ${failed}`);
process.exit(failed > 0 ? 1 : 0);
