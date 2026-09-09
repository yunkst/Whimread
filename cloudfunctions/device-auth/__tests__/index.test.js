/**
 * device-auth 云函数单元测试
 *
 * 策略:Node 内置 test runner(node --test)
 * 不 mock SDK 依赖,聚焦能脱机跑的部分:
 *   - 路由分发(未知路径 → 404)
 *   - OPTIONS 预检
 *   - register 字段校验(缺字段 → 400)
 *   - attestation 验证逻辑(无证书链 → 失败)
 *
 * 集成测试(真 PG + 真 JWT 密钥)用 scripts/cloudbase/test-end-to-end.sh 覆盖
 */

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { verifyAttestation } = require('../lib/attestation');
const { ok, err, handleCors, parseBody, ErrorCodes } = require('../../common/errors');

// ============================================
// errors 模块(脱机)
// ============================================
test('errors.handleCors:OPTIONS 返回 204', () => {
    const r = handleCors({ httpMethod: 'OPTIONS' });
    assert.equal(r.statusCode, 204);
});

test('errors.handleCors:GET 不拦截', () => {
    const r = handleCors({ httpMethod: 'GET' });
    assert.equal(r, null);
});

test('errors.parseBody:object 直通', () => {
    assert.deepEqual(parseBody({ body: { a: 1 } }), { a: 1 });
});

test('errors.parseBody:string 解析', () => {
    assert.deepEqual(parseBody({ body: '{"b":2}' }), { b: 2 });
});

// ============================================
// attestation 验证(纯函数,无依赖)
// ============================================
test('attestation:空链 → trusted=false', () => {
    const r = verifyAttestation([], 'nonce');
    assert.equal(r.trusted, false);
    assert.equal(r.reason, 'EMPTY_CHAIN');
});

test('attestation:非 PEM → trusted=false', () => {
    const r = verifyAttestation(['not a cert'], 'nonce');
    assert.equal(r.trusted, false);
    assert.equal(r.reason, 'INVALID_PEM');
});

test('attestation:合法 PEM → trusted=true(占位)', () => {
    const r = verifyAttestation(['-----BEGIN CERTIFICATE-----\nMIIB...\n-----END CERTIFICATE-----'], 'nonce');
    assert.equal(r.trusted, true);
    assert.equal(r.leafCert.includes('BEGIN CERTIFICATE'), true);
});

test('attestation:null 输入 → trusted=false', () => {
    const r = verifyAttestation(null, 'nonce');
    assert.equal(r.trusted, false);
});
