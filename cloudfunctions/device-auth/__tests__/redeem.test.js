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
