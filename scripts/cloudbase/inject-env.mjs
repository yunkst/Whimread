#!/usr/bin/env node
/**
 * 生成带敏感环境变量的 cloudbaserc.json(部署用,用完恢复)
 *
 * 用法: node scripts/cloudbase/inject-env.mjs
 * 流程:
 *   1. 备份当前 cloudbaserc.json
 *   2. 读 .env + PEM 密钥文件
 *   3. 把 envVariables 注入 cloudbaserc.json
 *   4. 用户跑 tcb config update fn ...
 *   5. restore 子命令恢复备份
 *
 * 子命令:
 *   (无参数)   注入敏感 env
 *   --restore  恢复干净配置
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..', '..');
const RC_FILE = path.join(ROOT, 'cloudbaserc.json');
const RC_BACKUP = path.join(ROOT, 'cloudbaserc.json.bak');
const ENV_FILE = path.join(ROOT, '.env');

function loadEnvFile() {
    if (!fs.existsSync(ENV_FILE)) return {};
    const vars = {};
    for (const line of fs.readFileSync(ENV_FILE, 'utf8').split('\n')) {
        const m = line.match(/^([A-Z_][A-Z0-9_]*)=(.*)$/);
        if (m) vars[m[1]] = m[2].trim();
    }
    return vars;
}

if (process.argv.includes('--restore')) {
    if (fs.existsSync(RC_BACKUP)) {
        fs.copyFileSync(RC_BACKUP, RC_FILE);
        fs.unlinkSync(RC_BACKUP);
        console.log('[OK] cloudbaserc.json 已恢复干净版本');
    } else {
        console.log('[SKIP] 无备份文件');
    }
    process.exit(0);
}

const envVars = loadEnvFile();
const envId = envVars.TCB_ENV_ID_DEV;
if (!envId) {
    console.error('[ERROR] .env 缺少 TCB_ENV_ID_DEV');
    process.exit(1);
}

function readPem(fileVar) {
    const rel = envVars[fileVar];
    if (!rel) return '';
    const abs = path.join(ROOT, rel.replace(/^\.\//, ''));
    if (!fs.existsSync(abs)) {
        console.error(`[ERROR] PEM 文件不存在: ${abs}`);
        process.exit(1);
    }
    return fs.readFileSync(abs, 'utf8');
}

const privateKey = readPem('DEVICE_JWT_PRIVATE_KEY_FILE');
const publicKey = readPem('DEVICE_JWT_PUBLIC_KEY_FILE');

if (!privateKey || !publicKey) {
    console.error('[ERROR] JWT 密钥为空');
    process.exit(1);
}

// 备份
fs.copyFileSync(RC_FILE, RC_BACKUP);

// 读取并注入
const rc = JSON.parse(fs.readFileSync(RC_FILE, 'utf8'));

const commonAuthEnv = {
    DEVICE_JWT_PUBLIC_KEY: publicKey,
    TCB_ENV_ID: envId,
};

for (const fn of rc.functions) {
    if (fn.name === 'device-auth') {
        fn.envVariables = {
            ...commonAuthEnv,
            DEVICE_JWT_PRIVATE_KEY: privateKey,
            TCB_ENV_ID: envId,
        };
    }
    if (fn.name === 'app-release') {
        fn.envVariables = {
            TCB_ENV_ID: envId,
        };
    }
    if (fn.name === 'llm-proxy') {
        fn.envVariables = {
            ...commonAuthEnv,
            LLM_BASE_URL: envVars.LLM_BASE_URL_DEV || envVars.LLM_BASE_URL || 'https://api.deepseek.com/v1',
            LLM_API_KEY: envVars.LLM_API_KEY || 'PLACEHOLDER_NOT_SET',
            LLM_DEFAULT_MODEL: envVars.LLM_DEFAULT_MODEL_DEV || envVars.LLM_DEFAULT_MODEL || 'deepseek-chat',
            TCB_ENV_ID: envId,
        };
    }
}

fs.writeFileSync(RC_FILE, JSON.stringify(rc, null, 2));
console.log('[OK] 敏感 env 已注入 cloudbaserc.json(device-auth + llm-proxy)');
console.log('[NEXT] 运行:');
console.log('  tcb config update fn device-auth');
console.log('  tcb config update fn llm-proxy');
console.log('  node scripts/cloudbase/inject-env.mjs --restore');
