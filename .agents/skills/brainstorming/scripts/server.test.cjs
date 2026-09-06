// server.cjs Origin 校验（CSWSH 防护，issue #12）单元测试
//
// 以子进程方式启动 server.cjs（固定测试端口 + 临时 screen 目录），
// 用原始 HTTP upgrade 请求验证三类来源：
// 1. 无 Origin（curl/脚本等非浏览器客户端）     → 101 放行
// 2. Origin 与 Host 同源（本服务服务的页面）    → 101 放行
// 3. Origin 跨站（恶意网页）                    → 403 拒绝升级
//
// 运行:
//   node --test .agents/skills/brainstorming/scripts/server.test.cjs
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');

const PORT = 49752;
const HOST = '127.0.0.1';
const SERVER_PATH = path.join(__dirname, 'server.cjs');

let child;
let tmpDir;

function waitForServerInfo(timeoutMs = 8000) {
  const infoFile = path.join(tmpDir, '.server-info');
  const deadline = Date.now() + timeoutMs;
  return new Promise((resolve, reject) => {
    (function poll() {
      if (fs.existsSync(infoFile)) {
        try {
          resolve(JSON.parse(fs.readFileSync(infoFile, 'utf8')));
          return;
        } catch (e) {
          // 文件可能写了一半，继续轮询
        }
      }
      if (Date.now() > deadline) {
        reject(new Error('server-started 超时'));
        return;
      }
      setTimeout(poll, 100);
    })();
  });
}

// 发起一次原始 WebSocket upgrade 请求，返回 { status }（101 或 403）
function upgradeRequest({ origin } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({
      host: HOST,
      port: PORT,
      headers: {
        Connection: 'Upgrade',
        Upgrade: 'websocket',
        'Sec-WebSocket-Key': crypto.randomBytes(16).toString('base64'),
        'Sec-WebSocket-Version': '13',
        ...(origin ? { Origin: origin } : {}),
      },
    });
    req.on('upgrade', (res, socket) => {
      socket.destroy();
      resolve({ status: res.statusCode });
    });
    req.on('response', (res) => {
      res.resume();
      resolve({ status: res.statusCode });
    });
    req.on('error', (e) => reject(new Error(`upgrade 请求失败: ${e.message}`)));
    req.end();
  });
}

test.before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'brainstorm-origin-test-'));
  child = spawn(process.execPath, [SERVER_PATH], {
    env: {
      ...process.env,
      BRAINSTORM_PORT: String(PORT),
      BRAINSTORM_HOST: HOST,
      BRAINSTORM_DIR: tmpDir,
    },
    stdio: 'ignore',
  });
  await waitForServerInfo();
});

test.after(() => {
  if (child && child.exitCode === null) child.kill();
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('无 Origin 头（非浏览器客户端）放行 101', async () => {
  const { status } = await upgradeRequest();
  assert.strictEqual(status, 101);
});

test('Origin 与 Host 同源放行 101', async () => {
  const { status } = await upgradeRequest({ origin: `http://${HOST}:${PORT}` });
  assert.strictEqual(status, 101);
});

test('跨站 Origin（恶意网页）被 403 拒绝升级', async () => {
  const { status } = await upgradeRequest({ origin: 'http://evil.example:8080' });
  assert.strictEqual(status, 403);
});

test('非法 Origin 字符串被 403 拒绝升级', async () => {
  const { status } = await upgradeRequest({ origin: '::not-a-url::' });
  assert.strictEqual(status, 403);
});
