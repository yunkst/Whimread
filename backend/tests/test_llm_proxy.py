#!/usr/bin/env python3
"""
LLM 代理端点测试。

上游通过替换 app.api.routes.llm_proxy.httpx.AsyncClient 为 FakeAsyncClient
模拟（流式/非流式/上游 5xx/连接失败），覆盖：
- 上游未配置 → 502
- 余额不足 → 402 + 审计落 insufficient_quota
- 非流式成功 → 200 + 按 usage 扣费（1000 token = 1 点）+ 流水/审计齐全
- 流式成功 → SSE 原样透传 + 末帧 usage 计费
- 流式无 usage → 按字符数估算
- 上游 500/断连 → 502 / 中断，不扣费
- 审计查询端点（X-API-TOKEN 保护）
"""

import asyncio
import json

import httpx
import pytest

from app.api.routes import llm_proxy as proxy_module
from app.config import settings
from tests.test_devices import _register

# conftest 的 autouse _override_get_db 与 client fixture 由根 conftest 提供


@pytest.fixture(autouse=True)
def _upstream_configured(monkeypatch):
    monkeypatch.setattr(settings, "llm_upstream_base_url", "https://upstream.test/v1")
    monkeypatch.setattr(settings, "llm_upstream_api_key", "sk-upstream")
    monkeypatch.setattr(settings, "llm_upstream_model", "test-model-1")


class _FakeResponse:
    def __init__(self, status_code=200, json_data=None, sse_chunks=None):
        self.status_code = status_code
        self._json = json_data
        self._sse = sse_chunks or []

    async def aiter_bytes(self):
        for chunk in self._sse:
            yield chunk

    async def aclose(self):
        pass

    def json(self):
        return self._json


class FakeAsyncClient:
    """可编程的 httpx.AsyncClient 替身。"""

    # 由测试设置
    blocking_response: _FakeResponse | None = None
    streaming_response: _FakeResponse | None = None
    raise_on_send: Exception | None = None
    last_request: httpx.Request | None = None

    def __init__(self, *args, **kwargs):
        pass

    def build_request(self, method, url, json=None, headers=None):
        httpx_request = httpx.Request(method, url, json=json, headers=headers)
        FakeAsyncClient.last_request = httpx_request
        return httpx_request

    async def send(self, request, stream=False):
        if FakeAsyncClient.raise_on_send is not None:
            raise FakeAsyncClient.raise_on_send
        if stream:
            assert FakeAsyncClient.streaming_response is not None, "未配置流式响应"
            return FakeAsyncClient.streaming_response
        assert FakeAsyncClient.blocking_response is not None, "未配置阻塞响应"
        return FakeAsyncClient.blocking_response

    async def aclose(self):
        pass


@pytest.fixture(autouse=True)
def _fake_httpx(monkeypatch):
    FakeAsyncClient.blocking_response = None
    FakeAsyncClient.streaming_response = None
    FakeAsyncClient.raise_on_send = None
    FakeAsyncClient.last_request = None
    monkeypatch.setattr(proxy_module.httpx, "AsyncClient", FakeAsyncClient)


@pytest.fixture(autouse=True)
def _attestation_pass(attestation_ok):
    """代理测试统一走 attestation 通过路径（verifier 已被 conftest 假实现替换）。"""


def _get_device_and_headers(client, android_id="device-with-quota-01"):
    register = _register(client, android_id=android_id)
    assert register.status_code == 200
    token = register.json()["token"]
    return register.json()["device_id"], {"Authorization": f"Bearer {token}"}


class TestGuards:
    def test_上游未配置_502(self, client, monkeypatch):
        monkeypatch.setattr(settings, "llm_upstream_base_url", "")
        _, headers = _get_device_and_headers(client)
        resp = client.post(
            "/v1/chat/completions",
            json={"messages": [{"role": "user", "content": "hi"}]},
            headers=headers,
        )
        assert resp.status_code == 502
        # 经全局异常处理器返回（扁平错误体）
        assert resp.json()["error"] == "LLM_UPSTREAM_NOT_CONFIGURED"

    def test_无token_401(self, client):
        resp = client.post("/v1/chat/completions", json={"messages": []})
        assert resp.status_code == 401

    def test_余额不足_402且审计落库(self, client, db_session):
        _, headers = _get_device_and_headers(client, android_id="broke-device-001")
        # 清空余额
        from app.models import Device, UsageLog

        device = db_session.query(Device).first()
        device.quota_balance = 0
        db_session.commit()

        resp = client.post(
            "/v1/chat/completions",
            json={"messages": [{"role": "user", "content": "hi"}]},
            headers=headers,
        )
        assert resp.status_code == 402
        assert resp.json()["error"]["code"] == "insufficient_quota"
        log = db_session.query(UsageLog).filter_by(device_id=device.id).first()
        assert log is not None
        assert log.status == "insufficient_quota"
        assert log.quota_cost == 0

    def test_模型被服务端覆写(self, client):
        _, headers = _get_device_and_headers(client, android_id="model-override-01")
        FakeAsyncClient.blocking_response = _FakeResponse(
            json_data={
                "choices": [{"message": {"role": "assistant", "content": "ok"}}],
                "usage": {"prompt_tokens": 100, "completion_tokens": 900},
            }
        )
        resp = client.post(
            "/v1/chat/completions",
            json={
                "model": "gpt-4-attacker-choice",
                "messages": [{"role": "user", "content": "hi"}],
            },
            headers=headers,
        )
        assert resp.status_code == 200
        sent_body = json.loads(FakeAsyncClient.last_request.content)
        assert sent_body["model"] == "test-model-1"


class TestBlocking:
    def test_成功_按usage扣费并审计(self, client, db_session):
        device_id, headers = _get_device_and_headers(client, android_id="blk-ok-0001")
        FakeAsyncClient.blocking_response = _FakeResponse(
            json_data={
                "choices": [{"message": {"role": "assistant", "content": "ok"}}],
                "usage": {"prompt_tokens": 1000, "completion_tokens": 1000},
            }
        )
        resp = client.post(
            "/v1/chat/completions",
            json={"messages": [{"role": "user", "content": "hi"}]},
            headers=headers,
        )
        assert resp.status_code == 200
        # 2000 tokens → 2 点
        from app.models import Device, QuotaTransaction, UsageLog

        device = db_session.get(Device, device_id)
        assert device.quota_balance == 498
        usage = db_session.query(UsageLog).filter_by(device_id=device_id).all()
        ok_logs = [u for u in usage if u.status == "ok"]
        assert len(ok_logs) == 1
        assert ok_logs[0].quota_cost == 2
        assert ok_logs[0].prompt_tokens == 1000
        txs = db_session.query(QuotaTransaction).filter_by(device_id=device_id).all()
        reasons = {t.reason for t in txs}
        assert reasons == {"free_grant", "usage"}

    def test_上游500_502不扣费(self, client, db_session):
        device_id, headers = _get_device_and_headers(client, android_id="blk-500-001")
        FakeAsyncClient.blocking_response = _FakeResponse(status_code=500, json_data={})
        resp = client.post(
            "/v1/chat/completions",
            json={"messages": [{"role": "user", "content": "hi"}]},
            headers=headers,
        )
        assert resp.status_code == 502
        from app.models import Device, UsageLog

        assert db_session.get(Device, device_id).quota_balance == 500
        log = db_session.query(UsageLog).filter_by(device_id=device_id).first()
        assert log.status == "upstream_error"
        assert log.quota_cost == 0

    def test_上游连接失败_502不扣费(self, client, db_session):
        device_id, headers = _get_device_and_headers(client, android_id="blk-conn-01")
        FakeAsyncClient.raise_on_send = httpx.ConnectError("connection refused")
        resp = client.post(
            "/v1/chat/completions",
            json={"messages": [{"role": "user", "content": "hi"}]},
            headers=headers,
        )
        assert resp.status_code == 502
        from app.models import Device

        assert db_session.get(Device, device_id).quota_balance == 500


class TestStreaming:
    def test_流式成功_usage末帧计费且SSE原样透传(self, client, db_session):
        device_id, headers = _get_device_and_headers(client, android_id="stream-ok-01")
        # 模拟上游 SSE：两个 content 帧 + usage-only 帧（choices 空数组）+ DONE
        sse = (
            b'data: {"choices":[{"delta":{"content":"\xe4\xbd\xa0\xe5\xa5\xbd"}}]}\n\n'
            b'data: {"choices":[{"delta":{"content":"world"}}]}\n\n'
            b'data: {"choices":[],"usage":{"prompt_tokens":600,"completion_tokens":400}}\n\n'
            b"data: [DONE]\n\n"
        )
        FakeAsyncClient.streaming_response = _FakeResponse(sse_chunks=[sse])

        with client.stream(
            "POST",
            "/v1/chat/completions",
            json={"messages": [{"role": "user", "content": "hi"}], "stream": True},
            headers=headers,
        ) as resp:
            assert resp.status_code == 200
            assert resp.headers["content-type"].startswith("text/event-stream")
            body = b"".join(resp.iter_raw())

        # 原样透传
        assert b'"delta":{"content":"world"}' in body
        assert b'"usage":{"prompt_tokens":600,"completion_tokens":400}' in body
        assert b"data: [DONE]" in body
        # 1000 tokens → 1 点
        from app.models import Device, UsageLog

        assert db_session.get(Device, device_id).quota_balance == 499
        usage = (
            db_session.query(UsageLog)
            .filter_by(device_id=device_id, status="ok")
            .first()
        )
        assert usage.quota_cost == 1
        assert usage.prompt_tokens == 600
        assert usage.completion_tokens == 400

    def test_流式无usage帧_按字符估算(self, client, db_session):
        device_id, headers = _get_device_and_headers(client, android_id="stream-no-usg")
        # 8000 个中文字符 → 8000/4 = 2000 token → 2 点
        big_text = "字" * 8000
        frames = (
            f"data: {json.dumps({'choices': [{'delta': {'content': big_text}}]})}\n\n"
        ).encode()
        FakeAsyncClient.streaming_response = _FakeResponse(
            sse_chunks=[frames, b"data: [DONE]\n\n"]
        )
        with client.stream(
            "POST",
            "/v1/chat/completions",
            json={"messages": [{"role": "user", "content": "hi"}], "stream": True},
            headers=headers,
        ) as resp:
            assert resp.status_code == 200
            b"".join(resp.iter_raw())

        from app.models import Device, UsageLog

        assert db_session.get(Device, device_id).quota_balance == 498
        usage = (
            db_session.query(UsageLog)
            .filter_by(device_id=device_id, status="ok")
            .first()
        )
        assert usage.quota_cost == 2
        assert usage.prompt_tokens is None

    def test_流式上游500_握手502不扣费(self, client, db_session):
        device_id, headers = _get_device_and_headers(client, android_id="stream-500-01")
        FakeAsyncClient.streaming_response = _FakeResponse(
            status_code=500, json_data={}
        )
        resp = client.post(
            "/v1/chat/completions",
            json={"messages": [{"role": "user", "content": "hi"}], "stream": True},
            headers=headers,
        )
        assert resp.status_code == 502
        from app.models import Device

        assert db_session.get(Device, device_id).quota_balance == 500


class TestConcurrency:
    def test_同设备并发第二请求_429(self, client):
        device_id, headers = _get_device_and_headers(client, android_id="busy-dev-001")
        # 人为持有该设备的锁，模拟在途请求（acquire 立即完成，无事件循环绑定）
        lock = proxy_module._lock_for(device_id)
        asyncio.run(lock.acquire())
        try:
            resp = client.post(
                "/v1/chat/completions",
                json={"messages": [{"role": "user", "content": "hi"}]},
                headers=headers,
            )
        finally:
            lock.release()
        assert resp.status_code == 429
        assert resp.json()["error"] == "DEVICE_BUSY"


class TestAdminAudit:
    def test_审计端点需管理token(self, client):
        resp = client.get("/api/admin/usage/1")
        assert resp.status_code == 401

    def test_审计端点返回用量与流水(self, client, db_session):
        device_id, headers = _get_device_and_headers(client, android_id="audit-dev-001")
        FakeAsyncClient.blocking_response = _FakeResponse(
            json_data={
                "choices": [{"message": {"role": "assistant", "content": "ok"}}],
                "usage": {"prompt_tokens": 500, "completion_tokens": 500},
            }
        )
        client.post(
            "/v1/chat/completions",
            json={"messages": [{"role": "user", "content": "hi"}]},
            headers=headers,
        )
        resp = client.get(
            f"/api/admin/usage/{device_id}",
            headers={"X-API-TOKEN": settings.api_token},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["device"]["id"] == device_id
        assert data["device"]["quota_balance"] == 499
        assert len(data["usage"]) == 1
        assert data["usage"][0]["status"] == "ok"
        assert {t["reason"] for t in data["quota_transactions"]} == {
            "free_grant",
            "usage",
        }

    def test_审计端点设备不存在_404(self, client):
        resp = client.get(
            "/api/admin/usage/99999",
            headers={"X-API-TOKEN": settings.api_token},
        )
        assert resp.status_code == 404
