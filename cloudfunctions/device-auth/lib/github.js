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
