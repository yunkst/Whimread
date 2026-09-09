#!/usr/bin/env node
/**
 * 发布新版 OCR 模型到 CloudBase Storage
 *
 * 用法:
 *   node scripts/cloudbase/publish-ocr-model.mjs <model_version>
 *   例:node scripts/cloudbase/publish-ocr-model.mjs 1.1.0
 *
 * 前置:
 *   - assets/models/inference.onnx + ppocrv6_dict.txt 存在(新版模型文件)
 *   - 已登录 CloudBase(tcb login 或 MCP 已绑定 env)
 *
 * 动作:
 *   1. 算两个文件的 SHA256
 *   2. 上传到 cos://<bucket>/ocr-models/<version>/
 *   3. 生成并上传 manifest.json(model_version / sha256 / size / url)
 *
 * 客户端下次启动时,比对本地 model_version + sha256,不一致自动重下。
 *
 * ⚠️ 模型极低频更新(训练才换),此脚本手动运行,不进 CI。
 */

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..', '..');
const MODEL_DIR = path.join(ROOT, 'assets', 'models');
const BUCKET = '7768-whimread-dev-d0gm4oi0z3099082d-1256733196';
const CDN = `https://${BUCKET}.tcb.qcloud.la`;

const version = process.argv[2];
if (!version || !/^\d+\.\d+\.\d+$/.test(version)) {
  console.error('用法: node scripts/cloudbase/publish-ocr-model.mjs <x.y.z>');
  console.error('例:  node scripts/cloudbase/publish-ocr-model.mjs 1.1.0');
  process.exit(1);
}

const modelFile = path.join(MODEL_DIR, 'inference.onnx');
const dictFile = path.join(MODEL_DIR, 'ppocrv6_dict.txt');
for (const f of [modelFile, dictFile]) {
  if (!fs.existsSync(f)) {
    console.error(`[ERROR] 文件不存在: ${f}`);
    process.exit(1);
  }
}

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}
function sizeOf(file) {
  return fs.statSync(file).size;
}

const modelSha = sha256(modelFile);
const dictSha = sha256(dictFile);
const modelSize = sizeOf(modelFile);
const dictSize = sizeOf(dictFile);

console.log(`[INFO] 版本: ${version}`);
console.log(`[INFO] model: ${modelSize} bytes  sha256=${modelSha}`);
console.log(`[INFO] dict:  ${dictSize} bytes  sha256=${dictSha}`);

// 生成 manifest
const manifest = {
  model_version: version,
  released_at: new Date().toISOString(),
  arch: {
    'arm64-v8a': {
      url: `${CDN}/ocr-models/${version}/inference.onnx`,
      sha256: modelSha,
      size: modelSize,
    },
    'armeabi-v7a': {
      url: `${CDN}/ocr-models/${version}/inference.onnx`,
      sha256: modelSha,
      size: modelSize,
    },
    x86_64: {
      url: `${CDN}/ocr-models/${version}/inference.onnx`,
      sha256: modelSha,
      size: modelSize,
    },
  },
  dict: {
    url: `${CDN}/ocr-models/${version}/ppocrv6_dict.txt`,
    sha256: dictSha,
    size: dictSize,
  },
};

const manifestPath = path.join(ROOT, 'ocr_model_manifest.json');
fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
console.log(`[OK] manifest 已生成: ${manifestPath}`);

// 上传指引(COS 上传走 MCP manageStorage,不走 tcb CLI —— bucket 是 CloudBase 托管)
console.log('');
console.log('===== 上传步骤(MCP manageStorage,3 次) =====');
console.log(`manageStorage(action="upload", cloudPath="ocr-models/${version}/inference.onnx", localPath="${modelFile}")`);
console.log(`manageStorage(action="upload", cloudPath="ocr-models/${version}/ppocrv6_dict.txt", localPath="${dictFile}")`);
console.log(`manageStorage(action="upload", cloudPath="ocr-models/${version}/manifest.json", localPath="${manifestPath}")`);
console.log('');
console.log('上传完成后验证:');
console.log(`  curl -s "${CDN}/ocr-models/${version}/manifest.json" | head -c 300`);
console.log('');
console.log('客户端下次启动自动检测到新 model_version 并重下。');
