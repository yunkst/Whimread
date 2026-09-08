#!/usr/bin/env node
/**
 * 把 cloudfunctions/common 同步进每个函数目录(部署前准备)
 *
 * 背景:CloudBase 云端 installDependency 只能装 npm registry 的包,
 * `file:../common` 引用在云端无法解析(函数包里没有 ../ 目录),
 * 导致函数启动即崩("0 code exit unexpected")。
 *
 * 方案:把 common/*.js + package.json 复制到各函数的 common/ 子目录,
 * 函数代码用相对路径 require('./common/xxx')。
 *
 * 用法: node scripts/cloudbase/sync-common.mjs
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..', '..');
const CF_ROOT = path.join(ROOT, 'cloudfunctions');
const COMMON = path.join(CF_ROOT, 'common');

const FUNCTIONS = ['device-auth', 'app-release', 'llm-proxy'];
const COMMON_FILES = ['db.js', 'jwt.js', 'quota.js', 'errors.js', 'logger.js', 'tcb-admin.js', 'cos-admin.js', 'package.json'];

const commonPkg = JSON.parse(fs.readFileSync(path.join(COMMON, 'package.json'), 'utf8'));
const commonDeps = commonPkg.dependencies || {};

for (const fn of FUNCTIONS) {
    const destDir = path.join(CF_ROOT, fn, 'common');
    fs.mkdirSync(destDir, { recursive: true });
    for (const f of COMMON_FILES) {
        fs.copyFileSync(path.join(COMMON, f), path.join(destDir, f));
    }

    // 把 common 的运行时依赖合并进函数的 package.json(云端 installDependency 需要)
    const fnPkgPath = path.join(CF_ROOT, fn, 'package.json');
    const fnPkg = JSON.parse(fs.readFileSync(fnPkgPath, 'utf8'));
    fnPkg.dependencies = {
        ...(fnPkg.dependencies || {}),
        ...commonDeps,
    };
    delete fnPkg.dependencies['@whimread/cloudfunctions-common'];
    fs.writeFileSync(fnPkgPath, JSON.stringify(fnPkg, null, 2) + '\n');

    console.log(`[OK] ${fn}: common/ 同步完成 (${COMMON_FILES.length} 个文件, deps 合并)`);
}

console.log('\n[DONE] 同步完成,可以重新部署函数');
